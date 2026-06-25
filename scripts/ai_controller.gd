class_name AiController
extends Node

## AI 指挥官：负责指定阵营的索敌、决策、经济管理和生产调度。
## 通过 Unit 的公开命令接口下达指令，通过 Building 的接口管理生产和采矿。
## 通用战术行为（环绕/保持距离/追逐/自动技能）由 Unit 统一处理，不分阵营。

enum TargetPref { SMALL_FIRST, BIG_FIRST, THREAT_FOCUS }

var all_units: Array[Unit] = []
var _my_team: String = ""
var _target_pref: TargetPref = TargetPref.SMALL_FIRST
var _decision_timer: float = 0.0
const DECISION_INTERVAL: float = 1.0

# ----- 集火 & 规避配置 -----
## 残血规避阈值（HP 低于此比例时撤退）
const EVADE_HULL_THRESHOLD := 0.3
## 撤退安全距离（px）
const EVADE_SAFE_DISTANCE := 800.0
## 追踪各单位是否正在撤退
var _retreating_units: Dictionary = {}

# ----- 经济 & 生产系统 -----
var _buildings: Array = []
var _main_node = null
var _economy_timer: float = 0.0
const ECONOMY_INTERVAL: float = 3.0       # 每3秒评估经济
var _production_timer: float = 0.0
const PRODUCTION_INTERVAL: float = 8.0    # 每8秒决定生产

## 各船型造价快捷引用
const _COST := {
	Unit.ShipClass.DRONE: GameConfig.SHIPYARD_COST_DRONE,
	Unit.ShipClass.FRIGATE: GameConfig.SHIPYARD_COST_FRIGATE,
	Unit.ShipClass.DESTROYER: GameConfig.SHIPYARD_COST_DESTROYER,
	Unit.ShipClass.CRUISER: GameConfig.SHIPYARD_COST_CRUISER,
	Unit.ShipClass.BATTLESHIP: GameConfig.SHIPYARD_COST_BATTLESHIP,
	Unit.ShipClass.MINER: GameConfig.SHIPYARD_COST_MINER,
}
const _BUILD_TIME := {
	Unit.ShipClass.DRONE: GameConfig.SHIPYARD_TIME_DRONE,
	Unit.ShipClass.FRIGATE: GameConfig.SHIPYARD_TIME_FRIGATE,
	Unit.ShipClass.DESTROYER: GameConfig.SHIPYARD_TIME_DESTROYER,
	Unit.ShipClass.CRUISER: GameConfig.SHIPYARD_TIME_CRUISER,
	Unit.ShipClass.BATTLESHIP: GameConfig.SHIPYARD_TIME_BATTLESHIP,
	Unit.ShipClass.MINER: GameConfig.SHIPYARD_TIME_MINER,
}


func init(units: Array[Unit], team: String, pref: TargetPref) -> void:
	all_units = units
	_my_team = team
	_target_pref = pref


## 扩展初始化：传入建筑列表和 Main 节点引用，用于经济和生产决策
func init_extended(buildings: Array, main_node) -> void:
	_buildings = buildings
	_main_node = main_node


func process_ai(delta: float) -> void:
	_decision_timer += delta
	if _decision_timer < DECISION_INTERVAL:
		return
	_decision_timer = 0.0

	# 清理已死亡的撤退标记
	var to_remove: Array = []
	for u in _retreating_units:
		if not is_instance_valid(u) or u.hull <= 0:
			to_remove.append(u)
	for u in to_remove:
		_retreating_units.erase(u)

	# 评估战场：根据策略选择目标阵营
	var focus_team = _evaluate_battlefield()

	# 为全队选择集火目标（高威胁 + 残血优先）
	var focus_target = _select_focus_target(focus_team)

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != _my_team:
			continue

		# Step 0: 残血规避 — 血量过低时撤退
		if _try_evade(unit):
			continue

		# 1. 清理已死亡的目标引用
		_clean_dead_targets(unit)

		# 2. 无人机 AI：继承母舰目标 / 环绕母舰
		if unit.home_battleship != null and is_instance_valid(unit.home_battleship):
			_process_drone_ai(unit)

		# 3. 采矿船 AI：主线已处理采矿状态机，但若母矿场被毁则需重分配
		if unit._is_miner:
			_manage_miner_unit(unit)
			continue

		# 4. 索敌（优先分配集火目标，其次按优先级选择）
		if unit._current_target == null:
			# 单位正在移动中（_is_moving=true 且无目标）时不打断
			if unit._is_moving:
				continue
			if focus_target != null and is_instance_valid(focus_target) and focus_target.hull > 0:
				unit.attack_target(focus_target)
			else:
				_select_target(unit, focus_team)

	# ---- 经济管理（间隔执行）----
	_economy_timer += DECISION_INTERVAL
	if _economy_timer >= ECONOMY_INTERVAL:
		_economy_timer = 0.0
		_manage_mining_fleet()

	# ---- 生产决策（间隔执行）----
	_production_timer += DECISION_INTERVAL
	if _production_timer >= PRODUCTION_INTERVAL:
		_production_timer = 0.0
		_make_production_decision()


# ----- 战场评估 -----

## 根据策略选择目标阵营
func _evaluate_battlefield() -> String:
	var score: Dictionary = {}  # team_name → score

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == _my_team:
			continue

		if _target_pref == TargetPref.THREAT_FOCUS:
			# 按总威胁度评估
			var total = score.get(unit.team, 0)
			score[unit.team] = total + unit.threat_level
		else:
			# 默认按总 HP 评估
			var total = score.get(unit.team, 0.0)
			score[unit.team] = total + unit.shield + unit.hull

	var best_team := ""
	var best_score := -INF
	for team in score:
		if score[team] > best_score:
			best_score = score[team]
			best_team = team

	return best_team


# ----- 集火目标选择 -----

## 从目标阵营中选择全队集火目标
## 评分 = 威胁度 × 10 + 已损失血量（优先集火高威胁 + 残血目标）
func _select_focus_target(target_team: String) -> Unit:
	var best: Unit = null
	var best_score := -INF
	for other in all_units:
		if not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team != target_team:
			continue
		var hp_lost = (other.max_hull + other.max_shield) - (other.hull + other.shield)
		var score = other.threat_level * 10.0 + hp_lost
		if score > best_score:
			best_score = score
			best = other
	return best


# ----- 目标管理 -----

func _clean_dead_targets(unit) -> void:
	if is_instance_valid(unit._explicit_attack_target) and unit._explicit_attack_target.hull <= 0:
		unit._explicit_attack_target = null
	if is_instance_valid(unit._current_target) and unit._current_target.hull <= 0:
		unit._current_target = null
		unit._advance_command_queue()


func _process_drone_ai(unit) -> void:
	var mothership = unit.home_battleship
	if not is_instance_valid(mothership) or mothership.hull <= 0:
		return

	if is_instance_valid(mothership._current_target) and mothership._current_target.hull > 0:
		var orbiting_home = (unit._orbit_target_unit == mothership)
		# 无人机正在执行玩家移动指令时不继承母舰目标
		if (unit._current_target == null or orbiting_home) and not unit._is_moving:
			unit._current_target = mothership._current_target
			unit._is_orbit = false
	elif unit._current_target == null and not unit._is_moving and not unit._is_orbit:
		unit.orbit_target(mothership)


# ----- 残血规避 -----

## 残血单位撤退：血量低于阈值时远离敌人，向友军靠拢
## 若连续 10 秒未受攻击则自动终止逃跑状态
func _try_evade(unit) -> bool:
	var hp_pct = unit.hull / unit.max_hull

	# ---- 脱离战斗检测：10 秒未受伤 → 终止逃跑 ----
	if unit._last_damage_timer >= 10.0:
		if _retreating_units.get(unit, false):
			_retreating_units[unit] = false
		return false

	if hp_pct > EVADE_HULL_THRESHOLD:
		if _retreating_units.get(unit, false):
			_retreating_units[unit] = false
		return false

	_retreating_units[unit] = true
	unit._current_target = null
	unit._explicit_attack_target = null

	# ---- 计算撤退方向 ----
	# 远离最近敌人
	var nearest = unit.find_nearest_enemy()
	var retreat_dir: Vector2
	if nearest != null:
		retreat_dir = (unit.global_position - nearest.global_position).normalized()
	else:
		# 无敌人时向地图中心方向撤退
		var to_center = GameConfig.MAP_CENTER - unit.global_position
		retreat_dir = to_center.normalized() if to_center.length_squared() > 0 else Vector2.UP

	# 向友军方向靠拢
	var friendly_center = Vector2.ZERO
	var count = 0
	for u in all_units:
		if is_instance_valid(u) and u.hull > 0 and u.team == unit.team and u != unit:
			friendly_center += u.global_position
			count += 1
	if count > 0:
		friendly_center /= count
		var to_friendly = (friendly_center - unit.global_position).normalized()
		retreat_dir = (retreat_dir + to_friendly * 0.5).normalized()

	# ---- 确保撤退目标在地图边界内 ----
	var retreat_pos = unit.global_position + retreat_dir * EVADE_SAFE_DISTANCE
	var dist_from_center = retreat_pos.distance_to(GameConfig.MAP_CENTER)
	if dist_from_center > GameConfig.MAP_RADIUS * 0.9:
		# 撤退目标超出安全区域 → 向地图中心方向撤退
		var to_center = GameConfig.MAP_CENTER - unit.global_position
		var safe_dir = to_center.normalized() if to_center.length_squared() > 0 else Vector2.DOWN
		retreat_pos = unit.global_position + safe_dir * EVADE_SAFE_DISTANCE

	unit.move_to(retreat_pos)
	return true


## 从指定阵营中按船型优先级选择目标，若无目标则尝试其他敌方阵营
func _select_target(unit, focus_team: String) -> void:
	var has_offensive = _get_approach_range(unit) > 0
	if not has_offensive:
		if not unit._is_orbit or not is_instance_valid(unit._orbit_target_unit):
			var largest = _find_largest_friendly(unit)
			if largest != null and largest != unit:
				unit.orbit_target(largest)
		return

	var enemy = _find_best_target(unit, focus_team)
	if enemy != null:
		unit.attack_target(enemy)
		return

	# focus_team 全灭 → 从 all_units 收集剩余敌方阵营
	var enemy_teams: Array = []
	for u in all_units:
		if is_instance_valid(u) and u.hull > 0 and u.team != _my_team and u.team != focus_team:
			if not enemy_teams.has(u.team):
				enemy_teams.append(u.team)
	for team in enemy_teams:
		enemy = _find_best_target(unit, team)
		if enemy != null:
			unit.attack_target(enemy)
			return


## 在指定阵营中按策略选择最佳目标
func _find_best_target(unit, target_team: String) -> Unit:
	var best: Unit = null
	var best_val := -INF if _target_pref == TargetPref.THREAT_FOCUS else INF

	for other in all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team != target_team:
			continue

		if _target_pref == TargetPref.THREAT_FOCUS:
			# 选威胁度最高的
			if other.threat_level > best_val:
				best_val = other.threat_level
				best = other
			elif other.threat_level == best_val and best != null:
				var d1 = unit.global_position.distance_to(other.global_position)
				var d2 = unit.global_position.distance_to(best.global_position)
				if d1 < d2:
					best = other
		else:
			# 按船型优先级选目标
			var prio = _ship_class_priority(other.class_type)
			if prio < best_val:
				best_val = prio
				best = other
			elif prio == best_val and best != null:
				var d1 = unit.global_position.distance_to(other.global_position)
				var d2 = unit.global_position.distance_to(best.global_position)
				if d1 < d2:
					best = other

	return best


## 根据策略返回船型优先级（越小越优先）
func _ship_class_priority(sc: Unit.ShipClass) -> int:
	match _target_pref:
		TargetPref.SMALL_FIRST:
			match sc:
				Unit.ShipClass.DRONE: return 0
				Unit.ShipClass.FRIGATE: return 1
				Unit.ShipClass.DESTROYER: return 2
				Unit.ShipClass.CRUISER: return 3
				Unit.ShipClass.BATTLESHIP: return 4
		TargetPref.BIG_FIRST:
			match sc:
				Unit.ShipClass.BATTLESHIP: return 0
				Unit.ShipClass.CRUISER: return 1
				Unit.ShipClass.DESTROYER: return 2
				Unit.ShipClass.FRIGATE: return 3
				Unit.ShipClass.DRONE: return 4
	return 99


func _find_largest_friendly(me: Unit) -> Unit:
	var best: Unit = null
	var best_tier := -1
	for u in all_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		if u.team != me.team or u == me:
			continue
		var t = Unit._ship_class_tier(u.class_type)
		if t > best_tier:
			best_tier = t
			best = u
	return best


# ----- 工具函数 -----

static func _get_approach_range(unit) -> float:
	var min_r := INF
	for w in unit._slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.attack_range * unit._weapon_range_mult)
	return min_r if min_r < INF else 0.0


# =============================================================================
# AI 经济系统：采矿管理 + 生产决策
# =============================================================================

## 管理单艘采矿船：当母矿场被毁时重新分配
func _manage_miner_unit(unit: Unit) -> void:
	if is_instance_valid(unit._home_mine):
		return  # 矿场还在，采矿状态机正常工作
	# 母矿场被毁 → 找己方其他矿场
	var new_home = _find_my_mine()
	if new_home != null:
		unit.set_as_miner(new_home)


## 管理采矿舰队：确保采矿船数量合理
func _manage_mining_fleet() -> void:
	var my_miners: Array[Unit] = []
	var my_shipyards: Array = []

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0 or unit.team != _my_team:
			continue
		if unit._is_miner:
			my_miners.append(unit)

	for b in _buildings:
		if not is_instance_valid(b) or b.team != _my_team:
			continue
		if b.building_type == 1:  # BuildingType.SHIPYARD
			my_shipyards.append(b)

	# 计算矿物场数量
	var mineral_fields = _get_mineral_fields()
	var field_count = mineral_fields.size()
	if field_count == 0:
		return

	# 理想采矿船数：每片矿 2 艘，最少 2 艘
	var ideal_miners = max(2, field_count * 2)

	# 如果采矿船不足且有余钱，生产采矿船
	if my_miners.size() < ideal_miners and my_shipyards.size() > 0:
		var minerals = _get_team_minerals()
		var miner_cost = GameConfig.SHIPYARD_COST_MINER
		# 至少保留 100 矿物用于战斗单位生产
		if minerals >= miner_cost + 100:
			for yard in my_shipyards:
				if not is_instance_valid(yard):
					continue
				if yard._production_queue.size() < 3 and minerals >= miner_cost:
					if yard.enqueue_ship(Unit.ShipClass.MINER, miner_cost, GameConfig.SHIPYARD_TIME_MINER):
						minerals -= miner_cost


## 生产决策：根据战场形势和矿物储备决定生产什么船
func _make_production_decision() -> void:
	var minerals = _get_team_minerals()
	if minerals < 50:
		return  # 太穷了，等采矿

	# ---- 统计敌我力量 ----
	var my_forces: Dictionary = {}  # ShipClass → count
	var enemy_forces: Dictionary = {}
	var my_power := 0.0
	var enemy_power := 0.0

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		var weight = pow(2, max(0, Unit._ship_class_tier(unit.class_type)))
		if unit.team == _my_team:
			my_forces[unit.class_type] = my_forces.get(unit.class_type, 0) + 1
			my_power += weight
		else:
			enemy_forces[unit.class_type] = enemy_forces.get(unit.class_type, 0) + 1
			enemy_power += weight

	# 力量比（>1 我方优势）
	var ratio = my_power / max(enemy_power, 1.0)

	# ---- 获取己方船坞 ----
	var my_shipyards: Array = []
	for b in _buildings:
		if is_instance_valid(b) and b.team == _my_team and b.building_type == 1:  # SHIPYARD
			my_shipyards.append(b)
	if my_shipyards.size() == 0:
		return

	# ---- 根据力量比和矿物储备选择造舰方案 ----
	var ship_type: int  # Unit.ShipClass
	var cost: int
	var build_time: float

	if ratio < 0.6:
		# 🚨 大劣势：爆最便宜的船（无人机/护卫舰）防守
		if minerals >= GameConfig.SHIPYARD_COST_FRIGATE * 2:
			ship_type = Unit.ShipClass.FRIGATE
		else:
			ship_type = Unit.ShipClass.DRONE

	elif ratio < 0.9:
		# ⚠️ 小劣势：混编护卫舰+驱逐舰
		var roll = randi() % 3
		ship_type = Unit.ShipClass.FRIGATE if roll < 2 else Unit.ShipClass.DESTROYER

	elif ratio < 1.5:
		# ➡️ 均势：均衡生产驱逐舰+巡洋舰
		if minerals >= GameConfig.SHIPYARD_COST_CRUISER * 2:
			ship_type = Unit.ShipClass.CRUISER
		else:
			ship_type = Unit.ShipClass.DESTROYER

	elif ratio < 2.5:
		# ✅ 优势：出巡洋舰+少量战列舰
		if minerals >= GameConfig.SHIPYARD_COST_BATTLESHIP * 3:
			ship_type = Unit.ShipClass.BATTLESHIP
		else:
			ship_type = Unit.ShipClass.CRUISER

	else:
		# 👑 大优势：暴战列舰碾压
		if minerals >= GameConfig.SHIPYARD_COST_BATTLESHIP:
			ship_type = Unit.ShipClass.BATTLESHIP
		elif minerals >= GameConfig.SHIPYARD_COST_CRUISER:
			ship_type = Unit.ShipClass.CRUISER
		else:
			ship_type = Unit.ShipClass.DESTROYER

	cost = _COST.get(ship_type, 100)
	build_time = _BUILD_TIME.get(ship_type, 5.0)

	# 找队列最短的船坞加入生产
	var best_yard = null
	var min_queue = 999
	for yard in my_shipyards:
		if not is_instance_valid(yard):
			continue
		var qsize = yard._production_queue.size()
		if qsize < min_queue:
			min_queue = qsize
			best_yard = yard

	if best_yard != null:
		best_yard.enqueue_ship(ship_type, cost, build_time)


## 获取己方第一个矿场
func _find_my_mine():
	for b in _buildings:
		if is_instance_valid(b) and b.team == _my_team and b.building_type == 0:  # BuildingType.MINE
			return b
	return null


## 查询阵营矿物储量
func _get_team_minerals() -> float:
	if _main_node != null and _main_node.has_method("get_team_minerals"):
		return _main_node.get_team_minerals(_my_team)
	return 0.0


## 获取所有矿物场
func _get_mineral_fields() -> Array:
	var fields = get_tree().get_nodes_in_group("mineral_fields")
	var result: Array = []
	for f in fields:
		if is_instance_valid(f):
			result.append(f)
	return result

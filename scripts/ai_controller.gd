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

# ----- 偷袭基地策略 -----
## 偷袭编队中的单位
var _sneak_attack_units: Dictionary = {}
## 偷袭目标位置（敌方建筑群中心）
var _sneak_attack_target: Vector2 = Vector2.ZERO
## 偷袭是否激活
var _sneak_attack_active: bool = false
var _sneak_attack_timer: float = 0.0
const SNEAK_ATTACK_INTERVAL: float = 15.0

# ----- 回防基地策略 -----
## 回防中的单位 → 正在防守的建筑
var _defense_assignments: Dictionary = {}
## 上次检查时建筑的结构值，用于检测是否被攻击
var _building_prev_hull: Dictionary = {}
var _defense_timer: float = 0.0
const DEFENSE_INTERVAL: float = 3.0

# ----- 偷袭矿区策略 -----
## 骚扰矿区编队中的单位
var _raid_mineral_units: Dictionary = {}
## 骚扰目标位置
var _raid_mineral_target: Vector2 = Vector2.ZERO
## 骚扰是否激活
var _raid_mineral_active: bool = false
var _raid_mineral_timer: float = 0.0
const RAID_MINERAL_INTERVAL: float = 20.0

# ----- 经济 & 生产系统 -----
var _buildings: Array = []
var _main_node = null
var _economy_timer: float = 0.0
const ECONOMY_INTERVAL: float = 3.0       # 每3秒评估经济
var _production_timer: float = 0.0
const PRODUCTION_INTERVAL: float = 8.0    # 每8秒决定生产
var _building_timer: float = 0.0
const BUILDING_INTERVAL: float = 20.0    # 每20秒评估建筑需求

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

	# ---- 偷袭基地评估（间隔执行）----
	_sneak_attack_timer += DECISION_INTERVAL
	if _sneak_attack_timer >= SNEAK_ATTACK_INTERVAL:
		_sneak_attack_timer = 0.0
		_evaluate_sneak_attack()

	# ---- 偷袭矿区评估（间隔执行）----
	_raid_mineral_timer += DECISION_INTERVAL
	if _raid_mineral_timer >= RAID_MINERAL_INTERVAL:
		_raid_mineral_timer = 0.0
		_evaluate_mineral_raid()

	# ---- 回防基地评估（间隔执行）----
	_defense_timer += DECISION_INTERVAL
	if _defense_timer >= DEFENSE_INTERVAL:
		_defense_timer = 0.0
		_evaluate_defense()

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

		# 4a. 偷袭编队：有目标时直接攻击敌方建筑
		if _sneak_attack_units.has(unit):
			_handle_sneak_attacker(unit)
			continue

		# 4b. 骚扰矿区编队：攻击敌方矿场和矿物场
		if _raid_mineral_units.has(unit):
			_handle_mineral_raider(unit)
			continue

		# 4c. 回防单位：有防守任务时防守指定建筑
		if _defense_assignments.has(unit):
			_handle_defender(unit)
			continue

		# 5. 索敌（优先分配集火目标，其次按优先级选择）
		if unit._current_target == null:
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

	# ---- 建筑建造决策（间隔执行）----
	_building_timer += DECISION_INTERVAL
	if _building_timer >= BUILDING_INTERVAL:
		_building_timer = 0.0
		_make_building_decision()


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
		# 无人机正在移动中时不继承母舰目标
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
	# 矿船逃跑时重置采矿状态并释放名额，10秒后自动恢复采矿
	if unit._is_miner:
		unit._miner_state = unit.MinerState.IDLE
		unit._unregister_from_field()

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


# =============================================================================
# AI 建筑系统：建造决策
# =============================================================================

## 建造决策：评估是否需要建造新建筑
func _make_building_decision() -> void:
	var minerals = _get_team_minerals()

	# 统计当前己方建筑数量
	var mine_count := 0
	var shipyard_count := 0
	for b in _buildings:
		if not is_instance_valid(b) or b.team != _my_team:
			continue
		if b.hull <= 0:
			continue
		match b.building_type:
			0: mine_count += 1   # MINE
			1: shipyard_count += 1  # SHIPYARD

	# 统计可用矿物场数量
	var mineral_fields = _get_mineral_fields()
	var field_count = mineral_fields.size()

	# ---- 矿场需求：每个矿物场配一个矿场，至少 1 个，最多 4 个 ----
	var target_mines = mini(max(1, field_count), 4)
	if mine_count < target_mines and minerals >= GameConfig.DEPLOY_COST_MINE:
		var pos = _pick_mine_position(mineral_fields)
		if pos != null:
			_execute_ai_deploy(0, GameConfig.DEPLOY_COST_MINE, pos)
			return

	# ---- 船坞需求：根据力量比决定，最多 3 个 ----
	var target_shipyards = 2  # 基础 2 个
	if minerals > 2000:
		target_shipyards = 3
	elif minerals < 500:
		target_shipyards = 1
	if shipyard_count < target_shipyards and minerals >= GameConfig.DEPLOY_COST_SHIPYARD:
		var pos = _pick_shipyard_position()
		if pos != null:
			_execute_ai_deploy(1, GameConfig.DEPLOY_COST_SHIPYARD, pos)


## 选择矿场建造位置：在最近的矿物场附近
func _pick_mine_position(mineral_fields: Array) -> Vector2:
	if mineral_fields.size() == 0:
		return _get_base_center()

	# 找最近的矿物场
	var nearest_field = null
	var nearest_dist := INF
	var base_pos = _get_base_center()

	for f in mineral_fields:
		if not is_instance_valid(f):
			continue
		var dist = base_pos.distance_to(f.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_field = f

	if nearest_field != null:
		# 在矿物场和基地之间放置矿场
		var dir_to_base = (base_pos - nearest_field.global_position).normalized()
		return nearest_field.global_position + dir_to_base * 150.0

	return base_pos


## 选择船坞建造位置：在现有建筑群附近扩展
func _pick_shipyard_position() -> Vector2:
	var base_pos = _get_base_center()
	# 绕基地随机偏移
	var angle = randf() * TAU
	var dist = 300.0 + randi() % 300
	return base_pos + Vector2(cos(angle), sin(angle)) * dist


## 计算己方建筑群中心点
func _get_base_center() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for b in _buildings:
		if is_instance_valid(b) and b.team == _my_team and b.hull > 0:
			sum += b.global_position
			count += 1
	if count > 0:
		return sum / count
	return GameConfig.MAP_CENTER


## AI 直接执行部署建筑（消耗矿物、生成建筑）
func _execute_ai_deploy(building_type: int, cost: int, pos: Vector2) -> void:
	if _main_node == null:
		return
	if _main_node.get_team_minerals(_my_team) < cost:
		return
	if not _main_node.spend_team_minerals(_my_team, cost):
		return
	if _main_node.has_method("spawn_deploy_building"):
		_main_node.spawn_deploy_building(_my_team, building_type, pos)


# =============================================================================
# AI 偷袭基地策略
# =============================================================================

## 获取敌方建筑列表
func _get_enemy_buildings() -> Array:
	var result: Array = []
	for b in Building.all_buildings:
		if is_instance_valid(b) and b.hull > 0 and b.team != _my_team:
			result.append(b)
	return result


## 获取敌方建筑群中心
func _calc_building_center(buildings: Array) -> Vector2:
	if buildings.size() == 0:
		return GameConfig.MAP_CENTER
	var sum := Vector2.ZERO
	for b in buildings:
		if is_instance_valid(b):
			sum += b.global_position
	return sum / buildings.size()


## 评估并执行偷袭基地策略
## 力量比 >= 1.5 时，抽调 30% 的战斗单位组成偷袭编队直扑敌方建筑群
func _evaluate_sneak_attack() -> void:
	# 清理已死亡的偷袭单位
	var to_remove: Array = []
	for u in _sneak_attack_units:
		if not is_instance_valid(u) or u.hull <= 0:
			to_remove.append(u)
	for u in to_remove:
		_sneak_attack_units.erase(u)

	var enemy_buildings = _get_enemy_buildings()
	if enemy_buildings.size() == 0:
		# 敌方无建筑 → 停止偷袭
		if _sneak_attack_active:
			_clear_sneak_attack()
		return

	# 计算力量比
	var my_power := 0.0
	var enemy_power := 0.0
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit._is_miner:
			continue
		var weight = pow(2, max(0, Unit._ship_class_tier(unit.class_type)))
		if unit.team == _my_team:
			my_power += weight
		else:
			enemy_power += weight

	var ratio = my_power / max(enemy_power, 1.0)

	if ratio >= 1.5:
		# ✅ 优势：执行偷袭
		var current_count = _sneak_attack_units.size()
		# 计算理想的偷袭编队大小（总战斗单位的 30%，最少 3 艘）
		var total_combat := 0
		for unit in all_units:
			if is_instance_valid(unit) and unit.hull > 0 and unit.team == _my_team and not unit._is_miner:
				total_combat += 1
		var ideal_count = max(3, int(total_combat * 0.3))

		if current_count < ideal_count:
			_assign_sneak_attack_units(ideal_count - current_count)

		# 更新偷袭目标位置
		_sneak_attack_target = _calc_building_center(enemy_buildings)
		_sneak_attack_active = true
	else:
		# ❌ 不占优势 → 取消偷袭，单位回归正常战斗
		if _sneak_attack_active:
			_clear_sneak_attack()


## 从战斗单位中抽调指定数量的单位加入偷袭编队
func _assign_sneak_attack_units(count: int) -> void:
	# 收集可用的战斗单位（非偷袭、非回防、非撤退）
	var candidates: Array[Unit] = []
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != _my_team:
			continue
		if unit._is_miner:
			continue
		if _sneak_attack_units.has(unit):
			continue
		if _defense_assignments.has(unit):
			continue
		if _retreating_units.get(unit, false):
			continue
		# 跳过无人机（需跟随母舰）
		if unit.home_battleship != null and is_instance_valid(unit.home_battleship):
			continue
		candidates.append(unit)

	# 按速度排序（选快的船作为偷袭舰队：护卫舰 > 驱逐 > 巡洋 > 战列）
	candidates.sort_custom(func(a, b):
		return Unit._ship_class_tier(a.class_type) < Unit._ship_class_tier(b.class_type))

	var assigned = 0
	for unit in candidates:
		if assigned >= count:
			break
		# 跳过战列舰（速度慢，不适合偷袭）
		if unit.class_type == Unit.ShipClass.BATTLESHIP:
			continue
		_sneak_attack_units[unit] = true
		assigned += 1


## 控制单艘偷袭单位：向敌方建筑群移动，抵达后攻击建筑
func _handle_sneak_attacker(unit: Unit) -> void:
	# 残血时停止偷袭，交由规避逻辑处理
	if unit.hull / unit.max_hull < EVADE_HULL_THRESHOLD:
		_sneak_attack_units.erase(unit)
		return

	# 清理死亡目标
	_clean_dead_targets(unit)

	# 如果已有目标且是建筑，继续攻击
	if is_instance_valid(unit._current_target) and unit._current_target.hull > 0:
		var target = unit._current_target
		if target is Building or (target.has_method("is_dead") and not target.is_dead()):
			return  # 正在攻击建筑，保持

	# 寻找最近的敌方建筑
	var nearest_building: Building = null
	var nearest_dist := INF
	for b in Building.all_buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		if b.team == _my_team:
			continue
		var dist = unit.global_position.distance_to(b.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_building = b

	if nearest_building != null:
		# 在射程内则直接攻击建筑
		var approach_range = _get_approach_range(unit)
		if approach_range > 0 and nearest_dist <= approach_range * 1.2:
			unit.attack_target(nearest_building)
		else:
			# 未到达：向目标建筑移动（攻击移动模式）
			unit.attack_area(nearest_building.global_position, approach_range * 2.0)
	else:
		# 无建筑目标 → 向敌方建筑群中心移动
		unit.move_to(_sneak_attack_target)


## 取消偷袭，清空偷袭编队
func _clear_sneak_attack() -> void:
	_sneak_attack_units.clear()
	_sneak_attack_active = false


# =============================================================================
# AI 偷袭矿区策略（骚扰敌方经济）
# =============================================================================

## 获取敌方矿场列表
func _get_enemy_mines() -> Array:
	var result: Array = []
	for b in Building.all_buildings:
		if is_instance_valid(b) and b.hull > 0 and b.team != _my_team \
			and b.building_type == Building.BuildingType.MINE:
			result.append(b)
	return result


## 获取敌方采矿船列表
func _get_enemy_miners() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == _my_team:
			continue
		if unit._is_miner:
			result.append(unit)
	return result


## 计算敌方矿区中心（优先选矿场，其次采矿船位置）
func _calc_mineral_raid_target() -> Vector2:
	var mines = _get_enemy_mines()
	if mines.size() > 0:
		return _calc_building_center(mines)

	var miners = _get_enemy_miners()
	if miners.size() > 0:
		var sum := Vector2.ZERO
		for m in miners:
			if is_instance_valid(m):
				sum += m.global_position
		return sum / miners.size()

	return GameConfig.MAP_CENTER


## 评估并执行偷袭矿区策略
## 力量比 >= 1.0（均势或优势）时，派 2~3 艘快速单位骚扰敌方矿区和矿物场
func _evaluate_mineral_raid() -> void:
	# 清理已死亡的骚扰单位
	var to_remove: Array = []
	for u in _raid_mineral_units:
		if not is_instance_valid(u) or u.hull <= 0:
			to_remove.append(u)
	for u in to_remove:
		_raid_mineral_units.erase(u)

	# 检查是否有可攻击的目标（矿场或采矿船）
	var mines = _get_enemy_mines()
	var miners = _get_enemy_miners()
	if mines.size() == 0 and miners.size() == 0:
		# 无可攻击目标 → 停止骚扰
		if _raid_mineral_active:
			_clear_mineral_raid()
		return

	# 计算力量比
	var my_power := 0.0
	var enemy_power := 0.0
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit._is_miner:
			continue
		var weight = pow(2, max(0, Unit._ship_class_tier(unit.class_type)))
		if unit.team == _my_team:
			my_power += weight
		else:
			enemy_power += weight

	var ratio = my_power / max(enemy_power, 1.0)

	if ratio >= 1.0:
		# ✅ 均势或优势：执行骚扰
		var current_count = _raid_mineral_units.size()
		# 骚扰编队大小：2~3 艘快速单位
		var ideal_count = 3

		if current_count < ideal_count:
			_assign_raid_mineral_units(ideal_count - current_count)

		# 更新目标位置
		_raid_mineral_target = _calc_mineral_raid_target()

		# 🚨 检查目标区域敌方火力：附近有超过 1 艘战斗单位则危险，取消骚扰
		if _is_enemy_strong_near_pos(_raid_mineral_target, 1500.0, 2):
			if _raid_mineral_active:
				_clear_mineral_raid()
			return

		_raid_mineral_active = true
	else:
		# ❌ 劣势 → 取消骚扰
		if _raid_mineral_active:
			_clear_mineral_raid()


## 从战斗单位中抽调指定数量的快速单位加入骚扰编队
func _assign_raid_mineral_units(count: int) -> void:
	var candidates: Array[Unit] = []
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != _my_team:
			continue
		if unit._is_miner:
			continue
		if _sneak_attack_units.has(unit):
			continue
		if _raid_mineral_units.has(unit):
			continue
		if _defense_assignments.has(unit):
			continue
		if _retreating_units.get(unit, false):
			continue
		# 跳过无人机（需跟随母舰）
		if unit.home_battleship != null and is_instance_valid(unit.home_battleship):
			continue
		candidates.append(unit)

	# 按速度排序（优先选最快的）
	candidates.sort_custom(func(a, b):
		return Unit._ship_class_tier(a.class_type) < Unit._ship_class_tier(b.class_type))

	var assigned = 0
	for unit in candidates:
		if assigned >= count:
			break
		# 只选护卫舰及以下（速度快，适合骚扰）
		if Unit._ship_class_tier(unit.class_type) > Unit._ship_class_tier(Unit.ShipClass.FRIGATE):
			continue
		_raid_mineral_units[unit] = true
		assigned += 1


## 控制骚扰单位：攻击敌方矿场，其次攻击矿物场
func _handle_mineral_raider(unit: Unit) -> void:
	# 残血时停止骚扰，交由规避逻辑处理
	if unit.hull / unit.max_hull < EVADE_HULL_THRESHOLD:
		_raid_mineral_units.erase(unit)
		return

	_clean_dead_targets(unit)

	# 优先攻击敌方矿场建筑
	var nearest_mine: Building = null
	var nearest_mine_dist := INF
	for b in Building.all_buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		if b.team == _my_team:
			continue
		if b.building_type != Building.BuildingType.MINE:
			continue
		var dist = unit.global_position.distance_to(b.global_position)
		if dist < nearest_mine_dist:
			nearest_mine_dist = dist
			nearest_mine = b

	if nearest_mine != null:
		var approach_range = _get_approach_range(unit)
		if approach_range > 0 and nearest_mine_dist <= approach_range * 1.2:
			unit.attack_target(nearest_mine)
			return
		else:
			unit.attack_area(nearest_mine.global_position, approach_range * 2.0)
			return

	# 无矿场 → 猎杀敌方采矿船（断敌经济命脉）
	var miners = _get_enemy_miners()
	var nearest_miner: Unit = null
	var nearest_miner_dist := INF
	for m in miners:
		if not is_instance_valid(m) or m.hull <= 0:
			continue
		var dist = unit.global_position.distance_to(m.global_position)
		if dist < nearest_miner_dist:
			nearest_miner_dist = dist
			nearest_miner = m

	if nearest_miner != null:
		# 锁定采矿船为目标优先击杀
		unit.attack_target(nearest_miner)
	else:
		# 无目标 → 向敌方矿区中心移动
		unit.move_to(_raid_mineral_target)


## 取消骚扰矿区，清空骚扰编队
func _clear_mineral_raid() -> void:
	_raid_mineral_units.clear()
	_raid_mineral_active = false


## 检查某位置附近敌方战斗单位是否过多（危险评估）
## pos: 目标位置, radius: 检测半径, threshold: 超过此数量即危险
func _is_enemy_strong_near_pos(pos: Vector2, radius: float, threshold: int) -> bool:
	var enemy_count := 0
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == _my_team:
			continue
		if unit._is_miner:
			continue
		var dist = unit.global_position.distance_to(pos)
		if dist < radius:
			enemy_count += 1
			if enemy_count >= threshold:
				return true
	return false


# =============================================================================
# AI 回防基地策略
# =============================================================================

## 评估回防需求：检测己方建筑是否正在被攻击，派附近的单位回防
func _evaluate_defense() -> void:
	# 清理已死亡的单位和建筑
	var to_remove_units: Array = []
	for u in _defense_assignments:
		if not is_instance_valid(u) or u.hull <= 0:
			to_remove_units.append(u)
		else:
			var bld = _defense_assignments[u]
			if not is_instance_valid(bld) or bld.hull <= 0:
				to_remove_units.append(u)
	for u in to_remove_units:
		_defense_assignments.erase(u)

	# 检查所有己方建筑是否正在被攻击
	var threatened_buildings: Array = []  # [{building, threat_level}]
	for b in _buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		if b.team != _my_team:
			continue

		# 检测建筑是否正在掉血
		var prev_hull = _building_prev_hull.get(b, b.max_hull)
		var hull_dropped = prev_hull > b.hull
		_building_prev_hull[b] = b.hull

		if hull_dropped or b.hull < b.max_hull:
			# 建筑被攻击或已受损 → 检查附近是否有敌人
			var enemy_nearby = _is_enemy_near_building(b)
			if enemy_nearby:
				threatened_buildings.append({"building": b, "hull_pct": b.hull / b.max_hull})

	# 按威胁程度排序（血量最低的建筑最需要防守）
	threatened_buildings.sort_custom(func(a, b): return a["hull_pct"] < b["hull_pct"])

	for entry in threatened_buildings:
		var building = entry["building"] as Building
		# 检查该建筑是否已有单位在防守
		var already_defending := false
		for u in _defense_assignments:
			if _defense_assignments[u] == building:
				already_defending = true
				break
		if already_defending:
			continue

		# 找一个空闲的单位去回防
		var defender = _find_defender_for_building(building)
		if defender != null:
			_defense_assignments[defender] = building


## 检查建筑附近是否有敌方单位
func _is_enemy_near_building(building: Building) -> bool:
	var check_range := 1200.0  # 检测范围 1200px
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == _my_team:
			continue
		var dist = unit.global_position.distance_to(building.global_position)
		if dist < check_range:
			return true
	return false


## 为受威胁建筑寻找回防单位
func _find_defender_for_building(building: Building) -> Unit:
	var best: Unit = null
	var best_score := INF

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != _my_team:
			continue
		if unit._is_miner:
			continue
		if _sneak_attack_units.has(unit):
			continue
		if _defense_assignments.has(unit):
			continue
		if _retreating_units.get(unit, false):
			continue

		# 评分：距离建筑越近越好 + 战力越强越好
		var dist = unit.global_position.distance_to(building.global_position)
		var tier = max(1, Unit._ship_class_tier(unit.class_type) + 1)  # 1~5
		var score = dist / tier  # 距离近且战力强的得分低
		if score < best_score:
			best_score = score
			best = unit

	return best


## 控制回防单位：移动至防守建筑附近，攻击附近的敌人
func _handle_defender(unit: Unit) -> void:
	var building = _defense_assignments.get(unit)
	if building == null or not is_instance_valid(building) or building.hull <= 0:
		_defense_assignments.erase(unit)
		return

	# 残血时取消回防，交给规避逻辑
	if unit.hull / unit.max_hull < EVADE_HULL_THRESHOLD:
		_defense_assignments.erase(unit)
		return

	_clean_dead_targets(unit)

	# 检查建筑附近是否有敌人
	var nearest_enemy: Unit = null
	var nearest_dist := INF
	for other in all_units:
		if not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == _my_team:
			continue
		var dist = other.global_position.distance_to(building.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = other

	if nearest_enemy != null and nearest_dist < 1500.0:
		# 有敌人在建筑附近 → 攻击敌人
		if is_instance_valid(unit._current_target) and unit._current_target == nearest_enemy:
			return  # 已在攻击该目标
		unit.attack_target(nearest_enemy)
	else:
		# 无威胁 → 在建筑附近巡逻（环绕建筑）
		var dist_to_building = unit.global_position.distance_to(building.global_position)
		if dist_to_building > 500.0:
			unit.move_to(building.global_position)
		elif not unit._is_orbit:
			unit.orbit_target(building, 300.0)

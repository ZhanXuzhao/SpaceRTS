class_name AiController
extends Node

## AI 控制器：负责指定阵营的索敌和决策，通过 Unit 的公开命令接口下达指令。
## 通用战术行为（环绕/保持距离/追逐/自动技能）由 Unit 统一处理，不分阵营。
## 决策间隔 1 秒，每次评估战场后选择目标阵营，再按优先级选择目标。

enum TargetPref { SMALL_FIRST, BIG_FIRST, THREAT_FOCUS }

var all_units: Array[Unit] = []
var _my_team: String = ""
var _target_pref: TargetPref = TargetPref.SMALL_FIRST
var _decision_timer: float = 0.0
const DECISION_INTERVAL: float = 1.0


func init(units: Array[Unit], team: String, pref: TargetPref) -> void:
	all_units = units
	_my_team = team
	_target_pref = pref


func process_ai(delta: float) -> void:
	_decision_timer += delta
	if _decision_timer < DECISION_INTERVAL:
		return
	_decision_timer = 0.0

	# 评估战场：根据策略选择目标阵营
	var focus_team = _evaluate_battlefield()

	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != _my_team:
			continue

		# 1. 清理已死亡的目标引用
		_clean_dead_targets(unit)

		# 2. 无人机 AI：继承母舰目标 / 环绕母舰
		if unit.home_battleship != null and is_instance_valid(unit.home_battleship):
			_process_drone_ai(unit)

		# 3. 索敌（从评估得出的敌方阵营中按优先级选择目标）
		if unit._current_target == null:
			_select_target(unit, focus_team)


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
		if unit._current_target == null or orbiting_home:
			unit._current_target = mothership._current_target
			unit._is_orbit = false
	elif unit._current_target == null and not unit._is_moving and not unit._is_orbit:
		unit.orbit_target(mothership)


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

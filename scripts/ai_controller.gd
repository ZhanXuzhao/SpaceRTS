extends Node

## AI 控制器：负责红队的索敌和专属决策，通过 Unit 的公开命令接口下达指令。
## 通用战术行为（环绕/保持距离/追逐）由 Unit._update_tactical 统一处理，不分阵营。


var all_units: Array[Unit] = []


func init(units: Array[Unit]) -> void:
	all_units = units


func process_ai(_delta: float) -> void:
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != Unit.Team.RED:
			continue

		# 1. 清理已死亡的目标引用
		_clean_dead_targets(unit)

		# 2. 无人机 AI：继承母舰目标 / 环绕母舰
		if unit.home_battleship != null and is_instance_valid(unit.home_battleship):
			_process_drone_ai(unit)

		# 3. 索敌
		if unit._current_target == null:
			_select_target(unit)

		# 4. 战术决策（红队专属：自动减速技能）
		if unit._current_target != null:
			_process_tactical(unit)


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
		# 母舰有目标 → 无人机攻击同一目标（如果当前空闲或正环绕母舰）
		var orbiting_home = (unit._orbit_target_unit == mothership)
		if unit._current_target == null or orbiting_home:
			unit._current_target = mothership._current_target
			unit._is_orbit = false
	elif unit._current_target == null and not unit._is_moving and not unit._is_orbit:
		# 母舰无目标且无人机空闲 → 环绕母舰
		unit.orbit_target(mothership)


func _select_target(unit) -> void:
	# 检查是否有进攻性武器（非 PD）
	var has_offensive = _get_approach_range(unit) > 0
	if has_offensive:
		var enemy = _find_nearest_enemy(unit)
		if enemy != null:
			unit.attack_target(enemy)
	else:
		# 只有 PD → 环绕最大友军
		if not unit._is_orbit or not is_instance_valid(unit._orbit_target_unit):
			var largest = _find_largest_friendly(unit)
			if largest != null and largest != unit:
				unit.orbit_target(largest)


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


# ----- 战术决策（仅处理红队专属逻辑，通用环绕/保持距离由 Unit._update_tactical 统一处理）-----

func _process_tactical(unit) -> void:
	# 自动减速（技能 4）
	if unit._skill_auto[4] and unit._skill_cooldowns[4] <= 0:
		var slow_dist = unit.global_position.distance_to(unit._current_target.global_position)
		if slow_dist <= GameConfig.SKILL_SLOW_RANGE:
			unit.apply_slow_to_target(unit._current_target)


# ----- 工具函数 -----

static func _get_approach_range(unit) -> float:
	var min_r := INF
	for w in unit._slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.attack_range * unit._weapon_range_mult)
	return min_r if min_r < INF else 0.0


static func _find_nearest_enemy(unit) -> Unit:
	var nearest: Unit = null
	var nearest_dist = INF
	for other in unit.all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == unit.team:
			continue
		var dist = unit.global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest

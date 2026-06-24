class_name UnitCombat
extends Resource


## 更新炮塔旋转朝向当前目标
static func update_turrets(unit, delta: float) -> void:
	if unit._current_target != null:
		for i in range(unit.slot_count):
			if unit._slot_weapons[i] != null:
				var rotated_offset = unit._slot_offsets_scaled[i].rotated(unit._body.rotation)
				var fire_pos = unit.global_position + rotated_offset
				var to_target = (unit._current_target.global_position - fire_pos).rotated(-unit._body.rotation)
				var target_angle = to_target.angle()
				var turn_speed = unit._slot_weapons[i].turn_speed
				unit._slot_angles[i] = unit._rotate_toward(unit._slot_angles[i], target_angle, turn_speed * delta)
	else:
		for i in range(unit.slot_count):
			if unit._slot_weapons[i] != null:
				unit._slot_angles[i] = unit._rotate_toward(unit._slot_angles[i], 0.0, 90.0 * delta)
	for i in range(min(unit._weapon_sprites.size(), unit.slot_count)):
		unit._weapon_sprites[i].rotation = unit._slot_angles[i]


## 激光周期计时 + 武器开火（纯执行，不含 AI 决策）
static func update_weapons(unit, delta: float) -> void:
	# 激光周期计时
	unit._laser_cycle_timer -= delta
	var laser_on = unit._laser_cycle_timer > 0
	if unit._laser_cycle_timer <= -GameConfig.LASER_COOLDOWN_DURATION:
		unit._laser_cycle_timer = unit._laser_attack_duration

	# 武器开火
	var max_range = unit._get_max_range()
	if unit._current_target != null and max_range > 0:
		var dist = unit.global_position.distance_to(unit._current_target.global_position)
		if dist <= max_range:
			for i in range(unit.slot_count):
				var w = unit._slot_weapons[i]
				if w == null:
					continue
				if w.weapon_type == Weapon.WeaponType.LASER and not laser_on:
					continue
				if dist <= w.attack_range * unit._weapon_range_mult and unit._slot_cooldowns[i] <= 0.0 and unit._current_target.team != unit.team:
					unit._fire_slot(i, unit._current_target)
					if w.weapon_type == Weapon.WeaponType.LASER:
						unit._slot_cooldowns[i] = 1.0 / GameConfig.LASER_HITS_PER_SECOND
					else:
						unit._slot_cooldowns[i] = w.cooldown


## PD 拦截系统（纯执行）
static func update_pd(unit, _delta: float) -> void:
	unit._pd_has_target = false
	var nearest_pd_range := 0.0
	for i in range(unit.slot_count):
		var w = unit._slot_weapons[i]
		if w != null and w.weapon_type == Weapon.WeaponType.PD:
			nearest_pd_range = max(nearest_pd_range, w.attack_range)
	if nearest_pd_range > 0:
		var proj = _find_nearest_enemy_missile(unit, nearest_pd_range)
		if proj != null:
			unit._pd_has_target = true
			unit._pd_target_pos = proj.global_position
	for i in range(unit.slot_count):
		var w = unit._slot_weapons[i]
		if w == null or w.weapon_type != Weapon.WeaponType.PD:
			continue
		if unit._slot_cooldowns[i] > 0.0:
			continue
		var proj = _find_nearest_enemy_missile(unit, w.attack_range)
		if proj != null:
			unit._slot_cooldowns[i] = w.cooldown
			proj.take_damage(w.damage)
			Unit.record_weapon_damage(unit.team, Weapon.WeaponType.PD, w.damage)


# ----- 工具函数（供 Unit 和 AI Controller 使用）-----

static func find_nearest_enemy(unit) -> Unit:
	return _find_nearest_enemy(unit)

static func find_nearest_enemy_in_area(unit) -> Unit:
	return _find_nearest_enemy_in_area(unit)


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


static func _find_nearest_enemy_in_area(unit) -> Unit:
	var nearest: Unit = null
	var nearest_dist = unit._area_radius
	for other in unit.all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == unit.team:
			continue
		var dist = other.global_position.distance_to(unit._area_center)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


static func _find_nearest_enemy_missile(unit, search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist = search_range
	for proj in unit.get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj):
			continue
		if proj.team == unit.team:
			continue
		if not proj.is_homing:
			continue
		var dist = unit.global_position.distance_to(proj.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = proj
	return nearest


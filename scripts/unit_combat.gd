extends Resource

const CFG = preload("res://scripts/game_config.gd")

static func update_target(unit) -> void:
	if unit._home_battleship != null and unit._current_target == null:
		if is_instance_valid(unit._home_battleship) and is_instance_valid(unit._home_battleship._current_target) and unit._home_battleship._current_target.hull > 0:
			unit._current_target = unit._home_battleship._current_target
			unit._is_orbit = false
	if unit._home_battleship != null and unit._current_target == null and not unit._is_moving and not unit._is_orbit:
		unit.orbit_target(unit._home_battleship)
		return
	if is_instance_valid(unit._explicit_attack_target) and unit._explicit_attack_target.hull <= 0:
		unit._explicit_attack_target = null
	if is_instance_valid(unit._current_target) and unit._current_target.hull <= 0:
		unit._current_target = null
	if unit._current_target == null:
		if unit._explicit_attack_target != null:
			unit._current_target = unit._explicit_attack_target
		elif unit._is_attack_move:
			unit._current_target = _find_nearest_enemy(unit)
		elif unit._is_area_attack:
			unit._current_target = _find_nearest_enemy_in_area(unit)
		else:
			unit._current_target = _find_nearest_enemy_in_range(unit)

static func find_nearest_enemy(unit) -> Unit:
	return _find_nearest_enemy(unit)

static func find_nearest_enemy_in_area(unit) -> Unit:
	return _find_nearest_enemy_in_area(unit)

static func _find_nearest_enemy(unit) -> Unit:
	var nearest: Unit = null
	var nearest_dist = INF
	for other in unit._all_units:
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
	for other in unit._all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == unit.team:
			continue
		var dist = other.global_position.distance_to(unit._area_center)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest

static func _find_nearest_enemy_in_range(unit) -> Unit:
	var nearest: Unit = null
	var nearest_dist = unit._get_max_range()
	if nearest_dist <= 0:
		return null
	for other in unit._all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == unit.team:
			continue
		var dist = unit.global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest

static func _get_approach_range(unit) -> float:
	var min_r := INF
	for w in unit._slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.range * unit._weapon_range_mult)
	return min_r if min_r < INF else 0.0

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

static func update_combat(unit, delta: float) -> void:
	if unit._attack_mode == Unit.AttackMode.KEEP_DISTANCE and is_instance_valid(unit._current_target) and unit._current_target.hull > 0:
		var dist = unit.global_position.distance_to(unit._current_target.global_position)
		var optimal = unit._get_max_range() * 0.7
		var target_dist = optimal * 0.9
		var dir = (unit._current_target.global_position - unit.global_position).normalized()
		if dist > optimal:
			unit._target_position = unit._current_target.global_position - dir * target_dist
			unit._is_moving = true
		elif dist < optimal * 0.8:
			unit._target_position = unit._current_target.global_position - dir * target_dist
			unit._is_moving = true
	if unit.class_type in [Unit.ShipClass.DRONE, Unit.ShipClass.FRIGATE] and is_instance_valid(unit._current_target) and unit._current_target.hull > 0 and unit._current_target.team != unit.team:
		if unit._skill_cooldowns[4] <= 0:
			unit.activate_skill(4)
	unit._laser_cycle_timer -= delta
	var laser_on = unit._laser_cycle_timer > 0
	if unit._laser_cycle_timer <= -CFG.LASER_COOLDOWN_DURATION:
		unit._laser_cycle_timer = unit._laser_attack_duration
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
				if dist <= w.range * unit._weapon_range_mult and unit._slot_cooldowns[i] <= 0.0 and unit._current_target.team != unit.team:
					unit._fire_slot(i, unit._current_target)
					if w.weapon_type == Weapon.WeaponType.LASER:
						unit._slot_cooldowns[i] = 1.0 / CFG.LASER_HITS_PER_SECOND
					else:
						unit._slot_cooldowns[i] = w.cooldown

static func update_chase(unit) -> void:
	var approach_range = _get_approach_range(unit)
	if unit._attack_mode == Unit.AttackMode.ORBIT_SHOOT and unit._current_target != null and is_instance_valid(unit._current_target) and unit._current_target.hull > 0 and unit._current_target.team != unit.team:
		if not unit._is_orbit or unit._orbit_target_unit != unit._current_target:
			unit.orbit_target(unit._current_target)
		return
	if unit._current_target != null and approach_range > 0:
		var dist = unit.global_position.distance_to(unit._current_target.global_position)
		if dist <= approach_range and unit._explicit_attack_target != null:
			unit._is_moving = false
		elif dist > approach_range:
			var should_chase := false
			if unit._explicit_attack_target != null:
				should_chase = true
			elif unit._is_attack_move:
				should_chase = true
			elif not unit._is_moving:
				should_chase = true
			if should_chase:
				var to_target = unit._current_target.global_position - unit.global_position
				var dir = to_target.normalized()
				unit._target_position = unit._current_target.global_position - dir * approach_range * 0.85
				unit._is_moving = true
			if not should_chase and is_instance_valid(unit._current_target):
				if dist > approach_range * 1.2:
					unit._current_target = null
	elif unit._current_target == null:
		if unit._has_saved_move:
			unit._target_position = unit._saved_move_target
			unit._is_moving = true
			unit._has_saved_move = false

static func update_pd(unit, delta: float) -> void:
	unit._pd_has_target = false
	var nearest_pd_range := 0.0
	for i in range(unit.slot_count):
		var w = unit._slot_weapons[i]
		if w != null and w.weapon_type == Weapon.WeaponType.PD:
			nearest_pd_range = max(nearest_pd_range, w.range)
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
		var proj = _find_nearest_enemy_missile(unit, w.range)
		if proj != null:
			unit._slot_cooldowns[i] = w.cooldown
			proj.take_damage(w.damage)


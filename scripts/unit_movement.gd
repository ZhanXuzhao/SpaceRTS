extends Resource


static func update_movement(unit, delta: float) -> void:
	if not unit._is_moving:
		unit.velocity = Vector2.ZERO
		return
	_move_toward_target(unit, delta)

	if unit._is_attack_move and unit._current_target == null:
		if unit.global_position.distance_to(unit.attack_move_destination) < 4.0:
			unit._is_attack_move = false
			unit._is_moving = false
	elif not unit._is_attack_move and unit._current_target == null:
		if unit.global_position.distance_to(unit._target_position) < 4.0:
			# 到达目标点，执行指令队列中的下一个操作
			if unit._command_queue.size() > 0:
				unit._advance_command_queue()
			else:
				unit._is_moving = false

static func _move_toward_target(unit, delta: float) -> void:
	var distance = unit.global_position.distance_to(unit._target_position)
	if distance < 4.0:
		unit._is_moving = false
		unit.velocity = Vector2.ZERO
		return

	var direction = (unit._target_position - unit.global_position).normalized()

	# ---- 减速（仅影响最大速度）----
	var slow_mult = unit._slow_mult * unit.get_slow_mult()
	var effective_max_speed = unit.speed * slow_mult

	# ---- 加速（同时提升最大速度和推力）----
	var effective_thrust = unit.thrust
	if unit._speed_mult > 1.0:
		effective_max_speed *= unit._speed_mult
		effective_thrust *= unit._speed_mult

	# ---- 分离力（编队避让，影响方向）----
	var separation_dir = Vector2.ZERO
	const SEPARATION_RADIUS: float = 80.0
	for other in unit.all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		var to_other = unit.global_position - other.global_position
		var dist = to_other.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			separation_dir += to_other.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS

	# ---- 合成为期望方向 ----
	var desired_dir = direction
	if separation_dir.length_squared() > 0.001:
		desired_dir = (direction + separation_dir * 1.5).normalized()

	# ---- 朝期望方向加速（加速度 = 推力 / 质量）----
	var accel = effective_thrust / unit.mass
	var target_velocity = desired_dir * effective_max_speed
	var accel_this_frame = accel * delta

	var diff = target_velocity - unit.velocity
	if diff.length() > accel_this_frame:
		unit.velocity += diff.normalized() * accel_this_frame
	else:
		unit.velocity = target_velocity

	# ---- 转向（使用角速度平滑旋转）----
	if unit.velocity.length_squared() > 1.0:
		var target_angle = unit.velocity.angle()
		var current_angle = unit._body.rotation
		var diff_angle = fmod(target_angle - current_angle + PI, TAU) - PI
		var max_turn = deg_to_rad(unit.max_angular_speed) * delta
		if abs(diff_angle) <= max_turn:
			unit._body.rotation = target_angle
		else:
			unit._body.rotation += sign(diff_angle) * max_turn

	# ---- 应用位置 ----
	unit.global_position += unit.velocity * delta

static func update_drones(unit, delta: float) -> void:
	if unit.class_type != Unit.ShipClass.BATTLESHIP or unit.drone_bay <= 0:
		return

	unit.deployed_drones = unit.deployed_drones.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	if unit.deployed_drones.size() < unit.max_deployed_drones:
		unit.drone_launch_timer -= delta
		if unit.drone_launch_timer <= 0:
			_launch_drone(unit)
			unit.drone_launch_timer = 1.0

static func _launch_drone(unit) -> void:
	var drone_scene = load("res://scenes/unit.tscn")
	var d = drone_scene.instantiate()
	d.class_type = Unit.ShipClass.DRONE
	d.team = unit.team
	d.unit_color = unit.unit_color
	d.all_units = unit.all_units
	var spawn_dir = Vector2.RIGHT.rotated(unit._body.rotation)
	d.global_position = unit.global_position + spawn_dir * 50.0 * unit._size_mult
	unit.get_parent().add_child(d)
	d._body.rotation = unit._body.rotation
	unit.all_units.append(d)

	var i := 0
	while i < d.slot_count:
		var w = Weapon.create_random()
		d._slot_weapons[i] = w
		if i + 1 < d.slot_count:
			d._slot_weapons[i + 1] = w
		i += 2
	d.refresh_weapon_visuals()
	d.orbit_target(unit, GameConfig.DRONE_ORBIT_RADIUS)
	d.home_battleship = unit
	unit.deployed_drones.append(d)
	unit.drone_bay -= 1

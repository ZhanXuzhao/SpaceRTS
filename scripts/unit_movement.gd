extends Resource


static func update_movement(unit, delta: float) -> void:
	# 环绕模式：速度由 _update_orbit 直接控制，只做转向和位置更新
	if unit._is_orbit:
		_apply_orbit_movement(unit, delta)
		return

	if not unit._is_moving:
		unit.velocity = Vector2.ZERO
		# 停稳后若指定了阵型朝向，转到位
		_snap_arrival_rotation(unit, delta)
		return
	_move_toward_target(unit, delta)

	if unit._is_attack_move and unit._current_target == null:
		if unit.global_position.distance_to(unit.attack_move_destination) < 4.0:
			unit._is_attack_move = false
			unit._is_moving = false
	elif not unit._is_attack_move and unit._current_target == null:
		var arrival_dist = _get_arrival_distance(unit)
		if unit.global_position.distance_to(unit._target_position) < arrival_dist:
			# 到达目标点，执行指令队列中的下一个操作
			if unit._command_queue.size() > 0:
				unit._advance_command_queue()
			else:
				unit._is_moving = false

static func _get_arrival_distance(unit) -> float:
	# 队列中还有后续指令时放宽到达判定，减少加减速时间
	if unit._command_queue.size() > 0:
		return GameConfig.QUEUE_MOVE_ARRIVAL_DISTANCE
	return 4.0

static func _move_toward_target(unit, delta: float) -> void:
	var arrival_dist = _get_arrival_distance(unit)
	var distance = unit.global_position.distance_to(unit._target_position)
	if distance < arrival_dist:
		unit._is_moving = false
		unit.velocity = Vector2.ZERO
		_snap_arrival_rotation(unit, delta)
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

	# ---- 分离力（编队避让，基于碰撞体尺寸动态计算）----
	var separation_dir = _compute_separation(unit)

	# ---- 合成为期望方向 ----
	var desired_dir = direction
	if separation_dir.length_squared() > 0.001:
		desired_dir = (direction + separation_dir * 8.0).normalized()

	# ---- 速度控制----
	var accel = effective_thrust / unit.mass
	var target_speed = effective_max_speed
	if not unit._is_orbit:
		# 非环绕时：用最大安全速度限制，接近目标时自动减速
		var max_safe_speed = sqrt(2.0 * accel * distance)
		target_speed = min(effective_max_speed, max_safe_speed)
	# 环绕时：全速前进，不做减速（目标点每帧移动，减速会拉成椭圆轨迹）
	var target_velocity = desired_dir * target_speed
	var accel_this_frame = accel * delta

	var diff = target_velocity - unit.velocity
	if diff.length() > accel_this_frame:
		unit.velocity += diff.normalized() * accel_this_frame
	else:
		unit.velocity = target_velocity

	# ---- 转向（使用角速度平滑旋转）----
	var face_angle: float
	if unit._arrival_rotation != INF and distance < 150.0:
		# 接近阵型位置时提前转向阵型朝向（距离阈值放大，留足时间）
		face_angle = unit._arrival_rotation
	elif unit.velocity.length_squared() > 1.0:
		face_angle = unit.velocity.angle()
	else:
		face_angle = unit._body.rotation

	var current_angle = unit._body.rotation
	var diff_angle = fposmod(face_angle - current_angle + PI, TAU) - PI
	var max_turn = deg_to_rad(unit.max_angular_speed) * delta
	if abs(diff_angle) <= max_turn:
		unit._body.rotation = face_angle
	else:
		unit._body.rotation += sign(diff_angle) * max_turn

	# ---- 应用位置 ----
	unit.global_position += unit.velocity * delta


## 环绕模式：速度已由 unit._update_orbit 算好，这里只做转向和位置更新
static func _apply_orbit_movement(unit, delta: float) -> void:
	# 转向速度方向
	if unit.velocity.length_squared() > 1.0:
		var target_angle = unit.velocity.angle()
		var current_angle = unit._body.rotation
		var diff_angle = fposmod(target_angle - current_angle + PI, TAU) - PI
		var max_turn = deg_to_rad(unit.max_angular_speed) * delta
		if abs(diff_angle) <= max_turn:
			unit._body.rotation = target_angle
		else:
			unit._body.rotation += sign(diff_angle) * max_turn

	# ---- 环绕时也施加分离力，避免堆叠 ----
	var sep_dir = _compute_separation(unit)
	if sep_dir.length_squared() > 0.001:
		var sep_speed = unit.velocity.length() * 0.5
		unit.global_position += sep_dir * sep_speed * delta

	# 应用位置
	unit.global_position += unit.velocity * delta


## 计算分离力方向（供移动和环绕共用）
static func _compute_separation(unit) -> Vector2:
	var sep_radius = unit.collision_shape.shape.size.length() * 1.2
	var sep_dir = Vector2.ZERO
	var space_state = unit.get_world_2d().direct_space_state
	var sep_query = PhysicsShapeQueryParameters2D.new()
	var sep_circle = CircleShape2D.new()
	sep_circle.radius = max(sep_radius, 120.0)
	sep_query.shape = sep_circle
	sep_query.transform = Transform2D(0, unit.global_position)
	sep_query.collision_mask = 1
	sep_query.collide_with_areas = true
	sep_query.collide_with_bodies = false
	var nearby = space_state.intersect_shape(sep_query)
	for r in nearby:
		var other = r.collider
		if other == unit or not is_instance_valid(other) or not other is Unit:
			continue
		if other.hull <= 0:
			continue
		var own_radius = unit.collision_shape.shape.size.length() * 0.5
		var other_radius = other.collision_shape.shape.size.length() * 0.5
		var min_dist = (own_radius + other_radius) * 0.8
		var to_other = unit.global_position - other.global_position
		var dist = to_other.length()
		if dist > 0.001 and dist < min_dist:
			var force = (min_dist - dist) / min_dist
			sep_dir += to_other.normalized() * force * force
	return sep_dir


## 停稳后若指定了阵型朝向，持续转直到到位
static func _snap_arrival_rotation(unit, delta: float) -> void:
	if unit._arrival_rotation == INF:
		return
	var current = unit._body.rotation
	var diff = fposmod(unit._arrival_rotation - current + PI, TAU) - PI
	var max_turn = deg_to_rad(unit.max_angular_speed) * delta
	if abs(diff) <= max_turn:
		unit._body.rotation = unit._arrival_rotation
		# 转到位后清除标记
		unit._arrival_rotation = INF
	else:
		unit._body.rotation += sign(diff) * max_turn

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

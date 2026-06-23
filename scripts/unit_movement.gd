extends Resource

const CFG = preload("res://scripts/game_config.gd")

static func update_movement(unit, delta: float) -> void:
	if not unit._is_moving:
		unit.velocity = Vector2.ZERO
		return
	_move_toward_target(unit, delta)

	if unit._is_attack_move and unit._current_target == null:
		if unit.global_position.distance_to(unit.attack_move_destination) < 4.0:
			unit._is_attack_move = false
			unit._is_moving = false
			unit._player_move_command = false
	elif not unit._is_attack_move and unit._current_target == null:
		if unit.global_position.distance_to(unit._target_position) < 4.0:
			unit._is_moving = false
			unit._player_move_command = false

static func _move_toward_target(unit, delta: float) -> void:
	var distance = unit.global_position.distance_to(unit._target_position)
	if distance < 4.0:
		unit._is_moving = false
		unit._player_move_command = false
		unit.velocity = Vector2.ZERO
		return

	var direction = (unit._target_position - unit.global_position).normalized()
	var desired_velocity = direction * unit.speed * unit._speed_mult

	var separation = Vector2.ZERO
	const SEPARATION_RADIUS: float = 80.0
	for other in unit.all_units:
		if other == unit or not is_instance_valid(other) or other.hull <= 0:
			continue
		var to_other = unit.global_position - other.global_position
		var dist = to_other.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			separation += to_other.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS

	var effective_speed = unit.speed * unit._speed_mult * unit._slow_mult * unit.get_slow_mult()
	var velocity = desired_velocity + separation * unit.speed * 1.5
	if velocity.length() > effective_speed:
		velocity = velocity.normalized() * effective_speed

	if velocity.length() > 0.0:
		unit._body.rotation = velocity.angle()

	unit.velocity = velocity
	unit.global_position += velocity * delta

static func update_drones(unit, delta: float) -> void:
	if unit.class_type != Unit.ShipClass.BATTLESHIP or unit.drone_bay <= 0:
		return

	unit.deployed_drones = unit.deployed_drones.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	if unit.deployed_drones.size() < unit.max_deployed_drones:
		unit.drone_launch_timer -= delta
		if unit.drone_launch_timer <= 0:
			_launch_drone(unit)
			unit.drone_launch_timer = 0.5

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
	unit.all_units.append(d)

	var i := 0
	while i < d.slot_count:
		var w = Weapon.create_random()
		d._slot_weapons[i] = w
		if i + 1 < d.slot_count:
			d._slot_weapons[i + 1] = w
		i += 2
	d.refresh_weapon_visuals()
	d.orbit_target(unit, CFG.DRONE_ORBIT_RADIUS)
	d.home_battleship = unit
	unit.deployed_drones.append(d)
	unit.drone_bay -= 1

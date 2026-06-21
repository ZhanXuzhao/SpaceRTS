class_name Unit
extends Area2D

enum Team { BLUE, RED }

const CFG = preload("res://scripts/game_config.gd")

@export var speed: float = CFG.UNIT_MAX_SPEED
@export var acceleration: float = CFG.UNIT_ACCELERATION
@export var mass: float = CFG.UNIT_MASS
var velocity: Vector2
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE

# ----- 护盾 & 结构 -----
@export var max_shield: float = CFG.UNIT_MAX_SHIELD
@export var max_hull: float = CFG.UNIT_MAX_HULL
@export var shield_regen_rate: float = CFG.UNIT_SHIELD_REGEN

var shield: float
var hull: float
var _shield_regen_delay: float = 0.0

@export var slot_count: int = CFG.UNIT_SLOT_COUNT

## 是否被选中
var is_selected: bool = false : set = _set_is_selected

var _all_units: Array[Unit] = []

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

# ----- 武器槽位 -----
var _slot_weapons: Array = []
var _slot_angles: Array[float] = []
var _slot_cooldowns: Array[float] = []

const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(0, -40),     # 0: 上
	Vector2(28, -28),    # 1: 右上
	Vector2(40, 0),      # 2: 右
	Vector2(28, 28),     # 3: 右下
	Vector2(0, 40),      # 4: 下
	Vector2(-28, 28),    # 5: 左下
	Vector2(-40, 0),     # 6: 左
	Vector2(-28, -28),   # 7: 左上
]

# ----- 攻击指令相关 -----
var _explicit_attack_target: Unit = null
var _attack_move_destination: Vector2
var _is_attack_move: bool = false
## 区域攻击（A+空地点地）
var _is_area_attack: bool = false
var _area_center: Vector2
var _area_radius: float = 500.0
var _saved_move_target: Vector2
var _has_saved_move: bool = false

# PD 持续弹道
var _pd_target_pos: Vector2
var _pd_has_target: bool = false

# ----- 环绕 -----
var _is_orbit: bool = false
var _orbit_target_unit: Unit = null
var _orbit_angle: float = 0.0
## 环绕方向：1 = 逆时针，-1 = 顺时针（由切入位置确定）
var _orbit_direction: float = 1.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	shield = max_shield
	hull = max_hull

	# 初始化武器槽位
	_slot_weapons.resize(slot_count)
	_slot_angles.resize(slot_count)
	_slot_cooldowns.resize(slot_count)
	for i in range(slot_count):
		_slot_weapons[i] = null
		_slot_angles[i] = 0.0
		_slot_cooldowns[i] = 0.0

	var shape = RectangleShape2D.new()
	shape.size = Vector2(64, 64)
	collision_shape.shape = shape


func _process(delta: float) -> void:

	# ---- 护盾自动恢复 ----
	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)

	# ---- 冷却更新 ----
	for i in range(slot_count):
		_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - delta)

	# 清理无效的明确攻击目标
	if is_instance_valid(_explicit_attack_target) and _explicit_attack_target.hull <= 0:
		_explicit_attack_target = null

	# 清理无效的当前目标
	if is_instance_valid(_current_target) and _current_target.hull <= 0:
		_current_target = null

	# ---- 目标获取（由外部控制器下发，这里只处理显式指令） ----
	if _current_target == null:
		if _explicit_attack_target != null:
			_current_target = _explicit_attack_target
		elif _is_attack_move:
			_current_target = _find_nearest_enemy()

	# ---- 炮塔旋转 ----
	if _current_target != null:
		var to_target = _current_target.global_position - global_position
		for i in range(slot_count):
			if _slot_weapons[i] != null:
				var target_angle = to_target.angle()
				var turn_speed = _slot_weapons[i].turn_speed
				_slot_angles[i] = _rotate_toward(_slot_angles[i], target_angle, turn_speed * delta)
	else:
		# 无目标时炮塔缓慢回正
		for i in range(slot_count):
			if _slot_weapons[i] != null:
				_slot_angles[i] = _rotate_toward(_slot_angles[i], 0.0, 90.0 * delta)

	# ---- 战斗 / 追击 ----
	var max_range = _get_max_range()
	var approach_range = _get_approach_range()
	# ---- 开火：在最大射程内的武器独立检查射程开火 ----
	if _current_target != null and max_range > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= max_range:
			for i in range(slot_count):
				var w = _slot_weapons[i]
				if w != null and dist <= w.range and _slot_cooldowns[i] <= 0.0:
					_fire_slot(i, _current_target)
					_slot_cooldowns[i] = w.cooldown

	# ---- 停靠 / 追击 ----
	if _current_target != null and approach_range > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= approach_range and _explicit_attack_target != null:
			_is_moving = false
		elif dist > approach_range:
			var should_chase := false
			if _explicit_attack_target != null:
				should_chase = true
			elif _is_attack_move:
				should_chase = true
			elif not _is_moving:
				should_chase = true

			if should_chase:
				var to_target = _current_target.global_position - global_position
				var dir = to_target.normalized()
				_target_position = _current_target.global_position - dir * approach_range * 0.85
				_is_moving = true
			if not should_chase and is_instance_valid(_current_target):
				if dist > approach_range * 1.2:
					_current_target = null
	elif _current_target == null:
		if _has_saved_move:
			_target_position = _saved_move_target
			_is_moving = true
			_has_saved_move = false

	# ---- PD 拦截 ----
	# 找到最近的敌方弹体用于显示光束
	_pd_has_target = false
	var nearest_pd_range := 0.0
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w != null and w.weapon_type == Weapon.WeaponType.PD:
			nearest_pd_range = max(nearest_pd_range, w.range)
	if nearest_pd_range > 0:
		var proj = _find_nearest_enemy_missile(nearest_pd_range)
		if proj != null:
			_pd_has_target = true
			_pd_target_pos = proj.global_position

	# 每个 PD 槽位独立开火
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w == null or w.weapon_type != Weapon.WeaponType.PD:
			continue
		if _slot_cooldowns[i] > 0.0:
			continue
		var proj = _find_nearest_enemy_missile(w.range)
		if proj != null:
			_slot_cooldowns[i] = w.cooldown
			proj.take_damage(w.damage)

	# ---- 环绕移动 ----
	if _is_orbit and is_instance_valid(_orbit_target_unit) and _orbit_target_unit.hull > 0:
		var dist = _get_approach_range() * 0.85
		if dist < 50: dist = 50
		# 角速度 = 线速度 / 半径，保证飞船实际能追上轨道
		var angular_speed = rad_to_deg(speed / dist)
		_orbit_angle += delta * angular_speed * _orbit_direction
		var rad = deg_to_rad(_orbit_angle)
		_target_position = _orbit_target_unit.global_position + Vector2(cos(rad), sin(rad)) * dist
		_is_moving = true
		queue_redraw()
	elif _is_orbit:
		_is_orbit = false

	# ---- 移动 ----
	if _is_moving:
		_move_toward_target(delta)

		if _is_attack_move and _current_target == null:
			if global_position.distance_to(_attack_move_destination) < 4.0:
				_is_attack_move = false
				_is_moving = false
		elif not _is_attack_move and _current_target == null:
			if global_position.distance_to(_target_position) < 4.0:
				_is_moving = false

	queue_redraw()


func _get_max_range() -> float:
	var max_r := 0.0
	for w in _slot_weapons:
		if w != null:
			max_r = max(max_r, w.range)
	return max_r


func _get_approach_range() -> float:
	var min_r := INF
	for w in _slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.range)
	return min_r if min_r < INF else 0.0

func _rotate_toward(current: float, target: float, max_delta: float) -> float:
	"""按最大步长旋转 current 角度到 target 角度（弧度）"""
	var diff = fmod(target - current + PI, TAU) - PI
	if abs(diff) < 0.001:
		return target
	var step = clamp(abs(diff), -max_delta, max_delta) * sign(diff)
	return current + step


func _fire_slot(slot_index: int, target: Unit) -> void:
	var w = _slot_weapons[slot_index]
	if w == null:
		return

	var slot_offset = SLOT_OFFSETS[slot_index]
	var fire_pos = global_position + slot_offset
	var fire_dir = Vector2.RIGHT.rotated(_slot_angles[slot_index])

	match w.weapon_type:
		Weapon.WeaponType.LASER:
			target.take_damage(w.damage, self)

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			_spawn_projectile(fire_pos, fire_dir, target, w)


func _spawn_projectile(from_pos: Vector2, direction: Vector2, target: Unit, w: Weapon) -> void:
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.global_position = from_pos

	# 弹体生命值（PD可消耗）
	var proj_hp := 0.0
	if w.weapon_type == Weapon.WeaponType.BULLET:
		proj_hp = CFG.BULLET_HP
	elif w.weapon_type == Weapon.WeaponType.MISSILE:
		proj_hp = CFG.MISSILE_HP

	proj.setup({
		"max_speed": w.projectile_speed,`n"acceleration": CFG.BULLET_ACCELERATION,
		"damage": w.damage,
		"direction": direction,
		"target": target,
		"team": team,
		"source": self,
		"is_homing": w.is_homing,
		"color": w.projectile_color,
		"size": w.projectile_size,
		"hp": proj_hp,
	})
	get_tree().root.add_child(proj)


func _move_toward_target(delta: float) -> void:
	var distance = global_position.distance_to(_target_position)
	if distance < 4.0:
		_is_moving = false
		return

	var direction = (_target_position - global_position).normalized()
	var desired_velocity = direction * speed

	var separation = Vector2.ZERO
	const SEPARATION_RADIUS: float = 80.0
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		var to_other = global_position - other.global_position
		var dist = to_other.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			separation += to_other.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS

	var velocity = desired_velocity + separation * speed * 1.5
	if velocity.length() > speed:
		velocity = velocity.normalized() * speed

	global_position += velocity * delta


func _find_nearest_enemy_in_area() -> Unit:
	var nearest: Unit = null
	var nearest_dist = _area_radius
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = other.global_position.distance_to(_area_center)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func find_nearest_enemy() -> Unit:
	"""公开接口：被外部控制器调用"""
	return _find_nearest_enemy()


func _find_nearest_enemy() -> Unit:
	var nearest: Unit = null
	var nearest_dist = INF
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func _find_nearest_enemy_missile(search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist = search_range
	for proj in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj):
			continue
		if proj.team == team:
			continue
		if not proj.is_homing:
			continue
		var dist = global_position.distance_to(proj.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = proj
	return nearest


func _find_nearest_enemy_projectile(search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist = search_range
	for proj in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj):
			continue
		if proj.team == team:
			continue
		var dist = global_position.distance_to(proj.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = proj
	return nearest


func take_damage(amount: float, attacker: Unit = null) -> void:
	# 护盾先吸收伤害
	if shield > 0.0:
		var absorbed = min(shield, amount)
		shield -= absorbed
		amount -= absorbed
	# 剩余伤害由结构承受
	if amount > 0.0:
		hull -= amount

	# 护盾恢复延迟
	_shield_regen_delay = CFG.UNIT_SHIELD_DELAY

	# 受击反击：任何单位被攻击后都会还手
	if attacker != null:
		if is_instance_valid(attacker) and attacker.hull > 0 and attacker.team != team:
			if _current_target == null:
				if _is_moving and not _is_attack_move:
					_saved_move_target = _target_position
					_has_saved_move = true
				_current_target = attacker
				_explicit_attack_target = null
				_is_attack_move = false

	if hull <= 0:
		_die()


func _die() -> void:
	_all_units.erase(self)
	queue_free()


func move_to(target: Vector2) -> void:
	_target_position = target
	_is_moving = true
	_current_target = null
	_explicit_attack_target = null
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_has_saved_move = false


func attack_target(target: Unit) -> void:
	_current_target = target
	_explicit_attack_target = target
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_has_saved_move = false
	_target_position = target.global_position


func attack_move_to(destination: Vector2) -> void:
	_target_position = destination
	_attack_move_destination = destination
	_is_attack_move = true
	_is_area_attack = false
	_is_orbit = false
	_is_moving = true
	_explicit_attack_target = null
	_has_saved_move = false
	_current_target = _find_nearest_enemy()


func attack_area(center: Vector2, radius: float) -> void:
	_area_center = center
	_area_radius = radius
	_is_area_attack = true
	_is_moving = false
	_is_attack_move = false
	_is_orbit = false
	_explicit_attack_target = null
	_has_saved_move = false
	_current_target = _find_nearest_enemy_in_area()


func orbit_target(target: Unit) -> void:
	_orbit_target_unit = target
	_is_orbit = true
	_explicit_attack_target = target
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_has_saved_move = false
	# 初始角度设为单位当前位置相对于目标的方向，避免先靠近再远离
	var from_target = global_position - target.global_position
	_orbit_angle = rad_to_deg(from_target.angle())
	# 方向由切入位置决定
	_orbit_direction = 1.0 if from_target.x >= 0.0 else -1.0
	_current_target = target


func stop() -> void:
	_is_moving = false


func _set_is_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	# ---- 环绕轨迹 ----
	if _is_orbit and is_instance_valid(_orbit_target_unit) and _orbit_target_unit.hull > 0:
		var center = _orbit_target_unit.global_position - global_position
		var radius = _get_approach_range() * 0.85
		if radius < 50: radius = 50
		var trail_color = Color(0.2, 1.0, 0.5, 0.25)
		var segments = 24
		for i in range(segments):
			var a1 = deg_to_rad(i * 360.0 / segments)
			var a2 = deg_to_rad((i + 1) * 360.0 / segments)
			var p1 = center + Vector2(cos(a1), sin(a1)) * radius
			var p2 = center + Vector2(cos(a2), sin(a2)) * radius
			draw_line(p1, p2, trail_color, 1.5)
		# 方向指示箭头
		var arrow_angle = deg_to_rad(_orbit_angle)
		var arrow_pos = center + Vector2(cos(arrow_angle), sin(arrow_angle)) * radius
		draw_circle(arrow_pos, 3.0, Color(0.2, 1.0, 0.5, 0.5))
		# 指向目标中心的连线
		draw_line(Vector2.ZERO, center, Color(0.2, 1.0, 0.5, 0.1), 1.0)

	# ---- 太空飞船本体 ----
	# 船体（六边形飞船）
	var body_color = unit_color
	if is_selected:
		body_color = Color(0.5, 0.7, 1.0)

	# 飞船多边形：箭头形，尖端向上
	var ship = PackedVector2Array([
		Vector2(0, -32),       # 船头
		Vector2(-20, -12),     # 左翼
		Vector2(-28, 16),      # 左引擎
		Vector2(-8, 12),       # 左尾
		Vector2(0, 22),        # 尾中
		Vector2(8, 12),        # 右尾
		Vector2(28, 16),       # 右引擎
		Vector2(20, -12),      # 右翼
	])
	draw_colored_polygon(ship, body_color)
	draw_polyline(ship, Color(0.1, 0.1, 0.1, 0.5), 2.0, true)

	# 驾驶舱
	draw_circle(Vector2(0, -10), 6, body_color.lightened(0.3))
	draw_circle(Vector2(0, -10), 6, Color(0.1, 0.1, 0.1, 0.3), false, 1.0)

	# ---- 绘制武器 ----
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w == null:
			continue
		var offset = SLOT_OFFSETS[i]
		var angle = _slot_angles[i]
		_draw_weapon(w, offset, angle)

	# 激光持续射线（有目标且在激光射程内时一直显示）
	if is_instance_valid(_current_target):
		var has_laser := false
		for w in _slot_weapons:
			if w != null and w.weapon_type == Weapon.WeaponType.LASER:
				has_laser = true
				break
		if has_laser:
			var dist = global_position.distance_to(_current_target.global_position)
			if dist <= 800.0:  # 约等于激光射程
				var end = _current_target.global_position - global_position
				# 外层光晕
				draw_line(Vector2.ZERO, end, Color(1.0, 0.15, 0.15, 0.25), 6.0)
				# 主光束
				draw_line(Vector2.ZERO, end, Color(1.0, 0.2, 0.2, 0.7), 2.0)
				# 核心亮线
				draw_line(Vector2.ZERO, end, Color(1.0, 0.7, 0.7, 0.4), 0.8)

	# PD 持续弹道（有目标时一直显示）
	if _pd_has_target:
		var end = _pd_target_pos - global_position
		# 外层光晕
		draw_line(Vector2.ZERO, end, Color(0.15, 0.8, 0.5, 0.25), 5.0)
		# 主光束
		draw_line(Vector2.ZERO, end, Color(0.2, 1.0, 0.7, 0.6), 2.0)
		# 核心亮线
		draw_line(Vector2.ZERO, end, Color(0.5, 1.0, 0.8, 0.4), 0.8)

	# ---- 护盾条 & 结构条 ----
	var bar_width = 64.0
	var bar_half = bar_width / 2.0

	# 护盾条（蓝色，上方）
	if shield < max_shield:
		draw_rect(Rect2(-bar_half, -44.0, bar_width, 4.0), Color(0.15, 0.15, 0.2, 0.8), true)
		draw_rect(Rect2(-bar_half, -44.0, bar_width * shield / max_shield, 4.0), Color(0.2, 0.5, 1.0, 0.9), true)

	# 结构条（绿色→黄色→红色）
	if hull < max_hull:
		draw_rect(Rect2(-bar_half, -38.0, bar_width, 5.0), Color(0.15, 0.15, 0.2, 0.8), true)
		var hull_pct = hull / max_hull
		var hull_color: Color
		if hull_pct > 0.5:
			hull_color = Color(0.2, 1.0, 0.3)
		elif hull_pct > 0.25:
			hull_color = Color(1.0, 0.8, 0.2)
		else:
			hull_color = Color(1.0, 0.2, 0.2)
		draw_rect(Rect2(-bar_half, -38.0, bar_width * hull_pct, 5.0), hull_color, true)

	# 选中标记
	if is_selected:
		var sel_rect = Rect2(-38, -38, 76, 76)
		draw_rect(sel_rect, Color(0.2, 1.0, 0.4, 0.6), false, 2.0)
		var corner_len = 10
		var d = 38
		draw_line(Vector2(-d, -d + corner_len), Vector2(-d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, -d), Vector2(-d + corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, -d + corner_len), Vector2(d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, -d), Vector2(d - corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, d - corner_len), Vector2(-d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, d), Vector2(-d + corner_len, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, d - corner_len), Vector2(d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, d), Vector2(d - corner_len, d), Color(0.2, 1.0, 0.4), 2.0)


func _draw_weapon(w: Weapon, offset: Vector2, angle: float) -> void:
	"""在指定偏移和角度绘制武器外观"""
	var barrel_len: float
	var barrel_width: float
	var color: Color

	match w.weapon_type:
		Weapon.WeaponType.BULLET:
			barrel_len = 16.0
			barrel_width = 5.0
			color = Color(0.5, 0.5, 0.3)
		Weapon.WeaponType.MISSILE:
			barrel_len = 24.0
			barrel_width = 10.0
			color = Color(0.6, 0.25, 0.1)
		Weapon.WeaponType.LASER:
			barrel_len = 14.0
			barrel_width = 4.0
			color = Color(0.7, 0.1, 0.1)
		Weapon.WeaponType.PD:
			barrel_len = 8.0
			barrel_width = 3.0
			color = Color(0.1, 0.8, 0.5)

	# 底座
	draw_circle(offset, barrel_width * 0.7, color.darkened(0.3))

	# 炮管（从底座向外延伸）
	var tip = offset + Vector2.RIGHT.rotated(angle) * barrel_len
	var half_w = Vector2.UP.rotated(angle) * barrel_width * 0.5
	var pts = PackedVector2Array([
		offset + half_w,
		offset - half_w,
		tip - half_w * 0.5,
		tip + half_w * 0.5,
	])
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([offset + half_w, offset - half_w, tip - half_w * 0.5, tip + half_w * 0.5]),
		Color.BLACK, 1.0, true)

	# 激光武器加发光点
	if w.weapon_type == Weapon.WeaponType.LASER:
		draw_circle(tip, 2.0, Color(1.0, 0.3, 0.3, 0.7))

class_name Unit
extends Area2D

enum Team { BLUE, RED }

@export var speed: float = 200.0
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE
@export var max_health: float = 100.0

## 武器槽数量（1-8）
@export var slot_count: int = 2

## 是否被选中（仅蓝队有效）
var is_selected: bool = false : set = _set_is_selected

var health: float
## 指向主场景中所有单位的共享数组
var _all_units: Array[Unit] = []

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

# ----- 武器槽位 -----
## 槽位武器（null 表示空槽）
var _slot_weapons: Array = []
## 槽位当前旋转角（弧度）
var _slot_angles: Array[float] = []
## 槽位冷却计时器
var _slot_cooldowns: Array[float] = []

## 8 个槽位在单位周围的偏移位置（64x64 单位）
const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(0, -36),     # 0: 上
	Vector2(25, -25),    # 1: 右上
	Vector2(36, 0),      # 2: 右
	Vector2(25, 25),     # 3: 右下
	Vector2(0, 36),      # 4: 下
	Vector2(-25, 25),    # 5: 左下
	Vector2(-36, 0),     # 6: 左
	Vector2(-25, -25),   # 7: 左上
]

# ----- 攻击指令相关 -----
var _explicit_attack_target: Unit = null
var _attack_move_destination: Vector2
var _is_attack_move: bool = false
var _saved_move_target: Vector2
var _has_saved_move: bool = false

# 激光视觉效果
var _laser_target_pos: Vector2
var _laser_flash_timer: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	health = max_health

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
	_laser_flash_timer = max(0.0, _laser_flash_timer - delta)

	# ---- 冷却更新 ----
	for i in range(slot_count):
		_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - delta)

	# 清理无效的明确攻击目标
	if is_instance_valid(_explicit_attack_target) and _explicit_attack_target.health <= 0:
		_explicit_attack_target = null

	# 清理无效的当前目标
	if is_instance_valid(_current_target) and _current_target.health <= 0:
		_current_target = null

	# ---- 目标获取 ----
	if _current_target == null:
		if _explicit_attack_target != null:
			_current_target = _explicit_attack_target
		else:
			if team == Team.RED:
				_current_target = _find_nearest_enemy()
			elif _is_attack_move:
				_current_target = _find_nearest_enemy()
			elif team == Team.BLUE:
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
	if _current_target != null and max_range > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= max_range:
			# 在射程内：边移动边开火（不打断移动）
			for i in range(slot_count):
				var w = _slot_weapons[i]
				if w != null and dist <= w.range and _slot_cooldowns[i] <= 0.0:
					_fire_slot(i, _current_target)
					_slot_cooldowns[i] = w.cooldown
		else:
			# 判断是否需要追击
			var should_chase := false
			if team == Team.RED:
				should_chase = true
			elif _explicit_attack_target != null:
				should_chase = true
			elif _is_attack_move:
				should_chase = true
			elif not _is_moving:
				# 空闲时自动追击
				should_chase = true

			if should_chase:
				# 追击到最大射程边缘
				var to_target = _current_target.global_position - global_position
				var dir = to_target.normalized()
				_target_position = _current_target.global_position - dir * max_range * 0.85
				_is_moving = true
			# 纯移动指令不追击，继续走原路线
			# 移动中的非追击单位：目标超出射程则清除，下次帧会重新获取
			if not should_chase and is_instance_valid(_current_target):
				if global_position.distance_to(_current_target.global_position) > max_range * 1.2:
					_current_target = null
	elif _current_target == null:
		if _has_saved_move:
			_target_position = _saved_move_target
			_is_moving = true
			_has_saved_move = false

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
			_laser_target_pos = target.global_position
			_laser_flash_timer = 0.08

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			_spawn_projectile(fire_pos, fire_dir, target, w)


func _spawn_projectile(from_pos: Vector2, direction: Vector2, target: Unit, w: Weapon) -> void:
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.global_position = from_pos
	proj.setup({
		"speed": w.projectile_speed,
		"damage": w.damage,
		"direction": direction,
		"target": target,
		"team": team,
		"source": self,
		"is_homing": w.is_homing,
		"color": w.projectile_color,
		"size": w.projectile_size,
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
		if other == self or not is_instance_valid(other) or other.health <= 0:
			continue
		var to_other = global_position - other.global_position
		var dist = to_other.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			separation += to_other.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS

	var velocity = desired_velocity + separation * speed * 1.5
	if velocity.length() > speed:
		velocity = velocity.normalized() * speed

	global_position += velocity * delta


func _find_nearest_enemy() -> Unit:
	var nearest: Unit = null
	var nearest_dist = INF
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.health <= 0:
			continue
		if other.team == team:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func take_damage(amount: float, attacker: Unit = null) -> void:
	health -= amount

	if attacker != null and team == Team.BLUE:
		if is_instance_valid(attacker) and attacker.health > 0 and attacker.team != team:
			if _current_target == null:
				if _is_moving and not _is_attack_move:
					_saved_move_target = _target_position
					_has_saved_move = true
				_current_target = attacker
				_explicit_attack_target = null
				_is_attack_move = false

	if health <= 0:
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
	_has_saved_move = false


func attack_target(target: Unit) -> void:
	_current_target = target
	_explicit_attack_target = target
	_is_moving = true
	_is_attack_move = false
	_has_saved_move = false
	_target_position = target.global_position


func attack_move_to(destination: Vector2) -> void:
	_target_position = destination
	_attack_move_destination = destination
	_is_attack_move = true
	_is_moving = true
	_explicit_attack_target = null
	_has_saved_move = false
	_current_target = _find_nearest_enemy()


func stop() -> void:
	_is_moving = false


func _set_is_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	# 单位本体
	var rect = Rect2(-32, -32, 64, 64)
	var base_color = unit_color
	if is_selected:
		base_color = Color(0.5, 0.7, 1.0)
	draw_rect(rect, base_color, true)
	draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), false, 2.0)

	# ---- 绘制武器 ----
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w == null:
			continue
		var offset = SLOT_OFFSETS[i]
		var angle = _slot_angles[i]
		_draw_weapon(w, offset, angle)

	# 激光射线（瞬闪效果）
	if _laser_flash_timer > 0.0:
		var alpha = _laser_flash_timer / 0.08
		var laser_color = Color(1.0, 0.2, 0.2, alpha)
		var end = _laser_target_pos - global_position
		draw_line(Vector2.ZERO, end, laser_color, 2.0)
		draw_line(Vector2.ZERO, end, Color.WHITE, 0.5)

	# 血条
	if health < max_health:
		var bar_width = 64.0
		var bar_height = 6.0
		var bar_y = -40.0
		draw_rect(Rect2(-bar_width / 2, bar_y, bar_width, bar_height), Color(0.2, 0.2, 0.2, 0.8), true)
		var health_pct = health / max_health
		var fill_color: Color
		if health_pct > 0.5:
			fill_color = Color.GREEN
		elif health_pct > 0.25:
			fill_color = Color.YELLOW
		else:
			fill_color = Color.RED
		draw_rect(Rect2(-bar_width / 2, bar_y, bar_width * health_pct, bar_height), fill_color, true)

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

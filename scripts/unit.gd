class_name Unit
extends Area2D

enum Team { BLUE, RED }

@export var speed: float = 200.0
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE
@export var max_health: float = 100.0

## 当前装备的武器
@export var weapon: Weapon

## 是否被选中（仅蓝队有效）
var is_selected: bool = false : set = _set_is_selected

var health: float
## 指向主场景中所有单位的共享数组
var _all_units: Array[Unit] = []

var _target_position: Vector2
var _is_moving: bool = false
var _attack_timer: float = 0.0
var _current_target: Unit = null

# ----- 攻击指令相关 -----
## 玩家明确指定的攻击目标（右键/A+左键点敌）
var _explicit_attack_target: Unit = null
## 攻击移动（A+左键地面）的目标位置
var _attack_move_destination: Vector2
var _is_attack_move: bool = false
## 反击前保存的移动目标（用于反击结束后继续移动）
var _saved_move_target: Vector2
var _has_saved_move: bool = false

# 激光视觉效果
var _laser_target_pos: Vector2
var _laser_flash_timer: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	health = max_health
	# 确保有默认武器
	if weapon == null:
		weapon = Weapon.create_bullet()

	var shape = RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	collision_shape.shape = shape


func _process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	_laser_flash_timer = max(0.0, _laser_flash_timer - delta)

	# 清理无效的明确攻击目标
	if is_instance_valid(_explicit_attack_target) and _explicit_attack_target.health <= 0:
		_explicit_attack_target = null

	# 清理无效的当前目标
	if is_instance_valid(_current_target) and _current_target.health <= 0:
		_current_target = null

	# ---- 目标获取 ----
	if _current_target == null:
		# 优先：玩家明确指定的攻击目标
		if _explicit_attack_target != null:
			_current_target = _explicit_attack_target
		else:
			# 红队永远自动寻敌
			if team == Team.RED:
				_current_target = _find_nearest_enemy()
			# 蓝队在攻击移动模式下自动寻敌
			elif _is_attack_move:
				_current_target = _find_nearest_enemy()
			# 蓝队空闲时自动寻敌（普通移动时不打断）
			elif team == Team.BLUE and not _is_moving:
				_current_target = _find_nearest_enemy()

	# ---- 战斗 / 追击 ----
	if _current_target != null and weapon != null:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= weapon.range:
			# 在攻击范围内：开火
			if _attack_timer <= 0.0:
				_attack(_current_target)
				_attack_timer = weapon.cooldown
			_is_moving = false
		else:
			# 追击目标：移动到射程边缘即可
			var to_target = _current_target.global_position - global_position
			var dir = to_target.normalized()
			_target_position = _current_target.global_position - dir * weapon.range * 0.85
			_is_moving = true
	elif _current_target == null:
		# 没有目标：如果之前存了移动目标则恢复移动
		if _has_saved_move:
			_target_position = _saved_move_target
			_is_moving = true
			_has_saved_move = false

	# ---- 移动 ----
	if _is_moving:
		_move_toward_target(delta)

		# 攻击移动模式下，到达目的地且无目标时停下
		if _is_attack_move and _current_target == null:
			if global_position.distance_to(_attack_move_destination) < 4.0:
				_is_attack_move = false
				_is_moving = false
		# 普通移动到达目的地
		elif not _is_attack_move and _current_target == null:
			if global_position.distance_to(_target_position) < 4.0:
				_is_moving = false

	queue_redraw()


func _move_toward_target(delta: float) -> void:
	var distance = global_position.distance_to(_target_position)
	if distance < 4.0:
		_is_moving = false
		return

	var direction = (_target_position - global_position).normalized()
	var desired_velocity = direction * speed

	# 碰撞回避：与其他单位保持距离
	var separation = Vector2.ZERO
	const SEPARATION_RADIUS: float = 40.0
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


func _attack(target: Unit) -> void:
	if weapon == null:
		return

	match weapon.weapon_type:
		Weapon.WeaponType.LASER:
			# 激光：瞬间命中，传递 self 以支持反击
			target.take_damage(weapon.damage, self)
			_laser_target_pos = target.global_position
			_laser_flash_timer = 0.08

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			_spawn_projectile(target)


func _spawn_projectile(target: Unit) -> void:
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position
	proj.setup({
		"speed": weapon.projectile_speed,
		"damage": weapon.damage,
		"direction": (target.global_position - global_position).normalized(),
		"target": target,
		"team": team,
		"source": self,
		"is_homing": weapon.is_homing,
		"color": weapon.projectile_color,
		"size": weapon.projectile_size,
	})
	get_tree().root.add_child(proj)


## 受到伤害（attacker 用于触发反击）
func take_damage(amount: float, attacker: Unit = null) -> void:
	health -= amount

	# 蓝队受击反击逻辑
	if attacker != null and team == Team.BLUE:
		if is_instance_valid(attacker) and attacker.health > 0 and attacker.team != team:
			# 如果当前没有攻击目标（纯移动或空闲），保存移动状态并反击
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


## 普通移动到指定位置（清除所有攻击状态）
func move_to(target: Vector2) -> void:
	_target_position = target
	_is_moving = true
	_current_target = null
	_explicit_attack_target = null
	_is_attack_move = false
	_has_saved_move = false


## 攻击指定敌方单位
func attack_target(target: Unit) -> void:
	_current_target = target
	_explicit_attack_target = target
	_is_moving = true
	_is_attack_move = false
	_has_saved_move = false
	_target_position = target.global_position


## 攻击移动：移动到目标位置，途中自动攻击遇到的敌人
func attack_move_to(destination: Vector2) -> void:
	_target_position = destination
	_attack_move_destination = destination
	_is_attack_move = true
	_is_moving = true
	_explicit_attack_target = null
	_has_saved_move = false
	# 立即扫描附近敌人
	_current_target = _find_nearest_enemy()


func stop() -> void:
	_is_moving = false


func _set_is_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	# 单位本体
	var rect = Rect2(-16, -16, 32, 32)
	var base_color = unit_color
	if is_selected:
		base_color = Color(0.5, 0.7, 1.0)
	draw_rect(rect, base_color, true)
	draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), false, 2.0)

	# 武器图标（小标记显示在单位上方）
	if weapon != null:
		var icon_y = -24
		match weapon.weapon_type:
			Weapon.WeaponType.BULLET:
				draw_circle(Vector2(0, icon_y), 2.5, Color.YELLOW)
			Weapon.WeaponType.MISSILE:
				var pts = PackedVector2Array([
					Vector2(0, icon_y - 3),
					Vector2(-3, icon_y + 2),
					Vector2(3, icon_y + 2),
				])
				draw_colored_polygon(pts, Color.ORANGE_RED)
			Weapon.WeaponType.LASER:
				draw_rect(Rect2(-2, icon_y - 3, 4, 6), Color.RED, true)

	# 激光射线（瞬闪效果）
	if _laser_flash_timer > 0.0:
		var alpha = _laser_flash_timer / 0.08
		var laser_color = Color(1.0, 0.2, 0.2, alpha)
		var end = _laser_target_pos - global_position
		draw_line(Vector2.ZERO, end, laser_color, 2.0)
		draw_line(Vector2.ZERO, end, Color.WHITE, 0.5)

	# 血条（受伤时显示）
	if health < max_health:
		var bar_width = 32.0
		var bar_height = 4.0
		var bar_y = -20.0
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
		var sel_rect = Rect2(-20, -20, 40, 40)
		draw_rect(sel_rect, Color(0.2, 1.0, 0.4, 0.6), false, 2.0)
		var corner_len = 6
		var d = 20
		draw_line(Vector2(-d, -d + corner_len), Vector2(-d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, -d), Vector2(-d + corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, -d + corner_len), Vector2(d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, -d), Vector2(d - corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, d - corner_len), Vector2(-d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, d), Vector2(-d + corner_len, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, d - corner_len), Vector2(d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, d), Vector2(d - corner_len, d), Color(0.2, 1.0, 0.4), 2.0)

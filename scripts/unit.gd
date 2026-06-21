class_name Unit
extends Area2D

enum Team { BLUE, RED }

@export var speed: float = 200.0
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE
@export var max_health: float = 100.0
@export var attack_damage: float = 12.0
@export var attack_range: float = 64.0
@export var attack_cooldown: float = 0.7

## 是否被选中（仅蓝队有效）
var is_selected: bool = false : set = _set_is_selected

var health: float
## 指向主场景中所有单位的共享数组
var _all_units: Array[Unit] = []

var _target_position: Vector2
var _is_moving: bool = false
var _attack_timer: float = 0.0
var _current_target: Unit = null

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	health = max_health
	var shape = RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	collision_shape.shape = shape


func _process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	# 校验当前攻击目标是否还活着
	if not is_instance_valid(_current_target) or _current_target.health <= 0:
		_current_target = _find_nearest_enemy()

	# 战斗逻辑
	if is_instance_valid(_current_target):
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= attack_range:
			# 在攻击范围内：攻击
			if _attack_timer <= 0.0:
				_attack(_current_target)
				_attack_timer = attack_cooldown
			_is_moving = false
		elif team == Team.RED:
			# 红队 AI：追击最近的敌人
			_target_position = _current_target.global_position
			_is_moving = true

	# 移动
	if _is_moving:
		_move_toward_target(delta)

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
	target.take_damage(attack_damage)


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0:
		_die()


func _die() -> void:
	_all_units.erase(self)
	queue_free()


## 玩家命令：移动到指定位置
func move_to(target: Vector2) -> void:
	_target_position = target
	_is_moving = true
	_current_target = null


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

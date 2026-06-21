class_name Projectile
extends Area2D

## 飞行速度
var speed: float = 500.0
## 伤害值
var damage: float = 10.0
## 飞行方向（子弹用）
var _direction: Vector2 = Vector2.RIGHT
## 追踪目标（导弹用）
var _target_unit: Unit = null
## 弹体所属阵营
var team: Unit.Team
## 发射者（用于反击）
var source: Unit = null
## 是否追踪
var is_homing: bool = false
## 弹体颜色
var projectile_color: Color = Color.YELLOW
## 弹体半径
var projectile_size: float = 4.0
## 弹体生命值（PD可消耗）
var hp: float = 5.0

var _lifetime: float

const CFG = preload("res://scripts/game_config.gd")


func _ready() -> void:
	_lifetime = CFG.PROJECTILE_LIFETIME
	add_to_group("projectiles")

	# 设置圆形碰撞
	var shape = CircleShape2D.new()
	shape.radius = projectile_size
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	# 连接碰撞信号
	area_entered.connect(_on_area_entered)


func setup(config: Dictionary) -> void:
	speed = config.get("speed", 500.0)
	damage = config.get("damage", 10.0)
	_direction = config.get("direction", Vector2.RIGHT)
	_target_unit = config.get("target", null)
	team = config.get("team", Unit.Team.BLUE)
	source = config.get("source", null)
	is_homing = config.get("is_homing", false)
	projectile_color = config.get("color", Color.YELLOW)
	projectile_size = config.get("size", 4.0)
	hp = config.get("hp", 5.0)


func _process(delta: float) -> void:
	_lifetime -= delta

	# 追踪模式下更新方向
	if is_homing and is_instance_valid(_target_unit) and _target_unit.hull > 0:
		_direction = (_target_unit.global_position - global_position).normalized()
		# 追踪弹略微调整角度
		var angle = _direction.angle()
		rotation = angle

	# 移动
	global_position += _direction * speed * delta

	# 超时或飞出边界则销毁
	if _lifetime <= 0:
		queue_free()
		return

	var pos = global_position
	if pos.x < -500 or pos.x > 2000 or pos.y < -500 or pos.y > 1500:
		queue_free()

	queue_redraw()


func _on_area_entered(other_area: Area2D) -> void:
	if not other_area is Unit:
		return

	var other_unit: Unit = other_area as Unit

	# 不打同阵营
	if other_unit.team == team:
		return

	# 不打已死的
	if other_unit.hull <= 0:
		return

	# 造成伤害（传递来源以支持反击，检查 source 是否还存活）
	if is_instance_valid(source):
		other_unit.take_damage(damage, source)
	else:
		other_unit.take_damage(damage)
	queue_free()


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()


func _draw() -> void:
	if is_homing:
		# 导弹：圆形 + 尾焰
		draw_circle(Vector2.ZERO, projectile_size, projectile_color)
		draw_circle(Vector2.ZERO, projectile_size * 0.5, Color.WHITE)
		# 尾迹
		var tail = -_direction * projectile_size * 2
		draw_line(Vector2.ZERO, tail, projectile_color, projectile_size * 0.8)
	else:
		# 子弹：小圆点 + 拖尾
		draw_circle(Vector2.ZERO, projectile_size, projectile_color)
		draw_circle(Vector2.ZERO, projectile_size * 0.4, Color.WHITE)
		var tail = -_direction * projectile_size * 3
		draw_line(Vector2.ZERO, tail, projectile_color.lightened(0.3), projectile_size * 0.5)

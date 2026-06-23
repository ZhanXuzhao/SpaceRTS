class_name Projectile
extends Area2D

## ����ٶ�
var max_speed: float = 500.0
## ���ٶ�
var acceleration: float = 3000.0
## ��ǰ�ٶ�����
var velocity: Vector2
## �˺�ֵ
var damage: float = 10.0
## ���з����ӵ��ã�
var _direction: Vector2 = Vector2.RIGHT
## ׷��Ŀ�꣨�����ã�
var _target_unit: Unit = null
## ����������Ӫ
var team: Unit.Team
## �����ߣ����ڷ�����
var source: Unit = null
## �Ƿ�׷��
var is_homing: bool = false
## ������ɫ
var projectile_color: Color = Color.YELLOW
## ����뾶
var projectile_size: float = 4.0
## ��������ֵ��PD�����ģ�
var hp: float = 5.0

var _lifetime: float = 3.0  # Ĭ��ֵ��setup() �Ḳ��
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("projectiles")
	_sprite = $Sprite2D
	_sprite.self_modulate = projectile_color

	# ����Բ����ײ
	var shape = CircleShape2D.new()
	shape.radius = projectile_size
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	# ������ײ�ź�
	area_entered.connect(_on_area_entered)


func setup(config: Dictionary) -> void:
	max_speed = config.get("max_speed", 500.0)
	acceleration = config.get("acceleration", 3000.0)
	damage = config.get("damage", 10.0)
	_direction = config.get("direction", Vector2.RIGHT)
	_target_unit = config.get("target", null)
	team = config.get("team", Unit.Team.BLUE)
	source = config.get("source", null)
	is_homing = config.get("is_homing", false)
	projectile_color = config.get("color", Color.YELLOW)
	projectile_size = config.get("size", 4.0)
	hp = config.get("hp", 5.0)
	if config.has("lifetime"):
		_lifetime = config.get("lifetime")


func _process(delta: float) -> void:
	_lifetime -= delta

	if _direction.length() > 0:
		_sprite.rotation = _direction.angle()

	# ׷��ģʽ�¸��·���
	if is_homing and is_instance_valid(_target_unit) and _target_unit.hull > 0:
		_direction = (_target_unit.global_position - global_position).normalized()
		_sprite.rotation = _direction.angle()

	# �㶨����ٶ��ƶ��������Ǽ��ٶȣ�
	velocity = _direction * max_speed
	global_position += velocity * delta

	# ��ʱ��ɳ��߽�������
	if _lifetime <= 0:
		queue_free()
		return

	queue_redraw()


func _on_area_entered(other_area: Area2D) -> void:
	if not other_area is Unit:
		return

	var other_unit: Unit = other_area as Unit

	# Ŀ������ѱ��ͷţ�ȷ��ʵ����Ȼ��Ч
	if not is_instance_valid(other_unit):
		return

	# ����ͬ��Ӫ
	if other_unit.team == team:
		return

	# ����������
	if other_unit.hull <= 0:
		return

	# ����˺���������Դ��֧�ַ�������� source �Ƿ񻹴�
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
		_sprite.rotation = _direction.angle()
		_sprite.visible = true
	else:
		# �ӵ���СԲ�� + ��β
		draw_circle(Vector2.ZERO, projectile_size, projectile_color)
		draw_circle(Vector2.ZERO, projectile_size * 0.4, Color.WHITE)
		var tail = -_direction * projectile_size * 3
		draw_line(Vector2.ZERO, tail, projectile_color.lightened(0.3), projectile_size * 0.5)

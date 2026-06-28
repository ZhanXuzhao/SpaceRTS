class_name EmpArea
extends Area2D

## EMP 区域效果
## 在目标位置创建，持续 10 秒，每秒对范围内敌方单位造成 100 护盾伤害

const EMP_TEX := preload("res://assets/emp.png")

var _team: String
var _duration: float = GameConfig.SKILL_EMP_DURATION
var _tick_timer: float = 0.0
var _rotation_speed: float = 180.0  # 度/秒（每秒 0.5 圈）

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_sprite.texture = EMP_TEX
	_sprite.centered = true

	# EMP 图层放在飞船之下
	z_index = -1

	# 圆形碰撞区域，匹配 EMP 半径
	var circle := CircleShape2D.new()
	circle.radius = GameConfig.SKILL_EMP_RADIUS
	_collision.shape = circle

	# Sprite 缩放至技能范围大小（根据贴图实际像素尺寸计算）
	var tex_size = EMP_TEX.get_size()
	var diameter = GameConfig.SKILL_EMP_RADIUS * 2.0
	var max_dim = max(tex_size.x, tex_size.y, 1.0)
	_sprite.scale = Vector2.ONE * (diameter / max_dim)

	# 只检测 Unit（layer 1）
	collision_mask = 1
	collision_layer = 0


func _process(delta: float) -> void:
	_duration -= delta
	_tick_timer -= delta

	# 旋转动画（逆时针）
	_sprite.rotation -= deg_to_rad(_rotation_speed * delta)

	if _duration <= 0.0:
		queue_free()
		return

	# 每秒造成护盾伤害
	if _tick_timer <= 0.0:
		_tick_timer = 1.0
		_apply_shield_damage()


func setup(team: String) -> void:
	_team = team
	_tick_timer = 0.0  # 立即造成一次伤害


func _apply_shield_damage() -> void:
	var areas = get_overlapping_areas()
	for area in areas:
		if not is_instance_valid(area):
			continue
		if not area.has_method("take_shield_damage"):
			continue
		if area.team == _team:
			continue
		area.take_shield_damage(GameConfig.SKILL_EMP_SHIELD_DMG)

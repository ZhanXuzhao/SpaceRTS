class_name MineralField
extends Area2D

## 矿物总量
var mineral_amount: float = GameConfig.MINERAL_FIELD_AMOUNT
## 初始总量（用于显示百分比）
var max_amount: float = GameConfig.MINERAL_FIELD_AMOUNT
## 矿物半径（随采集逐渐缩小）
var field_radius: float = GameConfig.MINERAL_FIELD_RADIUS
## 所属阵营（"" 表示中立，可被任何队伍采集）
var team: String = ""

signal field_depleted(field)

@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _body: Node2D = $Body
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_update_visual()


func _process(delta: float) -> void:
	# 缓慢地闪烁/脉冲效果（仅视觉）
	pass


## 被采矿船采集 amount 矿物，返回实际采集量
func mine(amount: float) -> float:
	var actual = min(amount, mineral_amount)
	mineral_amount -= actual
	_update_visual()
	if mineral_amount <= 0:
		emit_signal("field_depleted", self)
		queue_free()
	return actual


func _update_visual() -> void:
	var pct = mineral_amount / max_amount
	var scale = 0.5 + pct * 0.5
	_body.scale = Vector2(scale, scale)

	# 根据剩余量调整颜色：满→亮青，空→暗灰
	var color = Color(0.3, 0.8 + pct * 0.2, 0.7 + pct * 0.3, 0.6 + pct * 0.4)
	_sprite.self_modulate = color

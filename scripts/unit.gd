class_name Unit
extends Area2D

## 单位移动速度
@export var speed: float = 200.0
@export var unit_color: Color = Color(0.2, 0.6, 1.0)

## 是否被选中
var is_selected: bool = false :
	set(value):
		is_selected = value
		queue_redraw()

## 当前移动目标位置
var _target_position: Vector2 = Vector2.ZERO
var _is_moving: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# 设置碰撞形状大小
	var shape = RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	collision_shape.shape = shape
	# 确保可以接收输入
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta: float) -> void:
	if not _is_moving:
		return

	var distance = position.distance_to(_target_position)
	if distance < 2.0:
		_is_moving = false
		return

	var direction = (_target_position - position).normalized()
	position += direction * speed * delta


func _draw() -> void:
	# 绘制单位本体（32x32 圆角方块）
	var rect = Rect2(-16, -16, 32, 32)
	var base_color = unit_color if not is_selected else Color(0.8, 0.9, 1.0)
	draw_rect(rect, base_color, true)
	draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), false, 2.0)

	# 选中时绘制外发光边框
	if is_selected:
		var sel_rect = Rect2(-20, -20, 40, 40)
		draw_rect(sel_rect, Color(0.2, 1.0, 0.4, 0.6), false, 2.0)
		# 四个角的小标记
		var corner_len = 6
		var d = 20
		# 左上角
		draw_line(Vector2(-d, -d + corner_len), Vector2(-d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, -d), Vector2(-d + corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		# 右上角
		draw_line(Vector2(d, -d + corner_len), Vector2(d, -d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, -d), Vector2(d - corner_len, -d), Color(0.2, 1.0, 0.4), 2.0)
		# 左下角
		draw_line(Vector2(-d, d - corner_len), Vector2(-d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(-d, d), Vector2(-d + corner_len, d), Color(0.2, 1.0, 0.4), 2.0)
		# 右下角
		draw_line(Vector2(d, d - corner_len), Vector2(d, d), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(Vector2(d, d), Vector2(d - corner_len, d), Color(0.2, 1.0, 0.4), 2.0)


## 命令单位移动到指定世界坐标
func move_to(target: Vector2) -> void:
	_target_position = target
	_is_moving = true


## 停止移动
func stop() -> void:
	_is_moving = false


func _on_mouse_entered() -> void:
	# 鼠标悬停效果
	if not is_selected:
		modulate = Color(1, 1, 1, 0.8)


func _on_mouse_exited() -> void:
	if not is_selected:
		modulate = Color.WHITE

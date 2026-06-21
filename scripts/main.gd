extends Node2D

## 单位预制场景
@export var unit_scene: PackedScene

## 蓝队（玩家控制）数量
@export var blue_count: int = 6
## 红队（AI 控制）数量
@export var red_count: int = 4

var _units: Array[Unit] = []

# ----- 框选状态 -----
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

# ----- 选中单位集合 -----
var _selected_units: Array[Unit] = []


func _ready() -> void:
	_spawn_units()


func _input(event: InputEvent) -> void:
	# ---- 左键按下：开始框选 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_start = event.position
			_drag_end = event.position
			# 如果没按 Shift，清空之前的选中
			if not Input.is_key_pressed(KEY_SHIFT):
				_clear_selection()
		else:
			# 左键松开：结束框选
			_is_dragging = false
			_apply_selection()
			queue_redraw()

	# ---- 鼠标移动（拖拽中更新选框） ----
	if event is InputEventMouseMotion and _is_dragging:
		_drag_end = event.position
		queue_redraw()

	# ---- 右键：移动选中单位 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _selected_units.size() > 0:
			var world_pos = get_global_mouse_position()
			for unit in _selected_units:
				unit.move_to(world_pos)


func _draw() -> void:
	if not _is_dragging:
		return

	var rect = _get_drag_rect()
	if rect.has_area():
		# 绘制半透明蓝色选框
		draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
		draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)


func _get_drag_rect() -> Rect2:
	return Rect2(
		Vector2(
			min(_drag_start.x, _drag_end.x),
			min(_drag_start.y, _drag_end.y)
		),
		Vector2(
			abs(_drag_end.x - _drag_start.x),
			abs(_drag_end.y - _drag_start.y)
		)
	)


func _apply_selection() -> void:
	var drag_rect = _get_drag_rect()

	# 如果拖拽距离太小视为点击选单个单位
	if drag_rect.size.length() < 10.0:
		var click_pos = _drag_start
		for unit in _units:
			# 只能选中蓝队单位
			if unit.team != Unit.Team.BLUE:
				continue
			var unit_rect = _get_unit_screen_rect(unit)
			if unit_rect and unit_rect.has_point(click_pos):
				unit.is_selected = true
				if unit not in _selected_units:
					_selected_units.append(unit)
				return
		# 点空了
		_clear_selection()
		return

	# 框选：选中选框内所有蓝队单位
	for unit in _units:
		if unit.team != Unit.Team.BLUE:
			continue
		var unit_screen_pos = _to_screen(unit.global_position)
		if drag_rect.has_point(unit_screen_pos):
			if not unit.is_selected:
				unit.is_selected = true
				_selected_units.append(unit)


func _get_unit_screen_rect(unit: Unit) -> Rect2:
	if unit.collision_shape == null or unit.collision_shape.shape == null:
		return Rect2()
	var shape: RectangleShape2D = unit.collision_shape.shape as RectangleShape2D
	var half_size = shape.size / 2.0
	var screen_pos = _to_screen(unit.global_position)
	return Rect2(screen_pos - half_size, shape.size)


func _to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform * world_pos


func _clear_selection() -> void:
	for unit in _selected_units:
		unit.is_selected = false
	_selected_units.clear()


func _spawn_units() -> void:
	if unit_scene == null:
		push_error("请将 unit.tscn 拖入 Main 节点的 Unit Scene 属性！")
		return

	# 生成蓝队（玩家）——左侧
	for i in range(blue_count):
		var unit = _create_unit(Unit.Team.BLUE)
		unit.position = Vector2(randf_range(80, 350), randf_range(80, 520))

	# 生成红队（AI）——右侧
	for i in range(red_count):
		var unit = _create_unit(Unit.Team.RED)
		unit.position = Vector2(randf_range(450, 720), randf_range(80, 520))


func _create_unit(team: Unit.Team) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	unit.team = team
	if team == Unit.Team.BLUE:
		unit.unit_color = Color(0.2, 0.5, 1.0)  # 蓝色
	else:
		unit.unit_color = Color(1.0, 0.25, 0.25)  # 红色
	# 随机分配武器
	unit.weapon = _random_weapon()
	# 共享所有单位的引用，用于碰撞回避和寻敌
	unit._all_units = _units
	add_child(unit)
	_units.append(unit)
	return unit


func _random_weapon() -> Weapon:
	var roll = randi() % 3
	match roll:
		0: return Weapon.create_bullet()
		1: return Weapon.create_missile()
		2: return Weapon.create_laser()
	return Weapon.create_bullet()

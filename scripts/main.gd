extends Node2D

## 单位预制场景
@export var unit_scene: PackedScene

## 蓝队（玩家控制）数量
@export var blue_count: int = 2
## 红队（AI 控制）数量
@export var red_count: int = 2

var _units: Array[Unit] = []

# ----- 框选状态 -----
var _is_dragging: bool = false
## 拖拽起止点（世界坐标）
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

# ----- 选中单位集合 -----
var _selected_units: Array[Unit] = []

# ----- A 键攻击模式 -----
var _attack_cursor_mode: bool = false

# ----- 相机 -----
var _camera: Camera2D
var _zoom_target: float = 1.0
var _minimap_node: Node2D

# ----- 游戏结束状态 -----
var _game_over: bool = false
var _winner: String = ""

# ----- 暂停 -----
var _paused: bool = false


func _ready() -> void:
	# 全屏：先设窗口尺寸匹配屏幕，再全屏
	var screen_size = DisplayServer.screen_get_size()
	get_window().size = screen_size
	get_window().mode = Window.MODE_FULLSCREEN

	# 相机
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.global_position = Vector2(400, 300)
	add_child(_camera)
	_camera.make_current()

	# 小地图（CanvasLayer 不受相机影响）
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MinimapLayer"
	add_child(canvas_layer)
	_minimap_node = Node2D.new()
	_minimap_node.set_script(preload("res://scripts/minimap.gd"))
	canvas_layer.add_child(_minimap_node)
	_minimap_node.camera_ref = _camera

	_spawn_units()


func _process(delta: float) -> void:
	if _game_over or _paused:
		if _paused:
			_minimap_node.queue_redraw()
		return
		return
	_check_game_over()

	# ---- 边缘滚屏 ----
	_edge_scroll(delta)

	# ---- 相机平滑缩放 ----
	_camera.zoom = _camera.zoom.lerp(Vector2(_zoom_target, _zoom_target), delta * 8.0)

	# ---- 更新小地图 ----
	_minimap_node.units = _units
	_minimap_node.camera_pos = _camera.global_position
	_minimap_node.camera_zoom = _camera.zoom
	_minimap_node.queue_redraw()


func _edge_scroll(delta: float) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var edge_size := 30
	var scroll_speed: float = 400.0 * delta / _camera.zoom.x

	if mouse_pos.x < edge_size:
		_camera.global_position.x -= scroll_speed
	elif mouse_pos.x > viewport_size.x - edge_size:
		_camera.global_position.x += scroll_speed

	if mouse_pos.y < edge_size:
		_camera.global_position.y -= scroll_speed
	elif mouse_pos.y > viewport_size.y - edge_size:
		_camera.global_position.y += scroll_speed


func _check_game_over() -> void:
	var blue_alive := 0
	var red_alive := 0
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == Unit.Team.BLUE:
			blue_alive += 1
		else:
			red_alive += 1

	if blue_alive == 0:
		_game_over = true
		_winner = "红队"
	elif red_alive == 0:
		_game_over = true
		_winner = "蓝队"

	if _game_over:
		queue_redraw()


func _input(event: InputEvent) -> void:
	# ---- 游戏结束时的键盘操作 ----
	if _game_over:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_R:
				get_tree().reload_current_scene()
			elif event.keycode == KEY_Q:
				get_tree().quit()
		return

	# ---- ESC 暂停/继续 + 暂停时操作 ----
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_paused = not _paused
			_attack_cursor_mode = false
			queue_redraw()
			return
		if _paused:
			if event.keycode == KEY_R:
				get_tree().reload_current_scene()
			elif event.keycode == KEY_Q:
				get_tree().quit()
			return

	if _paused:
		return

	# 清除已死亡的选中单位
	_selected_units = _selected_units.filter(
		func(u): return is_instance_valid(u) and u.hull > 0
	)

	# ---- 键盘：A 键切换攻击光标模式 ----
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A and not event.echo:
			_attack_cursor_mode = not _attack_cursor_mode
			queue_redraw()
		elif event.keycode == KEY_ESCAPE:
			_attack_cursor_mode = false
			queue_redraw()

	# ---- 鼠标滚轮缩放 ----
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clamp(_zoom_target * 1.1, 0.3, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clamp(_zoom_target / 1.1, 0.3, 3.0)

	# ---- 左键按下 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _attack_cursor_mode:
				_handle_attack_click(event.position)
				_attack_cursor_mode = false
				queue_redraw()
			else:
				# 正常模式：开始框选（存世界坐标）
				_is_dragging = true
				_drag_start = _screen_to_world(event.position)
				_drag_end = _drag_start
				if not Input.is_key_pressed(KEY_SHIFT):
					_clear_selection()
		else:
			if _is_dragging:
				_is_dragging = false
				_apply_selection()
				queue_redraw()

	# ---- 鼠标移动（拖拽中更新选框） ----
	if event is InputEventMouseMotion and _is_dragging:
		_drag_end = _screen_to_world(event.position)
		queue_redraw()

	# ---- 右键：移动/攻击 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _selected_units.size() > 0:
			_attack_cursor_mode = false
			_handle_right_click(event.position)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen_pos


func _handle_attack_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var enemy = _find_enemy_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			unit.attack_target(enemy)
		else:
			unit.attack_move_to(world_pos)


func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var enemy = _find_enemy_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			unit.attack_target(enemy)
		else:
			unit.move_to(world_pos)


func _find_enemy_at_world(world_pos: Vector2) -> Unit:
	for unit in _units:
		if unit.team != Unit.Team.RED:
			continue
		if unit.hull <= 0:
			continue
		var half = Vector2(32, 32)
		var unit_rect = Rect2(unit.global_position - half, half * 2)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func _draw() -> void:
	# ---- 游戏结束画面（相机空间） ----
	if _game_over:
		var cam_pos = _camera.global_position
		var vsize = get_viewport().get_visible_rect().size / _camera.zoom
		var top_left = cam_pos - vsize / 2
		var overlay = Rect2(top_left, vsize)
		draw_rect(overlay, Color(0, 0, 0, 0.65), true)

		var center = cam_pos
		var is_victory = _winner == "蓝队"
		var title = "胜利！" if is_victory else "失败！"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var font = ThemeDB.fallback_font
		var title_size = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - title_size / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		var subtitle = _winner + "获胜"
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), subtitle,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		return

	# ---- 暂停画面 ----
	if _paused and not _game_over:
		var cam_pos = _camera.global_position
		var vsize = get_viewport().get_visible_rect().size / _camera.zoom
		var top_left = cam_pos - vsize / 2
		draw_rect(Rect2(top_left, vsize), Color(0, 0, 0, 0.65), true)
		var c = cam_pos
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), c - Vector2(40, 50), "  暂停",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.7, 1.0))
		font.draw_string(get_canvas_item(), c - Vector2(80, -10), "[ESC] 继续游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), c - Vector2(80, -40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), c - Vector2(80, -70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		return

	# 框选矩形（世界坐标绘制）
	if _is_dragging:
		var rect = _get_drag_rect()
		if rect.has_area():
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)

	# 攻击光标模式提示（屏幕坐标 → 转世界坐标）
	if _attack_cursor_mode:
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		const CROSS_SIZE: float = 12.0
		var cross_color = Color(1.0, 0.2, 0.2, 0.9)
		draw_line(world_mouse + Vector2(-CROSS_SIZE, 0), world_mouse + Vector2(CROSS_SIZE, 0), cross_color, 2.0)
		draw_line(world_mouse + Vector2(0, -CROSS_SIZE), world_mouse + Vector2(0, CROSS_SIZE), cross_color, 2.0)
		draw_circle(world_mouse, CROSS_SIZE * 0.6, cross_color, false, 1.5)


func _get_drag_rect() -> Rect2:
	return Rect2(
		Vector2(min(_drag_start.x, _drag_end.x), min(_drag_start.y, _drag_end.y)),
		Vector2(abs(_drag_end.x - _drag_start.x), abs(_drag_end.y - _drag_start.y))
	)


func _apply_selection() -> void:
	var drag_rect = _get_drag_rect()

	if drag_rect.size.length() < 10.0:
		var click_world = _drag_start
		for unit in _units:
			if unit.team != Unit.Team.BLUE:
				continue
			var half = Vector2(32, 32)
			var unit_rect = Rect2(unit.global_position - half, half * 2)
			if unit_rect.has_point(click_world):
				unit.is_selected = true
				if unit not in _selected_units:
					_selected_units.append(unit)
				return
		_clear_selection()
		return

	for unit in _units:
		if unit.team != Unit.Team.BLUE:
			continue
		if drag_rect.has_point(unit.global_position):
			if not unit.is_selected:
				unit.is_selected = true
				_selected_units.append(unit)


func _clear_selection() -> void:
	for unit in _selected_units:
		unit.is_selected = false
	_selected_units.clear()


func _spawn_units() -> void:
	if unit_scene == null:
		push_error("请将 unit.tscn 拖入 Main 节点的 Unit Scene 属性！")
		return

	for i in range(blue_count):
		var unit = _create_unit(Unit.Team.BLUE)
		unit.position = Vector2(randf_range(100, 350), randf_range(100, 500))

	for i in range(red_count):
		var unit = _create_unit(Unit.Team.RED)
		unit.position = Vector2(randf_range(450, 700), randf_range(100, 500))


func _create_unit(team: Unit.Team) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	unit.team = team
	if team == Unit.Team.BLUE:
		unit.unit_color = Color(0.2, 0.5, 1.0)
	else:
		unit.unit_color = Color(1.0, 0.25, 0.25)
	unit._all_units = _units
	add_child(unit)
	_units.append(unit)

	# 每种武器各一个
	unit._slot_weapons[0] = Weapon.create_bullet()
	unit._slot_weapons[1] = Weapon.create_missile()
	unit._slot_weapons[2] = Weapon.create_laser()
	unit._slot_weapons[3] = Weapon.create_pd()

	return unit

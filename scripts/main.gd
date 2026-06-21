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

# ----- A 键攻击模式 -----
var _attack_cursor_mode: bool = false

# ----- 游戏结束状态 -----
var _game_over: bool = false
var _winner: String = ""


func _ready() -> void:
	_spawn_units()


func _process(_delta: float) -> void:
	if _game_over:
		return
	_check_game_over()


func _check_game_over() -> void:
	var blue_alive := 0
	var red_alive := 0
	for unit in _units:
		if not is_instance_valid(unit) or unit.health <= 0:
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
		return  # 游戏结束后忽略其他输入

	# ---- 键盘：A 键切换攻击光标模式 ----
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A and not event.echo:
			_attack_cursor_mode = not _attack_cursor_mode
			queue_redraw()
		elif event.keycode == KEY_ESCAPE:
			_attack_cursor_mode = false
			queue_redraw()

	# ---- 左键按下 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _attack_cursor_mode:
				# A 模式：左键 = 攻击/攻击移动
				_handle_attack_click(event.position)
				_attack_cursor_mode = false
				queue_redraw()
			else:
				# 正常模式：开始框选
				_is_dragging = true
				_drag_start = event.position
				_drag_end = event.position
				if not Input.is_key_pressed(KEY_SHIFT):
					_clear_selection()
		else:
			# 左键松开：结束框选（仅当确实在拖拽时）
			if _is_dragging:
				_is_dragging = false
				_apply_selection()
				queue_redraw()

	# ---- 鼠标移动（拖拽中更新选框） ----
	if event is InputEventMouseMotion and _is_dragging:
		_drag_end = event.position
		queue_redraw()

	# ---- 右键：移动选中单位 / 攻击敌人 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _selected_units.size() > 0:
			# 取消攻击光标模式
			_attack_cursor_mode = false
			_handle_right_click(event.position)


func _handle_attack_click(screen_pos: Vector2) -> void:
	"""A 键模式下的左键处理"""
	var enemy = _find_enemy_at_position(screen_pos)
	if enemy != null:
		# 点击了敌方单位 → 攻击
		for unit in _selected_units:
			unit.attack_target(enemy)
	else:
		# 点击了地面 → 攻击移动
		var world_pos = get_global_mouse_position()
		for unit in _selected_units:
			unit.attack_move_to(world_pos)


func _handle_right_click(screen_pos: Vector2) -> void:
	"""右键处理：点敌 = 攻击，点地 = 移动"""
	var enemy = _find_enemy_at_position(screen_pos)
	if enemy != null:
		# 右键敌方单位 → 攻击
		for unit in _selected_units:
			unit.attack_target(enemy)
	else:
		# 右键地面 → 移动
		var world_pos = get_global_mouse_position()
		for unit in _selected_units:
			unit.move_to(world_pos)


func _find_enemy_at_position(screen_pos: Vector2) -> Unit:
	"""在屏幕位置查找敌方单位（红队）"""
	for unit in _units:
		if unit.team != Unit.Team.RED:
			continue
		if unit.health <= 0:
			continue
		var unit_rect = _get_unit_screen_rect(unit)
		if unit_rect and unit_rect.has_point(screen_pos):
			return unit
	return null


func _draw() -> void:
	# ---- 游戏结束画面 ----
	if _game_over:
		# 半透明遮罩
		var viewport_size = get_viewport().get_visible_rect().size
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.65), true)

		# 结果标题
		var center = viewport_size / 2
		var is_victory = _winner == "蓝队"
		var title = "胜利！" if is_victory else "失败！"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)

		# 使用简单的字符串绘制（Godot 4 需要 Font）
		var font = ThemeDB.fallback_font
		var title_size = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - title_size / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)

		# 副标题
		var subtitle = _winner + "获胜"
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), subtitle,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)

		# 操作提示
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

		return  # 游戏结束时不再绘制选框和十字

	# 框选矩形
	if _is_dragging:
		var rect = _get_drag_rect()
		if rect.has_area():
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)

	# 攻击光标模式提示
	if _attack_cursor_mode:
		var mouse_pos = get_local_mouse_position()
		# 红色十字
		const CROSS_SIZE: float = 12.0
		var cross_color = Color(1.0, 0.2, 0.2, 0.9)
		draw_line(mouse_pos + Vector2(-CROSS_SIZE, 0), mouse_pos + Vector2(CROSS_SIZE, 0), cross_color, 2.0)
		draw_line(mouse_pos + Vector2(0, -CROSS_SIZE), mouse_pos + Vector2(0, CROSS_SIZE), cross_color, 2.0)
		draw_circle(mouse_pos, CROSS_SIZE * 0.6, cross_color, false, 1.5)


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
			if unit.team != Unit.Team.BLUE:
				continue
			var unit_rect = _get_unit_screen_rect(unit)
			if unit_rect and unit_rect.has_point(click_pos):
				unit.is_selected = true
				if unit not in _selected_units:
					_selected_units.append(unit)
				return
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

	for i in range(blue_count):
		var unit = _create_unit(Unit.Team.BLUE)
		unit.position = Vector2(randf_range(80, 350), randf_range(80, 520))

	for i in range(red_count):
		var unit = _create_unit(Unit.Team.RED)
		unit.position = Vector2(randf_range(450, 720), randf_range(80, 520))


func _create_unit(team: Unit.Team) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	unit.team = team
	if team == Unit.Team.BLUE:
		unit.unit_color = Color(0.2, 0.5, 1.0)
	else:
		unit.unit_color = Color(1.0, 0.25, 0.25)
	unit.weapon = _random_weapon()
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

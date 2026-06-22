extends Node2D

## 单位预制场景
@export var unit_scene: PackedScene

var _units: Array[Unit] = []

# ----- 框选状态 -----
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

# ----- 选中单位集合 -----
var _selected_units: Array[Unit] = []

# ----- 控制组（10组，每组存一个Array[Unit]）-----
var _control_groups: Array = [[], [], [], [], [], [], [], [], [], []]

# ----- 双击检测 -----
var _last_click_time: float = 0.0
var _last_clicked_unit: Unit = null
const DOUBLE_CLICK_TIME: float = 0.3

# ----- 数字键双击（镜头移动）-----
var _last_number_key: int = -1
var _last_number_time: float = 0.0

# ----- 武器配置缓存（同型号共用一套）-----
var _weapon_loadout_cache: Dictionary = {}

# ----- A 键攻击模式 -----
var _attack_cursor_mode: bool = false
# ----- W 键环绕模式 -----
var _orbit_cursor_mode: bool = false

# ----- 相机 -----
var _camera: Camera2D
var _zoom_target: float = 1.0
var _minimap_node: Node2D
var _follow_unit: Unit = null  # F 键跟随目标

# ----- 游戏结束状态 -----
var _game_over: bool = false
var _winner: String = ""

# ----- 暂停 -----
var _paused: bool = false

# ----- 菜单覆图层（CanvasLayer 始终在顶层） -----
var _overlay: CanvasLayer


func _ready() -> void:
	# 暂停时 Main 仍需接收输入
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 全屏
	var screen_size = DisplayServer.screen_get_size()
	get_window().size = screen_size
	get_window().mode = Window.MODE_FULLSCREEN

	# 相机
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.global_position = Vector2(700, 300)
	add_child(_camera)
	_camera.make_current()

	# 小地图 CanvasLayer
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MinimapLayer"
	add_child(canvas_layer)
	_minimap_node = Node2D.new()
	_minimap_node.set_script(preload("res://scripts/minimap.gd"))
	canvas_layer.add_child(_minimap_node)
	_minimap_node.camera_ref = _camera

	# 菜单覆图层（Button 控件，始终在最上层）
	_overlay = load("res://scripts/overlay.gd").new()
	_overlay.name = "OverlayLayer"
	_overlay.main = self
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)
	_overlay.visible = false

	# ---- HUD CanvasLayer（信息面板 + 技能按钮） ----
	var hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	var hud = Node2D.new()
	hud.name = "Hud"
	hud.set_script(preload("res://scripts/hud.gd"))
	hud.main = self
	hud_layer.add_child(hud)

	_spawn_units()


func _process(delta: float) -> void:
	if _game_over or _paused:
		if _paused:
			_minimap_node.queue_redraw()
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var center = get_viewport().get_visible_rect().size / 2
				var click = get_viewport().get_mouse_position() - center
				if abs(click.x) < 100 and abs(click.y) < 75:
					_paused = false
					get_tree().paused = false
					_overlay.show(); _overlay.build_menu()
		return
	_check_game_over()

	# ---- AI 控制器（红队自动攻击蓝队） ---- 
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != Unit.Team.RED:
			continue
		# 如果没有目标或目标已死，找最近敌人
		if not is_instance_valid(unit._current_target) or unit._current_target.hull <= 0:
			# 检查是否有进攻性武器（非 PD）
			var has_offensive = unit._get_approach_range() > 0
			if has_offensive:
				var enemy = unit.find_nearest_enemy()
				if enemy != null:
					unit.attack_target(enemy)
			else:
				# 只有 PD → 环绕最大友军
				if not unit._is_orbit or not is_instance_valid(unit._orbit_target_unit):
					var largest = _find_largest_friendly(unit)
					if largest != null and largest != unit:
						unit.orbit_target(largest)

	# ---- 边缘滚屏 ----
	_edge_scroll(delta)

	# ---- 相机平滑缩放 ----
	_camera.zoom = _camera.zoom.lerp(Vector2(_zoom_target, _zoom_target), delta * 8.0)

	# ---- 镜头跟随 ----
	if _follow_unit != null and is_instance_valid(_follow_unit) and _follow_unit.hull > 0:
		_camera.position = _camera.position.lerp(_follow_unit.global_position, delta * 5.0)
	elif _follow_unit != null:
		_follow_unit = null

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
		_overlay.show(); _overlay.build_menu()
	elif red_alive == 0:
		_game_over = true
		_winner = "蓝队"
		_overlay.show(); _overlay.build_menu()


func _resume_game() -> void:
	_paused = false
	get_tree().paused = false
	_overlay.hide()


func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	# ---- 游戏结束 / 暂停时的键盘/鼠标操作 ----
	if _game_over or _paused:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_ESCAPE:
					if _paused and not _game_over:
						_resume_game()
				KEY_R:
					_restart_game()
				KEY_Q:
					get_tree().quit()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var center = get_viewport().get_visible_rect().size / 2
			var click = event.position - center
			if _paused:
				# 点击中心区域 200x150 恢复游戏
				if abs(click.x) < 100 and abs(click.y) < 75:
					_paused = false
					get_tree().paused = false
					_overlay.show(); _overlay.build_menu()
					return
			if _game_over:
				if abs(click.x) < 100 and abs(click.y) < 75:
					get_tree().reload_current_scene()
		return

	# ---- ESC 暂停 ----
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_paused = true
		get_tree().paused = true
		_attack_cursor_mode = false
		_overlay.show(); _overlay.build_menu()
		return

	# 清除已死亡的选中单位
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)

	# ---- 键盘：W / A / ESC / 数字编队 ----
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_W and not event.echo:
			if _selected_units.size() > 0:
				_orbit_cursor_mode = not _orbit_cursor_mode
			else:
				_orbit_cursor_mode = false
			_attack_cursor_mode = false
			queue_redraw()

		# ---- Ctrl+A 优先于普通 A ----
		elif event.keycode == KEY_A and event.ctrl_pressed and not event.echo:
			_clear_selection()
			for unit in _units:
				if unit.team == Unit.Team.BLUE and unit.hull > 0:
					unit.is_selected = true
					_selected_units.append(unit)
			_attack_cursor_mode = false
			_orbit_cursor_mode = false
			queue_redraw()
		elif event.keycode == KEY_A and not event.echo:
			_attack_cursor_mode = not _attack_cursor_mode
			_orbit_cursor_mode = false
			queue_redraw()
		elif event.keycode == KEY_ESCAPE:
			_attack_cursor_mode = false
			_orbit_cursor_mode = false
			queue_redraw()

		# ---- H：镜头移动到选中单位 ----
		elif event.keycode == KEY_H and not event.echo:
			_center_camera_on_selection()
			_follow_unit = null

		# ---- F：镜头跟随选中单位 ----
		elif event.keycode == KEY_F and not event.echo:
			if _selected_units.size() > 0:
				_follow_unit = _selected_units[0]
				_camera.position = _follow_unit.global_position
			else:
				_follow_unit = null

		# ---- Z/X/C/V：技能快捷键 ----
		elif [KEY_Z, KEY_X, KEY_C, KEY_V].has(event.keycode) and not event.echo:
			var slot = [KEY_Z, KEY_X, KEY_C, KEY_V].find(event.keycode)
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(slot)

		# ---- H：镜头移动到选中单位 ----
		elif event.keycode == KEY_H and not event.echo:
			_center_camera_on_selection()

		# ---- Ctrl+数字：编队 ----
		elif event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var group_idx = event.keycode - KEY_0
			_assign_control_group(group_idx)
		# ---- 单独数字：选中编队 / 双击跳镜头 ----
		elif not event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var group_idx = event.keycode - KEY_0
			var now = Time.get_ticks_msec() / 1000.0
			if group_idx == _last_number_key and (now - _last_number_time) < DOUBLE_CLICK_TIME:
				var g: Array = _control_groups[group_idx]
				if g.size() > 0:
					var first = g[0]
					if is_instance_valid(first):
						_camera.position = first.global_position
			else:
				_select_control_group(group_idx)
			_last_number_key = group_idx
			_last_number_time = now

	# ---- 鼠标滚轮缩放 ----
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clamp(_zoom_target * 1.1, 0.3, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clamp(_zoom_target / 1.1, 0.3, 3.0)

	# ---- 左键 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _orbit_cursor_mode:
				_handle_orbit_click(event.position)
				_orbit_cursor_mode = false
				queue_redraw()
			elif _attack_cursor_mode:
				_handle_attack_click(event.position)
				_attack_cursor_mode = false
				queue_redraw()
			else:
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

	# ---- 鼠标移动（拖拽中） ----
	if event is InputEventMouseMotion and _is_dragging:
		_drag_end = _screen_to_world(event.position)
		queue_redraw()

	# ---- 右键 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _selected_units.size() > 0:
			_orbit_cursor_mode = false
			_attack_cursor_mode = false
			_handle_right_click(event.position)




func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen_pos


func _handle_orbit_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var target = _find_unit_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if target != null:
			unit.orbit_target(target)
		else:
			unit.orbit_position(world_pos)


func _handle_attack_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var enemy = _find_enemy_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			# A+命中敌方单位 → 攻击该单位
			unit.attack_target(enemy)
		else:
			# A+点地 → 全屏攻击移动
			var viewport_size = get_viewport().get_visible_rect().size
			var world_radius = viewport_size.length() / _camera.zoom.x / 2
			unit.attack_area(world_pos, world_radius)


func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	# 不能控制敌方单位
	for u in _selected_units:
		if u.team != Unit.Team.BLUE:
			return
	var enemy = _find_enemy_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			unit.attack_target(enemy)
		else:
			unit.move_to(world_pos)


func _find_largest_friendly(me: Unit) -> Unit:
	var best: Unit = null
	var best_tier := -1
	for u in _units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		if u.team != me.team or u == me:
			continue
		var t = Unit._ship_class_tier(u.class_type)
		if t > best_tier:
			best_tier = t
			best = u
	return best


func _find_unit_at_world(world_pos: Vector2) -> Unit:
	for unit in _units:
		if unit.hull <= 0:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func _find_enemy_at_world(world_pos: Vector2) -> Unit:
	for unit in _units:
		if unit.team != Unit.Team.RED:
			continue
		if unit.hull <= 0:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func _draw_overlay() -> void:
	"""在 CanvasLayer 上绘制暂停/游戏结束画面（屏幕坐标）"""
	var vsize = get_viewport().get_visible_rect().size

	if _game_over:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var is_victory = _winner == "蓝队"
		var title = "胜利！" if is_victory else "失败！"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var font = ThemeDB.fallback_font
		var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - ts / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), _winner + "获胜",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

	elif _paused:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), center - Vector2(40, 50), "  暂停",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.7, 1.0))
		font.draw_string(get_canvas_item(), center - Vector2(80, -10), "[ESC] 继续游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))


func _draw() -> void:
	# 框选矩形（世界坐标）
	if _is_dragging:
		var rect = _get_drag_rect()
		if rect.has_area():
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)

	# 攻击光标模式提示
	if _attack_cursor_mode:
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		const CROSS_SIZE: float = 12.0
		var cross_color = Color(1.0, 0.2, 0.2, 0.9)
		draw_line(world_mouse + Vector2(-CROSS_SIZE, 0), world_mouse + Vector2(CROSS_SIZE, 0), cross_color, 2.0)
		draw_line(world_mouse + Vector2(0, -CROSS_SIZE), world_mouse + Vector2(0, CROSS_SIZE), cross_color, 2.0)
		draw_circle(world_mouse, CROSS_SIZE * 0.6, cross_color, false, 1.5)

	# 环绕光标提示
	if _orbit_cursor_mode:
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		var orbit_color = Color(0.2, 1.0, 0.5, 0.9)
		draw_circle(world_mouse, 14.0, orbit_color, false, 2.0)
		draw_circle(world_mouse, 10.0, Color(0.2, 1.0, 0.5, 0.3), true)
		# 箭头指示环绕方向
		var a = world_mouse + Vector2(14, 0)
		draw_line(a, a + Vector2(-4, -3), orbit_color, 2.0)
		draw_line(a, a + Vector2(-4, 3), orbit_color, 2.0)


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
			if unit.hull <= 0:
				continue
			var size = unit.collision_shape.shape.size
			var half = size / 2
			var unit_rect = Rect2(unit.global_position - half, size)
			if unit_rect.has_point(click_world):
				# ---- 双击检测：选中所有同类单位 ----
				var now = Time.get_ticks_msec() / 1000.0
				if unit == _last_clicked_unit and (now - _last_click_time) < DOUBLE_CLICK_TIME:
					_clear_selection()
					for u in _units:
						if u.team == Unit.Team.BLUE and u.class_type == unit.class_type:
							u.is_selected = true
							_selected_units.append(u)
				else:
					unit.is_selected = true
					if unit not in _selected_units:
						_selected_units.append(unit)
				_last_click_time = now
				_last_clicked_unit = unit
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

	# 每方舰队编成：各型号各一艘
	var fleet: Array[Array] = [
		[Unit.ShipClass.BATTLESHIP, 1],
		[Unit.ShipClass.CRUISER, 1],
		[Unit.ShipClass.DESTROYER, 1],
		[Unit.ShipClass.FRIGATE, 1],
		[Unit.ShipClass.DRONE, 1],
	]

	_spawn_fleet(Unit.Team.BLUE, 250, fleet)
	_spawn_fleet(Unit.Team.RED, 7000, fleet)

	# 镜头缩放到刚好显示双方所有舰队
	_fit_camera_to_fleets()


func _spawn_fleet(team: Unit.Team, center_x: int, fleet: Array[Array]) -> void:
	var color = Color(0.2, 0.5, 1.0) if team == Unit.Team.BLUE else Color(1.0, 0.25, 0.25)
	var y_center = 500.0
	var dir = 1 if team == Unit.Team.BLUE else -1
	var x_offset := 0

	# 红方反序迭代，实现镜像：小船在双方内侧，大船在外侧
	var fleet_iter = fleet.duplicate()
	if team == Unit.Team.RED:
		fleet_iter.reverse()

	for entry in fleet_iter:
		var sc: Unit.ShipClass = entry[0]
		var count: int = entry[1]
		x_offset += 80
		var y_spread = max(60.0 * count, 100.0)
		for j in range(count):
			var unit = _create_unit(team, sc, color)
			unit.position = Vector2(
				center_x + dir * x_offset + randf_range(-30, 30),
				y_center + (j - (count - 1) / 2.0) * (y_spread / count) + randf_range(-20, 20)
			)


func _fit_camera_to_fleets() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		min_pos = min_pos.min(unit.global_position)
		max_pos = max_pos.max(unit.global_position)

	var center = (min_pos + max_pos) / 2
	_camera.position = center

	var world_size = max_pos - min_pos + Vector2(600, 600)
	var viewport_size = get_viewport().get_visible_rect().size
	var zoom = min(viewport_size.x / world_size.x, viewport_size.y / world_size.y)
	_zoom_target = clamp(zoom, 0.3, 3.0)


func _center_camera_on_selection() -> void:
	if _selected_units.size() > 0:
		var target = _selected_units[0]
		if is_instance_valid(target) and _camera != null:
			_camera.position = target.global_position


func _create_unit(team: Unit.Team, class_type: Unit.ShipClass, unit_color: Color) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	unit.class_type = class_type
	unit.team = team
	unit.unit_color = unit_color
	unit._all_units = _units
	add_child(unit)
	_units.append(unit)

	# 同型号飞船使用同一套武器配置
	var loadout: Array
	if _weapon_loadout_cache.has(class_type):
		loadout = _weapon_loadout_cache[class_type]
	else:
		loadout = []
		for i in range(unit.slot_count):
			loadout.append(Weapon.create_random())
		_weapon_loadout_cache[class_type] = loadout

	for i in range(unit.slot_count):
		unit._slot_weapons[i] = loadout[i]

	return unit


# ==================== 编队系统 ====================

func _assign_control_group(group_idx: int) -> void:
	_clean_control_groups()
	var group = _control_groups[group_idx]
	# 清除这些单位在旧编队中的记录
	for u in _selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		# 从旧编队移除
		for gi in range(10):
			if gi == group_idx: continue
			var old_group: Array = _control_groups[gi]
			if u in old_group:
				old_group.erase(u)
				break
			
			u.control_group = -1
	# 添加到新编队
	group.clear()
	for u in _selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		group.append(u)
		u.control_group = group_idx


func _select_control_group(group_idx: int) -> void:
	_clean_control_groups()
	_clear_selection()
	var group: Array = _control_groups[group_idx]
	for u in group:
		if is_instance_valid(u) and u.hull > 0:
			u.is_selected = true
			_selected_units.append(u)


func _clean_control_groups() -> void:
	if _control_groups.size() < 10:
		return
	for i in range(10):
		var group: Array = _control_groups[i]
		group = group.filter(func(u): return is_instance_valid(u) and u.hull > 0)
		_control_groups[i] = group

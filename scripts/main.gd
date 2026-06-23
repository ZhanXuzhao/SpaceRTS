extends Node2D

const CFG = preload("res://scripts/game_config.gd")

## 锟斤拷位预锟狡筹拷锟斤拷
@export var unit_scene: PackedScene
@export var time_scale: float = 4.0

var _units: Array[Unit] = []

# ----- 锟斤拷选状态 -----
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

# ----- 选锟叫碉拷位锟斤拷锟斤拷 -----
var _selected_units: Array[Unit] = []

# ----- 锟斤拷锟斤拷锟介（10锟介，每锟斤拷锟揭伙拷锟紸rray[Unit]锟斤拷-----
var _control_groups: Array = [[], [], [], [], [], [], [], [], [], []]

# ----- 双锟斤拷锟斤拷锟?-----
var _last_click_time: float = 0.0
var _last_clicked_unit: Unit = null
const DOUBLE_CLICK_TIME: float = 0.3

# ----- 锟斤拷锟街硷拷双锟斤拷锟斤拷锟斤拷头锟狡讹拷锟斤拷-----
var _last_number_key: int = -1
var _last_number_time: float = 0.0

# ----- 锟斤拷锟斤拷锟斤拷锟矫伙拷锟芥（同锟酵号癸拷锟斤拷一锟阶ｏ拷-----
var _weapon_loadout_cache: Dictionary = {}

# ----- A 锟斤拷锟斤拷锟斤拷模式 -----
var _attack_cursor_mode: bool = false
# ----- W 锟斤拷锟斤拷锟斤拷模式 -----
var _orbit_cursor_mode: bool = false
var _orbit_drag_start: Vector2 = Vector2.ZERO  # W 锟斤拷拽锟斤拷锟?
var _orbit_drag_end: Vector2 = Vector2.ZERO
var _orbit_is_dragging: bool = false

# ----- 锟斤拷锟?-----
var _camera: Camera2D
var _zoom_target: float = 1.0
var _minimap_node: Node2D
var _follow_unit: Unit = null  # F 锟斤拷锟斤拷锟斤拷目锟斤拷

# ----- 锟斤拷戏锟斤拷锟斤拷状态 -----
var _game_over: bool = false
var _winner: String = ""

# ----- 锟斤拷停 -----
var _paused: bool = false

# ----- 锟剿碉拷锟斤拷图锟姐（CanvasLayer 始锟斤拷锟节讹拷锟姐） -----
var _overlay: CanvasLayer


func _ready() -> void:
	# 锟斤拷停时 Main 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟?
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 支锟斤拷锟斤拷锟斤拷锟叫革拷锟角碉拷时锟戒倍锟绞ｏ拷锟斤拷锟斤拷锟斤拷锟矫ｏ拷确锟斤拷锟斤拷位锟斤拷锟斤拷前锟斤拷效锟斤拷
	for arg in OS.get_cmdline_args():
		if typeof(arg) == TYPE_STRING and arg.begins_with("--time_scale="):
			var parts = arg.split("=")
			if parts.size() >= 2:
				var v = float(parts[1])
				if v > 0.0:
					time_scale = v
	Engine.time_scale = time_scale
	print("DEBUG: time_scale set to", time_scale)

	# 全锟斤拷
	var screen_size = DisplayServer.screen_get_size()
	get_window().size = screen_size
	get_window().mode = Window.MODE_FULLSCREEN

	# 锟斤拷锟?
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.global_position = Vector2(700, 300)
	add_child(_camera)
	_camera.make_current()

	# 小锟斤拷图 CanvasLayer
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MinimapLayer"
	add_child(canvas_layer)
	_minimap_node = Node2D.new()
	_minimap_node.set_script(preload("res://scripts/minimap.gd"))
	canvas_layer.add_child(_minimap_node)
	_minimap_node.camera_ref = _camera

	# 锟剿碉拷锟斤拷图锟姐（Button 锟截硷拷锟斤拷始锟斤拷锟斤拷锟斤拷锟较层）
	_overlay = load("res://scripts/overlay.gd").new()
	_overlay.name = "OverlayLayer"
	_overlay.main = self
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)
	_overlay.visible = false

	# ---- HUD CanvasLayer锟斤拷锟斤拷息锟斤拷锟?+ 锟斤拷锟杰帮拷钮锟斤拷 ----
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

	# ---- AI 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷远锟斤拷锟斤拷锟斤拷锟斤拷樱锟?---- 
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != Unit.Team.RED:
			continue
		# 锟斤拷锟矫伙拷锟侥匡拷锟斤拷目锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟?
		if not is_instance_valid(unit._current_target) or unit._current_target.hull <= 0:
			# 锟斤拷锟斤拷欠锟斤拷薪锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟?PD锟斤拷
			var has_offensive = unit._get_approach_range() > 0
			if has_offensive:
				var enemy = unit.find_nearest_enemy()
				if enemy != null:
					unit.attack_target(enemy)
			else:
				# 只锟斤拷 PD 锟斤拷 锟斤拷锟斤拷锟斤拷锟斤拷丫锟?
				if not unit._is_orbit or not is_instance_valid(unit._orbit_target_unit):
					var largest = _find_largest_friendly(unit)
					if largest != null and largest != unit:
						unit.orbit_target(largest)

	# ---- 锟斤拷缘锟斤拷锟斤拷 ----
	_edge_scroll(delta)

	# ---- 锟斤拷锟狡斤拷锟斤拷锟斤拷锟?----
	_camera.zoom = _camera.zoom.lerp(Vector2(_zoom_target, _zoom_target), delta * 8.0)

	# ---- 锟斤拷头锟斤拷锟斤拷 ----
	if _follow_unit != null and is_instance_valid(_follow_unit) and _follow_unit.hull > 0:
		_camera.position = _camera.position.lerp(_follow_unit.global_position, delta * 5.0)
	elif _follow_unit != null:
		_follow_unit = null

	# ---- 锟斤拷锟斤拷小锟斤拷图 ----
	_minimap_node.units = _units
	_minimap_node.camera_pos = _camera.global_position
	_minimap_node.camera_zoom = _camera.zoom
	_minimap_node.queue_redraw()


func _edge_scroll(delta: float) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var edge_size := 30
	var scroll_speed: float = CFG.SCROLL_SPEED * delta / _camera.zoom.x
	var scrolled := false

	if mouse_pos.x < edge_size:
		_camera.global_position.x -= scroll_speed
		scrolled = true
	elif mouse_pos.x > viewport_size.x - edge_size:
		_camera.global_position.x += scroll_speed
		scrolled = true

	if mouse_pos.y < edge_size:
		_camera.global_position.y -= scroll_speed
		scrolled = true
	elif mouse_pos.y > viewport_size.y - edge_size:
		_camera.global_position.y += scroll_speed
		scrolled = true

	if scrolled:
		_follow_unit = null


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
		_winner = "绾㈤槦"
		_overlay.show(); _overlay.build_menu()
	elif red_alive == 0:
		_game_over = true
		_winner = "钃濋槦"
		_overlay.show(); _overlay.build_menu()


func _resume_game() -> void:
	_paused = false
	get_tree().paused = false
	_overlay.hide()


func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	# ---- 锟斤拷戏锟斤拷锟斤拷 / 锟斤拷停时锟侥硷拷锟斤拷/锟斤拷锟斤拷锟斤拷 ----
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
				# 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟?200x150 锟街革拷锟斤拷戏
				if abs(click.x) < 100 and abs(click.y) < 75:
					_paused = false
					get_tree().paused = false
					_overlay.show(); _overlay.build_menu()
					return
			if _game_over:
				if abs(click.x) < 100 and abs(click.y) < 75:
					get_tree().reload_current_scene()
		return

	# ---- F5锟斤拷锟斤拷锟斤拷锟斤拷锟铰匡拷始 ----
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return

	# ---- ESC 锟斤拷停 ----
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_paused = true
		get_tree().paused = true
		_attack_cursor_mode = false
		_overlay.show(); _overlay.build_menu()
		return

	# 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟窖★拷械锟轿?
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)

	# ---- 锟斤拷锟教ｏ拷W / A / ESC / 锟斤拷锟街憋拷锟?----
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_W and not event.echo:
			if _selected_units.size() > 0:
				_orbit_cursor_mode = not _orbit_cursor_mode
			else:
				_orbit_cursor_mode = false
			_attack_cursor_mode = false
			queue_redraw()

		# ---- Ctrl+A 锟斤拷锟斤拷锟斤拷锟斤拷通 A ----
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

		# ---- H锟斤拷锟斤拷头锟狡讹拷锟斤拷选锟叫碉拷位 ----
		elif event.keycode == KEY_H and not event.echo:
			_center_camera_on_selection()
			_follow_unit = null

		# ---- F锟斤拷锟斤拷头锟斤拷锟斤拷选锟叫碉拷位 ----
		elif event.keycode == KEY_F and not event.echo:
			if _selected_units.size() > 0:
				_follow_unit = _selected_units[0]
				_camera.position = _follow_unit.global_position
			else:
				_follow_unit = null

		# ---- G锟斤拷锟叫伙拷锟斤拷锟斤拷模式 ----
		elif event.keycode == KEY_G and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u._attack_mode = (u._attack_mode + 1) % 3

		# ---- 鏃堕棿鍊嶇巼 +/- 锛堝噺鍗?/ 鍊嶅锛?----
		elif (event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT) and not event.echo:
			# 鍑忓崐锛屼絾涓嶄綆浜?0.125
			time_scale = max(0.125, time_scale * 0.5)
			Engine.time_scale = time_scale
			if _minimap_node:
				_minimap_node.queue_redraw()
			print("DEBUG: time_scale set to", time_scale)
			return
		elif (event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD or event.keycode == KEY_PLUS) and not event.echo:
			# 鍊嶅锛屼絾涓嶈秴杩?16.0
			time_scale = min(16.0, time_scale * 2.0)
			Engine.time_scale = time_scale
			if _minimap_node:
				_minimap_node.queue_redraw()
			print("DEBUG: time_scale set to", time_scale)
			return
			queue_redraw()

		# ---- Z锟斤拷锟斤拷锟斤拷 ----
		elif event.keycode == KEY_Z and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(0)
		# ---- X锟斤拷锟斤拷锟斤拷 ----
		elif event.keycode == KEY_X and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(1)
		# ---- C锟斤拷锟斤拷锟斤拷 ----
		elif event.keycode == KEY_C and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(2)
		# ---- V锟斤拷跃迁锟斤拷战锟叫斤拷专锟斤拷锟斤拷 ----
		elif event.keycode == KEY_V and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(3)
		# ---- B锟斤拷锟斤拷锟劫ｏ拷锟斤拷锟剿伙拷/锟斤拷锟斤拷锟斤拷锟斤拷 ----
		elif event.keycode == KEY_B and not event.echo:
			for u in _selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(4)

		# ---- Ctrl+锟斤拷锟街ｏ拷锟斤拷锟?----
		elif event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var group_idx = event.keycode - KEY_0
			_assign_control_group(group_idx)
		# ---- 锟斤拷锟斤拷锟斤拷锟街ｏ拷选锟叫憋拷锟?/ 双锟斤拷锟斤拷锟斤拷头 ----
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

	# ---- 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷 ----
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clamp(_zoom_target * 1.1, 0.3, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clamp(_zoom_target / 1.1, 0.3, 3.0)

	# ---- 锟斤拷锟?----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _orbit_cursor_mode:
				# 锟斤拷锟斤拷时锟斤拷录锟斤拷锟?
				_orbit_drag_start = event.position
				_orbit_drag_end = event.position
				_orbit_is_dragging = true
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
			if _orbit_is_dragging:
				_orbit_is_dragging = false
				_orbit_cursor_mode = false
				var start_world = _screen_to_world(_orbit_drag_start)
				var end_world = _screen_to_world(event.position)
				var radius = start_world.distance_to(end_world)
				if radius < 10.0:
					_handle_orbit_click(_orbit_drag_start, -1.0)
				else:
					_handle_orbit_click(_orbit_drag_start, radius)
				queue_redraw()

	# ---- 锟斤拷锟斤拷贫锟斤拷锟斤拷锟阶э拷校锟?----
	if event is InputEventMouseMotion and _is_dragging:
		_drag_end = _screen_to_world(event.position)
		queue_redraw()
	if event is InputEventMouseMotion and _orbit_is_dragging:
		_orbit_drag_end = event.position
		queue_redraw()

	# ---- 锟揭硷拷 ----
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _selected_units.size() > 0:
			_orbit_cursor_mode = false
			_attack_cursor_mode = false
			_handle_right_click(event.position)




func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen_pos


func _handle_orbit_click(screen_pos: Vector2, custom_radius: float = -1.0) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var target = _find_unit_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit == target:
			continue  # 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷
		if target != null:
			unit.orbit_target(target, custom_radius)
		else:
			unit.orbit_position(world_pos, custom_radius)


func _handle_attack_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var enemy = _find_enemy_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			# A+锟斤拷锟叫敌凤拷锟斤拷位 锟斤拷 锟斤拷锟斤拷锟矫碉拷位
			unit.attack_target(enemy)
		else:
			# A+锟斤拷锟?锟斤拷 全锟斤拷锟斤拷锟斤拷锟狡讹拷
			var viewport_size = get_viewport().get_visible_rect().size
			var world_radius = viewport_size.length() / _camera.zoom.x / 2
			unit.attack_area(world_pos, world_radius)


func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	# 锟斤拷锟杰匡拷锟狡敌凤拷锟斤拷位
	for u in _selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
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
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func _find_enemy_at_world(world_pos: Vector2) -> Unit:
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team != Unit.Team.RED:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func _draw_overlay() -> void:
	"""锟斤拷 CanvasLayer 锟较伙拷锟斤拷锟斤拷停/锟斤拷戏锟斤拷锟斤拷锟斤拷锟芥（锟斤拷幕锟斤拷锟疥）"""
	var vsize = get_viewport().get_visible_rect().size

	if _game_over:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var is_victory = _winner == "钃濋槦"
		var title = "鑳滃埄锛? if is_victory else "澶辫触锛?
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var font = ThemeDB.fallback_font
		var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - ts / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), _winner + "鑾疯儨",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 閲嶆柊寮€濮?,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 閫€鍑烘父鎴?,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

	elif _paused:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), center - Vector2(40, 50), "  鏆傚仠",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.7, 1.0))
		font.draw_string(get_canvas_item(), center - Vector2(80, -10), "[ESC] 缁х画娓告垙",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -40), "[R] 閲嶆柊寮€濮?,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -70), "[Q] 閫€鍑烘父鎴?,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))


func _draw() -> void:
	# 锟斤拷选锟斤拷锟轿ｏ拷锟斤拷锟斤拷锟斤拷锟疥）
	if _is_dragging:
		var rect = _get_drag_rect()
		if rect.has_area():
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
			draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)

	# 锟斤拷锟斤拷锟斤拷锟侥Ｊ斤拷锟绞?
	if _attack_cursor_mode:
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		const CROSS_SIZE: float = 12.0
		var cross_color = Color(1.0, 0.2, 0.2, 0.9)
		draw_line(world_mouse + Vector2(-CROSS_SIZE, 0), world_mouse + Vector2(CROSS_SIZE, 0), cross_color, 2.0)
		draw_line(world_mouse + Vector2(0, -CROSS_SIZE), world_mouse + Vector2(0, CROSS_SIZE), cross_color, 2.0)
		draw_circle(world_mouse, CROSS_SIZE * 0.6, cross_color, false, 1.5)

	# 锟斤拷锟斤拷锟斤拷拽预锟斤拷
	if _orbit_is_dragging:
		var start = _screen_to_world(_orbit_drag_start)
		var end = _screen_to_world(_orbit_drag_end)
		var radius = start.distance_to(end)
		draw_circle(start, radius, Color(0.2, 1.0, 0.5, 0.2), false, 2.0)
		draw_line(start, end, Color(0.2, 1.0, 0.5, 0.8), 2.0)

	# 锟斤拷锟狡癸拷锟斤拷锟绞?
	if _orbit_cursor_mode:
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		var orbit_color = Color(0.2, 1.0, 0.5, 0.9)
		draw_circle(world_mouse, 14.0, orbit_color, false, 2.0)
		draw_circle(world_mouse, 10.0, Color(0.2, 1.0, 0.5, 0.3), true)
		# 锟斤拷头指示锟斤拷锟狡凤拷锟斤拷
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
			if not is_instance_valid(unit) or unit.hull <= 0:
				continue
			var size = unit.collision_shape.shape.size
			var half = size / 2
			var unit_rect = Rect2(unit.global_position - half, size)
			if unit_rect.has_point(click_world):
				# ---- 双锟斤拷锟斤拷猓貉★拷锟斤拷锟斤拷锟酵拷嗟ノ?----
				var now = Time.get_ticks_msec() / 1000.0
				if unit == _last_clicked_unit and (now - _last_click_time) < DOUBLE_CLICK_TIME:
					_clear_selection()
					for u in _units:
						if not is_instance_valid(u) or u.hull <= 0:
							continue
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
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
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
		push_error("锟诫将 unit.tscn 锟斤拷锟斤拷 Main 锟节碉拷锟?Unit Scene 锟斤拷锟皆ｏ拷")
		return

	# 每锟斤拷锟斤拷锟接憋拷桑锟斤拷锟斤拷秃鸥锟揭伙拷锟?
	var fleet: Array[Array] = [
		[Unit.ShipClass.BATTLESHIP, 1],
		[Unit.ShipClass.CRUISER, 1],
		[Unit.ShipClass.DESTROYER, 1],
		[Unit.ShipClass.FRIGATE, 1],
		[Unit.ShipClass.DRONE, 1],
	]

	_spawn_fleet(Unit.Team.BLUE, 250, fleet)
	_spawn_fleet(Unit.Team.RED, 7000, fleet)

	# 锟斤拷头锟斤拷锟脚碉拷锟秸猴拷锟斤拷示双锟斤拷锟斤拷锟叫斤拷锟斤拷
	_fit_camera_to_fleets()


func _spawn_fleet(team: Unit.Team, center_x: int, fleet: Array[Array]) -> void:
	var color = Color(0.2, 0.5, 1.0) if team == Unit.Team.BLUE else Color(1.0, 0.25, 0.25)
	var y_center = 500.0
	var dir = 1 if team == Unit.Team.BLUE else -1
	var x_offset := 0

	# 锟届方锟斤拷锟斤拷锟斤拷锟斤拷锟绞碉拷志锟斤拷锟叫★拷锟斤拷锟剿拷锟斤拷诓啵拷锟斤拷锟斤拷锟斤拷
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

	# 同锟酵号飞达拷使锟斤拷同一锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷
	var loadout: Array
	if _weapon_loadout_cache.has(class_type):
		loadout = _weapon_loadout_cache[class_type]
	else:
		loadout = []
		var i := 0
		while i < unit.slot_count:
			var w = Weapon.create_random()
			loadout.append(w)
			if i + 1 < unit.slot_count:
				loadout.append(w)  # 锟斤拷锟斤拷一锟皆ｏ拷锟斤拷锟斤拷锟斤拷同
			i += 2
		_weapon_loadout_cache[class_type] = loadout

	for i in range(unit.slot_count):
		unit._slot_weapons[i] = loadout[i]
	unit.refresh_weapon_visuals()

	return unit


# ==================== 锟斤拷锟较低?====================

func _assign_control_group(group_idx: int) -> void:
	_clean_control_groups()
	var group = _control_groups[group_idx]
	# 锟斤拷锟斤拷锟叫╋拷锟轿伙拷诰杀锟斤拷锟叫的硷拷录
	for u in _selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		# 锟接旧憋拷锟斤拷瞥锟?
		for gi in range(10):
			if gi == group_idx: continue
			var old_group: Array = _control_groups[gi]
			if u in old_group:
				old_group.erase(u)
				break
			
			u.control_group = -1
	# 锟斤拷锟接碉拷锟铰憋拷锟?
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


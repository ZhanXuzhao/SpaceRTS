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

# ----- 控制组（10组，每组存一个Array[Unit]）----
var _control_groups: Array = [[], [], [], [], [], [], [], [], [], []]

# ----- 双击检测 -----
var _last_click_time: float = 0.0
var _last_clicked_unit: Unit = null
const DOUBLE_CLICK_TIME: float = 0.3

# ----- 数字键双击（镜头移动）----
var _last_number_key: int = -1
var _last_number_time: float = 0.0

# ----- 武器配置缓存（同型号共用一套）-----
var _weapon_loadout_cache: Dictionary = {}

# ----- 游戏速度（- 减半 / = 加倍）-----
var _game_speed: float = 1.0

# ----- A 键攻击模式 -----
var _attack_cursor_mode: bool = false
# ----- W 键环绕模式 -----
var _orbit_cursor_mode: bool = false
# ----- 技能施法选择模式（索引 3=跃迁, 4=减速, -1=关闭）----
var _skill_targeting_mode: int = -1
var _skill_targeting_units: Array[Unit] = []
var _orbit_drag_start: Vector2 = Vector2.ZERO  # W 拖拽起点
var _orbit_drag_end: Vector2 = Vector2.ZERO
var _orbit_is_dragging: bool = false

# ----- 相机 -----
var _camera: Camera2D
var _zoom_target: float = 1.0
var _minimap_node: Node2D
var _minimap_container: ColorRect
var _follow_unit: Unit = null  # F 键跟随目标

# ----- 游戏结束状态 -----
var _game_over: bool = false
var _winner: String = ""

# ----- 暂停 -----
var _paused: bool = false

# ----- AI 控制器 -----
var _ai_controllers: Array = []
const _AI_CTL_SCRIPT = preload("res://scripts/ai_controller.gd")

# ----- 菜单覆图层（CanvasLayer 始终在顶层） -----
var _overlay: CanvasLayer


func _ready() -> void:
	# 暂停时 Main 仍需接收输入
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 全屏
	var screen_size = DisplayServer.screen_get_size()
	get_window().size = screen_size
	get_window().mode = Window.MODE_FULLSCREEN

	# 相机（场景中已有节点）
	_camera = $Camera2D
	_camera.enabled = true
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.global_position = Vector2(700, 300)
	_camera.make_current()

	# 小地图（场景中已有 MinimapLayer > MinimapContainer > Minimap）
	_minimap_node = $MinimapLayer/MinimapContainer/Minimap
	_minimap_node.camera_ref = _camera
	_minimap_container = $MinimapLayer/MinimapContainer
	# 初始定位到右上角
	var vsize = get_viewport().get_visible_rect().size
	_minimap_container.position = Vector2(vsize.x - _minimap_container.size.x - 10, 10)

	# 菜单覆图层（场景中实例化 Overlay.tscn）
	_overlay = $OverlayLayer
	_overlay.main = self
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false

	# ---- HUD（场景中已有 HudLayer > Hud）---
	var hud = $HudLayer/Hud
	hud.main = self

	_spawn_units()

	# ---- AI 控制器（管理红队全部 AI 决策）----
	_ai_controller_init()


func _process(delta: float) -> void:
	if _game_over or _paused:
		if _paused:
			_minimap_node.queue_redraw()
		return
	_check_game_over()

	# 清理已释放的单位引用（原地过滤，保持 all_units 引用一致）
	var i := 0
	while i < _units.size():
		if not is_instance_valid(_units[i]):
			_units.remove_at(i)
		else:
			i += 1

	# ---- AI 控制器（红队/黄队 AI 决策）----
	for ctl in _ai_controllers:
		if ctl != null:
			ctl.process_ai(delta)

	# ---- 边缘滚屏 ----
	_edge_scroll(delta)

	# ---- 相机平滑缩放 ----
	_camera.zoom = _camera.zoom.lerp(Vector2(_zoom_target, _zoom_target), delta * 8.0)

	# ---- 镜头跟随 ----
	if _follow_unit != null and is_instance_valid(_follow_unit) and _follow_unit.hull > 0:
		_camera.position = _camera.position.lerp(_follow_unit.global_position, delta * 5.0)
	elif _follow_unit != null:
		_follow_unit = null

	# ---- 定位小地图容器（右上角）----
	var vsize = get_viewport().get_visible_rect().size
	_minimap_container.position = Vector2(vsize.x - _minimap_container.size.x - 10, 10)

	# ---- 更新小地图 ----
	_minimap_node.units = _units
	_minimap_node.camera_pos = _camera.global_position
	_minimap_node.camera_zoom = _camera.zoom
	_minimap_node.queue_redraw()

	# 施法选择模式下持续重绘，圆圈跟随单位移动
	if _skill_targeting_mode >= 0:
		queue_redraw()


func _edge_scroll(delta: float) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var edge_size := 30
	var scroll_speed: float = GameConfig.SCROLL_SPEED * delta / _camera.zoom.x
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
	var alive: Dictionary = {}  # Team → count
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		alive[unit.team] = alive.get(unit.team, 0) + 1

	# 只剩一个阵营存活时结束
	if alive.keys().size() <= 1:
		_game_over = true
		if alive.has(Unit.Team.BLUE):
			_winner = "蓝队"
		elif alive.has(Unit.Team.RED):
			_winner = "红队"
		elif alive.has(Unit.Team.YELLOW):
			_winner = "黄队"
		elif alive.has(Unit.Team.GREEN):
			_winner = "绿队"
		else:
			_winner = "无"
		_overlay.show(); _overlay.build_menu()


func _resume_game() -> void:
	_paused = false
	get_tree().paused = false
	_overlay.hide_menu()


func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	# ---- 游戏结束 / 暂停时的键盘操作 ---
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
		return

	# ---- 键盘事件统一在 _input 处理 ----
	if event is InputEventKey:
		_handle_keyboard(event)
		return

	# ---- 鼠标滚轮 ----
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_target = clamp(_zoom_target * 1.1, 0.3, 3.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_target = clamp(_zoom_target / 1.1, 0.3, 3.0)

	# ---- 拖拽中更新（鼠标移动）----
	if event is InputEventMouseMotion:
		if _is_dragging:
			_drag_end = _screen_to_world(event.position)
			queue_redraw()
		if _orbit_is_dragging:
			_orbit_drag_end = event.position
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# ---- 鼠标左键/右键在 GUI 之后处理，避免穿透 UI ----
	if not (event is InputEventMouseButton):
		return

	# 清除已死亡的选中单位
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_left_click(event)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click_input(event)


func _handle_keyboard(event: InputEvent) -> void:
	if not event.pressed:
		return

	# ---- F5：快速重新开始 ----
	if event.keycode == KEY_F5:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return

	# ---- ESC 暂停 ----
	if event.keycode == KEY_ESCAPE:
		_paused = true
		get_tree().paused = true
		_attack_cursor_mode = false
		_overlay.show(); _overlay.build_menu()
		return

	# ---- 清除已死亡的选中单位 ----
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)

	match event.keycode:
		KEY_W:
			if not event.echo:
				if _selected_units.size() > 0:
					_orbit_cursor_mode = not _orbit_cursor_mode
				else:
					_orbit_cursor_mode = false
				_attack_cursor_mode = false
				queue_redraw()
		KEY_A:
			if event.ctrl_pressed and not event.echo:
				_clear_selection()
				for unit in _units:
					if not is_instance_valid(unit):
						continue
					if unit.team == Unit.Team.BLUE and unit.hull > 0:
						unit.is_selected = true
						_selected_units.append(unit)
				_attack_cursor_mode = false
				_orbit_cursor_mode = false
				queue_redraw()
			elif not event.echo:
				_attack_cursor_mode = not _attack_cursor_mode
				_orbit_cursor_mode = false
				queue_redraw()
		KEY_H:
			if not event.echo:
				_center_camera_on_selection()
				_follow_unit = null
		KEY_F:
			if not event.echo:
				if _selected_units.size() > 0:
					_follow_unit = _selected_units[0]
					_camera.position = _follow_unit.global_position
				else:
					_follow_unit = null
		KEY_G:
			if not event.echo:
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.attack_mode = ((u.attack_mode + 1) % 3) as Unit.AttackMode
				queue_redraw()
		KEY_Z:
			if not event.echo:
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(0)
		KEY_X:
			if not event.echo:
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(1)
		KEY_C:
			if not event.echo:
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(2)
		KEY_V:
			if not event.echo and _selected_units.size() > 0:
				enter_skill_targeting_mode(3, _selected_units)
		KEY_B:
			if not event.echo and _selected_units.size() > 0:
				enter_skill_targeting_mode(4, _selected_units)
		KEY_N:
			if not event.echo:
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(5)
		KEY_MINUS:
			if not event.echo:
				_game_speed *= 0.5
				Engine.time_scale = _game_speed
		KEY_EQUAL:
			if not event.echo:
				_game_speed *= 2.0
				Engine.time_scale = _game_speed

	# ---- Ctrl+数字：编队 ----
	if event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		_assign_control_group(event.keycode - KEY_0)
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


func _handle_left_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		if _skill_targeting_mode >= 0:
			_handle_skill_targeting_click(event.position)
			return
		if _orbit_cursor_mode:
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


func _handle_right_click_input(event: InputEventMouseButton) -> void:
	if _skill_targeting_mode >= 0:
		_exit_skill_targeting_mode()
		return
	if event.pressed and _selected_units.size() > 0:
		_orbit_cursor_mode = false
		_attack_cursor_mode = false
		_handle_right_click(event.position)




func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen_pos


func enter_skill_targeting_mode(skill_index: int, units: Array) -> void:
	# 冷却判定：所有选中单位均冷却中时提示，不进入施法模式
	var all_on_cd := true
	for u in units:
		if is_instance_valid(u) and u.hull > 0 and u._skill_cooldowns[skill_index] <= 0:
			all_on_cd = false
			break
	if all_on_cd:
		var hud = $HudLayer/Hud
		if hud.has_method("show_message"):
			hud.show_message("冷却中")
		return

	_skill_targeting_mode = skill_index
	_skill_targeting_units = units
	_attack_cursor_mode = false
	_orbit_cursor_mode = false
	queue_redraw()

func _exit_skill_targeting_mode() -> void:
	_skill_targeting_mode = -1
	_skill_targeting_units = []
	queue_redraw()

func _handle_skill_targeting_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var skill_idx = _skill_targeting_mode

	if skill_idx == 3:
		# 跃迁：瞬移到鼠标方向
		var any_cast := false
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				if u._skill_cooldowns[3] <= 0:
					u.jump_to_position(world_pos)
					any_cast = true
		if any_cast:
			var hud = $HudLayer/Hud
			if hud.has_method("hide_message"):
				hud.hide_message()
			_exit_skill_targeting_mode()
		else:
			var hud = $HudLayer/Hud
			if hud.has_method("show_message"):
				hud.show_message("冷却中")
		return

	if skill_idx == 4:
		# 减速：查找目标（任何非蓝方单位）
		var target: Unit = null
		for unit in _units:
			if not is_instance_valid(unit) or unit.hull <= 0 or unit.team == Unit.Team.BLUE:
				continue
			var size = unit.collision_shape.shape.size
			var half = size / 2
			var unit_rect = Rect2(unit.global_position - half, size)
			if unit_rect.has_point(world_pos):
				target = unit
				break

		if target == null:
			# 没点中敌人，提示并留在施法模式
			var hud = $HudLayer/Hud
			if hud.has_method("show_message"):
				hud.show_message("请选择目标")
			return

		var in_range := false
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				var d = u.global_position.distance_to(target.global_position)
				if d <= GameConfig.SKILL_SLOW_RANGE and u._skill_cooldowns[4] <= 0:
					in_range = true
					u.apply_slow_to_target(target)

		if in_range:
			# 施法成功，隐藏提示并退出施法模式
			var hud = $HudLayer/Hud
			if hud.has_method("hide_message"):
				hud.hide_message()
			_exit_skill_targeting_mode()
		else:
			# 超出范围，提示并留在施法模式
			var hud = $HudLayer/Hud
			if hud.has_method("show_message"):
				hud.show_message("超出范围")
		return


## 太空总览行点击处理
func on_overview_unit_clicked(unit: Unit, is_right_click: bool) -> void:
	if not is_instance_valid(unit) or unit.hull <= 0:
		return

	# 技能施法模式
	if _skill_targeting_mode >= 0:
		_handle_overview_skill_targeting(unit)
		return

	if is_right_click:
		# 右键 → 攻击该单位
		var shift_held = Input.is_key_pressed(KEY_SHIFT)
		for u in _selected_units:
			if is_instance_valid(u) and u.hull > 0 and u.team == Unit.Team.BLUE:
				if shift_held:
					u.queue_attack_target(unit)
				else:
					u.attack_target(unit)
		return

	# 左键 → 镜头跟随
	_follow_unit = unit
	_camera.position = unit.global_position


## 太空总览技能施法
func _handle_overview_skill_targeting(target: Unit) -> void:
	var skill_idx = _skill_targeting_mode

	if skill_idx == 3:
		# 跃迁：瞬移到目标位置
		var any_cast := false
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				if u._skill_cooldowns[3] <= 0:
					u.jump_to_position(target.global_position)
					any_cast = true
		if any_cast:
			var hud = $HudLayer/Hud
			if hud.has_method("hide_message"):
				hud.hide_message()
			_exit_skill_targeting_mode()
		else:
			var hud = $HudLayer/Hud
			if hud.has_method("show_message"):
				hud.show_message("冷却中")
		return

	if skill_idx == 4:
		# 减速
		var in_range := false
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				var d = u.global_position.distance_to(target.global_position)
				if d <= GameConfig.SKILL_SLOW_RANGE and u._skill_cooldowns[4] <= 0:
					in_range = true
					u.apply_slow_to_target(target)

		if in_range:
			var hud = $HudLayer/Hud
			if hud.has_method("hide_message"):
				hud.hide_message()
			_exit_skill_targeting_mode()
		else:
			var hud = $HudLayer/Hud
			if hud.has_method("show_message"):
				hud.show_message("超出范围")
		return


func _handle_orbit_click(screen_pos: Vector2, custom_radius: float = -1.0) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var target = _find_unit_at_world(world_pos)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit == target:
			continue  # 自身不环绕自身
		if target != null:
			unit.orbit_target(target, custom_radius)
		else:
			unit.orbit_position(world_pos, custom_radius)


func _handle_attack_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	var enemy = _find_enemy_at_world(world_pos)
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			# A+命中敌方单位 → 攻击该单位
			if shift_held:
				unit.queue_attack_target(enemy)
			else:
				unit.attack_target(enemy)
		else:
			# A+点地 → 全屏攻击移动
			var viewport_size = get_viewport().get_visible_rect().size
			var world_radius = viewport_size.length() / _camera.zoom.x / 2
			unit.attack_area(world_pos, world_radius)


func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	# 不能控制敌方单位
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	for u in _selected_units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != Unit.Team.BLUE:
			return
	var enemy = _find_enemy_at_world(world_pos)
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	for unit in _selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			if shift_held:
				unit.queue_attack_target(enemy)
			else:
				unit.attack_target(enemy)
		else:
			if shift_held:
				unit.queue_move_to(world_pos)
			else:
				unit.move_to(world_pos)


func _ai_controller_init() -> void:
	# 红方指挥官：优先攻击小船
	var ai_red = _AI_CTL_SCRIPT.new()
	ai_red.init(_units, Unit.Team.RED, _AI_CTL_SCRIPT.TargetPref.SMALL_FIRST)
	add_child(ai_red)
	_ai_controllers.append(ai_red)

	# 黄方指挥官：优先攻击大船
	var ai_yellow = _AI_CTL_SCRIPT.new()
	ai_yellow.init(_units, Unit.Team.YELLOW, _AI_CTL_SCRIPT.TargetPref.BIG_FIRST)
	add_child(ai_yellow)
	_ai_controllers.append(ai_yellow)

	# 绿方指挥官：优先攻击总威胁度最高的阵营中的高威胁单位
	var ai_green = _AI_CTL_SCRIPT.new()
	ai_green.init(_units, Unit.Team.GREEN, _AI_CTL_SCRIPT.TargetPref.THREAT_FOCUS)
	add_child(ai_green)
	_ai_controllers.append(ai_green)


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
		if not is_instance_valid(unit) or unit.team == Unit.Team.BLUE:
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
	"""在 CanvasLayer 上绘制临时游戏结束画面（屏幕坐标）"""
	var vsize = get_viewport().get_visible_rect().size

	if _game_over:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var is_victory = _winner == "蓝队"
		var title = "胜利" if is_victory else "失败"
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

	# 环绕拖拽预览
	if _orbit_is_dragging:
		var start = _screen_to_world(_orbit_drag_start)
		var end = _screen_to_world(_orbit_drag_end)
		var radius = start.distance_to(end)
		draw_circle(start, radius, Color(0.2, 1.0, 0.5, 0.2), false, 2.0)
		draw_line(start, end, Color(0.2, 1.0, 0.5, 0.8), 2.0)

	# 技能施法选择模式 → 半透明填充 + 描边
	if _skill_targeting_mode == 3:
		var jump_fill = Color(0.8, 0.3, 1.0, 0.08)
		var jump_stroke = Color(0.8, 0.3, 1.0, 0.6)
		# 跃迁：在每个选中单位周围 → 2000 范围
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				draw_circle(u.global_position, GameConfig.SKILL_JUMP_MAX_DIST, jump_fill, true)
				draw_circle(u.global_position, GameConfig.SKILL_JUMP_MAX_DIST, jump_stroke, false, 2.0)
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		draw_circle(world_mouse, 8.0, jump_stroke, false, 2.0)
		# 鼠标位置到选中中心的方向指示器
		var center = _get_selection_center()
		if center != null:
			var dir = (world_mouse - center).normalized()
			var arrow_tip = world_mouse
			var arrow_base = world_mouse - dir * 20.0
			draw_line(arrow_base, arrow_tip, jump_stroke, 3.0)
			draw_line(arrow_tip, arrow_tip + dir.rotated(2.5) * 8.0, jump_stroke, 2.0)
			draw_line(arrow_tip, arrow_tip + dir.rotated(-2.5) * 8.0, jump_stroke, 2.0)

	if _skill_targeting_mode == 4:
		var slow_fill = Color(0.6, 0.2, 0.8, 0.08)
		var slow_stroke = Color(0.6, 0.2, 0.8, 0.6)
		# 减速：绘制每个选中单位 → 1000 施法范围
		for u in _skill_targeting_units:
			if is_instance_valid(u) and u.hull > 0:
				draw_circle(u.global_position, GameConfig.SKILL_SLOW_RANGE, slow_fill, true)
				draw_circle(u.global_position, GameConfig.SKILL_SLOW_RANGE, slow_stroke, false, 2.0)
		var world_mouse = _screen_to_world(get_viewport().get_mouse_position())
		draw_circle(world_mouse, 6.0, slow_stroke, false, 2.0)

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


func _get_selection_center():
	if _skill_targeting_units.size() == 0:
		return null
	var sum := Vector2.ZERO
	var count := 0
	for u in _skill_targeting_units:
		if is_instance_valid(u) and u.hull > 0:
			sum += u.global_position
			count += 1
	if count > 0:
		return sum / count
	return null


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
				# ---- 双击检测：选中所有同类单位 ----
				var now = Time.get_ticks_msec() / 1000.0
				if unit == _last_clicked_unit and (now - _last_click_time) < DOUBLE_CLICK_TIME:
					_clear_selection()
					for u in _units:
						if not is_instance_valid(u):
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
		if not is_instance_valid(unit) or unit.team != Unit.Team.BLUE:
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

	Unit.reset_name_pool()

	# 每方舰队编成
	var fleet: Array[Array] = [
		[Unit.ShipClass.BATTLESHIP, 1],
		[Unit.ShipClass.CRUISER, 2],
		[Unit.ShipClass.DESTROYER, 2],
		[Unit.ShipClass.FRIGATE, 4],
	]

	# 四方正方形分布
	_spawn_fleet(Unit.Team.BLUE, 1000, fleet, 800)         # 左下
	_spawn_fleet(Unit.Team.RED, 6000, fleet, 800)          # 右下
	_spawn_fleet(Unit.Team.YELLOW, 1000, fleet, -3000)     # 左上
	_spawn_fleet(Unit.Team.GREEN, 6000, fleet, -3000)      # 右上

	# 镜头缩放到刚好显示双方所有舰队
	_fit_camera_to_fleets()


const V_SPREAD_ANGLE := 120.0       # V字翅膀展开角度（度）
const SPRITE_BASE_SIZE := 64.0       # 飞船精灵基准尺寸（像素）

func _spawn_fleet(team: Unit.Team, center_x: int, fleet: Array[Array], center_y: float = 500.0, facing_rotation: float = NAN) -> void:
	var color: Color
	var forward_dir: Vector2
	match team:
		Unit.Team.BLUE:
			color = Color(0.2, 0.5, 1.0)
			forward_dir = Vector2.RIGHT
		Unit.Team.RED:
			color = Color(1.0, 0.25, 0.25)
			forward_dir = Vector2.LEFT
		Unit.Team.YELLOW:
			color = Color(1.0, 0.8, 0.1)
			forward_dir = Vector2.DOWN
		Unit.Team.GREEN:
			color = Color(0.2, 1.0, 0.3)
			forward_dir = Vector2.LEFT
	var y_center = center_y

	# V字翅膀方向：从尖端向后延伸并向外展开
	var half_angle = deg_to_rad(V_SPREAD_ANGLE / 2.0)
	var backward = -forward_dir
	var wing_up   = backward.rotated( half_angle)   # 上翼（向后+向上）
	var wing_down = backward.rotated(-half_angle)   # 下翼（向后+向下）

	# 出生朝向与 V 字尖端一致
	var v_rotation = forward_dir.angle() if is_nan(facing_rotation) else facing_rotation

	# 计算每种船型的尺寸倍率
	var class_size: Dictionary = {}  # ShipClass → size_mult
	for entry in fleet:
		var sc: Unit.ShipClass = entry[0]
		class_size[sc] = pow(1.5, Unit._ship_class_tier(sc))

	# 中心（V字尖端）：最大的船（fleet[0] = BATTLESHIP）
	var center_sc: Unit.ShipClass = fleet[0][0]
	var center_unit = _create_unit(team, center_sc, color)
	center_unit.position = Vector2(center_x, y_center)
	center_unit._body.rotation = v_rotation

	# 其余船依次往两边交替排列，大的靠内，小的靠外
	var left_classes: Array[Unit.ShipClass] = []
	var right_classes: Array[Unit.ShipClass] = []
	var toggle := true
	for i in range(1, fleet.size()):
		var sc: Unit.ShipClass = fleet[i][0]
		var cnt: int = fleet[i][1]
		for _j in range(cnt):
			if toggle:
				left_classes.append(sc)
			else:
				right_classes.append(sc)
			toggle = not toggle

	# 统一间距 = 最大船（战列舰）尺寸 × 1.5
	var spacing = class_size[center_sc] * 1.5 * SPRITE_BASE_SIZE

	# 放置左翼（上侧）
	var prev_pos = center_unit.position
	for i in range(left_classes.size()):
		var sc = left_classes[i]
		var new_pos = prev_pos + wing_up * spacing
		var unit = _create_unit(team, sc, color)
		unit.position = new_pos
		unit._body.rotation = v_rotation
		prev_pos = new_pos

	# 放置右翼（下侧）
	prev_pos = center_unit.position
	for i in range(right_classes.size()):
		var sc = right_classes[i]
		var new_pos = prev_pos + wing_down * spacing
		var unit = _create_unit(team, sc, color)
		unit.position = new_pos
		unit._body.rotation = v_rotation
		prev_pos = new_pos


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
	unit.all_units = _units
	add_child(unit)
	_units.append(unit)

	# 同型号飞船使用同一套武器配置
	var loadout: Array
	if _weapon_loadout_cache.has(class_type):
		loadout = _weapon_loadout_cache[class_type]
	else:
		loadout = []
		var pairs := unit.slot_count >> 1  # 插槽对数
		var i := 0
		while i < unit.slot_count:
			var w: Weapon
			# 最后一对插槽：如果前面全是 PD，强制生成非 PD 武器
			if pairs > 1 and i >= (pairs - 1) * 2:
				var all_pd := true
				for j in range(0, i, 2):
					if loadout[j].weapon_type != Weapon.WeaponType.PD:
						all_pd = false
						break
				w = Weapon.create_random_offensive() if all_pd else Weapon.create_random()
			else:
				w = Weapon.create_random()
			loadout.append(w)
			if i + 1 < unit.slot_count:
				loadout.append(w)  # 左右一对，武器相同
			i += 2
		_weapon_loadout_cache[class_type] = loadout

	for i in range(unit.slot_count):
		unit._slot_weapons[i] = loadout[i]
	unit.refresh_weapon_visuals()

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

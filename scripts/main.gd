extends Node2D

const _Building = preload("res://scripts/building.gd")

## 单位预制场景
@export var unit_scene: PackedScene
## 建筑预制场景
@export var building_scene: PackedScene
## 矿场预制场景
@export var mineral_field_scene: PackedScene

var _units: Array[Unit] = []
var _buildings: Array = []
var _mineral_fields: Array = []

## 各阵营的矿物储量 team_name → float
var team_minerals: Dictionary = {}

# ----- 框选状态 -----
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

# ----- 选中单位集合 -----
var _selected_units: Array[Unit] = []
## 当前选中的建筑（点击建筑时设置）
var _selected_building = null

# ----- 控制组（10组，每组存一个Array[Unit]）----
var _control_groups: Array = [[], [], [], [], [], [], [], [], [], []]

# ----- 双击检测 -----
var _last_click_time: float = 0.0
var _last_clicked_unit: Unit = null
const DOUBLE_CLICK_TIME: float = 0.3

# ----- 数字键双击（镜头移动）----
var _last_number_key: int = -1
var _last_number_time: float = 0.0

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
var _minimap_node
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


# ----- 阵营属性 -----
## 颜色调色板（按索引循环分配）
const _TEAM_COLOR_PALETTE := [
	Color(0.2, 0.5, 1.0),    # 蓝
	Color(1.0, 0.25, 0.25),  # 红
	Color(1.0, 0.8, 0.1),    # 黄
	Color(0.2, 1.0, 0.3),    # 绿
	Color(0.7, 0.2, 1.0),    # 紫
	Color(1.0, 0.6, 0.0),    # 橙
	Color(0.0, 1.0, 1.0),    # 青
	Color(1.0, 1.0, 1.0),    # 白
	Color(1.0, 0.4, 0.7),    # 粉
	Color(0.4, 1.0, 0.2),    # 柠
]
## 阵营名随机生成词库
const _FACTION_NAME_PREFIX := ["星辉","暗影","极光","深渊","苍穹","烈焰","冰霜","雷霆","风暴","铁血","神威","天罚","银河","曙光","永恒","混沌","星云","猩红"]
const _FACTION_NAME_SUFFIX := ["军团","舰队","联盟","帝国","联邦","集团","议会","王国","战盟"]

## 正多边形布局参数：中心点、边长
const _POLYGON_CENTER := Vector2(3500, -600)
const _SIDE_LENGTH := 6000.0

## 随机生成阵营名称
static func _generate_faction_name() -> String:
	return _FACTION_NAME_PREFIX[randi() % _FACTION_NAME_PREFIX.size()] \
		+ _FACTION_NAME_SUFFIX[randi() % _FACTION_NAME_SUFFIX.size()]

## 当前局生成的阵营数据（索引=阵营序号）
var faction_team_names: Array[String] = []
var faction_team_colors: Array[Color] = []
## 玩家阵营名（faction_team_names[0] 的快捷引用）
var _player_team_name: String = ""


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

	# 清理已释放的建筑引用
	i = 0
	while i < _buildings.size():
		if not is_instance_valid(_buildings[i]):
			_buildings.remove_at(i)
		else:
			i += 1

	# 清理已释放的矿场引用
	i = 0
	while i < _mineral_fields.size():
		if not is_instance_valid(_mineral_fields[i]):
			_mineral_fields.remove_at(i)
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

	# ---- 更新小地图（每 3 帧一次）----
	if Engine.get_process_frames() % 3 == 0:
		_minimap_node.units = _units
		_minimap_node.buildings = _buildings
		_minimap_node.mineral_fields = _mineral_fields
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
	# 仅一个阵营时不判定游戏结束（方便自由测试）
	if faction_team_names.size() <= 1:
		return

	var alive: Dictionary = {}  # team_name → count
	for unit in _units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		alive[unit.team] = alive.get(unit.team, 0) + 1

	# 只剩一个阵营存活时结束
	if alive.keys().size() <= 1:
		_game_over = true
		if alive.size() == 1:
			_winner = alive.keys()[0] as String
		else:
			_winner = "无"
		_overlay.show(); _overlay.build_menu()


func _resume_game() -> void:
	_paused = false
	get_tree().paused = false
	_overlay.hide_menu()


func _restart_game() -> void:
	get_tree().paused = false
	# 清理静态数据
	team_minerals.clear()
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
	if _selected_building != null and not is_instance_valid(_selected_building):
		_selected_building = null

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
					if unit.team == _player_team_name and unit.hull > 0:
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
		KEY_T:
			if not event.echo and _selected_units.size() > 0:
				# 收集当前选中单位的类型集合
				var types := {}
				for u in _selected_units:
					if is_instance_valid(u) and u.hull > 0:
						types[u.class_type] = true
				_clear_selection()
				for u in _units:
					if not is_instance_valid(u) or u.hull <= 0:
						continue
					if u.team == _player_team_name and types.has(u.class_type):
						u.is_selected = true
						_selected_units.append(u)
				_attack_cursor_mode = false
				_orbit_cursor_mode = false
				queue_redraw()
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
			if not is_instance_valid(unit) or unit.hull <= 0 or unit.team == _player_team_name:
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
			if is_instance_valid(u) and u.hull > 0 and u.team == _player_team_name:
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
		if not is_instance_valid(u) or u.hull <= 0 or u.team != _player_team_name:
			return
	var enemy = _find_enemy_at_world(world_pos)
	var shift_held = Input.is_key_pressed(KEY_SHIFT)

	# 多单位移动时计算阵型偏移（只在非攻击指令时生效）
	var formation_offsets: Array[Vector2] = []
	var _formation_forward_rot: float = INF  # 阵型朝向（弧度）
	if _selected_units.size() > 1 and enemy == null:
		formation_offsets = _calc_v_formation(_selected_units, world_pos)
		# 计算阵型朝向：领队（最大船）→ 目标点的射线角度
		var leader: Unit = _selected_units[0]
		for u in _selected_units:
			if u._size_mult > leader._size_mult:
				leader = u
		_formation_forward_rot = (world_pos - leader.global_position).angle()

	for i in range(_selected_units.size()):
		var unit = _selected_units[i]
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			if shift_held:
				unit.queue_attack_target(enemy)
			else:
				unit.attack_target(enemy)
		else:
			var target_pos = world_pos
			if i < formation_offsets.size():
				target_pos = world_pos + formation_offsets[i]
			if shift_held:
				unit.queue_move_to(target_pos, _formation_forward_rot)
			else:
				unit.move_to(target_pos, _formation_forward_rot)


const FORMATION_BASE_SPACING := 200.0

## 计算 V 字阵型偏移量（相对于顶点）
## sizes: 按尺寸降序排列的 _size_mult 数组
## forward: V 字尖端指向方向
## spacing: 基础间距
## 返回与 sizes 顺序对应的偏移数组，[0] 在顶点
static func _calc_v_formation_offsets(sizes: Array, forward: Vector2, spacing: float) -> Array[Vector2]:
	var right := Vector2(forward.y, -forward.x)
	var count = sizes.size()
	var offsets: Array[Vector2] = []
	offsets.append(Vector2.ZERO)  # 顶点（最大船）

	var idx := 1
	while idx < count:
		var layer := (idx + 1) * 0.5  # 第几对，从 1 开始
		var back = layer * spacing * 0.8
		var spread = layer * spacing * 1.0
		# 左翼
		offsets.append(-forward * back - right * spread)
		idx += 1
		if idx < count:
			# 右翼
			offsets.append(-forward * back + right * spread)
			idx += 1

	return offsets


func _calc_v_formation(units: Array, target_pos: Vector2) -> Array[Vector2]:
	"""计算移动 V 字阵型
	- 目标点 = 阵型顶点（最大船停在目标点）
	- 方向 = 领队（最大船）当前位置 → 目标点的射线
	- 按船型从大到小排布：大船居中靠前，小船展开两翼
	- 返回值保持与 units 入参顺序一致
	"""
	# 筛选有效单位
	var valid: Array[Unit] = []
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			valid.append(u)
	var count = valid.size()
	if count == 0:
		return []

	# 找到领队（尺寸最大的船）
	var leader: Unit = valid[0]
	for u in valid:
		if u._size_mult > leader._size_mult:
			leader = u

	# 前进方向：领队当前位置 → 目标点
	var forward := (target_pos - leader.global_position).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector2.RIGHT

	# 平均尺寸决定基础间距
	var avg_size := 0.0
	for u in valid:
		avg_size += u._size_mult
	avg_size /= count
	var spacing := FORMATION_BASE_SPACING * avg_size

	# 按尺寸从大到小排序
	var sorted = valid.duplicate()
	sorted.sort_custom(func(a, b): return a._size_mult > b._size_mult)

	# 提取尺寸数组计算偏移
	var sorted_sizes: Array[float] = []
	for u in sorted:
		sorted_sizes.append(u._size_mult)
	var sorted_offsets = _calc_v_formation_offsets(sorted_sizes, forward, spacing)

	# 映射回原始入参顺序
	var unit_to_offset: Dictionary = {}
	for i in range(count):
		unit_to_offset[sorted[i]] = sorted_offsets[i]

	var result: Array[Vector2] = []
	result.resize(units.size())
	for i in range(units.size()):
		var u = units[i]
		if is_instance_valid(u) and u.hull > 0 and unit_to_offset.has(u):
			result[i] = unit_to_offset[u]
		else:
			result[i] = Vector2.ZERO
	return result


func _ai_controller_init() -> void:
	# 除第一个阵营（玩家）外，其余阵营由AI指挥官控制，偏好随机分配
	var prefs = [
		_AI_CTL_SCRIPT.TargetPref.SMALL_FIRST,
		_AI_CTL_SCRIPT.TargetPref.BIG_FIRST,
		_AI_CTL_SCRIPT.TargetPref.THREAT_FOCUS,
	]
	var count = mini(GameConfig.faction_config.size(), 999)
	for i in range(1, count):
		var team_name = faction_team_names[i]
		var pref = prefs[randi() % prefs.size()]
		var ai = _AI_CTL_SCRIPT.new()
		ai.init(_units, team_name, pref)
		add_child(ai)
		_ai_controllers.append(ai)


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
		if not is_instance_valid(unit) or unit.team == _player_team_name:
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
		var is_victory = _winner == _player_team_name
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
						if u.team == _player_team_name and u.class_type == unit.class_type:
							u.is_selected = true
							_selected_units.append(u)
				else:
					# Shift+点击已选中的友军 → 反选
					if Input.is_key_pressed(KEY_SHIFT) and unit.team == _player_team_name and unit in _selected_units:
						unit.is_selected = false
						_selected_units.erase(unit)
					else:
						unit.is_selected = true
						if unit not in _selected_units:
							_selected_units.append(unit)
				_last_click_time = now
				_last_clicked_unit = unit
				return
		# ---- 没点中单位，检查是否点击了建筑 ----
		for building in _buildings:
			if not is_instance_valid(building):
				continue
			var bsize = GameConfig.BUILDING_SIZE * 2
			var b_rect = Rect2(building.global_position - Vector2(bsize, bsize), Vector2(bsize * 2, bsize * 2))
			if b_rect.has_point(click_world):
				_clear_selection()
				_selected_building = building
				building._is_selected = true
				building.queue_redraw()
				var hud = $HudLayer/Hud
				if hud.has_method("set_selected_building"):
					hud.set_selected_building(building)
				return
		# 没点中任何东西 → 取消建筑选中
		_selected_building = null
		var hud = $HudLayer/Hud
		if hud.has_method("set_selected_building"):
			hud.set_selected_building(null)
		_clear_selection()
		return

	for unit in _units:
		if not is_instance_valid(unit) or unit.team != _player_team_name:
			continue
		if drag_rect.has_point(unit.global_position):
			if not unit.is_selected:
				unit.is_selected = true
				_selected_units.append(unit)


func _clear_selection() -> void:
	for unit in _selected_units:
		unit.is_selected = false
	_selected_units.clear()
	# 清除建筑选中高亮
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building._is_selected = false
		_selected_building.queue_redraw()
	_selected_building = null
	var hud = $HudLayer/Hud
	if is_instance_valid(hud) and hud.has_method("set_selected_building"):
		hud.set_selected_building(null)


# 配置值 → ShipClass 映射（与 GameConfig.FLEET_* 配合使用）
# -1=随机，1=护卫舰，2=驱逐舰，3=巡洋舰，4=战列舰
const VAL_TO_CLASS := {
	1: Unit.ShipClass.FRIGATE,
	2: Unit.ShipClass.DESTROYER,
	3: Unit.ShipClass.CRUISER,
	4: Unit.ShipClass.BATTLESHIP,
}
const ALL_SHIPS := [
	Unit.ShipClass.FRIGATE,
	Unit.ShipClass.DESTROYER,
	Unit.ShipClass.CRUISER,
	Unit.ShipClass.BATTLESHIP,
]


# ===== 矿物管理 =====

## 获取某阵营的矿物储量
func get_team_minerals(team_name: String) -> float:
	return team_minerals.get(team_name, 0.0)


## 消耗矿物，返回是否成功
func spend_team_minerals(team_name: String, amount: int) -> bool:
	var current = team_minerals.get(team_name, 0.0)
	if current < amount:
		return false
	team_minerals[team_name] = current - amount
	return true


func _on_mineral_deposited(team_name: String, amount: float) -> void:
	team_minerals[team_name] = team_minerals.get(team_name, 0.0) + amount


func _on_ship_produced(team_name: String, ship_type, building) -> void:
	# 生产船只：在建筑附近生成
	if unit_scene == null:
		return

	# 确定船型
	var sc: Unit.ShipClass
	var is_miner := false
	if ship_type is String and ship_type == "miner":
		is_miner = true
		sc = Unit.ShipClass.DRONE  # 用无人机尺寸
	elif ship_type is Unit.ShipClass:
		sc = ship_type
	else:
		return

	# 查找颜色
	var color = Color.WHITE
	for i in faction_team_names.size():
		if faction_team_names[i] == team_name:
			color = faction_team_colors[i]
			break

	# 在建筑附近生成
	var spawn_pos = building.global_position + Vector2(150, 0).rotated(randf() * TAU)
	var unit: Unit = unit_scene.instantiate()
	unit.class_type = sc
	unit.team = team_name
	unit.unit_color = color
	unit.all_units = _units
	add_child(unit)
	unit.global_position = spawn_pos
	_units.append(unit)

	# 如果是采矿船，配置采矿模式
	if is_miner:
		# 找己方矿场
		var home_mine = null
		for b in _buildings:
			if b.team == team_name and b.building_type == _Building.BuildingType.MINE:
				home_mine = b
				break
		if home_mine != null:
			unit.set_as_miner(home_mine)
	else:
		# 战斗船只：分配武器
		var class_idx = Unit._ship_class_tier(sc)
		var configs: Array = GameConfig.WEAPON_CONFIGS.get(class_idx, [[-1]])
		var config: Array = configs[randi() % configs.size()]
		var loadout: Array = []
		var pairs = unit.slot_count >> 1
		for pair_idx in pairs:
			var wt: int = config[pair_idx] if pair_idx < config.size() else GameConfig.WT_RANDOM
			var w := Weapon.create_by_type(wt)
			loadout.append(w)
			if loadout.size() < unit.slot_count:
				loadout.append(w)
		for i in range(unit.slot_count):
			unit._slot_weapons[i] = loadout[i]
		unit.refresh_weapon_visuals()


func _spawn_units() -> void:
	if unit_scene == null:
		push_error("请将 unit.tscn 拖入 Main 节点的 Unit Scene 属性！")
		return

	Unit.reset_name_pool()
	Unit.team_scores.clear()
	Unit.reset_weapon_stats()

	# 根据 GameConfig.faction_config 动态生成阵营（正多边形布局）
	var count = mini(GameConfig.faction_config.size(), 999)
	# 生成阵营名和颜色（颜色循环分配）
	faction_team_names.resize(count)
	faction_team_colors.resize(count)
	for i in range(count):
		faction_team_names[i] = _generate_faction_name()
		faction_team_colors[i] = _TEAM_COLOR_PALETTE[i % _TEAM_COLOR_PALETTE.size()]
	_player_team_name = faction_team_names[0]
	Unit.player_team_name = _player_team_name
	Unit.team_color_map.clear()
	for i in range(count):
		Unit.team_color_map[faction_team_names[i]] = faction_team_colors[i]

	var R = _SIDE_LENGTH / (2.0 * sin(PI / count))
	var start_angle = -PI / 2.0  # 第一个阵营（玩家）在正下方
	for i in range(count):
		var team_name = faction_team_names[i]
		var config: Array = GameConfig.faction_config[i]
		var angle = start_angle + i * TAU / count
		var pos = _POLYGON_CENTER + Vector2(cos(angle), sin(angle)) * R
		var forward_dir = (_POLYGON_CENTER - pos).normalized()

		# ---- 每个阵营出生点后方生成矿场和矿物 ----
		var field_dir = -forward_dir  # 阵营后方
		_spawn_buildings(team_name, pos, field_dir)
		_spawn_mineral_fields(pos, field_dir)

		_spawn_fleet(team_name, pos.x, config, pos.y, forward_dir)

		# ---- 每个阵营初始赠送 1 艘采矿船 ----
		_spawn_start_miner(team_name, pos, field_dir)

	# 初始化各阵营矿物储量（初始 3000）
	for name in faction_team_names:
		team_minerals[name] = 3000.0

	# 玩家单位自动编为1队
	var player_group: Array = _control_groups[1]
	player_group.clear()
	for unit in _units:
		if is_instance_valid(unit) and unit.hull > 0 and unit.team == _player_team_name:
			player_group.append(unit)
			unit.control_group = 1

	# 镜头对准玩家舰队，缩放至舰队宽度占屏幕一半
	var cam_target := Vector2.ZERO
	var player_count := 0
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in _units:
		if is_instance_valid(unit) and unit.hull > 0 and unit.team == _player_team_name:
			cam_target += unit.global_position
			player_count += 1
			min_pos = min_pos.min(unit.global_position)
			max_pos = max_pos.max(unit.global_position)
	if player_count > 0:
		cam_target /= player_count
		_camera.position = cam_target
		var viewport_w = get_viewport().get_visible_rect().size.x
		var fleet_w = max_pos.x - min_pos.x + 200.0  # +200 边距
		_zoom_target = clamp(viewport_w * 0.5 / fleet_w, 0.3, 3.0) if fleet_w > 0 else 1.0
		_camera.zoom = Vector2(_zoom_target, _zoom_target)
		_follow_unit = null


## 将配置字典解析为 ShipClass 列表，按尺寸降序排列（最大船排首位作为 V 字尖端）
func _parse_fleet_config(config: Array) -> Array[Unit.ShipClass]:
	## config = [随机数, 护卫舰数, 驱逐舰数, 巡洋舰数, 战列舰数]
	var result: Array[Unit.ShipClass] = []
	# config[0] = 随机船数量
	for _j in range(config[0]):
		result.append(ALL_SHIPS[randi() % ALL_SHIPS.size()])
	# config[1..4] = 护卫舰~战列舰数量
	for i in range(1, min(config.size(), 5)):
		var count: int = config[i]
		var sc: Unit.ShipClass = VAL_TO_CLASS[i]
		for _j in range(count):
			result.append(sc)
	# 按等级降序排列（大船在前）
	result.sort_custom(func(a, b): return Unit._ship_class_tier(a) > Unit._ship_class_tier(b))
	return result


func _spawn_fleet(team: String, center_x: int, config: Array, center_y: float = 500.0, forward_dir: Vector2 = Vector2.RIGHT) -> void:
	# 根据阵营名查找颜色
	var color = Color.WHITE
	for i in faction_team_names.size():
		if faction_team_names[i] == team:
			color = faction_team_colors[i]
			break

	# 解析配置（已按等级降序排列）
	var ship_classes = _parse_fleet_config(config)
	if ship_classes.size() == 0:
		return

	# 计算每艘船的尺寸和平均尺寸
	var sizes: Array[float] = []
	for sc in ship_classes:
		sizes.append(pow(1.5, Unit._ship_class_tier(sc)))
	var avg_size := 0.0
	for s in sizes:
		avg_size += s
	avg_size /= sizes.size()

	# 使用与移动阵型相同的 V 字算法
	var forward = forward_dir
	var spacing = FORMATION_BASE_SPACING * avg_size
	var offsets = _calc_v_formation_offsets(sizes, forward, spacing)
	var v_rotation = forward.angle()

	var center_pos = Vector2(center_x, center_y)
	for i in range(ship_classes.size()):
		var unit = _create_unit(team, ship_classes[i], color)
		unit.position = center_pos + offsets[i]
		unit._body.rotation = v_rotation


## 在阵营出生点后方生成建筑（矿场 + 船坞）
func _spawn_buildings(team_name: String, base_pos: Vector2, back_dir: Vector2) -> void:
	if building_scene == null:
		return

	# 查找颜色
	var color = Color.WHITE
	for i in faction_team_names.size():
		if faction_team_names[i] == team_name:
			color = faction_team_colors[i]
			break

	# ---- 矿场（在出生点后方稍近处）----
	var mine_pos = base_pos + back_dir * 400
	var mine = building_scene.instantiate()
	mine.building_type = _Building.BuildingType.MINE
	mine.team = team_name
	mine.building_color = color
	mine.global_position = mine_pos
	mine.mineral_deposited.connect(_on_mineral_deposited)
	add_child(mine)
	_buildings.append(mine)

	# ---- 船坞（在矿场旁边）----
	var yard_pos = mine_pos + back_dir.rotated(deg_to_rad(90)) * 200
	var yard = building_scene.instantiate()
	yard.building_type = _Building.BuildingType.SHIPYARD
	yard.team = team_name
	yard.building_color = color
	yard.global_position = yard_pos
	yard.ship_produced.connect(_on_ship_produced)
	add_child(yard)
	_buildings.append(yard)


## 在阵营出生点后方生成矿场
func _spawn_mineral_fields(base_pos: Vector2, back_dir: Vector2) -> void:
	if mineral_field_scene == null:
		return

	# 在阵营后方分散生成3片矿
	for j in range(3):
		var offset_angle = (j - 1) * deg_to_rad(40)
		var spread_dir = back_dir.rotated(offset_angle)
		var field_pos = base_pos + back_dir * 700 + spread_dir * 200
		var field = mineral_field_scene.instantiate()
		field.global_position = field_pos
		field.team = ""  # 中立
		add_child(field)
		_mineral_fields.append(field)
		field.add_to_group("mineral_fields")
		field.field_depleted.connect(_on_field_depleted)


func _on_field_depleted(_field) -> void:
	# 矿枯竭后不做特殊处理（采矿船自动找下一片）
	pass


## 初始赠送一艘采矿船
func _spawn_start_miner(team_name: String, base_pos: Vector2, back_dir: Vector2) -> void:
	if unit_scene == null:
		return

	# 查找颜色
	var color = Color.WHITE
	for i in faction_team_names.size():
		if faction_team_names[i] == team_name:
			color = faction_team_colors[i]
			break

	# 找己方矿场
	var home_mine = null
	for b in _buildings:
		if b.team == team_name and b.building_type == _Building.BuildingType.MINE:
			home_mine = b
			break
	if home_mine == null:
		return

	# 在矿场旁边生成采矿船
	var spawn_pos = home_mine.global_position + back_dir.rotated(deg_to_rad(-60)) * 120
	var unit: Unit = unit_scene.instantiate()
	unit.class_type = Unit.ShipClass.DRONE
	unit.team = team_name
	unit.unit_color = color
	unit.all_units = _units
	add_child(unit)
	unit.global_position = spawn_pos
	_units.append(unit)
	unit.set_as_miner(home_mine)


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


func _create_unit(team: String, class_type: Unit.ShipClass, unit_color: Color) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	unit.class_type = class_type
	unit.team = team
	unit.unit_color = unit_color
	unit.all_units = _units
	add_child(unit)
	_units.append(unit)

	# 根据 GameConfig.WEAPON_CONFIGS 生成武器配置
	var class_idx := Unit._ship_class_tier(class_type)  # 0~4 对应 ShipClass 枚举
	var configs: Array = GameConfig.WEAPON_CONFIGS.get(class_idx, [[-1]])
	# 从多组配置中随机选一组
	var config: Array = configs[randi() % configs.size()]
	var loadout: Array = []
	var pairs := unit.slot_count >> 1
	for pair_idx in pairs:
		var wt: int = config[pair_idx] if pair_idx < config.size() else GameConfig.WT_RANDOM
		# -1 时在全武器池中随机（含PD），避免旧配置被局限
		var w := Weapon.create_by_type(wt)
		loadout.append(w)
		if loadout.size() < unit.slot_count:
			loadout.append(w)  # 左右一对，武器相同

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

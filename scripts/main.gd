extends Node2D

## 单位预制场景
@export var unit_scene: PackedScene
## 建筑预制场景
@export var building_scene: PackedScene
## 矿场预制场景
@export var mineral_field_scene: PackedScene

# ----- 子脚本实例 -----
var _input_handler
var _selection_system
var _draw_helper
var _skill_targeting
var _control_group
var _spawn_system

var units: Array[Unit] = []
var buildings: Array = []
var mineral_fields: Array = []

## 各阵营的矿物储量 team_name → float
var team_minerals: Dictionary = {}

# ----- 框选状态 -----
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO

# ----- 选中单位集合 -----
var selected_units: Array[Unit] = []
## 当前选中的建筑（多选）
var selected_buildings: Array[Building] = []
## 兼容单建筑引用（取第一个选中建筑，用于 HUD 面板显示）
var selected_building: Building:
	get: return selected_buildings[0] if selected_buildings.size() > 0 else null
	set(v):
		selected_buildings.clear()
		if v != null:
			selected_buildings.append(v)

# ----- 控制组（10组，混合存 Unit / Building）----
var control_groups: Array = [[], [], [], [], [], [], [], [], [], []]

# ----- 双击检测 -----
var last_click_time: float = 0.0
var last_clicked_unit: Unit = null
var last_clicked_building: Building = null

# ----- 数字键双击（镜头移动）----
var last_number_key: int = -1
var last_number_time: float = 0.0

# ----- 游戏速度（- 减半 / = 加倍）-----
var game_speed: float = 1.0

# ----- A 键攻击模式 -----
var attack_cursor_mode: bool = false
# ----- W 键环绕模式 -----
var orbit_cursor_mode: bool = false
# ----- 技能施法选择模式（索引 3=跃迁, 4=减速, -1=关闭）----
var skill_targeting_mode: int = -1
var skill_targeting_units: Array[Unit] = []
var orbit_drag_start: Vector2 = Vector2.ZERO  # W 拖拽起点
var orbit_drag_end: Vector2 = Vector2.ZERO
var orbit_is_dragging: bool = false

# ----- 相机 -----
var camera: Camera2D
var zoom_target: float = 1.0
@onready var minimap_node = $MinimapLayer/MinimapContainer/Minimap
var minimap_container: ColorRect
var follow_unit: Unit = null  # F 键跟随目标

# ----- 游戏结束状态 -----
var game_over: bool = false
var winner: String = ""

# ----- 暂停 -----
var paused: bool = false

# ----- AI 控制器 -----
var ai_controllers: Array = []
# ----- 菜单覆图层（CanvasLayer 始终在顶层） -----
var overlay: CanvasLayer


# ----- 阵营属性 -----
## 颜色调色板（按索引循环分配）
const TEAM_COLOR_PALETTE := [
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
## 正多边形布局参数：中心点、边长
const POLYGON_CENTER := Vector2(3500, -600)
const SIDE_LENGTH := 6000.0

## 当前局生成的阵营数据（索引=阵营序号）
var faction_team_names: Array[String] = []
var faction_team_colors: Array[Color] = []
## 玩家阵营名（faction_team_names[0] 的快捷引用）
var player_team_name: String = ""


func _ready() -> void:
	# 暂停时 Main 仍需接收输入
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 全屏
	var screen_size = DisplayServer.screen_get_size()
	get_window().size = screen_size
	get_window().mode = Window.MODE_FULLSCREEN

	# ---- 初始化子脚本 ----
	_input_handler = load("res://scripts/input_handler.gd").new(self)
	_selection_system = load("res://scripts/selection_system.gd").new()
	_draw_helper = load("res://scripts/draw_helper.gd").new()
	_skill_targeting = load("res://scripts/skill_targeting.gd").new()
	_control_group = load("res://scripts/control_group.gd").new()

	# 相机（场景中已有节点）
	camera = $Camera2D
	camera.enabled = true
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.global_position = Vector2(700, 300)
	camera.make_current()

	# 小地图（场景中已有 MinimapLayer > MinimapContainer > Minimap）
	minimap_node.camera_ref = camera
	minimap_container = $MinimapLayer/MinimapContainer
	# 初始定位到右上角
	var vsize = get_viewport().get_visible_rect().size
	minimap_container.position = Vector2(vsize.x - minimap_container.size.x - 10, 10)

	# 菜单覆图层（场景中实例化 Overlay.tscn）
	overlay = $OverlayLayer
	overlay.main = self
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false

	# ---- HUD（场景中已有 HudLayer > Hud）---
	var hud = $HudLayer/Hud
	hud.main = self

	# ---- 生成系统 ----
	_spawn_system = load("res://scripts/spawn_system.gd").new(self)
	_spawn_system.spawn_all()

	# ---- AI 控制器（管理红队全部 AI 决策）----
	_ai_controller_init()


func _process(delta: float) -> void:
	if game_over or paused:
		if paused:
			minimap_node.queue_redraw()
		return
	_check_game_over()

	# 清理已释放的单位引用（原地过滤，保持 all_units 引用一致）
	var i := 0
	while i < units.size():
		if not is_instance_valid(units[i]):
			units.remove_at(i)
		else:
			i += 1

	# 清理已释放的建筑引用
	i = 0
	while i < buildings.size():
		if not is_instance_valid(buildings[i]):
			buildings.remove_at(i)
		else:
			i += 1

	# 清理已释放的矿场引用
	i = 0
	while i < mineral_fields.size():
		if not is_instance_valid(mineral_fields[i]):
			mineral_fields.remove_at(i)
		else:
			i += 1

	# ---- AI 控制器（红队/黄队 AI 决策）----
	for ctl in ai_controllers:
		if ctl != null:
			ctl.process_ai(delta)

	# ---- 地图边界伤害：超出安全圆范围的单位/建筑每秒损失 5% 最大生命 ----
	const MAP_CENTER := GameConfig.MAP_CENTER
	const MAP_RADIUS := GameConfig.MAP_RADIUS
	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		var dist = unit.global_position.distance_to(MAP_CENTER)
		if dist > MAP_RADIUS:
			var dmg = unit.max_hull * GameConfig.MAP_BORDER_DAMAGE_PCT * delta
			unit.take_damage(dmg)
	for building in buildings:
		if not is_instance_valid(building) or building.hull <= 0:
			continue
		var dist = building.global_position.distance_to(MAP_CENTER)
		if dist > MAP_RADIUS:
			var dmg = building.max_hull * GameConfig.MAP_BORDER_DAMAGE_PCT * delta
			building.take_damage(dmg)

	# ---- 边缘滚屏 ----
	_edge_scroll(delta)

	# ---- 相机平滑缩放 ----
	camera.zoom = camera.zoom.lerp(Vector2(zoom_target, zoom_target), delta * 8.0)

	# ---- 镜头跟随 ----
	if follow_unit != null and is_instance_valid(follow_unit) and follow_unit.hull > 0:
		camera.position = camera.position.lerp(follow_unit.global_position, delta * 5.0)
	elif follow_unit != null:
		follow_unit = null

	# ---- 定位小地图容器（右上角）----
	var vsize = get_viewport().get_visible_rect().size
	minimap_container.position = Vector2(vsize.x - minimap_container.size.x - 10, 10)

	# ---- 更新小地图（每 3 帧一次）----
	if Engine.get_process_frames() % 3 == 0:
		minimap_node.units = units
		minimap_node.buildings = buildings
		minimap_node.mineral_fields = mineral_fields
		minimap_node.camera_pos = camera.global_position
		minimap_node.camera_zoom = camera.zoom
		minimap_node.queue_redraw()

	# 施法选择模式下持续重绘，圆圈跟随单位移动
	if skill_targeting_mode >= 0:
		queue_redraw()

	# 选中单位时有指令队列/移动/攻击目标时持续重绘
	if selected_units.size() > 0:
		for u in selected_units:
			if is_instance_valid(u) and (u._is_moving or is_instance_valid(u._current_target) or u._command_queue.size() > 0):
				queue_redraw()
				break


func _edge_scroll(delta: float) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var edge_size := 30
	var scroll_speed: float = GameConfig.SCROLL_SPEED * delta / camera.zoom.x
	var scrolled := false

	if mouse_pos.x < edge_size:
		camera.global_position.x -= scroll_speed
		scrolled = true
	elif mouse_pos.x > viewport_size.x - edge_size:
		camera.global_position.x += scroll_speed
		scrolled = true

	if mouse_pos.y < edge_size:
		camera.global_position.y -= scroll_speed
		scrolled = true
	elif mouse_pos.y > viewport_size.y - edge_size:
		camera.global_position.y += scroll_speed
		scrolled = true

	if scrolled:
		follow_unit = null


func _check_game_over() -> void:
	# 仅一个阵营时不判定游戏结束（方便自由测试）
	if faction_team_names.size() <= 1:
		return

	var alive: Dictionary = {}  # team_name → count
	# 统计存活单位
	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		alive[unit.team] = alive.get(unit.team, 0) + 1
	# 统计存活建筑
	for building in buildings:
		if not is_instance_valid(building) or building.hull <= 0:
			continue
		alive[building.team] = alive.get(building.team, 0) + 10  # 建筑权重更高

	# 只剩一个阵营存活时结束
	if alive.keys().size() <= 1:
		game_over = true
		if alive.size() == 1:
			winner = alive.keys()[0] as String
		else:
			winner = "无"
		overlay.show(); overlay.build_menu()


func _resume_game() -> void:
	paused = false
	get_tree().paused = false
	overlay.hide_menu()


func _restart_game() -> void:
	get_tree().paused = false
	# 清理静态数据
	team_minerals.clear()
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	_input_handler.handle_input(event)


func _unhandled_input(event: InputEvent) -> void:
	_input_handler.handle_unhandled_input(event)







func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen_pos





## 太空总览行点击处理
func on_overview_unit_clicked(unit: Unit, is_right_click: bool) -> void:
	if not is_instance_valid(unit) or unit.hull <= 0:
		return

	# 技能施法模式
	if skill_targeting_mode >= 0:
		_skill_targeting.handle_overview_skill_targeting(
			self, skill_targeting_mode, skill_targeting_units, units,
			player_team_name, team_minerals, unit
		)
		return

	if is_right_click:
		# 右键 → 攻击该单位
		var shift_held = Input.is_key_pressed(KEY_SHIFT)
		for u in selected_units:
			if is_instance_valid(u) and u.hull > 0 and u.team == player_team_name:
				if shift_held:
					u.queue_attack_target(unit)
				else:
					u.attack_target(unit)
		return

	# 左键 → 镜头跟随
	follow_unit = unit
	camera.position = unit.global_position











func _ai_controller_init() -> void:
	# 除第一个阵营（玩家）外，其余阵营由AI指挥官控制，偏好随机分配
	var prefs = [
		AiController.TargetPref.SMALL_FIRST,
		AiController.TargetPref.BIG_FIRST,
		AiController.TargetPref.THREAT_FOCUS,
	]
	var count = mini(GameConfig.faction_config.size(), 999)
	for i in range(1, count):
		var team_name = faction_team_names[i]
		var pref = prefs[randi() % prefs.size()]
		var ai = AiController.new()
		ai.init(units, team_name, pref)
		# 传入建筑列表和 Main 引用，使AI能管理经济和生产
		ai.init_extended(buildings, self)
		add_child(ai)
		ai_controllers.append(ai)








func _draw_overlay() -> void:
	"""在 CanvasLayer 上绘制临时游戏结束画面（屏幕坐标）"""
	var vsize = get_viewport().get_visible_rect().size

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var is_victory = winner == player_team_name
		var title = "胜利" if is_victory else "失败"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var font = ThemeDB.fallback_font
		var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - ts / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), winner + "获胜",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

	elif paused:
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
	_draw_helper.draw_map_boundary(self)
	_draw_helper.draw_selection_box(self, is_dragging, drag_start, drag_end)
	var mouse_pos = _screen_to_world(get_viewport().get_mouse_position())
	_draw_helper.draw_attack_cursor(self, attack_cursor_mode, mouse_pos)
	_draw_helper.draw_orbit_drag_preview(self, orbit_is_dragging, orbit_drag_start, orbit_drag_end)
	_draw_helper.draw_skill_targeting(self, skill_targeting_mode, skill_targeting_units, player_team_name)
	_draw_helper.draw_unit_command_lines(self, selected_units)
	_draw_helper.draw_orbit_cursor(self, orbit_cursor_mode)
	_draw_overlay()





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
	_spawn_system.on_ship_produced(team_name, ship_type, building)





func _on_field_depleted(_field) -> void:
	# 矿枯竭后不做特殊处理（采矿船自动找下一片）
	pass


func _enter_skill_targeting_mode(skill_index: int, target_units: Array) -> void:
	var ok = _skill_targeting.enter_skill_targeting_mode(self, skill_index, target_units, player_team_name, team_minerals)
	if ok:
		skill_targeting_mode = skill_index
		skill_targeting_units = target_units
		attack_cursor_mode = false
		orbit_cursor_mode = false
		queue_redraw()


func _exit_skill_targeting_mode() -> void:
	skill_targeting_mode = -1
	skill_targeting_units = []
	queue_redraw()





func _fit_camera_to_fleets() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		min_pos = min_pos.min(unit.global_position)
		max_pos = max_pos.max(unit.global_position)

	var center = (min_pos + max_pos) / 2
	camera.position = center

	var world_size = max_pos - min_pos + Vector2(600, 600)
	var viewport_size = get_viewport().get_visible_rect().size
	var zoom = min(viewport_size.x / world_size.x, viewport_size.y / world_size.y)
	zoom_target = clamp(zoom, 0.3, 3.0)


func _center_camera_on_selection() -> void:
	if selected_units.size() > 0:
		var target = selected_units[0]
		if is_instance_valid(target) and camera != null:
			camera.position = target.global_position
	elif selected_buildings.size() > 0:
		var target = selected_buildings[0]
		if is_instance_valid(target) and camera != null:
			camera.position = target.global_position




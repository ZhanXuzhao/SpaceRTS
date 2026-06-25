extends MarginContainer

const _Building = preload("res://scripts/building.gd")

var main: Node2D = null

# ---- 场景子节点引用 ----
var _top_bar: HBoxContainer
var _speed_indicator: Label
var _info_panel: VBoxContainer
var _ship_class_label: Label
var _speed_label: Label
var _shield_bar_bg: ColorRect
var _shield_bar_fill: ColorRect
var _shield_label: Label
var _hull_bar_bg: ColorRect
var _hull_bar_fill: ColorRect
var _hull_label: Label
var _weapon_label: Label
var _attack_mode_label: Label
var _drone_label: Label
var _skill_panel: GridContainer
var _skill_buttons: Array[MarginContainer] = []
var _message_label: Label = null
var _buff_label: Label = null
var _kill_label: Label = null
var _threat_label: Label = null

# ---- 顶部调试信息 ----
var _ship_count_label: Label
var _projectile_count_label: Label
var _fps_label: Label
var _mineral_label: Label

# ---- 速度平滑显示 ----
var _displayed_speed: float = 0.0

# ---- FPS 平滑 ----
var _smoothed_fps: float = 0.0

# ---- 太空总览面板 ----
var _overview_panel: PanelContainer
var _overview_rows: VBoxContainer
var _overview_title: Label
var _overview_headers: Array[Button] = []
var _sort_column: int = 2  # 默认按距离排序
var _sort_ascending: bool = true

# ---- 建筑/生产面板 ----
var _build_panel: GridContainer
var _build_btns: Array[Button] = []
var _build_panel_visible: bool = false
var _selected_building = null
var _build_queue_label: Label

const SKILL_NAMES := ["加速", "速射", "减伤", "跃迁", "减速", "净化"]
const SKILL_COLORS := [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.4, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.8, 0.3, 1.0),
	Color(0.6, 0.2, 0.8),
	Color(0.3, 0.9, 0.9),
]

const BAR_W := 240.0
const BAR_H := 12.0
const TOP_BAR_H := 40


## 外部：设置当前选中的建筑（船坞时显示生产面板）
func set_selected_building(building) -> void:
	_selected_building = building
	if building != null and building.building_type == _Building.BuildingType.SHIPYARD:
		_build_panel.visible = true
		_build_queue_label.visible = true
		_build_panel_visible = true
	else:
		_build_panel.visible = false
		_build_queue_label.visible = false
		_build_panel_visible = false


## 建造按钮回调
## 从按钮的父容器中查找费用标签
func _get_btn_cost(btn: Button) -> int:
	var container = btn.get_parent()
	if container == null:
		return 99999
	for child in container.get_children():
		if child is Label and child.name == "Cost":
			var text = child.text
			var idx = text.find("💰")
			if idx >= 0:
				return int(text.substr(idx + 1))
	return 99999


func _on_build_btn_pressed(ship_type, cost: int) -> void:
	if _selected_building == null or not is_instance_valid(_selected_building):
		return
	if _selected_building.building_type != _Building.BuildingType.SHIPYARD:
		return

	var build_time := 0.0
	if ship_type == Unit.ShipClass.MINER:
		build_time = GameConfig.SHIPYARD_TIME_MINER
	elif ship_type == Unit.ShipClass.FRIGATE:
		build_time = GameConfig.SHIPYARD_TIME_FRIGATE
	elif ship_type == Unit.ShipClass.DESTROYER:
		build_time = GameConfig.SHIPYARD_TIME_DESTROYER
	elif ship_type == Unit.ShipClass.CRUISER:
		build_time = GameConfig.SHIPYARD_TIME_CRUISER
	elif ship_type == Unit.ShipClass.BATTLESHIP:
		build_time = GameConfig.SHIPYARD_TIME_BATTLESHIP
	else:
		return

	_selected_building.enqueue_ship(ship_type, cost, build_time)


func _ready() -> void:
	_top_bar = $TopBar
	_speed_indicator = $TopBar/SpeedIndicator

	# ---- 顶部调试信息标签 ----
	_ship_count_label = Label.new()
	_ship_count_label.name = "ShipCount"
	_ship_count_label.add_theme_font_size_override("font_size", 14)
	_ship_count_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_ship_count_label.custom_minimum_size.x = 80
	_ship_count_label.text = "🚀 0"
	_top_bar.add_child(_ship_count_label)

	_projectile_count_label = Label.new()
	_projectile_count_label.name = "ProjectileCount"
	_projectile_count_label.add_theme_font_size_override("font_size", 14)
	_projectile_count_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_projectile_count_label.custom_minimum_size.x = 100
	_projectile_count_label.text = "💥 0"
	_top_bar.add_child(_projectile_count_label)

	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_fps_label.custom_minimum_size.x = 64
	_fps_label.text = "FPS 0"
	_top_bar.add_child(_fps_label)

	# ---- 矿物储量标签 ----
	_mineral_label = Label.new()
	_mineral_label.name = "MineralLabel"
	_mineral_label.add_theme_font_size_override("font_size", 14)
	_mineral_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	_mineral_label.custom_minimum_size.x = 120
	_mineral_label.text = "🪨 0"
	_top_bar.add_child(_mineral_label)

	_info_panel = $InfoPanel
	_ship_class_label = $InfoPanel/ShipClassLabel
	_speed_label = $InfoPanel/SpeedLabel
	_shield_bar_bg = $InfoPanel/ShieldBarBg
	_shield_bar_fill = $InfoPanel/ShieldBarFill
	_shield_label = $InfoPanel/ShieldLabel
	_hull_bar_bg = $InfoPanel/HullBarBg
	_hull_bar_fill = $InfoPanel/HullBarFill
	_hull_label = $InfoPanel/HullLabel
	_weapon_label = $InfoPanel/WeaponLabel
	_attack_mode_label = $InfoPanel/AttackModeLabel
	_drone_label = $InfoPanel/DroneLabel
	_skill_panel = $SkillPanel

	# 创建 Buff/Debuff 显示标签
	_buff_label = Label.new()
	_buff_label.name = "BuffLabel"
	_buff_label.add_theme_font_size_override("font_size", 20)
	_buff_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_info_panel.add_child(_buff_label)
	_info_panel.move_child(_buff_label, _info_panel.get_child_count() - 1)

	# ---- 击杀/威胁度显示 ----
	_kill_label = Label.new()
	_kill_label.name = "KillLabel"
	_kill_label.add_theme_font_size_override("font_size", 16)
	_kill_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
	_info_panel.add_child(_kill_label)

	_threat_label = Label.new()
	_threat_label.name = "ThreatLabel"
	_threat_label.add_theme_font_size_override("font_size", 16)
	_threat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
	_info_panel.add_child(_threat_label)
	for i in 6:
		var btn = get_node("SkillPanel/SkillBtn" + str(i))
		_skill_buttons.append(btn)
		# 添加 "自动" 标签
		var auto_label = Label.new()
		auto_label.name = "AutoLabel"
		auto_label.text = "自动"
		auto_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
		auto_label.add_theme_font_size_override("font_size", 10)
		auto_label.position = Vector2(58, 2)
		auto_label.visible = false
		btn.add_child(auto_label)

	# ---- 建筑生产面板（场景中已有 BuildGrid GridContainer）----
	_build_panel = $BuildGrid
	_build_panel.visible = false

	# 标题 + 队列信息（在 BuildGrid 上方，作为兄弟节点放在场景中）
	_build_queue_label = $BuildQueueLabel
	_build_queue_label.text = ""

	# 建造按钮（颜色方案类似技能面板）
	var build_colors = [
		Color(0.6, 0.8, 0.3),  # 采矿船 - 绿色
		Color(1.0, 0.4, 0.2),  # 护卫舰 - 橙
		Color(1.0, 0.7, 0.1),  # 驱逐舰 - 金
		Color(0.7, 0.3, 1.0),  # 巡洋舰 - 紫
		Color(1.0, 0.2, 0.2),  # 战列舰 - 红
	]
	var build_items = [
		{"label": "采矿船", "cost": GameConfig.SHIPYARD_COST_MINER, "type": Unit.ShipClass.MINER},
		{"label": "护卫舰", "cost": GameConfig.SHIPYARD_COST_FRIGATE, "type": Unit.ShipClass.FRIGATE},
		{"label": "驱逐舰", "cost": GameConfig.SHIPYARD_COST_DESTROYER, "type": Unit.ShipClass.DESTROYER},
		{"label": "巡洋舰", "cost": GameConfig.SHIPYARD_COST_CRUISER, "type": Unit.ShipClass.CRUISER},
		{"label": "战列舰", "cost": GameConfig.SHIPYARD_COST_BATTLESHIP, "type": Unit.ShipClass.BATTLESHIP},
	]
	for idx in range(build_items.size()):
		var item = build_items[idx]
		var color = build_colors[idx]

		var btn_container = MarginContainer.new()
		btn_container.custom_minimum_size = Vector2(90, 80)
		btn_container.mouse_filter = Control.MOUSE_FILTER_STOP
		_build_panel.add_child(btn_container)

		var bg = ColorRect.new()
		bg.name = "Bg"
		bg.color = color
		bg.size = Vector2(90, 80)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_container.add_child(bg)

		var border = ColorRect.new()
		border.name = "Border"
		border.color = Color(0.2, 0.2, 0.2, 0.6)
		border.size = Vector2(90, 80)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_container.add_child(border)

		var name_lbl = Label.new()
		name_lbl.name = "Name"
		name_lbl.text = item.label
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.size = Vector2(90, 40)
		name_lbl.position = Vector2(0, 8)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_container.add_child(name_lbl)

		var cost_lbl = Label.new()
		cost_lbl.name = "Cost"
		cost_lbl.text = "💰" + str(item.cost)
		cost_lbl.add_theme_font_size_override("font_size", 12)
		cost_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_lbl.size = Vector2(90, 20)
		cost_lbl.position = Vector2(0, 50)
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_container.add_child(cost_lbl)

		# 可点击区域（透明的 Button 覆盖整个容器）
		var btn = Button.new()
		btn.text = ""
		btn.size = Vector2(90, 80)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.connect("pressed", Callable(self, "_on_build_btn_pressed").bind(item.type, item.cost))
		btn_container.add_child(btn)
		_build_btns.append(btn)

	# ---- 引用场景中的太空总览容器并构建内容 ----
	_overview_panel = $SpaceOverview
	_build_space_overview()


var _hud_frame_counter: int = 0

func _process(delta: float) -> void:
	# 速度指示器（始终显示）
	_speed_indicator.visible = true
	_speed_indicator.text = "⚡x" + str(Engine.time_scale)

	# 更新调试信息和太空总览（每 2 帧一次）
	_hud_frame_counter += 1
	if _hud_frame_counter % 2 == 0 and main != null:
		# 顶部调试信息
		var ship_count := 0
		for u in main._units:
			if is_instance_valid(u) and u.hull > 0:
				ship_count += 1
		_ship_count_label.text = "🚀 " + str(ship_count)
		_projectile_count_label.text = "💥 " + str(get_tree().get_nodes_in_group("projectiles").size())
		_smoothed_fps = lerp(_smoothed_fps, Performance.get_monitor(Performance.TIME_FPS), delta * 8.0)
		_fps_label.text = "FPS " + str(roundi(_smoothed_fps))

		# 矿物储量
		var minerals = main.team_minerals.get(main._player_team_name, 0.0)
		_mineral_label.text = "🪨 " + str(int(minerals))

		_update_space_overview()

	if main == null:
		_hide_all(); return

	# ---- 建筑选择/生产面板 ----
	if _selected_building != null and is_instance_valid(_selected_building):
		if _selected_building.building_type == _Building.BuildingType.SHIPYARD:
			_build_panel.visible = true
			_build_queue_label.visible = true
			var qsize = _selected_building._production_queue.size()
			var progress = _selected_building.get_production_progress()
			var queue_cost = _selected_building.get_queue_total_cost()
			if qsize > 0:
				var pct = int(progress * 100)
				_build_queue_label.text = "生产中: " + str(pct) + "%  队列: " + str(qsize) + "  排队矿物: " + str(queue_cost)
			else:
				_build_queue_label.text = "空闲  矿物: " + str(int(main.team_minerals.get(main._player_team_name, 0)))
			# 更新按钮可用状态
			var minerals = main.team_minerals.get(main._player_team_name, 0.0)
			for btn in _build_btns:
				btn.disabled = (minerals < _get_btn_cost(btn))
		else:
			_build_panel.visible = false
			_build_queue_label.visible = false
	else:
		_build_panel.visible = false
		_build_queue_label.visible = false

	var sel = main._selected_units
	if sel.size() == 0:
		_hide_all(); _speed_indicator.visible = true; return
	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		_hide_all(); _speed_indicator.visible = true; return

	# ---- 左下信息面板（VBoxContainer 自动布局）----
	var cnames := ["无人机", "护卫舰", "驱逐舰", "巡洋舰", "战列舰"]
	var cls = cnames[Unit._ship_class_tier(unit.class_type)]

	_make_visible()

	_ship_class_label.text = unit.team + " " + cls
	var max_speed = int(unit.speed * unit._speed_mult)
	var raw_speed = unit.velocity.length()
	_displayed_speed = lerp(_displayed_speed, raw_speed, 0.25)
	_speed_label.text = "速度: " + str(roundi(_displayed_speed)) + "/" + str(max_speed)

	_shield_bar_fill.size.x = BAR_W * (unit.shield / unit.max_shield) if unit.max_shield > 0 else 0
	_shield_label.text = "护盾 " + str(int(unit.shield)) + "/" + str(int(unit.max_shield))

	var hull_pct = unit.hull / unit.max_hull if unit.max_hull > 0 else 0
	_hull_bar_fill.size.x = BAR_W * hull_pct
	_hull_bar_fill.color = Color(0.2, 1.0, 0.3) if hull_pct > 0.5 else (Color(1.0, 0.8, 0.2) if hull_pct > 0.25 else Color(1.0, 0.2, 0.2))
	_hull_label.text = "结构 " + str(int(unit.hull)) + "/" + str(int(unit.max_hull))

	_weapon_label.text = "武器: " + _get_weapon_summary(unit)

	var mode_names := ["就地攻击", "机动攻击", "环绕攻击"]
	_attack_mode_label.text = "攻击模式: " + mode_names[unit.attack_mode] + " [G]"

	if unit.class_type == Unit.ShipClass.BATTLESHIP:
		_drone_label.visible = true
		var total = unit.drone_bay + unit.deployed_drones.size()
		_drone_label.text = "无人机 仓容/舱内/舱外: " + str(total) + "/" + str(unit.drone_bay) + "/" + str(unit.deployed_drones.size())
	else:
		_drone_label.visible = false

	# ---- 战绩显示 ----
	_kill_label.text = "击杀: " + str(unit.kill_count)
	_threat_label.text = "威胁度: " + str(unit.threat_level)

	# ---- Buff/Debuff 显示 ----
	_update_buff_display(unit)

	# ---- 右下技能面板（GridContainer 自动布局）----
	_update_skill_buttons(sel)


func _update_buff_display(unit: Unit) -> void:
	var buffs = unit.get_active_buffs()
	if buffs.size() == 0:
		_buff_label.visible = false
		return
	_buff_label.visible = true
	var lines: Array[String] = []
	for b in buffs:
		lines.append(b["name"] + " " + b["desc"])
	_buff_label.text = "\n".join(lines)


func _update_skill_buttons(sel: Array) -> void:
	for btn in _skill_buttons:
		btn.visible = false

	for i in 6:
		var btn = _skill_buttons[i]
		btn.visible = true

		var max_cd := 0.0
		var any_active := false
		# 以第一个有效单位的状态显示
		var first_auto := false
		var found_first := false
		for u in sel:
			if is_instance_valid(u) and u.hull > 0:
				if u._skill_cooldowns[i] > max_cd: max_cd = u._skill_cooldowns[i]
				if u._skill_timers[i] > 0: any_active = true
				if not found_first:
					first_auto = u._skill_auto[i]
					found_first = true

		var bg: ColorRect = btn.get_node("Bg")
		var color = SKILL_COLORS[i]
		if max_cd > 0: color = color.darkened(0.5)
		elif any_active: color = color.lightened(0.3)
		bg.color = color

		var cd: Label = btn.get_node("CD")
		if max_cd > 0:
			cd.visible = true
			cd.text = str(ceil(max_cd))
		else:
			cd.visible = false

		# 自动释放标记（以第一个单位为准）
		var auto_label: Label = btn.get_node("AutoLabel")
		auto_label.visible = found_first and first_auto


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if main == null or main._selected_units.size() == 0:
		return
	if main._skill_targeting_mode >= 0:
		# 施法选择模式下不处理按钮
		return

	var is_right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	var is_left: bool = event.button_index == MOUSE_BUTTON_LEFT
	if not is_left and not is_right:
		return

	# 检测技能按钮点击
	for i in 6:
		var btn = _skill_buttons[i]
		if not btn.visible:
			continue
		var rect = Rect2(btn.global_position, Vector2(80, 80))
		if not rect.has_point(event.position):
			continue

		get_viewport().set_input_as_handled()

		if is_right:
			# 以第一个有效单位的状态为基准，同步所有单位
			var ref_auto := false
			var found := false
			for u in main._selected_units:
				if is_instance_valid(u) and u.hull > 0:
					ref_auto = u._skill_auto[i]
					found = true
					break
			if found:
				var new_val := not ref_auto
				for u in main._selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u._skill_auto[i] = new_val
			return

		if is_left:
			if i <= 2:
				# 加速/速射/减伤：直接释放
				for u in main._selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(i)
				return
			elif i == 3 or i == 4:
				# 跃迁/减速：进入施法选择模式（冷却判定在 main 中统一处理）
				main.enter_skill_targeting_mode(i, main._selected_units)
				return
		if i == 5:
			# 净化：直接释放
			for u in main._selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(i)
			return


func _hide_all() -> void:
	_ship_class_label.visible = false
	_speed_label.visible = false
	_shield_bar_bg.visible = false
	_shield_bar_fill.visible = false
	_shield_label.visible = false
	_hull_bar_bg.visible = false
	_hull_bar_fill.visible = false
	_hull_label.visible = false
	_weapon_label.visible = false
	_attack_mode_label.visible = false
	_drone_label.visible = false
	_buff_label.visible = false
	_kill_label.visible = false
	_threat_label.visible = false
	_speed_indicator.visible = false
	for btn in _skill_buttons:
		btn.visible = false
	# 太空总览始终显示，不隐藏


func _make_visible() -> void:
	_ship_class_label.visible = true
	_speed_label.visible = true
	_shield_bar_bg.visible = true
	_shield_bar_fill.visible = true
	_shield_label.visible = true
	_hull_bar_bg.visible = true
	_hull_bar_fill.visible = true
	_hull_label.visible = true
	_weapon_label.visible = true
	_attack_mode_label.visible = true
	_buff_label.visible = true
	_kill_label.visible = true
	_threat_label.visible = true
	# 太空总览始终显示


## 临时提示消息（2 秒后自动消失）
func show_message(text: String) -> void:
	# 移除旧消息
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.queue_free()
		_message_label = null

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.position = get_viewport().get_visible_rect().size / 2 - Vector2(60, 0)
	add_child(lbl)
	_message_label = lbl

	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(_clear_message)


func _clear_message() -> void:
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.queue_free()
		_message_label = null


# ==================== 太空总览 ====================

## 构建太空总览面板（在场景的 SpaceOverview 容器内）
func _build_space_overview() -> void:
	if _overview_panel == null:
		return

	# 背景样式
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.75)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	_overview_panel.add_theme_stylebox_override("panel", bg_style)

	# 内部垂直布局
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 8.0
	vbox.offset_right = -8.0
	vbox.offset_top = 8.0
	vbox.offset_bottom = -8.0
	_overview_panel.add_child(vbox)

	# 标题
	_overview_title = Label.new()
	_overview_title.text = "🚀 太空总览"
	_overview_title.add_theme_font_size_override("font_size", 18)
	_overview_title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_overview_title.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(_overview_title)

	# 表头（可点击排序）
	var header = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 4)

	var h_names := ["名字", "类型", "距离", "速度", "阵营"]
	var h_widths := [80.0, 50.0, 50.0, 40.0, 40.0]
	_overview_headers.clear()
	for i in h_names.size():
		var btn = Button.new()
		btn.flat = true
		btn.text = h_names[i]
		btn.custom_minimum_size.x = h_widths[i]
		btn.custom_minimum_size.y = 22
		btn.size_flags_horizontal = SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		# 悬停高亮
		var hover_bg = StyleBoxFlat.new()
		hover_bg.bg_color = Color(0.2, 0.35, 0.5, 0.3)
		btn.add_theme_stylebox_override("hover", hover_bg)
		var pressed_bg = StyleBoxFlat.new()
		pressed_bg.bg_color = Color(0.25, 0.4, 0.55, 0.4)
		btn.add_theme_stylebox_override("pressed", pressed_bg)
		btn.pressed.connect(_on_sort_header_pressed.bind(i))
		header.add_child(btn)
		_overview_headers.append(btn)
	vbox.add_child(header)

	_update_header_indicators()

	# 分隔线
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Color(0.3, 0.5, 0.7, 0.5))
	vbox.add_child(sep)

	# 行容器（可滚动）
	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.anchor_left = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_overview_rows = VBoxContainer.new()
	_overview_rows.name = "Rows"
	_overview_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_overview_rows)


## 太空总览跳帧计数器（每 2 帧刷新一次）
var _overview_frame_counter: int = 0

## 新建一行太空总览（仅创建节点结构，不设内容）
func _create_overview_row() -> Button:
	var row = Button.new()
	row.flat = true
	row.custom_minimum_size.y = 22
	row.size_flags_horizontal = SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(hbox)

	var widths := [80.0, 50.0, 50.0, 40.0, 40.0]
	var fields := ["name", "type", "dist", "spd", "faction"]
	for i in 5:
		var lbl = Label.new()
		lbl.name = fields[i]
		lbl.custom_minimum_size.x = widths[i]
		lbl.size_flags_horizontal = SIZE_SHRINK_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		hbox.add_child(lbl)

	# 缓存 StyleBox 避免每帧创建
	var bg_normal_even = StyleBoxFlat.new()
	bg_normal_even.bg_color = Color(0.15, 0.2, 0.3, 0.3)
	var bg_normal_odd = StyleBoxFlat.new()
	bg_normal_odd.bg_color = Color(0.1, 0.15, 0.25, 0.2)
	var bg_hover = StyleBoxFlat.new()
	bg_hover.bg_color = Color(0.25, 0.35, 0.5, 0.4)
	var bg_pressed = StyleBoxFlat.new()
	bg_pressed.bg_color = Color(0.3, 0.45, 0.6, 0.5)
	row.set_meta("style_even", bg_normal_even)
	row.set_meta("style_odd", bg_normal_odd)
	row.set_meta("style_hover", bg_hover)
	row.set_meta("style_pressed", bg_pressed)
	row.add_theme_stylebox_override("hover", bg_hover)
	row.add_theme_stylebox_override("pressed", bg_pressed)
	return row


## 更新现有行内容（不重建节点）
func _update_overview_row(row: Button, unit: Unit, idx: int, ref_unit: Unit) -> void:
	row.set_meta("unit_ref", unit)
	# 断开旧信号后重新连接
	if row.gui_input.is_connected(_on_overview_row_gui_input):
		row.gui_input.disconnect(_on_overview_row_gui_input)
	row.gui_input.connect(_on_overview_row_gui_input.bind(unit))

	var hbox = row.get_node("HBox") as HBoxContainer
	var labels := hbox.get_children()
	labels[0].text = unit.unit_name
	labels[1].text = unit.class_name_cn if unit.class_name_cn != "" else Unit.get_class_name_cn(unit.class_type)
	if ref_unit != null:
		var dist = int(unit.global_position.distance_to(ref_unit.global_position))
		labels[2].text = str(dist)
	else:
		labels[2].text = "-"
	labels[3].text = str(int(unit.velocity.length()))
	labels[4].text = unit.team

	# 交替背景色（使用缓存的 StyleBox）
	var style = row.get_meta("style_even") if idx % 2 == 0 else row.get_meta("style_odd")
	row.add_theme_stylebox_override("normal", style)


## 更新太空总览表（每 2 帧刷新一次，节点复用避免重建）
func _update_space_overview() -> void:
	if main == null or _overview_panel == null:
		return

	_overview_frame_counter += 1
	if _overview_frame_counter % 2 != 0:
		return

	# 收集敌方单位
	var enemies: Array[Unit] = []
	for unit in main._units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == main._player_team_name:
			continue
		enemies.append(unit)

	# 确定距离参考点
	var ref_unit: Unit = null
	var ref_tier := -1
	for u in main._selected_units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != main._player_team_name:
			continue
		var t = Unit._ship_class_tier(u.class_type)
		if t > ref_tier:
			ref_tier = t
			ref_unit = u
	if ref_unit == null:
		for u in main._units:
			if not is_instance_valid(u) or u.hull <= 0 or u.team != main._player_team_name:
				continue
			var t = Unit._ship_class_tier(u.class_type)
			if t > ref_tier:
				ref_tier = t
				ref_unit = u

	_sort_enemies(enemies, ref_unit)

	# 节点复用：增删行到匹配数量
	var rows = _overview_rows.get_children()
	var needed = enemies.size()

	# 多余的行移除
	while rows.size() > needed:
		var r = rows.pop_back()
		_overview_rows.remove_child(r)
		r.queue_free()

	# 无敌人时显示提示
	if needed == 0:
		if rows.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.name = "EmptyHint"
			empty_lbl.text = "无敌方目标"
			empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.size_flags_horizontal = SIZE_SHRINK_CENTER
			_overview_rows.add_child(empty_lbl)
		return

	# 不够的行补充
	while rows.size() < needed:
		var r = _create_overview_row()
		rows.append(r)
		_overview_rows.add_child(r)

	# 只更新文本
	for idx in needed:
		_update_overview_row(rows[idx] as Button, enemies[idx], idx, ref_unit)


## 施法成功时隐藏提示
func hide_message() -> void:
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.queue_free()
		_message_label = null


# ==================== 太空总览点击处理 ====================

## 左键/右键点击总览行
func _on_overview_row_gui_input(event: InputEvent, unit: Unit) -> void:
	if main == null or not is_instance_valid(unit) or unit.hull <= 0:
		return
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			main.on_overview_unit_clicked(unit, true)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			main.on_overview_unit_clicked(unit, false)


# ==================== 排序 ====================

## 点击排序列头
func _on_sort_header_pressed(col_index: int) -> void:
	if col_index == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = col_index
		_sort_ascending = true
	_update_header_indicators()


## 更新表头排序指示箭头
func _update_header_indicators() -> void:
	var h_names := ["名字", "类型", "距离", "速度", "阵营"]
	for i in _overview_headers.size():
		var text = h_names[i]
		if i == _sort_column:
			text += " ▲" if _sort_ascending else " ▼"
		_overview_headers[i].text = text


## 按当前排序设置对敌方列表排序
func _sort_enemies(enemies: Array, ref_unit: Unit) -> void:
	enemies.sort_custom(func(a, b):
		var va
		var vb
		match _sort_column:
			0:  # 名字
				va = a.unit_name
				vb = b.unit_name
			1:  # 类型（按 tier）
				va = Unit._ship_class_tier(a.class_type)
				vb = Unit._ship_class_tier(b.class_type)
			2:  # 距离
				if ref_unit != null:
					va = a.global_position.distance_squared_to(ref_unit.global_position)
					vb = b.global_position.distance_squared_to(ref_unit.global_position)
				else:
					va = 0
					vb = 0
			3:  # 速度
				va = a.velocity.length()
				vb = b.velocity.length()
			4:  # 阵营
				va = a.team
				vb = b.team
			_:
				va = 0
				vb = 0
		if _sort_ascending:
			return va < vb
		else:
			return va > vb
	)


func _get_weapon_summary(unit: Unit) -> String:
	var counts = {}
	for w in unit._slot_weapons:
		if w != null:
			var wn = w.get_display_name()
			counts[wn] = counts.get(wn, 0) + 1
	var parts = []
	for k in counts:
		parts.append(k + "x" + str(counts[k]))
	return ", ".join(parts)

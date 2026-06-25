extends MarginContainer

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
var _skill_buttons: Array = []
var _message_label: Label = null
var _buff_label: Label = null
var _kill_label: Label = null
var _threat_label: Label = null

# ---- 顶部调试信息 ----
var _ship_count_label: Label
var _projectile_count_label: Label
var _fps_label: Label
var _mineral_label: Label
var _miner_count_label: Label
var _combat_count_label: Label

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
var _build_btns: Array = []
var _build_panel_visible: bool = false
var _selected_building = null
var _build_queue_label: Label

const CornerLabelButton = preload("res://scenes/corner_label_button.tscn")

const SKILL_NAMES := ["加速", "速射", "减伤", "跃迁", "减速", "净化", "建船厂", "建矿场"]
const SKILL_KEYS := ["Z", "X", "C", "V", "B", "N", "M", "K"]
const SKILL_COLORS := [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.4, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.8, 0.3, 1.0),
	Color(0.6, 0.2, 0.8),
	Color(0.3, 0.9, 0.9),
	Color(0.5, 0.7, 1.0),   # 建船厂
	Color(0.7, 0.5, 0.3),   # 建矿场
]

const BAR_W := 240.0
const BAR_H := 12.0
const TOP_BAR_H := 40


## 外部：设置当前选中的建筑（船坞时显示生产面板）
## 当多选建筑时，传入 null 隐藏面板，但保留主场景的多选状态
func set_selected_building(building) -> void:
	_selected_building = building
	# 仅当唯一选中船坞时才显示生产面板
	var is_shipyard = building != null and building.building_type == Building.BuildingType.SHIPYARD
	_build_queue_label.visible = is_shipyard
	_build_panel_visible = is_shipyard


## 建造按钮回调 — 从按钮的右下角标读取费用
func _get_btn_cost(btn) -> int:
	if not btn.has_method("get_br"):
		return 99999
	var text = btn.get_br().text
	var idx = text.find("💰")
	if idx >= 0:
		return int(text.substr(idx + 1))
	return 99999


func _on_build_btn_pressed(ship_type, cost: int) -> void:
	if main == null:
		return
	# 收集选中建筑中有效的船坞
	var shipyards: Array = []
	for b in main.selected_buildings:
		if is_instance_valid(b) and b.building_type == Building.BuildingType.SHIPYARD:
			shipyards.append(b)
	if shipyards.size() == 0:
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

	# 分配到队列最短的船坞
	var best = shipyards[0]
	var best_q = best._production_queue.size()
	for b in shipyards:
		var qsize = b._production_queue.size()
		if qsize < best_q:
			best_q = qsize
			best = b
	best.enqueue_ship(ship_type, cost, build_time)


func _ready() -> void:
	_top_bar = $TopBar
	_speed_indicator = $TopBar/SpeedIndicator

	# ---- 顶部调试信息标签（场景中已静态定义）----
	_ship_count_label = $TopBar/ShipCount
	_projectile_count_label = $TopBar/ProjectileCount
	_fps_label = $TopBar/FpsLabel
	_miner_count_label = $TopBar/MinerCount
	_combat_count_label = $TopBar/CombatCount
	_mineral_label = $TopBar/MineralLabel

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
	for i in 8:
		var btn = CornerLabelButton.instantiate()
		btn.set_name_text(SKILL_NAMES[i])
		btn.set_tl(SKILL_KEYS[i])
		btn.set_bg_color(SKILL_COLORS[i])
		btn.get_bl().visible = false  # 左下角无快捷键
		btn.set_tr("")       # CD — 默认隐藏
		btn.get_tr().visible = false
		btn.set_br("自动")    # 自动标签 — 默认隐藏
		btn.get_br().visible = false
		btn.pressed.connect(_on_skill_btn_pressed.bind(i))
		btn.right_clicked.connect(_on_skill_btn_right_clicked.bind(i))
		_skill_panel.add_child(btn)
		_skill_buttons.append(btn)

	# ---- 建筑生产面板（场景中已有 BuildGrid GridContainer）----
	# 标题 + 队列信息（在 BuildGrid 上方，作为兄弟节点放在场景中）
	_build_queue_label = $BuildQueueLabel
	_build_queue_label.text = ""

	# 建造按钮（颜色方案类似技能面板）
	var build_colors = [
		Color(0.2, 0.6, 1.0),  # 采矿船 - 蓝（同技能加速）
		Color(1.0, 0.4, 0.2),  # 护卫舰 - 橙（同技能速射）
		Color(0.2, 1.0, 0.3),  # 驱逐舰 - 绿（同技能减伤）
		Color(0.8, 0.3, 1.0),  # 巡洋舰 - 紫（同技能跃迁）
		Color(0.6, 0.2, 0.8),  # 战列舰 - 深紫（同技能减速）
	]
	var build_keys = ["Z", "X", "C", "V", "B"]
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

		var btn = CornerLabelButton.instantiate()
		btn.set_name_text(item.label)
		btn.set_bg_color(color)
		btn.set_tl(build_keys[idx])
		btn.set_br("💰" + str(item.cost))
		btn.get_bl().visible = false
		btn.get_tr().visible = false
		btn.pressed.connect(_on_build_btn_pressed.bind(item.type, item.cost))
		_skill_panel.add_child(btn)
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
		var miner_count := 0
		var combat_count := 0
		for u in main.units:
			if is_instance_valid(u) and u.hull > 0:
				if u.team == main.player_team_name:
					if u._is_miner:
						miner_count += 1
					else:
						combat_count += 1
				ship_count += 1
		_ship_count_label.text = "🚀 " + str(ship_count)
		_miner_count_label.text = "⛏ " + str(miner_count)
		_combat_count_label.text = "⚔ " + str(combat_count)
		_projectile_count_label.text = "💥 " + str(get_tree().get_nodes_in_group("projectiles").size())
		_smoothed_fps = lerp(_smoothed_fps, Performance.get_monitor(Performance.TIME_FPS), delta * 8.0)
		_fps_label.text = "FPS " + str(roundi(_smoothed_fps))

		# 矿物储量
		var minerals = main.team_minerals.get(main.player_team_name, 0.0)
		_mineral_label.text = "🪨 " + str(int(minerals))

		_update_space_overview()

	if main == null:
		_hide_all(); return

	# ---- 建筑选择/生产面板 ----
	var has_shipyard = false
	var total_qsize := 0
	var minerals := 0.0
	if main != null:
		minerals = main.team_minerals.get(main.player_team_name, 0.0)
	for b in main.selected_buildings:
			if is_instance_valid(b) and b.building_type == Building.BuildingType.SHIPYARD:
				has_shipyard = true
				total_qsize += b._production_queue.size()
	_build_queue_label.visible = has_shipyard
	_build_panel_visible = has_shipyard
	if has_shipyard:
		if total_qsize > 0:
			_build_queue_label.text = "队列: " + str(total_qsize) + "  矿物: " + str(int(minerals))
		else:
			_build_queue_label.text = "空闲  矿物: " + str(int(minerals))
		# 更新按钮可用状态
		for btn in _build_btns:
			btn.set_disabled(minerals < _get_btn_cost(btn))

	var sel = main.selected_units
	if sel.size() == 0:
		_hide_all()
		# 船坞选中时在生产按钮，隐藏技能按钮
		if _build_panel_visible:
			for btn in _skill_buttons:
				btn.visible = false
			for btn in _build_btns:
				btn.visible = true
		_speed_indicator.visible = true
		return
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
	for btn in _build_btns:
		btn.visible = false

	for i in 8:
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

		var color = SKILL_COLORS[i]
		if max_cd > 0: color = color.darkened(0.5)
		elif any_active: color = color.lightened(0.3)
		btn.set_bg_color(color)

		if max_cd > 0:
			btn.get_tr().visible = true
			btn.set_tr(str(ceil(max_cd)))
		else:
			btn.get_tr().visible = false

		# 自动释放标记（以第一个单位为准）
		btn.get_br().visible = found_first and first_auto

		# 部署技能显示矿物消耗
		if i == 6:
			btn.set_br("💰" + str(GameConfig.DEPLOY_COST_SHIPYARD))
			btn.get_br().visible = true
		elif i == 7:
			btn.set_br("💰" + str(GameConfig.DEPLOY_COST_MINE))
			btn.get_br().visible = true


func _input(event: InputEvent) -> void:
	# ---- 船坞快捷键 Z/X/C/V/B（仅在船坞选中且无单位选中时触发）----
	if event is InputEventKey and event.pressed and main != null \
			and main.selected_units.size() == 0 and main.selected_buildings.size() > 0:
		# 检查首个选中建筑是否为船坞
		var first = main.selected_buildings[0]
		if is_instance_valid(first) and first.building_type == Building.BuildingType.SHIPYARD:
			var key_idx = -1
			match event.keycode:
				KEY_Z: key_idx = 0
				KEY_X: key_idx = 1
				KEY_C: key_idx = 2
				KEY_V: key_idx = 3
				KEY_B: key_idx = 4
			if key_idx >= 0 and key_idx < _build_btns.size():
				_build_btns[key_idx].pressed.emit()
				return

	# 技能按钮点击已由 CornerLabelButton 信号处理


# ==================== 技能按钮信号回调 ====================

func _on_skill_btn_pressed(idx: int) -> void:
	if main == null or main.selected_units.size() == 0:
		return
	if main.skill_targeting_mode >= 0:
		return

	if idx <= 2:
		# 加速/速射/减伤：直接释放
		for u in main.selected_units:
			if is_instance_valid(u) and u.hull > 0:
				u.activate_skill(idx)
	elif idx == 3 or idx == 4:
		# 跃迁/减速：进入施法选择模式
		main._enter_skill_targeting_mode(idx, main.selected_units)
	elif idx == 5:
		# 净化：直接释放
		for u in main.selected_units:
			if is_instance_valid(u) and u.hull > 0:
				u.activate_skill(idx)
	elif idx >= 6:
		# 部署船厂/矿厂：进入施法选择模式
		main._enter_skill_targeting_mode(idx, main.selected_units)


func _on_skill_btn_right_clicked(idx: int) -> void:
	if main == null or main.selected_units.size() == 0:
		return
	# 以第一个有效单位的状态为基准，同步所有单位的自动施法
	var ref_auto := false
	var found := false
	for u in main.selected_units:
		if is_instance_valid(u) and u.hull > 0:
			ref_auto = u._skill_auto[idx]
			found = true
			break
	if found:
		var new_val := not ref_auto
		for u in main.selected_units:
			if is_instance_valid(u) and u.hull > 0:
				u._skill_auto[idx] = new_val


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
	for btn in _build_btns:
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
	for unit in main.units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == main.player_team_name:
			continue
		enemies.append(unit)

	# 确定距离参考点
	var ref_unit: Unit = null
	var ref_tier := -1
	for u in main.selected_units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != main.player_team_name:
			continue
		var t = Unit._ship_class_tier(u.class_type)
		if t > ref_tier:
			ref_tier = t
			ref_unit = u
	if ref_unit == null:
		for u in main.units:
			if not is_instance_valid(u) or u.hull <= 0 or u.team != main.player_team_name:
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

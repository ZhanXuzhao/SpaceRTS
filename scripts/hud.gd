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
var _skill_buttons: Array[MarginContainer] = []
var _message_label: Label = null
var _buff_label: Label = null
var _kill_label: Label = null
var _threat_label: Label = null

# ---- 速度平滑显示 ----
var _displayed_speed: float = 0.0

# ---- 太空总览面板 ----
var _overview_panel: PanelContainer
var _overview_rows: VBoxContainer
var _overview_title: Label
var _overview_headers: Array[Button] = []
var _sort_column: int = 2  # 默认按距离排序
var _sort_ascending: bool = true

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


func _ready() -> void:
	_top_bar = $TopBar
	_speed_indicator = $TopBar/SpeedIndicator
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

	# ---- 引用场景中的太空总览容器并构建内容 ----
	_overview_panel = $SpaceOverview
	_build_space_overview()


var _hud_frame_counter: int = 0

func _process(_delta: float) -> void:
	# 速度指示器（始终显示）
	_speed_indicator.visible = true
	_speed_indicator.text = "⚡x" + str(Engine.time_scale)

	# 更新太空总览（每 2 帧一次，降低 UI 节点创建/销毁开销）
	_hud_frame_counter += 1
	if _hud_frame_counter % 2 == 0:
		_update_space_overview()

	if main == null:
		_hide_all(); return
	var sel = main._selected_units
	if sel.size() == 0:
		_hide_all(); _speed_indicator.visible = true; return
	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		_hide_all(); _speed_indicator.visible = true; return

	# ---- 左下信息面板（VBoxContainer 自动布局）----
	var team_str = "蓝队" if unit.team == Unit.Team.BLUE else ("红队" if unit.team == Unit.Team.RED else ("黄队" if unit.team == Unit.Team.YELLOW else "绿队"))
	var cnames := ["无人机", "护卫舰", "驱逐舰", "巡洋舰", "战列舰"]
	var cls = cnames[Unit._ship_class_tier(unit.class_type)]

	_make_visible()

	_ship_class_label.text = team_str + " " + cls
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


## 更新太空总览表
func _update_space_overview() -> void:
	if main == null or _overview_panel == null:
		return

	# 清除旧行
	for child in _overview_rows.get_children():
		child.queue_free()

	# 收集敌方单位（蓝方视角：红方和黄方均为敌人）
	var enemies: Array[Unit] = []
	for unit in main._units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit.team == Unit.Team.BLUE:
			continue  # 只显示敌方
		enemies.append(unit)

	if enemies.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "无敌方目标"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.size_flags_horizontal = SIZE_SHRINK_CENTER
		_overview_rows.add_child(empty_lbl)
		return

	# 确定距离参考点：选中单位中最大的船 → 友军中最大的船 → 无
	var ref_unit: Unit = null
	var ref_tier := -1
	# 1. 从选中单位中找最大船
	for u in main._selected_units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != Unit.Team.BLUE:
			continue
		var t = Unit._ship_class_tier(u.class_type)
		if t > ref_tier:
			ref_tier = t
			ref_unit = u
	# 2. 如果无选中，从所有友军找
	if ref_unit == null:
		for u in main._units:
			if not is_instance_valid(u) or u.hull <= 0 or u.team != Unit.Team.BLUE:
				continue
			var t = Unit._ship_class_tier(u.class_type)
			if t > ref_tier:
				ref_tier = t
				ref_unit = u

	# 按当前排序列和方向排序
	_sort_enemies(enemies, ref_unit)

	# 最多显示 15 行
	var max_rows = min(enemies.size(), 15)
	for idx in max_rows:
		var unit = enemies[idx]
		var dist_str: String
		if ref_unit != null:
			var dist = int(unit.global_position.distance_to(ref_unit.global_position))
			dist_str = str(dist)
		else:
			dist_str = "-"
		var spd = int(unit.velocity.length())
		var faction = "红方" if unit.team == Unit.Team.RED else ("黄方" if unit.team == Unit.Team.YELLOW else ("绿方" if unit.team == Unit.Team.GREEN else "蓝方"))
		var type_name = unit.class_name_cn if unit.class_name_cn != "" else Unit.get_class_name_cn(unit.class_type)

		# 可点击行（Button 方便捕获点击，flat 无按钮样式）
		var row = Button.new()
		row.flat = true
		row.custom_minimum_size.y = 22
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		# 存储单位引用
		row.set_meta("unit_ref", unit)

		# 行内水平布局
		var hbox = HBoxContainer.new()
		hbox.name = "HBox"
		hbox.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(hbox)

		var vals := [unit.unit_name, type_name, dist_str, str(spd), faction]
		var widths := [80.0, 50.0, 50.0, 40.0, 40.0]
		for i in vals.size():
			var lbl = Label.new()
			lbl.text = vals[i]
			lbl.custom_minimum_size.x = widths[i]
			lbl.size_flags_horizontal = SIZE_SHRINK_CENTER
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
			hbox.add_child(lbl)

		# 设置行背景色和悬停高亮
		var bg_color = Color(0.15, 0.2, 0.3, 0.3) if idx % 2 == 0 else Color(0.1, 0.15, 0.25, 0.2)
		var bg_normal = StyleBoxFlat.new()
		bg_normal.bg_color = bg_color
		row.add_theme_stylebox_override("normal", bg_normal)

		var bg_hover = StyleBoxFlat.new()
		bg_hover.bg_color = Color(0.25, 0.35, 0.5, 0.4)
		row.add_theme_stylebox_override("hover", bg_hover)

		var bg_pressed = StyleBoxFlat.new()
		bg_pressed.bg_color = Color(0.3, 0.45, 0.6, 0.5)
		row.add_theme_stylebox_override("pressed", bg_pressed)

		# 左键/右键点击（通过 gui_input 阻止穿透到场景）
		row.gui_input.connect(_on_overview_row_gui_input.bind(unit))

		_overview_rows.add_child(row)


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

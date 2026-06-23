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
	_buff_label.add_theme_font_size_override("font_size", 18)
	_info_panel.add_child(_buff_label)
	_info_panel.move_child(_buff_label, _info_panel.get_child_count() - 1)
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


func _process(_delta: float) -> void:
	# 速度指示器（始终显示）
	_speed_indicator.visible = true
	_speed_indicator.text = "⚡x" + str(Engine.time_scale)

	if main == null:
		_hide_all(); return
	var sel = main._selected_units
	if sel.size() == 0:
		_hide_all(); _speed_indicator.visible = true; return
	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		_hide_all(); _speed_indicator.visible = true; return

	# ---- 左下信息面板（VBoxContainer 自动布局）----
	var team_str = "蓝队" if unit.team == Unit.Team.BLUE else "红队"
	var cnames := ["无人机", "护卫舰", "驱逐舰", "巡洋舰", "战列舰"]
	var cls = cnames[Unit._ship_class_tier(unit.class_type)]

	_make_visible()

	_ship_class_label.text = team_str + " " + cls
	_speed_label.text = "速度: " + str(int(unit.speed * unit._speed_mult))

	_shield_bar_fill.size.x = BAR_W * (unit.shield / unit.max_shield) if unit.max_shield > 0 else 0
	_shield_label.text = "护盾 " + str(int(unit.shield)) + "/" + str(int(unit.max_shield))

	var hull_pct = unit.hull / unit.max_hull if unit.max_hull > 0 else 0
	_hull_bar_fill.size.x = BAR_W * hull_pct
	_hull_bar_fill.color = Color(0.2, 1.0, 0.3) if hull_pct > 0.5 else (Color(1.0, 0.8, 0.2) if hull_pct > 0.25 else Color(1.0, 0.2, 0.2))
	_hull_label.text = "结构 " + str(int(unit.hull)) + "/" + str(int(unit.max_hull))

	_weapon_label.text = "武器: " + _get_weapon_summary(unit)

	var mode_names := ["自由开火", "保持距离", "环绕射击"]
	_attack_mode_label.text = "攻击模式: " + mode_names[unit.attack_mode] + " [G]"

	if unit.class_type == Unit.ShipClass.BATTLESHIP:
		_drone_label.visible = true
		var total = unit.drone_bay + unit.deployed_drones.size()
		_drone_label.text = "无人机 仓容/舱内/舱外: " + str(total) + "/" + str(unit.drone_bay) + "/" + str(unit.deployed_drones.size())
	else:
		_drone_label.visible = false

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
			elif i == 3:
				# 跃迁：进入施法选择模式
				main.enter_skill_targeting_mode(3, main._selected_units)
				return
			elif i == 4:
				# 减速：进入施法选择模式
				main.enter_skill_targeting_mode(4, main._selected_units)
				return
		elif i == 5:
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
	_speed_indicator.visible = false
	for btn in _skill_buttons:
		btn.visible = false


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


## 施法成功时隐藏提示
func hide_message() -> void:
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.queue_free()
		_message_label = null


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

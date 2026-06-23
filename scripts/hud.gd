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

const SKILL_NAMES := ["加速", "速射", "减伤", "跃迁", "减速"]
const SKILL_COLORS := [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.4, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.8, 0.3, 1.0),
	Color(0.6, 0.2, 0.8),
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
	for i in 5:
		_skill_buttons.append(get_node("SkillPanel/SkillBtn" + str(i)))


func _process(_delta: float) -> void:
	if main == null:
		_hide_all(); return
	var sel = main._selected_units
	if sel.size() == 0:
		_hide_all(); return
	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		_hide_all(); return

	# 速度指示器
	if Engine.time_scale != 1.0:
		_speed_indicator.visible = true
		_speed_indicator.text = "⚡ " + str(Engine.time_scale) + "x"
	else:
		_speed_indicator.visible = false

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
	_attack_mode_label.text = "攻击模式: " + mode_names[unit._attack_mode] + " [G]"

	if unit.class_type == Unit.ShipClass.BATTLESHIP:
		_drone_label.visible = true
		var total = unit._drone_bay + unit._deployed_drones.size()
		_drone_label.text = "无人机 仓容/舱内/舱外: " + str(total) + "/" + str(unit._drone_bay) + "/" + str(unit._deployed_drones.size())
	else:
		_drone_label.visible = false

	# ---- 右下技能面板（GridContainer 自动布局）----
	_update_skill_buttons(sel)


func _update_skill_buttons(sel: Array) -> void:
	var has_bs := false
	var has_df := false
	for u in sel:
		if not is_instance_valid(u): continue
		if u.class_type == Unit.ShipClass.BATTLESHIP: has_bs = true
		if u.class_type in [Unit.ShipClass.DRONE, Unit.ShipClass.FRIGATE]: has_df = true

	var indices: Array[int] = [0, 1, 2]
	if has_bs: indices.append(3)
	if has_df: indices.append(4)

	for btn in _skill_buttons:
		btn.visible = false

	for i in indices:
		var btn = _skill_buttons[i]
		btn.visible = true

		var max_cd := 0.0
		var any_active := false
		for u in sel:
			if is_instance_valid(u) and u.hull > 0:
				if u._skill_cooldowns[i] > max_cd: max_cd = u._skill_cooldowns[i]
				if u._skill_timers[i] > 0: any_active = true

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


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if main == null or main._selected_units.size() == 0:
		return

	# 检测技能按钮点击（基于按钮实际屏幕位置）
	for i in 5:
		var btn = _skill_buttons[i]
		if not btn.visible:
			continue
		var rect = Rect2(btn.global_position, Vector2(50, 50))
		if rect.has_point(event.position):
			for u in main._selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(i)
			get_viewport().set_input_as_handled()
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

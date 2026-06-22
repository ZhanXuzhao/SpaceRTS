extends Node2D

var main: Node2D = null
var font: Font = null

func _ready() -> void:
	font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if main == null:
		return
	var sel = main._selected_units
	if sel.size() != 1:
		# 选中 0 个或多个单位时不显示
		return

	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		return

	var vsize = get_viewport().get_visible_rect().size

	# ---- 左下角：单位信息面板 ----
	var info_x = 10.0
	var info_y = vsize.y - 160.0
	var team_str = "蓝队" if unit.team == Unit.Team.BLUE else "红队"
	var class_names = ["无人机", "护卫舰", "驱逐舰", "巡洋舰", "战列舰"]
	var cls = class_names[Unit._ship_class_tier(unit.class_type)]

	var lines = [
		team_str + " " + cls,
		"速度: " + str(int(unit.speed * unit._speed_mult)),
		"护盾: " + str(int(unit.shield)) + "/" + str(int(unit.max_shield)),
		"结构: " + str(int(unit.hull)) + "/" + str(int(unit.max_hull)),
		"武器: " + _get_weapon_summary(unit),
	]
	var line_h = 14.0
	for i in range(lines.size()):
		font.draw_string(get_canvas_item(), Vector2(info_x, info_y + i * line_h),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# ---- 右下角：技能按钮（仅友方） ----
	if unit.team != Unit.Team.BLUE:
		return

	var btn_size = 48.0
	var gap = 4.0
	var start_x = vsize.x - btn_size * 4 - gap * 3 - 10
	var start_y = vsize.y - btn_size - 10
	var skill_names = ["加速", "速射", "减伤", "跃迁"]
	var skill_colors = [
		Color(0.2, 0.6, 1.0),
		Color(1.0, 0.4, 0.2),
		Color(0.2, 1.0, 0.3),
		Color(0.8, 0.3, 1.0),
	]

	for i in range(4):
		# 战列舰专属第 4 个技能
		if i == 3 and unit.class_type != Unit.ShipClass.BATTLESHIP:
			continue
		var bx = start_x + i * (btn_size + gap)
		var by = start_y
		var cd = unit._skill_cooldowns[i]
		var active = unit._skill_timers[i] > 0
		var color = skill_colors[i].darkened(0.5) if cd > 0 else (skill_colors[i].lightened(0.3) if active else skill_colors[i])
		draw_rect(Rect2(bx, by, btn_size, btn_size), color, true)
		draw_rect(Rect2(bx, by, btn_size, btn_size), Color(0.2, 0.2, 0.2, 0.6), false, 1.0)
		font.draw_string(get_canvas_item(), Vector2(bx + 6, by + 20),
			skill_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		if cd > 0:
			font.draw_string(get_canvas_item(), Vector2(bx + 6, by + 42),
				str(ceil(cd)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.8, 0.2))

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if main == null or main._selected_units.size() != 1:
		return
	var unit = main._selected_units[0]
	if not is_instance_valid(unit) or unit.team != Unit.Team.BLUE:
		return

	var vsize = get_viewport().get_visible_rect().size
	var btn_size = 48.0
	var gap = 4.0
	var start_x = vsize.x - btn_size * 4 - gap * 3 - 10
	var start_y = vsize.y - btn_size - 10
	var mpos = event.position

	for i in range(4):
		if i == 3 and unit.class_type != Unit.ShipClass.BATTLESHIP:
			continue
		var bx = start_x + i * (btn_size + gap)
		var by = start_y
		var rect = Rect2(bx, by, btn_size, btn_size)
		if rect.has_point(mpos):
			unit.activate_skill(i)
			return

func _get_weapon_summary(unit: Unit) -> String:
	var names = []
	for w in unit._slot_weapons:
		if w != null:
			var wn = w.get_display_name()
			if wn not in names:
				names.append(wn)
	return ", ".join(names)

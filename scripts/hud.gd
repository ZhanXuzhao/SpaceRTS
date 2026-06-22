extends Node2D

var main: Node2D = null
var font: Font = null

const SKILL_KEYS = ["Z", "X", "C", "V"]
const SKILL_NAMES = ["加速", "速射", "减伤", "跃迁"]
const SKILL_COLORS = [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.4, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.8, 0.3, 1.0),
]

func _ready() -> void:
	font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if main == null:
		return
	var sel = main._selected_units
	if sel.size() == 0:
		return

	var unit = sel[0]
	if not is_instance_valid(unit) or unit.hull <= 0:
		return

	var vsize = get_viewport().get_visible_rect().size

	# ---- 左下角：单位信息面板 ----
	var info_x = 12.0
	var info_y = vsize.y - 170.0
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

	var has_battleship = false
	for u in sel:
		if u.class_type == Unit.ShipClass.BATTLESHIP:
			has_battleship = true
			break

	var margin = 20
	var btn_size = 50.0
	var gap = 6.0
	var skill_count = 3 if not has_battleship else 4
	var total_w = skill_count * btn_size + (skill_count - 1) * gap
	var start_x = vsize.x - total_w - margin
	var start_y = vsize.y - btn_size - margin

	for i in range(skill_count):
		var bx = start_x + i * (btn_size + gap)
		var by = start_y
		# 检查所有选中单位该技能是否都还在冷却
		var max_cd = 0.0
		var any_active = false
		for u in sel:
			if is_instance_valid(u) and u.hull > 0:
				var c = u._skill_cooldowns[i]
				if c > max_cd:
					max_cd = c
				if u._skill_timers[i] > 0:
					any_active = true
		var color = SKILL_COLORS[i]
		if max_cd > 0:
			color = color.darkened(0.5)
		elif any_active:
			color = color.lightened(0.3)
		draw_rect(Rect2(bx, by, btn_size, btn_size), color, true)
		draw_rect(Rect2(bx, by, btn_size, btn_size), Color(0.2, 0.2, 0.2, 0.6), false, 1.0)
		# 技能名
		font.draw_string(get_canvas_item(), Vector2(bx + 5, by + 18),
			SKILL_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		# 快捷键（左下角）
		font.draw_string(get_canvas_item(), Vector2(bx + 3, by + btn_size - 3),
			SKILL_KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.8, 0.6))
		# CD
		if max_cd > 0:
			font.draw_string(get_canvas_item(), Vector2(bx + btn_size - 20, by + btn_size - 3),
				str(ceil(max_cd)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.8, 0.2))

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if main == null or main._selected_units.size() == 0:
		return
	# 检查是否点击了技能按钮
	var vsize = get_viewport().get_visible_rect().size
	var has_battleship = false
	for u in main._selected_units:
		if u.class_type == Unit.ShipClass.BATTLESHIP:
			has_battleship = true
			break
	var margin = 20
	var btn_size = 50.0
	var gap = 6.0
	var skill_count = 3 if not has_battleship else 4
	var total_w = skill_count * btn_size + (skill_count - 1) * gap
	var start_x = vsize.x - total_w - margin
	var start_y = vsize.y - btn_size - margin
	var mpos = event.position

	for i in range(skill_count):
		var bx = start_x + i * (btn_size + gap)
		var by = start_y
		var rect = Rect2(bx, by, btn_size, btn_size)
		if rect.has_point(mpos):
			for u in main._selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(i)
			get_viewport().set_input_as_handled()
			return

func _get_weapon_summary(unit: Unit) -> String:
	var names = []
	for w in unit._slot_weapons:
		if w != null:
			var wn = w.get_display_name()
			if wn not in names:
				names.append(wn)
	return ", ".join(names)

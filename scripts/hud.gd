extends Node2D

var main: Node2D = null
var font: Font = null

const SKILL_KEYS = ["Z", "X", "C", "V", "B"]
const SKILL_NAMES = ["加速", "速射", "减伤", "跃迁", "减速"]
const SKILL_COLORS = [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.4, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.8, 0.3, 1.0),
	Color(0.6, 0.2, 0.8),
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

	# 船型
	font.draw_string(get_canvas_item(), Vector2(info_x, info_y),
		team_str + " " + cls, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# 速度
	font.draw_string(get_canvas_item(), Vector2(info_x, info_y + 14),
		"速度: " + str(int(unit.speed * unit._speed_mult)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# 护盾进度条
	var bar_y = info_y + 30
	var bar_w = 120.0
	var bar_h = 6.0
	draw_rect(Rect2(info_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.2, 0.8), true)
	if unit.max_shield > 0:
		draw_rect(Rect2(info_x, bar_y, bar_w * unit.shield / unit.max_shield, bar_h), Color(0.2, 0.5, 1.0, 0.9), true)
	font.draw_string(get_canvas_item(), Vector2(info_x + bar_w + 6, bar_y + 5),
		"护盾 " + str(int(unit.shield)) + "/" + str(int(unit.max_shield)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.8, 1.0))

	# 结构进度条
	var hull_bar_y = bar_y + bar_h + 4
	draw_rect(Rect2(info_x, hull_bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.2, 0.8), true)
	if unit.max_hull > 0:
		var hull_pct = unit.hull / unit.max_hull
		var hull_color = Color(0.2, 1.0, 0.3) if hull_pct > 0.5 else (Color(1.0, 0.8, 0.2) if hull_pct > 0.25 else Color(1.0, 0.2, 0.2))
		draw_rect(Rect2(info_x, hull_bar_y, bar_w * hull_pct, bar_h), hull_color, true)
	font.draw_string(get_canvas_item(), Vector2(info_x + bar_w + 6, hull_bar_y + 5),
		"结构 " + str(int(unit.hull)) + "/" + str(int(unit.max_hull)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 1.0, 0.6))

	# ---- 文字信息（自然向下排列） ----
	var line_y = hull_bar_y + bar_h + 12
	var lh = 14  # 行高

	# 武器
	font.draw_string(get_canvas_item(), Vector2(info_x, line_y),
		"武器: " + _get_weapon_summary(unit), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	line_y += lh

	# 攻击模式
	var mode_names = ["自由开火", "保持距离", "环绕射击"]
	font.draw_string(get_canvas_item(), Vector2(info_x, line_y),
		"攻击模式: " + mode_names[unit._attack_mode] + " [G]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.6))
	line_y += lh

	# 无人机仓（战列舰）
	if unit.class_type == Unit.ShipClass.BATTLESHIP:
		var total = unit._drone_bay + unit._deployed_drones.size()
		font.draw_string(get_canvas_item(), Vector2(info_x, line_y),
			"无人机 仓容/舱内/舱外: " + str(total) + "/" + str(unit._drone_bay) + "/" + str(unit._deployed_drones.size()),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0))
		line_y += lh

	# ---- 右下角：技能按钮（仅友方） ----
	if unit.team != Unit.Team.BLUE:
		return

	var has_battleship = false
	var has_drone_frigate = false
	for u in sel:
		if not is_instance_valid(u):
			continue
		if u.class_type == Unit.ShipClass.BATTLESHIP:
			has_battleship = true
		if u.class_type in [Unit.ShipClass.DRONE, Unit.ShipClass.FRIGATE]:
			has_drone_frigate = true

	# 技能按钮列表
	var skill_indices: Array[int] = [0, 1, 2]
	if has_battleship:
		skill_indices.append(3)
	if has_drone_frigate and not has_battleship:
		skill_indices.append(4)
	if has_battleship and has_drone_frigate:
		skill_indices.append(4)

	var margin = 20
	var btn_size = 50.0
	var gap = 6.0
	var skill_count = skill_indices.size()
	var total_w = skill_count * btn_size + (skill_count - 1) * gap
	var start_x = vsize.x - total_w - margin
	var start_y = vsize.y - btn_size - margin

	for si in range(skill_count):
		var i = skill_indices[si]
		var bx = start_x + si * (btn_size + gap)
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
	# 技能按钮点击检测
	var vsize = get_viewport().get_visible_rect().size
	var has_battleship = false
	var has_drone_frigate = false
	for u in main._selected_units:
		if not is_instance_valid(u):
			continue
		if u.class_type == Unit.ShipClass.BATTLESHIP:
			has_battleship = true
		if u.class_type in [Unit.ShipClass.DRONE, Unit.ShipClass.FRIGATE]:
			has_drone_frigate = true
	var skill_indices: Array[int] = [0, 1, 2]
	if has_battleship: skill_indices.append(3)
	if has_drone_frigate and not has_battleship: skill_indices.append(4)
	if has_battleship and has_drone_frigate: skill_indices.append(4)
	var margin = 20
	var btn_size = 50.0
	var gap = 6.0
	var skill_count = skill_indices.size()
	var total_w = skill_count * btn_size + (skill_count - 1) * gap
	var start_x = vsize.x - total_w - margin
	var start_y = vsize.y - btn_size - margin
	var mpos = event.position

	for si in range(skill_count):
		var i = skill_indices[si]
		var bx = start_x + si * (btn_size + gap)
		var by = start_y
		var rect = Rect2(bx, by, btn_size, btn_size)
		if rect.has_point(mpos):
			for u in main._selected_units:
				if is_instance_valid(u) and u.hull > 0:
					u.activate_skill(i)
			get_viewport().set_input_as_handled()
			return
			return

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

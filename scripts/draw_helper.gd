class_name DrawHelper
extends RefCounted

## 绘制辅助 — 所有 _draw_* 函数抽出
## 接收 main 节点引用，在其上调用 draw_* 方法


func draw_map_boundary(main: Node2D) -> void:
	var boundary_color = Color(1.0, 0.3, 0.1, 0.15)
	main.draw_arc(GameConfig.MAP_CENTER, GameConfig.MAP_RADIUS, 0, TAU, 192, boundary_color, 3.0)
	var warn_color = Color(1.0, 0.2, 0.05, 0.06)
	main.draw_arc(GameConfig.MAP_CENTER, GameConfig.MAP_RADIUS, 0, TAU, 192, warn_color, 12.0)


func draw_selection_box(main: Node2D, is_dragging: bool, drag_start: Vector2, drag_end: Vector2) -> void:
	if not is_dragging:
		return
	var rect = _get_drag_rect(drag_start, drag_end)
	if rect.has_area():
		main.draw_rect(rect, Color(0.2, 0.5, 1.0, 0.15), true)
		main.draw_rect(rect, Color(0.2, 0.5, 1.0, 0.8), false, 1.5)


func draw_attack_cursor(main: Node2D, attack_cursor_mode: bool, mouse_pos: Vector2) -> void:
	if not attack_cursor_mode:
		return
	const CROSS_SIZE: float = 12.0
	var cross_color = Color(1.0, 0.2, 0.2, 0.9)
	main.draw_line(mouse_pos + Vector2(-CROSS_SIZE, 0), mouse_pos + Vector2(CROSS_SIZE, 0), cross_color, 2.0)
	main.draw_line(mouse_pos + Vector2(0, -CROSS_SIZE), mouse_pos + Vector2(0, CROSS_SIZE), cross_color, 2.0)
	main.draw_circle(mouse_pos, CROSS_SIZE * 0.6, cross_color, false, 1.5)


func draw_orbit_drag_preview(main: Node2D, orbit_is_dragging: bool, orbit_drag_start: Vector2, orbit_drag_end: Vector2) -> void:
	if not orbit_is_dragging:
		return
	var start = orbit_drag_start
	var end = orbit_drag_end
	var radius = start.distance_to(end)
	main.draw_circle(start, radius, Color(0.2, 1.0, 0.5, 0.2), false, 2.0)
	main.draw_line(start, end, Color(0.2, 1.0, 0.5, 0.8), 2.0)


func draw_skill_targeting(main: Node2D, skill_targeting_mode: int, skill_targeting_units: Array, player_team_name: String) -> void:
	if skill_targeting_mode == 3:
		_draw_skill_jump(main, skill_targeting_units)
	elif skill_targeting_mode == 4:
		_draw_skill_slow(main, skill_targeting_units)
	elif skill_targeting_mode == 6 or skill_targeting_mode == 7:
		_draw_skill_deploy(main, skill_targeting_units, player_team_name)


func _draw_skill_jump(main: Node2D, units: Array) -> void:
	var jump_fill = Color(0.8, 0.3, 1.0, 0.08)
	var jump_stroke = Color(0.8, 0.3, 1.0, 0.6)
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			main.draw_circle(u.global_position, GameConfig.SKILL_JUMP_MAX_DIST, jump_fill, true)
			main.draw_circle(u.global_position, GameConfig.SKILL_JUMP_MAX_DIST, jump_stroke, false, 2.0)
	var world_mouse = main._screen_to_world(main.get_viewport().get_mouse_position())
	main.draw_circle(world_mouse, 8.0, jump_stroke, false, 2.0)
	var center = _get_selection_center(units)
	if center != null:
		var dir = (world_mouse - center).normalized()
		var arrow_tip = world_mouse
		var arrow_base = world_mouse - dir * 20.0
		main.draw_line(arrow_base, arrow_tip, jump_stroke, 3.0)
		main.draw_line(arrow_tip, arrow_tip + dir.rotated(2.5) * 8.0, jump_stroke, 2.0)
		main.draw_line(arrow_tip, arrow_tip + dir.rotated(-2.5) * 8.0, jump_stroke, 2.0)


func _draw_skill_slow(main: Node2D, units: Array) -> void:
	var slow_fill = Color(0.6, 0.2, 0.8, 0.08)
	var slow_stroke = Color(0.6, 0.2, 0.8, 0.6)
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			main.draw_circle(u.global_position, GameConfig.SKILL_SLOW_RANGE, slow_fill, true)
			main.draw_circle(u.global_position, GameConfig.SKILL_SLOW_RANGE, slow_stroke, false, 2.0)
	var world_mouse = main._screen_to_world(main.get_viewport().get_mouse_position())
	main.draw_circle(world_mouse, 6.0, slow_stroke, false, 2.0)


func _draw_skill_deploy(main: Node2D, units: Array, player_team_name: String) -> void:
	var deploy_fill = Color(0.5, 0.8, 1.0, 0.08)
	var deploy_stroke = Color(0.5, 0.8, 1.0, 0.6)
	for u in units:
		if is_instance_valid(u) and u.hull > 0 and u.team == player_team_name:
			main.draw_circle(u.global_position, GameConfig.DEPLOY_RANGE, deploy_fill, true)
			main.draw_circle(u.global_position, GameConfig.DEPLOY_RANGE, deploy_stroke, false, 2.0)
	var world_mouse = main._screen_to_world(main.get_viewport().get_mouse_position())
	var deploy_valid := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0 and u.team == player_team_name:
			if u.is_in_deploy_range(world_mouse):
				deploy_valid = true
				break
	if deploy_valid:
		main.draw_circle(world_mouse, 10.0, Color(0.3, 1.0, 0.5, 0.6), false, 2.0)
		main.draw_circle(world_mouse, 6.0, Color(0.3, 1.0, 0.5, 0.3), true)
	else:
		main.draw_circle(world_mouse, 10.0, Color(1.0, 0.3, 0.3, 0.6), false, 2.0)


func draw_unit_command_lines(main: Node2D, selected_units: Array) -> void:
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		if not unit._is_moving and not is_instance_valid(unit._current_target) and unit._command_queue.size() == 0:
			continue
		var line_width = 1.2 * unit._size_mult
		var prev = unit.global_position

		if unit._is_moving and not unit._is_orbit:
			main.draw_line(prev, unit._target_position, Color(0.2, 1.0, 0.3, 0.55), line_width)
			prev = unit._target_position
		if is_instance_valid(unit._current_target) and unit._current_target.hull > 0 and unit._current_target.team != unit.team:
			var tp = unit._current_target.global_position
			main.draw_line(prev, tp, Color(1.0, 0.15, 0.15, 0.55), line_width)
			prev = tp

		for cmd in unit._command_queue:
			if cmd.type == "move":
				main.draw_line(prev, cmd.pos, Color(0.2, 1.0, 0.3, 0.55), line_width)
				prev = cmd.pos
			elif cmd.type == "attack":
				if not is_instance_valid(cmd.target):
					continue
				var t = cmd.target
				if "hull" in t and t.hull <= 0:
					continue
				main.draw_line(prev, t.global_position, Color(1.0, 0.15, 0.15, 0.55), line_width)
				prev = t.global_position
			elif cmd.type == "deploy":
				main.draw_line(prev, cmd.pos, Color(0.5, 0.8, 1.0, 0.55), line_width)
				main.draw_circle(cmd.pos, 6.0, Color(0.5, 0.8, 1.0, 0.5), false, 1.5)
				prev = cmd.pos


func draw_orbit_cursor(main: Node2D, orbit_cursor_mode: bool) -> void:
	if not orbit_cursor_mode:
		return
	var world_mouse = main._screen_to_world(main.get_viewport().get_mouse_position())
	var orbit_color = Color(0.2, 1.0, 0.5, 0.9)
	main.draw_circle(world_mouse, 14.0, orbit_color, false, 2.0)
	main.draw_circle(world_mouse, 10.0, Color(0.2, 1.0, 0.5, 0.3), true)
	var a = world_mouse + Vector2(14, 0)
	main.draw_line(a, a + Vector2(-4, -3), orbit_color, 2.0)
	main.draw_line(a, a + Vector2(-4, 3), orbit_color, 2.0)


static func _get_selection_center(units: Array):
	if units.size() == 0:
		return null
	var sum := Vector2.ZERO
	var count := 0
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			sum += u.global_position
			count += 1
	if count > 0:
		return sum / count
	return null


static func _get_drag_rect(drag_start: Vector2, drag_end: Vector2) -> Rect2:
	return Rect2(
		Vector2(min(drag_start.x, drag_end.x), min(drag_start.y, drag_end.y)),
		Vector2(abs(drag_end.x - drag_start.x), abs(drag_end.y - drag_start.y))
	)


## 绘制暂停/结束覆盖层文字
func draw_overlay(main: Node2D, game_over: bool, paused: bool, winner: String, player_team_name: String) -> void:
	var vsize = main.get_viewport().get_visible_rect().size

	if game_over:
		main.draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var is_victory = winner == player_team_name
		var title = "胜利" if is_victory else "失败"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var font = ThemeDB.fallback_font
		var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(main.get_canvas_item(), center - ts / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		font.draw_string(main.get_canvas_item(), center - Vector2(40, 10), winner + "获胜",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(main.get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(main.get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

	elif paused:
		main.draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)
		var center = vsize / 2
		var font = ThemeDB.fallback_font
		font.draw_string(main.get_canvas_item(), center - Vector2(40, 50), "  暂停",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.7, 1.0))
		font.draw_string(main.get_canvas_item(), center - Vector2(80, -10), "[ESC] 继续游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(main.get_canvas_item(), center - Vector2(80, -40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(main.get_canvas_item(), center - Vector2(80, -70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

extends Node2D

## 指向 Main 的引用
var main: Node2D = null


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if main == null or not (main._game_over or main._paused):
		return

	var click = event.position
	var center = get_viewport().get_visible_rect().size / 2
	var font = ThemeDB.fallback_font
	var fsize := 18

	if main._game_over:
		# [R] 重新开始  →  center - Vector2(80, 40)
		if _hit_test(click, center - Vector2(80, 40), "[R] 重新开始", font, fsize):
			get_tree().reload_current_scene()
		# [Q] 退出游戏  →  center - Vector2(80, 70)
		if _hit_test(click, center - Vector2(80, 70), "[Q] 退出游戏", font, fsize):
			get_tree().quit()

	elif main._paused:
		# [ESC] 继续游戏  →  center - Vector2(80, -10)
		if _hit_test(click, center - Vector2(80, -10), "[ESC] 继续游戏", font, fsize):
			main._paused = false
			get_tree().paused = false
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# [R] 重新开始  →  center - Vector2(80, -40)
		if _hit_test(click, center - Vector2(80, -40), "[R] 重新开始", font, fsize):
			get_tree().reload_current_scene()
		# [Q] 退出游戏  →  center - Vector2(80, -70)
		if _hit_test(click, center - Vector2(80, -70), "[Q] 退出游戏", font, fsize):
			get_tree().quit()


func _hit_test(click_pos: Vector2, text_center: Vector2, text: String, font: Font, font_size: int) -> bool:
	var ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var rect = Rect2(text_center.x - ts.x / 2, text_center.y - font_size, ts.x, font_size + 4)
	return rect.has_point(click_pos)


func _draw() -> void:
	if main == null:
		return
	if not (main._game_over or main._paused):
		return

	var vsize = get_viewport().get_visible_rect().size

	# 半透明遮罩
	draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.65), true)

	var center = vsize / 2
	var font = ThemeDB.fallback_font

	if main._game_over:
		var is_victory = main._winner == "蓝队"
		var title = "胜利！" if is_victory else "失败！"
		var title_color = Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3)
		var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 32)
		font.draw_string(get_canvas_item(), center - ts / 2 - Vector2(0, 60), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, title_color)
		font.draw_string(get_canvas_item(), center - Vector2(40, 10), main._winner + "获胜",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color.WHITE)
		font.draw_string(get_canvas_item(), center - Vector2(80, 40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, 70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

	elif main._paused:
		font.draw_string(get_canvas_item(), center - Vector2(40, 50), "  暂停",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.7, 1.0))
		font.draw_string(get_canvas_item(), center - Vector2(80, -10), "[ESC] 继续游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -40), "[R] 重新开始",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))
		font.draw_string(get_canvas_item(), center - Vector2(80, -70), "[Q] 退出游戏",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 0.7, 0.7))

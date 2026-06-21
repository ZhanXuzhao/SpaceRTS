extends CanvasLayer

## 指向 Main 的引用
var main: Node2D = null


func build_menu() -> void:
	"""创建暂停/游戏结束 UI 控件"""
	# 半透明遮罩
	var bg = ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标签 + 按钮共用设置
	var center_x = get_viewport().get_visible_rect().size.x / 2
	var center_y = get_viewport().get_visible_rect().size.y / 2
	var font_size := 18
	var btn_w := 220
	var btn_h := 36

	# --- 游戏结束 ---
	if main._game_over:
		# 标题 Label
		var title = Label.new()
		title.name = "Title"
		var is_victory = main._winner == "蓝队"
		title.text = "胜利！" if is_victory else "失败！"
		title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3))
		title.add_theme_font_size_override("font_size", 32)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(center_x - 80, center_y - 80)
		title.size = Vector2(160, 40)
		add_child(title)

		# 副标题
		var sub = Label.new()
		sub.name = "Subtitle"
		sub.text = main._winner + "获胜"
		sub.add_theme_color_override("font_color", Color.WHITE)
		sub.add_theme_font_size_override("font_size", 22)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.position = Vector2(center_x - 80, center_y - 40)
		sub.size = Vector2(160, 30)
		add_child(sub)

		_add_button("[R] 重新开始", center_y + 10, font_size, btn_w, btn_h, _restart)
		_add_button("[Q] 退出游戏", center_y + 50, font_size, btn_w, btn_h, _quit)

	# --- 暂停 ---
	elif main._paused:
		var title = Label.new()
		title.name = "Title"
		title.text = "  暂停"
		title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		title.add_theme_font_size_override("font_size", 32)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(center_x - 80, center_y - 70)
		title.size = Vector2(160, 40)
		add_child(title)

		_add_button("[ESC] 继续游戏", center_y - 20, font_size, btn_w, btn_h, _resume)
		_add_button("[R] 重新开始", center_y + 20, font_size, btn_w, btn_h, _restart)
		_add_button("[Q] 退出游戏", center_y + 60, font_size, btn_w, btn_h, _quit)


func _add_button(text: String, y: float, font_size: int, w: int, h: int, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = Vector2(w, h)
	btn.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - w / 2, y)
	btn.size = Vector2(w, h)
	btn.pressed.connect(callback)
	add_child(btn)


func _resume() -> void:
	main._paused = false
	get_tree().paused = false
	queue_free()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().quit()

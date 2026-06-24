extends CanvasLayer

## 指向 Main 的引用
var main: Node2D = null

# 场景节点引用
var _bg: ColorRect
var _menu: VBoxContainer
var _title: Label
var _subtitle: Label
var _resume_btn: Button


func _ready() -> void:
	_bg = $Bg
	_menu = $MenuContainer
	_title = $MenuContainer/Title
	_subtitle = $MenuContainer/Subtitle
	_resume_btn = $MenuContainer/ResumeBtn

	$MenuContainer/ResumeBtn.pressed.connect(_resume)
	$MenuContainer/RestartBtn.pressed.connect(_restart)
	$MenuContainer/QuitBtn.pressed.connect(_quit)

	# 初始隐藏
	_bg.visible = false
	_menu.visible = false


func build_menu() -> void:
	"""根据场景动态更新 UI 内容"""
	_bg.visible = true
	_menu.visible = true

	if main._game_over:
		var is_victory = main._winner == "蓝队"
		_title.text = "胜利！" if is_victory else "失败！"
		_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3))
		if main._winner == "黄队":
			_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		_subtitle.text = main._winner + "获胜"
		_subtitle.visible = true
		_resume_btn.visible = false

	elif main._paused:
		_title.text = "暂停"
		_title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		_subtitle.visible = false
		_resume_btn.visible = true


func hide_menu() -> void:
	_bg.visible = false
	_menu.visible = false


func _resume() -> void:
	main._resume_game()


func _restart() -> void:
	main._restart_game()


func _quit() -> void:
	get_tree().quit()

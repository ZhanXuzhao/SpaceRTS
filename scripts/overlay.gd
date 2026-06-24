extends CanvasLayer

## 指向 Main 的引用
var main: Node2D = null

# 场景节点引用
var _bg: ColorRect
var _menu: VBoxContainer
var _title: Label
var _subtitle: Label
var _resume_btn: Button

# 阵营图标（按索引循环）
const _TEAM_ICONS := ["🔵","🔴","🟡","🟢","🟣","🟠","🔷","⚪","🩷","💚"]

# 积分榜 & DPS
var _scoreboard_entries: Array[Label] = []
var _dps_entries: Array[Label] = []
const WEAPON_NAMES := {
	Weapon.WeaponType.BULLET: "子弹",
	Weapon.WeaponType.MISSILE: "导弹",
	Weapon.WeaponType.LASER: "激光",
	Weapon.WeaponType.PD: "PD",
}


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

	# 构建积分榜标签（仅标题，具体行由 build_menu 动态创建）
	_build_scoreboard_headers()


func _build_scoreboard_headers() -> void:
	"""创建积分榜和 DPS 的标题行（不含具体阵营行）"""
	var header = Label.new()
	header.name = "ScoreHeader"
	header.text = "——— 阵营积分榜 ———"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(header)
	_menu.move_child(header, 2)

	var dps_header = Label.new()
	dps_header.name = "DpsHeader"
	dps_header.text = "——— 武器 DPS ———"
	dps_header.add_theme_font_size_override("font_size", 18)
	dps_header.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	dps_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(dps_header)


func _clear_team_labels() -> void:
	"""清除旧的阵营行标签"""
	for lbl in _scoreboard_entries:
		lbl.queue_free()
	_scoreboard_entries.clear()
	for lbl in _dps_entries:
		lbl.queue_free()
	_dps_entries.clear()


func _rebuild_team_labels() -> void:
	"""根据 main 中的 faction_team_names 重建阵营行"""
	var names: Array[String] = main.faction_team_names
	var colors: Array[Color] = main.faction_team_colors
	var dps_header = _menu.get_node("DpsHeader")
	var score_header = _menu.get_node("ScoreHeader")

	for i in names.size():
		var team_name = names[i]
		var icon = _TEAM_ICONS[i % _TEAM_ICONS.size()]
		var color = colors[i]

		# 积分行（插在 ScoreHeader 之后）
		var slbl = Label.new()
		slbl.name = "Score_" + team_name
		slbl.text = icon + " " + team_name + ": 0"
		slbl.add_theme_font_size_override("font_size", 16)
		slbl.add_theme_color_override("font_color", color)
		slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu.add_child(slbl)
		_menu.move_child(slbl, score_header.get_index() + 1 + i)
		_scoreboard_entries.append(slbl)

		# DPS 行（插在 DpsHeader 之后）
		var dlbl = Label.new()
		dlbl.name = "Dps_" + team_name
		dlbl.text = icon + " " + team_name + ": 计算中..."
		dlbl.add_theme_font_size_override("font_size", 14)
		dlbl.add_theme_color_override("font_color", color.lightened(0.3))
		dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu.add_child(dlbl)
		_menu.move_child(dlbl, dps_header.get_index() + 1 + i)
		_dps_entries.append(dlbl)


func build_menu() -> void:
	"""根据场景动态更新 UI 内容"""
	_bg.visible = true
	_menu.visible = true

	# 重建阵营行（清除旧的，按实际 faction 创建）
	_clear_team_labels()
	_rebuild_team_labels()

	# 更新积分榜
	_update_scoreboard()

	if main._game_over:
		var is_victory = main._winner == main._player_team_name
		_title.text = "胜利！" if is_victory else "失败！"
		_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3))
		_subtitle.text = main._winner + "获胜"
		_subtitle.visible = true
		_resume_btn.visible = false

	elif main._paused:
		_title.text = "暂停"
		_title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		_subtitle.visible = false
		_resume_btn.visible = true


func _update_scoreboard() -> void:
	"""刷新积分榜显示"""
	var scores = Unit.team_scores
	var dmg_data = Unit.team_weapon_damage
	var life_data = Unit.team_weapon_lifetime
	var wt_types = [Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE, Weapon.WeaponType.LASER, Weapon.WeaponType.PD]

	for lbl in _scoreboard_entries:
		var team_name = lbl.name.trim_prefix("Score_")
		var score = scores.get(team_name, 0)
		# 从文本中提取图标部分
		var icon = lbl.text[0] if lbl.text.length() > 0 else ""
		lbl.text = icon + " " + team_name + ": " + str(score)

	for lbl in _dps_entries:
		var team_name = lbl.name.trim_prefix("Dps_")
		var icon = lbl.text[0] if lbl.text.length() > 0 else ""
		var parts: Array[String] = []
		parts.append(icon + " " + team_name)
		for wt in wt_types:
			var dmg = dmg_data.get(team_name, {}).get(wt, 0.0)
			var life = life_data.get(team_name, {}).get(wt, 0.0)
			var dps = dmg / life if life > 0.0 else 0.0
			parts.append(WEAPON_NAMES[wt] + " " + str(roundi(dps)))
		lbl.text = "  ".join(parts)


func hide_menu() -> void:
	_bg.visible = false
	_menu.visible = false


func _resume() -> void:
	main._resume_game()


func _restart() -> void:
	main._restart_game()


func _quit() -> void:
	get_tree().quit()

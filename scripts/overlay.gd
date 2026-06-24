extends CanvasLayer

## 指向 Main 的引用
var main: Node2D = null

# 场景节点引用
var _bg: ColorRect
var _menu: VBoxContainer
var _title: Label
var _subtitle: Label
var _resume_btn: Button

# 积分榜
var _scoreboard_entries: Array[Label] = []

# 阵营显示配置
const TEAM_ICONS := {
	Unit.Team.BLUE: "🔵",
	Unit.Team.RED: "🔴",
	Unit.Team.YELLOW: "🟡",
	Unit.Team.GREEN: "🟢",
}
const TEAM_NAMES := {
	Unit.Team.BLUE: "蓝队",
	Unit.Team.RED: "红队",
	Unit.Team.YELLOW: "黄队",
	Unit.Team.GREEN: "绿队",
}
const TEAM_COLORS := {
	Unit.Team.BLUE: Color(0.2, 0.5, 1.0),
	Unit.Team.RED: Color(1.0, 0.25, 0.25),
	Unit.Team.YELLOW: Color(1.0, 0.8, 0.1),
	Unit.Team.GREEN: Color(0.2, 1.0, 0.3),
}

# DPS 显示
var _dps_entries: Array[Label] = []  # 每阵营一行
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

	# 构建积分榜标签
	_build_scoreboard_labels()


func _build_scoreboard_labels() -> void:
	"""在菜单中创建积分榜标签"""
	var header = Label.new()
	header.name = "ScoreHeader"
	header.text = "——— 阵营积分榜 ———"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(header)
	_menu.move_child(header, 2)  # 放在 Title 和 Subtitle 之后

	for team in [Unit.Team.BLUE, Unit.Team.RED, Unit.Team.YELLOW, Unit.Team.GREEN]:
		var lbl = Label.new()
		lbl.name = "Score_" + TEAM_NAMES[team]
		lbl.text = TEAM_ICONS[team] + " " + TEAM_NAMES[team] + ": 0"
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", TEAM_COLORS[team])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu.add_child(lbl)
		_scoreboard_entries.append(lbl)

	# DPS 标题
	var dps_header = Label.new()
	dps_header.name = "DpsHeader"
	dps_header.text = "——— 武器 DPS ———"
	dps_header.add_theme_font_size_override("font_size", 18)
	dps_header.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	dps_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(dps_header)

	# 每阵营一行 DPS
	for team in [Unit.Team.BLUE, Unit.Team.RED, Unit.Team.YELLOW, Unit.Team.GREEN]:
		var lbl = Label.new()
		lbl.name = "Dps_" + TEAM_NAMES[team]
		lbl.text = TEAM_ICONS[team] + " " + TEAM_NAMES[team] + ": 计算中..."
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", TEAM_COLORS[team].lightened(0.3))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu.add_child(lbl)
		_dps_entries.append(lbl)


func build_menu() -> void:
	"""根据场景动态更新 UI 内容"""
	_bg.visible = true
	_menu.visible = true

	# 更新积分榜
	_update_scoreboard()

	if main._game_over:
		var is_victory = main._winner == "蓝队"
		_title.text = "胜利！" if is_victory else "失败！"
		_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if is_victory else Color(1.0, 0.3, 0.3))
		if main._winner == "黄队":
			_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		if main._winner == "绿队":
			_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
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
	for lbl in _scoreboard_entries:
		var team_str = lbl.name.trim_prefix("Score_")
		var team := Unit.Team.BLUE
		for t in TEAM_NAMES:
			if TEAM_NAMES[t] == team_str:
				team = t
				break
		var score = scores.get(team, 0)
		lbl.text = TEAM_ICONS[team] + " " + TEAM_NAMES[team] + ": " + str(score)

	# 刷新 DPS
	var dmg_data = Unit.team_weapon_damage
	var life_data = Unit.team_weapon_lifetime
	var wt_types = [Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE, Weapon.WeaponType.LASER, Weapon.WeaponType.PD]
	for lbl in _dps_entries:
		var team_str = lbl.name.trim_prefix("Dps_")
		var team := Unit.Team.BLUE
		for t in TEAM_NAMES:
			if TEAM_NAMES[t] == team_str:
				team = t
				break
		var parts: Array[String] = []
		parts.append(TEAM_ICONS[team] + " " + TEAM_NAMES[team])
		for wt in wt_types:
			var dmg = dmg_data.get(team, {}).get(wt, 0.0)
			var life = life_data.get(team, {}).get(wt, 0.0)
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

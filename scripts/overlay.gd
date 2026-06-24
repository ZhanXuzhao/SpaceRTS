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

# 阵营数据（积分 + DPS）
var _faction_entries: Array[Label] = []
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

	# 构建阵营数据标题（具体行由 build_menu 动态创建）
	_build_faction_data_header()


func _build_faction_data_header() -> void:
	"""创建阵营数据标题行（积分 + DPS 合并）"""
	var header = Label.new()
	header.name = "FactionHeader"
	header.text = "——— 阵营数据 ———"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.auto_translate = false
	_menu.add_child(header)


func _clear_team_labels() -> void:
	"""清除旧的阵营标签（立即从场景树移除避免名字冲突）"""
	for lbl in _faction_entries:
		if is_instance_valid(lbl):
			_menu.remove_child(lbl)
			lbl.queue_free()
	_faction_entries.clear()


func _rebuild_team_labels() -> void:
	"""根据 main 中的 faction_team_names 重建阵营行（积分 + DPS 合并）"""
	var names: Array[String] = main.faction_team_names
	var colors: Array[Color] = main.faction_team_colors
	var header = _menu.get_node("FactionHeader")

	for i in names.size():
		var team_name = names[i]
		var icon = _TEAM_ICONS[i % _TEAM_ICONS.size()]
		var color = colors[i]

		var lbl = Label.new()
		lbl.name = "FactionData_" + team_name
		lbl.text = icon + " " + team_name + ": 0"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.auto_translate = false
		_menu.add_child(lbl)
		_menu.move_child(lbl, header.get_index() + 1 + i)
		_faction_entries.append(lbl)


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
	"""刷新阵营数据（积分 + DPS 合并显示）"""
	var scores = Unit.team_scores
	var dmg_data = Unit.team_weapon_damage
	var life_data = Unit.team_weapon_lifetime
	var wt_types = [Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE, Weapon.WeaponType.LASER, Weapon.WeaponType.PD]

	for lbl in _faction_entries:
		var team_name = lbl.name.trim_prefix("FactionData_")
		var icon = lbl.text[0] if lbl.text.length() > 0 else ""
		var score = scores.get(team_name, 0)

		var parts: Array[String] = []
		parts.append(icon + " " + team_name + "  积分:" + str(score))
		for wt in wt_types:
			var dmg = dmg_data.get(team_name, {}).get(wt, 0.0)
			var life = life_data.get(team_name, {}).get(wt, 0.0)
			var dps = dmg / life if life > 0.0 else 0.0
			parts.append(WEAPON_NAMES[wt] + ":" + str(roundi(dps)))
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

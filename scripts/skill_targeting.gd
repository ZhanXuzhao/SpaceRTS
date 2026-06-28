class_name SkillTargeting
extends RefCounted

## 技能施法选择模式管理


## 进入施法选择模式
func enter_skill_targeting_mode(main, skill_index: int, units: Array, player_team_name: String, team_minerals: Dictionary) -> bool:
	# 部署技能（6/7）：检查矿物是否足够
	if skill_index == 6 or skill_index == 7:
		var cost = GameConfig.DEPLOY_COST_SHIPYARD if skill_index == 6 else GameConfig.DEPLOY_COST_MINE
		var any_afford := false
		for u in units:
			if is_instance_valid(u) and u.hull > 0 and u.team == player_team_name:
				var team_min = team_minerals.get(u.team, 0.0)
				if team_min >= cost:
					any_afford = true
					break
		if not any_afford:
			var hud = main.get_node("HudLayer/Hud")
			if hud.has_method("show_message"):
				hud.show_message("矿物不足")
			return false

	# 冷却判定
	if skill_index < 6 or skill_index == 8:
		var all_on_cd := true
		for u in units:
			if is_instance_valid(u) and u.hull > 0 and u._skill_cooldowns[skill_index] <= 0:
				all_on_cd = false
				break
		if all_on_cd:
			var hud = main.get_node("HudLayer/Hud")
			if hud.has_method("show_message"):
				hud.show_message("冷却中")
			return false

	return true


## 技能施法点击处理
func handle_skill_targeting_click(
	main,
	screen_pos: Vector2,
	skill_targeting_mode: int,
	skill_targeting_units: Array,
	units: Array,
	player_team_name: String,
	team_minerals: Dictionary,
) -> bool:
	"""返回 true 表示已处理，false 表示未处理"""
	var world_pos = main._screen_to_world(screen_pos)
	var skill_idx = skill_targeting_mode

	if skill_idx == 3:
		return _handle_jump_click(main, skill_idx, skill_targeting_units, world_pos)

	if skill_idx == 4:
		return _handle_slow_click(main, skill_idx, skill_targeting_units, units, player_team_name, world_pos)

	# 部署技能（6=船厂, 7=矿厂）
	if skill_idx == 6 or skill_idx == 7:
		return _handle_deploy_click(main, skill_idx, skill_targeting_units, player_team_name, team_minerals, world_pos)

	# EMP（8）
	if skill_idx == 8:
		return _handle_emp_click(main, skill_idx, skill_targeting_units, world_pos)

	return false


## 太空总览技能施法
func handle_overview_skill_targeting(
	main,
	skill_targeting_mode: int,
	skill_targeting_units: Array,
	_units: Array,
	player_team_name: String,
	team_minerals: Dictionary,
	target,
) -> void:
	var skill_idx = skill_targeting_mode

	if skill_idx == 3:
		_handle_jump_cast(main, skill_targeting_units, target.global_position)
	elif skill_idx == 4:
		_handle_slow_cast(main, skill_targeting_units, target, player_team_name)
	elif skill_idx == 6 or skill_idx == 7:
		_handle_deploy_at(main, skill_idx, skill_targeting_units, player_team_name, team_minerals, target.global_position)
	elif skill_idx == 8:
		_handle_emp_cast(main, skill_targeting_units, target.global_position)


func _handle_jump_click(main, _skill_idx: int, units: Array, world_pos: Vector2) -> bool:
	var any_cast := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			if u._skill_cooldowns[3] <= 0:
				u.jump_to_position(world_pos)
				any_cast = true
	var hud = main.get_node("HudLayer/Hud")
	if any_cast:
		if hud.has_method("hide_message"):
			hud.hide_message()
		return true  # 退出施法模式
	else:
		if hud.has_method("show_message"):
			hud.show_message("冷却中")
		return false


func _handle_jump_cast(main, units: Array, target_pos: Vector2) -> void:
	var any_cast := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			if u._skill_cooldowns[3] <= 0:
				u.jump_to_position(target_pos)
				any_cast = true
	var hud = main.get_node("HudLayer/Hud")
	if any_cast:
		if hud.has_method("hide_message"):
			hud.hide_message()


func _handle_slow_click(main, _skill_idx: int, units: Array, all_units: Array, player_team_name: String, world_pos: Vector2) -> bool:
	# 查找目标
	var target = null
	var hud = main.get_node("HudLayer/Hud")
	for unit in all_units:
		if not is_instance_valid(unit) or unit.hull <= 0 or unit.team == player_team_name:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			target = unit
			break

	if target == null:
		if hud.has_method("show_message"):
			hud.show_message("请选择目标")
		return false  # 留在施法模式

	var in_range := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			var d = u.global_position.distance_to(target.global_position)
			if d <= GameConfig.SKILL_SLOW_RANGE and u._skill_cooldowns[4] <= 0:
				in_range = true
				u.apply_slow_to_target(target)

	if in_range:
		if hud.has_method("hide_message"):
			hud.hide_message()
		return true  # 退出施法模式
	else:
		if hud.has_method("show_message"):
			hud.show_message("超出范围")
		return false  # 留在施法模式


func _handle_slow_cast(main, units: Array, target, _player_team_name: String) -> void:
	var in_range := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			var d = u.global_position.distance_to(target.global_position)
			if d <= GameConfig.SKILL_SLOW_RANGE and u._skill_cooldowns[4] <= 0:
				in_range = true
				u.apply_slow_to_target(target)

	var hud = main.get_node("HudLayer/Hud")
	if in_range:
		if hud.has_method("hide_message"):
			hud.hide_message()
	else:
		if hud.has_method("show_message"):
			hud.show_message("超出范围")


func _handle_deploy_click(main, skill_idx: int, units: Array, player_team_name: String, team_minerals: Dictionary, world_pos: Vector2) -> bool:
	var building_type = Building.BuildingType.SHIPYARD if skill_idx == 6 else Building.BuildingType.MINE
	var cost = GameConfig.DEPLOY_COST_SHIPYARD if skill_idx == 6 else GameConfig.DEPLOY_COST_MINE
	var any_deploy := false
	var out_of_range := false
	var shift_held = Input.is_key_pressed(KEY_SHIFT)

	# 检测位置是否与已有建筑重叠
	var hud = main.get_node("HudLayer/Hud")
	if Building.is_position_blocked(world_pos):
		if hud.has_method("show_message"):
			hud.show_message("此处已有建筑")
		return false  # 不退出施法模式，让玩家重新选择位置

	for u in units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != player_team_name:
			continue
		var team_min = team_minerals.get(u.team, 0.0)
		if team_min < cost:
			continue
		if shift_held:
			u.queue_deploy_building(building_type, cost, world_pos)
		else:
			u._command_queue.clear()
			u._command_queue.append({"type": "deploy", "building_type": building_type, "cost": cost, "pos": world_pos})
			u._try_execute_queue()
		any_deploy = true
		if not u.is_in_deploy_range(world_pos):
			out_of_range = true

	if any_deploy:
		if hud.has_method("hide_message"):
			hud.hide_message()
		return not shift_held  # shift 时不退出施法模式
	elif out_of_range:
		if hud.has_method("show_message"):
			hud.show_message("超出范围")
		return false
	else:
		if hud.has_method("show_message"):
			hud.show_message("矿物不足")
		return false


func _handle_emp_click(main, _skill_idx: int, units: Array, world_pos: Vector2) -> bool:
	var any_cast := false
	var out_of_range := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			var dist = u.global_position.distance_to(world_pos)
			if dist > GameConfig.SKILL_EMP_CAST_RANGE:
				out_of_range = true
				continue
			if u._skill_cooldowns[8] > 0.0:
				continue
			u.activate_emp(world_pos)
			any_cast = true
	var hud = main.get_node("HudLayer/Hud")
	if any_cast:
		if hud.has_method("hide_message"):
			hud.hide_message()
		return true
	elif out_of_range:
		if hud.has_method("show_message"):
			hud.show_message("超出范围")
	else:
		if hud.has_method("show_message"):
			hud.show_message("冷却中")
	return false


func _handle_emp_cast(main, units: Array, target_pos: Vector2) -> void:
	var any_cast := false
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			if u._skill_cooldowns[8] > 0.0:
				continue
			u.activate_emp(target_pos)
			any_cast = true
	var hud = main.get_node("HudLayer/Hud")
	if any_cast:
		if hud.has_method("hide_message"):
			hud.hide_message()


func _handle_deploy_at(main, skill_idx: int, units: Array, player_team_name: String, team_minerals: Dictionary, target_pos: Vector2) -> void:
	var building_type = Building.BuildingType.SHIPYARD if skill_idx == 6 else Building.BuildingType.MINE
	var cost = GameConfig.DEPLOY_COST_SHIPYARD if skill_idx == 6 else GameConfig.DEPLOY_COST_MINE

	# 检测位置是否重叠
	if Building.is_position_blocked(target_pos):
		var hud = main.get_node("HudLayer/Hud")
		if hud.has_method("show_message"):
			hud.show_message("此处已有建筑")
		return

	var any_deploy := false
	var out_of_range := false
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	for u in units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != player_team_name:
			continue
		var team_min = team_minerals.get(u.team, 0.0)
		if team_min < cost:
			continue
		if shift_held:
			u.queue_deploy_building(building_type, cost, target_pos)
		else:
			u._command_queue.clear()
			u._command_queue.append({"type": "deploy", "building_type": building_type, "cost": cost, "pos": target_pos})
			u._try_execute_queue()
		any_deploy = true
		if not u.is_in_deploy_range(target_pos):
			out_of_range = true

	var hud = main.get_node("HudLayer/Hud")
	if any_deploy:
		if hud.has_method("hide_message"):
			hud.hide_message()
	elif out_of_range:
		if hud.has_method("show_message"):
			hud.show_message("超出范围")
	else:
		if hud.has_method("show_message"):
			hud.show_message("矿物不足")

class_name SelectionSystem
extends RefCounted

## 选择系统 — 框选、点选、双击选中同类、清除选中

const DOUBLE_CLICK_TIME: float = 0.3


## 应用框选/点选，返回 {selected_units, selected_buildings, clicked_unit, clicked_building}
func apply_selection(
	main,
	drag_start: Vector2,
	drag_end: Vector2,
	units: Array,
	buildings: Array,
	_mineral_fields: Array,
	player_team_name: String,
	last_click_time: float,
	last_clicked_unit,
	last_clicked_building,
) -> Dictionary:
	var drag_rect = _get_drag_rect(drag_start, drag_end)
	var result = {
		"selected_units": [],
		"selected_buildings": [],
		"clicked_unit": null,
		"clicked_building": null,
		"new_last_click_time": last_click_time,
		"new_last_clicked_unit": last_clicked_unit,
		"new_last_clicked_building": last_clicked_building,
		"clear_all": false,
		"deselect_building": false,
	}

	if drag_rect.size.length() < 10.0:
		var click_world = drag_start
		# ---- 点选单位 ----
		for unit in units:
			if not is_instance_valid(unit) or unit.hull <= 0:
				continue
			var size = unit.collision_shape.shape.size
			var half = size / 2
			var unit_rect = Rect2(unit.global_position - half, size)
			if unit_rect.has_point(click_world):
				var now = Time.get_ticks_msec() / 1000.0
				# 双击检测：选中所有同类单位
				if unit == last_clicked_unit and (now - last_click_time) < DOUBLE_CLICK_TIME:
					result["clear_all"] = true
					for u in units:
						if not is_instance_valid(u):
							continue
						if u.team == player_team_name and u.class_type == unit.class_type:
							u.is_selected = true
							result["selected_units"].append(u)
				else:
					# Shift+点击已选中的友军 → 反选
					if Input.is_key_pressed(KEY_SHIFT) and unit.team == player_team_name and unit in main.selected_units:
						unit.is_selected = false
					else:
						unit.is_selected = true
						result["selected_units"].append(unit)
				result["new_last_click_time"] = now
				result["new_last_clicked_unit"] = unit
				result["clicked_unit"] = unit
				return result

		# ---- 没点中单位，检查建筑 ----
		for building in buildings:
			if not is_instance_valid(building):
				continue
			var bsize = GameConfig.BUILDING_SIZE * 2
			var b_rect = Rect2(building.global_position - Vector2(bsize, bsize), Vector2(bsize * 2, bsize * 2))
			if b_rect.has_point(click_world):
				var now = Time.get_ticks_msec() / 1000.0
				# 双击建筑
				if building == last_clicked_building and (now - last_click_time) < DOUBLE_CLICK_TIME:
					result["clear_all"] = true
					for b in buildings:
						if not is_instance_valid(b) or b.hull <= 0:
							continue
						if b.team == player_team_name and b.building_type == building.building_type:
							b._is_selected = true
							b.queue_redraw()
							result["selected_buildings"].append(b)
				else:
					if Input.is_key_pressed(KEY_SHIFT):
						if building in main.selected_buildings:
							building._is_selected = false
							building.queue_redraw()
						else:
							building._is_selected = true
							building.queue_redraw()
							result["selected_buildings"].append(building)
					else:
						result["clear_all"] = true
						building._is_selected = true
						building.queue_redraw()
						result["selected_buildings"].append(building)
				result["new_last_click_time"] = now
				result["new_last_clicked_building"] = building
				result["clicked_building"] = building
				return result

		# 没点中任何东西
		result["clear_all"] = true
		result["deselect_building"] = true
		return result

	# ---- 框选 ----
	for unit in units:
		if not is_instance_valid(unit) or unit.team != player_team_name:
			continue
		if drag_rect.has_point(unit.global_position):
			if not unit.is_selected:
				unit.is_selected = true
				result["selected_units"].append(unit)

	result["clear_all"] = false
	return result


func _get_drag_rect(drag_start: Vector2, drag_end: Vector2) -> Rect2:
	return Rect2(
		Vector2(min(drag_start.x, drag_end.x), min(drag_start.y, drag_end.y)),
		Vector2(abs(drag_end.x - drag_start.x), abs(drag_end.y - drag_start.y))
	)


func find_unit_at_world(world_pos: Vector2, units: Array):
	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	return null


func find_enemy_at_world(world_pos: Vector2, units: Array, buildings: Array, player_team_name: String):
	# 检测敌方单位
	for unit in units:
		if not is_instance_valid(unit) or unit.team == player_team_name:
			continue
		if unit.hull <= 0:
			continue
		var size = unit.collision_shape.shape.size
		var half = size / 2
		var unit_rect = Rect2(unit.global_position - half, size)
		if unit_rect.has_point(world_pos):
			return unit
	# 检测敌方建筑
	for building in buildings:
		if not is_instance_valid(building) or building.team == player_team_name:
			continue
		if building.hull <= 0:
			continue
		var bsize = GameConfig.BUILDING_SIZE * 2
		var b_rect = Rect2(building.global_position - Vector2(bsize, bsize), Vector2(bsize * 2, bsize * 2))
		if b_rect.has_point(world_pos):
			return building
	return null

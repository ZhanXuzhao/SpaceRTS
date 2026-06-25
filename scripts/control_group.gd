class_name ControlGroup
extends RefCounted

## 编队系统（Ctrl+数字 编组，数字 选中/双击跳镜头）


func assign_control_group(_main, group_idx: int, selected_units: Array, selected_buildings: Array, control_groups: Array) -> void:
	_clean_control_groups(control_groups)
	var group = control_groups[group_idx]
	# 清除这些单位在旧编队中的记录
	for u in selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		for gi in range(10):
			if gi == group_idx: continue
			var old_group: Array = control_groups[gi]
			if u in old_group:
				old_group.erase(u)
				break
		u.control_group = -1
	for b in selected_buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		for gi in range(10):
			if gi == group_idx: continue
			var old_group: Array = control_groups[gi]
			if b in old_group:
				old_group.erase(b)
				break
		b.control_group = -1
	# 添加到新编队
	group.clear()
	for u in selected_units:
		if not is_instance_valid(u) or u.hull <= 0:
			continue
		group.append(u)
		u.control_group = group_idx
	for b in selected_buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		group.append(b)
		b.control_group = group_idx


func select_control_group(_main, group_idx: int, control_groups: Array) -> Dictionary:
	"""返回 {selected_units, selected_buildings}"""
	_clean_control_groups(control_groups)
	# 清除选中（由调用方做 clear_selection）
	var result = { "units": [], "buildings": [] }
	var group: Array = control_groups[group_idx]
	for item in group:
		if item is Unit and is_instance_valid(item) and item.hull > 0:
			item.is_selected = true
			result["units"].append(item)
		elif item is Building and is_instance_valid(item) and item.hull > 0:
			item._is_selected = true
			item.queue_redraw()
			result["buildings"].append(item)
	return result


func _clean_control_groups(control_groups: Array) -> void:
	if control_groups.size() < 10:
		return
	for i in range(10):
		var group: Array = control_groups[i]
		group = group.filter(func(item): return is_instance_valid(item) and (not "hull" in item or item.hull > 0))
		control_groups[i] = group

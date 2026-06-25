class_name FormationHelper
extends RefCounted

## 纯函数阵型计算工具
## 多排横队阵型：根据数量自动计算排数，满足 排长 - 排数 <= 2


## 计算最优排数，满足约束：排长(前排人数) - 排数 <= 2
## 使阵型尽量接近方形，避免过长或过深
static func _calc_row_count(unit_count: int) -> int:
	if unit_count <= 3:
		return 1
	for rows in range(2, 30):
		var front = ceil(float(unit_count) / rows)
		if front - rows <= 2:
			return rows
	return max(1, unit_count / 3)


## 计算多排横队阵型偏移量（前排大船、后排小船）
## 每排单位横向展开，排与排之间纵向错开
static func calc_v_formation_offsets(sizes: Array, forward: Vector2, spacing: float) -> Array[Vector2]:
	var right := Vector2(forward.y, -forward.x)
	var count = sizes.size()
	if count == 0:
		return []

	var rows = _calc_row_count(count)
	var cols = ceil(float(count) / rows)  # 每排最多单位数

	var offsets: Array[Vector2] = []
	offsets.resize(count)

	var idx := 0
	for row in range(rows):
		var units_in_this_row = min(cols, count - idx)
		var row_width = (units_in_this_row - 1) * spacing
		# 每排向后错开，后排间距略缩以形成梯队感
		var row_forward_offset = -forward * row * spacing

		for col in range(units_in_this_row):
			var col_offset = right * (col * spacing - row_width * 0.5)
			offsets[idx] = row_forward_offset + col_offset
			idx += 1

	return offsets


## 计算移动阵型
## 返回与 units 入参顺序一致的偏移数组
static func calc_v_formation(units: Array, target_pos: Vector2, formation_base_spacing: float) -> Array[Vector2]:
	# 筛选有效单位
	var valid: Array = []
	for u in units:
		if is_instance_valid(u) and u.hull > 0:
			valid.append(u)
	var count = valid.size()
	if count == 0:
		return []

	# 找到领队（尺寸最大的船）
	var leader = valid[0]
	for u in valid:
		if u._size_mult > leader._size_mult:
			leader = u

	# 前进方向：领队当前位置 → 目标点
	var forward: Vector2 = (target_pos - leader.global_position).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector2.RIGHT

	# 以大船尺寸决定基础间距，确保所有船都有足够间隔
	var max_size := 0.0
	for u in valid:
		max_size = max(max_size, u._size_mult)
	var spacing = formation_base_spacing * max_size

	# 按尺寸从大到小排序（大船在前排）
	var sorted = valid.duplicate()
	sorted.sort_custom(func(a, b): return a._size_mult > b._size_mult)

	# 提取尺寸数组计算偏移
	var sorted_sizes: Array[float] = []
	for u in sorted:
		sorted_sizes.append(u._size_mult)
	var sorted_offsets = calc_v_formation_offsets(sorted_sizes, forward, spacing)

	# 映射回原始入参顺序
	var unit_to_offset: Dictionary = {}
	for i in range(count):
		unit_to_offset[sorted[i]] = sorted_offsets[i]

	var result: Array[Vector2] = []
	result.resize(units.size())
	for i in range(units.size()):
		var u = units[i]
		if is_instance_valid(u) and u.hull > 0 and unit_to_offset.has(u):
			result[i] = unit_to_offset[u]
		else:
			result[i] = Vector2.ZERO
	return result

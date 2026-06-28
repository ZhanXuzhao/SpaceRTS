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


## 生成从中间向两边的列顺序索引
## 例如 5列 → [2, 1, 3, 0, 4]，4列 → [1, 2, 0, 3]
static func _center_out_column_order(col_count: int) -> Array[int]:
	var order: Array[int] = []
	var left = (col_count - 1) / 2
	var right = col_count / 2
	if left == right:
		order.append(left)
		left -= 1
		right += 1
	else:
		order.append(left)
		order.append(right)
		left -= 1
		right += 1
	while left >= 0 or right < col_count:
		if left >= 0:
			order.append(left)
			left -= 1
		if right < col_count:
			order.append(right)
			right += 1
	return order


## 计算多排横队阵型偏移量（前排小船、后排大船）
## 大船占中间列，小船依次往两边的列排开，每列一种船型
## 布局形如：S M L M S
## sizes 为各单位的 _size_mult（1/2/4/8/16），碰撞半宽 = 32 * _size_mult
static func calc_v_formation_offsets(sizes: Array, forward: Vector2, spacing: float) -> Array[Vector2]:
	var right := Vector2(forward.y, -forward.x)
	var count = sizes.size()
	if count == 0:
		return []

	var rows = _calc_row_count(count)
	var cols = ceil(float(count) / rows)

	# 将每艘船分配到 grid[row][col]
	# 大船占中间列，小船往两边列排开
	# 先按行分组（按传入顺序取），再对每行内的船按尺寸降序排列
	var grid: Array[Array] = []  # grid[row][col] = size_mult
	grid.resize(rows)
	var idx := 0
	for row in range(rows):
		var units_in_this_row = min(cols, count - idx)
		# 取出本行的 size_mult
		var row_sizes_raw: Array[float] = []
		for _j in range(units_in_this_row):
			row_sizes_raw.append(sizes[idx])
			idx += 1
		# 本行内按尺寸降序（大→小），用 _center_out_column_order 分配列
		row_sizes_raw.sort_custom(func(a, b): return a > b)
		grid[row] = []
		grid[row].resize(units_in_this_row)
		var col_order = _center_out_column_order(units_in_this_row)
		for col_in_row in range(units_in_this_row):
			grid[row][col_order[col_in_row]] = row_sizes_raw[col_in_row]

	# 计算每行相邻船之间的实际间距（碰撞半径之和 × 1.5 安全系数）
	var row_col_gaps: Array[Array] = []  # row_col_gaps[row][col_pair] = gap
	row_col_gaps.resize(rows)
	for row in range(rows):
		var row_sizes = grid[row]
		var gaps: Array[float] = []
		for c in range(row_sizes.size() - 1):
			var r1 = 32.0 * row_sizes[c]
			var r2 = 32.0 * row_sizes[c + 1]
			gaps.append((r1 + r2) * 1.5)
		row_col_gaps[row] = gaps

	# 计算行间距（基于前后两排的最大碰撞半径 × 1.5）
	var row_spacings: Array[float] = []
	row_spacings.resize(rows)
	row_spacings[0] = 0.0
	for row in range(1, rows):
		var prev_max_radius := 0.0
		var curr_max_radius := 0.0
		for s in grid[row - 1]:
			prev_max_radius = max(prev_max_radius, 32.0 * s)
		for s in grid[row]:
			curr_max_radius = max(curr_max_radius, 32.0 * s)
		row_spacings[row] = (prev_max_radius + curr_max_radius) * 1.5

	# 生成偏移量（使用实际相邻间距，不取平均，确保绝不重叠）
	var offsets: Array[Vector2] = []
	offsets.resize(count)
	idx = 0
	for row in range(rows):
		var row_sizes = grid[row]
		var units_in_this_row = row_sizes.size()
		var gaps = row_col_gaps[row]

		# 计算每列的实际 X 位置（基于累计相邻间距）
		var col_positions: Array[float] = []
		col_positions.resize(units_in_this_row)
		if units_in_this_row > 0:
			col_positions[0] = 0.0
			for c in range(1, units_in_this_row):
				col_positions[c] = col_positions[c - 1] + gaps[c - 1]
			# 居中偏移
			var total_width = col_positions[units_in_this_row - 1] - col_positions[0]
			var center_offset = total_width * 0.5
			for c in range(units_in_this_row):
				col_positions[c] -= center_offset

		# 累计向前的行偏移
		var row_forward_offset = Vector2.ZERO
		for r in range(1, row + 1):
			row_forward_offset -= forward * row_spacings[r]

		var col_order = _center_out_column_order(units_in_this_row)
		for col_in_row in range(units_in_this_row):
			var actual_col = col_order[col_in_row]
			var col_offset = right * col_positions[actual_col]
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

	# 按尺寸从小到大排序（小船在前排）
	var sorted = valid.duplicate()
	sorted.sort_custom(func(a, b): return a._size_mult < b._size_mult)

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

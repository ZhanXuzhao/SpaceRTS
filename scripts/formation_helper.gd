class_name FormationHelper
extends RefCounted

## 纯函数阵型计算工具


## 计算 V 字阵型偏移量（相对于顶点）
static func calc_v_formation_offsets(sizes: Array, forward: Vector2, spacing: float) -> Array[Vector2]:
	var right := Vector2(forward.y, -forward.x)
	var count = sizes.size()
	var offsets: Array[Vector2] = []
	offsets.append(Vector2.ZERO)  # 顶点（最大船）

	var idx := 1
	while idx < count:
		var layer := (idx + 1) * 0.5  # 第几对，从 1 开始
		var back = layer * spacing * 0.8
		var spread = layer * spacing * 1.0
		# 左翼
		offsets.append(-forward * back - right * spread)
		idx += 1
		if idx < count:
			# 右翼
			offsets.append(-forward * back + right * spread)
			idx += 1

	return offsets


## 计算移动 V 字阵型
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

	# 平均尺寸决定基础间距
	var avg_size := 0.0
	for u in valid:
		avg_size += u._size_mult
	avg_size /= count
	var spacing = formation_base_spacing * avg_size

	# 按尺寸从大到小排序
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

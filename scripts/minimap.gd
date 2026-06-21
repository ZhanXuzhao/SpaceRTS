extends Node2D

## 单位列表引用
var units: Array = []
## 相机信息
var camera_pos: Vector2 = Vector2.ZERO
var camera_zoom: Vector2 = Vector2.ONE

## 动态计算的世界范围（每帧更新）
var _world_bounds: Rect2 = Rect2(0, 0, 800, 600)

const MAP_SIZE: Vector2 = Vector2(150, 150)
const MAP_MARGIN: float = 10.0


func _draw() -> void:
	_update_bounds()

	var viewport_size = get_viewport().get_visible_rect().size
	var map_pos = Vector2(viewport_size.x - MAP_SIZE.x - MAP_MARGIN, MAP_MARGIN)
	var map_rect = Rect2(map_pos, MAP_SIZE)

	# 背景
	draw_rect(map_rect, Color(0.05, 0.05, 0.1, 0.8), true)
	draw_rect(map_rect, Color(0.4, 0.4, 0.5, 0.6), false, 1.0)

	# 绘制单位
	for unit in units:
		if not is_instance_valid(unit) or unit.health <= 0:
			continue
		var mm_pos = _world_to_minimap(unit.global_position, map_pos)
		if not map_rect.has_point(mm_pos):
			continue
		var color = Color(0.2, 0.6, 1.0) if unit.team == Unit.Team.BLUE else Color(1.0, 0.25, 0.25)
		if unit.is_selected:
			color = Color(0.2, 1.0, 0.4)
		draw_circle(mm_pos, 2.5, color)

	# 相机视野框
	var cam_rect = _get_camera_viewport_rect()
	if cam_rect:
		var mm_cam_pos = _world_to_minimap(cam_rect.position, map_pos)
		var mm_cam_size = cam_rect.size * (MAP_SIZE / _world_bounds.size)
		draw_rect(Rect2(mm_cam_pos, mm_cam_size), Color.WHITE, false, 1.0)


func _update_bounds() -> void:
	"""根据所有单位位置 + 相机视野动态计算世界范围"""
	var has_units := false
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)

	# 收集所有存活单位的位置
	for unit in units:
		if not is_instance_valid(unit) or unit.health <= 0:
			continue
		has_units = true
		min_pos = min_pos.min(unit.global_position)
		max_pos = max_pos.max(unit.global_position)

	# 加入相机视野范围
	var viewport_size = get_viewport().get_visible_rect().size
	var world_view_size = viewport_size / camera_zoom
	var cam_min = camera_pos - world_view_size / 2
	var cam_max = camera_pos + world_view_size / 2

	if has_units:
		_world_bounds.position = min_pos.min(cam_min)
		_world_bounds.size = max_pos.max(cam_max) - min_pos.min(cam_min)
	else:
		_world_bounds.position = cam_min
		_world_bounds.size = world_view_size

	# 添加 30% 边距，至少 300x300
	var padding = _world_bounds.size * 0.3 + Vector2(150, 150)
	_world_bounds.position -= padding
	_world_bounds.size += padding * 2

	# 确保最小尺寸
	if _world_bounds.size.x < 300:
		_world_bounds.size.x = 300
	if _world_bounds.size.y < 300:
		_world_bounds.size.y = 300


func _world_to_minimap(world: Vector2, map_pos: Vector2) -> Vector2:
	var ratio = MAP_SIZE / _world_bounds.size
	return map_pos + (world - _world_bounds.position) * ratio


func _get_camera_viewport_rect() -> Rect2:
	var viewport_size = get_viewport().get_visible_rect().size
	var world_view_size = viewport_size / camera_zoom
	var top_left = camera_pos - world_view_size / 2
	return Rect2(top_left, world_view_size)

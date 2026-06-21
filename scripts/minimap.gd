extends Node2D

## 单位列表引用
var units: Array = []
## 相机引用（读取 zoom 和 position）
var camera_pos: Vector2 = Vector2.ZERO
var camera_zoom: Vector2 = Vector2.ONE
## 世界范围（用于映射到小地图）
var world_bounds: Rect2 = Rect2(0, 0, 800, 600)

const MAP_SIZE: Vector2 = Vector2(150, 150)
const MAP_MARGIN: float = 10.0


func _draw() -> void:
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
		var mm_cam_size = cam_rect.size * (MAP_SIZE / world_bounds.size)
		draw_rect(Rect2(mm_cam_pos, mm_cam_size), Color.WHITE, false, 1.0)


func _world_to_minimap(world: Vector2, map_pos: Vector2) -> Vector2:
	var ratio = MAP_SIZE / world_bounds.size
	return map_pos + (world - world_bounds.position) * ratio


func _get_camera_viewport_rect() -> Rect2:
	var viewport_size = get_viewport().get_visible_rect().size
	# 视野大小 = 视口尺寸 / 缩放
	var world_view_size = viewport_size / camera_zoom
	# 视野左上角 = 相机位置 - 视野一半（相机居中于视口）
	var top_left = camera_pos - world_view_size / 2
	return Rect2(top_left, world_view_size)

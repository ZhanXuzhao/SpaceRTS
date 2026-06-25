class_name CameraHelper
extends RefCounted

## 相机系统 — 边缘滚屏、平滑缩放、镜头跟随、小地图更新、镜头定位

var main: Node2D

func _init(main_node: Node2D):
	main = main_node


## 每帧处理相机缩放、跟随、小地图更新
func process_camera(delta: float) -> void:
	# ---- 相机平滑缩放 ----
	main.camera.zoom = main.camera.zoom.lerp(Vector2(main.zoom_target, main.zoom_target), delta * 8.0)

	# ---- 镜头跟随 ----
	if main.follow_unit != null and is_instance_valid(main.follow_unit) and main.follow_unit.hull > 0:
		main.camera.position = main.camera.position.lerp(main.follow_unit.global_position, delta * 5.0)
	elif main.follow_unit != null:
		main.follow_unit = null

	# ---- 定位小地图容器（右上角）----
	var vsize = main.get_viewport().get_visible_rect().size
	main.minimap_node.position = Vector2(vsize.x - main.minimap_node.size.x - 10, 10)

	# ---- 更新小地图（每 3 帧一次）----
	if Engine.get_process_frames() % 3 == 0:
		main.minimap_node.units = main.units
		main.minimap_node.buildings = main.buildings
		main.minimap_node.mineral_fields = main.mineral_fields
		main.minimap_node.camera_pos = main.camera.global_position
		main.minimap_node.camera_zoom = main.camera.zoom
		main.minimap_node.queue_redraw()


## 边缘滚屏
func edge_scroll(delta: float) -> void:
	var viewport_size = main.get_viewport().get_visible_rect().size
	var mouse_pos = main.get_viewport().get_mouse_position()
	var edge_size := 30
	var scroll_speed: float = GameConfig.SCROLL_SPEED * delta / main.camera.zoom.x
	var scrolled := false

	if mouse_pos.x < edge_size:
		main.camera.global_position.x -= scroll_speed
		scrolled = true
	elif mouse_pos.x > viewport_size.x - edge_size:
		main.camera.global_position.x += scroll_speed
		scrolled = true

	if mouse_pos.y < edge_size:
		main.camera.global_position.y -= scroll_speed
		scrolled = true
	elif mouse_pos.y > viewport_size.y - edge_size:
		main.camera.global_position.y += scroll_speed
		scrolled = true

	if scrolled:
		main.follow_unit = null


## 缩放相机以显示所有舰队
func fit_camera_to_fleets() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in main.units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		min_pos = min_pos.min(unit.global_position)
		max_pos = max_pos.max(unit.global_position)

	var center = (min_pos + max_pos) / 2
	main.camera.position = center

	var world_size = max_pos - min_pos + Vector2(600, 600)
	var viewport_size = main.get_viewport().get_visible_rect().size
	var zoom = min(viewport_size.x / world_size.x, viewport_size.y / world_size.y)
	main.zoom_target = clamp(zoom, 0.3, 3.0)


## 镜头对准当前选中单位/建筑
func center_camera_on_selection() -> void:
	if main.selected_units.size() > 0:
		var target = main.selected_units[0]
		if is_instance_valid(target) and main.camera != null:
			main.camera.position = target.global_position
	elif main.selected_buildings.size() > 0:
		var target = main.selected_buildings[0]
		if is_instance_valid(target) and main.camera != null:
			main.camera.position = target.global_position

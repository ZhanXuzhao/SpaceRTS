extends Node2D

## 单位列表引用
var units: Array = []
## 相机信息
var camera_pos: Vector2 = Vector2.ZERO
var camera_zoom: Vector2 = Vector2.ONE
var camera_ref: Camera2D = null

## 动态计算的世界范围（每帧更新）
var _world_bounds: Rect2 = Rect2(0, 0, 800, 600)
var font: Font = null

## 小地图拖拽状态
var _dragging_minimap: bool = false


## 获取容器（父节点 ColorRect）提供的尺寸
func _get_map_size() -> Vector2:
	var p = get_parent()
	if p is ColorRect:
		return p.size
	return Vector2(150, 150)


func _input(event: InputEvent) -> void:
	var map_rect = _get_map_rect()

	# 左键按下/拖拽小地图
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if map_rect.has_point(event.position):
			if event.pressed:
				_dragging_minimap = true
				_move_camera_to_minimap(event.position)
			else:
				_dragging_minimap = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_minimap:
		_move_camera_to_minimap(event.position)
		get_viewport().set_input_as_handled()


func _move_camera_to_minimap(screen_pos: Vector2) -> void:
	if camera_ref == null:
		return
	var map_pos = _get_map_rect().position
	var world_pos = _minimap_to_world(screen_pos, map_pos)
	camera_ref.global_position = world_pos


func _get_map_rect() -> Rect2:
	var container = get_parent()
	var map_pos = container.position if container is ColorRect else Vector2.ZERO
	return Rect2(map_pos, _get_map_size())


func _draw() -> void:
	_update_bounds()

	var map_size = _get_map_size()
	var map_rect = _get_map_rect()
	var map_pos = map_rect.position

	# 背景
	draw_rect(map_rect, Color(0.05, 0.05, 0.1, 0.8), true)
	draw_rect(map_rect, Color(0.4, 0.4, 0.5, 0.6), false, 1.0)

	# 时间倍率显示（小地图左侧）
	if font == null:
		font = ThemeDB.fallback_font
	var ts = "x" + str(Engine.time_scale)
	var ts_pos = map_pos + Vector2(-64, 8)
	# 背景小块
	draw_rect(Rect2(map_pos.x - 68, map_pos.y + 4, 60, 20), Color(0.02, 0.02, 0.02, 0.6), true)
	font.draw_string(get_canvas_item(), ts_pos, ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# 绘制单位
	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
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
		var mm_cam_size = cam_rect.size * (map_size / _world_bounds.size)
		draw_rect(Rect2(mm_cam_pos, mm_cam_size), Color.WHITE, false, 1.0)


func _update_bounds() -> void:
	var has_units := false
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)

	for unit in units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		has_units = true
		min_pos = min_pos.min(unit.global_position)
		max_pos = max_pos.max(unit.global_position)

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

	var padding = _world_bounds.size * 0.3 + Vector2(150, 150)
	_world_bounds.position -= padding
	_world_bounds.size += padding * 2

	if _world_bounds.size.x < 300:
		_world_bounds.size.x = 300
	if _world_bounds.size.y < 300:
		_world_bounds.size.y = 300


func _world_to_minimap(world: Vector2, map_pos: Vector2) -> Vector2:
	var map_size = _get_map_size()
	var ratio = map_size / _world_bounds.size
	return map_pos + (world - _world_bounds.position) * ratio


func _minimap_to_world(mm_pos: Vector2, map_pos: Vector2) -> Vector2:
	var map_size = _get_map_size()
	var ratio = _world_bounds.size / map_size
	return _world_bounds.position + (mm_pos - map_pos) * ratio


func _get_camera_viewport_rect() -> Rect2:
	var viewport_size = get_viewport().get_visible_rect().size
	var world_view_size = viewport_size / camera_zoom
	var top_left = camera_pos - world_view_size / 2
	return Rect2(top_left, world_view_size)

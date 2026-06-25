class_name InputHandler
extends RefCounted

const _FormationHelper = preload("res://scripts/formation_helper.gd")

## 输入处理 — 键盘/鼠标事件分发
## 持有 main 引用，直接修改其状态

var main: Node2D

func _init(main_node: Node2D):
	main = main_node


func handle_input(event: InputEvent) -> void:
	# 游戏结束 / 暂停时的键盘操作
	if main.game_over or main.paused:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_ESCAPE:
					if main.paused and not main.game_over:
						main.overlay.resume_game()
				KEY_R:
					main.overlay.restart_game()
				KEY_Q:
					main.get_tree().quit()
		return

	# 键盘事件
	if event is InputEventKey:
		_handle_keyboard(event)
		return

	# 鼠标滚轮
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				main.zoom_target = clamp(main.zoom_target * 1.1, 0.3, 3.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				main.zoom_target = clamp(main.zoom_target / 1.1, 0.3, 3.0)

	# 拖拽中更新（鼠标移动）
	if event is InputEventMouseMotion:
		if main.is_dragging:
			main.drag_end = main._screen_to_world(event.position)
			main.queue_redraw()
		if main.orbit_is_dragging:
			main.orbit_drag_end = event.position
			main.queue_redraw()


func handle_unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	# 清除已死亡的选中单位
	main.selected_units = main.selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	# 清除已死亡的选中建筑
	main.selected_buildings = main.selected_buildings.filter(func(b): return is_instance_valid(b) and b.hull > 0)
	for b in main.selected_buildings:
		b._is_selected = true

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_left_click(event)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click_input(event)


func _handle_keyboard(event: InputEvent) -> void:
	if not event.pressed:
		return

	# F5：快速重新开始
	if event.keycode == KEY_F5:
		main.get_tree().paused = false
		main.get_tree().reload_current_scene()
		return

	# ESC 暂停
	if event.keycode == KEY_ESCAPE:
		main.paused = true
		main.get_tree().paused = true
		main.attack_cursor_mode = false
		main.overlay.show()
		main.overlay.build_menu()
		return

	# 清除已死亡的选中单位/建筑
	main.selected_units = main.selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	main.selected_buildings = main.selected_buildings.filter(func(b): return is_instance_valid(b) and b.hull > 0)

	match event.keycode:
		KEY_W:
			if not event.echo:
				if main.selected_units.size() > 0:
					main.orbit_cursor_mode = not main.orbit_cursor_mode
				else:
					main.orbit_cursor_mode = false
				main.attack_cursor_mode = false
				main.queue_redraw()
		KEY_A:
			if event.ctrl_pressed and not event.echo:
				_clear_selection()
				for unit in main.units:
					if not is_instance_valid(unit):
						continue
					if unit.team == main.player_team_name and unit.hull > 0 \
							and unit.class_type != Unit.ShipClass.MINER:
						unit.is_selected = true
						main.selected_units.append(unit)
				main.attack_cursor_mode = false
				main.orbit_cursor_mode = false
				main.queue_redraw()
			elif not event.echo:
				main.attack_cursor_mode = not main.attack_cursor_mode
				main.orbit_cursor_mode = false
				main.queue_redraw()
		KEY_H:
			if not event.echo:
				main._center_camera_on_selection()
				main.follow_unit = null
		KEY_F:
			if not event.echo:
				if main.selected_units.size() > 0:
					main.follow_unit = main.selected_units[0]
					main.camera.position = main.follow_unit.global_position
				else:
					main.follow_unit = null
		KEY_T:
			if not event.echo:
				var unit_types := {}
				var building_types := {}
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						unit_types[u.class_type] = true
				for b in main.selected_buildings:
					if is_instance_valid(b) and b.hull > 0:
						building_types[b.building_type] = true
				if unit_types.size() > 0 or building_types.size() > 0:
					_clear_selection()
					for u in main.units:
						if not is_instance_valid(u) or u.hull <= 0:
							continue
						if u.team == main.player_team_name and unit_types.has(u.class_type):
							u.is_selected = true
							main.selected_units.append(u)
					for b in main.buildings:
						if not is_instance_valid(b) or b.hull <= 0:
							continue
						if b.team == main.player_team_name and building_types.has(b.building_type):
							b._is_selected = true
							b.queue_redraw()
							main.selected_buildings.append(b)
				main.attack_cursor_mode = false
				main.orbit_cursor_mode = false
				main.queue_redraw()
		KEY_G:
			if not event.echo:
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.attack_mode = ((u.attack_mode + 1) % 3) as Unit.AttackMode
				main.queue_redraw()
		KEY_Z:
			if not event.echo:
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(0)
		KEY_X:
			if not event.echo:
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(1)
		KEY_C:
			if not event.echo:
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(2)
		KEY_V:
			if not event.echo and main.selected_units.size() > 0:
				main._enter_skill_targeting_mode(3, main.selected_units)
		KEY_B:
			if not event.echo and main.selected_units.size() > 0:
				main._enter_skill_targeting_mode(4, main.selected_units)
		KEY_N:
			if not event.echo:
				for u in main.selected_units:
					if is_instance_valid(u) and u.hull > 0:
						u.activate_skill(5)
		KEY_M:
			if not event.echo and main.selected_units.size() > 0:
				main._enter_skill_targeting_mode(6, main.selected_units)
		KEY_K:
			if not event.echo and main.selected_units.size() > 0:
				main._enter_skill_targeting_mode(7, main.selected_units)
		KEY_MINUS:
			if not event.echo:
				main.game_speed *= 0.5
				Engine.time_scale = main.game_speed
		KEY_EQUAL:
			if not event.echo:
				main.game_speed *= 2.0
				Engine.time_scale = main.game_speed

	# Ctrl+数字：编队
	if event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		main._control_group.assign_control_group(
			main, event.keycode - KEY_0,
			main.selected_units, main.selected_buildings,
			main.control_groups
		)
	# 单独数字：选中编队 / 双击跳镜头
	elif not event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		var group_idx = event.keycode - KEY_0
		var now = Time.get_ticks_msec() / 1000.0
		if group_idx == main.last_number_key and (now - main.last_number_time) < 0.3:
			var g: Array = main.control_groups[group_idx]
			if g.size() > 0:
				var first = g[0]
				if is_instance_valid(first):
					main.camera.position = first.global_position
		else:
			_clear_selection()
			var result = main._control_group.select_control_group(
				main, group_idx, main.control_groups
			)
			main.selected_units = result["units"]
			main.selected_buildings = result["buildings"]
		main.last_number_key = group_idx
		main.last_number_time = now


func _handle_left_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		if main.skill_targeting_mode >= 0:
			var handled = main._skill_targeting.handle_skill_targeting_click(
				main, event.position,
				main.skill_targeting_mode, main.skill_targeting_units,
				main.units, main.player_team_name, main.team_minerals
			)
			if handled:
				main._exit_skill_targeting_mode()
			return
		if main.orbit_cursor_mode:
			main.orbit_drag_start = event.position
			main.orbit_drag_end = event.position
			main.orbit_is_dragging = true
		elif main.attack_cursor_mode:
			_handle_attack_click(event.position)
			main.attack_cursor_mode = false
			main.queue_redraw()
		else:
			main.is_dragging = true
			main.drag_start = main._screen_to_world(event.position)
			main.drag_end = main.drag_start
			if not Input.is_key_pressed(KEY_SHIFT):
				_clear_selection()
	else:
		if main.is_dragging:
			main.is_dragging = false
			_apply_selection()
			main.queue_redraw()
		if main.orbit_is_dragging:
			main.orbit_is_dragging = false
			main.orbit_cursor_mode = false
			var start_world = main._screen_to_world(main.orbit_drag_start)
			var end_world = main._screen_to_world(event.position)
			var radius = start_world.distance_to(end_world)
			if radius < 10.0:
				_handle_orbit_click(main.orbit_drag_start, -1.0)
			else:
				_handle_orbit_click(main.orbit_drag_start, radius)
			main.queue_redraw()


func _handle_right_click_input(event: InputEventMouseButton) -> void:
	if main.skill_targeting_mode >= 0:
		main._exit_skill_targeting_mode()
		return
	if event.pressed:
		main.orbit_cursor_mode = false
		main.attack_cursor_mode = false
		# 选中建筑时右键 → 设置集结点
		if main.selected_units.size() == 0 and main.selected_buildings.size() > 0:
			var b = main.selected_buildings[0]
			if is_instance_valid(b) and b.building_type == Building.BuildingType.SHIPYARD:
				var world_pos = main._screen_to_world(event.position)
				var hit_mineral = false
				for field in main.mineral_fields:
					if not is_instance_valid(field):
						continue
					if field.global_position.distance_to(world_pos) < 60.0:
						hit_mineral = true
						break
				if hit_mineral:
					b.miner_rally_point = world_pos
					b.has_miner_rally_point = true
				else:
					b.rally_point = world_pos
					b.has_rally_point = true
				b.queue_redraw()
			return
		if main.selected_units.size() > 0:
			_handle_right_click(event.position)


func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = main._screen_to_world(screen_pos)
	main.selected_units = main.selected_units.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	for u in main.selected_units:
		if not is_instance_valid(u) or u.hull <= 0 or u.team != main.player_team_name:
			return
	var enemy = main._selection_system.find_enemy_at_world(
		world_pos, main.units, main.buildings, main.player_team_name
	)
	var shift_held = Input.is_key_pressed(KEY_SHIFT)

	# 多单位移动时计算阵型偏移
	var formation_offsets: Array[Vector2] = []
	var _formation_forward_rot: float = INF
	if main.selected_units.size() > 1 and enemy == null:
		formation_offsets = _FormationHelper.calc_v_formation(
			main.selected_units, world_pos, GameConfig.FORMATION_BASE_SPACING
		)
		var leader: Unit = main.selected_units[0]
		for u in main.selected_units:
			if u._size_mult > leader._size_mult:
				leader = u
		_formation_forward_rot = (world_pos - leader.global_position).angle()

	for i in range(main.selected_units.size()):
		var unit = main.selected_units[i]
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			if shift_held:
				unit.queue_attack_target(enemy)
			else:
				unit.attack_target(enemy)
		else:
			var target_pos = world_pos
			if i < formation_offsets.size():
				target_pos = world_pos + formation_offsets[i]
			if shift_held:
				unit.queue_move_to(target_pos, _formation_forward_rot)
			else:
				unit.move_to(target_pos, _formation_forward_rot)


func _handle_attack_click(screen_pos: Vector2) -> void:
	var world_pos = main._screen_to_world(screen_pos)
	var enemy = main._selection_system.find_enemy_at_world(
		world_pos, main.units, main.buildings, main.player_team_name
	)
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	for unit in main.selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if enemy != null:
			if shift_held:
				unit.queue_attack_target(enemy)
			else:
				unit.attack_target(enemy)
		else:
			var viewport_size = main.get_viewport().get_visible_rect().size
			var world_radius = viewport_size.length() / main.camera.zoom.x / 2
			unit.attack_area(world_pos, world_radius)


func _handle_orbit_click(screen_pos: Vector2, custom_radius: float = -1.0) -> void:
	var world_pos = main._screen_to_world(screen_pos)
	var target = main._selection_system.find_unit_at_world(world_pos, main.units)
	for unit in main.selected_units:
		if not is_instance_valid(unit) or unit.hull <= 0:
			continue
		if unit == target:
			continue
		if target != null:
			unit.orbit_target(target, custom_radius)
		else:
			unit.orbit_position(world_pos, custom_radius)


func _clear_selection() -> void:
	for unit in main.selected_units:
		unit.is_selected = false
	main.selected_units.clear()
	for b in main.selected_buildings:
		if is_instance_valid(b):
			b._is_selected = false
			b.queue_redraw()
	main.selected_buildings.clear()
	var hud = main.get_node("HudLayer/Hud")
	if is_instance_valid(hud) and hud.has_method("set_selected_building"):
		hud.set_selected_building(null)


func _apply_selection() -> void:
	var result = main._selection_system.apply_selection(
		main,
		main.drag_start, main.drag_end,
		main.units, main.buildings, main.mineral_fields,
		main.player_team_name,
		main.last_click_time, main.last_clicked_unit, main.last_clicked_building,
	)

	# 应用结果
	if result["clear_all"]:
		_clear_selection()

	for u in result["selected_units"]:
		if u not in main.selected_units:
			main.selected_units.append(u)

	for b in result["selected_buildings"]:
		if b not in main.selected_buildings:
			main.selected_buildings.append(b)

	main.last_click_time = result["new_last_click_time"]
	if result["clicked_unit"] != null:
		main.last_clicked_unit = result["clicked_unit"]
	if result["clicked_building"] != null:
		main.last_clicked_building = result["clicked_building"]

	if result["deselect_building"]:
		main.selected_buildings.clear()
		main.last_clicked_building = null
		var hud = main.get_node("HudLayer/Hud")
		if hud.has_method("set_selected_building"):
			hud.set_selected_building(null)
	elif result["clicked_building"] != null:
		var hud2 = main.get_node("HudLayer/Hud")
		if hud2.has_method("set_selected_building"):
			hud2.set_selected_building(
				result["clicked_building"] if main.selected_buildings.size() == 1 else null
			)

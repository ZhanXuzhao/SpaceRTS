class_name SpawnSystem
extends RefCounted

const _FormationHelper = preload("res://scripts/formation_helper.gd")

## 生成系统 — 舰队、建筑、矿物、单位创建

var main: Node2D

func _init(main_node: Node2D):
	main = main_node

# ----- 阵营名随机生成 -----
const _FACTION_NAME_PREFIX := ["星辉","暗影","极光","深渊","苍穹","烈焰","冰霜","雷霆","风暴","铁血","神威","天罚","银河","曙光","永恒","混沌","星云","猩红"]
const _FACTION_NAME_SUFFIX := ["军团","舰队","联盟","帝国","联邦","集团","议会","王国","战盟"]

# 配置值 → ShipClass 映射
const VAL_TO_CLASS := {
	1: Unit.ShipClass.FRIGATE,
	2: Unit.ShipClass.DESTROYER,
	3: Unit.ShipClass.CRUISER,
	4: Unit.ShipClass.BATTLESHIP,
}
const ALL_SHIPS := [
	Unit.ShipClass.FRIGATE,
	Unit.ShipClass.DESTROYER,
	Unit.ShipClass.CRUISER,
	Unit.ShipClass.BATTLESHIP,
]


static func _generate_faction_name() -> String:
	return _FACTION_NAME_PREFIX[randi() % _FACTION_NAME_PREFIX.size()] \
		+ _FACTION_NAME_SUFFIX[randi() % _FACTION_NAME_SUFFIX.size()]


## 主入口：初始化所有单位/建筑/矿场
func spawn_all() -> void:
	if main.unit_scene == null:
		push_error("请将 unit.tscn 拖入 Main 节点的 Unit Scene 属性！")
		return

	Unit.reset_name_pool()
	Unit.team_scores.clear()
	Unit.reset_weapon_stats()

	# 根据 GameConfig.faction_config 动态生成阵营（正多边形布局）
	var count = mini(GameConfig.faction_config.size(), 999)
	main.faction_team_names.resize(count)
	main.faction_team_colors.resize(count)
	for i in range(count):
		main.faction_team_names[i] = _generate_faction_name()
		main.faction_team_colors[i] = main.TEAM_COLOR_PALETTE[i % main.TEAM_COLOR_PALETTE.size()]
	main.player_team_name = main.faction_team_names[0]
	Unit.player_team_name = main.player_team_name
	Unit.team_color_map.clear()
	for i in range(count):
		Unit.team_color_map[main.faction_team_names[i]] = main.faction_team_colors[i]

	var R = main.SIDE_LENGTH / (2.0 * sin(PI / count))
	var start_angle = -PI / 2.0
	for i in range(count):
		var team_name = main.faction_team_names[i]
		var config: Array = GameConfig.faction_config[i]
		var angle = start_angle + i * TAU / count
		var pos = main.POLYGON_CENTER + Vector2(cos(angle), sin(angle)) * R
		var forward_dir = (main.POLYGON_CENTER - pos).normalized()

		# 建筑和矿物
		var field_dir = -forward_dir
		_spawn_buildings(team_name, pos, field_dir)
		_spawn_mineral_fields(pos, field_dir)

		_spawn_fleet(team_name, pos.x, config, pos.y, forward_dir)

		# 初始采矿船
		_spawn_start_miner(team_name, pos, field_dir)

	# 初始化各阵营矿物储量
	for tname in main.faction_team_names:
		main.team_minerals[tname] = GameConfig.INITIAL_MINERALS

	# 镜头对准玩家舰队
	_camera_to_player_fleet()


## 将配置字典解析为 ShipClass 列表，按尺寸降序排列
func _parse_fleet_config(config: Array) -> Array[Unit.ShipClass]:
	## config = [随机数, 护卫舰数, 驱逐舰数, 巡洋舰数, 战列舰数]
	var result: Array[Unit.ShipClass] = []
	for _j in range(config[0]):
		result.append(ALL_SHIPS[randi() % ALL_SHIPS.size()])
	for i in range(1, min(config.size(), 5)):
		var count: int = config[i]
		var sc: Unit.ShipClass = VAL_TO_CLASS[i]
		for _j in range(count):
			result.append(sc)
	result.sort_custom(func(a, b): return Unit._ship_class_tier(a) > Unit._ship_class_tier(b))
	return result


func _spawn_fleet(team: String, center_x: int, config: Array, center_y: float = 500.0, forward_dir: Vector2 = Vector2.RIGHT) -> void:
	var color = Color.WHITE
	for i in main.faction_team_names.size():
		if main.faction_team_names[i] == team:
			color = main.faction_team_colors[i]
			break

	var ship_classes = _parse_fleet_config(config)
	if ship_classes.size() == 0:
		return

	var sizes: Array[float] = []
	for sc in ship_classes:
		sizes.append(pow(1.5, Unit._ship_class_tier(sc)))
	var max_size := 0.0
	for s in sizes:
		max_size = max(max_size, s)

	var forward = forward_dir
	var spacing = GameConfig.FORMATION_BASE_SPACING * max_size
	var offsets = _FormationHelper.calc_v_formation_offsets(sizes, forward, spacing)
	var v_rotation = forward.angle()

	var center_pos = Vector2(center_x, center_y)
	for i in range(ship_classes.size()):
		var unit = _create_unit(team, ship_classes[i], color)
		unit.position = center_pos + offsets[i]
		unit._body.rotation = v_rotation


func _spawn_buildings(team_name: String, base_pos: Vector2, back_dir: Vector2) -> void:
	if main.building_scene == null:
		return

	var color = Color.WHITE
	for i in main.faction_team_names.size():
		if main.faction_team_names[i] == team_name:
			color = main.faction_team_colors[i]
			break

	# 矿场
	var mine_pos = base_pos + back_dir * 400
	var mine = main.building_scene.instantiate()
	mine.building_type = Building.BuildingType.MINE
	mine.team = team_name
	mine.building_color = color
	mine.global_position = mine_pos
	mine.mineral_deposited.connect(main._on_mineral_deposited)
	main.add_child(mine)
	main.buildings.append(mine)

	# 船坞
	var yard_pos = mine_pos + back_dir.rotated(deg_to_rad(90)) * 200
	var yard = main.building_scene.instantiate()
	yard.building_type = Building.BuildingType.SHIPYARD
	yard.team = team_name
	yard.building_color = color
	yard.global_position = yard_pos
	yard.ship_produced.connect(main._on_ship_produced)
	main.add_child(yard)
	main.buildings.append(yard)


func _spawn_mineral_fields(base_pos: Vector2, back_dir: Vector2) -> void:
	if main.mineral_field_scene == null:
		return

	for j in range(GameConfig.MINERAL_FIELD_COUNT):
		var offset_angle = (j - 1) * deg_to_rad(40)
		var spread_dir = back_dir.rotated(offset_angle)
		var field_pos = base_pos + back_dir * 700 + spread_dir * 200
		var field = main.mineral_field_scene.instantiate()
		field.global_position = field_pos
		field.team = ""
		main.add_child(field)
		main.mineral_fields.append(field)
		field.add_to_group("mineral_fields")
		field.field_depleted.connect(main._on_field_depleted)


func _spawn_start_miner(team_name: String, _base_pos: Vector2, back_dir: Vector2) -> void:
	if main.unit_scene == null:
		return

	var color = Color.WHITE
	for i in main.faction_team_names.size():
		if main.faction_team_names[i] == team_name:
			color = main.faction_team_colors[i]
			break

	var home_mine = null
	for b in main.buildings:
		if b.team == team_name and b.building_type == Building.BuildingType.MINE:
			home_mine = b
			break
	if home_mine == null:
		return

	var spawn_pos = home_mine.global_position + back_dir.rotated(deg_to_rad(-60)) * 120
	var unit: Unit = main.unit_scene.instantiate()
	unit.class_type = Unit.ShipClass.MINER
	unit.team = team_name
	unit.unit_color = color
	unit.all_units = main.units
	main.add_child(unit)
	unit.global_position = spawn_pos
	main.units.append(unit)
	unit.set_as_miner(home_mine)


func _create_unit(team: String, class_type: Unit.ShipClass, unit_color: Color) -> Unit:
	var unit: Unit = main.unit_scene.instantiate()
	unit.class_type = class_type
	unit.team = team
	unit.unit_color = unit_color
	unit.all_units = main.units
	main.add_child(unit)
	main.units.append(unit)

	var class_idx := Unit._ship_class_tier(class_type)
	var configs: Array = GameConfig.WEAPON_CONFIGS.get(class_idx, [[-1]])
	var config: Array = configs[randi() % configs.size()]
	var loadout: Array = []
	var pairs := unit.slot_count >> 1
	for pair_idx in pairs:
		var wt: int = config[pair_idx] if pair_idx < config.size() else GameConfig.WT_RANDOM
		var w := Weapon.create_by_type(wt)
		loadout.append(w)
		if loadout.size() < unit.slot_count:
			loadout.append(w)

	for i in range(unit.slot_count):
		unit._slot_weapons[i] = loadout[i]
	unit.refresh_weapon_visuals()

	return unit


func _camera_to_player_fleet() -> void:
	var cam_target := Vector2.ZERO
	var player_count := 0
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in main.units:
		if is_instance_valid(unit) and unit.hull > 0 and unit.team == main.player_team_name:
			cam_target += unit.global_position
			player_count += 1
			min_pos = min_pos.min(unit.global_position)
			max_pos = max_pos.max(unit.global_position)
	if player_count > 0:
		cam_target /= player_count
		main.camera.position = cam_target
		var viewport_w = main.get_viewport().get_visible_rect().size.x
		var fleet_w = max_pos.x - min_pos.x + 200.0
		main.zoom_target = clamp(viewport_w * 0.5 / fleet_w, 0.3, 3.0) if fleet_w > 0 else 1.0
		main.camera.zoom = Vector2(main.zoom_target, main.zoom_target)
		main.follow_unit = null


## 单位部署建筑（由 unit._deploy_building 调用）
func spawn_deploy_building(team_name: String, building_type: int, position: Vector2) -> void:
	if main.building_scene == null:
		return

	var color = Color.WHITE
	for i in main.faction_team_names.size():
		if main.faction_team_names[i] == team_name:
			color = main.faction_team_colors[i]
			break

	var building = main.building_scene.instantiate()
	building.building_type = building_type
	building.team = team_name
	building.building_color = color
	building.global_position = position
	building.mineral_deposited.connect(main._on_mineral_deposited)
	building.ship_produced.connect(main._on_ship_produced)
	building.start_deploy(GameConfig.DEPLOY_DURATION)
	main.add_child(building)
	main.buildings.append(building)


## 生产船只
func on_ship_produced(team_name: String, ship_type, building) -> void:
	if main.unit_scene == null:
		return

	var sc: Unit.ShipClass
	var is_miner := false
	if ship_type is Unit.ShipClass and ship_type == Unit.ShipClass.MINER:
		is_miner = true
		sc = Unit.ShipClass.MINER
	elif ship_type is Unit.ShipClass:
		sc = ship_type
	else:
		return

	var color = Color.WHITE
	for i in main.faction_team_names.size():
		if main.faction_team_names[i] == team_name:
			color = main.faction_team_colors[i]
			break

	var spawn_pos = building.global_position + Vector2(150, 0).rotated(randf() * TAU)
	var unit: Unit = main.unit_scene.instantiate()
	unit.class_type = sc
	unit.team = team_name
	unit.unit_color = color
	unit.all_units = main.units
	main.add_child(unit)
	unit.global_position = spawn_pos
	main.units.append(unit)

	if is_miner:
		var home_mine = null
		for b in main.buildings:
			if b.team == team_name and b.building_type == Building.BuildingType.MINE:
				home_mine = b
				break
		if home_mine != null:
			unit.set_as_miner(home_mine)
		if building.has_miner_rally_point:
			unit.move_to(building.miner_rally_point)
	else:
		var class_idx = Unit._ship_class_tier(sc)
		var configs: Array = GameConfig.WEAPON_CONFIGS.get(class_idx, [[-1]])
		var config: Array = configs[randi() % configs.size()]
		var loadout: Array = []
		var pairs = unit.slot_count >> 1
		for pair_idx in pairs:
			var wt: int = config[pair_idx] if pair_idx < config.size() else GameConfig.WT_RANDOM
			var w := Weapon.create_by_type(wt)
			loadout.append(w)
			if loadout.size() < unit.slot_count:
				loadout.append(w)
		for i in range(unit.slot_count):
			unit._slot_weapons[i] = loadout[i]
		unit.refresh_weapon_visuals()
		if building.has_rally_point:
			unit.move_to(building.rally_point)

class_name Unit
extends Area2D

enum Team { BLUE, RED }
enum ShipClass { DRONE, FRIGATE, DESTROYER, CRUISER, BATTLESHIP }
enum AttackMode { FREE_FIRE, KEEP_DISTANCE, ORBIT_SHOOT }

const CFG = preload("res://scripts/game_config.gd")

@export var class_type: ShipClass = ShipClass.DRONE
@export var speed: float = CFG.UNIT_MAX_SPEED
@export var acceleration: float = CFG.UNIT_ACCELERATION
@export var mass: float = CFG.UNIT_MASS
@export var forward_acceleration: float = CFG.UNIT_FORWARD_ACCELERATION
@export var max_angular_speed: float = CFG.UNIT_MAX_ANGULAR_SPEED
@export var angular_acceleration: float = CFG.UNIT_ANGULAR_ACCELERATION
var velocity: Vector2
## 飞船朝向角（弧度），上=0，右=PI/2
var _facing_angle: float = 0.0
var _angular_vel: float = 0.0
## 飞船等级 (0=无人机, 1=护卫舰, ..., 4=战列舰)
var _tier: int = 0
## 武器伤害倍率 (×1.2^_tier)
var _weapon_damage_mult: float = 1.0
## 武器射程倍率 (×1.5^_tier)
var _weapon_range_mult: float = 1.0
## 控制组编号（-1 = 未编组）
var control_group: int = -1

# ----- 技能系统 -----
var _skill_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]  # 加速/攻速/减伤/跃迁
var _speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _damage_taken_mult: float = 1.0
var _slow_mult: float = 1.0
var _slow_timer: float = 0.0
var _skill_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
const SKILL_CD: float = 12.0
const SKILL_DURATION: float = 10.0

# ----- 激光脉冲（攻击3s / 冷却2s，无人机~战列舰攻击时长+0~40%）-----
var _laser_cycle_timer: float = 0.0  # 初始立即攻击
var _laser_attack_duration: float = CFG.LASER_ATTACK_DURATION  # 在 _ready 中根据船型计算

## 尺寸倍率 (×1.5^_tier)
var _size_mult: float = 1.0
## 缩放后的槽位偏移
var _slot_offsets_scaled: Array[Vector2] = []
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE

# ----- 护盾 & 结构 -----
@export var max_shield: float = CFG.UNIT_MAX_SHIELD
@export var max_hull: float = CFG.UNIT_MAX_HULL
@export var shield_regen_rate: float = CFG.UNIT_SHIELD_REGEN

var shield: float
var hull: float
var _shield_regen_delay: float = 0.0

@export var slot_count: int = CFG.UNIT_SLOT_COUNT

## 是否被选中
var is_selected: bool = false : set = _set_is_selected

var _all_units: Array[Unit] = []
var _attack_mode: AttackMode = AttackMode.FREE_FIRE

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

# ----- 武器槽位 -----
var _slot_weapons: Array = []
var _slot_angles: Array[float] = []
var _slot_cooldowns: Array[float] = []

const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(0, -40),     # 0: 上
	Vector2(28, -28),    # 1: 右上
	Vector2(40, 0),      # 2: 右
	Vector2(28, 28),     # 3: 右下
	Vector2(0, 40),      # 4: 下
	Vector2(-28, 28),    # 5: 左下
	Vector2(-40, 0),     # 6: 左
	Vector2(-28, -28),   # 7: 左上
]

# ----- 攻击指令相关 -----
var _explicit_attack_target: Unit = null
var _attack_move_destination: Vector2
var _is_attack_move: bool = false
## 区域攻击（A+空地点地）
var _is_area_attack: bool = false
var _area_center: Vector2
var _area_radius: float = 500.0
var _saved_move_target: Vector2
var _has_saved_move: bool = false

# PD 持续弹道
var _pd_target_pos: Vector2
var _pd_has_target: bool = false

# ----- 环绕 -----
var _is_orbit: bool = false
var _orbit_target_unit: Unit = null
var _orbit_position: Vector2 = Vector2.ZERO  # 地面环绕目标点
var _orbit_angle: float = 0.0
## 环绕方向：1 = 逆时针，-1 = 顺时针（由切入位置确定）
var _orbit_direction: float = 1.0
var _orbit_radius: float = -1.0  # >=0 时覆盖默认半径

# ----- 无人机仓（战列舰专属）-----
var _drone_bay: int = 10
var _home_battleship: Unit = null  # 无人机所属母舰
var _deployed_drones: Array[Unit] = []
var _max_deployed_drones: int = 4
var _drone_launch_timer: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	# ---- 根据飞船等级计算属性 ----
	_tier = _ship_class_tier(class_type)
	_size_mult = pow(1.5, _tier)
	_weapon_damage_mult = pow(1.2, _tier)
	_laser_attack_duration = CFG.LASER_ATTACK_DURATION * (1.0 + _tier * CFG.LASER_CLASS_BONUS)
	_weapon_range_mult = pow(1.5, _tier)
	# 根据船型设置默认攻击模式
	match class_type:
		ShipClass.DRONE, ShipClass.FRIGATE:
			_attack_mode = AttackMode.ORBIT_SHOOT
		ShipClass.DESTROYER:
			_attack_mode = AttackMode.KEEP_DISTANCE
		_:
			_attack_mode = AttackMode.FREE_FIRE

	slot_count = int(pow(2, _tier))
	speed = CFG.UNIT_MAX_SPEED * pow(0.8, _tier)
	max_shield = CFG.UNIT_MAX_SHIELD * pow(1.5, _tier)
	max_hull = CFG.UNIT_MAX_HULL * pow(1.5, _tier)
	shield_regen_rate = CFG.UNIT_SHIELD_REGEN * pow(1.5, _tier)

	shield = max_shield
	hull = max_hull
	_sprite.self_modulate = unit_color

	# ---- 尺寸缩放 ----
	_sprite.scale = Vector2(_size_mult, _size_mult)
	var shape = RectangleShape2D.new()
	shape.size = Vector2(64, 64) * _size_mult
	collision_shape.shape = shape

	# ---- 缩放槽位偏移 ----
	_slot_offsets_scaled.resize(slot_count)
	for i in range(slot_count):
		if i < SLOT_OFFSETS.size():
			_slot_offsets_scaled[i] = SLOT_OFFSETS[i] * _size_mult
		else:
			# 超出 8 个基本位置的槽位，按圆周均匀分布
			var angle = (i - SLOT_OFFSETS.size()) * TAU / (slot_count - SLOT_OFFSETS.size())
			var radius = 50.0 * _size_mult
			_slot_offsets_scaled[i] = Vector2(cos(angle), sin(angle)) * radius

	# ---- 初始化武器槽位 ----
	_slot_weapons.resize(slot_count)
	_slot_angles.resize(slot_count)
	_slot_cooldowns.resize(slot_count)
	for i in range(slot_count):
		_slot_weapons[i] = null
		_slot_angles[i] = 0.0
		_slot_cooldowns[i] = 0.0


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_skill_timers(delta)
	_update_shield(delta)
	_update_target()
	_update_turrets(delta)
	_update_combat(delta)
	_update_chase()
	_update_pd(delta)
	_update_orbit(delta)
	_update_drones(delta)
	_update_movement(delta)
	queue_redraw()


func _update_cooldowns(delta: float) -> void:
	var cd_rate = delta * _attack_speed_mult
	for i in range(slot_count):
		_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - cd_rate)
	for i in range(4):
		_skill_cooldowns[i] = max(0.0, _skill_cooldowns[i] - delta)


func _update_skill_timers(delta: float) -> void:
	for i in range(4):
		if _skill_timers[i] > 0:
			_skill_timers[i] -= delta
			if _skill_timers[i] <= 0:
				match i:
					0: _speed_mult = 1.0
					1: _attack_speed_mult = 1.0
					2: _damage_taken_mult = 1.0


func _update_slow(delta: float) -> void:
	if _slow_timer > 0:
		_slow_timer -= delta
		if _slow_timer <= 0:
			_slow_mult = 1.0


func _update_shield(delta: float) -> void:
	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)


func _update_target() -> void:
	# 无人机辅助母舰攻击
	if _home_battleship != null and _current_target == null:
		if is_instance_valid(_home_battleship) and is_instance_valid(_home_battleship._current_target) and _home_battleship._current_target.hull > 0:
			_current_target = _home_battleship._current_target
			_is_orbit = false
	# 无人机无目标时返回母舰
	if _home_battleship != null and _current_target == null and not _is_moving and not _is_orbit:
		orbit_target(_home_battleship)
		return
	# 清理无效的明确攻击目标
	if is_instance_valid(_explicit_attack_target) and _explicit_attack_target.hull <= 0:
		_explicit_attack_target = null

	# 清理无效的当前目标
	if is_instance_valid(_current_target) and _current_target.hull <= 0:
		_current_target = null

	# 目标获取（由外部控制器下发，这里只处理显式指令）
	if _current_target == null:
		if _explicit_attack_target != null:
			_current_target = _explicit_attack_target
		elif _is_attack_move:
			_current_target = _find_nearest_enemy()
		elif _is_area_attack:
			_current_target = _find_nearest_enemy_in_area()


func _update_turrets(delta: float) -> void:
	if _current_target != null:
		for i in range(slot_count):
			if _slot_weapons[i] != null:
				var fire_pos = global_position + _slot_offsets_scaled[i]
				var to_target = _current_target.global_position - fire_pos
				var target_angle = to_target.angle()
				var turn_speed = _slot_weapons[i].turn_speed
				_slot_angles[i] = _rotate_toward(_slot_angles[i], target_angle, turn_speed * delta)
	else:
		# 无目标时炮塔缓慢回正
		for i in range(slot_count):
			if _slot_weapons[i] != null:
				_slot_angles[i] = _rotate_toward(_slot_angles[i], 0.0, 90.0 * delta)


func _update_combat(delta: float) -> void:
	# 保持距离模式：持续调整到最佳射程
	if _attack_mode == AttackMode.KEEP_DISTANCE and is_instance_valid(_current_target) and _current_target.hull > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		var optimal = _get_max_range() * 0.7
		var target_dist = optimal * 0.9
		var dir = (_current_target.global_position - global_position).normalized()
		if dist > optimal:
			_target_position = _current_target.global_position - dir * target_dist
			_is_moving = true
		elif dist < optimal * 0.8:
			_target_position = _current_target.global_position - dir * target_dist
			_is_moving = true
	# 激光脉冲周期
	_laser_cycle_timer -= delta
	var laser_on = _laser_cycle_timer > 0
	if _laser_cycle_timer <= -CFG.LASER_COOLDOWN_DURATION:
		_laser_cycle_timer = _laser_attack_duration  # 冷却结束，开始攻击
	elif _laser_cycle_timer <= 0 and _laser_cycle_timer > -CFG.LASER_COOLDOWN_DURATION:
		pass  # 冷却中

	var max_range = _get_max_range()
	if _current_target != null and max_range > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= max_range:
			for i in range(slot_count):
				var w = _slot_weapons[i]
				if w == null:
					continue
				# 激光武器受脉冲周期控制
				if w.weapon_type == Weapon.WeaponType.LASER and not laser_on:
					continue
				if dist <= w.range * _weapon_range_mult and _slot_cooldowns[i] <= 0.0:
					_fire_slot(i, _current_target)
					# 激光攻速固定 3次/秒，其他武器用各自冷却
					if w.weapon_type == Weapon.WeaponType.LASER:
						_slot_cooldowns[i] = 1.0 / CFG.LASER_HITS_PER_SECOND
					else:
						_slot_cooldowns[i] = w.cooldown


func _update_chase() -> void:
	var approach_range = _get_approach_range()
	# 环绕射击模式：仅首次调用
	if _attack_mode == AttackMode.ORBIT_SHOOT and _current_target != null and is_instance_valid(_current_target) and _current_target.hull > 0 and _current_target.team != team:
		if not _is_orbit or _orbit_target_unit != _current_target:
			orbit_target(_current_target)
		return
	if _current_target != null and approach_range > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		if dist <= approach_range and _explicit_attack_target != null:
			_is_moving = false
		elif dist > approach_range:
			var should_chase := false
			if _explicit_attack_target != null:
				should_chase = true
			elif _is_attack_move:
				should_chase = true
			elif not _is_moving:
				should_chase = true

			if should_chase:
				var to_target = _current_target.global_position - global_position
				var dir = to_target.normalized()
				_target_position = _current_target.global_position - dir * approach_range * 0.85
				_is_moving = true
			if not should_chase and is_instance_valid(_current_target):
				if dist > approach_range * 1.2:
					_current_target = null
	elif _current_target == null:
		if _has_saved_move:
			_target_position = _saved_move_target
			_is_moving = true
			_has_saved_move = false


func _update_pd(delta: float) -> void:
	# 找到最近的敌方弹体用于显示光束
	_pd_has_target = false
	var nearest_pd_range := 0.0
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w != null and w.weapon_type == Weapon.WeaponType.PD:
			nearest_pd_range = max(nearest_pd_range, w.range)
	if nearest_pd_range > 0:
		var proj = _find_nearest_enemy_missile(nearest_pd_range)
		if proj != null:
			_pd_has_target = true
			_pd_target_pos = proj.global_position

	# 每个 PD 槽位独立开火
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w == null or w.weapon_type != Weapon.WeaponType.PD:
			continue
		if _slot_cooldowns[i] > 0.0:
			continue
		var proj = _find_nearest_enemy_missile(w.range)
		if proj != null:
			_slot_cooldowns[i] = w.cooldown
			proj.take_damage(w.damage)


func _update_orbit(delta: float) -> void:
	if _is_orbit:
		# 每帧记录目标位置，死亡时自动转为环绕死亡地点
		if is_instance_valid(_orbit_target_unit):
			_orbit_position = _orbit_target_unit.global_position
			if _orbit_target_unit.hull <= 0:
				_orbit_target_unit = null

		var center: Vector2
		if _orbit_target_unit != null and is_instance_valid(_orbit_target_unit):
			center = _orbit_target_unit.global_position
		else:
			center = _orbit_position
		var dist = _orbit_radius if _orbit_radius > 0 else _get_approach_range() * 0.85
		if dist < 50:
			dist = 500.0  # 只有 PD 时默认 500
		var angular_speed = rad_to_deg(speed / dist)
		_orbit_angle += delta * angular_speed * _orbit_direction
		var rad = deg_to_rad(_orbit_angle)
		_target_position = center + Vector2(cos(rad), sin(rad)) * dist
		_is_moving = true
		queue_redraw()
	elif _is_orbit:
		_is_orbit = false


func _update_drones(delta: float) -> void:
	if class_type != ShipClass.BATTLESHIP or _drone_bay <= 0:
		return
	# 清理已死无人机
	_deployed_drones = _deployed_drones.filter(func(u): return is_instance_valid(u) and u.hull > 0)
	# 发射新无人机
	if _deployed_drones.size() < _max_deployed_drones:
		_drone_launch_timer -= delta
		if _drone_launch_timer <= 0:
			_launch_drone()
			_drone_launch_timer = 0.5


func _launch_drone() -> void:
	var drone_scene = load("res://scenes/unit.tscn")
	var d: Unit = drone_scene.instantiate()
	d.class_type = ShipClass.DRONE
	d.team = team
	d.unit_color = unit_color
	d._all_units = _all_units
	# 从母舰前方弹出
	var spawn_dir = Vector2.RIGHT.rotated(_sprite.rotation)
	d.global_position = global_position + spawn_dir * 50.0 * _size_mult
	get_parent().add_child(d)
	_all_units.append(d)
	# 随机分配武器
	for i in range(d.slot_count):
		d._slot_weapons[i] = Weapon.create_random()
	# 环绕母舰
	d.orbit_target(self, CFG.DRONE_ORBIT_RADIUS)
	d._home_battleship = self
	_deployed_drones.append(d)
	_drone_bay -= 1


func _update_movement(delta: float) -> void:
	if not _is_moving:
		return
	_move_toward_target(delta)

	if _is_attack_move and _current_target == null:
		if global_position.distance_to(_attack_move_destination) < 4.0:
			_is_attack_move = false
			_is_moving = false
	elif not _is_attack_move and _current_target == null:
		if global_position.distance_to(_target_position) < 4.0:
			_is_moving = false

static func _ship_class_tier(sc: ShipClass) -> int:
	match sc:
		ShipClass.DRONE: return 0
		ShipClass.FRIGATE: return 1
		ShipClass.DESTROYER: return 2
		ShipClass.CRUISER: return 3
		ShipClass.BATTLESHIP: return 4
	return 0


func _get_max_range() -> float:
	var max_r := 0.0
	for w in _slot_weapons:
		if w != null:
			max_r = max(max_r, w.range * _weapon_range_mult)
	return max_r


func _get_approach_range() -> float:
	var min_r := INF
	for w in _slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.range * _weapon_range_mult)
	return min_r if min_r < INF else 0.0

func _rotate_toward(current: float, target: float, max_delta: float) -> float:
	"""按最大步长旋转 current 角度到 target 角度（弧度）"""
	var diff = fmod(target - current + PI, TAU) - PI
	if abs(diff) < 0.001:
		return target
	var step = clamp(abs(diff), -max_delta, max_delta) * sign(diff)
	return current + step


func _fire_slot(slot_index: int, target: Unit) -> void:
	var w = _slot_weapons[slot_index]
	if w == null or target.team == team:
		return  # 不攻击友军

	var slot_offset = _slot_offsets_scaled[slot_index]
	var fire_pos = global_position + slot_offset
	var fire_dir = Vector2.RIGHT.rotated(_slot_angles[slot_index])

	match w.weapon_type:
		Weapon.WeaponType.LASER:
			target.take_damage(w.damage, self)

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			_spawn_projectile(fire_pos, fire_dir, target, w)


func _spawn_projectile(from_pos: Vector2, direction: Vector2, target: Unit, w: Weapon) -> void:
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.global_position = from_pos

	# 弹体生命值（PD可消耗）
	var proj_hp := 0.0
	if w.weapon_type == Weapon.WeaponType.BULLET:
		proj_hp = CFG.BULLET_HP
	elif w.weapon_type == Weapon.WeaponType.MISSILE:
		proj_hp = CFG.MISSILE_HP

	# 寿命 = 有效射程 / 弹体速度（确保子弹能飞到最大射程）
	var effective_range = w.range * _weapon_range_mult
	var lifetime = effective_range / max(w.projectile_speed, 1.0) * 1.1

	proj.setup({
		"max_speed": w.projectile_speed,
		"acceleration": CFG.BULLET_ACCELERATION,
		"damage": w.damage,
		"direction": direction,
		"target": target,
		"team": team,
		"source": self,
		"is_homing": w.is_homing,
		"color": w.projectile_color,
		"size": w.projectile_size,
		"hp": proj_hp,
		"lifetime": lifetime,
	})
	get_parent().add_child(proj)


func _move_toward_target(delta: float) -> void:
	var distance = global_position.distance_to(_target_position)
	if distance < 4.0:
		_is_moving = false
		return

	var direction = (_target_position - global_position).normalized()
	var desired_velocity = direction * speed * _speed_mult

	var separation = Vector2.ZERO
	const SEPARATION_RADIUS: float = 80.0
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		var to_other = global_position - other.global_position
		var dist = to_other.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			separation += to_other.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS

	var effective_speed = speed * _speed_mult * _slow_mult
	var velocity = desired_velocity + separation * speed * 1.5
	if velocity.length() > effective_speed:
		velocity = velocity.normalized() * effective_speed

	if velocity.length() > 0.0:
		_sprite.rotation = velocity.angle()

	global_position += velocity * delta


func _find_nearest_enemy_in_area() -> Unit:
	var nearest: Unit = null
	var nearest_dist = _area_radius
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = other.global_position.distance_to(_area_center)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func _find_nearest_enemy_in_range() -> Unit:
	var nearest: Unit = null
	var nearest_dist = _get_max_range()
	if nearest_dist <= 0:
		return null
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func find_nearest_enemy() -> Unit:
	"""公开接口：被外部控制器调用"""
	return _find_nearest_enemy()


func _find_nearest_enemy() -> Unit:
	var nearest: Unit = null
	var nearest_dist = INF
	for other in _all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func _find_nearest_enemy_missile(search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist = search_range
	for proj in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj):
			continue
		if proj.team == team:
			continue
		if not proj.is_homing:
			continue
		var dist = global_position.distance_to(proj.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = proj
	return nearest


func _find_nearest_enemy_projectile(search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist = search_range
	for proj in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj):
			continue
		if proj.team == team:
			continue
		var dist = global_position.distance_to(proj.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = proj
	return nearest


func activate_skill(slot: int) -> void:
	if _skill_cooldowns[slot] > 0:
		return
	_skill_cooldowns[slot] = SKILL_CD if slot != 3 else 3.0
	match slot:
		0:
			_speed_mult = 2.0
			_skill_timers[0] = SKILL_DURATION
		1:
			_attack_speed_mult = 2.0
			_skill_timers[1] = SKILL_DURATION
		2:
			_damage_taken_mult = 0.5
			_skill_timers[2] = SKILL_DURATION
		3:
			if class_type == ShipClass.BATTLESHIP:
				var dir = Vector2.RIGHT.rotated(_sprite.rotation)
				global_position += dir * 2000.0


func take_damage(amount: float, attacker: Unit = null) -> void:
	amount *= _damage_taken_mult
	# 护盾先吸收伤害
	if shield > 0.0:
		var absorbed = min(shield, amount)
		shield -= absorbed
		amount -= absorbed
	# 剩余伤害由结构承受
	if amount > 0.0:
		hull -= amount

	# 护盾恢复延迟
	_shield_regen_delay = CFG.UNIT_SHIELD_DELAY

	# 受击反击：任何单位被攻击后都会还手
	if attacker != null:
		if is_instance_valid(attacker) and attacker.hull > 0 and attacker.team != team:
			if _current_target == null:
				if _is_moving and not _is_attack_move:
					_saved_move_target = _target_position
					_has_saved_move = true
				_current_target = attacker
				_explicit_attack_target = null
				_is_attack_move = false

	if hull <= 0:
		_die()


func _die() -> void:
	_all_units.erase(self)
	queue_free()


func move_to(target: Vector2) -> void:
	_target_position = target
	_is_moving = true
	_current_target = null
	_explicit_attack_target = null
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_has_saved_move = false


func attack_target(target: Unit) -> void:
	_current_target = target
	_explicit_attack_target = target
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_has_saved_move = false
	_target_position = target.global_position


func attack_move_to(destination: Vector2) -> void:
	_target_position = destination
	_attack_move_destination = destination
	_is_attack_move = true
	_is_area_attack = false
	_is_orbit = false
	_is_moving = true
	_explicit_attack_target = null
	_has_saved_move = false
	_current_target = _find_nearest_enemy()


func attack_area(center: Vector2, radius: float) -> void:
	_area_center = center
	_area_radius = radius
	_is_area_attack = true
	_is_moving = false
	_is_attack_move = false
	_is_orbit = false
	_explicit_attack_target = null
	_has_saved_move = false
	_current_target = _find_nearest_enemy_in_area()


func orbit_position(pos: Vector2, custom_radius: float = -1.0) -> void:
	_orbit_target_unit = null
	_orbit_position = pos
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_is_attack_move = false
	# 初始角度由当前位置决定
	var diff = global_position - pos
	_orbit_angle = rad_to_deg(atan2(diff.y, diff.x))
	_orbit_direction = 1 if diff.cross(Vector2.RIGHT) > 0 else -1


func orbit_target(target: Unit, custom_radius: float = -1.0) -> void:
	_orbit_target_unit = target
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_has_saved_move = false
	# 初始角度设为单位当前位置相对于目标的方向，避免先靠近再远离
	var from_target = global_position - target.global_position
	_orbit_angle = rad_to_deg(from_target.angle())
	# 方向由切入位置决定
	_orbit_direction = 1.0 if from_target.x >= 0.0 else -1.0
	_current_target = target


func stop() -> void:
	_is_moving = false


func _set_is_selected(value: bool) -> void:
	is_selected = value
	_sprite.self_modulate = Color(0.5, 0.7, 1.0) if value else unit_color
	queue_redraw()


func _draw() -> void:
	# ---- 尾焰 ----
	var flame_len := 6.0
	var flame_color := Color(1.0, 0.6, 0.1, 0.6)
	if _speed_mult > 1.0:
		flame_len = 24.0
		flame_color = Color(1.0, 0.9, 0.3, 0.9)
	elif _is_moving:
		flame_len = 14.0
		flame_color = Color(1.0, 0.5, 0.1, 0.7)
	if flame_len > 0:
		var back = Vector2.LEFT.rotated(_sprite.rotation) * 8.0 * _size_mult
		var tip = back + Vector2.LEFT.rotated(_sprite.rotation) * flame_len * _size_mult
		var spread = Vector2.UP.rotated(_sprite.rotation) * 3.0 * _size_mult
		var pts = PackedVector2Array([back + spread, back - spread, tip])
		draw_colored_polygon(pts, flame_color)

	# ---- 环绕轨迹（仅选中时绘制） ---- 
	if _is_orbit and is_selected:
		var center: Vector2
		if is_instance_valid(_orbit_target_unit) and _orbit_target_unit.hull > 0:
			center = _orbit_target_unit.global_position - global_position
		else:
			center = _orbit_position - global_position
		var radius = _orbit_radius if _orbit_radius > 0 else _get_approach_range() * 0.85
		if radius < 50: radius = 50
		var trail_color = Color(0.2, 1.0, 0.5, 0.25)
		var segments = 48
		for i in range(segments):
			var a1 = deg_to_rad(i * 360.0 / segments)
			var a2 = deg_to_rad((i + 1) * 360.0 / segments)
			var p1 = center + Vector2(cos(a1), sin(a1)) * radius
			var p2 = center + Vector2(cos(a2), sin(a2)) * radius
			draw_line(p1, p2, trail_color, 1.5)
		# 方向指示箭头
		var arrow_angle = deg_to_rad(_orbit_angle)
		var arrow_pos = center + Vector2(cos(arrow_angle), sin(arrow_angle)) * radius
		draw_circle(arrow_pos, 3.0, Color(0.2, 1.0, 0.5, 0.5))
		# 指向目标中心的连线
		draw_line(Vector2.ZERO, center, Color(0.2, 1.0, 0.5, 0.1), 1.0)

	# ---- 绘制武器 ----
	for i in range(slot_count):
		var w = _slot_weapons[i]
		if w == null:
			continue
		var offset = _slot_offsets_scaled[i]
		var angle = _slot_angles[i]
		_draw_weapon(w, offset, angle)

	# 激光持续射线（有目标且在激光射程内时一直显示）
	if is_instance_valid(_current_target):
		var has_laser := false
		for w in _slot_weapons:
			if w != null and w.weapon_type == Weapon.WeaponType.LASER:
				has_laser = true
				break
		if has_laser and _laser_cycle_timer > 0:
			var dist = global_position.distance_to(_current_target.global_position)
			var laser_range = 0.0
			for w in _slot_weapons:
				if w != null and w.weapon_type == Weapon.WeaponType.LASER:
					laser_range = w.range * _weapon_range_mult
					break
			if dist <= laser_range:
				var end = _current_target.global_position - global_position
				var lc1: Color
				var lc2: Color
				var lc3: Color
				if team == Team.BLUE:
					lc1 = Color(0.15, 0.3, 1.0, 0.25)
					lc2 = Color(0.2, 0.4, 1.0, 0.7)
					lc3 = Color(0.6, 0.8, 1.0, 0.4)
				else:
					lc1 = Color(1.0, 0.15, 0.15, 0.25)
					lc2 = Color(1.0, 0.2, 0.2, 0.7)
					lc3 = Color(1.0, 0.7, 0.7, 0.4)
				# 外层光晕
				draw_line(Vector2.ZERO, end, lc1, 18.0)
				# 主光束
				draw_line(Vector2.ZERO, end, lc2, 6.0)
				# 核心亮线
				draw_line(Vector2.ZERO, end, lc3, 2.4)

	# PD 持续弹道（有目标时一直显示）
	if _pd_has_target:
		var end = _pd_target_pos - global_position
		# 外层光晕
		draw_line(Vector2.ZERO, end, Color(0.15, 0.8, 0.5, 0.25), 5.0)
		# 主光束
		draw_line(Vector2.ZERO, end, Color(0.2, 1.0, 0.7, 0.6), 2.0)
		# 核心亮线
		draw_line(Vector2.ZERO, end, Color(0.5, 1.0, 0.8, 0.4), 0.8)

	# ---- 护盾条 & 结构条 ---- 
	var bar_width = 64.0 * _size_mult
	var bar_half = bar_width / 2.0
	var bar_top = -collision_shape.shape.size.y * 0.6  # 选中框顶部 = -size×1.2/2

	# 护盾条（蓝色，上方）
	if shield < max_shield:
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width, 4.0), Color(0.15, 0.15, 0.2, 0.8), true)
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width * shield / max_shield, 4.0), Color(0.2, 0.5, 1.0, 0.9), true)

	# 结构条（绿色→黄色→红色）
	if hull < max_hull:
		draw_rect(Rect2(-bar_half, bar_top - 28.0, bar_width, 5.0), Color(0.15, 0.15, 0.2, 0.8), true)
		var hull_pct = hull / max_hull
		var hull_color: Color
		if hull_pct > 0.5:
			hull_color = Color(0.2, 1.0, 0.3)
		elif hull_pct > 0.25:
			hull_color = Color(1.0, 0.8, 0.2)
		else:
			hull_color = Color(1.0, 0.2, 0.2)
		draw_rect(Rect2(-bar_half, bar_top - 28.0, bar_width * hull_pct, 5.0), hull_color, true)

	# ---- 编队号（在血条左侧） ----
	if control_group >= 0:
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), Vector2(-bar_half - 22, bar_top - 34 + 8), str(control_group),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.6))

	# 选中标记
	if is_selected:
		var sel_size = collision_shape.shape.size * 1.2
		var sel_half = sel_size / 2
		var sel_rect = Rect2(-sel_half.x, -sel_half.y, sel_size.x, sel_size.y)
		draw_rect(sel_rect, Color(0.2, 1.0, 0.4, 0.6), false, 2.0 * _size_mult)
		var corner_len = 10 * _size_mult
		var d = 38 * _size_mult
		draw_line(Vector2(-d, -d + corner_len), Vector2(-d, -d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(-d, -d), Vector2(-d + corner_len, -d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(d, -d + corner_len), Vector2(d, -d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(d, -d), Vector2(d - corner_len, -d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(-d, d - corner_len), Vector2(-d, d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(-d, d), Vector2(-d + corner_len, d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(d, d - corner_len), Vector2(d, d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)
		draw_line(Vector2(d, d), Vector2(d - corner_len, d), Color(0.2, 1.0, 0.4), 2.0 * _size_mult)


func _draw_weapon(w: Weapon, offset: Vector2, angle: float) -> void:
	"""在指定偏移和角度绘制武器外观"""
	var barrel_len: float
	var barrel_width: float
	var color: Color

	match w.weapon_type:
		Weapon.WeaponType.BULLET:
			barrel_len = 16.0
			barrel_width = 5.0
			color = Color(0.5, 0.5, 0.3)
		Weapon.WeaponType.MISSILE:
			barrel_len = 24.0
			barrel_width = 10.0
			color = Color(0.6, 0.25, 0.1)
		Weapon.WeaponType.LASER:
			barrel_len = 14.0
			barrel_width = 4.0
			color = Color(0.7, 0.1, 0.1)
		Weapon.WeaponType.PD:
			barrel_len = 8.0
			barrel_width = 3.0
			color = Color(0.1, 0.8, 0.5)

	# 底座
	draw_circle(offset, barrel_width * 0.7, color.darkened(0.3))

	# 炮管（从底座向外延伸）
	var tip = offset + Vector2.RIGHT.rotated(angle) * barrel_len
	var half_w = Vector2.UP.rotated(angle) * barrel_width * 0.5
	var pts = PackedVector2Array([
		offset + half_w,
		offset - half_w,
		tip - half_w * 0.5,
		tip + half_w * 0.5,
	])
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([offset + half_w, offset - half_w, tip - half_w * 0.5, tip + half_w * 0.5]),
		Color.BLACK, 1.0, true)

	# 激光武器加发光点
	if w.weapon_type == Weapon.WeaponType.LASER:
		draw_circle(tip, 2.0, Color(1.0, 0.3, 0.3, 0.7))

class_name Unit
extends Area2D

## 阵营用字符串标识，第一个阵营为玩家，其余为AI
## 通过 Unit.player_team_name 获取玩家阵营名
static var player_team_name: String = ""
## 阵营名 → 颜色映射（由 main 在生成时填充）
static var team_color_map: Dictionary = {}

enum ShipClass { DRONE, FRIGATE, DESTROYER, CRUISER, BATTLESHIP, MINER }
enum AttackMode { FREE_FIRE, KEEP_DISTANCE, ORBIT_SHOOT }

const UNIT_MOVEMENT = preload("res://scripts/unit_movement.gd")

@export var class_type: ShipClass = ShipClass.DRONE
## 最大速度 px/s
@export var speed: float = GameConfig.UNIT_MAX_SPEED
## 质量（由尺寸³决定）
@export var mass: float = GameConfig.DRONE_BASE_MASS
## 推力（由质量×加速度反推）
@export var thrust: float = 0.0
## 转向速度 °/s
@export var max_angular_speed: float = GameConfig.DRONE_TURN_SPEED
## 角加速度 °/s²
@export var angular_acceleration: float = GameConfig.DRONE_TURN_SPEED * 2.0
var velocity: Vector2
## 飞船等级 (0=无人机, 1=护卫舰, ..., 4=战列舰)
var _tier: int = 0
## 武器伤害倍率 (×1.2^_tier)
var _weapon_damage_mult: float = 1.0
## 武器射程倍率 (×1.5^_tier)
var _weapon_range_mult: float = 1.0
## 控制组号（-1 = 未编组）
var control_group: int = -1

# ----- 技能系统 -----
var _skill_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # 加速/速射/减伤/跃迁/减速/净化/部署船厂/部署矿厂
## 技能自动释放标记，默认减速自动
var _skill_auto: Array[bool] = [false, false, false, false, true, false, false, false] :
	set = _set_skill_auto
var _speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _damage_taken_mult: float = 1.0
var _slow_mult: float = 1.0
## 对敌方施加 debuff，支持叠加
var _slow_debuffs: Array[Dictionary] = []  # 每项: {"factor": float, "timer": float}
var _skill_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 减益免疫计时
var _debuff_immunity_timer: float = 0.0
## 自上次受伤以来经过的时间（秒），用于 AI 判断是否脱离战斗
var _last_damage_timer: float = 0.0

# ----- 战绩 -----
var kill_count: int = 0
var threat_level: int = 0

## 阵营总积分（击杀无人机~战列舰分别加 1~5 分），static 跨 Unit 实例共享
static var team_scores: Dictionary = {}  # Team → int
## 阵营损失积分（被击毁的飞船分值累计），用于计算效率
static var team_losses: Dictionary = {}  # Team → int

## 武器 DPS 统计
## team_weapon_damage[team][weapon_type] = 总伤害
static var team_weapon_damage: Dictionary = {}  # Team → {WeaponType: float}
## team_weapon_lifetime[team][weapon_type] = 总存活秒数
static var team_weapon_lifetime: Dictionary = {}  # Team → {WeaponType: float}

# ----- 激光系统（攻击3s / 冷却2s，无人机~战列舰时长+0~40%）-----
var _laser_cycle_timer: float = 0.0  # 初始倒计时
var _laser_attack_duration: float = GameConfig.LASER_ATTACK_DURATION  # 在 _ready 中根据船型计算

## 尺寸倍数 (×1.5^_tier)
var _size_mult: float = 1.0
## 缩放后的插槽偏移
var _slot_offsets_scaled: Array[Vector2] = []
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
## 阵营名称字符串
var team: String = ""

# ----- 护盾 & 结构 -----
@export var max_shield: float = GameConfig.UNIT_MAX_SHIELD
@export var max_hull: float = GameConfig.UNIT_MAX_HULL
@export var shield_regen_rate: float = GameConfig.UNIT_SHIELD_REGEN

var shield: float
var hull: float
var _shield_regen_delay: float = 0.0

@export var slot_count: int = GameConfig.UNIT_SLOT_COUNT

## 飞船名字，初始化时自动生成
var unit_name: String

## 飞船类型中文名
var class_name_cn: String

## 是否选中
var is_selected: bool = false : set = _set_is_selected

var all_units: Array[Unit] = []
var attack_mode: AttackMode = AttackMode.FREE_FIRE :
	set(value):
		if attack_mode != value:
			# 离开 ORBIT_SHOOT 模式时立即停止环绕
			if attack_mode == AttackMode.ORBIT_SHOOT:
				_is_orbit = false
				_orbit_target_unit = null
			# 离开 KEEP_DISTANCE 模式时清除移动状态，让新模式接管
			if attack_mode == AttackMode.KEEP_DISTANCE:
				_is_moving = false
		attack_mode = value

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Node = null
## 到达目标点后的朝向（弧度），INF=不设置
var _arrival_rotation: float = INF

# ----- 统一指令队列（Shift+右键连续操作，混合移动/攻击）-----
var _command_queue: Array[Dictionary] = []

# ----- 武器插槽 -----
var _slot_weapons: Array = []
var _slot_angles: Array[float] = []
var _slot_cooldowns: Array[float] = []
var _weapon_sprites: Array[Sprite2D] = []

const SLOT_OFFSETS: Array[Vector2] = [
	# 飞船插槽布局，上侧为-Y，下侧为+Y
	Vector2(25, -35),    # 0: 前上1
	Vector2(25, 35),     # 1: 前下1
	Vector2(10, -40),    # 2: 前上2
	Vector2(10, 40),     # 3: 前下2
	Vector2(-5, -40),    # 4: 后上1
	Vector2(-5, 40),     # 5: 后下1
	Vector2(-20, -35),   # 6: 后上2
	Vector2(-20, 35),    # 7: 后下2
	Vector2(32, -20),    # 8: 前上3
	Vector2(32, 20),     # 9: 前下3
	Vector2(-32, -20),   # 10: 后上3
	Vector2(-32, 20),    # 11: 后下3
	Vector2(-10, -25),   # 12: 后上4
	Vector2(-10, 25),    # 13: 后下4
	Vector2(0, -30),     # 14: 中上
	Vector2(0, 30),      # 15: 中下
]

# ----- 显式攻击指令 -----
var _explicit_attack_target: Node = null
var attack_move_destination: Vector2
var _is_attack_move: bool = false
## 攻击移动（A+点地触发）
var _is_area_attack: bool = false
var _area_center: Vector2
var _area_radius: float = 500.0
var saved_move_target: Vector2
var has_saved_move: bool = false


# PD 拦截系统
var _pd_target_pos: Vector2
var _pd_has_target: bool = false

# ----- 脏标记（优化重绘用）-----
var _redraw_dirty: bool = true

# ----- 环绕 -----
var _is_orbit: bool = false
var _orbit_target_unit: Node = null
var _orbit_position: Vector2 = Vector2.ZERO  # 相对环绕目标
var _orbit_angle: float = 0.0
## 轨道方向 1 = 逆时针，-1 = 顺时针（根据初始位置确定）
var _orbit_direction: float = 1.0
var _orbit_radius: float = -1.0  # >=0 时覆盖默认半径

# ----- 无人机舱（战列舰专用）-----
var drone_bay: int = 10
var home_battleship: Unit = null  # 无人机归属母舰
var deployed_drones: Array[Unit] = []
var max_deployed_drones: int = 4
var drone_launch_timer: float = 0.0

# ----- 采矿系统 -----
enum MinerState { IDLE, MOVING_TO_FIELD, MINING, RETURNING_TO_MINE, DEPOSITING }
var _miner_state: int = MinerState.IDLE
var _is_miner: bool = false
var _mining_target_field = null
var _home_mine = null
var _miner_cargo: float = 0.0
var _miner_cargo_capacity: float = GameConfig.MINER_CARGO_CAPACITY
var _miner_mine_timer: float = 0.0



@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _body: Node2D = $Body

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	print("DEBUG: Unit._ready loaded", self, self.get_script())
	# 优化物理层：Unit 在 layer 1（供弹体检测），只检测弹体 layer 2
	collision_mask = 2
	# ---- 根据飞船等级计算属性 ----
	_tier = _ship_class_tier(class_type)
	_size_mult = pow(1.5, _tier)
	_weapon_damage_mult = pow(1.2, _tier)
	_laser_attack_duration = GameConfig.LASER_ATTACK_DURATION * (1.0 + _tier * GameConfig.LASER_CLASS_BONUS)
	_weapon_range_mult = pow(1.5, _tier)
	# 根据船型设置默认攻击模式
	match class_type:
		ShipClass.MINER:
			attack_mode = AttackMode.FREE_FIRE
		ShipClass.DRONE, ShipClass.FRIGATE:
			attack_mode = AttackMode.ORBIT_SHOOT
		ShipClass.DESTROYER:
			attack_mode = AttackMode.KEEP_DISTANCE
		_:
			attack_mode = AttackMode.FREE_FIRE

		# 插槽数量：采矿船0 无人机2 护卫舰2 驱逐4 巡洋6 战列舰8
	match class_type:
		ShipClass.MINER:
			slot_count = 0
		ShipClass.DRONE:
			slot_count = 2
		ShipClass.CRUISER:
			slot_count = 6
		ShipClass.BATTLESHIP:
			slot_count = 8
		_:
			slot_count = int(pow(2, _tier))
	# ---- 根据尺寸计算质量（质量 ∝ 尺寸³）----
	mass = GameConfig.DRONE_BASE_MASS * pow(_size_mult, 3)
	# ---- 最大速度（越大越慢）----
	speed = GameConfig.UNIT_MAX_SPEED * pow(0.8, _tier)
	# ---- 加速时间（尺寸越大加速越慢）----
	var accel_time = GameConfig.DRONE_ACCEL_TIME * _size_mult
	# ---- 推力 = 质量 × 加速度（加速度 = 最大速度 / 加速时间）----
	thrust = mass * speed / accel_time
	# ---- 转向速度（越大越慢）----
	max_angular_speed = GameConfig.DRONE_TURN_SPEED / _size_mult
	angular_acceleration = max_angular_speed * 2.0

	max_shield = GameConfig.UNIT_MAX_SHIELD * pow(1.5, _tier)
	max_hull = GameConfig.UNIT_MAX_HULL * pow(1.5, _tier)
	shield_regen_rate = GameConfig.UNIT_SHIELD_REGEN * pow(1.5, _tier)

	shield = max_shield
	hull = max_hull
	_sprite.self_modulate = unit_color

	# ---- 自动生成名称 ----
	class_name_cn = _get_class_name_cn()
	unit_name = _generate_ship_name()

	# ---- 尺寸缩放 ----
	_sprite.scale = Vector2(_size_mult, _size_mult)
	var shape = RectangleShape2D.new()
	shape.size = Vector2(64, 64) * _size_mult
	collision_shape.shape = shape

	# ---- 缩放插槽偏移 ----
	_slot_offsets_scaled.resize(slot_count)
	for i in range(slot_count):
		if i < SLOT_OFFSETS.size():
			_slot_offsets_scaled[i] = SLOT_OFFSETS[i] * _size_mult
		else:
			# 超出 8 个插槽位置的插槽沿圆周均匀分布
			var angle = (i - SLOT_OFFSETS.size()) * TAU / (slot_count - SLOT_OFFSETS.size())
			var radius = 50.0 * _size_mult
			_slot_offsets_scaled[i] = Vector2(cos(angle), sin(angle)) * radius

	# ---- 初始化武器插槽 ----
	_slot_weapons.resize(slot_count)
	_slot_angles.resize(slot_count)
	_slot_cooldowns.resize(slot_count)
	for i in range(slot_count):
		_slot_weapons[i] = null
		_slot_angles[i] = 0.0
		_slot_cooldowns[i] = 0.0
		_create_weapon_sprite(i)


func mark_dirty() -> void:
	_redraw_dirty = true


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_skill_timers(delta)
	_update_shield(delta)

	# ---- 自动释放标记为自动的技能（所有队伍统一处理）----
	_update_auto_skills()

	# ---- 根据攻击模式做战术决策（所有队伍统一处理）----
	_update_tactical()

	# ---- 执行层（不含任何 AI 决策）----
	UnitCombat.update_turrets(self, delta)
	UnitCombat.update_weapons(self, delta)
	UnitCombat.update_pd(self, delta)
	_update_chase_execution()
	_update_orbit(delta)
	# ---- 武器存活时间统计（DPS 计算用，每秒更新一次）----
	if Engine.get_process_frames() % 60 == 0:
		_update_weapon_lifetime(delta * 60.0)
	# ---- 采矿系统（仅采矿船）----
	_update_mining(delta)
	UNIT_MOVEMENT.update_drones(self, delta)
	UNIT_MOVEMENT.update_movement(self, delta)

	# ---- 待部署：停止后检查队首是否为部署指令 ----
	if not _is_moving and not _is_orbit and _command_queue.size() > 0 and _command_queue[0].type == "deploy":
		_advance_command_queue()

	# 仅当脏标记或有目标/PD时触发重绘（确保冷却时能清除激光残影）
	if _redraw_dirty:
		_redraw_dirty = false
		queue_redraw()
	elif is_instance_valid(_current_target):
		# 有目标时每帧重绘：_draw 内部根据 _laser_cycle_timer 控制激光显示/隐藏
		queue_redraw()
	elif _pd_has_target:
		# PD拦截光线每帧需更新位置
		queue_redraw()


func _update_cooldowns(delta: float) -> void:
	var cd_rate = delta * _attack_speed_mult
	for i in range(slot_count):
		_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - cd_rate)
	for i in range(8):
		_skill_cooldowns[i] = max(0.0, _skill_cooldowns[i] - delta)


func _update_skill_timers(delta: float) -> void:
	for i in range(8):
		if _skill_timers[i] > 0:
			_skill_timers[i] -= delta
			if _skill_timers[i] <= 0:
				match i:
					0: _speed_mult = 1.0
					1: _attack_speed_mult = 1.0
					2: _damage_taken_mult = 1.0
					3: _speed_mult = 1.0; _attack_speed_mult = 1.0
					4: _slow_mult = 1.0
	# 敌方施加的 debuff 叠加计时
	var i := 0
	while i < _slow_debuffs.size():
		_slow_debuffs[i]["timer"] -= delta
		if _slow_debuffs[i]["timer"] <= 0:
			_slow_debuffs.remove_at(i)
		else:
			i += 1
	# 减益免疫计时
	if _debuff_immunity_timer > 0:
		_debuff_immunity_timer -= delta


func _update_weapon_lifetime(delta: float) -> void:
	for w in _slot_weapons:
		if w != null:
			var team_dict = team_weapon_lifetime.get(team, {})
			team_dict[w.weapon_type] = team_dict.get(w.weapon_type, 0.0) + delta
			team_weapon_lifetime[team] = team_dict


func _update_shield(delta: float) -> void:
	# 跟踪自上次受伤的时间
	_last_damage_timer += delta

	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)


## 自动释放标记为自动的技能
func _update_auto_skills() -> void:
	# 技能 0：加速 — 有目标时自动开启
	if _skill_auto[0] and _skill_cooldowns[0] <= 0 and _skill_timers[0] <= 0:
		if _current_target != null:
			activate_skill(0)

	# 技能 1：速射 — 有目标时自动开启
	if _skill_auto[1] and _skill_cooldowns[1] <= 0 and _skill_timers[1] <= 0:
		if _current_target != null:
			activate_skill(1)

	# 技能 2：减伤 — 有目标或血量低于 50% 时自动开启
	if _skill_auto[2] and _skill_cooldowns[2] <= 0 and _skill_timers[2] <= 0:
		if _current_target != null or hull < max_hull * 0.5:
			activate_skill(2)

	# 技能 3：跃迁 — 目标过远时自动跃迁接近
	if _skill_auto[3] and _skill_cooldowns[3] <= 0:
		if _current_target != null:
			var dist = global_position.distance_to(_current_target.global_position)
			var approach = _get_approach_range()
			if approach > 0 and dist > approach * 2.0:
				jump_to_position(_current_target.global_position)

	# 技能 4：减速 — 对当前目标自动减速
	if _skill_auto[4] and _skill_cooldowns[4] <= 0:
		if _current_target != null and is_instance_valid(_current_target) and _current_target.team != team:
			var dist = global_position.distance_to(_current_target.global_position)
			if dist <= GameConfig.SKILL_SLOW_RANGE:
				apply_slow_to_target(_current_target)

	# 技能 5：净化 — 有 debuff 时自动释放
	if _skill_auto[5] and _skill_cooldowns[5] <= 0:
		if _slow_debuffs.size() > 0:
			activate_skill(5)


## 根据 attack_mode 做战术决策（环绕/保持距离/自由开火）
func _update_tactical() -> void:
	if _current_target == null or not is_instance_valid(_current_target) or _current_target.hull <= 0:
		return

	match attack_mode:
		AttackMode.ORBIT_SHOOT:
			# 还未环绕当前目标 → 启动环绕（含建筑，建筑为静态环绕中心）
			if not _is_orbit or _orbit_target_unit != _current_target:
				orbit_target(_current_target)

		AttackMode.KEEP_DISTANCE:
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

		AttackMode.FREE_FIRE:
			pass  # 由 _update_chase_execution 处理默认追逐


## 追逐当前目标（纯执行：在目标射程外则移动靠近，射程内则停火）
func _update_chase_execution() -> void:
	if _current_target == null or not is_instance_valid(_current_target) or _current_target.hull <= 0:
		_current_target = null
		if _is_area_attack:
			# 攻击移动模式下自动索敌
			_auto_target_in_area()
		elif has_saved_move:
			_target_position = saved_move_target
			_is_moving = true
			has_saved_move = false
		# 空闲自动攻击：没有指令时自动攻击射程内最近的敌人
		elif _auto_acquire_target():
			pass
		return

	# 环绕中不额外追逐（环绕逻辑自行处理移动）
	if _is_orbit:
		return

	var approach_range = _get_approach_range()
	if approach_range <= 0:
		return

	var dist = global_position.distance_to(_current_target.global_position)
	if dist <= approach_range and _explicit_attack_target != null:
		_is_moving = false
	elif dist > approach_range:
		var to_target = _current_target.global_position - global_position
		var dir = to_target.normalized()
		_target_position = _current_target.global_position - dir * approach_range * 0.85
		_is_moving = true


## 攻击移动模式下自动寻找范围内敌人（含建筑）
func _auto_target_in_area() -> void:
	if _is_area_attack and _current_target == null:
		var target = UnitCombat.find_nearest_enemy_in_area(self)
		if target != null:
			_current_target = target
		else:
			var building = UnitCombat.find_nearest_enemy_building_in_area(self)
			if building != null:
				_current_target = building


## 空闲自动攻击：没有指令时自动寻找射程内最近的敌人（含建筑）
## 返回 true 表示成功获取到目标
func _auto_acquire_target() -> bool:
	# 采矿船不自动攻击
	if _is_miner:
		return false
	# 正在移动、环绕或有指令队列时不自动索敌
	if _is_moving or _is_orbit or _command_queue.size() > 0:
		return false
	# 检查是否有进攻性武器
	var max_range = _get_max_range()
	if max_range <= 0:
		return false
	# 寻找射程内最近的敌人（含单位与建筑）
	var nearest: Node = null
	var nearest_dist = max_range
	# 搜索敌方单位
	for other in all_units:
		if other == self or not is_instance_valid(other) or other.hull <= 0:
			continue
		if other.team == team:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	# 搜索敌方建筑
	for b in Building.all_buildings:
		if not is_instance_valid(b) or b.hull <= 0:
			continue
		if b.team == team:
			continue
		var dist = global_position.distance_to(b.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = b
	if nearest != null:
		_current_target = nearest
		return true
	return false


func _update_orbit(delta: float) -> void:
	if not _is_orbit:
		return

	# 每帧记录目标位置，死亡时自动转为原地环绕点
	if is_instance_valid(_orbit_target_unit):
		_orbit_position = _orbit_target_unit.global_position
		if _orbit_target_unit.hull <= 0:
			_orbit_target_unit = null

	var center: Vector2
	if _orbit_target_unit != null and is_instance_valid(_orbit_target_unit):
		center = _orbit_target_unit.global_position
	else:
		center = _orbit_position

	var target_dist = _orbit_radius if _orbit_radius > 0 else _get_approach_range() * GameConfig.DEFAULT_ORBIT_RADIUS_RATIO
	if target_dist < 50:
		target_dist = 500.0

	# ---- EVE 风格速度矢量合成 ----
	var to_center = global_position - center
	var dist = to_center.length()

	# 更新轨道角度（供绘制轨道轨迹用）
	_orbit_angle = rad_to_deg(atan2(to_center.y, to_center.x))

	if dist < 0.001:
		# 完全重叠时随机推离
		velocity = Vector2.RIGHT.rotated(_body.rotation) * speed * 0.5
		_is_moving = true
		mark_dirty()
		return

	var radial = to_center / dist          # 径向（指向外）
	var tang = Vector2(-radial.y, radial.x) * _orbit_direction  # 切向（绕行方向）

	# 有效速度
	var slow_mult = _slow_mult * get_slow_mult()
	var effective_speed = speed * slow_mult
	if _speed_mult > 1.0:
		effective_speed *= _speed_mult

	# 切向速度（占绝大部分，保持环绕）
	var tang_speed = effective_speed * 0.9

	# 径向修正（比例控制，把距离拉回 target_dist）
	var error = dist - target_dist
	var radial_gain = 0.5
	var radial_speed = clamp(error * radial_gain, -effective_speed * 0.3, effective_speed * 0.3)

	# 合成期望速度
	var desired = tang * tang_speed - radial * radial_speed  # -radial 指向圆心
	if desired.length() > effective_speed:
		desired = desired.normalized() * effective_speed

	# 加速度限制
	var accel = thrust / mass
	if _speed_mult > 1.0:
		accel *= _speed_mult
	var accel_frame = accel * delta
	var diff = desired - velocity
	if diff.length() > accel_frame:
		velocity += diff.normalized() * accel_frame
	else:
		velocity = desired

	_is_moving = true
	mark_dirty()


static func _ship_class_tier(sc: ShipClass) -> int:
	match sc:
		ShipClass.MINER: return -1
		ShipClass.DRONE: return 0
		ShipClass.FRIGATE: return 1
		ShipClass.DESTROYER: return 2
		ShipClass.CRUISER: return 3
		ShipClass.BATTLESHIP: return 4
	return 0

static func get_class_name_cn(sc: ShipClass) -> String:
	match sc:
		ShipClass.MINER: return "采矿船"
		ShipClass.DRONE: return "无人机"
		ShipClass.FRIGATE: return "护卫舰"
		ShipClass.DESTROYER: return "驱逐舰"
		ShipClass.CRUISER: return "巡洋舰"
		ShipClass.BATTLESHIP: return "战列舰"
	return "未知"

func _get_class_name_cn() -> String:
	return get_class_name_cn(class_type)


# ===== 采矿系统 =====

## 将本船设置为采矿船模式
## 右键指定矿船前往某矿物场采矿
func mine_field(field) -> void:
	if not _is_miner or not is_instance_valid(field):
		return
	_command_queue.clear()
	_mining_target_field = field
	_miner_state = MinerState.MOVING_TO_FIELD
	_is_moving = true
	_target_position = field.global_position
	_is_attack_move = false
	_is_area_attack = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	mark_dirty()


func set_as_miner(home_mine) -> void:
	_is_miner = true
	_home_mine = home_mine
	_miner_state = MinerState.IDLE
	# 替换为采矿船纹理
	_sprite.texture = load("res://assets/miner.svg")
	# 降低战斗相关设置
	_current_target = null
	_explicit_attack_target = null


## 每帧更新采矿状态机（在 _process 中调用）
func _update_mining(delta: float) -> void:
	if not _is_miner or not is_instance_valid(_home_mine):
		return

	match _miner_state:
		MinerState.IDLE:
			# 正在执行玩家指令时等待，不自动采矿
			if _is_moving or _command_queue.size() > 0:
				return
			# 寻找最近的矿场
			_find_nearest_field()
			if _mining_target_field != null:
				_is_moving = true
				_target_position = _mining_target_field.global_position
				_miner_state = MinerState.MOVING_TO_FIELD

		MinerState.MOVING_TO_FIELD:
			if not is_instance_valid(_mining_target_field):
				_miner_state = MinerState.IDLE
				return
			var dist = global_position.distance_to(_mining_target_field.global_position)
			if dist < 60.0:
				_is_moving = false
				_miner_state = MinerState.MINING

		MinerState.MINING:
			if not is_instance_valid(_mining_target_field):
				_miner_state = MinerState.IDLE
				return
			# 每秒计算一次采矿量
			_miner_mine_timer += delta
			if _miner_mine_timer < 1.0:
				return
			_miner_mine_timer = 0.0
			var mine_amount = GameConfig.MINER_MINE_RATE
			var actual = _mining_target_field.mine(mine_amount)
			_miner_cargo = min(_miner_cargo + actual, _miner_cargo_capacity)
			if _miner_cargo >= _miner_cargo_capacity or actual <= 0:
				# 货仓满或矿枯竭 → 回矿场
				_miner_state = MinerState.RETURNING_TO_MINE
				_is_moving = true
				_target_position = _home_mine.global_position

		MinerState.RETURNING_TO_MINE:
			if not is_instance_valid(_home_mine):
				_miner_state = MinerState.IDLE
				return
			var dist = global_position.distance_to(_home_mine.global_position)
			if dist < GameConfig.MINER_DEPOSIT_RANGE:
				_is_moving = false
				_miner_state = MinerState.DEPOSITING

		MinerState.DEPOSITING:
			if not is_instance_valid(_home_mine):
				_miner_state = MinerState.IDLE
				return
			# 在矿场附近，卸货
			if _miner_cargo > 0:
				var deposited = _home_mine.deposit_minerals(_miner_cargo)
				_miner_cargo -= deposited
			else:
				_miner_state = MinerState.IDLE


func _find_nearest_field() -> void:
	var nearest = null
	var nearest_dist = GameConfig.MINER_SCAN_RANGE
	var all_fields = get_tree().get_nodes_in_group("mineral_fields")
	for field in all_fields:
		if not is_instance_valid(field):
			continue
		if field.mineral_amount <= 0:
			continue
		var dist = global_position.distance_to(field.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = field
	_mining_target_field = nearest


## 飞船名称前缀库
const SHIP_PREFIXES_CN: Array[String] = [
	"前锋", "骑士", "利剑", "风暴", "暗影", "长枪", "冰霜",
	"铁锤", "巨炮", "雷霆", "闪电", "烈焰", "寒冬", "光辉",
	"深渊", "星辉", "银河", "苍穹", "天罚", "神威",
]
## 已用名称记录，防止重名
static var _used_names: Array[String] = []

static func record_weapon_damage(which_team: String, wtype: Weapon.WeaponType, amount: float) -> void:
	var team_dict = team_weapon_damage.get(which_team, {})
	team_dict[wtype] = team_dict.get(wtype, 0.0) + amount
	team_weapon_damage[which_team] = team_dict


## 重置名称池，游戏重新开始时调用
static func reset_name_pool() -> void:
	_used_names.clear()

## 重置阵营积分，游戏重新开始时调用
static func reset_team_scores() -> void:
	team_scores.clear()
	team_losses.clear()

## 重置武器 DPS 统计，游戏重新开始时调用
static func reset_weapon_stats() -> void:
	team_weapon_damage.clear()
	team_weapon_lifetime.clear()

func _generate_ship_name() -> String:
	var prefix = SHIP_PREFIXES_CN[randi() % SHIP_PREFIXES_CN.size()]
	var suffix = class_name_cn
	var name_candidate = prefix + suffix
	# 如果重名则添加数字后缀
	var attempt := 0
	while name_candidate in _used_names and attempt < 50:
		var num = randi() % 100
		name_candidate = prefix + suffix + str(num)
		attempt += 1
	_used_names.append(name_candidate)
	return name_candidate


func _get_max_range() -> float:
	var max_r := 0.0
	for w in _slot_weapons:
		if w != null:
			max_r = max(max_r, w.attack_range * _weapon_range_mult)
	return max_r


func _get_approach_range() -> float:
	var min_r := INF
	for w in _slot_weapons:
		if w == null or w.weapon_type == Weapon.WeaponType.PD:
			continue
		min_r = min(min_r, w.attack_range * _weapon_range_mult)
	return min_r if min_r < INF else 0.0

func _rotate_toward(current: float, target: float, max_delta: float) -> float:
	"""限制步长旋转 current 角度到 target 角度（弧度）"""
	var diff = fposmod(target - current + PI, TAU) - PI
	if abs(diff) < 0.001:
		return target
	var step = clamp(abs(diff), -max_delta, max_delta) * sign(diff)
	return current + step


func _fire_slot(slot_index: int, target: Node) -> void:
	var w = _slot_weapons[slot_index]
	# 确保武器和目标有效，再发射子弹
	if w == null or target == null or not is_instance_valid(target) or target.team == team:
		return  # 武器或目标已失效

	var rotated_offset = _slot_offsets_scaled[slot_index].rotated(_body.rotation)
	var fire_pos = global_position + rotated_offset

	match w.weapon_type:
		Weapon.WeaponType.LASER:
			if target.has_method("take_damage"):
				target.call("take_damage", w.damage, self)
				# 激光立即造成伤害，直接统计
				Unit.record_weapon_damage(team, w.weapon_type, w.damage)
			else:
				print("DEBUG: missing take_damage on target", target, target.get_script())

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			# 计算目标速度修正提前量（预测拦截方向）
			var lead_dir: Vector2
			if target is Unit:
				lead_dir = _calculate_lead_direction(fire_pos, target as Unit, w.projectile_speed)
			else:
				# 对建筑等静态目标直接瞄准当前位置
				lead_dir = (target.global_position - fire_pos).normalized()
			# 子弹随机散布：每发子弹偏移瞄准方向 ±3°
			if w.weapon_type == Weapon.WeaponType.BULLET:
				lead_dir = lead_dir.rotated(deg_to_rad(randf_range(-3.0, 3.0)))
			_spawn_projectile(fire_pos, lead_dir, target, w)
			# 投射物发射时统计伤害（命中前即可统计实际DPS基准）
			Unit.record_weapon_damage(team, w.weapon_type, w.damage)


func _spawn_projectile(from_pos: Vector2, direction: Vector2, target: Node, w: Weapon) -> void:
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.global_position = from_pos

	# 弹体生命值（PD可消耗）
	var proj_hp := 0.0
	if w.weapon_type == Weapon.WeaponType.BULLET:
		proj_hp = GameConfig.BULLET_HP
	elif w.weapon_type == Weapon.WeaponType.MISSILE:
		proj_hp = GameConfig.MISSILE_HP

	# 寿命 = 有效射程 / 弹体速度，确保子弹能飞到射程
	var effective_range = w.attack_range * _weapon_range_mult
	var lifetime = effective_range / max(w.projectile_speed, 1.0) * 1.1

	# 先加入场景树，确保 @onready 变量初始化后再 setup
	get_parent().add_child(proj)
	proj.setup({
		"max_speed": w.projectile_speed,
		"acceleration": GameConfig.BULLET_ACCELERATION,
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


## 计算目标速度修正提前量（预测拦截方向）
## 通过解二次方程求子弹与目标相遇时间，计算前置瞄准方向
func _calculate_lead_direction(from_pos: Vector2, target: Node, proj_speed: float) -> Vector2:
	var d = target.global_position - from_pos
	# 建筑等静态目标无 velocity，做零向量处理
	var v: Vector2 = Vector2.ZERO
	if "velocity" in target:
		v = target.velocity
	var s = max(proj_speed, 1.0)

	# 解二次方程: (v·v - s²)t² + 2(d·v)t + d·d = 0
	var a = v.dot(v) - s * s
	var b = 2.0 * d.dot(v)
	var c = d.dot(d)

	var t := 0.0
	if abs(a) > 0.001:
		var discriminant = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var sqrt_d = sqrt(discriminant)
			var t1 = (-b - sqrt_d) / (2.0 * a)
			var t2 = (-b + sqrt_d) / (2.0 * a)
			# 选择最小的正解
			if t1 > 0.0 and (t2 <= 0.0 or t1 < t2):
				t = t1
			elif t2 > 0.0:
				t = t2
	elif abs(b) > 0.001:
		t = -c / b

	if t <= 0.0:
		# 无法计算提前量，直接瞄准目标当前位置
		return (target.global_position - from_pos).normalized()

	var predicted_pos = target.global_position + v * t
	return (predicted_pos - from_pos).normalized()


func take_damage(amount: float, source: Node = null) -> void:
	# 重置受伤计时器（用于 AI 判断脱离战斗）
	_last_damage_timer = 0.0

	# 先处理伤害加成和减免逻辑
	var final_damage = amount * _damage_taken_mult
	if source != null and source is Unit and source.team != team:
		# 友军伤害额外减免或无视（暂无效果）
		pass

	if shield > 0.0:
		var remaining = final_damage - shield
		shield = max(0.0, shield - final_damage)
		if remaining > 0.0:
			hull = max(0.0, hull - remaining)
	else:
		hull = max(0.0, hull - final_damage)

	_shield_regen_delay = GameConfig.SHIELD_REGEN_DELAY
	mark_dirty()
	if hull <= 0.0:
		# 根据船型计算损失积分（在 if 块外定义，供后续使用）
		var threat_gain := 0
		match class_type:
			ShipClass.DRONE: threat_gain = 1
			ShipClass.FRIGATE: threat_gain = 2
			ShipClass.DESTROYER: threat_gain = 3
			ShipClass.CRUISER: threat_gain = 4
			ShipClass.BATTLESHIP: threat_gain = 5
		# 击杀者增加战绩
		if source != null and source is Unit and source != self:
			var killer: Unit = source
			killer.kill_count += 1
			killer.threat_level += threat_gain
			# 更新阵营总积分
			team_scores[killer.team] = team_scores.get(killer.team, 0) + threat_gain
		# 被击毁方记录损失积分
		team_losses[team] = team_losses.get(team, 0) + threat_gain
		# 目标死亡时清理状态
		_is_moving = false
		_is_orbit = false
		_current_target = null
		_explicit_attack_target = null
		queue_free()

func find_nearest_enemy() -> Unit:
	return UnitCombat.find_nearest_enemy(self)

func _set_skill_auto(value: Array[bool]) -> void:
	_skill_auto = value
	mark_dirty()

func activate_skill(index: int) -> void:
	"""纯 buff 类直接释放，跃迁/减速对位置或目标使用远程版本"""
	if index < 0 or index >= _skill_cooldowns.size():
		return
	if _skill_cooldowns[index] > 0.0:
		return

	match index:
		0:
			_speed_mult = GameConfig.SKILL_SPEED_MULT
			_skill_timers[0] = GameConfig.SKILL_DURATION
		1:
			_attack_speed_mult = GameConfig.SKILL_ATTACK_SPEED_MULT
			_skill_timers[1] = GameConfig.SKILL_DURATION
		2:
			_damage_taken_mult = GameConfig.SKILL_DAMAGE_TAKEN_MULT
			_skill_timers[2] = GameConfig.SKILL_DURATION
		3:
			# 跃迁：手动释放，调用 jump_to_position
			pass
		4:
			# 减速：自动或手动释放，调用 apply_slow_to_target
			pass
		5:
			# 净化：清除所有 debuff，重置状态
			_slow_debuffs.clear()
			_slow_mult = 1.0
			_debuff_immunity_timer = GameConfig.SKILL_PURIFY_IMMUNITY_DURATION
		6:
			# 部署船厂 — 由施法模式处理，此处仅检查矿物
			return
		7:
			# 部署矿厂 — 由施法模式处理，此处仅检查矿物
			return

	_skill_cooldowns[index] = GameConfig.SKILL_CD if index != 5 else GameConfig.SKILL_PURIFY_COOLDOWN
	mark_dirty()


## 跃迁到目标位置瞬移，受 max_dist 限制
func jump_to_position(target_pos: Vector2, max_dist: float = GameConfig.SKILL_JUMP_MAX_DIST) -> void:
	if _skill_cooldowns[3] > 0.0:
		return
	var dir = (target_pos - global_position).normalized()
	var dist = min(global_position.distance_to(target_pos), max_dist)
	global_position += dir * dist
	_skill_cooldowns[3] = GameConfig.SKILL_CD
	mark_dirty()


## 探测某位置是否在部署范围内（供 main 调用）
func is_in_deploy_range(target_pos: Vector2) -> bool:
	return global_position.distance_to(target_pos) <= GameConfig.DEPLOY_RANGE


## 立即执行部署（消耗矿物、生成建筑）
func _execute_deploy_now(building_type: int, cost: int, pos: Vector2) -> void:
	var main_node = get_parent()
	if not main_node or not main_node.has_method("get_team_minerals"):
		return
	if main_node.get_team_minerals(team) < cost:
		return
	if not main_node.has_method("spend_team_minerals"):
		return
	if not main_node.spend_team_minerals(team, cost):
		return
	if main_node.has_method("spawn_deploy_building"):
		main_node.spawn_deploy_building(team, building_type, pos)


## 将部署建筑指令加入队列末尾（Shift+部署）
func queue_deploy_building(building_type: int, cost: int, pos: Vector2) -> void:
	_command_queue.append({"type": "deploy", "building_type": building_type, "cost": cost, "pos": pos})
	mark_dirty()
	_try_execute_queue()


## 减速，对目标施加 50% 减速 debuff
func apply_slow_to_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_slow_debuff"):
		return
	if _skill_cooldowns[4] > 0.0:
		return
	var dist = global_position.distance_to(target.global_position)
	if dist > GameConfig.SKILL_SLOW_RANGE:
		return
	target.take_slow_debuff(GameConfig.SKILL_SLOW_DEBUFF_FACTOR, GameConfig.SKILL_SLOW_DEBUFF_DURATION)
	_skill_cooldowns[4] = GameConfig.SKILL_SLOW_COOLDOWN


## 被施加减速 debuff，叠加，每层叠加，可被净化
func take_slow_debuff(factor: float, duration: float) -> void:
	if _debuff_immunity_timer > 0:
		return
	_slow_debuffs.append({"factor": factor, "timer": duration})
	mark_dirty()


## 获取当前所有 debuff 叠加后的总倍率
func get_slow_mult() -> float:
	if _slow_debuffs.size() == 0:
		return 1.0
	var mult := 1.0
	for d in _slow_debuffs:
		mult *= d["factor"]
	return mult


## 获取当前所有活跃 buff/debuff 信息，供 HUD 显示
func get_active_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _skill_timers[0] > 0:
		result.append({"name": "加速", "desc": "速度+100%", "color": Color(0.2, 1.0, 0.3)})
	if _skill_timers[1] > 0:
		result.append({"name": "速射", "desc": "射速+100%", "color": Color(1.0, 0.6, 0.2)})
	if _skill_timers[2] > 0:
		var dmg_pct = int((1.0 - GameConfig.SKILL_DAMAGE_TAKEN_MULT) * 100.0)
		result.append({"name": "减伤", "desc": "减免-%d%%" % dmg_pct, "color": Color(0.2, 0.8, 1.0)})
	if _debuff_immunity_timer > 0:
		result.append({"name": "免疫", "desc": "免疫debuff", "color": Color(0.3, 0.9, 0.9)})
	if _slow_debuffs.size() > 0:
		var count = _slow_debuffs.size()
		var slow_pct = int((1.0 - get_slow_mult()) * 100.0)
		var label = "减速" if count == 1 else "减速 x%d" % count
		result.append({"name": label, "desc": "速度-%d%%" % slow_pct, "color": Color(1.0, 0.3, 0.3)})
	return result

func _set_is_selected(value: bool) -> void:
	is_selected = value
	_sprite.self_modulate = unit_color
	mark_dirty()

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
		var back = Vector2.LEFT.rotated(_body.rotation) * 8.0 * _size_mult
		var tip = back + Vector2.LEFT.rotated(_body.rotation) * flame_len * _size_mult
		var spread = Vector2.UP.rotated(_body.rotation) * 3.0 * _size_mult
		var pts = PackedVector2Array([back + spread, back - spread, tip])
		draw_colored_polygon(pts, flame_color)

	# ---- 轨道轨迹（选中时绘制）---- 
	if _is_orbit and is_selected:
		var center: Vector2
		if is_instance_valid(_orbit_target_unit) and _orbit_target_unit.hull > 0:
			center = _orbit_target_unit.global_position - global_position
		else:
			center = _orbit_position - global_position
		var radius = _orbit_radius if _orbit_radius > 0 else _get_approach_range() * GameConfig.DEFAULT_ORBIT_RADIUS_RATIO
		if radius < 50: radius = 50
		var trail_color = Color(0.2, 1.0, 0.5, 0.25)
		var segments = 48
		for i in range(segments):
			var a1 = deg_to_rad(i * 360.0 / segments)
			var a2 = deg_to_rad((i + 1) * 360.0 / segments)
			var p1 = center + Vector2(cos(a1), sin(a1)) * radius
			var p2 = center + Vector2(cos(a2), sin(a2)) * radius
			draw_line(p1, p2, trail_color, 1.5)
		# 位置指示箭头
		var arrow_angle = deg_to_rad(_orbit_angle)
		var arrow_pos = center + Vector2(cos(arrow_angle), sin(arrow_angle)) * radius
		draw_circle(arrow_pos, 3.0, Color(0.2, 1.0, 0.5, 0.5))
		# 指向目标中心的虚线
		draw_line(Vector2.ZERO, center, Color(0.2, 1.0, 0.5, 0.1), 1.0)

	# ---- Buff/Debuff 显示（单位右侧从上到下）----
	var buff_entries = get_active_buffs()
	if buff_entries.size() > 0:
		var font = ThemeDB.fallback_font
		var font_size: int = max(1, int(11.0 * _size_mult))
		var line_h: float = font_size * 1.3
		var total_h = buff_entries.size() * line_h
		var x = 32.0 * _size_mult + 30.0
		var y = -total_h / 2.0 + line_h * 0.8
		for e in buff_entries:
			draw_string(font, Vector2(x, y), e["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, e["color"])
			y += line_h

	# 激光渲染线（每个激光炮台指向目标）
	if is_instance_valid(_current_target) and _current_target.team != team and _laser_cycle_timer > 0:
		var dist = global_position.distance_to(_current_target.global_position)
		var lc1: Color
		var lc2: Color
		var lc3: Color
		if team == Unit.player_team_name:
			lc1 = Color(0.15, 0.3, 1.0, 0.25)
			lc2 = Color(0.2, 0.4, 1.0, 0.7)
			lc3 = Color(0.6, 0.8, 1.0, 0.4)
		else:
			lc1 = Color(1.0, 0.15, 0.15, 0.25)
			lc2 = Color(1.0, 0.2, 0.2, 0.7)
			lc3 = Color(1.0, 0.7, 0.7, 0.4)
		for i in range(slot_count):
			var w = _slot_weapons[i]
			if w != null and w.weapon_type == Weapon.WeaponType.LASER and dist <= w.attack_range * _weapon_range_mult:
				var start = _slot_offsets_scaled[i].rotated(_body.rotation)
				var end = _current_target.global_position - global_position
				# 外发光
				draw_line(start, end, lc1, 18.0)
				# 主光束
				draw_line(start, end, lc2, 6.0)
				# 核心光柱
				draw_line(start, end, lc3, 2.4)

	# PD 拦截光线（每个 PD 炮台指向目标弹体）
	if _pd_has_target:
		var end = _pd_target_pos - global_position
		for i in range(slot_count):
			var w = _slot_weapons[i]
			if w != null and w.weapon_type == Weapon.WeaponType.PD:
				var start = _slot_offsets_scaled[i].rotated(_body.rotation)
				# 外发光
				draw_line(start, end, Color(0.15, 0.8, 0.5, 0.25), 5.0)
				# 主光束
				draw_line(start, end, Color(0.2, 1.0, 0.7, 0.6), 2.0)
				# 核心光柱
				draw_line(start, end, Color(0.5, 1.0, 0.8, 0.4), 0.8)

	# ---- 指令队列连线（选中时显示）----
	# （移入 Main._draw 在世界坐标系中绘制）
	
	# ---- 护盾 & 结构条 ---- 
	var bar_width = 64.0 * _size_mult
	var bar_half = bar_width / 2.0
	var bar_top = -collision_shape.shape.size.y * 0.6  # 选择框顶部 = -size*1.2/2

	# 护盾条（蓝色，上方）
	if shield < max_shield:
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width, 4.0), Color(0.15, 0.15, 0.2, 0.8), true)
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width * shield / max_shield, 4.0), Color(0.2, 0.5, 1.0, 0.9), true)

	# 结构条（绿色/黄色/红色）
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

	# ---- 编组号（血条左侧）----
	if control_group >= 0:
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), Vector2(-bar_half - 22, bar_top - 34 + 8), str(control_group),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.6))

	# 选择框
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


func _create_weapon_sprite(index: int) -> void:
	var ws = Sprite2D.new()
	ws.name = "Weapon" + str(index)
	ws.position = _slot_offsets_scaled[index]
	ws.texture = load("res://assets/weapon_launcher/Cannon.svg")
	ws.centered = true
	ws.scale = Vector2.ONE * _size_mult / 3.0
	_body.add_child(ws)
	_weapon_sprites.append(ws)


## 根据船型返回对应 SVG 图片路径
const WEAPON_TEX_PATHS: Dictionary = {
	Weapon.WeaponType.BULLET: "res://assets/weapon_launcher/Cannon.svg",
	Weapon.WeaponType.LASER: "res://assets/weapon_launcher/Laser.svg",
	Weapon.WeaponType.MISSILE: "res://assets/weapon_launcher/MissileLauncher.svg",
	Weapon.WeaponType.PD: "res://assets/weapon_launcher/PD.svg",
}

## 刷新武器插槽 Sprite2D 显示，由外部赋值 _slot_weapons 后调用
func refresh_weapon_visuals() -> void:
	for i in range(min(_weapon_sprites.size(), _slot_weapons.size())):
		var w = _slot_weapons[i]
		if w != null and WEAPON_TEX_PATHS.has(w.weapon_type):
			_weapon_sprites[i].texture = load(WEAPON_TEX_PATHS[w.weapon_type])
			_weapon_sprites[i].visible = true
		else:
			_weapon_sprites[i].visible = false

func attack_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.is_dead():
		return
	if "hull" in target and target.hull <= 0:
		return
	# 非 Shift 时清空指令队列
	_command_queue.clear()
	_explicit_attack_target = target
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_current_target = target
	mark_dirty()

## 将攻击目标加入指令队列末尾（Shift+右键点敌）
func queue_attack_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.is_dead():
		return
	if "hull" in target and target.hull <= 0:
		return
	_command_queue.append({"type": "attack", "target": target})
	mark_dirty()
	_try_execute_queue()

func attack_area(center: Vector2, radius: float) -> void:
	_command_queue.clear()
	_area_center = center
	_area_radius = radius
	_is_area_attack = true
	_is_attack_move = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	mark_dirty()

func move_to(target_pos: Vector2, arrival_rotation: float = INF) -> void:
	_command_queue.clear()
	_target_position = target_pos
	_arrival_rotation = arrival_rotation
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	mark_dirty()

## 将移动点加入指令队列末尾（Shift+点地）
func queue_move_to(target_pos: Vector2, arrival_rotation: float = INF) -> void:
	_command_queue.append({"type": "move", "pos": target_pos, "face": arrival_rotation})
	mark_dirty()
	_try_execute_queue()

## 开始环绕（共有逻辑：清空指令、设置轨道参数、标记重绘）
func _start_orbit(center_pos: Vector2, custom_radius: float) -> void:
	_command_queue.clear()
	_orbit_radius = custom_radius
	_target_position = center_pos  # 清除旧移动指示线
	# 从当前位置切入环绕圆，避免调头绕远路
	_orbit_angle = rad_to_deg((global_position - center_pos).angle())
	_is_orbit = true
	_is_moving = true
	mark_dirty()

func orbit_target(target: Node, custom_radius: float = -1.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	if "hull" in target and target.hull <= 0:
		return
	_orbit_target_unit = target
	_orbit_position = target.global_position
	_current_target = target
	_start_orbit(target.global_position, custom_radius)

func orbit_position(orbit_pos: Vector2, custom_radius: float = -1.0) -> void:
	_orbit_target_unit = null
	_orbit_position = orbit_pos
	_current_target = null
	_start_orbit(orbit_pos, custom_radius)

## 从指令队列取出下一个指令并执行（移动到达/目标死亡后自动调用）
func _advance_command_queue() -> void:
	while _command_queue.size() > 0:
		var cmd = _command_queue[0]  # 先 peek，不要立即 pop
		if cmd.type == "move":
			_command_queue.pop_front()
			_target_position = cmd.pos
			_is_moving = true
			_is_attack_move = false
			_is_area_attack = false
			_is_orbit = false
			_current_target = null
			_explicit_attack_target = null
			return
		elif cmd.type == "attack":
			if not is_instance_valid(cmd.target):
				_command_queue.pop_front()
				continue
			var t = cmd.target
			if "hull" in t and t.hull > 0:
				_command_queue.pop_front()
				_explicit_attack_target = t
				_current_target = t
				_is_attack_move = false
				_is_area_attack = false
				_is_orbit = false
				mark_dirty()
			return
		elif cmd.type == "deploy":
			# 部署指令：在范围内直接部署，否则移动靠近（不弹出指令）
			var deploy_pos = cmd.pos as Vector2
			if is_in_deploy_range(deploy_pos):
				_command_queue.pop_front()
				_execute_deploy_now(cmd.building_type, cmd.cost, deploy_pos)
				continue  # 继续处理下一条指令
			else:
				# 超出范围：移动到距部署点 DEPLOY_ARRIVAL_DISTANCE 处
				var dir = (deploy_pos - global_position).normalized()
				var dist = global_position.distance_to(deploy_pos)
				var move_dist = max(dist - GameConfig.DEPLOY_ARRIVAL_DISTANCE, 0.0)
				_target_position = global_position + dir * move_dist
				_is_moving = true
				_is_orbit = false
				_current_target = null
				_explicit_attack_target = null
				mark_dirty()
			return
		# 未知指令类型，跳过
		_command_queue.pop_front()

## 如果当前空闲则开始执行指令队列；环绕中时有指令则取消环绕
func _try_execute_queue() -> void:
	if _command_queue.size() == 0:
		return
	# 环绕中时有新指令，退出环绕以执行队列
	if _is_orbit:
		_is_orbit = false
		_is_moving = false
	var idle = not _is_moving \
		and (_current_target == null or not is_instance_valid(_current_target) or _current_target.hull <= 0)
	if idle:
		_advance_command_queue()

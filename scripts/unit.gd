class_name Unit
extends Area2D

enum Team { BLUE, RED, YELLOW }
enum ShipClass { DRONE, FRIGATE, DESTROYER, CRUISER, BATTLESHIP }
enum AttackMode { FREE_FIRE, KEEP_DISTANCE, ORBIT_SHOOT }

const UNIT_COMBAT = preload("res://scripts/unit_combat.gd")
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
var _skill_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # 加速/速射/减伤/跃迁/减速/净化
## 技能自动释放标记，默认减速自动
var _skill_auto: Array[bool] = [false, false, false, false, true, false] :
	set = _set_skill_auto
var _speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _damage_taken_mult: float = 1.0
var _slow_mult: float = 1.0
## 对敌方施加 debuff，支持叠加
var _slow_debuffs: Array[Dictionary] = []  # 每项: {"factor": float, "timer": float}
var _skill_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 减益免疫计时
var _debuff_immunity_timer: float = 0.0

# ----- 激光系统（攻击3s / 冷却2s，无人机~战列舰时长+0~40%）-----
var _laser_cycle_timer: float = 0.0  # 初始倒计时
var _laser_attack_duration: float = GameConfig.LASER_ATTACK_DURATION  # 在 _ready 中根据船型计算

## 尺寸倍数 (×1.5^_tier)
var _size_mult: float = 1.0
## 缩放后的插槽偏移
var _slot_offsets_scaled: Array[Vector2] = []
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE

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
var attack_mode: AttackMode = AttackMode.FREE_FIRE

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

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
var _explicit_attack_target: Unit = null
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

# ----- 环绕 -----
var _is_orbit: bool = false
var _orbit_target_unit: Unit = null
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

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _body: Node2D = $Body

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	print("DEBUG: Unit._ready loaded", self, self.get_script())
	# ---- 根据飞船等级计算属性 ----
	_tier = _ship_class_tier(class_type)
	_size_mult = pow(1.5, _tier)
	_weapon_damage_mult = pow(1.2, _tier)
	_laser_attack_duration = GameConfig.LASER_ATTACK_DURATION * (1.0 + _tier * GameConfig.LASER_CLASS_BONUS)
	_weapon_range_mult = pow(1.5, _tier)
	# 根据船型设置默认攻击模式
	match class_type:
		ShipClass.DRONE, ShipClass.FRIGATE:
			attack_mode = AttackMode.ORBIT_SHOOT
		ShipClass.DESTROYER:
			attack_mode = AttackMode.KEEP_DISTANCE
		_:
			attack_mode = AttackMode.FREE_FIRE

		# 插槽数量：无人机2 护卫舰2 驱逐4 巡洋6 战列舰8
	match class_type:
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


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_skill_timers(delta)
	_update_shield(delta)

	# ---- 自动释放标记为自动的技能（所有队伍统一处理）----
	_update_auto_skills()

	# ---- 根据攻击模式做战术决策（所有队伍统一处理）----
	_update_tactical()

	# ---- 执行层（不含任何 AI 决策）----
	UNIT_COMBAT.update_turrets(self, delta)
	UNIT_COMBAT.update_weapons(self, delta)
	UNIT_COMBAT.update_pd(self, delta)
	_update_chase_execution()
	_update_orbit(delta)
	UNIT_MOVEMENT.update_drones(self, delta)
	UNIT_MOVEMENT.update_movement(self, delta)
	queue_redraw()


func _update_cooldowns(delta: float) -> void:
	var cd_rate = delta * _attack_speed_mult
	for i in range(slot_count):
		_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - cd_rate)
	for i in range(6):
		_skill_cooldowns[i] = max(0.0, _skill_cooldowns[i] - delta)


func _update_skill_timers(delta: float) -> void:
	for i in range(6):
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


func _update_shield(delta: float) -> void:
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
			# 还未环绕当前目标 → 启动环绕
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


## 攻击移动模式下自动寻找范围内敌人
func _auto_target_in_area() -> void:
	if _is_area_attack and _current_target == null:
		var target = UNIT_COMBAT.find_nearest_enemy_in_area(self)
		if target != null:
			_current_target = target


func _update_orbit(delta: float) -> void:
	if _is_orbit:
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


static func _ship_class_tier(sc: ShipClass) -> int:
	match sc:
		ShipClass.DRONE: return 0
		ShipClass.FRIGATE: return 1
		ShipClass.DESTROYER: return 2
		ShipClass.CRUISER: return 3
		ShipClass.BATTLESHIP: return 4
	return 0

static func get_class_name_cn(sc: ShipClass) -> String:
	match sc:
		ShipClass.DRONE: return "无人机"
		ShipClass.FRIGATE: return "护卫舰"
		ShipClass.DESTROYER: return "驱逐舰"
		ShipClass.CRUISER: return "巡洋舰"
		ShipClass.BATTLESHIP: return "战列舰"
	return "未知"

func _get_class_name_cn() -> String:
	return get_class_name_cn(class_type)

## 飞船名称前缀库
const SHIP_PREFIXES_CN: Array[String] = [
	"前锋", "骑士", "利剑", "风暴", "暗影", "长枪", "冰霜",
	"铁锤", "巨炮", "雷霆", "闪电", "烈焰", "寒冬", "光辉",
	"深渊", "星辉", "银河", "苍穹", "天罚", "神威",
]
## 已用名称记录，防止重名
static var _used_names: Array[String] = []

## 重置名称池，游戏重新开始时调用
static func reset_name_pool() -> void:
	_used_names.clear()

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
	var diff = fmod(target - current + PI, TAU) - PI
	if abs(diff) < 0.001:
		return target
	var step = clamp(abs(diff), -max_delta, max_delta) * sign(diff)
	return current + step


func _fire_slot(slot_index: int, target: Unit) -> void:
	var w = _slot_weapons[slot_index]
	# 确保武器和目标有效，再发射子弹
	if w == null or target == null or not is_instance_valid(target) or target.team == team:
		return  # 武器或目标已失效

	var rotated_offset = _slot_offsets_scaled[slot_index].rotated(_body.rotation)
	var fire_pos = global_position + rotated_offset
	var fire_dir = Vector2.RIGHT.rotated(_body.rotation + _slot_angles[slot_index])

	match w.weapon_type:
		Weapon.WeaponType.LASER:
			if target.has_method("take_damage"):
				target.call("take_damage", w.damage, self)
			else:
				print("DEBUG: missing take_damage on target", target, target.get_script())

		Weapon.WeaponType.BULLET, Weapon.WeaponType.MISSILE:
			_spawn_projectile(fire_pos, fire_dir, target, w)


func _spawn_projectile(from_pos: Vector2, direction: Vector2, target: Unit, w: Weapon) -> void:
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
	get_parent().add_child(proj)

func take_damage(amount: float, source: Node = null) -> void:
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
	if hull <= 0.0:
		# 目标死亡时清理状态
		_is_moving = false
		_is_orbit = false
		_current_target = null
		_explicit_attack_target = null
		queue_free()

func find_nearest_enemy() -> Unit:
	return UNIT_COMBAT.find_nearest_enemy(self)

func _set_skill_auto(value: Array[bool]) -> void:
	_skill_auto = value

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

	_skill_cooldowns[index] = GameConfig.SKILL_CD if index != 5 else GameConfig.SKILL_PURIFY_COOLDOWN


## 跃迁到目标位置瞬移，受 max_dist 限制
func jump_to_position(target_pos: Vector2, max_dist: float = GameConfig.SKILL_JUMP_MAX_DIST) -> void:
	if _skill_cooldowns[3] > 0.0:
		return
	var dir = (target_pos - global_position).normalized()
	var dist = min(global_position.distance_to(target_pos), max_dist)
	global_position += dir * dist
	_skill_cooldowns[3] = GameConfig.SKILL_CD


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
		if team == Team.BLUE:
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

	# ---- 指令队列连线（选中时显示，绿=移动，红=攻击）----
	if is_selected and _command_queue.size() > 0:
		var line_width = 1.2 * _size_mult
		var from_pos = Vector2.ZERO
		# 如果正在移动，先连绿线到当前移动目标
		if _is_moving:
			var cur_pos = _target_position - global_position
			draw_line(from_pos, cur_pos, Color(0.2, 1.0, 0.3, 0.55), line_width)
			from_pos = cur_pos
		# 如果有当前攻击目标，连红线
		elif is_instance_valid(_current_target) and _current_target.hull > 0 and _current_target.team != team:
			var cur_pos = _current_target.global_position - global_position
			draw_line(from_pos, cur_pos, Color(1.0, 0.15, 0.15, 0.55), line_width)
			from_pos = cur_pos
		# 遍历队列依次绘制
		for cmd in _command_queue:
			if cmd.type == "move":
				var to_pos = cmd.pos - global_position
				draw_line(from_pos, to_pos, Color(0.2, 1.0, 0.3, 0.55), line_width)
				from_pos = to_pos
			elif cmd.type == "attack":
				if not is_instance_valid(cmd.target):
					continue
				var t: Unit = cmd.target
				if t.hull <= 0:
					continue
				var to_pos = t.global_position - global_position
				draw_line(from_pos, to_pos, Color(1.0, 0.15, 0.15, 0.55), line_width)
				from_pos = to_pos

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

func attack_target(target: Unit) -> void:
	if target == null or not is_instance_valid(target) or target.hull <= 0:
		return
	# 非 Shift 时清空指令队列
	_command_queue.clear()
	_explicit_attack_target = target
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_current_target = target

## 将攻击目标加入指令队列末尾（Shift+右键点敌）
func queue_attack_target(target: Unit) -> void:
	if target == null or not is_instance_valid(target) or target.hull <= 0:
		return
	_command_queue.append({"type": "attack", "target": target})
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

func move_to(target_pos: Vector2) -> void:
	_command_queue.clear()
	_target_position = target_pos
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null

## 将移动点加入指令队列末尾（Shift+点地）
func queue_move_to(target_pos: Vector2) -> void:
	_command_queue.append({"type": "move", "pos": target_pos})
	_try_execute_queue()

func orbit_target(target: Unit, custom_radius: float = -1.0) -> void:
	if target == null or not is_instance_valid(target) or target.hull <= 0:
		return
	_command_queue.clear()
	_orbit_target_unit = target
	_orbit_position = target.global_position
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_current_target = target

func orbit_position(orbit_pos: Vector2, custom_radius: float = -1.0) -> void:
	_command_queue.clear()
	_orbit_target_unit = null
	_orbit_position = orbit_pos
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_current_target = null

## 从指令队列取出下一个指令并执行（移动到达/目标死亡后自动调用）
func _advance_command_queue() -> void:
	while _command_queue.size() > 0:
		var cmd = _command_queue.pop_front()
		if cmd.type == "move":
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
				continue
			var t: Unit = cmd.target
			if t.hull > 0:
				_explicit_attack_target = t
				_current_target = t
				_is_attack_move = false
				_is_area_attack = false
				_is_orbit = false
				return
			# 目标已死亡，跳过继续取下一条

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

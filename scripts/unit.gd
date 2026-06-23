class_name Unit
extends Area2D

enum Team { BLUE, RED }
enum ShipClass { DRONE, FRIGATE, DESTROYER, CRUISER, BATTLESHIP }
enum AttackMode { FREE_FIRE, KEEP_DISTANCE, ORBIT_SHOOT }

const CFG = preload("res://scripts/game_config.gd")
const UNIT_COMBAT = preload("res://scripts/unit_combat.gd")
const UNIT_MOVEMENT = preload("res://scripts/unit_movement.gd")

@export var class_type: ShipClass = ShipClass.DRONE
@export var speed: float = CFG.UNIT_MAX_SPEED
@export var acceleration: float = CFG.UNIT_ACCELERATION
@export var mass: float = CFG.UNIT_MASS
@export var forward_acceleration: float = CFG.UNIT_FORWARD_ACCELERATION
@export var max_angular_speed: float = CFG.UNIT_MAX_ANGULAR_SPEED
@export var angular_acceleration: float = CFG.UNIT_ANGULAR_ACCELERATION
var velocity: Vector2
## 飞船等级 (0=无人机, 1=护卫舰, ..., 4=战列舰)
var _tier: int = 0
## 武器伤害倍率 (×1.2^_tier)
var _weapon_damage_mult: float = 1.0
## 武器射程倍率 (×1.5^_tier)
var _weapon_range_mult: float = 1.0
## 控制组编号（-1 = 未编组）
var control_group: int = -1

# ----- 技能系统 -----
var _skill_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # 加速/攻速/减伤/跃迁/减速/净化
## 技能自动释放标记（默认仅减速自动）
var _skill_auto: Array[bool] = [false, false, false, false, true, false] :
	set = _set_skill_auto
var _speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _damage_taken_mult: float = 1.0
var _slow_mult: float = 1.0
## 来自敌方减速 debuff（支持叠加）
var _slow_debuffs: Array[Dictionary] = []  # 每项: {"factor": float, "timer": float}
var _skill_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 净化免疫倒计时
var _debuff_immunity_timer: float = 0.0

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
## 飞船名字（初始化时自动生成）
var unit_name: String

## 飞船类名（中文）
var class_name_cn: String

## 是否被选中
var is_selected: bool = false : set = _set_is_selected

var all_units: Array[Unit] = []
var attack_mode: AttackMode = AttackMode.FREE_FIRE

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

# ----- 武器槽位 -----
var _slot_weapons: Array = []
var _slot_angles: Array[float] = []
var _slot_cooldowns: Array[float] = []
var _weapon_sprites: Array[Sprite2D] = []

const SLOT_OFFSETS: Array[Vector2] = [
	# 飞船两侧布置（上侧为负Y，下侧为正Y）
	Vector2(25, -35),    # 0: 上前1
	Vector2(25, 35),     # 1: 下前1
	Vector2(10, -40),    # 2: 上前2
	Vector2(10, 40),     # 3: 下前2
	Vector2(-5, -40),    # 4: 上中1
	Vector2(-5, 40),     # 5: 下中1
	Vector2(-20, -35),   # 6: 上后1
	Vector2(-20, 35),    # 7: 下后1
	Vector2(32, -20),    # 8: 上前3
	Vector2(32, 20),     # 9: 下前3
	Vector2(-32, -20),   # 10: 上后2
	Vector2(-32, 20),    # 11: 下后2
	Vector2(-10, -25),   # 12: 上中2
	Vector2(-10, 25),    # 13: 下中2
	Vector2(0, -30),     # 14: 上中3
	Vector2(0, 30),      # 15: 下中3
]

# ----- 攻击指令相关 -----
var _explicit_attack_target: Unit = null
var attack_move_destination: Vector2
var _is_attack_move: bool = false
## 区域攻击（A+空地点地）
var _is_area_attack: bool = false
var _area_center: Vector2
var _area_radius: float = 500.0
var saved_move_target: Vector2
var has_saved_move: bool = false
## 玩家指令计时器 >0 时 AI 不覆盖行为
var _player_command_timer: float = 0.0
## 玩家下达了移动指令（在到达目的地前阻止自动攻击覆盖移动）
var _player_move_command: bool = false

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
var drone_bay: int = 10
var home_battleship: Unit = null  # 无人机所属母舰
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
	_laser_attack_duration = CFG.LASER_ATTACK_DURATION * (1.0 + _tier * CFG.LASER_CLASS_BONUS)
	_weapon_range_mult = pow(1.5, _tier)
	# 根据船型设置默认攻击模式
	match class_type:
		ShipClass.DRONE, ShipClass.FRIGATE:
			attack_mode = AttackMode.ORBIT_SHOOT
		ShipClass.DESTROYER:
			attack_mode = AttackMode.KEEP_DISTANCE
		_:
			attack_mode = AttackMode.FREE_FIRE

		# 槽位数量：无人机2 护卫舰2 驱逐舰4 巡洋舰6 战列舰8
	match class_type:
		ShipClass.DRONE:
			slot_count = 2
		ShipClass.CRUISER:
			slot_count = 6
		ShipClass.BATTLESHIP:
			slot_count = 8
		_:
			slot_count = int(pow(2, _tier))
	speed = CFG.UNIT_MAX_SPEED * pow(0.8, _tier)
	max_shield = CFG.UNIT_MAX_SHIELD * pow(1.5, _tier)
	max_hull = CFG.UNIT_MAX_HULL * pow(1.5, _tier)
	shield_regen_rate = CFG.UNIT_SHIELD_REGEN * pow(1.5, _tier)

	shield = max_shield
	hull = max_hull
	_sprite.self_modulate = unit_color

	# ---- 自动生成名字 ----
	class_name_cn = _get_class_name_cn()
	unit_name = _generate_ship_name()

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
		_create_weapon_sprite(i)


func _process(delta: float) -> void:
	_player_command_timer = max(0.0, _player_command_timer - delta)
	_update_cooldowns(delta)
	_update_skill_timers(delta)
	_update_shield(delta)
	UNIT_COMBAT.update_target(self)
	UNIT_COMBAT.update_turrets(self, delta)
	UNIT_COMBAT.update_combat(self, delta)
	UNIT_COMBAT.update_chase(self)
	UNIT_COMBAT.update_pd(self, delta)
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
	# 敌方减速 debuff 叠加计时
	var i := 0
	while i < _slow_debuffs.size():
		_slow_debuffs[i]["timer"] -= delta
		if _slow_debuffs[i]["timer"] <= 0:
			_slow_debuffs.remove_at(i)
		else:
			i += 1
	# 净化免疫倒计时
	if _debuff_immunity_timer > 0:
		_debuff_immunity_timer -= delta


func _update_shield(delta: float) -> void:
	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)


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

## 飞船名字前缀池
const SHIP_PREFIXES_CN: Array[String] = [
	"前锋", "勇士", "闪电", "风暴", "暗影", "烈焰", "冰霜",
	"雷霆", "利刃", "堡垒", "长空", "流星", "银河", "曙光",
	"破晓", "星辉", "疾风", "惊雷", "天火", "苍穹",
]
## 已用名字记录（避免重名）
static var _used_names: Array[String] = []

## 重置名字池（游戏重新开始时调用）
static func reset_name_pool() -> void:
	_used_names.clear()

func _generate_ship_name() -> String:
	var prefix = SHIP_PREFIXES_CN[randi() % SHIP_PREFIXES_CN.size()]
	var suffix = class_name_cn
	var name_candidate = prefix + suffix
	# 避免重名，加数字后缀
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
	# 先确保武器和目标有效，再访问目标属性
	if w == null or target == null or not is_instance_valid(target) or target.team == team:
		return  # 不攻击友军或目标无效

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

func take_damage(amount: float, source: Node = null) -> void:
	# 先处理伤害加成和减伤逻辑
	var final_damage = amount * _damage_taken_mult
	if source != null and source is Unit and source.team != team:
		# 这里可以添加反击、仇恨或联动效果
		pass

	if shield > 0.0:
		var remaining = final_damage - shield
		shield = max(0.0, shield - final_damage)
		if remaining > 0.0:
			hull = max(0.0, hull - remaining)
	else:
		hull = max(0.0, hull - final_damage)

	_shield_regen_delay = CFG.SHIELD_REGEN_DELAY
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
	"""纯 buff 技能直接释放；跃迁/减速有位置或目标参数的重载版本"""
	if index < 0 or index >= _skill_cooldowns.size():
		return
	if _skill_cooldowns[index] > 0.0:
		return

	match index:
		0:
			_speed_mult = CFG.SKILL_SPEED_MULT
			_skill_timers[0] = CFG.SKILL_DURATION
		1:
			_attack_speed_mult = CFG.SKILL_ATTACK_SPEED_MULT
			_skill_timers[1] = CFG.SKILL_DURATION
		2:
			_damage_taken_mult = CFG.SKILL_DAMAGE_TAKEN_MULT
			_skill_timers[2] = CFG.SKILL_DURATION
		3:
			# 跃迁：手动释放，用 jump_to_position
			pass
		4:
			# 减速：自动或手动释放，用 apply_slow_to_target
			pass
		5:
			# 净化：清除所有 debuff，获得免疫
			_slow_debuffs.clear()
			_slow_mult = 1.0
			_debuff_immunity_timer = CFG.SKILL_PURIFY_IMMUNITY_DURATION

	_skill_cooldowns[index] = CFG.SKILL_CD if index != 5 else CFG.SKILL_PURIFY_COOLDOWN


## 跃迁：向目标位置瞬移，最多 max_dist 像素
func jump_to_position(target_pos: Vector2, max_dist: float = CFG.SKILL_JUMP_MAX_DIST) -> void:
	if _skill_cooldowns[3] > 0.0:
		return
	var dir = (target_pos - global_position).normalized()
	var dist = min(global_position.distance_to(target_pos), max_dist)
	global_position += dir * dist
	_skill_cooldowns[3] = CFG.SKILL_CD


## 减速：对目标施加 50% 减速 debuff
func apply_slow_to_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_slow_debuff"):
		return
	if _skill_cooldowns[4] > 0.0:
		return
	var dist = global_position.distance_to(target.global_position)
	if dist > CFG.SKILL_SLOW_RANGE:
		return
	target.take_slow_debuff(CFG.SKILL_SLOW_DEBUFF_FACTOR, CFG.SKILL_SLOW_DEBUFF_DURATION)
	_skill_cooldowns[4] = CFG.SKILL_SLOW_COOLDOWN


## 被施加减速 debuff（叠加：每次新加一层，免疫期间忽略）
func take_slow_debuff(factor: float, duration: float) -> void:
	if _debuff_immunity_timer > 0:
		return
	_slow_debuffs.append({"factor": factor, "timer": duration})


## 获取当前减速 debuff 叠加后的总倍率
func get_slow_mult() -> float:
	if _slow_debuffs.size() == 0:
		return 1.0
	var mult := 1.0
	for d in _slow_debuffs:
		mult *= d["factor"]
	return mult


## 获取当前所有活跃 buff/debuff 信息（供 HUD 显示）
func get_active_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _skill_timers[0] > 0:
		result.append({"name": "加速", "desc": "速度+100%", "color": Color(0.2, 1.0, 0.3)})
	if _skill_timers[1] > 0:
		result.append({"name": "速射", "desc": "攻速+100%", "color": Color(1.0, 0.6, 0.2)})
	if _skill_timers[2] > 0:
		var dmg_pct = int((1.0 - CFG.SKILL_DAMAGE_TAKEN_MULT) * 100.0)
		result.append({"name": "减伤", "desc": "受伤-%d%%" % dmg_pct, "color": Color(0.2, 0.8, 1.0)})
	if _debuff_immunity_timer > 0:
		result.append({"name": "净化", "desc": "免疫debuff", "color": Color(0.3, 0.9, 0.9)})
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

	# 激光持续射线（从每个激光炮台指向目标）
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
			if w != null and w.weapon_type == Weapon.WeaponType.LASER and dist <= w.range * _weapon_range_mult:
				var start = _slot_offsets_scaled[i].rotated(_body.rotation)
				var end = _current_target.global_position - global_position
				# 外层光晕
				draw_line(start, end, lc1, 18.0)
				# 主光束
				draw_line(start, end, lc2, 6.0)
				# 核心亮线
				draw_line(start, end, lc3, 2.4)

	# PD 持续弹道（从每个 PD 炮台指向目标弹体）
	if _pd_has_target:
		var end = _pd_target_pos - global_position
		for i in range(slot_count):
			var w = _slot_weapons[i]
			if w != null and w.weapon_type == Weapon.WeaponType.PD:
				var start = _slot_offsets_scaled[i].rotated(_body.rotation)
				# 外层光晕
				draw_line(start, end, Color(0.15, 0.8, 0.5, 0.25), 5.0)
				# 主光束
				draw_line(start, end, Color(0.2, 1.0, 0.7, 0.6), 2.0)
				# 核心亮线
				draw_line(start, end, Color(0.5, 1.0, 0.8, 0.4), 0.8)

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


func _create_weapon_sprite(index: int) -> void:
	var ws = Sprite2D.new()
	ws.name = "Weapon" + str(index)
	ws.position = _slot_offsets_scaled[index]
	ws.texture = load("res://assets/weapon_launcher/Cannon.svg")
	ws.centered = true
	ws.scale = Vector2.ONE * _size_mult / 3.0
	_body.add_child(ws)
	_weapon_sprites.append(ws)


## 根据武器类型返回对应 SVG 纹理路径
const WEAPON_TEX_PATHS: Dictionary = {
	Weapon.WeaponType.BULLET: "res://assets/weapon_launcher/Cannon.svg",
	Weapon.WeaponType.LASER: "res://assets/weapon_launcher/Laser.svg",
	Weapon.WeaponType.MISSILE: "res://assets/weapon_launcher/MissileLauncher.svg",
	Weapon.WeaponType.PD: "res://assets/weapon_launcher/PD.svg",
}

## 刷新所有武器槽位的 Sprite2D 纹理（在外部赋值 _slot_weapons 后调用）
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
	_explicit_attack_target = target
	_is_attack_move = false
	_is_area_attack = false
	_is_orbit = false
	_current_target = target
	_player_command_timer = 0.5
	_player_move_command = false

func attack_area(center: Vector2, radius: float) -> void:
	_area_center = center
	_area_radius = radius
	_is_area_attack = true
	_is_attack_move = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	_player_command_timer = 0.5
	_player_move_command = false

func move_to(target_pos: Vector2) -> void:
	_target_position = target_pos
	_is_moving = true
	_is_attack_move = false
	_is_area_attack = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	_player_command_timer = 0.5
	_player_move_command = true

func orbit_target(target: Unit, custom_radius: float = -1.0) -> void:
	if target == null or not is_instance_valid(target) or target.hull <= 0:
		return
	_orbit_target_unit = target
	_orbit_position = target.global_position
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_current_target = target

func orbit_position(orbit_pos: Vector2, custom_radius: float = -1.0) -> void:
	_orbit_target_unit = null
	_orbit_position = orbit_pos
	_orbit_radius = custom_radius
	_is_orbit = true
	_is_moving = true
	_current_target = null
	_player_command_timer = 0.5

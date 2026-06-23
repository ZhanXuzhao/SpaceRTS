class_name Unit
extends Area2D

enum Team { BLUE, RED }
enum ShipClass { DRONE, FRIGATE, DESTROYER, CRUISER, BATTLESHIP }
enum AttackMode { FREE_FIRE, KEEP_DISTANCE, ORBIT_SHOOT }

const UNIT_COMBAT = preload("res://scripts/unit_combat.gd")
const UNIT_MOVEMENT = preload("res://scripts/unit_movement.gd")

@export var class_type: ShipClass = ShipClass.DRONE
@export var speed: float = GameConfig.UNIT_MAX_SPEED
@export var acceleration: float = GameConfig.UNIT_ACCELERATION
@export var mass: float = GameConfig.UNIT_MASS
@export var forward_acceleration: float = GameConfig.UNIT_FORWARD_ACCELERATION
@export var max_angular_speed: float = GameConfig.UNIT_MAX_ANGULAR_SPEED
@export var angular_acceleration: float = GameConfig.UNIT_ANGULAR_ACCELERATION
var velocity: Vector2
## �ɴ��ȼ� (0=���˻�, 1=������, ..., 4=ս�н�)
var _tier: int = 0
## �����˺����� (��1.2^_tier)
var _weapon_damage_mult: float = 1.0
## ������̱��� (��1.5^_tier)
var _weapon_range_mult: float = 1.0
## �������ţ�-1 = δ���飩
var control_group: int = -1

# ----- ����ϵͳ -----
var _skill_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # ����/����/����/ԾǨ/����/����
## �����Զ��ͷű�ǣ�Ĭ�Ͻ������Զ���
var _skill_auto: Array[bool] = [false, false, false, false, true, false] :
	set = _set_skill_auto
var _speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _damage_taken_mult: float = 1.0
var _slow_mult: float = 1.0
## ���Եз����� debuff��֧�ֵ��ӣ�
var _slow_debuffs: Array[Dictionary] = []  # ÿ��: {"factor": float, "timer": float}
var _skill_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## �������ߵ���ʱ
var _debuff_immunity_timer: float = 0.0

# ----- �������壨����3s / ��ȴ2s�����˻�~ս�н�����ʱ��+0~40%��-----
var _laser_cycle_timer: float = 0.0  # ��ʼ��������
var _laser_attack_duration: float = GameConfig.LASER_ATTACK_DURATION  # �� _ready �и��ݴ��ͼ���

## �ߴ籶�� (��1.5^_tier)
var _size_mult: float = 1.0
## ���ź�Ĳ�λƫ��
var _slot_offsets_scaled: Array[Vector2] = []
@export var unit_color: Color = Color(0.2, 0.6, 1.0)
@export var team: Team = Team.BLUE

# ----- ���� & �ṹ -----
@export var max_shield: float = GameConfig.UNIT_MAX_SHIELD
@export var max_hull: float = GameConfig.UNIT_MAX_HULL
@export var shield_regen_rate: float = GameConfig.UNIT_SHIELD_REGEN

var shield: float
var hull: float
var _shield_regen_delay: float = 0.0

@export var slot_count: int = GameConfig.UNIT_SLOT_COUNT

## �Ƿ�ѡ��
## �ɴ����֣���ʼ��ʱ�Զ����ɣ�
var unit_name: String

## �ɴ����������ģ�
var class_name_cn: String

## �Ƿ�ѡ��
var is_selected: bool = false : set = _set_is_selected

var all_units: Array[Unit] = []
var attack_mode: AttackMode = AttackMode.FREE_FIRE

var _target_position: Vector2
var _is_moving: bool = false
var _current_target: Unit = null

# ----- ������λ -----
var _slot_weapons: Array = []
var _slot_angles: Array[float] = []
var _slot_cooldowns: Array[float] = []
var _weapon_sprites: Array[Sprite2D] = []

const SLOT_OFFSETS: Array[Vector2] = [
	# �ɴ����಼�ã��ϲ�Ϊ��Y���²�Ϊ��Y��
	Vector2(25, -35),    # 0: ��ǰ1
	Vector2(25, 35),     # 1: ��ǰ1
	Vector2(10, -40),    # 2: ��ǰ2
	Vector2(10, 40),     # 3: ��ǰ2
	Vector2(-5, -40),    # 4: ����1
	Vector2(-5, 40),     # 5: ����1
	Vector2(-20, -35),   # 6: �Ϻ�1
	Vector2(-20, 35),    # 7: �º�1
	Vector2(32, -20),    # 8: ��ǰ3
	Vector2(32, 20),     # 9: ��ǰ3
	Vector2(-32, -20),   # 10: �Ϻ�2
	Vector2(-32, 20),    # 11: �º�2
	Vector2(-10, -25),   # 12: ����2
	Vector2(-10, 25),    # 13: ����2
	Vector2(0, -30),     # 14: ����3
	Vector2(0, 30),      # 15: ����3
]

# ----- ����ָ����� -----
var _explicit_attack_target: Unit = null
var attack_move_destination: Vector2
var _is_attack_move: bool = false
## ���򹥻���A+�յص�أ�
var _is_area_attack: bool = false
var _area_center: Vector2
var _area_radius: float = 500.0
var saved_move_target: Vector2
var has_saved_move: bool = false
## ���ָ���ʱ�� >0 ʱ AI ��������Ϊ
var _player_command_timer: float = 0.0
## ����´����ƶ�ָ��ڵ���Ŀ�ĵ�ǰ��ֹ�Զ����������ƶ���
var _player_move_command: bool = false

# PD ��������
var _pd_target_pos: Vector2
var _pd_has_target: bool = false

# ----- ���� -----
var _is_orbit: bool = false
var _orbit_target_unit: Unit = null
var _orbit_position: Vector2 = Vector2.ZERO  # ���滷��Ŀ���
var _orbit_angle: float = 0.0
## ���Ʒ���1 = ��ʱ�룬-1 = ˳ʱ�루������λ��ȷ����
var _orbit_direction: float = 1.0
var _orbit_radius: float = -1.0  # >=0 ʱ����Ĭ�ϰ뾶

# ----- ���˻��֣�ս�н�ר����-----
var drone_bay: int = 10
var home_battleship: Unit = null  # ���˻�����ĸ��
var deployed_drones: Array[Unit] = []
var max_deployed_drones: int = 4
var drone_launch_timer: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _body: Node2D = $Body

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")


func _ready() -> void:
	print("DEBUG: Unit._ready loaded", self, self.get_script())
	# ---- ���ݷɴ��ȼ��������� ----
	_tier = _ship_class_tier(class_type)
	_size_mult = pow(1.5, _tier)
	_weapon_damage_mult = pow(1.2, _tier)
	_laser_attack_duration = GameConfig.LASER_ATTACK_DURATION * (1.0 + _tier * GameConfig.LASER_CLASS_BONUS)
	_weapon_range_mult = pow(1.5, _tier)
	# ���ݴ�������Ĭ�Ϲ���ģʽ
	match class_type:
		ShipClass.DRONE, ShipClass.FRIGATE:
			attack_mode = AttackMode.ORBIT_SHOOT
		ShipClass.DESTROYER:
			attack_mode = AttackMode.KEEP_DISTANCE
		_:
			attack_mode = AttackMode.FREE_FIRE

		# ��λ���������˻�2 ������2 ����4 Ѳ��6 ս�н�8
	match class_type:
		ShipClass.DRONE:
			slot_count = 2
		ShipClass.CRUISER:
			slot_count = 6
		ShipClass.BATTLESHIP:
			slot_count = 8
		_:
			slot_count = int(pow(2, _tier))
	speed = GameConfig.UNIT_MAX_SPEED * pow(0.8, _tier)
	max_shield = GameConfig.UNIT_MAX_SHIELD * pow(1.5, _tier)
	max_hull = GameConfig.UNIT_MAX_HULL * pow(1.5, _tier)
	shield_regen_rate = GameConfig.UNIT_SHIELD_REGEN * pow(1.5, _tier)

	shield = max_shield
	hull = max_hull
	_sprite.self_modulate = unit_color

	# ---- �Զ��������� ----
	class_name_cn = _get_class_name_cn()
	unit_name = _generate_ship_name()

	# ---- �ߴ����� ----
	_sprite.scale = Vector2(_size_mult, _size_mult)
	var shape = RectangleShape2D.new()
	shape.size = Vector2(64, 64) * _size_mult
	collision_shape.shape = shape

	# ---- ���Ų�λƫ�� ----
	_slot_offsets_scaled.resize(slot_count)
	for i in range(slot_count):
		if i < SLOT_OFFSETS.size():
			_slot_offsets_scaled[i] = SLOT_OFFSETS[i] * _size_mult
		else:
			# ���� 8 ������λ�õĲ�λ����Բ�ܾ��ȷֲ�
			var angle = (i - SLOT_OFFSETS.size()) * TAU / (slot_count - SLOT_OFFSETS.size())
			var radius = 50.0 * _size_mult
			_slot_offsets_scaled[i] = Vector2(cos(angle), sin(angle)) * radius

	# ---- ��ʼ��������λ ----
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
	# �з����� debuff ���Ӽ�ʱ
	var i := 0
	while i < _slow_debuffs.size():
		_slow_debuffs[i]["timer"] -= delta
		if _slow_debuffs[i]["timer"] <= 0:
			_slow_debuffs.remove_at(i)
		else:
			i += 1
	# �������ߵ���ʱ
	if _debuff_immunity_timer > 0:
		_debuff_immunity_timer -= delta


func _update_shield(delta: float) -> void:
	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)


func _update_orbit(delta: float) -> void:
	if _is_orbit:
		# ÿ֡��¼Ŀ��λ�ã�����ʱ�Զ�תΪ���������ص�
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
			dist = 500.0  # ֻ�� PD ʱĬ�� 500
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
		ShipClass.DRONE: return "���˻�"
		ShipClass.FRIGATE: return "������"
		ShipClass.DESTROYER: return "����"
		ShipClass.CRUISER: return "Ѳ��"
		ShipClass.BATTLESHIP: return "ս�н�"
	return "δ֪"

func _get_class_name_cn() -> String:
	return get_class_name_cn(class_type)

## �ɴ�����ǰ׺��
const SHIP_PREFIXES_CN: Array[String] = [
	"ǰ��", "��ʿ", "����", "�籩", "��Ӱ", "����", "��˪",
	"����", "����", "����", "����", "����", "����", "���",
	"����", "�ǻ�", "����", "����", "���", "���",
]
## �������ּ�¼������������
static var _used_names: Array[String] = []

## �������ֳأ���Ϸ���¿�ʼʱ���ã�
static func reset_name_pool() -> void:
	_used_names.clear()

func _generate_ship_name() -> String:
	var prefix = SHIP_PREFIXES_CN[randi() % SHIP_PREFIXES_CN.size()]
	var suffix = class_name_cn
	var name_candidate = prefix + suffix
	# ���������������ֺ�׺
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
	"""����󲽳���ת current �Ƕȵ� target �Ƕȣ����ȣ�"""
	var diff = fmod(target - current + PI, TAU) - PI
	if abs(diff) < 0.001:
		return target
	var step = clamp(abs(diff), -max_delta, max_delta) * sign(diff)
	return current + step


func _fire_slot(slot_index: int, target: Unit) -> void:
	var w = _slot_weapons[slot_index]
	# ��ȷ��������Ŀ����Ч���ٷ���Ŀ������
	if w == null or target == null or not is_instance_valid(target) or target.team == team:
		return  # �������Ѿ���Ŀ����Ч

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

	# ��������ֵ��PD�����ģ�
	var proj_hp := 0.0
	if w.weapon_type == Weapon.WeaponType.BULLET:
		proj_hp = GameConfig.BULLET_HP
	elif w.weapon_type == Weapon.WeaponType.MISSILE:
		proj_hp = GameConfig.MISSILE_HP

	# ���� = ��Ч��� / �����ٶȣ�ȷ���ӵ��ܷɵ������̣�
	var effective_range = w.range * _weapon_range_mult
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
	# �ȴ����˺��ӳɺͼ����߼�
	var final_damage = amount * _damage_taken_mult
	if source != null and source is Unit and source.team != team:
		# ����������ӷ�������޻�����Ч��
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
		# Ŀ������ʱ����״̬
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
	"""�� buff ����ֱ���ͷţ�ԾǨ/������λ�û�Ŀ����������ذ汾"""
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
			# ԾǨ���ֶ��ͷţ��� jump_to_position
			pass
		4:
			# ���٣��Զ����ֶ��ͷţ��� apply_slow_to_target
			pass
		5:
			# ������������� debuff���������
			_slow_debuffs.clear()
			_slow_mult = 1.0
			_debuff_immunity_timer = GameConfig.SKILL_PURIFY_IMMUNITY_DURATION

	_skill_cooldowns[index] = GameConfig.SKILL_CD if index != 5 else GameConfig.SKILL_PURIFY_COOLDOWN


## ԾǨ����Ŀ��λ��˲�ƣ���� max_dist ����
func jump_to_position(target_pos: Vector2, max_dist: float = GameConfig.SKILL_JUMP_MAX_DIST) -> void:
	if _skill_cooldowns[3] > 0.0:
		return
	var dir = (target_pos - global_position).normalized()
	var dist = min(global_position.distance_to(target_pos), max_dist)
	global_position += dir * dist
	_skill_cooldowns[3] = GameConfig.SKILL_CD


## ���٣���Ŀ��ʩ�� 50% ���� debuff
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


## ��ʩ�Ӽ��� debuff�����ӣ�ÿ���¼�һ�㣬�����ڼ���ԣ�
func take_slow_debuff(factor: float, duration: float) -> void:
	if _debuff_immunity_timer > 0:
		return
	_slow_debuffs.append({"factor": factor, "timer": duration})


## ��ȡ��ǰ���� debuff ���Ӻ���ܱ���
func get_slow_mult() -> float:
	if _slow_debuffs.size() == 0:
		return 1.0
	var mult := 1.0
	for d in _slow_debuffs:
		mult *= d["factor"]
	return mult


## ��ȡ��ǰ���л�Ծ buff/debuff ��Ϣ���� HUD ��ʾ��
func get_active_buffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _skill_timers[0] > 0:
		result.append({"name": "����", "desc": "�ٶ�+100%", "color": Color(0.2, 1.0, 0.3)})
	if _skill_timers[1] > 0:
		result.append({"name": "����", "desc": "����+100%", "color": Color(1.0, 0.6, 0.2)})
	if _skill_timers[2] > 0:
		var dmg_pct = int((1.0 - GameConfig.SKILL_DAMAGE_TAKEN_MULT) * 100.0)
		result.append({"name": "����", "desc": "����-%d%%" % dmg_pct, "color": Color(0.2, 0.8, 1.0)})
	if _debuff_immunity_timer > 0:
		result.append({"name": "����", "desc": "����debuff", "color": Color(0.3, 0.9, 0.9)})
	if _slow_debuffs.size() > 0:
		var count = _slow_debuffs.size()
		var slow_pct = int((1.0 - get_slow_mult()) * 100.0)
		var label = "����" if count == 1 else "���� x%d" % count
		result.append({"name": label, "desc": "�ٶ�-%d%%" % slow_pct, "color": Color(1.0, 0.3, 0.3)})
	return result

func _set_is_selected(value: bool) -> void:
	is_selected = value
	_sprite.self_modulate = unit_color
	queue_redraw()

func _draw() -> void:
	# ---- β�� ----
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

	# ---- ���ƹ켣����ѡ��ʱ���ƣ� ---- 
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
		# ����ָʾ��ͷ
		var arrow_angle = deg_to_rad(_orbit_angle)
		var arrow_pos = center + Vector2(cos(arrow_angle), sin(arrow_angle)) * radius
		draw_circle(arrow_pos, 3.0, Color(0.2, 1.0, 0.5, 0.5))
		# ָ��Ŀ�����ĵ�����
		draw_line(Vector2.ZERO, center, Color(0.2, 1.0, 0.5, 0.1), 1.0)

	# ---- Buff/Debuff ��ʾ����λ�Ҳ���ϵ��£�----
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

	# ����������ߣ���ÿ��������ָ̨��Ŀ�꣩
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
				# ������
				draw_line(start, end, lc1, 18.0)
				# ������
				draw_line(start, end, lc2, 6.0)
				# ��������
				draw_line(start, end, lc3, 2.4)

	# PD ������������ÿ�� PD ��ָ̨��Ŀ�굯�壩
	if _pd_has_target:
		var end = _pd_target_pos - global_position
		for i in range(slot_count):
			var w = _slot_weapons[i]
			if w != null and w.weapon_type == Weapon.WeaponType.PD:
				var start = _slot_offsets_scaled[i].rotated(_body.rotation)
				# ������
				draw_line(start, end, Color(0.15, 0.8, 0.5, 0.25), 5.0)
				# ������
				draw_line(start, end, Color(0.2, 1.0, 0.7, 0.6), 2.0)
				# ��������
				draw_line(start, end, Color(0.5, 1.0, 0.8, 0.4), 0.8)

	# ---- ������ & �ṹ�� ---- 
	var bar_width = 64.0 * _size_mult
	var bar_half = bar_width / 2.0
	var bar_top = -collision_shape.shape.size.y * 0.6  # ѡ�п򶥲� = -size��1.2/2

	# ����������ɫ���Ϸ���
	if shield < max_shield:
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width, 4.0), Color(0.15, 0.15, 0.2, 0.8), true)
		draw_rect(Rect2(-bar_half, bar_top - 34.0, bar_width * shield / max_shield, 4.0), Color(0.2, 0.5, 1.0, 0.9), true)

	# �ṹ������ɫ����ɫ����ɫ��
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

	# ---- ��Ӻţ���Ѫ����ࣩ ----
	if control_group >= 0:
		var font = ThemeDB.fallback_font
		font.draw_string(get_canvas_item(), Vector2(-bar_half - 22, bar_top - 34 + 8), str(control_group),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.6))

	# ѡ�б��
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


## �����������ͷ��ض�Ӧ SVG ����·��
const WEAPON_TEX_PATHS: Dictionary = {
	Weapon.WeaponType.BULLET: "res://assets/weapon_launcher/Cannon.svg",
	Weapon.WeaponType.LASER: "res://assets/weapon_launcher/Laser.svg",
	Weapon.WeaponType.MISSILE: "res://assets/weapon_launcher/MissileLauncher.svg",
	Weapon.WeaponType.PD: "res://assets/weapon_launcher/PD.svg",
}

## ˢ������������λ�� Sprite2D ���������ⲿ��ֵ _slot_weapons ����ã�
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

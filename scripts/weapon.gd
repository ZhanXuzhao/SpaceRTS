class_name Weapon
extends Resource

enum WeaponType { BULLET, MISSILE, LASER, PD }

@export var weapon_type: WeaponType = WeaponType.BULLET
@export_range(0.0, 200.0, 0.5, "or_greater") var damage: float = 10.0
@export_range(0.0, 5000.0, 10.0) var range: float = 200.0
@export_range(0.0, 10.0, 0.05) var cooldown: float = 0.5
@export_range(0.0, 5000.0, 50.0) var projectile_speed: float = 500.0
@export var projectile_color: Color = Color.YELLOW
@export_range(0.5, 30.0, 0.5) var projectile_size: float = 4.0
@export var is_homing: bool = false
@export_range(0.0, 2000.0, 10.0) var turn_speed: float = 360.0



static func create_bullet() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.BULLET
	w.damage = GameConfig.BULLET_DAMAGE
	w.range = GameConfig.BULLET_RANGE
	w.cooldown = GameConfig.BULLET_COOLDOWN
	w.projectile_speed = GameConfig.BULLET_MAX_SPEED
	w.projectile_color = Color(1.0, 0.85, 0.2)
	w.projectile_size = GameConfig.BULLET_SIZE
	w.is_homing = false
	w.turn_speed = GameConfig.BULLET_TURN_SPEED
	return w


static func create_missile() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.MISSILE
	w.damage = GameConfig.MISSILE_DAMAGE
	w.range = GameConfig.MISSILE_RANGE
	w.cooldown = GameConfig.MISSILE_COOLDOWN
	w.projectile_speed = GameConfig.MISSILE_MAX_SPEED
	w.projectile_color = Color(1.0, 0.3, 0.1)
	w.projectile_size = GameConfig.MISSILE_SIZE
	w.is_homing = GameConfig.MISSILE_HOMING
	w.turn_speed = GameConfig.MISSILE_TURN_SPEED
	return w


static func create_laser() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.LASER
	w.damage = GameConfig.LASER_DAMAGE
	w.range = GameConfig.LASER_RANGE
	w.cooldown = GameConfig.LASER_COOLDOWN
	w.projectile_color = Color(1.0, 0.2, 0.2)
	w.turn_speed = GameConfig.LASER_TURN_SPEED
	return w


static func create_pd() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.PD
	w.damage = GameConfig.PD_DAMAGE
	w.range = GameConfig.PD_RANGE
	w.cooldown = GameConfig.PD_COOLDOWN
	w.projectile_color = Color(0.2, 1.0, 0.7)
	w.turn_speed = GameConfig.PD_TURN_SPEED
	return w


func get_display_name() -> String:
	match weapon_type:
		WeaponType.BULLET: return "子弹"
		WeaponType.MISSILE: return "导弹"
		WeaponType.LASER: return "激光"
		WeaponType.PD: return "PD近防"
	return "未知"


static func create_random() -> Weapon:
	match randi() % 4:
		0: return create_bullet()
		1: return create_missile()
		2: return create_laser()
		3: return create_pd()
	return create_bullet()

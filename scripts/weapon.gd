class_name Weapon
extends Resource

enum WeaponType { BULLET, MISSILE, LASER, PD }

@export var weapon_type: WeaponType = WeaponType.BULLET
@export var damage: float = 10.0
@export var range: float = 200.0
@export var cooldown: float = 0.5
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color.YELLOW
@export var projectile_size: float = 4.0
@export var is_homing: bool = false
@export var turn_speed: float = 360.0

const CFG = preload("res://scripts/game_config.gd")


static func create_bullet() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.BULLET
	w.damage = CFG.BULLET_DAMAGE
	w.range = CFG.BULLET_RANGE
	w.cooldown = CFG.BULLET_COOLDOWN
	w.projectile_speed = CFG.BULLET_MAX_SPEED
	w.projectile_color = Color(1.0, 0.85, 0.2)
	w.projectile_size = CFG.BULLET_SIZE
	w.is_homing = false
	w.turn_speed = CFG.BULLET_TURN_SPEED
	return w


static func create_missile() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.MISSILE
	w.damage = CFG.MISSILE_DAMAGE
	w.range = CFG.MISSILE_RANGE
	w.cooldown = CFG.MISSILE_COOLDOWN
	w.projectile_speed = CFG.MISSILE_MAX_SPEED
	w.projectile_color = Color(1.0, 0.3, 0.1)
	w.projectile_size = CFG.MISSILE_SIZE
	w.is_homing = CFG.MISSILE_HOMING
	w.turn_speed = CFG.MISSILE_TURN_SPEED
	return w


static func create_laser() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.LASER
	w.damage = CFG.LASER_DAMAGE
	w.range = CFG.LASER_RANGE
	w.cooldown = CFG.LASER_COOLDOWN
	w.projectile_color = Color(1.0, 0.2, 0.2)
	w.turn_speed = CFG.LASER_TURN_SPEED
	return w


static func create_pd() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.PD
	w.damage = CFG.PD_DAMAGE
	w.range = CFG.PD_RANGE
	w.cooldown = CFG.PD_COOLDOWN
	w.projectile_color = Color(0.2, 1.0, 0.7)
	w.turn_speed = CFG.PD_TURN_SPEED
	return w


func get_display_name() -> String:
	match weapon_type:
		WeaponType.BULLET: return "子弹"
		WeaponType.MISSILE: return "导弹"
		WeaponType.LASER: return "激光"
		WeaponType.PD: return "PD近防"
	return "未知"

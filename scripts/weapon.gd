class_name Weapon
extends Resource

enum WeaponType { BULLET, MISSILE, LASER, PD }

## 武器类型
@export var weapon_type: WeaponType = WeaponType.BULLET

## 每次攻击伤害
@export var damage: float = 10.0

## 攻击范围（像素）
@export var range: float = 200.0

## 攻击冷却（秒）
@export var cooldown: float = 0.5

## 弹体飞行速度（子弹/导弹用；激光忽略）
@export var projectile_speed: float = 500.0

## 弹体颜色
@export var projectile_color: Color = Color.YELLOW

## 弹体大小（半径）
@export var projectile_size: float = 4.0

## 是否追踪（导弹为 true）
@export var is_homing: bool = false

## 炮塔转向速度（度/秒）
@export var turn_speed: float = 360.0


## 工厂方法：创建预设武器

static func create_bullet() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.BULLET
	w.damage = 8.0
	w.range = 220.0
	w.cooldown = 0.4
	w.projectile_speed = 600.0
	w.projectile_color = Color(1.0, 0.85, 0.2)  # 金黄色
	w.projectile_size = 3.0
	w.is_homing = false
	w.turn_speed = 540.0  # 轻武器转向快
	return w


static func create_missile() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.MISSILE
	w.damage = 25.0
	w.range = 300.0
	w.cooldown = 1.2
	w.projectile_speed = 250.0
	w.projectile_color = Color(1.0, 0.3, 0.1)  # 橙红色
	w.projectile_size = 6.0
	w.is_homing = true
	w.turn_speed = 180.0  # 重武器转向慢
	return w


static func create_laser() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.LASER
	w.damage = 5.0
	w.range = 180.0
	w.cooldown = 0.15  # 快速攻击
	w.projectile_color = Color(1.0, 0.2, 0.2)  # 红色激光
	w.turn_speed = 720.0  # 激光炮塔极快
	return w


static func create_pd() -> Weapon:
	var w = Weapon.new()
	w.weapon_type = WeaponType.PD
	w.damage = 1.0  # 对飞船极低伤害
	w.range = 160.0  # 短距拦截
	w.cooldown = 0.2  # 极快射速
	w.projectile_color = Color(0.2, 1.0, 0.7)  # 青绿色
	w.turn_speed = 800.0  # 极快转向
	return w


func get_display_name() -> String:
	match weapon_type:
		WeaponType.BULLET: return "子弹"
		WeaponType.MISSILE: return "导弹"
		WeaponType.LASER: return "激光"
		WeaponType.PD: return "PD近防"
	return "未知"

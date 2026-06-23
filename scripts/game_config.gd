# game_config.gd
# 所有游戏数值集中管理
extends Node

# ===== 飞船 =====
const UNIT_MAX_SPEED := 500.0
const UNIT_ACCELERATION := 150.0
const UNIT_MASS := 10.0
const UNIT_MAX_ANGULAR_SPEED := 30.0     # °/s
const UNIT_ANGULAR_ACCELERATION := 60.0   # °/s²
const UNIT_FORWARD_ACCELERATION := 50.0   # px/s²
const UNIT_MAX_SHIELD := 1000.0
const UNIT_MAX_HULL := 1000.0
const UNIT_SHIELD_REGEN := 8.0    # /s
const UNIT_SHIELD_DELAY := 2.0    # 受击后恢复等待
const SHIELD_REGEN_DELAY := UNIT_SHIELD_DELAY
const UNIT_SLOT_COUNT := 4

# ===== 子弹 =====
const BULLET_DAMAGE := 8.0
const BULLET_RANGE := 1000.0
const BULLET_COOLDOWN := 0.4
const BULLET_MAX_SPEED := 1500.0
const BULLET_ACCELERATION := 3000.0
const BULLET_MASS := 0.5
const BULLET_SIZE := 3.0
const BULLET_TURN_SPEED := 540.0
const BULLET_HP := 2.0

# ===== 导弹 =====
const MISSILE_DAMAGE := 50.0
const MISSILE_RANGE := 1000.0
const MISSILE_COOLDOWN := 1.2
const MISSILE_MAX_SPEED := 400.0
const MISSILE_ACCELERATION := 500.0
const MISSILE_MASS := 2.0
const MISSILE_SIZE := 6.0
const MISSILE_TURN_SPEED := 180.0
const MISSILE_HP := 15.0
const MISSILE_HOMING := true

# ===== 激光 =====
const LASER_DAMAGE := 5.0
const LASER_RANGE := 1000.0
const LASER_COOLDOWN := 0.15
const LASER_TURN_SPEED := 720.0
# 激光脉冲参数
const LASER_ATTACK_DURATION := 2.0       # 每次攻击持续秒数
const LASER_COOLDOWN_DURATION := 2.0     # 每次冷却秒数
const LASER_HITS_PER_SECOND := 3.0       # 攻击时每秒命中次数
const LASER_CLASS_BONUS := 0.1           # 每级船型攻击时长加成比例

# ===== PD近防 =====
const PD_DAMAGE := 1.0
const PD_RANGE := 1000.0
const PD_COOLDOWN := 0.2
const PD_TURN_SPEED := 800.0

# ===== 弹体通用 =====
const PROJECTILE_LIFETIME := 3.0

# ===== 无人机 =====
const DRONE_ORBIT_RADIUS := 500.0

# ===== 技能 =====
const SKILL_SLOW_FACTOR := 0.5
const SKILL_SLOW_DURATION := 10.0

# ===== 相机 =====
const SCROLL_SPEED := 1000.0

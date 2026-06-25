# game_config.gd
# 所有游戏数值集中管理
extends Node

# ===== 飞船 =====
const UNIT_MAX_SPEED := 500.0          # 无人机最大速度 px/s
const DRONE_BASE_MASS := 10.0          # 无人机质量（质量 = base × 尺寸³）
const DRONE_ACCEL_TIME := 0.5         # 无人机 0→max 加速时间（秒）
const DRONE_TURN_SPEED := 360.0         # 无人机转向速度 °/s
const UNIT_MAX_SHIELD := 500.0
const UNIT_MAX_HULL := 500.0
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
const MISSILE_COOLDOWN := 2.0
const MISSILE_MAX_SPEED := 400.0
const MISSILE_ACCELERATION := 500.0
const MISSILE_MASS := 2.0
const MISSILE_SIZE := 6.0
const MISSILE_TURN_SPEED := 180.0
const MISSILE_HP := 15.0
const MISSILE_HOMING := true
const MISSILE_EXPLOSION_RADIUS := 300.0

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
const PD_DAMAGE := 5.0
const PD_RANGE := 1000.0
const PD_COOLDOWN := 0.25
const PD_TURN_SPEED := 800.0

# ===== 弹体通用 =====
const PROJECTILE_LIFETIME := 3.0

# ===== 无人机 =====
const DRONE_ORBIT_RADIUS := 500.0
## 默认环绕半径 = 最小射程进攻型武器射程 × 此比例
const DEFAULT_ORBIT_RADIUS_RATIO := 0.80

# ===== 技能 =====
# 通用
const SKILL_CD := 2.0
const SKILL_DURATION := 10.0

# 加速
const SKILL_SPEED_MULT := 2.0

# 速射
const SKILL_ATTACK_SPEED_MULT := 5

# 减伤（0.1 = 减伤90%，承受10%伤害）
const SKILL_DAMAGE_TAKEN_MULT := 0.1

# 跃迁
const SKILL_JUMP_MAX_DIST := 3000.0

# 减速（自身光环）
const SKILL_SLOW_RANGE := 1500.0
const SKILL_SLOW_COOLDOWN := 5.0
const SKILL_SLOW_DEBUFF_FACTOR := 0.5
const SKILL_SLOW_DEBUFF_DURATION := 5.0

# 净化
const SKILL_PURIFY_COOLDOWN := 5.0
const SKILL_PURIFY_IMMUNITY_DURATION := 5.0

# ===== 地图边界 =====
## 地图中心点（世界坐标原点）
const MAP_CENTER := Vector2(0, 0)
## 地图安全半径（px），超出后单位每秒受最大生命值百分比伤害
const MAP_RADIUS := 13000.0
## 边界外每秒损失最大生命值比例
const MAP_BORDER_DAMAGE_PCT := 0.05

# ===== 相机 =====
const SCROLL_SPEED := 1000.0

# ===== 武器配置 =====
## 武器类型常量（供 WEAPON_CONFIGS 使用）
const WT_BULLET := 1   # 子弹
const WT_MISSILE := 2  # 导弹
const WT_LASER := 3    # 激光
const WT_PD := 4       # PD近防
const WT_RANDOM := -1  # 随机

## 武器配置：每个船型的多组配置，初始化时随机选择一组
## 数组下标 = 第几对插槽，值 = 武器类型 (WT_RANDOM / WT_MISSILE / WT_BULLET / WT_LASER / WT_PD)
## 键 = ShipClass 枚举值 (0=DRONE, 1=FRIGATE, 2=DESTROYER, 3=CRUISER, 4=BATTLESHIP)
## 例如 [-1] 表示无人机1对插槽随机
##     [[1,2], [2,3]] 表示驱逐舰有2组配置可选
const WEAPON_CONFIGS := {
	0: [[1]],                    # DRONE: 1对
	1: [[1, -1]],                # FRIGATE: 2对
	2: [[1, -1]],                # DESTROYER: 2对
	3: [[1, -1, -1]],            # CRUISER: 3对
	4: [[1, 1, 1, 11]],        # BATTLESHIP: 4对
}

# ===== 矿物 & 经济 =====
const MINERAL_FIELD_AMOUNT := 15000       # 每片矿的总储量
const MINERAL_FIELD_COUNT := 15           # 每阵营初始矿物场数量
const MINERAL_FIELD_RADIUS := 60.0        # 矿场视觉/碰撞半径
const MINER_CARGO_CAPACITY := 100         # 采矿船单次采集量
const MINER_MINE_RATE := 10.0             # 每秒采集速度
const MINER_DEPOSIT_RANGE := 150.0        # 回矿场卸货距离
const MINER_SCAN_RANGE := 2000.0          # 采矿船搜索矿物半径
const MINER_SPEED := 350.0                # 采矿船速度
const MINER_MASS := 5.0                   # 采矿船质量

# ===== 建筑 =====
const BUILDING_MAX_HULL := 2000.0
const BUILDING_MAX_SHIELD := 3000.0
const BUILDING_SHIELD_REGEN := 5.0
const BUILDING_SHIELD_DELAY := 3.0
const BUILDING_SIZE := 80.0               # 建筑碰撞/视觉尺寸

# ===== 移动 =====
## 队列中非末位移动指令的到达判定距离（px），大于此值算到达，减少加减速时间
const QUEUE_MOVE_ARRIVAL_DISTANCE := 300.0
## 部署建筑时移动终点距部署点的距离（px），到达即部署
const DEPLOY_ARRIVAL_DISTANCE := 0.0

## 阵型基础间距（px），乘以平均尺寸系数
const FORMATION_BASE_SPACING := 100.0

## 船坞造舰价格（矿物）
const SHIPYARD_COST_DRONE := 50
const SHIPYARD_COST_FRIGATE := 100
const SHIPYARD_COST_DESTROYER := 200
const SHIPYARD_COST_CRUISER := 400
const SHIPYARD_COST_BATTLESHIP := 800
const SHIPYARD_COST_MINER := 100
## 船坞造舰时间（秒）
const SHIPYARD_TIME_DRONE := 3.0
const SHIPYARD_TIME_FRIGATE := 5.0
const SHIPYARD_TIME_DESTROYER := 8.0
const SHIPYARD_TIME_CRUISER := 12.0
const SHIPYARD_TIME_BATTLESHIP := 20.0
const SHIPYARD_TIME_MINER := 4.0

# ===== 部署建筑 =====
const DEPLOY_COST_SHIPYARD := 500      # 部署船厂消耗矿物
const DEPLOY_COST_MINE := 300          # 部署矿场消耗矿物
const DEPLOY_DURATION := 10.0          # 部署时间（秒）
const DEPLOY_RANGE := 1000.0            # 部署施法范围（px）

# ===== 初始经济 =====
const INITIAL_MINERALS := 9000.0          # 每阵营初始矿物数量

# ===== 阵营配置 =====
## 二维数组：[[随机船, 护卫舰, 驱逐舰, 巡洋舰, 战列舰], ...]
## a.length = 阵营数量，a[0] = 玩家阵营，其余为AI阵营
static var player = [0, 0, 10, 0, 0]
static var f0 = [10, 0, 0, 1, 0]
static var f1 = [0, 2, 2, 2, 1]
static var f2 = [0, 2, 4, 2, 1]
static var f3 = [0, 2, 2, 4, 1]
static var f4 = [0, 2, 2, 2, 4]
# static var faction_config: Array = [player,f0,f0,f0,f0,f0]
static var faction_config: Array = [player,f0]

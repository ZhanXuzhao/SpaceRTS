class_name Building
extends Area2D

## 建筑类型
enum BuildingType { MINE, SHIPYARD }

## 所有建筑引用（供单位和 AI 索敌用）
static var all_buildings: Array[Building] = []

@export var building_type: BuildingType = BuildingType.MINE
## 所属阵营
var team: String = ""
## 阵营颜色
var building_color: Color = Color.WHITE
## 当前结构值
var hull: float = GameConfig.BUILDING_MAX_HULL
var max_hull: float = GameConfig.BUILDING_MAX_HULL

# ----- 护盾系统 -----
var shield: float = GameConfig.BUILDING_MAX_SHIELD
var max_shield: float = GameConfig.BUILDING_MAX_SHIELD
var shield_regen_rate: float = GameConfig.BUILDING_SHIELD_REGEN
var _shield_regen_delay: float = 0.0

# ----- 部署状态 -----
## 是否正在部署中（HP/护盾从0逐渐增长到满）
var _is_deploying: bool = false
## 部署剩余时间（秒）
var _deploy_timer: float = 0.0
## 部署总时长
var _deploy_duration: float = GameConfig.DEPLOY_DURATION

## 自增 ID，用于区分多个建筑
var building_id: int = 0

# ----- 矿场专用 -----
## 本矿场储存的矿物总量（采矿船卸货到这里）
var stored_minerals: float = 0.0
## 矿场矿物容量上限
var max_stored_minerals: float = 99999

# ----- 船坞专用 -----
## 战斗船集结点
var rally_point: Vector2 = Vector2.ZERO
var has_rally_point: bool = false
## 采矿船集结点（独立，不同颜色）
var miner_rally_point: Vector2 = Vector2.ZERO
var has_miner_rally_point: bool = false
## 生产队列: [{ "type": ShipClass or "miner", "time": float, "total": float, "cost": int }]
var _production_queue: Array[Dictionary] = []
## 正在生产
var _is_producing: bool = false
var _production_timer: float = 0.0

signal mineral_deposited(team_name: String, amount: float)
signal ship_produced(team_name: String, ship_type, building)

@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _body: Node2D = $Body
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


var _is_selected: bool = false

func _ready() -> void:
	# 注册到全局建筑列表
	all_buildings.append(self)

	shield = max_shield
	hull = max_hull
	_sprite.self_modulate = building_color
	# 根据建筑类型切换纹理
	if building_type == BuildingType.SHIPYARD:
		_sprite.texture = load("res://assets/shipyard.svg")
	else:
		_sprite.texture = load("res://assets/mine.svg")
	# 设置碰撞尺寸
	var shape = RectangleShape2D.new()
	shape.size = Vector2(GameConfig.BUILDING_SIZE * 2, GameConfig.BUILDING_SIZE * 2)
	collision_shape.shape = shape
	_body.scale = Vector2(1.5, 1.5)


func _exit_tree() -> void:
	all_buildings.erase(self)


## 以部署状态启动建筑（HP/护盾从0开始，随时间增长）
func start_deploy(duration: float = GameConfig.DEPLOY_DURATION) -> void:
	_is_deploying = true
	_deploy_timer = duration
	_deploy_duration = duration
	shield = 0.0
	hull = 0.0


## 建筑是否已死亡（用于外部检查）
func is_dead() -> bool:
	return hull <= 0.0


func _draw() -> void:
	# ---- 护盾 & 结构条 ----
	var bar_width = 140.0
	var bar_half = bar_width / 2.0
	var bar_top = -GameConfig.BUILDING_SIZE * 2.0

	# 护盾条（蓝色）
	if shield < max_shield:
		draw_rect(Rect2(-bar_half, bar_top - 20.0, bar_width, 4.0), Color(0.15, 0.15, 0.2, 0.8), true)
		draw_rect(Rect2(-bar_half, bar_top - 20.0, bar_width * shield / max_shield, 4.0), Color(0.2, 0.5, 1.0, 0.9), true)

	# 结构条（绿色/黄色/红色）
	if hull < max_hull:
		draw_rect(Rect2(-bar_half, bar_top - 14.0, bar_width, 5.0), Color(0.15, 0.15, 0.2, 0.8), true)
		var hull_pct = hull / max_hull
		var hull_color: Color
		if hull_pct > 0.5:
			hull_color = Color(0.2, 1.0, 0.3)
		elif hull_pct > 0.25:
			hull_color = Color(1.0, 0.8, 0.2)
		else:
			hull_color = Color(1.0, 0.2, 0.2)
		draw_rect(Rect2(-bar_half, bar_top - 14.0, bar_width * hull_pct, 5.0), hull_color, true)

	# ---- 部署进度条 ----
	if _is_deploying:
		var progress = 1.0 - (_deploy_timer / _deploy_duration)
		draw_rect(Rect2(-bar_half, bar_top - 26.0, bar_width, 4.0), Color(0.2, 0.2, 0.3, 0.8), true)
		draw_rect(Rect2(-bar_half, bar_top - 26.0, bar_width * progress, 4.0), Color(1.0, 0.8, 0.2, 0.9), true)
		# 部署中标签
		var font = ThemeDB.fallback_font
		if font:
			var pct = int(progress * 100)
			font.draw_string(get_canvas_item(), Vector2(-bar_half, bar_top - 32), "部署中 %d%%" % pct,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.8, 0.2, 0.9))

	if _is_selected:
		var r = GameConfig.BUILDING_SIZE * 2.5
		draw_circle(Vector2.ZERO, r, Color(0.2, 1.0, 0.4, 0.15), true)
		draw_circle(Vector2.ZERO, r, Color(0.2, 1.0, 0.4, 0.6), false, 2.0)
		# 建筑类型标签
		var label = "矿场" if building_type == BuildingType.MINE else "船坞"
		var font = ThemeDB.fallback_font
		if font:
			font.draw_string(get_canvas_item(), Vector2(-30, -GameConfig.BUILDING_SIZE * 2), label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 1, 1, 0.8))

		# 战斗船集结点（绿色）
		if building_type == BuildingType.SHIPYARD and has_rally_point:
			_draw_rally_flag(rally_point - global_position, Color(0.2, 1.0, 0.4))
		# 采矿船集结点（橙色）
		if building_type == BuildingType.SHIPYARD and has_miner_rally_point:
			_draw_rally_flag(miner_rally_point - global_position, Color(1.0, 0.7, 0.1))


## 绘制单个集结点旗帜
func _draw_rally_flag(local_pos: Vector2, color: Color) -> void:
	draw_line(Vector2.ZERO, local_pos, Color(color.r, color.g, color.b, 0.4), 2.0)
	draw_circle(local_pos, 8.0, Color(color.r, color.g, color.b, 0.15), true)
	draw_circle(local_pos, 8.0, Color(color.r, color.g, color.b, 0.8), false, 1.5)
	var flag_top = local_pos + Vector2(0, -8)
	var flag_bot = local_pos + Vector2(0, 8)
	var flag_tip = local_pos + Vector2(10, 0)
	draw_line(flag_top, flag_tip, Color(color.r, color.g, color.b, 0.9), 2.0)
	draw_line(flag_tip, flag_bot, Color(color.r, color.g, color.b, 0.9), 2.0)
	draw_line(local_pos + Vector2(0, -12), local_pos + Vector2(0, 12), Color(color.r, color.g, color.b, 0.7), 1.5)


func _process(delta: float) -> void:
	# 部署状态：HP/护盾随时间同步增长
	if _is_deploying:
		_deploy_timer -= delta
		var progress = 1.0 - (_deploy_timer / _deploy_duration)
		progress = clamp(progress, 0.0, 1.0)
		shield = max_shield * progress
		hull = max_hull * progress
		queue_redraw()
		if _deploy_timer <= 0.0:
			_is_deploying = false
			shield = max_shield
			hull = max_hull
		return  # 部署期间不进行护盾恢复

	# 护盾恢复
	if _shield_regen_delay > 0.0:
		_shield_regen_delay -= delta
	elif shield < max_shield:
		shield = min(max_shield, shield + shield_regen_rate * delta)

	if building_type == BuildingType.SHIPYARD and _is_producing:
		_production_timer -= delta
		if _production_timer <= 0.0:
			_finish_production()


## 船坞：加入生产队列
func enqueue_ship(ship_type, cost: int, build_time: float) -> bool:
	if building_type != BuildingType.SHIPYARD:
		return false

	# 检查当前队列和总矿物
	var total_cost = cost
	for entry in _production_queue:
		total_cost += entry.cost

	var main_node = get_parent()
	if main_node and main_node.has_method("get_team_minerals"):
		var available = main_node.get_team_minerals(team)
		if available < total_cost:
			return false

	_production_queue.append({
		"type": ship_type,
		"time": build_time,
		"total": build_time,
		"cost": cost
	})

	if not _is_producing:
		_start_next_production()
	return true


func _start_next_production() -> void:
	if _production_queue.size() == 0:
		_is_producing = false
		return

	var entry = _production_queue[0]
	# 扣除矿物
	var main_node = get_parent()
	if main_node and main_node.has_method("spend_team_minerals"):
		if not main_node.spend_team_minerals(team, entry.cost):
			return

	_is_producing = true
	_production_timer = entry.time


func _finish_production() -> void:
	if _production_queue.size() == 0:
		_is_producing = false
		return

	var entry = _production_queue.pop_front()
	emit_signal("ship_produced", team, entry.type, self)

	# 继续生产队列中的下一个
	_is_producing = false
	_start_next_production()


## 获取生产进度 0.0~1.0
func get_production_progress() -> float:
	if not _is_producing or _production_queue.size() == 0:
		return 0.0
	var entry = _production_queue[0]
	return 1.0 - (_production_timer / entry.total)


## 获取队列中的总矿物消耗
func get_queue_total_cost() -> int:
	var total = 0
	for entry in _production_queue:
		total += entry.cost
	return total


## 矿场：接收采矿船卸货
func deposit_minerals(amount: float) -> float:
	if building_type != BuildingType.MINE:
		return 0.0
	var actual = min(amount, max_stored_minerals - stored_minerals)
	if actual > 0:
		stored_minerals += actual
		emit_signal("mineral_deposited", team, actual)
	return actual


func take_damage(amount: float, source: Node = null) -> void:
	# 护盾优先吸收伤害
	if shield > 0.0:
		var remaining = amount - shield
		shield = max(0.0, shield - amount)
		if remaining > 0.0:
			hull = max(0.0, hull - remaining)
	else:
		hull = max(0.0, hull - amount)

	_shield_regen_delay = GameConfig.BUILDING_SHIELD_DELAY
	queue_redraw()

	if hull <= 0.0:
		queue_free()

class_name Building
extends Area2D

## 建筑类型
enum BuildingType { MINE, SHIPYARD }

@export var building_type: BuildingType = BuildingType.MINE
## 所属阵营
var team: String = ""
## 阵营颜色
var building_color: Color = Color.WHITE
## 当前结构值
var hull: float = GameConfig.BUILDING_MAX_HULL
var max_hull: float = GameConfig.BUILDING_MAX_HULL

## 自增 ID，用于区分多个建筑
var building_id: int = 0

# ----- 矿场专用 -----
## 本矿场储存的矿物总量（采矿船卸货到这里）
var stored_minerals: float = 0.0
## 矿场矿物容量上限
var max_stored_minerals: float = 99999

# ----- 船坞专用 -----
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


func _draw() -> void:
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


func _process(delta: float) -> void:
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


func take_damage(amount: float) -> void:
	hull = max(0.0, hull - amount)
	if hull <= 0.0:
		queue_free()

class_name UnitMining
extends Unit

## 采矿状态机
enum MinerState { IDLE, MOVING_TO_FIELD, MINING, RETURNING_TO_MINE, DEPOSITING }

## 采矿状态
var _miner_state: int = MinerState.IDLE
## 当前采矿目标矿物场
var _mining_target_field = null
## 所属母矿场
var _home_mine = null
## 当前货仓矿物量
var _miner_cargo: float = 0.0
## 货仓容量
var _miner_cargo_capacity: float = GameConfig.MINER_CARGO_CAPACITY
## 采矿计时器
var _miner_mine_timer: float = 0.0


func _ready() -> void:
	super()
	_is_miner = true
	# 替换为采矿船纹理
	_sprite.texture = load("res://assets/miner.svg")
	# 降低战斗相关设置
	_current_target = null
	_explicit_attack_target = null


func _process(delta: float) -> void:
	super(delta)
	_update_mining(delta)


## 将本船设置为采矿船模式
func set_as_miner(home_mine) -> void:
	_home_mine = home_mine
	_miner_state = MinerState.IDLE


## 右键指定矿船前往某矿物场采矿
func mine_field(field) -> void:
	if not is_instance_valid(field):
		return
	_command_queue.clear()
	_unregister_from_field()
	_mining_target_field = field
	_mining_target_field.register_miner()
	_miner_state = MinerState.MOVING_TO_FIELD
	_is_moving = true
	_target_position = field.global_position
	_is_attack_move = false
	_is_area_attack = false
	_explicit_attack_target = null
	_is_orbit = false
	_current_target = null
	mark_dirty()


## 取消注册当前矿物场，释放矿船名额
func _unregister_from_field() -> void:
	if _mining_target_field != null and is_instance_valid(_mining_target_field):
		_mining_target_field.unregister_miner()


## 每帧更新采矿状态机
func _update_mining(delta: float) -> void:
	if not is_instance_valid(_home_mine):
		return

	match _miner_state:
		MinerState.IDLE:
			# 正在执行玩家指令时等待，不自动采矿
			if _is_moving or _command_queue.size() > 0:
				return
			# 离开旧矿场时释放名额
			_unregister_from_field()
			# 寻找最近的矿场
			_find_nearest_field()
			if _mining_target_field != null:
				_mining_target_field.register_miner()
				_is_moving = true
				_target_position = _mining_target_field.global_position
				_miner_state = MinerState.MOVING_TO_FIELD

		MinerState.MOVING_TO_FIELD:
			if not is_instance_valid(_mining_target_field):
				_unregister_from_field()
				_miner_state = MinerState.IDLE
				return
			var dist = global_position.distance_to(_mining_target_field.global_position)
			if dist < 60.0:
				_is_moving = false
				_miner_state = MinerState.MINING

		MinerState.MINING:
			if not is_instance_valid(_mining_target_field):
				_unregister_from_field()
				_miner_state = MinerState.IDLE
				return
			# 每秒计算一次采矿量
			_miner_mine_timer += delta
			if _miner_mine_timer < 1.0:
				return
			_miner_mine_timer = 0.0
			var mine_amount = GameConfig.MINER_MINE_RATE
			var actual = _mining_target_field.mine(mine_amount)
			_miner_cargo = min(_miner_cargo + actual, _miner_cargo_capacity)
			if _miner_cargo >= _miner_cargo_capacity or actual <= 0:
				# 货仓满或矿枯竭 → 回矿场，释放名额
				_unregister_from_field()
				_miner_state = MinerState.RETURNING_TO_MINE
				_is_moving = true
				_target_position = _home_mine.global_position

		MinerState.RETURNING_TO_MINE:
			if not is_instance_valid(_home_mine):
				_miner_state = MinerState.IDLE
				return
			var dist = global_position.distance_to(_home_mine.global_position)
			if dist < GameConfig.MINER_DEPOSIT_RANGE:
				_is_moving = false
				_miner_state = MinerState.DEPOSITING

		MinerState.DEPOSITING:
			if not is_instance_valid(_home_mine):
				_miner_state = MinerState.IDLE
				return
			# 在矿场附近，卸货
			if _miner_cargo > 0:
				var deposited = _home_mine.deposit_minerals(_miner_cargo)
				_miner_cargo -= deposited
			else:
				_miner_state = MinerState.IDLE


func _find_nearest_field() -> void:
	var best = null
	var best_score := INF
	var all_fields = get_tree().get_nodes_in_group("mineral_fields")
	var range_weight = GameConfig.MINER_SCAN_RANGE + 1.0
	for field in all_fields:
		if not is_instance_valid(field):
			continue
		if field.mineral_amount <= 0:
			continue
		var dist = global_position.distance_to(field.global_position)
		# 评分：优先选矿船少的矿（权重高），同数量时选最近的
		var score = field.miner_count * range_weight + dist
		if score < best_score:
			best_score = score
			best = field
	_mining_target_field = best

class_name Projectile
extends Area2D

## 最大速度
var max_speed: float = 500.0
## 加速度
var acceleration: float = 3000.0
## 当前速度向量
var velocity: Vector2
## 伤害值
var damage: float = 10.0
## 飞行方向
var _direction: Vector2 = Vector2.RIGHT
## 追踪目标（导弹用）
var _target_unit: Node = null
## 弹体所属阵营
var team: String = ""
## 发射者（用于反击）
var source: Unit = null
## 是否追踪
var is_homing: bool = false
## 弹体颜色
var projectile_color: Color = Color.YELLOW
## 弹体半径
var projectile_size: float = 4.0
## 弹体生命值（PD可消耗）
var hp: float = 5.0
## 爆炸半径（>0 表示命中时产生范围伤害）
var explosion_radius: float = 0.0

var _lifetime: float = 3.0  # 默认值，setup() 会覆盖
## 碰撞形状引用，setup 时调整半径
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D

## 弹体纹理（首次使用时加载，失败则生成程序化纹理）
var _bullet_tex: Texture2D = null
var _missile_tex: Texture2D = null

## 生成一个纯色圆形程序化纹理
static func _make_circle_texture(radius: float, color: Color = Color.WHITE) -> Texture2D:
	var size = max(1, int(radius * 2 + 2))
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center = Vector2(size / 2.0, size / 2.0)
	for x in size:
		for y in size:
			var d = Vector2(x, y).distance_to(center)
			if d <= radius:
				var alpha = 1.0 - clamp((d - radius + 1.0) / 1.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	add_to_group("projectiles")
	area_entered.connect(_on_area_entered)


## 对弹体精灵应用渐变着色器（中心亮白 → 两侧黄色）
func _apply_gradient_shader() -> void:
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/bullet_gradient.gdshader")
	mat.set_shader_parameter("edge_color", projectile_color)
	mat.set_shader_parameter("center_color", Color.WHITE)
	_sprite.material = mat


func setup(config: Dictionary) -> void:
	max_speed = config.get("max_speed", 500.0)
	acceleration = config.get("acceleration", 3000.0)
	damage = config.get("damage", 10.0)
	_direction = config.get("direction", Vector2.RIGHT)
	_target_unit = config.get("target", null)
	team = config.get("team", "")
	source = config.get("source", null)
	is_homing = config.get("is_homing", false)
	explosion_radius = config.get("explosion_radius", 0.0)
	projectile_color = config.get("color", Color.YELLOW)
	projectile_size = config.get("size", 4.0)
	hp = config.get("hp", 5.0)
	if config.has("lifetime"):
		_lifetime = config.get("lifetime")

	# 根据类型切换纹理（优先加载 SVG，失败时回退程序化纹理）
	if is_homing:
		if _missile_tex == null:
			# _missile_tex = load("res://assets/missile.svg")
			_missile_tex = load("res://assets/missile.png")
			if _missile_tex == null:
				_missile_tex = _make_circle_texture(projectile_size, Color(1.0, 0.3, 0.1))
		_sprite.texture = _missile_tex
	else:
		if _bullet_tex == null:
			_bullet_tex = load("res://assets/bullet.svg")
		_sprite.texture = _bullet_tex
	if not is_homing:
		_apply_gradient_shader()
	_sprite.rotation = _direction.angle()
	# 缩放匹配尺寸（根据贴图实际像素尺寸计算）
	var tex = _sprite.texture
	if tex != null:
		var tex_size = tex.get_size()
		# projectile_size 是期望的世界半径，贴图显示直径 = projectile_size * 2
		var target_diameter = projectile_size * 2.0
		if is_homing:
			# 导弹等方形纹理：以长边为基准缩放（保持原有行为）
			_sprite.scale = Vector2.ONE * target_diameter / max(tex_size.x, tex_size.y, 1.0)
		else:
			# 子弹胶囊纹理：无人机基础尺寸 10×2，其它按飞船尺寸等比缩放
			const BULLET_BASE_SIZE := 3.0
			var size_factor = projectile_size / BULLET_BASE_SIZE
			_sprite.scale = Vector2(10.0 * size_factor / tex_size.x, 2.0 * size_factor / tex_size.y)
	else:
		_sprite.scale = Vector2(projectile_size / 4.0, projectile_size / 4.0)
	# 更新碰撞半径
	var shape = _collision_shape.shape
	if shape is CircleShape2D:
		shape.radius = projectile_size


func _process(delta: float) -> void:
	_lifetime -= delta

	# 追踪模式下更新方向和精灵朝向
	if is_homing and is_instance_valid(_target_unit) and _target_unit.hull > 0:
		_direction = (_target_unit.global_position - global_position).normalized()
		_sprite.rotation = _direction.angle()

	# 恒定最大速度移动
	velocity = _direction * max_speed
	global_position += velocity * delta

	# 超时则销毁
	if _lifetime <= 0:
		queue_free()


func _on_area_entered(other_area: Area2D) -> void:
	# 友军或自身不触发
	if other_area == source:
		return
	if other_area is Unit:
		var u: Unit = other_area as Unit
		if u.team == team or u.hull <= 0:
			return
	elif other_area is Building:
		var b: Building = other_area as Building
		if b.team == team or b.hull <= 0:
			return
	else:
		return

	# 爆炸伤害（导弹用）：命中时对范围内所有敌人造成伤害
	if explosion_radius > 0.0:
		_do_explosion()
		queue_free()
		return

	# 直接伤害
	if other_area is Unit:
		var other_unit: Unit = other_area as Unit
		if is_instance_valid(source):
			other_unit.take_damage(damage, source)
		else:
			other_unit.take_damage(damage)
		queue_free()
		return

	# 检测建筑
	if other_area is Building:
		var other_building: Building = other_area as Building
		if not is_instance_valid(other_building):
			return
		if other_building.team == team:
			return
		if other_building.hull <= 0:
			return

		if is_instance_valid(source):
			other_building.take_damage(damage, source)
		else:
			other_building.take_damage(damage)
		queue_free()
		return


## 执行爆炸：对爆炸半径内的所有敌方单位/建筑造成伤害
func _do_explosion() -> void:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = explosion_radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)
	# 检测单位（layer 1）和建筑（layer 1）
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results = space_state.intersect_shape(query)
	var hit_targets: Array[Node] = []
	for r in results:
		var area: Area2D = r.collider
		if not is_instance_valid(area):
			continue
		if area is Unit:
			var u: Unit = area
			if u.team == team or u.hull <= 0:
				continue
			hit_targets.append(u)
		elif area is Building:
			var b: Building = area
			if b.team == team or b.hull <= 0:
				continue
			hit_targets.append(b)

	# 对每个目标造成伤害
	for target in hit_targets:
		if is_instance_valid(source):
			target.take_damage(damage, source)
		else:
			target.take_damage(damage)


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()

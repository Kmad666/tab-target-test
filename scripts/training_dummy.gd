class_name TrainingDummy
extends StaticBody3D
## A stationary wooden training dummy. It never dies: at 0 health it refills.

signal health_changed(hp: float, max_hp: float)

@export var display_name := "Training Dummy"
@export var max_hp := 2000.0

var hp := 0.0

var _ring: MeshInstance3D
var _sway: Node3D
var _burlap: ShaderMaterial
var _flash := 0.0
var _wobble := 0.0
var _wobble_vel := 0.0
var _t := 0.0


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	collision_layer = 1 | 2     # layer 2 = clickable enemies
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 2.2
	col.shape = shape
	col.position.y = 1.1
	add_child(col)
	_build_model()


func get_hit_point() -> Vector3:
	return global_position + Vector3(0, 1.35, 0)


func set_targeted(on: bool) -> void:
	_ring.visible = on


func take_damage(amount: float) -> void:
	hp -= amount
	_flash = 0.15
	_wobble_vel += 1.6
	if hp <= 0.0:
		hp = max_hp
	health_changed.emit(hp, max_hp)


func _process(delta: float) -> void:
	_t += delta
	# Springy wobble when hit.
	_wobble_vel += (-_wobble * 60.0 - _wobble_vel * 6.0) * delta
	_wobble += _wobble_vel * delta
	_sway.rotation.x = -_wobble * 0.12
	# Blue-white flash from the lightning.
	_flash = maxf(0.0, _flash - delta)
	_burlap.set_shader_parameter("emission_energy", 1.5 * _flash / 0.15)
	# Pulsing red target circle.
	if _ring.visible:
		var s := 1.0 + sin(_t * 4.0) * 0.04
		_ring.scale = Vector3(s, 0.3, s)


func _build_model() -> void:
	var wood := Toon.outlined(Toon.mat(Color(0.55, 0.34, 0.18), {"shade": Color(0.5, 0.42, 0.6)}))
	var rope := Toon.outlined(Toon.mat(Color(0.4, 0.27, 0.15), {"shade": Color(0.5, 0.42, 0.6)}))
	var stitch := Toon.unshaded(Color(0.16, 0.09, 0.05))
	_burlap = Toon.outlined(Toon.mat(Color(0.9, 0.76, 0.5), {"shade": Color(0.55, 0.48, 0.65),
			"emission_color": Color(0.5, 0.6, 1.0)}))

	Toon.add(self, Toon.cyl(0.45, 0.55, 0.18, 20), wood, Vector3(0, 0.09, 0))

	_sway = Toon.pivot(self, Vector3(0, 0.18, 0))
	Toon.add(_sway, Toon.cyl(0.07, 0.085, 1.0, 12), wood, Vector3(0, 0.45, 0))
	Toon.add(_sway, Toon.lathe([Vector2(0.24, 0.0), Vector2(0.33, 0.12), Vector2(0.35, 0.4),
			Vector2(0.32, 0.68), Vector2(0.2, 0.8)], 20), _burlap, Vector3(0, 0.72, 0))
	for y in [0.86, 1.36]:
		Toon.add(_sway, Toon.torus(0.31, 0.37, 24, 8), rope, Vector3(0, y, 0))
	Toon.add(_sway, Toon.cyl(0.06, 0.06, 1.3, 12), wood, Vector3(0, 1.3, 0), Vector3(0, 0, PI / 2.0))
	for side in [1.0, -1.0]:
		Toon.add(_sway, Toon.ball(0.1, 14, 8), _burlap, Vector3(0.66 * side, 1.3, 0))
	Toon.add(_sway, Toon.ball(0.24, 18, 12), _burlap, Vector3(0, 1.74, 0))
	# Stitched X eyes and a mouth, facing +Z (toward the player's start).
	for side in [1.0, -1.0]:
		for r in [0.8, -0.8]:
			Toon.add(_sway, Toon.box(Vector3(0.1, 0.02, 0.02)), stitch,
					Vector3(0.08 * side, 1.79, 0.225), Vector3(0, 0, r))
	Toon.add(_sway, Toon.box(Vector3(0.15, 0.02, 0.02)), stitch, Vector3(0, 1.65, 0.23))

	# Red target circle on the ground, hidden until targeted.
	_ring = Toon.add(self, Toon.torus(0.85, 0.95, 40, 4), Toon.unshaded(Color(1.0, 0.12, 0.08)),
			Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false

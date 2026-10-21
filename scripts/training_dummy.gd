class_name TrainingDummy
extends StaticBody3D
## A stationary wooden training dummy. It never dies: at 0 health it refills.

signal health_changed(hp: float, max_hp: float)

@export var display_name := "Training Dummy"
@export var max_hp := 2000.0

var hp := 0.0

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _sway: Node3D
var _burlap: StandardMaterial3D
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
	_burlap.emission = Color(0.45, 0.55, 1.0) * (_flash / 0.15)
	# Pulsing red target circle.
	if _ring.visible:
		var s := 1.0 + sin(_t * 4.0) * 0.04
		_ring.scale = Vector3(s, 1.0, s)


func _build_model() -> void:
	var wood := LowPoly.mat(Color(0.36, 0.22, 0.12))
	var rope := LowPoly.mat(Color(0.25, 0.17, 0.1))
	var stitch := LowPoly.mat(Color(0.12, 0.08, 0.05))
	_burlap = LowPoly.mat(Color(0.78, 0.64, 0.42))
	_burlap.emission_enabled = true
	_burlap.emission = Color.BLACK
	_burlap.emission_energy_multiplier = 2.0

	LowPoly.add(self, LowPoly.cyl(0.45, 0.52, 0.16, 8), wood, Vector3(0, 0.08, 0))

	_sway = LowPoly.pivot(self, Vector3(0, 0.16, 0))
	LowPoly.add(_sway, LowPoly.cyl(0.07, 0.08, 1.0, 6), wood, Vector3(0, 0.45, 0))
	LowPoly.add(_sway, LowPoly.cyl(0.28, 0.33, 0.8, 8), _burlap, Vector3(0, 1.1, 0))
	for y in [0.82, 1.38]:
		LowPoly.add(_sway, LowPoly.torus(0.27, 0.34, 10, 4), rope, Vector3(0, y, 0))
	LowPoly.add(_sway, LowPoly.cyl(0.06, 0.06, 1.3, 6), wood, Vector3(0, 1.3, 0), Vector3(0, 0, PI / 2.0))
	for side in [1.0, -1.0]:
		LowPoly.add(_sway, LowPoly.sphere(0.09, 6, 4), _burlap, Vector3(0.66 * side, 1.3, 0))
	LowPoly.add(_sway, LowPoly.sphere(0.23, 8, 5), _burlap, Vector3(0, 1.72, 0))
	# Stitched X eyes and a mouth, facing +Z (toward the player's start).
	for side in [1.0, -1.0]:
		for r in [0.8, -0.8]:
			LowPoly.add(_sway, LowPoly.box(Vector3(0.09, 0.018, 0.02)), stitch,
					Vector3(0.08 * side, 1.77, 0.21), Vector3(0, 0, r))
	LowPoly.add(_sway, LowPoly.box(Vector3(0.14, 0.018, 0.02)), stitch, Vector3(0, 1.63, 0.215))

	# Red target circle on the ground, hidden until targeted.
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.12, 0.08)
	_ring = LowPoly.add(self, LowPoly.torus(0.85, 0.95, 24, 3), _ring_mat, Vector3(0, 0.03, 0),
			Vector3.ZERO, Vector3.ONE, false)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false

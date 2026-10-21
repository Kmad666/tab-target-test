class_name ForceLightning
extends MeshInstance3D
## Draws crackling lightning from the caster's fingertip to the target while channeling.
## Bolts are camera-facing ribbons rebuilt every frame; the jagged shape re-rolls ~20x a second.

const POINTS := 16
const BOLTS := 3
const FORKS := 3

var player: Player

var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _regen := 0.0
var _bolts: Array = []      # Array of PackedVector2Array offsets
var _forks: Array = []      # Array of {start: int, steps: PackedVector3Array}
var _hand_light := OmniLight3D.new()
var _hit_light := OmniLight3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for l in [_hand_light, _hit_light]:
		l.light_color = Color(0.55, 0.62, 1.0)
		l.omni_range = 4.0
		l.visible = false
		add_child(l)


func _process(delta: float) -> void:
	_im.clear_surfaces()
	var on := player != null and player.channeling and is_instance_valid(player.target) \
			and player.fingertip != null and player.target.has_method("get_hit_point")
	_hand_light.visible = on
	_hit_light.visible = on
	if not on:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a: Vector3 = player.fingertip.global_position
	var b: Vector3 = player.target.get_hit_point()
	var span := b - a
	var length := span.length()
	if length < 0.05:
		return
	var dir := span / length
	var u := dir.cross(Vector3.UP)
	if u.length_squared() < 0.001:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := dir.cross(u).normalized()
	var amp := clampf(length * 0.06, 0.15, 1.1)

	_regen -= delta
	if _regen <= 0.0 or _bolts.is_empty():
		_regen = 0.05
		_generate()

	var cam_pos := cam.global_position
	var main_pts := PackedVector3Array()
	for k in _bolts.size():
		var offs: PackedVector2Array = _bolts[k]
		var pts := PackedVector3Array()
		for i in POINTS + 1:
			var t := float(i) / POINTS
			var env := sin(PI * t) * (0.4 + 0.6 * t)   # tight at the finger, wild near the target
			var o := offs[i]
			pts.append(a.lerp(b, t) + (u * o.x + v * o.y) * amp * env)
		if k == 0:
			main_pts = pts
		var core_w := 0.03 if k == 0 else 0.018
		_strip(pts, core_w * 4.0, Color(0.3, 0.38, 1.0, 0.35), cam_pos)
		_strip(pts, core_w, Color(0.85, 0.9, 1.0, 1.0), cam_pos)

	for f in _forks:
		var p: Vector3 = main_pts[f["start"]]
		var pts := PackedVector3Array([p])
		for s in f["steps"]:
			p += (dir * s.x + u * s.y + v * s.z) * amp * 0.9
			pts.append(p)
		_strip(pts, 0.06, Color(0.3, 0.38, 1.0, 0.25), cam_pos)
		_strip(pts, 0.014, Color(0.8, 0.85, 1.0, 0.9), cam_pos)

	_hand_light.global_position = a
	_hand_light.light_energy = randf_range(1.0, 2.2)
	_hit_light.global_position = b
	_hit_light.light_energy = randf_range(1.5, 3.0)


func _generate() -> void:
	_bolts.clear()
	for k in BOLTS:
		var offs := PackedVector2Array()
		var spread := 0.45 if k == 0 else 0.75
		for i in POINTS + 1:
			offs.append(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread)
		_bolts.append(offs)
	_forks.clear()
	for k in FORKS:
		var steps := PackedVector3Array()
		for s in randi_range(3, 5):
			steps.append(Vector3(randf_range(0.2, 0.6), randf_range(-0.7, 0.7), randf_range(-0.7, 0.7)))
		_forks.append({"start": randi_range(3, POINTS - 3), "steps": steps})


## Adds a ribbon along the points that always faces the camera.
func _strip(pts: PackedVector3Array, width: float, col: Color, cam_pos: Vector3) -> void:
	var n := pts.size()
	if n < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for i in n:
		var p := pts[i]
		var seg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := seg.cross((cam_pos - p).normalized()).normalized() * width
		var c := col
		c.a *= 1.0 - 0.4 * float(i) / (n - 1)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side)
	_im.surface_end()

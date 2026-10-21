class_name CloudTrail
extends MeshInstance3D
## A thin wispy ribbon left behind the hover cloud. It records a few recent positions
## of `source` and draws one camera-facing strip through them that thins and fades out.

const LIFETIME := 0.45
const SPACING := 0.12

var source: Node3D
var emitting := false
var width := 0.1
var color := Color(0.4, 0.34, 0.5, 0.45)

var _points: Array = []          # each entry: [position: Vector3, age: float]
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(delta: float) -> void:
	for p in _points:
		p[1] += delta
	while not _points.is_empty() and _points[0][1] > LIFETIME:
		_points.pop_front()
	var head := Vector3.ZERO
	if emitting and source != null:
		head = source.global_position
		if _points.is_empty() or (_points[-1][0] as Vector3).distance_to(head) > SPACING:
			_points.append([head, 0.0])

	_im.clear_surfaces()
	var pts := _points.duplicate()
	if emitting and source != null:
		pts.append([head, 0.0])
	if pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i][0]
		var life := 1.0 - clampf(pts[i][1] / LIFETIME, 0.0, 1.0)
		var seg: Vector3 = (pts[mini(i + 1, n - 1)][0] - pts[maxi(i - 1, 0)][0])
		if seg.length_squared() < 1e-6:
			seg = Vector3.FORWARD
		var side := seg.normalized().cross((cam.global_position - p).normalized()).normalized()
		var w := width * life
		var c := color
		c.a *= life
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()

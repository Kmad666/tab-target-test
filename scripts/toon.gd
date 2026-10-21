class_name Toon
extends RefCounted
## Helpers for the cartoon look: cel-shaded materials, outlines and smooth shapes.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")


## A cel-shaded material. `params` can set any shader uniform, e.g. {"use_inner": true}.
static func mat(color: Color, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## Adds an ink outline pass to a material.
static func outlined(m: ShaderMaterial, thickness := 0.0026, color := Color(0.07, 0.03, 0.1)) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter("thickness", thickness)
	o.set_shader_parameter("color", color)
	m.next_pass = o
	return m


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


## Surface of revolution around the Y axis. profile = Array of Vector2(radius, y), bottom to top.
## folds/fold_amp add vertical cloth folds that are strongest at the bottom.
## deform (optional) is a Callable(Vector3) -> Vector3 applied to every vertex.
static func lathe(profile: Array, segments := 28, folds := 0, fold_amp := 0.0,
		deform := Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0: float = profile[0].y
	var y1: float = profile[profile.size() - 1].y
	for i in profile.size():
		var p: Vector2 = profile[i]
		var t := (p.y - y0) / maxf(y1 - y0, 0.0001)
		var amp := fold_amp * pow(1.0 - t, 1.6)
		for j in segments:
			var a := TAU * j / segments
			var r := p.x * (1.0 + amp * sin(a * folds))
			var y := p.y
			if i == 0 and folds > 0:
				y += amp * 0.5 * (1.0 - cos(a * folds))   # wavy hem
			var v := Vector3(sin(a) * r, y, cos(a) * r)
			if deform.is_valid():
				v = deform.call(v)
			st.add_vertex(v)
	for i in profile.size() - 1:
		for j in segments:
			var a := i * segments + j
			var b := i * segments + (j + 1) % segments
			var c := a + segments
			var d := b + segments
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()


## A smooth sphere built with lathe, so it can be deformed without seams.
static func ball(radius: float, segments := 20, rings := 12, deform := Callable()) -> ArrayMesh:
	var prof := []
	for i in rings + 1:
		var phi := PI * float(i) / rings
		prof.append(Vector2(sin(phi) * radius, -cos(phi) * radius))
	return lathe(prof, segments, 0, 0.0, deform)


static func cyl(top: float, bottom: float, height: float, segments := 18, caps := true) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	m.cap_top = caps
	m.cap_bottom = caps
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


static func torus(inner: float, outer: float, rings := 24, ring_segments := 10) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segments
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func add(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

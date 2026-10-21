class_name LowPoly
extends RefCounted
## Small helpers for building flat-shaded low poly models out of primitive meshes.


## Returns a copy of the mesh with one normal per triangle (faceted look).
static func flat(mesh: Mesh) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms = arrays[Mesh.ARRAY_NORMAL]
	var idx = arrays[Mesh.ARRAY_INDEX]
	if idx == null or idx.size() == 0:
		idx = PackedInt32Array()
		for i in verts.size():
			idx.append(i)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in range(0, idx.size() - 2, 3):
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		if norms != null and norms.size() > 0:
			var ref: Vector3 = norms[idx[i]] + norms[idx[i + 1]] + norms[idx[i + 2]]
			if ref.dot(n) < 0.0:
				n = -n
		out_v.append(a)
		out_v.append(b)
		out_v.append(c)
		out_n.append(n)
		out_n.append(n)
		out_n.append(n)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func mat(color: Color, roughness := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## A material that glows (emission above 1 feeds the glow effect).
static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func cyl(top: float, bottom: float, height: float, segments := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 0
	return m


static func sphere(radius: float, segments := 8, rings := 5) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func torus(inner: float, outer: float, rings := 10, ring_segments := 5) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segments
	return m


## Adds a mesh part to a parent node. Flat shaded by default.
static func add(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE, flat_shade := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = flat(mesh) if flat_shade else mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Adds an empty joint node, used as a pivot for animation.
static func pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

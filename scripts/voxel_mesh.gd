class_name VoxelMesh
## Builds meshes out of small colored cubes (Cube World style). Used for terrain faces, characters, trees, props.

const DIRS: Array[Vector3i] = [
	Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD,
]
# (up, right) sign of each corner emitted by add_face, in order. Lets callers compute per-corner AO.
const CORNERS: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

static var material: StandardMaterial3D
const NO_UV2 := Vector2(-1, -1)


# Tangent axes of face n: (up, right). right = up x n.
static func axes(n: Vector3) -> Array[Vector3]:
	var up := Vector3.UP if n.y == 0 else Vector3.FORWARD
	return [up, up.cross(n)]


# Quad on face n of the unit cube at p, clockwise (Godot front face), scaled by s.
# cols: one color per corner (see CORNERS).
# uv2: optional second UV (terrain: darkness from the sky light, World.light_at); NO_UV2 = none.
static func add_face(st: SurfaceTool, p: Vector3, n: Vector3, cols: Array[Color], s := 1.0, uv := Vector2.ZERO, uv2 := NO_UV2) -> void:
	var ax := axes(n)
	var c := p + Vector3.ONE * 0.5 + n * 0.5
	var q: Array[Vector3] = []
	for k in CORNERS:
		q.append(c + (ax[0] * k.x + ax[1] * k.y) * 0.5)
	st.set_normal(n)
	st.set_uv(uv)
	if uv2 != NO_UV2:
		st.set_uv2(uv2)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[i])
		st.add_vertex(q[i] * s)


static func fill(v: Dictionary, from: Vector3i, size: Vector3i, col: Color) -> void:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				v[from + Vector3i(x, y, z)] = col


# Highlight overlay. cells: Vector3i -> Color (alpha used). top_only: just the top face of each
# cell (ground tiles); else the outer faces of the group. out pushes faces outward, half = face half-size.
static func shell(cells: Dictionary, top_only: bool, out := 0.02, half := 0.5) -> ArrayMesh:
	if cells.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3i in cells:
		for n in ([Vector3i.UP] if top_only else DIRS):
			if not top_only and cells.has(p + n):
				continue
			var ax := axes(Vector3(n))
			var c := Vector3(p) + Vector3.ONE * 0.5 + Vector3(n) * (0.5 + out)
			var q: Array[Vector3] = []
			for k in CORNERS:
				q.append(c + (ax[0] * k.x + ax[1] * k.y) * half)
			st.set_normal(Vector3(n))
			st.set_color(cells[p])
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[i])
	return st.commit()


# Line mesh of the 12 edges of each cell (cells: Vector3i -> Color), grown by `grow` per side.
static func edges(cells: Dictionary, grow := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for p: Vector3i in cells:
		var a := Vector3(p) - Vector3.ONE * grow
		var b := Vector3(p) + Vector3.ONE * (1.0 + grow)
		st.set_color(Color(cells[p], 0.9))
		for i in 8:
			for bit in [1, 2, 4]:
				if i & bit == 0:
					st.add_vertex(_corner(a, b, i))
					st.add_vertex(_corner(a, b, i | bit))
	return st.commit()


static func _corner(a: Vector3, b: Vector3, i: int) -> Vector3:
	return Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z)


# v: Vector3i -> Color. Voxel p spans (p + offset) * s. jitter = per-voxel brightness noise.
static func build(v: Dictionary, s: float, offset := Vector3.ZERO, jitter := 0.06) -> ArrayMesh:
	if material == null:
		material = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3i in v:
		var k := 1.0 + jitter * ((hash(p) % 200) / 100.0 - 1.0)
		var col: Color = v[p] * k
		var cols: Array[Color] = [col, col, col, col]
		for n in DIRS:
			if not v.has(p + n):
				add_face(st, Vector3(p) + offset, Vector3(n), cols, s)
	st.set_material(material)
	return st.commit()

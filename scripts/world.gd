class_name World
extends Node3D
## Infinite voxel world. Columns of 16x16 blocks (y 0..SY-1) are generated on demand by WorldGen
## and kept in memory, so digging and building persist. Meshes, grass and tree nodes only exist for
## columns near `focus` (the camera) and are streamed in/out a few milliseconds per frame. The A*
## nav graph covers every column whose nav was built and is patched locally when a block changes.

signal terrain_changed

const CHUNK := 16
const SY := 64
const SECTION := 16  # meshes are built per 16x16x16 section of a column
const SECTIONS := SY / SECTION
const SECTION_VOL := CHUNK * CHUNK * SECTION
const VIEW := 7  # columns (Chebyshev distance) meshed around the focus; fog hides the edge
const KEEP := VIEW + 2  # meshes farther than this are freed
const STREAM_BUDGET_MS := 6.0
# Saved as bytes: only append new types at the end. Non-cube pieces live in `props`.
enum { AIR, GRASS, DIRT, STONE, WOOD, BRICK, SAND, SNOW, WATER, IRON_ORE }
const COLORS := {
	GRASS: Color(0.36, 0.62, 0.25),
	DIRT: Color(0.45, 0.30, 0.18),
	STONE: Color(0.50, 0.50, 0.52),
	WOOD: Color(0.68, 0.5, 0.3),
	BRICK: Color(0.62, 0.6, 0.58),
	SAND: Color(0.86, 0.79, 0.55),
	SNOW: Color(0.93, 0.95, 0.98),
	IRON_ORE: Color(0.50, 0.50, 0.52),  # stone with rust specks (terrain shader)
}
const AO_LIGHT := [0.5, 0.68, 0.84, 1.0]  # by number of open neighbors at a corner
const GRASS_CHANCE := 0.45
const FLOWER_CHANCE := 0.05
const H_DIRS: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
const N_OFF := [1, -1, CHUNK * CHUNK, -CHUNK * CHUNK, CHUNK, -CHUNK]  # column index offsets matching VoxelMesh.DIRS
const NAV_ID_OFFSET := 1 << 20

@export var flat := false  # debug map: endless flat plain
@export var world_seed := 0  # 0 = random each run

var gen: WorldGen
var focus := Vector3.ZERO  # streaming center, set from the camera
var columns := {}  # Vector2i -> PackedByteArray, index lx + 16 * (lz + 16 * y)
var dirty := {}  # Vector2i -> true: columns changed since generation (what a save stores)
var saved_columns := {}  # from a loaded save: Vector2i -> blocks, used instead of generating
var tree_left := {}  # tree cell -> wood left, for trees cut down (0); from a save also half-cut ones
var opaque := {}  # Vector2i -> PackedInt32Array: opaque blocks per section (buried sections aren't meshed)
var nav_built := {}  # Vector2i -> true
var meshed := {}  # Vector2i -> Array of SECTIONS section nodes (null = nothing to show)
var trees := {}  # cell -> {cell, kind, size, variant, amount}; survives its node being unloaded
var chunk_trees := {}  # Vector2i -> Array of tree cells
var tree_nodes := {}  # cell -> ResourceNode, only near the camera
var material := ShaderMaterial.new()
var water_material := ShaderMaterial.new()
var sway := ShaderMaterial.new()
var tuft_meshes: Array[ArrayMesh] = []  # tall grass, red flowers, yellow flowers
var astar := AStar3D.new()
var blocked := {}  # Vector3i -> true: cells occupied by trees / planned solid pieces
var bare := {}  # cells kept free of tall grass (stockpile tiles)
# Built pieces that aren't full blocks (Pieces catalog): cell -> {item, dir, base}.
# Tall pieces (doors) fill two cells; both entries point to the base cell.
var props := {}
var prop_nodes := {}  # base cell -> Node3D
var door_tweens := {}  # base cell -> Tween swinging that door
var _offsets: Array[Vector2i] = []  # column offsets around the focus, nearest first
var _unload_wait := 0


func _ready() -> void:
	gen = WorldGen.new(world_seed if world_seed != 0 else randi(), flat)
	material.shader = preload("res://shaders/terrain.gdshader")
	water_material.shader = preload("res://shaders/water.gdshader")
	sway.shader = preload("res://shaders/grass.gdshader")
	for flower: Color in [Color.TRANSPARENT, Color(0.9, 0.2, 0.2), Color(1, 0.85, 0.2)]:
		tuft_meshes.append(_tuft_mesh(flower))
	for x in range(-VIEW - 1, VIEW + 2):
		for z in range(-VIEW - 1, VIEW + 2):
			_offsets.append(Vector2i(x, z))
	_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())


func _process(_delta: float) -> void:
	stream(STREAM_BUDGET_MS)


# --- Streaming ---

# Builds nav and meshes around `focus`, nearest first, until the time budget runs out; frees
# meshes that fell behind.
func stream(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	var center := Vector2i(floori(focus.x) >> 4, floori(focus.z) >> 4)
	for off in _offsets:
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return
		var c := center + off
		var ring := maxi(absi(off.x), absi(off.y))
		if not nav_built.has(c):
			_build_nav(c)
		elif ring <= VIEW and not meshed.has(c):
			_mesh_column(c)
	_unload_wait += 1
	if _unload_wait > 30:
		_unload_wait = 0
		for c: Vector2i in meshed.keys():
			if maxi(absi(c.x - center.x), absi(c.y - center.y)) > KEEP:
				_unmesh_column(c)


# Synchronously loads nav (and meshes) for every column within `radius` of center.
func load_area(center: Vector3, radius: int, with_meshes := true) -> void:
	focus = center
	var cc := Vector2i(floori(center.x) >> 4, floori(center.z) >> 4)
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			var c := cc + Vector2i(x, z)
			if not nav_built.has(c):
				_build_nav(c)
	if with_meshes:
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var c := cc + Vector2i(x, z)
				if not meshed.has(c):
					_mesh_column(c)


# --- Block access ---

func idx(p: Vector3i) -> int:  # nav point id of a cell
	return ((p.x + NAV_ID_OFFSET) * (NAV_ID_OFFSET * 2) + (p.z + NAV_ID_OFFSET)) * SY + p.y


func in_bounds(p: Vector3i) -> bool:
	return p.y >= 0 and p.y < SY


func get_block(p: Vector3i) -> int:
	if p.y < 0 or p.y >= SY:
		return AIR
	var data: PackedByteArray = _data(Vector2i(p.x >> 4, p.z >> 4))
	return data[(p.x & 15) + CHUNK * ((p.z & 15) + CHUNK * p.y)]


# Blocks walking / holds things up: terrain and built blocks, plus solid pieces (windows, posts).
func is_solid(p: Vector3i) -> bool:
	var t := get_block(p)
	return (t != AIR and t != WATER) or (props.has(p) and prop_shape(p).solid)


func set_block(p: Vector3i, t: int) -> void:
	if not in_bounds(p):
		return
	var c := Vector2i(p.x >> 4, p.z >> 4)
	var i := (p.x & 15) + CHUNK * ((p.z & 15) + CHUNK * p.y)
	var old: int = _data(c)[i]
	columns[c][i] = t
	dirty[c] = true
	opaque[c][p.y / SECTION] += int(_opaque(t)) - int(_opaque(old))
	# Sections around too: face culling and AO read across section borders.
	var done := {}
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var q := p + Vector3i(dx, dy, dz)
				var key := Vector3i(q.x >> 4, q.y / SECTION, q.z >> 4)
				if in_bounds(q) and not done.has(key):
					done[key] = true
					_rebuild_section(Vector2i(key.x, key.z), key.y)
	_update_nav(p)
	terrain_changed.emit()


func _opaque(t: int) -> bool:
	return t != AIR and t != WATER


func _data(c: Vector2i) -> PackedByteArray:
	if not columns.has(c):
		_generate(c)
	return columns[c]


func _generate(c: Vector2i) -> void:
	var g := gen.generate(c.x, c.y, CHUNK, SY)
	var blocks: PackedByteArray = g.blocks
	if saved_columns.has(c):
		blocks = saved_columns[c]
		saved_columns.erase(c)
		dirty[c] = true
	columns[c] = blocks
	var counts := PackedInt32Array()
	counts.resize(SECTIONS)
	for i in blocks.size():
		if _opaque(blocks[i]):
			counts[i / SECTION_VOL] += 1
	opaque[c] = counts
	var cells := []
	for t: Dictionary in g.trees:
		t.amount = tree_left.get(t.cell, ResourceNode.amount_for(t.size))
		if t.amount == 0:
			continue  # cut down before the save
		trees[t.cell] = t
		cells.append(t.cell)
		set_blocked(t.cell, true)
	chunk_trees[c] = cells


# Highest free cell above column (x, z), i.e. where feet stand.
func top_at(x: int, z: int) -> int:
	for y in range(SY - 1, -1, -1):
		if is_solid(Vector3i(x, y, z)):
			return y + 1
	return 0


# --- Trees ---

func remove_tree(cell: Vector3i) -> void:
	trees.erase(cell)
	tree_left[cell] = 0
	tree_nodes.erase(cell)  # the node plays its fall and frees itself
	set_blocked(cell, false)


func _spawn_tree(cell: Vector3i) -> void:
	var r := ResourceNode.new()
	r.world = self
	r.data = trees[cell]
	r.position = Vector3(cell) + Vector3(0.5, 0, 0.5)
	add_child(r)
	tree_nodes[cell] = r


# --- Meshes ---

func _mesh_column(c: Vector2i) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_data(c + d)  # border faces and AO read the neighbors
	var nodes := []
	nodes.resize(SECTIONS)
	meshed[c] = nodes
	for s in SECTIONS:
		_rebuild_section(c, s)
	for cell: Vector3i in chunk_trees.get(c, []):
		if trees.has(cell) and not tree_nodes.has(cell):
			_spawn_tree(cell)


func _unmesh_column(c: Vector2i) -> void:
	for n in meshed[c]:
		if n:
			n.queue_free()
	meshed.erase(c)
	for cell: Vector3i in chunk_trees.get(c, []):
		if tree_nodes.has(cell) and tree_nodes[cell].claims == 0:
			tree_nodes[cell].queue_free()
			tree_nodes.erase(cell)


func _rebuild_section(c: Vector2i, s: int) -> void:
	if not meshed.has(c):
		return
	if meshed[c][s]:
		meshed[c][s].queue_free()
	meshed[c][s] = null if _buried(c, s) else _build_section(c, s)


# Solid all through with solid sections on every side: nothing in it can be seen.
func _buried(c: Vector2i, s: int) -> bool:
	if s + 1 >= SECTIONS or opaque[c][s] != SECTION_VOL or opaque[c][s + 1] != SECTION_VOL:
		return false
	if s > 0 and opaque[c][s - 1] != SECTION_VOL:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_data(c + d)
		if opaque[c + d][s] != SECTION_VOL:
			return false
	return true


func _build_section(c: Vector2i, s: int) -> Node3D:
	var data: PackedByteArray = columns[c]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	var water_faces := 0
	var grass_tops: Array[Vector3i] = []
	for y in range(s * SECTION, (s + 1) * SECTION):
		for lz in CHUNK:
			for lx in CHUNK:
				var i := lx + CHUNK * (lz + CHUNK * y)
				var t := data[i]
				if t == AIR:
					continue
				var p := Vector3i(c.x * CHUNK + lx, y, c.y * CHUNK + lz)
				var inner := lx > 0 and lz > 0 and y > 0 and lx < CHUNK - 1 and lz < CHUNK - 1 and y < SY - 1
				for k in 6:
					var nb: int = data[i + N_OFF[k]] if inner else get_block(p + VoxelMesh.DIRS[k])
					if t == WATER:
						if nb == AIR:
							_add_water_face(wst, p, VoxelMesh.DIRS[k])
							water_faces += 1
					elif nb == AIR or nb == WATER:
						_add_block_face(st, p, VoxelMesh.DIRS[k], t)
						faces += 1
				if t == GRASS and y < SY - 1 and data[i + CHUNK * CHUNK] == AIR:
					grass_tops.append(p + Vector3i.UP)
	if faces == 0 and water_faces == 0:
		return null
	var node := Node3D.new()
	add_child(node)
	if faces > 0:
		st.set_material(material)
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		node.add_child(mi)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
	if water_faces > 0:
		wst.set_material(water_material)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wst.commit()
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wmi)
	_add_tufts(node, grass_tops)
	return node


# Face with Minecraft-style per-corner ambient occlusion baked into vertex alpha.
func _add_block_face(st: SurfaceTool, p: Vector3i, n: Vector3i, t: int) -> void:
	var ax := VoxelMesh.axes(Vector3(n))
	var up := Vector3i(ax[0])
	var right := Vector3i(ax[1])
	var front := p + n
	var cols: Array[Color] = []
	for k in VoxelMesh.CORNERS:
		var s1 := is_solid(front + up * k.x)
		var s2 := is_solid(front + right * k.y)
		var corner := is_solid(front + up * k.x + right * k.y)
		var open := 0 if s1 and s2 else 3 - int(s1) - int(s2) - int(corner)
		cols.append(Color(COLORS[t], AO_LIGHT[open]))
	VoxelMesh.add_face(st, Vector3(p), Vector3(n), cols, 1.0, Vector2(t, 0))


# Water surface sits a little below the block top.
func _add_water_face(st: SurfaceTool, p: Vector3i, n: Vector3i) -> void:
	var col := Color.WHITE
	var drop := Vector3(0, -0.12, 0) if n == Vector3i.UP else Vector3.ZERO
	VoxelMesh.add_face(st, Vector3(p) + drop, Vector3(n), [col, col, col, col])


# Tall grass and flowers on exposed grass blocks. Seeded per column so rebuilds don't reshuffle.
func _add_tufts(node: Node3D, spots: Array[Vector3i]) -> void:
	var lists: Array = [[], [], []]
	var rng := RandomNumberGenerator.new()
	for p in spots:
		if blocked.has(p) or props.has(p) or bare.has(p):
			continue
		rng.seed = hash(Vector2i(p.x, p.z))
		var roll := rng.randf()
		if roll > GRASS_CHANCE:
			continue
		var kind := 0 if roll > FLOWER_CHANCE else 1 + rng.randi() % 2
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
		lists[kind].append(Transform3D(b, Vector3(p.x + rng.randf_range(0.25, 0.75), p.y, p.z + rng.randf_range(0.25, 0.75))))
	for i in lists.size():
		if lists[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tuft_meshes[i]
		mm.instance_count = lists[i].size()
		for j in lists[i].size():
			mm.set_instance_transform(j, lists[i][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = sway
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


# Small voxel tuft: blades getting lighter toward the tip; optional flower in the middle.
func _tuft_mesh(flower: Color) -> ArrayMesh:
	var v := {}
	var blades := [Vector2i(0, 0), Vector2i(2, 1), Vector2i(4, 0), Vector2i(1, 3), Vector2i(3, 4), Vector2i(4, 2), Vector2i(0, 4)]
	for i in blades.size():
		var h := 3 + (i * 7) % 4
		for y in h:
			v[Vector3i(blades[i].x, y, blades[i].y)] = Color(0.28, 0.52, 0.16).lerp(Color(0.55, 0.82, 0.3), float(y) / h)
	if flower.a > 0:
		VoxelMesh.fill(v, Vector3i(2, 0, 2), Vector3i(1, 7, 1), Color(0.3, 0.55, 0.2))
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			v[Vector3i(2, 7, 2) + d] = flower
		v[Vector3i(2, 7, 2)] = Color(1, 0.9, 0.4)
	return VoxelMesh.build(v, 0.07, Vector3(-2.5, 0, -2.5))


# Replaces the set of grass-free cells and rebuilds the sections whose tufts changed.
func set_bare(cells: Dictionary) -> void:
	var touched := {}
	for c: Vector3i in bare:
		if not cells.has(c):
			touched[Vector3i(c.x >> 4, (c.y - 1) / SECTION, c.z >> 4)] = true
	for c: Vector3i in cells:
		if not bare.has(c):
			touched[Vector3i(c.x >> 4, (c.y - 1) / SECTION, c.z >> 4)] = true
	bare = cells.duplicate()
	for k: Vector3i in touched:
		if k.y >= 0:
			_rebuild_section(Vector2i(k.x, k.z), k.y)


# --- Pieces (props) ---

func add_prop(p: Vector3i, item: String, dir: Vector3i) -> void:
	for c in prop_cells(p, item):
		props[c] = {"item": item, "dir": dir, "base": p}
	var n := Pieces.instance(item, dir)
	n.position = Pieces.origin(item, p)
	add_child(n)
	prop_nodes[p] = n
	for c in prop_cells(p, item):
		_update_nav(c)
	terrain_changed.emit()


# Removes the piece occupying p (any of its cells).
func remove_prop(p: Vector3i) -> void:
	if not props.has(p):
		return
	var base: Vector3i = props[p].base
	var item: String = props[base].item
	for c in prop_cells(base, item):
		props.erase(c)
	prop_nodes[base].queue_free()
	prop_nodes.erase(base)
	for c in prop_cells(base, item):
		_update_nav(c)
	terrain_changed.emit()


# Every cell a piece fills: its footprint (Pieces.size) from the base corner.
func prop_cells(base: Vector3i, item: String) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var sz := Pieces.size(item)
	for y in sz.y:
		for x in sz.x:
			for z in sz.z:
				cells.append(base + Vector3i(x, y, z))
	return cells


# Workstation fire and smoke while someone is working it.
func set_station_active(base: Vector3i, on: bool) -> void:
	var n: Node3D = prop_nodes.get(base)
	if n == null:
		return
	for child in n.get_children():
		if child.name == "Fire":
			child.visible = on
		elif child is CPUParticles3D:
			child.emitting = on


# A villager is stepping into p: if it's a door, swing it open, then shut it a moment later.
# Walking through again before it shuts keeps it open.
func open_door(p: Vector3i) -> void:
	if not props.has(p) or Pieces.ITEMS[props[p].item].shape != "door":
		return
	var base: Vector3i = props[p].base
	var hinge: Node3D = prop_nodes[base].get_node("Hinge")
	if door_tweens.has(base) and door_tweens[base].is_valid():
		door_tweens[base].kill()
	var tw := hinge.create_tween()
	tw.tween_property(hinge, "rotation:y", -1.6, 0.2)
	tw.tween_interval(1.2)
	tw.tween_property(hinge, "rotation:y", 0.0, 0.35)
	door_tweens[base] = tw


func add_ladder(p: Vector3i, dir: Vector3i) -> void:
	add_prop(p, "ladder", dir)


func prop_shape(p: Vector3i) -> Dictionary:
	return Pieces.shape(props[p].item) if props.has(p) else {}


func is_ladder(p: Vector3i) -> bool:
	return props.has(p) and Pieces.ITEMS[props[p].item].shape == "ladder"


func is_roof(p: Vector3i) -> bool:
	return prop_shape(p).get("roof", false)


# Can something rest on / against p? Solid cells, plus roof pieces (they hold the next ring).
func holds(p: Vector3i) -> bool:
	return is_solid(p) or is_roof(p)


# Walks the grid along a ray (Amanatides-Woo) until hit(cell) is true.
# Returns {cell, normal} (normal = face entered through, ZERO if the ray starts inside) or {}.
func raycast_cells(from: Vector3, dir: Vector3, hit: Callable, max_dist := 300.0) -> Dictionary:
	var cell := Vector3i(from.floor())
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3.ZERO
	var t_max := Vector3.ZERO
	for a in 3:
		if dir[a] == 0:
			t_delta[a] = INF
			t_max[a] = INF
		else:
			t_delta[a] = absf(1.0 / dir[a])
			t_max[a] = ((cell[a] + 1 - from[a]) if dir[a] > 0 else (from[a] - cell[a])) * t_delta[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		if hit.call(cell):
			return {"cell": cell, "normal": normal}
		var a := 0 if t_max.x < t_max.y and t_max.x < t_max.z else (1 if t_max.y < t_max.z else 2)
		cell[a] += step[a]
		t = t_max[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


# --- Navigation ---

# Feet cell: air (not water) for body + head, solid underneath.
func walkable(p: Vector3i) -> bool:
	return not is_solid(p) and get_block(p) != WATER and not is_solid(p + Vector3i.UP) \
		and is_solid(p + Vector3i.DOWN)


func set_blocked(p: Vector3i, on: bool) -> void:
	if on:
		blocked[p] = true
	else:
		blocked.erase(p)
	if in_bounds(p) and astar.has_point(idx(p)):
		astar.set_point_disabled(idx(p), on)


# Blocked target cells are skipped, so the path ends next to them.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _nearest_point(from)
	var b := _nearest_point(to)
	if a == -1 or b == -1:
		return PackedVector3Array()
	return astar.get_point_path(a, b, true)


# Nearest enabled nav point to pos, searched in growing rings around it (the graph is huge, so
# AStar3D.get_closest_point, which scans every point, is only the last resort).
func _nearest_point(pos: Vector3) -> int:
	var base := Vector3i(pos.floor())
	var best := -1
	var best_d := INF
	for r in 5:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for dy in range(-4, 4):
					var p := base + Vector3i(dx, dy, dz)
					if not in_bounds(p):
						continue
					var id := idx(p)
					if astar.has_point(id) and not astar.is_point_disabled(id):
						var d := astar.get_point_position(id).distance_squared_to(pos)
						if d < best_d:
							best_d = d
							best = id
		if best != -1 and r >= 1:
			return best
	if best == -1 and astar.get_point_count() > 0:
		best = astar.get_closest_point(pos)
	return best


func _build_nav(c: Vector2i) -> void:
	var data: PackedByteArray = _data(c)
	var cells: Array[Vector3i] = []
	for y in range(1, SY - 1):
		for lz in CHUNK:
			for lx in CHUNK:
				var i := lx + CHUNK * (lz + CHUNK * y)
				if data[i] != AIR:
					continue
				var p := Vector3i(c.x * CHUNK + lx, y, c.y * CHUNK + lz)
				var below := data[i - CHUNK * CHUNK]
				if not _opaque(below) and not props.has(p) and not props.has(p + Vector3i.DOWN):
					continue
				if _add_nav_point(p):
					cells.append(p)
	nav_built[c] = true
	for p in cells:
		_link(p, H_DIRS)  # neighbors in columns without nav yet get linked when theirs is built


# Block b changed: walkability only changes in b's column (b-1..b+1), and every edge whose
# validity can change has an endpoint in b's column (b-2..b+1, the -2 is the head-room rule).
func _update_nav(b: Vector3i) -> void:
	if not nav_built.has(Vector2i(b.x >> 4, b.z >> 4)):
		return  # built later from the current blocks
	for y in range(b.y - 1, b.y + 2):
		var p := Vector3i(b.x, y, b.z)
		if in_bounds(p) and astar.has_point(idx(p)):
			astar.remove_point(idx(p))
		_add_nav_point(p)
	for y in range(b.y - 2, b.y + 2):
		_link(Vector3i(b.x, y, b.z), H_DIRS)


# Ladder and roof cells are nav points even with nothing underneath (you hang on / walk the roof).
func _add_nav_point(p: Vector3i) -> bool:
	if not in_bounds(p):
		return false
	var hanging := (is_ladder(p) or is_roof(p)) and not is_solid(p) and not is_solid(p + Vector3i.UP)
	if not hanging and not walkable(p):
		return false
	# Slabs and stairs: you stand on top of them, half a block up.
	astar.add_point(idx(p), Vector3(p) + Vector3(0.5, prop_shape(p).get("floor", 0.0), 0.5))
	if blocked.has(p):
		astar.set_point_disabled(idx(p))
	return true


# (Re)evaluate p's edges to its neighbors one step away, up to 1 block up/down.
func _link(p: Vector3i, dirs: Array[Vector3i]) -> void:
	if not in_bounds(p) or not astar.has_point(idx(p)):
		return
	for d in dirs:
		for dy in [-1, 0, 1]:
			var q := p + d + Vector3i(0, dy, 0)
			if not in_bounds(q) or not astar.has_point(idx(q)):
				continue
			var low := p if dy > 0 else q
			var ok: bool = dy == 0 or not is_solid(low + Vector3i(0, 2, 0))  # head room when stepping
			if ok:
				astar.connect_points(idx(p), idx(q))
			elif astar.are_points_connected(idx(p), idx(q)):
				astar.disconnect_points(idx(p), idx(q))
	# Climb: anything (ladder or the floor under it) to the ladder cell above. From the top rung
	# the normal step-up edge above leads onto the wall.
	var up := p + Vector3i.UP
	if is_ladder(up) and astar.has_point(idx(up)):
		astar.connect_points(idx(p), idx(up))

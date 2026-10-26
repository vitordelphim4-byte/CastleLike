class_name World
extends Node3D
## Infinite voxel world. Columns of 16x16 blocks (y 0..SY-1) are generated on demand by WorldGen
## and kept in memory, so digging and building persist. Meshes, grass and tree nodes only exist for
## columns near `focus` (the camera) and are streamed in/out a few milliseconds per frame. The A*
## nav graph covers every column whose nav was built and is patched locally when a block changes.

signal terrain_changed
signal cut_changed

const CHUNK := 16
const SY := 192  # WorldGen.DEPTH blocks of underground below the old sea floor + terrain + sky
const SECTION := 16  # meshes are built per 16x16x16 section of a column
const SECTIONS := SY / SECTION
const SECTION_VOL := CHUNK * CHUNK * SECTION
const VIEW := 8  # columns (Chebyshev distance) meshed around the focus; fog hides the edge
const KEEP := VIEW + 2  # meshes farther than this are freed
const STREAM_BUDGET_MS := 6.0
const WATER_BUDGET_MS := 3.0  # water mesh rebuilds per frame
# Saved as bytes: only append new types at the end. Non-cube pieces live in `props`.
# WATER is a source block; FLOW_1..FLOW_7 flowing water by level, FALLING a falling column (Fluids).
enum { AIR, GRASS, DIRT, STONE, WOOD, BRICK, SAND, SNOW, WATER, IRON_ORE, FARMLAND, DEEPSLATE, BEDROCK, COAL_ORE,
	FLOW_1, FLOW_2, FLOW_3, FLOW_4, FLOW_5, FLOW_6, FLOW_7, FALLING }
const COLORS := {
	GRASS: Color(0.36, 0.62, 0.25),
	DIRT: Color(0.45, 0.30, 0.18),
	STONE: Color(0.50, 0.50, 0.52),
	WOOD: Color(0.68, 0.5, 0.3),
	BRICK: Color(0.62, 0.6, 0.58),
	SAND: Color(0.86, 0.79, 0.55),
	SNOW: Color(0.93, 0.95, 0.98),
	IRON_ORE: Color(0.50, 0.50, 0.52),  # stone with rust specks (terrain shader)
	FARMLAND: Color(0.36, 0.24, 0.14),  # tilled soil with furrows (terrain shader)
	DEEPSLATE: Color(0.30, 0.30, 0.34),  # deep stone, layered (terrain shader)
	BEDROCK: Color(0.17, 0.17, 0.18),  # world floor, can't be dug
	COAL_ORE: Color(0.50, 0.50, 0.52),  # stone with black lumps (terrain shader)
}
const AO_LIGHT := [0.5, 0.68, 0.84, 1.0]  # by number of open neighbors at a corner
const GRASS_CHANCE := 0.45
const FLOWER_CHANCE := 0.05
const TUFT_RANGE := 45.0  # grass tufts are hidden beyond this camera distance
const TUFT_SIZE := 0.8  # tuft quad width and height, in blocks
# Atlas tiles after the plain grass one: [petal color, flower heart] (poppy, dandelion, daisy, cornflower).
const TUFT_TILES := [[], [Color(0.9, 0.18, 0.15), Color(0.35, 0.08, 0.06)], [Color(1, 0.84, 0.2), Color(0.95, 0.6, 0.1)],
	[Color(0.97, 0.97, 0.94), Color(1, 0.85, 0.25)], [Color(0.35, 0.5, 0.95), Color(0.15, 0.2, 0.55)]]
const H_DIRS: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
const N_OFF := [1, -1, CHUNK * CHUNK, -CHUNK * CHUNK, CHUNK, -CHUNK]  # column index offsets matching VoxelMesh.DIRS
const NAV_ID_OFFSET := 1 << 20
# AO_OFF[k][corner * 3 + 0..2]: column-index offsets of the 3 cells shading each corner of a face
# in direction k (side, other side, diagonal), for blocks away from the column's edges.
static var AO_OFF: Array[PackedInt32Array] = []
const XRAY_MAX := 9  # matches view_clip.gdshaderinc
const WADE_COST := 3.0  # A* weight of a shallow-water cell: paths go around when it's cheap to
# Lake / sea surface shortcut (_still_surface): the 8 cells around (and the cell itself), and the
# corners every such cell gets.
const STILL_OFF := [0, 1, -1, CHUNK, -CHUNK, CHUNK + 1, CHUNK - 1, -CHUNK + 1, -CHUNK - 1]
const STILL_CORNERS := {Vector2i(0, 0): 0.88, Vector2i(1, 0): 0.88, Vector2i(0, 1): 0.88, Vector2i(1, 1): 0.88}

@export var flat := false  # debug map: endless flat plain
@export var world_seed := 0  # 0 = random each run

var gen: WorldGen
var focus := Vector3.ZERO  # streaming center, set from the camera
var columns := {}  # Vector2i -> PackedByteArray, index lx + 16 * (lz + 16 * y)
var dirty := {}  # Vector2i -> true: columns changed since generation (what a save stores)
var saved_columns := {}  # from a loaded save: Vector2i -> blocks, used instead of generating
var saved_bottom := 0  # layers under saved columns taken from the generator (old, shallower saves)
var tree_left := {}  # tree cell -> wood left, for trees cut down (0); from a save also half-cut ones
var opaque := {}  # Vector2i -> PackedInt32Array: opaque blocks per section (buried sections aren't meshed)
var nav_built := {}  # Vector2i -> true
var meshed := {}  # Vector2i -> Array of SECTIONS section nodes (null = nothing to show)
# Sections of meshed columns not built yet, one at a time within the frame budget: the ones near
# the surface first (every column), then the deep ones (caves), only once they can show.
var _pending_top := {}  # Vector2i -> Array of section indices
var _pending_deep := {}
var trees := {}  # cell -> {cell, kind, size, variant, amount}; survives its node being unloaded
var chunk_trees := {}  # Vector2i -> Array of tree cells
var tree_nodes := {}  # cell -> ResourceNode, only near the camera
var material := ShaderMaterial.new()
var water_material := ShaderMaterial.new()
var sway := ShaderMaterial.new()
var tuft_meshes: Array[ArrayMesh] = []  # one per TUFT_TILES entry
var astar := AStar3D.new()
var blocked := {}  # Vector3i -> true: cells occupied by trees / planned solid pieces
var bare := {}  # cells kept free of tall grass (stockpile tiles)
# Built pieces that aren't full blocks (Pieces catalog): cell -> {item, dir, base}.
# Tall pieces (doors) fill two cells; both entries point to the base cell.
var props := {}
var prop_nodes := {}  # base cell -> Node3D
var door_tweens := {}  # base cell -> Tween swinging that door
# Layer cut (Phase 9): cells at y >= cut_y aren't drawn or picked; SY = off. caps: column -> mesh
# of the cut plane (top faces of blocks just under it whose cell above is solid), or null.
var cut_y := SY
var caps := {}
var xray_cursor := false:  # V: see through the ground around the mouse
	set(v):
		xray_cursor = v
		_show_sections()
# Deep sections (wholly under the column's natural ground, caves only) are hidden unless something
# can show them: a layer cut, the cursor x-ray, or digging in that column (opened).
var _deep_below := {}  # Vector2i -> sections whose top is at or under this y are deep
var fluids := Fluids.new()
var _water_dirty := {}  # Vector3i(cx, section, cz) -> true: water mesh to rebuild
var _full_dirty := {}  # same, whole section (water came over / left tall grass)
var wet := {}  # Vector2i -> PackedInt32Array: water blocks per section (dry ones skip the water mesh)
var _opened := {}  # Vector2i -> deep sections reaching above this y show (0 = all: dug into)
var _cut_tick := 0.0
var _offsets: Array[Vector2i] = []  # column offsets around the focus, nearest first
var _unload_wait := 0


func _ready() -> void:
	gen = WorldGen.new(world_seed if world_seed != 0 else randi(), flat)
	if AO_OFF.is_empty():
		for n in VoxelMesh.DIRS:
			var ax := VoxelMesh.axes(Vector3(n))
			var o := PackedInt32Array()
			for k in VoxelMesh.CORNERS:
				for v: Vector3i in [n + Vector3i(ax[0]) * k.x, n + Vector3i(ax[1]) * k.y, n + Vector3i(ax[0]) * k.x + Vector3i(ax[1]) * k.y]:
					o.append(v.x + CHUNK * (v.z + CHUNK * v.y))
			AO_OFF.append(o)
	material.shader = preload("res://shaders/terrain.gdshader")
	water_material.shader = preload("res://shaders/water.gdshader")
	sway.shader = preload("res://shaders/grass.gdshader")
	_add_void_floor()
	fluids.world = self
	add_child(fluids)
	sway.set_shader_parameter("tex", _tuft_atlas())
	for k in TUFT_TILES.size():
		tuft_meshes.append(_tuft_mesh(k))
	for x in range(-VIEW - 1, VIEW + 2):
		for z in range(-VIEW - 1, VIEW + 2):
			_offsets.append(Vector2i(x, z))
	_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())


func _process(delta: float) -> void:
	stream(STREAM_BUDGET_MS)
	_flush_water(WATER_BUDGET_MS)
	$VoidFloor.position = Vector3(focus.x, -0.5, focus.z)
	_cut_tick -= delta
	if cut_y < SY and _cut_tick <= 0.0:
		_cut_tick = 0.2
		_apply_cut_visibility()


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
		elif _pending_top.has(c):
			if not _build_pending(c, _pending_top, start, budget_ms):
				return
		elif cut_y < SY and meshed.has(c) and not caps.has(c):
			_build_cap(c)
	for off in _offsets:  # surface done all around: now the underground, when it can show
		var c := center + off
		if _pending_deep.has(c):
			for s: int in _pending_deep[c].duplicate():
				if _section_visible(c, s):  # only what can show gets built
					if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
						return
					_rebuild_section(c, s)
			if _pending_deep.get(c, [1]).is_empty():
				_pending_deep.erase(c)
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
					_mesh_column(c, true)


# Builds c's waiting sections from `pending` until the budget runs out. False = out of time.
func _build_pending(c: Vector2i, pending: Dictionary, start: int, budget_ms: float) -> bool:
	var list: Array = pending[c]
	while not list.is_empty():
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return false
		_rebuild_section(c, list.back())  # removes it from the list
	pending.erase(c)
	return true


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
	return (t != AIR and not is_water(t)) or (props.has(p) and prop_shape(p).solid)


func set_block(p: Vector3i, t: int) -> void:
	set_blocks({p: t})


# cells: Vector3i -> block type. Many at once (debug scenarios): each touched section rebuilds once.
func set_blocks(cells: Dictionary) -> void:
	var done := {}
	for p: Vector3i in cells:
		if not in_bounds(p):
			continue
		var c := Vector2i(p.x >> 4, p.z >> 4)
		var i := (p.x & 15) + CHUNK * ((p.z & 15) + CHUNK * p.y)
		var old: int = _data(c)[i]
		columns[c][i] = cells[p]
		dirty[c] = true
		opaque[c][p.y / SECTION] += int(_opaque(cells[p])) - int(_opaque(old))
		wet[c][p.y / SECTION] += int(is_water(cells[p])) - int(is_water(old))
		# Sections around too: face culling and AO read across section borders.
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var q := p + Vector3i(dx, dy, dz)
					if in_bounds(q):
						done[Vector3i(q.x >> 4, q.y / SECTION, q.z >> 4)] = true
		if p.y == cut_y - 1 or p.y == cut_y:
			_free_cap(c)  # the stream rebuilds it next frame
		if p.y < _deep_below.get(c, 0) + SECTION and _opened.get(c, SY) > 0:
			_opened[c] = 0  # dug toward the caves: they all show from now on
			for s in SECTIONS:
				if meshed.has(c) and meshed[c][s]:
					meshed[c][s].visible = _section_visible(c, s)
	for key: Vector3i in done:
		_rebuild_section(Vector2i(key.x, key.z), key.y)
	for p: Vector3i in cells:
		if in_bounds(p):
			_update_nav(p)
			fluids.wake(p)  # water next to a dug / built block moves
	terrain_changed.emit()


# Water cells changed by Fluids (p -> water type or AIR). Only the water meshes rebuild (queued,
# budgeted), the terrain stays.
func apply_water(changes: Dictionary) -> void:
	for p: Vector3i in changes:
		var c := Vector2i(p.x >> 4, p.z >> 4)
		var i := (p.x & 15) + CHUNK * ((p.z & 15) + CHUNK * p.y)
		wet[c][p.y / SECTION] += int(is_water(changes[p])) - int(is_water(_data(c)[i]))
		columns[c][i] = changes[p]
		dirty[c] = true
		for dx in [-1, 0, 1]:  # sections around: faces toward p and corner heights read across
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var q := p + Vector3i(dx, dy, dz)
					if in_bounds(q):
						_water_dirty[Vector3i(q.x >> 4, q.y / SECTION, q.z >> 4)] = true
		if get_block(p + Vector3i.DOWN) == GRASS:  # tall grass drowns / grows back: full rebuild
			_full_dirty[Vector3i(c.x, (p.y - 1) / SECTION, c.y)] = true
		fluids.wake(p)
	for p: Vector3i in changes:
		_update_nav(p)
	terrain_changed.emit()


# Queued water meshes, a few per frame.
func _flush_water(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	for key: Vector3i in _full_dirty.keys():
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return
		_full_dirty.erase(key)
		_water_dirty.erase(key)  # the full rebuild redoes the water too
		_rebuild_section(Vector2i(key.x, key.z), key.y)
	for key: Vector3i in _water_dirty.keys():
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return
		_water_dirty.erase(key)
		_rebuild_water(Vector2i(key.x, key.z), key.y)


func _opaque(t: int) -> bool:
	return t != AIR and not is_water(t)


static func is_water(t: int) -> bool:
	return t == WATER or (t >= FLOW_1 and t <= FALLING)


# 8 = source or falling, 7..1 flowing, 0 = no water.
static func water_level(t: int) -> int:
	if t == WATER or t == FALLING:
		return 8
	return t - FLOW_1 + 1 if t >= FLOW_1 and t <= FLOW_7 else 0


func _data(c: Vector2i) -> PackedByteArray:
	if not columns.has(c):
		_generate(c)
	return columns[c]


func _generate(c: Vector2i) -> void:
	var g := gen.generate(c.x, c.y, CHUNK, SY)
	var blocks: PackedByteArray = g.blocks
	if g.get("opened", false):  # a cave mouth / ravine: what's behind it must show
		var y: int = int(gen.height(c.x * CHUNK + 8, c.y * CHUNK + 8)) - g.open_depth - SECTION
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				_opened[c + Vector2i(dx, dz)] = mini(_opened.get(c + Vector2i(dx, dz), SY), y)
	if saved_columns.has(c):
		blocks = saved_columns[c]
		blocks.resize(CHUNK * CHUNK * SY)  # saves from before SY grew: pad the top with air
		if saved_bottom > 0:
			var n := saved_bottom * CHUNK * CHUNK
			blocks = g.blocks.slice(0, n) + blocks.slice(n)
		saved_columns.erase(c)
		dirty[c] = true
	columns[c] = blocks
	var counts := PackedInt32Array()
	counts.resize(SECTIONS)
	var waters := PackedInt32Array()
	waters.resize(SECTIONS)
	for i in blocks.size():
		var t := blocks[i]
		if t == AIR:
			continue
		if is_water(t):
			waters[i / SECTION_VOL] += 1
		else:
			counts[i / SECTION_VOL] += 1
	opaque[c] = counts
	wet[c] = waters
	var cells := []
	for t: Dictionary in g.trees:
		t.amount = tree_left.get(t.cell, ResourceNode.amount_for(t))
		if t.amount == 0 and t.kind != "bush":
			continue  # cut down before the save (a picked bush stays and grows back)
		trees[t.cell] = t
		cells.append(t.cell)
		set_blocked(t.cell, true)
	chunk_trees[c] = cells


# Highest free cell above column (x, z), i.e. where feet stand. below: only look under that layer
# (the layer cut, for what the player points at).
func top_at(x: int, z: int, below := SY) -> int:
	for y in range(mini(below, SY) - 1, -1, -1):
		if is_solid(Vector3i(x, y, z)):
			return y + 1
	return 0


# --- Trees ---

# Places a tree or bush ({cell, kind, size, variant}) by hand (debug map); its column generates
# first so generation doesn't plant over it later.
func add_tree(t: Dictionary) -> void:
	var c := Vector2i(t.cell.x >> 4, t.cell.z >> 4)
	_data(c)
	t.amount = t.get("amount", ResourceNode.amount_for(t))
	trees[t.cell] = t
	chunk_trees[c] = chunk_trees.get(c, []) + [t.cell]
	set_blocked(t.cell, true)
	if meshed.has(c):
		_spawn_tree(t.cell)


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

# Starts showing column c: its sections queue up for stream() (now = build them all at once).
func _mesh_column(c: Vector2i, now := false) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_data(c + d)  # border faces and AO read the neighbors
	var nodes := []
	nodes.resize(SECTIONS)
	meshed[c] = nodes
	if now:
		for s in SECTIONS:
			_rebuild_section(c, s)
	else:
		# Deep = wholly under the column's lowest natural ground, tunnel roof included.
		var low := SY
		for k: Vector2i in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15), Vector2i(8, 8)]:
			low = mini(low, ground_at(c.x * CHUNK + k.x, c.y * CHUNK + k.y))
		var top := []
		var deep := []
		for s in SECTIONS:
			(deep if (s + 1) * SECTION <= low - 1 - WorldGen.CAVE_ROOF else top).append(s)
		_deep_below[c] = low - 1 - WorldGen.CAVE_ROOF
		_pending_top[c] = top
		if deep:
			_pending_deep[c] = deep
	for cell: Vector3i in chunk_trees.get(c, []):
		if trees.has(cell) and not tree_nodes.has(cell):
			_spawn_tree(cell)


func _unmesh_column(c: Vector2i) -> void:
	for n in meshed[c]:
		if n:
			n.queue_free()
	meshed.erase(c)
	_deep_below.erase(c)
	_pending_top.erase(c)
	_pending_deep.erase(c)
	_free_cap(c)
	for cell: Vector3i in chunk_trees.get(c, []):
		if tree_nodes.has(cell) and tree_nodes[cell].claims == 0:
			tree_nodes[cell].queue_free()
			tree_nodes.erase(cell)


func _rebuild_section(c: Vector2i, s: int) -> void:
	if not meshed.has(c):
		return
	_pending_top.get(c, []).erase(s)
	if s in _pending_deep.get(c, []):
		_pending_deep[c].erase(s)
		if s <= (cut_y - 1) / SECTION:
			_free_cap(c)  # its dark placeholder holes give way to the real caves
	if meshed[c][s]:
		meshed[c][s].queue_free()
	# All air: nothing to draw (water only lies at or below WATER_LEVEL and isn't counted as opaque).
	var empty: bool = opaque[c][s] == 0 and wet[c][s] == 0
	meshed[c][s] = null if empty or _buried(c, s) else _build_section(c, s)
	if meshed[c][s]:
		meshed[c][s].visible = _section_visible(c, s)


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
	var faces := 0
	var grass_tops: Array[Vector3i] = []
	var col_props := false  # solid pieces shade too: then AO goes the slow way (is_solid)
	for q: Vector3i in props:
		if q.x >> 4 == c.x and q.z >> 4 == c.y:
			col_props = true
			break
	for y in range(s * SECTION, (s + 1) * SECTION):
		for lz in CHUNK:
			for lx in CHUNK:
				var i := lx + CHUNK * (lz + CHUNK * y)
				var t := data[i]
				if t == AIR or t == WATER or (t >= FLOW_1 and t <= FALLING):  # is_water, inlined: hot loop
					continue  # water: _water_mesh
				var p := Vector3i(c.x * CHUNK + lx, y, c.y * CHUNK + lz)
				var inner := lx > 0 and lz > 0 and y > 0 and lx < CHUNK - 1 and lz < CHUNK - 1 and y < SY - 1
				for k in 6:
					var nb: int = data[i + N_OFF[k]] if inner else get_block(p + VoxelMesh.DIRS[k])
					if nb == AIR or nb == WATER or (nb >= FLOW_1 and nb <= FALLING):
						if inner and not col_props:
							_add_inner_face(st, p, k, t, data, i)
						else:
							_add_block_face(st, p, VoxelMesh.DIRS[k], t)
						faces += 1
				if t == GRASS and y < SY - 1 and data[i + CHUNK * CHUNK] == AIR:
					grass_tops.append(p + Vector3i.UP)
	var water := _water_mesh(c, s)
	if faces == 0 and water == null:
		return null
	var node := Node3D.new()
	add_child(node)
	if faces > 0:
		st.set_material(material)
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		node.add_child(mi)  # no collision: picking walks the voxel grid (raycast_cells)
	if water:
		node.add_child(water)
	_add_tufts(node, grass_tops)
	return node


# The water of section s, its own mesh so the water can change without rebuilding the terrain
# (water never changes terrain faces or AO). Surface height by level.
func _water_mesh(c: Vector2i, s: int) -> MeshInstance3D:
	if wet[c][s] == 0:
		return null
	var data: PackedByteArray = columns[c]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	var heights := {}  # cell -> surface height, shared by the corners around it
	for y in range(s * SECTION, (s + 1) * SECTION):
		for lz in CHUNK:
			for lx in CHUNK:
				var i := lx + CHUNK * (lz + CHUNK * y)
				var t := data[i]
				if t != WATER and (t < FLOW_1 or t > FALLING):
					continue
				var p := Vector3i(c.x * CHUNK + lx, y, c.y * CHUNK + lz)
				var inner := lx > 0 and lz > 0 and y > 0 and lx < CHUNK - 1 and lz < CHUNK - 1 and y < SY - 1
				var flow := Color(0.5, 0.5, 1.0 if t == FALLING else 0.0)  # see _water_flow
				var corners := {}  # Vector2i(0..1, 0..1) -> height
				if inner and t == WATER and _still_surface(data, i):
					corners = STILL_CORNERS  # lake / sea / river: flat
					flow = _river_color(p)
				for k in 6:
					var nb: int = data[i + N_OFF[k]] if inner else get_block(p + VoxelMesh.DIRS[k])
					if nb != AIR:
						continue  # only faces toward air (water next to water is one surface)
					var n := VoxelMesh.DIRS[k]
					if corners.is_empty():
						for a in 2:
							for b in 2:
								corners[Vector2i(a, b)] = _corner_height(p, a, b, heights)
						flow = _water_flow(p, t, heights)
					_add_water_face(st, p, n, corners, flow)
					faces += 1
	if faces == 0:
		return null
	st.set_material(water_material)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# Source with sources all around and nothing on top of any of them: open lake or sea surface.
func _still_surface(data: PackedByteArray, i: int) -> bool:
	for o in STILL_OFF:
		if data[i + o] != WATER or data[i + o + CHUNK * CHUNK] != AIR:
			return false
	return true


func _water_height(t: int, p: Vector3i) -> float:
	if t == FALLING or is_water(get_block(p + Vector3i.UP)):
		return 1.0
	return 0.88 if t == WATER else 0.1 + 0.11 * water_level(t)


# Height of the surface at corner (a, b) of cell p (Minecraft style): the average of the water
# cells sharing that corner, or the full block if any of them has water on top (a falling column).
# Neighbors share corners, so the surface slopes between levels with no steps or gaps.
func _corner_height(p: Vector3i, a: int, b: int, heights: Dictionary) -> float:
	var sum := 0.0
	var n := 0
	for dx in [a - 1, a]:
		for dz in [b - 1, b]:
			var q := p + Vector3i(dx, 0, dz)
			if not heights.has(q):
				var t := get_block(q)
				heights[q] = _water_height(t, q) if is_water(t) else -1.0
			var h: float = heights[q]
			if h >= 1.0:
				return 1.0
			if h >= 0.0:
				sum += h
				n += 1
	return sum / n


# Which way p's water runs, packed in a vertex color for the shader: r, g = x, z direction
# (0.5 = none), b = 1 for a falling column. Downhill toward lower water and toward drops at the edge.
func _water_flow(p: Vector3i, t: int, heights: Dictionary) -> Color:
	if t == FALLING:
		return Color(0.5, 0.5, 1.0)
	var h: float = heights.get(p, _water_height(t, p))
	var v := Vector2.ZERO
	for d in H_DIRS:
		var q := p + d
		var tq := get_block(q)
		if is_water(tq):
			v += Vector2(d.x, d.z) * (h - _water_height(tq, q))
		elif tq == AIR and not is_solid(q + Vector3i.DOWN):
			v += Vector2(d.x, d.z) * h  # spills over the edge
	if t == WATER and v.length() < 0.3:
		return _river_color(p)  # still water, unless a river runs here
	v = v.normalized() if v.length() > 0.001 else Vector2.ZERO
	return Color(0.5 + v.x * 0.5, 0.5 + v.y * 0.5, 0.0)


# A river's current (WorldGen.river_flow) as a flow color; still otherwise.
func _river_color(p: Vector3i) -> Color:
	var f := gen.river_flow(p.x, p.z)
	return Color(0.5 + f.x * 0.5, 0.5 + f.y * 0.5, 0.0)


# Rebuilds only the water of section s (the terrain didn't change).
func _rebuild_water(c: Vector2i, s: int) -> void:
	if not meshed.has(c) or s < 0 or s >= SECTIONS:
		return
	var node: Node3D = meshed[c][s]
	if node == null:
		_rebuild_section(c, s)
		return
	var old := node.get_node_or_null("Water")
	if old:
		old.free()
	var water := _water_mesh(c, s)
	if water:
		node.add_child(water)


# Dark floor under the bedrock, following the camera: looking down a hole into caves that aren't
# meshed (hidden deep, still streaming) shows darkness instead of the sky.
func _add_void_floor() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.02, 0.02, 0.02)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (VIEW + 2) * CHUNK * 2
	plane.material = m
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "VoidFloor"
	floor_mi.mesh = plane
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_mi.position.y = -0.5
	add_child(floor_mi)


# --- Seeing inside (layer cut, x-ray) ---

# Hide every layer from y up (SY = show all). Caps on the cut plane stream in nearest first.
func set_cut(y: int) -> void:
	cut_y = clampi(y, 1, SY)
	for m: ShaderMaterial in [material, water_material, sway]:
		m.set_shader_parameter("cut_y", float(cut_y))
	for c: Vector2i in caps.keys():
		_free_cap(c)
	_show_sections()
	_apply_cut_visibility()
	cut_changed.emit()


# Feet level of the natural ground at (x, z): buildings and digging don't move it.
func ground_at(x: int, z: int) -> int:
	return clampi(int(gen.height(x, z)) + 1, 1, SY - 1)


# Jump the cut to a villager's floor (clicked / picked in the top bar): its two body cells show,
# everything over its head hides. Out in the open with no cut on, the view stays as it is.
func cut_to(feet: Vector3) -> void:
	var y := floori(feet.y + 0.01)
	if cut_y >= SY and top_at(floori(feet.x), floori(feet.z)) <= y:
		return
	set_cut(y + 2)


func _show_sections() -> void:
	for c: Vector2i in meshed:
		for s in SECTIONS:
			if meshed[c][s]:
				meshed[c][s].visible = _section_visible(c, s)


func _section_visible(c: Vector2i, s: int) -> bool:
	if s * SECTION >= cut_y:
		return false
	var deep: bool = (s + 1) * SECTION <= _deep_below.get(c, 0)
	return not deep or cut_y < SY or xray_cursor or (s + 1) * SECTION > _opened.get(c, SY)


# Up to XRAY_MAX world points the camera sees through the ground to (selected villagers, cursor).
func set_xray(points: Array[Vector3]) -> void:
	var v := PackedVector4Array()
	v.resize(XRAY_MAX)
	for i in mini(points.size(), XRAY_MAX):
		v[i] = Vector4(points[i].x, points[i].y, points[i].z, 1.0)
	for m: ShaderMaterial in [material, water_material, sway]:
		m.set_shader_parameter("xray", v)


# Things standing in a hidden layer (feet above the cut's top visible block) disappear whole.
func _apply_cut_visibility() -> void:
	var nodes: Array = tree_nodes.values() + prop_nodes.values()
	for g in ["workers", "animals", "corpses"]:
		nodes.append_array(get_tree().get_nodes_in_group(g))
	for parent in get_tree().get_nodes_in_group("cut_hide_children"):  # stockpile items, crops
		nodes.append_array(parent.get_children())
	for n in nodes:
		if is_instance_valid(n) and n is Node3D:
			n.visible = floori(n.global_position.y + 0.01) <= cut_y


func _build_cap(c: Vector2i) -> void:
	caps[c] = null
	var y := cut_y - 1
	if y < 0 or y >= SY - 1:
		return
	var data: PackedByteArray = columns[c]
	var unbuilt: bool = _pending_deep.get(c, []).any(func(k: int) -> bool: return k <= y / SECTION)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	for lz in CHUNK:
		for lx in CHUNK:
			var i := lx + CHUNK * (lz + CHUNK * y)
			var t := data[i]
			var col := Color.TRANSPARENT
			if _opaque(t) and _opaque(data[i + CHUNK * CHUNK]):
				col = Color(COLORS[t], 1.0)
			elif t == AIR and unbuilt:
				col = Color(0.03, 0.03, 0.03, 1.0)  # cave not meshed yet: dark, not sky
			if col.a > 0:
				VoxelMesh.add_face(st, Vector3(c.x * CHUNK + lx, y, c.y * CHUNK + lz), Vector3.UP, [col, col, col, col], 1.0, Vector2(0 if t == AIR else t, 1))
				faces += 1
	if faces == 0:
		return
	st.set_material(material)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	caps[c] = mi


func _free_cap(c: Vector2i) -> void:
	if caps.get(c):
		caps[c].queue_free()
	caps.erase(c)


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


# Same as _add_block_face for a block away from the column's edges: AO read straight from the
# column array (the hot path when meshing caves: 12 lookups per face).
func _add_inner_face(st: SurfaceTool, p: Vector3i, k: int, t: int, data: PackedByteArray, i: int) -> void:
	var o: PackedInt32Array = AO_OFF[k]
	var cols: Array[Color] = []
	for j in 4:
		var a := data[i + o[j * 3]]
		var b := data[i + o[j * 3 + 1]]
		var d := data[i + o[j * 3 + 2]]
		# Solid = not air and not water (is_water inlined: 12 lookups per face).
		var s1 := a != AIR and a != WATER and (a < FLOW_1 or a > FALLING)
		var s2 := b != AIR and b != WATER and (b < FLOW_1 or b > FALLING)
		var s3 := d != AIR and d != WATER and (d < FLOW_1 or d > FALLING)
		var open := 0 if s1 and s2 else 3 - int(s1) - int(s2) - int(s3)
		cols.append(Color(COLORS[t], AO_LIGHT[open]))
	VoxelMesh.add_face(st, Vector3(p), Vector3(VoxelMesh.DIRS[k]), cols, 1.0, Vector2(t, 0))


# Water face of cell p toward air: the top edge follows the surface's corner heights
# (_corner_height); flow goes to the shader in the vertex color (_water_flow).
func _add_water_face(st: SurfaceTool, p: Vector3i, n: Vector3i, corners: Dictionary, flow: Color) -> void:
	var ax := VoxelMesh.axes(Vector3(n))
	var c := Vector3(p) + Vector3.ONE * 0.5 + Vector3(n) * 0.5
	var q: Array[Vector3] = []
	for k in VoxelMesh.CORNERS:
		var v := c + (ax[0] * k.x + ax[1] * k.y) * 0.5
		if v.y > p.y + 0.5:  # top edge: the shared corner height
			v.y = p.y + corners[Vector2i(roundi(v.x - p.x), roundi(v.z - p.z))]
		q.append(v)
	var normal := Vector3(n)
	if n == Vector3i.UP:  # sloped surface: real normal for the light
		normal = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
		if normal.y < 0:
			normal = -normal
	st.set_normal(normal)
	st.set_color(flow)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[i])


# Tall grass and flowers on exposed grass blocks. Seeded per column so rebuilds don't reshuffle.
func _add_tufts(node: Node3D, spots: Array[Vector3i]) -> void:
	var lists: Array = []
	for k in TUFT_TILES.size():
		lists.append([])
	var rng := RandomNumberGenerator.new()
	for p in spots:
		if blocked.has(p) or props.has(p) or bare.has(p):
			continue
		rng.seed = hash(Vector2i(p.x, p.z))
		var roll := rng.randf()
		if roll > GRASS_CHANCE:
			continue
		var kind := 0 if roll > FLOWER_CHANCE else 1 + rng.randi() % (TUFT_TILES.size() - 1)
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
		mmi.visibility_range_end = TUFT_RANGE  # far grass is a few pixels: skip it
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)


# Tuft = two crossed quads showing a pixel-art tile with cut-out alpha (Minecraft style): 4 triangles
# per tuft instead of dozens of voxel faces. Tile `kind` of the TUFT_TILES atlas.
func _tuft_mesh(kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)  # lit like the ground under it (the shader forces this too)
	var u0 := float(kind) / TUFT_TILES.size()
	var u1 := float(kind + 1) / TUFT_TILES.size()
	var r := TUFT_SIZE / 2.0
	for d: Vector2 in [Vector2(r, r), Vector2(r, -r)]:  # the two diagonals of the cell
		var q := [Vector3(-d.x, 0, -d.y), Vector3(d.x, 0, d.y), Vector3(d.x, TUFT_SIZE, d.y), Vector3(-d.x, TUFT_SIZE, -d.y)]
		var uv := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:  # winding doesn't matter: the grass shader draws both sides
			st.set_uv(uv[i])
			st.add_vertex(q[i])
	return st.commit()


# 16x16 pixel tiles side by side: tall grass, then a flower over short grass per TUFT_TILES color.
func _tuft_atlas() -> ImageTexture:
	var n := TUFT_TILES.size()
	var img := Image.create(16 * n, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for k in n:
		var ox := 16 * k
		var flower: bool = k > 0
		for x in 16:
			if rng.randf() < 0.2:
				continue  # gap between blades
			var h := rng.randi_range(3, 8) if flower else rng.randi_range(6, 15)
			var lean := rng.randi_range(-1, 1)
			for i in h:
				var t := float(i) / h
				# Base = the grass block color so tufts melt into the ground; only the tips get lighter.
				var col := (COLORS[GRASS] as Color).lerp(Color(0.6, 0.84, 0.34), t) * rng.randf_range(0.95, 1.05)
				var px := clampi(x + (lean if t > 0.7 else 0), 0, 15)  # tips bend a little
				img.set_pixel(ox + px, 15 - i, Color(col, 1))
		if flower:
			var petal: Color = TUFT_TILES[k][0]
			var heart: Color = TUFT_TILES[k][1]
			for y in range(5, 16):
				img.set_pixel(ox + 7, y, Color(0.3, 0.55, 0.2))  # stem
			img.set_pixel(ox + 8, 10, Color(0.35, 0.62, 0.22))  # leaf
			for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
				img.set_pixel(ox + 7 + o.x, 3 + o.y, petal if o.length() < 2 or rng.randf() < 0.8 else petal.darkened(0.15))
			img.set_pixel(ox + 7, 3, heart)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
		if cell.y < cut_y and hit.call(cell):  # hidden layers can't be pointed at
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
# Shallow water: water at the feet only (head in the air), ground underneath. Villagers wade
# through it, slower; deeper water isn't in the nav at all.
func wadeable(p: Vector3i) -> bool:
	var head := p + Vector3i.UP
	return is_water(get_block(p)) and not is_solid(p) and not is_water(get_block(head)) and not is_solid(head) \
		and is_solid(p + Vector3i.DOWN)


# Dry ground to stand on (spawns, zones and fields want this; the nav also takes wadeable).
func walkable(p: Vector3i) -> bool:
	return not is_solid(p) and not is_water(get_block(p)) and not is_solid(p + Vector3i.UP) \
		and is_solid(p + Vector3i.DOWN)


func set_blocked(p: Vector3i, on: bool) -> void:
	if on:
		blocked[p] = true
	else:
		blocked.erase(p)
	if in_bounds(p) and astar.has_point(idx(p)):
		astar.set_point_disabled(idx(p), on)


# Nearest place to stand (dry or wading) around pos, for someone swimming; INF if none.
func nearest_footing(pos: Vector3) -> Vector3:
	var id := _nearest_point(pos)
	return astar.get_point_position(id) if id != -1 else Vector3.INF


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
	# Sky sections (no ground in them or just below, no built pieces) have nothing to stand on.
	var with_props := {}
	for p: Vector3i in props:
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			with_props[p.y / SECTION] = true
	for y in range(1, SY - 1):
		var s := y / SECTION
		if opaque[c][s] == 0 and (s == 0 or opaque[c][s - 1] == 0) and not with_props.has(s):
			continue
		if opaque[c][s] == SECTION_VOL:
			continue  # solid all through: nowhere to stand
		for lz in CHUNK:
			for lx in CHUNK:
				var i := lx + CHUNK * (lz + CHUNK * y)
				var t := data[i]
				if t != AIR and t != WATER and (t < FLOW_1 or t > FALLING):
					continue  # solid (air and shallow water can be stood in)
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
	var wade := not hanging and wadeable(p)
	if not hanging and not wade and not walkable(p):
		return false
	# Slabs and stairs: you stand on top of them, half a block up. Wading costs more.
	astar.add_point(idx(p), Vector3(p) + Vector3(0.5, prop_shape(p).get("floor", 0.0), 0.5), WADE_COST if wade else 1.0)
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

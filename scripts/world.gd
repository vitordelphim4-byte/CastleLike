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
# Section meshes are built from a padded copy: the section plus 1 block all around (P per side).
const P := SECTION + 2
const P_OFF := [1, -1, P * P, -P * P, P, -P]  # padded index offsets matching VoxelMesh.DIRS
const MAX_JOBS := 4
const UNLOAD_MS := 1.0
const NAV_SLAB := 4  # layers of a column's nav built per step while streaming  # section meshes being built on worker threads at once
# AO_OFF[k][corner * 3 + 0..2]: padded index offsets of the 3 cells shading each corner of a face
# in direction k (side, other side, diagonal).
static var AO_OFF: Array[PackedInt32Array] = []
const XRAY_MAX := 9  # matches view_clip.gdshaderinc
const INSIDE_LIGHT := 0.4  # least light underground while cutting / x-raying (shader min_light)
const WADE_COST := 3.0  # A* weight of a shallow-water cell: paths go around when it's cheap to
# Lake / sea surface shortcut (_still_surface): the 8 cells around (and the cell itself), and the
# corners every such cell gets.
const STILL_OFF := [0, 1, -1, CHUNK, -CHUNK, CHUNK + 1, CHUNK - 1, -CHUNK + 1, -CHUNK - 1]
const STILL_CORNERS := {Vector2i(0, 0): 8.0 / 9.0, Vector2i(1, 0): 8.0 / 9.0, Vector2i(0, 1): 8.0 / 9.0, Vector2i(1, 1): 8.0 / 9.0}

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
var _nav_pending := {}  # Vector2i -> sections whose nav is still to build (Phase 10g)
var _tree_pending := {}  # Vector2i -> tree cells still to spawn
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
		_set_min_light()
# Deep sections (wholly under the column's natural ground, caves only) are hidden unless something
# can show them: a layer cut, the cursor x-ray, or digging in that column (opened).
var _deep_below := {}  # Vector2i -> sections whose top is at or under this y are deep
# Background generation (Phase 10g): a worker thread with its own WorldGen (generation is a pure
# function of seed and position, so nothing is shared) generates the columns stream() will need
# next. _generate takes the finished ones; a column needed before it's ready is made right there.
var GEN_AHEAD := 12  # columns queued for the worker at most (0 = no worker: benchmarks)
var _gen_thread: Thread
var _gen_mutex := Mutex.new()
var _gen_sem := Semaphore.new()
var _gen_queue: Array[Vector2i] = []  # waiting for the worker, nearest first
var _gen_busy := {}  # Vector2i -> true: queued or being generated
var _gen_done := {}  # Vector2i -> generate() result
var _gen_quit := false
var _tree_models := {}  # tree models the worker built, handed over in _request_ahead
# Section meshes on WorkerThreadPool (Phase 10g): stream() hands the waiting sections to _terrain on
# a worker, with a copy of what it reads (_snapshot), and places the results. Edits rebuild right
# away; a job for a section edited meanwhile is dropped (_sec_ver).
var _jobs := {}  # Vector3i(cx, s, cz) -> {id, ver, snap}
var _sec_ver := {}  # Vector3i(cx, s, cz) -> times rebuilt
var fluids := Fluids.new()
var _water_dirty := {}  # Vector3i(cx, section, cz) -> true: water mesh to rebuild
var _full_dirty := {}  # same, whole section (water came over / left tall grass)
# Sky light (Phase 10f), Minecraft style 0..15: cells over a column's highest opaque block (heights)
# get 15; light reaches under overhangs, down shafts and into cave mouths losing 1 per block.
# Stored sparse per column (sky): only lit cells under the top; anything else down there is dark.
var heights := {}  # Vector2i -> PackedInt32Array(256): highest opaque y per spot, -1 none
var sky := {}  # Vector2i -> Dictionary Vector3i -> light (cells under the top that some light reaches)
var _sky_src := {}  # Vector2i -> the light entering through that column's openings (_sky_from)
var flows := {}  # Vector2i -> PackedVector2Array(256): river current per spot (WorldGen.generate)
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
					o.append(v.x + P * (v.z + P * v.y))
			AO_OFF.append(o)
		MeshBuf.new()  # its static corner table, made here and not on a worker
	material.shader = preload("res://shaders/terrain.gdshader")
	water_material.shader = preload("res://shaders/water.gdshader")
	sway.shader = preload("res://shaders/grass.gdshader")
	_add_void_floor()
	fluids.world = self
	add_child(fluids)
	_set_min_light()
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
	_request_ahead(center)
	_unload_far(center, start)
	_run_jobs(start, budget_ms)
	for off in _offsets:
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return
		var c := center + off
		var ring := maxi(absi(off.x), absi(off.y))
		if not nav_built.has(c):
			if _column_ready(c):
				_build_nav(c, false)
		elif _nav_pending.has(c):
			var todo: Array = _nav_pending[c]
			while not todo.is_empty():
				if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
					return
				var y: int = todo.pop_back()
				_nav_layers(c, y, y + NAV_SLAB)
			_nav_pending.erase(c)
		elif ring <= VIEW and not meshed.has(c):
			if _around_ready(c):
				_mesh_column(c)
		elif _pending_top.has(c) and not _sky_ready(c):
			continue
		elif _pending_top.has(c):
			if not _build_pending(c, _pending_top, start, budget_ms):
				return
		elif _tree_pending.has(c):
			var cells: Array = _tree_pending[c]
			while not cells.is_empty():
				if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
					return
				var cell: Vector3i = cells.pop_back()
				if trees.has(cell) and not tree_nodes.has(cell):
					_spawn_tree(cell)
			_tree_pending.erase(c)
		elif cut_y < SY and meshed.has(c) and not caps.has(c):
			_build_cap(c)
	for off in _offsets:  # surface done all around: now the underground, when it can show
		var c := center + off
		if _pending_deep.has(c):
			for s: int in _pending_deep[c].duplicate():
				if _section_visible(c, s):  # only what can show gets built
					if (Time.get_ticks_usec() - start) > budget_ms * 1000.0 or not _sky_ready(c):
						return
					if not _start_job(c, s):
						return  # every worker busy
			if _pending_deep.get(c, [1]).is_empty():
				_pending_deep.erase(c)


# Every ~30 frames, frees the meshes that fell behind, at most UNLOAD_MS per frame (a whole ring at
# once took up to 80 ms); what's left goes on the next frame.
func _unload_far(center: Vector2i, start: int) -> void:
	_unload_wait += 1
	if _unload_wait <= 30:
		return
	for c: Vector2i in meshed.keys():
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) > KEEP:
			if (Time.get_ticks_usec() - start) > UNLOAD_MS * 1000.0:
				return
			_unmesh_column(c)
	_unload_wait = 0


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


# Starts c's waiting sections from `pending` on workers until the budget runs out (false) or every
# worker is busy (the rest wait for a later frame).
func _build_pending(c: Vector2i, pending: Dictionary, start: int, budget_ms: float) -> bool:
	var list: Array = pending[c]
	while not list.is_empty():
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return false
		if not _start_job(c, list.back()):  # removes it from the list
			return true
	pending.erase(c)
	return true


# Sky light ready for c and its 4 sides (section meshes read it through their faces); else one
# step toward it (one neighbor's openings, ~1.5 ms) and false.
func _sky_ready(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not sky.has(c + d):
			_data(c + d)
			_sky_step(c + d)
			return false
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
		_update_height(p)
		for dx in range(-2, 3):  # the sky light around may change: computed again when asked
			for dz in range(-2, 3):
				sky.erase(c + Vector2i(dx, dz))
				if absi(dx) < 2 and absi(dz) < 2:
					_sky_src.erase(c + Vector2i(dx, dz))
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
		if key.y not in _pending_deep.get(Vector2i(key.x, key.z), []):  # not built yet: it'll have the water
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
	var g := _take_generated(c)
	if g.is_empty():
		g = gen.generate(c.x, c.y, CHUNK, SY)
	var blocks: PackedByteArray = g.blocks
	if g.get("opened", false):  # a cave mouth / ravine: what's behind it must show
		var y: int = int(gen.height(c.x * CHUNK + 8, c.y * CHUNK + 8)) - g.open_depth - SECTION
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				_opened[c + Vector2i(dx, dz)] = mini(_opened.get(c + Vector2i(dx, dz), SY), y)
	var saved := saved_columns.has(c)
	if saved:
		blocks = saved_columns[c]
		blocks.resize(CHUNK * CHUNK * SY)  # saves from before SY grew: pad the top with air
		if saved_bottom > 0:
			var n := saved_bottom * CHUNK * CHUNK
			blocks = g.blocks.slice(0, n) + blocks.slice(n)
		saved_columns.erase(c)
		dirty[c] = true
	columns[c] = blocks
	flows[c] = g.flow
	for p: Vector3i in g.get("springs", []):  # cave waterfalls run once, then sit still
		fluids.wake(p)
	if not g.has("top") or saved:
		g.merge(_column_stats(blocks), true)  # made here, or a saved column replaced the generated one
	opaque[c] = g.counts
	wet[c] = g.waters
	heights[c] = g.top
	var cells := []
	for t: Dictionary in g.trees:
		t.amount = tree_left.get(t.cell, ResourceNode.amount_for(t))
		if t.amount == 0 and t.kind != "bush":
			continue  # cut down before the save (a picked bush stays and grows back)
		trees[t.cell] = t
		cells.append(t.cell)
		set_blocked(t.cell, true)
	chunk_trees[c] = cells


# Per-section counts of opaque and water blocks, and the highest opaque y per spot (-1: none).
# Static: the generating thread runs it too.
static func _column_stats(blocks: PackedByteArray) -> Dictionary:
	# Per-section counts with the engine's own count() (a GDScript loop over 49k blocks took ~10 ms).
	var counts := PackedInt32Array()
	counts.resize(SECTIONS)
	var waters := PackedInt32Array()
	waters.resize(SECTIONS)
	var high := -1  # highest section with anything opaque
	for s in SECTIONS:
		var sec := blocks.slice(s * SECTION_VOL, (s + 1) * SECTION_VOL)
		var w := sec.count(WATER)
		for t in range(FLOW_1, FALLING + 1):
			w += sec.count(t)
		waters[s] = w
		counts[s] = SECTION_VOL - sec.count(AIR) - w
		if counts[s] > 0:
			high = s
	# Highest opaque block per spot: scan down from the top of the highest opaque section.
	var top := PackedInt32Array()
	top.resize(CHUNK * CHUNK)
	for k in CHUNK * CHUNK:
		var y := (high + 1) * SECTION - 1
		while y >= 0:
			var t := blocks[k + CHUNK * CHUNK * y]
			if t != AIR and t != WATER and (t < FLOW_1 or t > FALLING):
				break
			y -= 1
		top[k] = y
	return {counts = counts, waters = waters, top = top}


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
	if now:  # the surface right away; the underground streams in when it can show (like any column)
		for s: int in _pending_top[c].duplicate():
			_rebuild_section(c, s)
		_pending_top.erase(c)
	if now:
		for cell: Vector3i in chunk_trees.get(c, []):
			if trees.has(cell) and not tree_nodes.has(cell):
				_spawn_tree(cell)
	else:  # stream() spawns them a few per frame
		_tree_pending[c] = chunk_trees.get(c, []).duplicate()


func _unmesh_column(c: Vector2i) -> void:
	for n in meshed[c]:
		if n:
			n.queue_free()
	meshed.erase(c)
	_tree_pending.erase(c)
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
	_unpend(c, s)
	var key := Vector3i(c.x, s, c.y)
	_sec_ver[key] = _sec_ver.get(key, 0) + 1  # a worker job still running for it is stale now
	_place_section(c, s, null if _skip_section(c, s) else _terrain(_snapshot(c, s, false)))


func _unpend(c: Vector2i, s: int) -> void:
	_pending_top.get(c, []).erase(s)
	if s in _pending_deep.get(c, []):
		_pending_deep[c].erase(s)
		if s <= (cut_y - 1) / SECTION:
			_free_cap(c)  # its dark placeholder holes give way to the real caves


# All air (water only lies at or below WATER_LEVEL and isn't counted as opaque), or buried.
func _skip_section(c: Vector2i, s: int) -> bool:
	return (opaque[c][s] == 0 and wet[c][s] == 0) or _buried(c, s)


# Puts the section's node in place: terrain = _terrain's result (null: nothing to draw).
func _place_section(c: Vector2i, s: int, terrain: Variant) -> void:
	if meshed[c][s]:
		meshed[c][s].queue_free()
	meshed[c][s] = _build_section(c, s, terrain) if terrain != null else null
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


func _build_section(c: Vector2i, s: int, terrain: Dictionary) -> Node3D:
	var faces: int = terrain.faces
	var grass_tops: Array[Vector3i] = terrain.grass
	var water := _water_mesh(c, s)
	if faces == 0 and water == null:
		return null
	var node := Node3D.new()
	add_child(node)
	if faces > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = terrain.buf.commit(material)
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
				if inner and data[i + 1] != AIR and data[i - 1] != AIR and data[i + CHUNK] != AIR 						and data[i - CHUNK] != AIR and data[i + CHUNK * CHUNK] != AIR and data[i - CHUNK * CHUNK] != AIR:
					continue  # no face toward air: nothing to draw (most of a lake or the sea)
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
	return 8.0 / 9.0 if t == WATER else water_level(t) / 9.0  # Minecraft: source 8/9, flowing level/9


# Height of the surface at corner (a, b) of cell p, Minecraft's rule: over the 4 cells sharing the
# corner, the full block if any has water on top (a falling column); else the weighted average of
# their water depth, where sources and falling water count 11 times, flowing water once, and an
# open (air) cell counts once as empty. So the surface slopes down to an edge and drapes over it
# (smooth falls), and neighbors share corners: no steps or gaps. Solid cells don't count.
func _corner_height(p: Vector3i, a: int, b: int, heights: Dictionary) -> float:
	var depth := 0.0
	var n := 0
	for dx in [a - 1, a]:
		for dz in [b - 1, b]:
			var q := p + Vector3i(dx, 0, dz)
			if not heights.has(q):
				var t := get_block(q)
				if is_water(t):
					heights[q] = _water_height(t, q) + (10.0 if t == WATER or t == FALLING else 0.0)  # +10: heavy
				else:
					heights[q] = -1.0 if is_solid(q) else -2.0  # -2: open air
			var h: float = heights[q]
			if h == -1.0:
				continue
			if h == -2.0:
				depth += 1.0
				n += 1
				continue
			var heavy := h >= 10.0
			h -= 10.0 if heavy else 0.0
			if h >= 1.0:
				return 1.0
			depth += (1.0 - h) * (11 if heavy else 1)
			n += 11 if heavy else 1
	return 1.0 - depth / n


# Which way p's water runs, packed in a vertex color for the shader: r, g = x, z direction
# (0.5 = none), b = 1 for a falling column. Downhill toward lower water and toward drops at the edge.
func _water_flow(p: Vector3i, t: int, _heights: Dictionary) -> Color:
	if t == FALLING:
		return Color(0.5, 0.5, 1.0)
	var h := _water_height(t, p)
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
	var c := Vector2i(p.x >> 4, p.z >> 4)
	var f: Vector2 = flows[c][(p.x & 15) + CHUNK * (p.z & 15)] if flows.has(c) else gen.river_flow(p.x, p.z)
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


# --- Background generation (Phase 10g) ---

# Queues the nearest columns that don't exist yet, up to GEN_AHEAD waiting.
func _request_ahead(center: Vector2i) -> void:
	if GEN_AHEAD == 0:
		return
	if _gen_thread == null:
		VoxelMesh.build({}, 1.0)  # makes the shared voxel material here, not on two threads at once
		_gen_thread = Thread.new()
		_gen_thread.start(_gen_worker.bind(gen.world_seed, gen.flat))
	_gen_mutex.lock()
	for key: String in _tree_models:  # models the worker made: the main thread uses them from now on
		if not ResourceNode._meshes.has(key):
			ResourceNode._meshes[key] = _tree_models[key]
	_tree_models = {}
	var room := GEN_AHEAD - _gen_queue.size()
	for c: Vector2i in _gen_done.keys():  # finished after the column was made here anyway
		if columns.has(c):
			_gen_done.erase(c)
	_gen_mutex.unlock()
	if room <= 0:
		return
	for off in _offsets:
		var c := center + off
		if columns.has(c) or _gen_busy.has(c):
			continue
		_gen_busy[c] = true
		_gen_mutex.lock()
		_gen_queue.append(c)
		_gen_mutex.unlock()
		_gen_sem.post()
		room -= 1
		if room == 0:
			return


# Column c can be used without generating it here: it exists, or the worker has it done. Else the
# worker gets it soon (_request_ahead), and the stream waits for it (no worker: made here).
func _column_ready(c: Vector2i) -> bool:
	if columns.has(c) or GEN_AHEAD == 0:
		return true
	if not _gen_busy.has(c):
		return false
	_gen_mutex.lock()
	var done := _gen_done.has(c)
	_gen_mutex.unlock()
	return done


# c and the 8 around it ready (_column_ready): meshes read across the borders.
func _around_ready(c: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if not _column_ready(c + Vector2i(dx, dz)):
				return false
	return true


# The worker's result for c, or {} if it isn't done (then it's dropped from the queue: the caller
# generates it now).
func _take_generated(c: Vector2i) -> Dictionary:
	if not _gen_busy.has(c):
		return {}
	_gen_mutex.lock()
	var g: Dictionary = _gen_done.get(c, {})
	_gen_done.erase(c)
	_gen_queue.erase(c)
	_gen_mutex.unlock()
	_gen_busy.erase(c)
	return g


func _gen_worker(seed_value: int, is_flat: bool) -> void:
	# First the tree models (each built the first time it shows took up to ~100 ms on the main thread).
	var models := {}
	var maker := ResourceNode.new()
	for kind in ["oak", "pine"]:
		for size in 3:
			for variant in 4:
				var key := "%s_%d_%d" % [kind, size, variant]
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(key)
				models[key] = maker._tree(rng, kind == "pine", size)
	maker.free()
	_gen_mutex.lock()
	_tree_models = models
	_gen_mutex.unlock()
	var wg := WorldGen.new(seed_value, is_flat)
	while true:
		_gen_sem.wait()
		_gen_mutex.lock()
		if _gen_quit:
			_gen_mutex.unlock()
			return
		var c: Vector2i = _gen_queue.pop_front() if not _gen_queue.is_empty() else Vector2i.MAX
		_gen_mutex.unlock()
		if c == Vector2i.MAX:
			continue
		var g := wg.generate(c.x, c.y, CHUNK, SY)
		g.merge(_column_stats(g.blocks))
		_gen_mutex.lock()
		_gen_done[c] = g
		_gen_mutex.unlock()


func _exit_tree() -> void:
	for key: Vector3i in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[key].id)
	_jobs.clear()
	if _gen_thread:
		_gen_mutex.lock()
		_gen_quit = true
		_gen_mutex.unlock()
		_gen_sem.post()
		_gen_thread.wait_to_finish()


# --- Sky light (Phase 10f) ---

# Sky light at p, 0..15 (for later: monsters spawn in the dark). Unknown columns count as lit.
func light_at(p: Vector3i) -> int:
	var c := Vector2i(p.x >> 4, p.z >> 4)
	if not heights.has(c):
		return 15
	if p.y > heights[c][(p.x & 15) + CHUNK * (p.z & 15)]:
		return 15
	if not sky.has(c):
		_compute_sky(c)
	return sky[c].get(p, 0)




# For the mesh: darkness of the cell a face looks into (UV2.x = 1 - light / 15).
func _dark(front: Vector3i) -> Vector2:
	return Vector2(1.0 - light_at(front) / 15.0, 0)


# Keeps a spot's highest opaque block right after p changed.
func _update_height(p: Vector3i) -> void:
	var c := Vector2i(p.x >> 4, p.z >> 4)
	if not heights.has(c):
		return
	var k := (p.x & 15) + CHUNK * (p.z & 15)
	if _opaque(get_block(p)):
		heights[c][k] = maxi(heights[c][k], p.y)
	elif p.y == heights[c][k]:
		var y := p.y - 1
		while y >= 0 and not _opaque(get_block(Vector3i(p.x, y, p.z))):
			y -= 1
		heights[c][k] = y


# Sky light under the tops of column c: the light of every column within reach (3x3 around, each
# flood done once: _sky_from) merged, brightest wins.
func _compute_sky(c: Vector2i) -> void:
	var out := {}
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var n := c + Vector2i(dx, dz)
			if not heights.has(n):
				continue  # not generated yet (the light never makes columns generate)
			if not _sky_src.has(n):
				_sky_src[n] = _sky_from(n)
			for p: Vector3i in _sky_src[n]:
				if p.x >> 4 == c.x and p.z >> 4 == c.y and out.get(p, 0) < _sky_src[n][p]:
					out[p] = _sky_src[n][p]
	sky[c] = out


# One step toward column c's sky light: one neighbor's openings, or the merge once all are done.
func _sky_step(c: Vector2i) -> void:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var n := c + Vector2i(dx, dz)
			if heights.has(n) and not _sky_src.has(n):
				_sky_src[n] = _sky_from(n)
				return
	_compute_sky(c)


# The light coming in through column n's openings: from each open-sky cell of n that touches a
# non-opaque cell under a neighbor's top (cave mouth, overhang, shaft side), losing 1 per block.
# Returns every lit cell under the tops (any column) -> light.
func _sky_from(n: Vector2i) -> Dictionary:
	var lit := {}
	var queue: Array[Vector3i] = []
	for x in range(n.x * CHUNK, n.x * CHUNK + CHUNK):
		for z in range(n.y * CHUNK, n.y * CHUNK + CHUNK):
			var top := _top_at(x, z)
			for d in H_DIRS:
				var nc := Vector2i((x + d.x) >> 4, (z + d.z) >> 4)
				if not heights.has(nc):
					continue  # not generated: light from there comes in when it is (ponytail)
				var nk := ((x + d.x) & 15) + CHUNK * ((z + d.z) & 15)
				var nt: int = heights[nc][nk]
				for y in range(top + 1, nt + 1):  # open sky here, under the neighbor's top there
					var q := Vector3i(x + d.x, y, z + d.z)
					if lit.get(q, 0) < 14 and not _opaque(get_block(q)):
						lit[q] = 14
						queue.append(q)
	while not queue.is_empty():
		var p: Vector3i = queue.pop_back()
		var l: int = lit[p]
		if l <= 1:
			continue
		for d in VoxelMesh.DIRS:
			var q := p + d
			var known := heights.has(Vector2i(q.x >> 4, q.z >> 4))
			if q.y < 0 or q.y >= SY or lit.get(q, 0) >= l - 1 or not known or q.y > _top_at(q.x, q.z) or _opaque(get_block(q)):
				continue
			lit[q] = l - 1
			queue.append(q)
	return lit


func _top_at(x: int, z: int) -> int:
	var c := Vector2i(x >> 4, z >> 4)
	if not heights.has(c):
		_data(c)
	return heights[c][(x & 15) + CHUNK * (z & 15)]


# --- Seeing inside (layer cut, x-ray) ---

# Hide every layer from y up (SY = show all). Caps on the cut plane stream in nearest first.
func set_cut(y: int) -> void:
	cut_y = clampi(y, 1, SY)
	for m: ShaderMaterial in [material, water_material, sway]:
		m.set_shader_parameter("cut_y", float(cut_y))
	_set_min_light()
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


# Caves are dark, but not while the player is looking inside them (cut / x-ray): see min_light.
func _set_min_light() -> void:
	var v := INSIDE_LIGHT if cut_y < SY or xray_cursor else 0.0
	for m: ShaderMaterial in [material, water_material]:
		m.set_shader_parameter("min_light", v)


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
				VoxelMesh.add_face(st, Vector3(c.x * CHUNK + lx, y, c.y * CHUNK + lz), Vector3.UP, [col, col, col, col], 1.0,
					Vector2(0 if t == AIR else t, 1), Vector2(1, 0))  # under the cut: dark (min_light shows it)
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


# What _terrain reads to mesh section s of c. copy = for a worker thread: the main thread keeps
# writing into the live arrays (dictionaries of light are only ever replaced, never edited).
func _snapshot(c: Vector2i, s: int, copy: bool) -> Dictionary:
	var cols := []  # 3x3 columns around c, index (dx + 1) + 3 * (dz + 1)
	var tops := []
	var skies := []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := c + Vector2i(dx, dz)
			var d := _data(n)
			cols.append(d.duplicate() if copy else d)
			tops.append(heights[n].duplicate() if copy else heights[n])
			if dx == 0 or dz == 0:  # light is read through faces: c and its 4 sides
				if not sky.has(n):
					_compute_sky(n)
				skies.append(sky[n])
			else:
				skies.append({})
	var solid := {}  # solid pieces next to the section shade its corners too
	var y0 := s * SECTION - 1
	for q: Vector3i in props:
		if absi((q.x >> 4) - c.x) <= 1 and absi((q.z >> 4) - c.y) <= 1 and q.y >= y0 and q.y <= y0 + P 				and prop_shape(q).solid:
			solid[q] = true
	return {c = c, s = s, cols = cols, tops = tops, skies = skies, props = solid}


# The terrain faces of a section, from a _snapshot only (runs on worker threads): {buf: MeshBuf,
# faces, grass: spots for tall grass}, faces with Minecraft-style per-corner AO in vertex alpha
# and the sky light's darkness in UV2.
static func _terrain(snap: Dictionary) -> Dictionary:
	var c: Vector2i = snap.c
	var s: int = snap.s
	var cols: Array = snap.cols
	var props: Dictionary = snap.props
	# The padded blocks, row by row (x fastest): air outside the world.
	var pad := PackedByteArray()
	var air_row := PackedByteArray()
	air_row.resize(P)
	for py in P:
		var y := s * SECTION + py - 1
		for pz in P:
			if y < 0 or y >= SY:
				pad.append_array(air_row)
				continue
			var dz := -1 if pz == 0 else (1 if pz == P - 1 else 0)
			var row := CHUNK * (((pz - 1) & 15) + CHUNK * y)
			var w: PackedByteArray = cols[3 * (dz + 1)]
			var m: PackedByteArray = cols[1 + 3 * (dz + 1)]
			var e: PackedByteArray = cols[2 + 3 * (dz + 1)]
			pad.append(w[row + 15])
			pad.append_array(m.slice(row, row + CHUNK))
			pad.append(e[row])
	var buf := MeshBuf.new()
	var faces := 0
	var grass: Array[Vector3i] = []
	var origin := Vector3i(c.x * CHUNK - 1, s * SECTION - 1, c.y * CHUNK - 1)  # world cell of pad[0]
	var cols_col: Array[Color] = []
	cols_col.resize(4)
	for py in range(1, P - 1):
		for pz in range(1, P - 1):
			for px in range(1, P - 1):
				var i := px + P * (pz + P * py)
				var t := pad[i]
				if t == AIR or t == WATER or (t >= FLOW_1 and t <= FALLING):  # is_water inlined: hot loop
					continue  # water: _water_mesh
				var p := origin + Vector3i(px, py, pz)
				for k in 6:
					var nb := pad[i + P_OFF[k]]
					if nb != AIR and nb != WATER and (nb < FLOW_1 or nb > FALLING):
						continue
					var o: PackedInt32Array = AO_OFF[k]
					for j in 4:
						var ia := i + o[j * 3]
						var ib := i + o[j * 3 + 1]
						var id := i + o[j * 3 + 2]
						var a := pad[ia]
						var b := pad[ib]
						var d := pad[id]
						# Solid = not air and not water (is_water inlined: 12 lookups per face).
						var s1 := a != AIR and a != WATER and (a < FLOW_1 or a > FALLING)
						var s2 := b != AIR and b != WATER and (b < FLOW_1 or b > FALLING)
						var s3 := d != AIR and d != WATER and (d < FLOW_1 or d > FALLING)
						if not props.is_empty():
							s1 = s1 or props.has(origin + Vector3i(ia % P, ia / (P * P), (ia / P) % P))
							s2 = s2 or props.has(origin + Vector3i(ib % P, ib / (P * P), (ib / P) % P))
							s3 = s3 or props.has(origin + Vector3i(id % P, id / (P * P), (id / P) % P))
						var open := 0 if s1 and s2 else 3 - int(s1) - int(s2) - int(s3)
						cols_col[j] = Color(COLORS[t], AO_LIGHT[open])
					# Sky light in front of the face (from the column it's in: c or a side neighbor).
					var f := p + VoxelMesh.DIRS[k]
					var fl := f - origin - Vector3i.ONE  # 0..15 inside c
					var n := (1 + (-1 if fl.x < 0 else (1 if fl.x > 15 else 0))) 							+ 3 * (1 + (-1 if fl.z < 0 else (1 if fl.z > 15 else 0)))
					var top: int = snap.tops[n][(f.x & 15) + CHUNK * (f.z & 15)]
					var dark: float = 0.0 if f.y > top else 1.0 - snap.skies[n].get(f, 0) / 15.0
					buf.quad(p, k, cols_col, Vector2(t, 0), Vector2(dark, 0))
					faces += 1
				if t == GRASS and pad[i + P * P] == AIR and p.y < SY - 1:
					grass.append(p + Vector3i.UP)
	return {buf = buf, faces = faces, grass = grass}


# Hands waiting sections to worker threads (at most MAX_JOBS at once) and places the finished ones.
func _run_jobs(start: int, budget_ms: float) -> void:
	for key: Vector3i in _jobs.keys():
		if (Time.get_ticks_usec() - start) > budget_ms * 1000.0:
			return
		var job: Dictionary = _jobs[key]
		if not WorkerThreadPool.is_task_completed(job.id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.id)
		_jobs.erase(key)
		var c := Vector2i(key.x, key.z)
		if meshed.has(c) and _sec_ver.get(key, 0) == job.ver:  # else unloaded or edited meanwhile
			_place_section(c, key.y, job.snap.out)


# Starts section s of c on a worker; false = no free slot (try again next frame).
func _start_job(c: Vector2i, s: int) -> bool:
	var key := Vector3i(c.x, s, c.y)
	if _jobs.has(key):
		_unpend(c, s)
		return true
	if _skip_section(c, s):  # nothing to draw: no job needed
		_rebuild_section(c, s)
		return true
	if _jobs.size() >= MAX_JOBS:
		return false
	_unpend(c, s)
	var snap := _snapshot(c, s, true)
	var id := WorkerThreadPool.add_task(func() -> void: snap.out = _terrain(snap))
	_jobs[key] = {id = id, ver = _sec_ver.get(key, 0), snap = snap}
	return true


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
	st.set_uv2(_dark(p))
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


# Nav of column c. now = all of it at once; else it's marked built and its sections queue up for
# stream() (_nav_pending), one per step within the frame budget. Block changes meanwhile still
# patch the nav (_update_nav), and sections built later read the blocks as they are then.
func _build_nav(c: Vector2i, now := true) -> void:
	_data(c)
	nav_built[c] = true
	var with_props := {}
	for p: Vector3i in props:
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			with_props[p.y / SECTION] = true
	var todo := []
	for s in SECTIONS:
		# Sky sections (no ground in them or just below, no built pieces) have nothing to stand on;
		# solid ones have no room.
		var sky_only: bool = opaque[c][s] == 0 and (s == 0 or opaque[c][s - 1] == 0) and not with_props.has(s)
		if not sky_only and opaque[c][s] != SECTION_VOL:
			todo.append(s)
	if now:
		for s: int in todo:
			_nav_layers(c, s * SECTION, (s + 1) * SECTION)
	elif not todo.is_empty():
		var slabs := []  # first y of NAV_SLAB layers each: a whole cave section took up to ~18 ms
		for s: int in todo:
			for y in range(s * SECTION, (s + 1) * SECTION, NAV_SLAB):
				slabs.append(y)
		_nav_pending[c] = slabs


# Nav points of column c's layers y0..y1-1, linked to the points around them.
func _nav_layers(c: Vector2i, y0: int, y1: int) -> void:
	var data: PackedByteArray = columns[c]
	var cells: Array[Vector3i] = []
	for y in range(maxi(1, y0), mini(SY - 1, y1)):
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
	for p in cells:
		_link(p, H_DIRS)  # neighbors not in the nav yet get linked when theirs are built


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


# Terrain mesh data, built straight into packed arrays with an index buffer: 4 vertices per face
# instead of 6, and ~3x faster than SurfaceTool (measured: 3000 faces 11 ms -> ~4 ms).
class MeshBuf:
	# Corner offsets of the face in each VoxelMesh.DIRS direction, in VoxelMesh.CORNERS order.
	static var CORNER_OFF: Array[PackedVector3Array] = []
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func _init() -> void:
		if CORNER_OFF.is_empty():
			for d in VoxelMesh.DIRS:
				var ax := VoxelMesh.axes(Vector3(d))
				var c := Vector3.ONE * 0.5 + Vector3(d) * 0.5
				var o := PackedVector3Array()
				for k in VoxelMesh.CORNERS:
					o.append(c + (ax[0] * k.x + ax[1] * k.y) * 0.5)
				CORNER_OFF.append(o)

	# Face k (VoxelMesh.DIRS index) of the block at p; cols per corner (VoxelMesh.CORNERS order).
	func quad(p: Vector3i, k: int, cols: Array[Color], tex: Vector2, dark: Vector2) -> void:
		var base := v.size()
		var o: PackedVector3Array = CORNER_OFF[k]
		var nn := Vector3(VoxelMesh.DIRS[k])
		var pp := Vector3(p)
		for j in 4:
			v.append(pp + o[j])
			n.append(nn)
			col.append(cols[j])
			uv.append(tex)
			uv2.append(dark)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func commit(mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m

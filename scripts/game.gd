extends Node
## Autoload "Game": global stock, standing orders (RimWorld-style designations), blueprints,
## player modes + small shared helpers.

signal changed
signal orders_changed
signal mode_changed

# Work types, in work-tab column order (= tie-break order at equal priority, like RimWorld).
# To add a job (soldier, archer, hunter...): add it here and teach Worker._find_work() to find its jobs.
const WORKS := {"build": "Construção", "dig": "Mineração", "wood": "Lenhador", "farm": "Agricultor", "gather": "Coletor",
	"hunt": "Caçador", "craft": "Artesão"}
# Area kinds the player marks; "stock" = stockpile zone (the others are standing orders).
const ORDER_NAMES := {"wood": "Cortar árvores", "gather": "Colher frutas", "hunt": "Caçar", "dig": "Escavar",
	"stock": "Estoque", "farm": "Plantação"}
const ORDER_COLORS := {"wood": Color(0.45, 0.95, 0.3), "gather": Color(1, 0.45, 0.65), "dig": Color(1, 0.45, 0.1),
	"stock": Color(0.95, 0.8, 0.3), "farm": Color(0.6, 0.9, 0.35), "hunt": Color(0.9, 0.3, 0.25)}
const PAUSED_COLOR := Color(0.6, 0.6, 0.6)
const DIG_COLOR := Color(1, 0.45, 0.1, 0.35)
# Classic blueprint blue (by material, stone a bit deeper); red for demolition marks.
const BLUEPRINT_COLORS := {"wood": Color(0.45, 0.75, 1.0), "stone": Color(0.3, 0.5, 1.0)}
const DEMOLISH_COLOR := Color(1, 0.25, 0.2)
# per_tile: how much one stockpile tile holds (one kind per tile). Balanced to what gathering
# gives: a tree yields 2/4/6 wood, a dug stone block 1 stone.
const RESOURCES := {
	"wood": {"name": "madeira", "per_tile": 10},
	"stone": {"name": "pedra", "per_tile": 16},
	"iron_ore": {"name": "minério de ferro", "per_tile": 18},
	"charcoal": {"name": "carvão", "per_tile": 18},
	"iron": {"name": "barra de ferro", "per_tile": 20},
	"berries": {"name": "frutas silvestres", "per_tile": 12, "food": 0.2},  # food: hunger filled per unit
	"wheat": {"name": "trigo", "per_tile": 15, "food": 0.1},  # raw grain: weak food (bread later)
	"carrot": {"name": "cenoura", "per_tile": 12, "food": 0.25},
	"meat": {"name": "carne crua", "per_tile": 10, "food": 0.15},  # raw: so-so food (cooking later)
}
const START_FOOD := {"berries": 20}  # in the stockpile of a new colony
const BUILT_BLOCKS := {World.WOOD: "wood", World.BRICK: "stone"}  # player blocks -> resource refunded
const ROT_DIRS: Array[Vector3i] = [Vector3i.FORWARD, Vector3i.RIGHT, Vector3i.BACK, Vector3i.LEFT]

var stock := _empty_stock()  # totals over all stockpile tiles (kept by _stock_changed)
var infinite := false  # debug map: building never runs out
var hunger := true  # villagers get hungry (the debug panel can switch it off)
var stockpile := Vector3.ZERO  # colony home: where the first stockpile and the villagers start
# Stockpile zones: {id, area: Rect2i, tiles: {feet cell: {kind, n}}}. One kind per tile.
var zones: Array[Dictionary] = []
var _zone_count := 0
# Growing zones (Farming): {id, area, crop, tiles: {feet cell: {plant, sown, claimed}}}.
var farms: Array[Dictionary] = []
var _farm_count := 0
# Workstations with bills (Crafting): base cell -> {item, bills: {recipe: {mode, target}}, claimed}.
# Added when the player first opens a station; dropped when the station is gone.
var stations := {}
var world: World
# Each order: {id, kind: "wood"/"dig", area: Rect2i (x,z cells), cells: {Vector3i: claimed} for dig,
# paused: bool, marker: MeshInstance3D or null}
var orders: Array[Dictionary] = []
# Planned pieces: base cell -> {item, dir, claimed}. Tall pieces also block the cell above.
var blueprints := {}
var planned := {}  # every cell a blueprint occupies (tall pieces: both) -> its base cell
var blueprint_view: Array[Node3D] = []
var demolish := {}  # built block cell / piece base cell -> claimed
var demolish_view: Array[Node3D] = []
var overlay_material: StandardMaterial3D
var _ghost_mats := {}
var _previews := {}
# Player modes
var pending_area := {}  # {kind, order} while marking an area; order = the one being edited, or {}
var building := false
var build_item := "wood_block"
var build_tool := "build"  # "build" or "demolish"
var build_rot := 0  # index into ROT_DIRS, R rotates (roof tool: even = ridge along X)
var roof_type := "gable"  # Roofs.TYPES key
var roof_mat := "wood"
var roof_overhang := false
var build_height := 1
var dig_depth := 3
var _order_count := 0
# Session, set by the main menu before main.tscn starts.
var world_name := "Mundo"
var start_seed := 0  # 0 = random
var pending_load := {}  # save data to restore when main.tscn starts

# --- Clock ---
const DAY_LENGTH := 600.0  # real seconds per in-game day at 1x speed
const SPEEDS := [0, 1, 2, 3]  # Space pauses, 1/2/3 pick a speed
var time_of_day := 0.3  # 0 = midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset
var day := 1
var speed := 1
var real_dt := 0.0  # unscaled frame time: the camera keeps moving while paused
var _last_speed := 1
var _last_ticks := 0


func _ready() -> void:
	ThemeDB.get_default_theme().merge_with(UiTheme.build())  # every Control, even under Node3D


func _process(delta: float) -> void:  # delta is already scaled by Engine.time_scale
	var now := Time.get_ticks_usec()
	real_dt = minf((now - _last_ticks) / 1e6, 0.1) if _last_ticks else 0.0
	_last_ticks = now
	time_of_day += delta / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1


func set_speed(s: int) -> void:
	if s > 0:
		_last_speed = s
	speed = s
	Engine.time_scale = s


func toggle_game_pause() -> void:
	set_speed(_last_speed if speed == 0 else 0)


# Days since the colony started, with the time of day as the fraction (berry regrowth, hunger).
func now() -> float:
	return day + time_of_day


func clock_text() -> String:
	var minutes := int(time_of_day * 24 * 60)
	return "Dia %d · %02d:%02d" % [day, minutes / 60, minutes % 60]


# Fresh state for a new or loaded game (this autoload outlives scene changes).
func reset() -> void:
	stock = _empty_stock()
	stations.clear()
	farms.clear()
	_farm_count = 0
	zones.clear()
	_zone_count = 0
	orders.clear()
	blueprints.clear()
	planned.clear()
	demolish.clear()
	blueprint_view.clear()  # those nodes went away with the old scene
	demolish_view.clear()
	pending_area = {}
	building = false
	_order_count = 0
	time_of_day = 0.3
	day = 1
	set_speed(1)


func _empty_stock() -> Dictionary:
	var s := {}
	for kind: String in RESOURCES:
		s[kind] = 0
	return s


# The station at base (bills all off at first), or {} if no workstation stands there anymore.
func station(base: Vector3i) -> Dictionary:
	var p: Dictionary = world.props.get(base, {})
	if p.get("base") != base or not Crafting.is_station(p.item):
		stations.erase(base)
		return {}
	if not stations.has(base) or stations[base].item != p.item:
		var bills := {}
		for id in Crafting.recipes_for(p.item):
			bills[id] = {"mode": "off", "target": Crafting.DEFAULT_TARGET}
		stations[base] = {"item": p.item, "bills": bills, "claimed": false}
	return stations[base]


func has_stock(kind: String, n := 1) -> bool:
	return infinite or stock[kind] >= n


# --- Stockpile zones ---

func zone_tile(c: Vector3i) -> Dictionary:  # the tile's {kind, n}, or {} if c isn't a stock tile
	for z in zones:
		if z.tiles.has(c):
			return z.tiles[c]
	return {}


func add_zone(area: Rect2i) -> Dictionary:
	_zone_count += 1
	var z := {"id": _zone_count, "area": area, "tiles": {}}
	zones.append(z)
	set_zone_area(z, area)
	return z


# Tiles: the ground of each column in area that's walkable and free (no tree, plan or other zone).
# Tiles that drop out of the zone move their goods to other tiles.
func set_zone_area(z: Dictionary, area: Rect2i) -> void:
	var old: Dictionary = z.tiles
	z.area = area
	z.tiles = {}
	for x in range(area.position.x, area.end.x):
		for zz in range(area.position.y, area.end.y):
			var c := Vector3i(x, world.top_at(x, zz), zz)
			if old.has(c):
				z.tiles[c] = old[c]
			elif world.walkable(c) and not world.blocked.has(c) and not planned.has(c) and zone_tile(c).is_empty():
				z.tiles[c] = {"kind": "", "n": 0}
	for c: Vector3i in old:
		if not z.tiles.has(c):
			_relocate(old[c])
	_zones_reshaped()


func remove_zone(z: Dictionary) -> void:
	zones.erase(z)
	for c: Vector3i in z.tiles:
		_relocate(z.tiles[c])
	_zones_reshaped()


func zone_used(z: Dictionary) -> int:
	return z.tiles.values().filter(func(t: Dictionary) -> bool: return t.n > 0).size()


# How much of kind fits on tile t.
func room(t: Dictionary, kind: String) -> int:
	if t.n == 0:
		return RESOURCES[kind].per_tile
	return RESOURCES[kind].per_tile - t.n if t.kind == kind else 0


func has_room(kind: String) -> bool:
	return infinite or deposit_tile(kind, Vector3.ZERO) != null


# Nearest tile that can take kind; tiles already holding it count as closer, so piles fill up
# before new ones start. null if every tile is full.
# ponytail: scans every tile per call; fine for hundreds of tiles
func deposit_tile(kind: String, from: Vector3) -> Variant:
	var best = null
	var best_d := INF
	for z in zones:
		for c: Vector3i in z.tiles:
			var t: Dictionary = z.tiles[c]
			if room(t, kind) > 0:
				var d := from.distance_squared_to(Vector3(c)) + (0.0 if t.n > 0 else 64.0)
				if d < best_d:
					best_d = d
					best = c
	if best == null and infinite and zones and zones[0].tiles:
		best = zones[0].tiles.keys()[0]  # debug map: drop it there, it's thrown away
	return best


# Nearest tile holding at least n of kind (any tile on the infinite debug map), or null.
# ponytail: a cost split over two tiles (2 + 1 for a door) isn't found; piles fill one tile first
func withdraw_tile(kind: String, n: int, from: Vector3) -> Variant:
	var best = null
	var best_d := INF
	for z in zones:
		for c: Vector3i in z.tiles:
			var t: Dictionary = z.tiles[c]
			if infinite or (t.kind == kind and t.n >= n):
				var d := from.distance_squared_to(Vector3(c))
				if d < best_d:
					best_d = d
					best = c
	return best


# Puts up to n of kind on tile c; returns what didn't fit (the debug map takes the rest away).
func deposit(c: Vector3i, kind: String, n: int) -> int:
	var t := zone_tile(c)
	var k := mini(n, room(t, kind)) if t else 0
	if k > 0:
		t.kind = kind
		t.n += k
		_stock_changed()
	return 0 if infinite else n - k


# Spreads n of kind over stockpile tiles near the colony home (old saves, tests); returns what
# didn't fit.
func store(kind: String, n: int) -> int:
	while n > 0:
		var c = deposit_tile(kind, stockpile)
		if c == null:
			break
		n = deposit(c, kind, n)
	return n


func withdraw(c: Vector3i, kind: String, n: int) -> bool:
	if infinite:
		return true
	var t := zone_tile(c)
	if t.get("kind") != kind or t.n < n:
		return false
	t.n -= n
	if t.n == 0:
		t.kind = ""
	_stock_changed()
	return true


# --- Growing zones ---

func farm_tile(c: Vector3i) -> Dictionary:  # {plant, sown, claimed}, or {} if c isn't farmed
	var f := farm_of(c)
	return f.tiles[c] if f else {}


func farm_of(c: Vector3i) -> Dictionary:
	for f in farms:
		if f.tiles.has(c):
			return f
	return {}


func add_farm(area: Rect2i) -> Dictionary:
	_farm_count += 1
	var f := {"id": _farm_count, "area": area, "crop": Farming.CROPS.keys()[0], "tiles": {}}
	farms.append(f)
	set_farm_area(f, area)
	return f


# Tiles: walkable soil (grass, dirt or farmland underneath) not used by anything else.
func set_farm_area(f: Dictionary, area: Rect2i) -> void:
	var old: Dictionary = f.tiles
	f.area = area
	f.tiles = {}
	for x in range(area.position.x, area.end.x):
		for z in range(area.position.y, area.end.y):
			var c := Vector3i(x, world.top_at(x, z), z)
			var soil := world.get_block(c + Vector3i.DOWN) in [World.GRASS, World.DIRT, World.FARMLAND]
			if old.has(c):
				f.tiles[c] = old[c]
			elif soil and world.walkable(c) and not world.blocked.has(c) and not planned.has(c) \
					and zone_tile(c).is_empty() and farm_tile(c).is_empty():
				f.tiles[c] = {"plant": "", "sown": 0.0, "claimed": false}
	_zones_reshaped()


func remove_farm(f: Dictionary) -> void:
	farms.erase(f)
	_zones_reshaped()


func cycle_crop(f: Dictionary) -> void:
	var crops: Array = Farming.CROPS.keys()
	f.crop = crops[(crops.find(f.crop) + 1) % crops.size()]
	orders_changed.emit()


# 0 = just sown .. 1 = ripe.
func growth(t: Dictionary) -> float:
	if t.plant == "":
		return 0.0
	return clampf((now() - t.sown) / Farming.CROPS[t.plant].grow_days, 0.0, 1.0)


func farm_ripe(f: Dictionary) -> int:
	return f.tiles.values().filter(func(t: Dictionary) -> bool: return t.plant != "" and growth(t) >= 1.0).size()


# Nearest stockpile tile holding any food; tiles with enough to fill `need` hunger count as closer.
func food_tile(from: Vector3, need: float) -> Variant:
	var best = null
	var best_d := INF
	for z in zones:
		for c: Vector3i in z.tiles:
			var t: Dictionary = z.tiles[c]
			if t.n == 0 or not RESOURCES[t.kind].has("food"):
				continue
			var d := from.distance_squared_to(Vector3(c)) + (0.0 if t.n * RESOURCES[t.kind].food >= need else 400.0)
			if d < best_d:
				best_d = d
				best = c
	return best


# Goods of a tile leaving its zone go to other tiles; whatever doesn't fit anywhere is lost.
func _relocate(t: Dictionary) -> void:
	while t.n > 0:
		var c = deposit_tile(t.kind, Vector3.ZERO)
		if c == null:
			return
		var dest := zone_tile(c)
		var k := mini(t.n, room(dest, t.kind))
		dest.kind = t.kind
		dest.n += k
		t.n -= k


# Zone or farm tiles changed: no tall grass growing through the piles and crops.
func _zones_reshaped() -> void:
	var cells := {}
	for z in zones:
		cells.merge(z.tiles)
	for f in farms:
		cells.merge(f.tiles)
	world.set_bare(cells)
	_stock_changed()


func _stock_changed() -> void:
	for kind in stock:
		stock[kind] = 0
	for z in zones:
		for t: Dictionary in z.tiles.values():
			if t.n > 0:
				stock[t.kind] += t.n
	changed.emit()
	orders_changed.emit()  # zone rows show how full they are


# --- Orders ---

# wood: cut trees inside area. dig: the top dig_depth blocks of each column in area.
func add_order(kind: String, area: Rect2i) -> Dictionary:
	_order_count += 1
	var o := {"id": _order_count, "kind": kind, "area": area, "cells": {}, "paused": false, "marker": null}
	orders.append(o)
	set_order_area(o, area)
	return o


# Re-marks an order's area. Workers holding a dig cell that is no longer marked drop it.
func set_order_area(o: Dictionary, area: Rect2i) -> void:
	o.area = area
	if o.kind == "dig":
		o.cells = dig_cells(area, dig_depth)
	refresh_marker(o)
	orders_changed.emit()


func remove_order(o: Dictionary) -> void:
	_free_marker(o)
	o.cells.clear()
	orders.erase(o)
	orders_changed.emit()


# What an order still has to do, for the orders panel ("18 árvores"). Same tests the villagers use.
func order_info(o: Dictionary) -> String:
	if o.kind == "dig":
		return _count(o.cells.size(), "bloco", "blocos")
	var n := 0
	if o.kind == "hunt":
		for a in get_tree().get_nodes_in_group("animals"):
			if a.state != Animal.DEAD and o.area.has_point(Vector2i(floori(a.position.x), floori(a.position.z))):
				n += 1
		return _count(n, "animal", "animais")
	var kind := "wood" if o.kind == "wood" else "berries"
	for r: ResourceNode in get_tree().get_nodes_in_group("resources"):
		if r.kind == kind and r.available() > 0 \
				and o.area.has_point(Vector2i(floori(r.position.x), floori(r.position.z))):
			n += 1
	return _count(n, "árvore", "árvores") if o.kind == "wood" else _count(n, "arbusto com frutas", "arbustos com frutas")


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func toggle_pause(o: Dictionary) -> void:
	o.paused = not o.paused
	refresh_marker(o)
	orders_changed.emit()


# Is (x,z) inside an active order of this kind?
func ordered(kind: String, cell: Vector2i) -> bool:
	for o in orders:
		if o.kind == kind and not o.paused and o.area.has_point(cell):
			return true
	return false


# Dig cell -> claimed flag.
func dig_cells(area: Rect2i, depth: int) -> Dictionary:
	var cells := {}
	for x in range(area.position.x, area.end.x):
		for z in range(area.position.y, area.end.y):
			var top := world.top_at(x, z, world.cut_y) - 1  # under the layer cut: dig inside hills
			var above := Vector3i(x, top + 1, z)
			if world.blocked.has(above) or planned.has(above) or not zone_tile(above).is_empty() \
					or not farm_tile(above).is_empty():
				continue  # tree, blueprint, stockpile or field on it: can't dig under that
			for d in depth:
				var c := Vector3i(x, top - d, z)
				if top - d >= 0 and world.is_solid(c) and world.get_block(c) != World.BEDROCK:
					cells[c] = false
	return cells


func dig_done(o: Dictionary, cell: Vector3i) -> void:
	o.cells.erase(cell)
	refresh_marker(o)
	orders_changed.emit()


# Ground tiles for tree areas, outlined blocks for dig orders. Grey while paused.
func refresh_marker(o: Dictionary) -> void:
	_free_marker(o)
	var col: Color = PAUSED_COLOR if o.paused else ORDER_COLORS[o.kind]
	var mesh: ArrayMesh = null
	if o.kind != "dig":  # tree / bush areas: ground tiles
		mesh = VoxelMesh.shell(tiles(o.area, Color(col, 0.3)), true, 0.03, 0.45)
	else:
		var cells := {}
		for c: Vector3i in o.cells:
			cells[c] = Color(col, 0.35)
		mesh = VoxelMesh.shell(cells, false, 0.03, 0.53)
	if mesh:
		o.marker = overlay(mesh)


# Top block of each column in area -> color (for tile highlights).
func tiles(area: Rect2i, col: Color) -> Dictionary:
	var cells := {}
	for x in range(area.position.x, area.end.x):
		for z in range(area.position.y, area.end.y):
			var y := world.top_at(x, z)
			if y > 0:
				cells[Vector3i(x, y - 1, z)] = col
	return cells


func _free_marker(o: Dictionary) -> void:
	if o.marker:
		o.marker.queue_free()
		o.marker = null


# --- Blueprints ---

# Plans build_item on each cell. facing: direction from the cell into the face the player clicked
# (ladders lean on it); other oriented pieces use the R rotation.
func place_blueprints(cells: Array[Vector3i], facing := Vector3i.ZERO) -> void:
	for c in cells:
		var dir := ROT_DIRS[build_rot]
		if Pieces.shape(build_item).get("climb", false):
			dir = facing if facing.y == 0 and facing != Vector3i.ZERO else _ladder_dir(c, cells)
			if dir == Vector3i.ZERO:
				continue  # nothing to lean on
		_plan_one(c, build_item, dir)
	_refresh_blueprints()


# plan: cell -> {item, dir} (e.g. from Roofs.plan). Cells already taken are skipped.
func place_plan(plan: Dictionary) -> void:
	for c: Vector3i in plan:
		_plan_one(c, plan[c].item, plan[c].dir)
	_refresh_blueprints()


func _plan_one(c: Vector3i, item: String, dir: Vector3i) -> void:
	if not world.prop_cells(c, item).all(_free):
		return
	blueprints[c] = {"item": item, "dir": dir, "claimed": false}
	for k in world.prop_cells(c, item):
		planned[k] = c
		if Pieces.shape(item).solid:
			world.set_blocked(k, true)  # workers path around planned walls; doors, stairs... stay passable


# Automatic roof over rect (wall tops at base - 1) with the current roof settings. If the wall
# tops can't be reached from the stockpile, also plans a ladder up the eave side facing it.
func plan_roof(rect: Rect2i, base: int) -> void:
	place_plan(roof_plan(rect, base))


# The roof (plus access ladder if needed) plan_roof would place; also used for the live preview.
func roof_plan(rect: Rect2i, base: int) -> Dictionary:
	var along_x := build_rot % 2 == 0
	var plan := Roofs.plan(rect, base, roof_type, roof_mat, along_x, roof_overhang)
	if not _wall_top_reachable(rect, base):
		var ladder := roof_ladder(rect, base, along_x)
		for c: Vector3i in ladder:
			plan.erase(c)  # leave a hatch in the overhang where the ladder comes up
		plan.merge(ladder)
	return plan


func _wall_top_reachable(rect: Rect2i, base: int) -> bool:
	for x in range(rect.position.x, rect.end.x):
		for z in [rect.position.y, rect.end.y - 1]:
			var top := Vector3(x + 0.5, base, z + 0.5)
			var path := world.find_path(stockpile, top)
			if not path.is_empty() and path[-1].distance_to(top) < 0.6:
				return true
	return false


# Ladder from the ground to the wall top, outside the middle of the eave side facing the
# stockpile. A flat roof needs one rung more (you step onto the roof, not the wall top).
func roof_ladder(rect: Rect2i, base: int, along_x: bool) -> Dictionary:
	var center := Vector2(rect.position) + Vector2(rect.size) / 2.0
	var to_stock := Vector2(stockpile.x, stockpile.z) - center
	var side := Vector3i.ZERO
	for s in Roofs.eave_sides(roof_type, along_x):
		if side == Vector3i.ZERO or Vector2(s.x, s.z).dot(to_stock) > Vector2(side.x, side.z).dot(to_stock):
			side = s
	var top := base if roof_type == "flat" else base - 1
	# Walk the side from its middle outward; take the first spot with solid wall all the way up
	# (not a door or window gap) and room outside.
	var along := Vector2i(absi(side.z), absi(side.x))  # direction along that wall
	var length := rect.size.x if along.x else rect.size.y
	var mid := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
	var edge := Vector2i(rect.position.x if side.x < 0 else (rect.end.x - 1 if side.x > 0 else mid.x),
		rect.position.y if side.z < 0 else (rect.end.y - 1 if side.z > 0 else mid.y))
	for i in length:
		var offset := (i + 1) / 2 * (1 if i % 2 else -1)  # 0, +1, -1, +2, -2...
		var wall := edge + along * offset
		if not rect.has_point(wall):
			continue
		var col := Vector2i(wall.x + side.x, wall.y + side.z)
		var ground := world.top_at(col.x, col.y)
		var ok := ground <= top
		for y in range(ground, top + 1):
			var c := Vector3i(col.x, y, col.y)
			ok = ok and _free(c) and (world.is_solid(Vector3i(wall.x, y, wall.y)) or y >= base)
		if ok:
			var out := {}
			for y in range(ground, top + 1):
				out[Vector3i(col.x, y, col.y)] = {"item": "ladder", "dir": -side}
			return out
	return {}  # no good spot: the player has to put a ladder up by hand


func _free(c: Vector3i) -> bool:
	return world.in_bounds(c) and not world.is_solid(c) and not world.props.has(c) \
		and not world.blocked.has(c) and not planned.has(c) and zone_tile(c).is_empty() and farm_tile(c).is_empty()


# Lean on the ladder (or ladder blueprint) below, else on a wall next to this column.
func _ladder_dir(c: Vector3i, column: Array[Vector3i]) -> Vector3i:
	var below := c + Vector3i.DOWN
	if world.is_ladder(below):
		return world.props[below].dir
	if blueprints.has(below) and blueprints[below].item == "ladder":
		return blueprints[below].dir
	for d in World.H_DIRS:
		for y in range(c.y, c.y + 4):
			if world.is_solid(Vector3i(c.x, y, c.z) + d) or column.has(Vector3i(c.x, y, c.z) + d):
				return d
	return Vector3i.ZERO


func erase_blueprints(cells: Array[Vector3i]) -> void:
	for c in cells:
		if blueprints.has(c) and not blueprints[c].claimed:
			_unblock(c)
	_refresh_blueprints()


func blueprint_done(c: Vector3i) -> void:
	_unblock(c)
	_refresh_blueprints()


func _unblock(c: Vector3i) -> void:
	for k in world.prop_cells(c, blueprints[c].item):
		planned.erase(k)
		if Pieces.shape(blueprints[c].item).solid:
			world.set_blocked(k, false)
	blueprints.erase(c)


# Castle Story rule: a block needs something to rest on (below or beside). Doors need a floor;
# a ladder needs its wall or the ladder below it.
func supported(c: Vector3i) -> bool:
	var bp: Dictionary = blueprints.get(c, {})
	var shape: String = Pieces.ITEMS[bp.item].shape if bp else "block"
	if shape == "ladder":
		return world.is_solid(c + bp.dir) or world.is_ladder(c + Vector3i.DOWN)
	if world.holds(c + Vector3i.DOWN):
		return true
	if shape == "door":
		return false
	for d in World.H_DIRS:
		if world.holds(c + d):
			return true
		# Roofs climb in rings: each piece rests on the built roof piece diagonally below it.
		if Pieces.SHAPES[shape].get("roof", false) and world.holds(c + Vector3i.DOWN + d):
			return true
	return false


func _refresh_blueprints() -> void:
	for m in blueprint_view:
		m.queue_free()
	blueprint_view = ghost_pieces(blueprints)


# Blueprint look. plan: cell -> {item, dir}. Blocks: translucent cube + outline; other pieces:
# their own model in translucent blue.
func ghost_pieces(plan: Dictionary, tint := Color.TRANSPARENT) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var cubes := {}
	for c: Vector3i in plan:
		var item: String = plan[c].item
		var col: Color = BLUEPRINT_COLORS[Pieces.ITEMS[item].mat] if tint.a == 0 else tint
		if Pieces.is_block(item):
			cubes[c] = col
		else:
			out.append(ghost_piece(item, plan[c].dir, c, col))
	out.append_array(ghost(cubes))
	return out


func ghost_piece(item: String, dir: Vector3i, cell: Vector3i, col: Color) -> Node3D:
	if not _ghost_mats.has(col):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(col, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mats[col] = mat
	var n := Pieces.instance(item, dir)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _ghost_mats[col]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for light in n.find_children("*", "OmniLight3D", true, false):
		light.queue_free()  # no light from a plan
	n.position = Pieces.origin(item, cell)
	world.add_child(n)
	return n


# Blueprint look for plain cubes: translucent fill + bright outline. cells: Vector3i -> Color.
# outside: wrap existing blocks (demolition marks) instead of sitting inside empty cells.
func ghost(cells: Dictionary, outside := false) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if cells.is_empty():
		return out
	var fill := {}
	for c: Vector3i in cells:
		fill[c] = Color(cells[c], 0.45 if outside else 0.4)
	out.append(overlay(VoxelMesh.shell(fill, false, 0.03 if outside else -0.02, 0.53 if outside else 0.48)))
	out.append(overlay(VoxelMesh.edges(cells, 0.04 if outside else -0.01)))
	return out


# --- Demolition ---

# What demolishing cell c would remove: a built block (c itself) or a piece (its base cell).
func demolish_target(c: Vector3i) -> Variant:
	if world.props.has(c):
		return world.props[c].base
	if BUILT_BLOCKS.has(world.get_block(c)):
		return c
	return null


# Resource handed back when the target goes.
func demolish_refund(c: Vector3i) -> String:
	if world.props.has(c):
		return Pieces.ITEMS[world.props[c].item].mat
	return BUILT_BLOCKS.get(world.get_block(c), "")


func mark_demolish(cells: Array[Vector3i], on: bool) -> void:
	for c in cells:
		var t = demolish_target(c)
		if t == null:
			continue
		if on and not demolish.has(t):
			demolish[t] = false
		elif not on and demolish.has(t) and not demolish[t]:
			demolish.erase(t)
	_refresh_demolish()


func demolish_done(c: Vector3i) -> void:
	demolish.erase(c)
	_refresh_demolish()


func _refresh_demolish() -> void:
	for m in demolish_view:
		m.queue_free()
	var cells := {}
	for c: Vector3i in demolish:
		var item: String = world.props[c].item if world.props.has(c) else "wood_block"
		for k in world.prop_cells(c, item):
			cells[k] = DEMOLISH_COLOR
	demolish_view = ghost(cells, true)


# --- Menu thumbnails ---

# 3D picture of a piece (build menu, resource bar).
func preview(item: String) -> Texture2D:
	var sz := Pieces.size(item)
	return render_icon(item, func() -> Node3D: return Pieces.instance(item),
		Vector3(0, sz.y * 0.5, 0), 1.3 * maxi(sz.x, sz.y) + 0.4)


# Renders make_node() once in its own little world, cached by key. size: ortho camera size.
func render_icon(key: String, make_node: Callable, center: Vector3, size: float, view := Vector3(1.4, 1.2, 2.0)) -> Texture2D:
	if _previews.has(key):
		return _previews[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(96, 96)
	vp.own_world_3d = true
	vp.transparent_bg = true
	# Draw once, and once more a moment later: the first draw came out blank for pictures made
	# right after a change_scene (villager faces when starting from the title menu).
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_tree().create_timer(0.5, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	add_child(vp)
	vp.add_child(make_node.call())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.transform = Transform3D(Basis(), center + view.normalized() * 6).looking_at(center)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	vp.add_child(env)
	_previews[key] = vp.get_texture()
	return _previews[key]


# --- Modes ---

# Mark a new order area, or re-mark `order` (edit).
func start_area(kind: String, order := {}) -> void:
	building = false
	pending_area = {"kind": kind, "order": order}
	if kind == "dig" and order:
		dig_depth = maxi(1, _depth_of(order))
	mode_changed.emit()


func finish_area(area: Rect2i) -> void:
	if pending_area.kind == "stock":
		if pending_area.order:
			set_zone_area(pending_area.order, area)
		else:
			add_zone(area)
	elif pending_area.kind == "farm":
		if pending_area.order:
			set_farm_area(pending_area.order, area)
		else:
			add_farm(area)
	elif pending_area.order:
		set_order_area(pending_area.order, area)
	else:
		add_order(pending_area.kind, area)
	cancel_area()


func cancel_area() -> void:
	pending_area = {}
	mode_changed.emit()


func set_building(on: bool) -> void:
	building = on
	pending_area = {}
	mode_changed.emit()


# Layers still marked in a dig order (to keep its depth when editing).
func _depth_of(o: Dictionary) -> int:
	var ys := {}
	for c: Vector3i in o.cells:
		ys[c.y] = true
	return ys.size()


# --- Helpers ---

# Translucent unshaded mesh added to the world (highlights, ghosts).
func overlay(mesh: ArrayMesh) -> MeshInstance3D:
	if overlay_material == null:
		overlay_material = StandardMaterial3D.new()
		overlay_material.vertex_color_use_as_albedo = true
		overlay_material.vertex_color_is_srgb = true
		overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = overlay_material
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(m)
	return m


# Colored box mesh added as child of parent.
func box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	parent.add_child(m)
	return m

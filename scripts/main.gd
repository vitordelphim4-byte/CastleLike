extends Node3D
## Level setup: stockpile and villagers at the origin of the infinite world (terrain, trees and
## water come from World/WorldGen), plus test houses on the debug map.

const WORKER_COUNT := 5
const START_LOAD_RADIUS := 3  # columns loaded before the first frame
const EXPLORE_RADIUS := 192.0  # the camera stays this close (horizontally) to some villager
const MALE_NAMES := ["João", "Kofi", "Hiro", "Tomás", "Ravi", "Duarte"]
const FEMALE_NAMES := ["Amara", "Maria", "Yuki", "Leonor", "Zara", "Inês"]
const COLORS := [Color(0.85, 0.2, 0.2), Color(0.25, 0.5, 0.95), Color(0.95, 0.75, 0.15), Color(0.6, 0.3, 0.85), Color(0.2, 0.75, 0.6)]
# Skin tones light -> dark; hair: black, dark brown, brown, blond, red.
const SKINS := [Color(0.98, 0.8, 0.66), Color(0.93, 0.72, 0.55), Color(0.8, 0.58, 0.4), Color(0.6, 0.4, 0.26), Color(0.42, 0.27, 0.17)]
const HAIRS := [Color(0.08, 0.07, 0.06), Color(0.22, 0.13, 0.07), Color(0.42, 0.26, 0.12), Color(0.85, 0.7, 0.35), Color(0.65, 0.25, 0.1)]
const SHIRTS := [Color(0.82, 0.68, 0.45), Color(0.75, 0.78, 0.82), Color(0.7, 0.8, 0.62), Color(0.9, 0.85, 0.75)]
const VESTS := [Color(0.5, 0.32, 0.17), Color(0.25, 0.4, 0.25), Color(0.5, 0.18, 0.2), Color(0.22, 0.28, 0.45)]

@export var debug_mode := false  # debug.tscn: flat world (World.flat) + infinite resources, test houses

# Debug map: roofless houses to try roofs on (footprint rect, wall block). Walls 3 high, door
# facing the stockpile.
const DEBUG_HOUSES := [
	{"offset": Vector2i(5, -9), "size": Vector2i(5, 5), "wall": "wood_block"},
	{"offset": Vector2i(-14, 5), "size": Vector2i(10, 5), "wall": "stone_block"},
]
const DEBUG_WALL_HEIGHT := 3
const STOREY := 4  # debug building: floor-to-floor height

var debug_houses: Array[Rect2i] = []
# Debug map Phase 9 hill (see _build_mine_area): rect, ground y, chamber spot, sealed cave layer.
var mine := {}
var tower := {}  # debug map 2-floor building (_build_tower): rect, ground y

@onready var world: World = $World
@onready var workers: Node3D = $Workers
var animals := Node3D.new()
var perf := Label.new()  # F3: FPS / frame time / draw calls overlay for performance testing


func _ready() -> void:
	Game.reset()
	Game.world = world
	Game.infinite = debug_mode
	var data := Game.pending_load
	Game.pending_load = {}
	if data:
		SaveGame.apply_world(world, data)
	elif Game.start_seed != 0:
		world.gen = WorldGen.new(Game.start_seed, world.flat)
	Game.changed.emit()  # HUD drew before this was set
	var cx := world.gen.spawn.x  # WorldGen picks a dry, flattened spot per seed (origin on the debug map)
	var cz := world.gen.spawn.y
	Game.stockpile = data.stockpile if data else Vector3(cx + 0.5, world.top_at(cx, cz), cz + 0.5)
	$CameraRig.position = Game.stockpile
	# Load the start area up front (a short pause); the rest streams in around the camera.
	world.load_area(Game.stockpile, START_LOAD_RADIUS)
	add_child(Stockpile.new())
	add_child(Farming.new())
	animals.name = "Animals"
	add_child(animals)
	var herds := Timer.new()  # wildlife wanders in now and then
	herds.wait_time = 8.0
	herds.autostart = true
	herds.timeout.connect(func() -> void: Animal.populate(animals, world))
	add_child(herds)

	if data:
		SaveGame.apply_game(self, data)
		for info: Dictionary in data.workers:
			var w := Worker.new()
			w.world = world
			w.worker_name = info.name
			w.color = info.color
			w.look = info.look
			w.priorities.merge(info.priorities, true)  # keeps defaults for work types added since
			w.position = info.position
			w.food = info.get("food", 1.0)
			w.returns = info.get("returns", {})
			world.load_area(info.position, 1, false)  # nav under them before they look for paths
			workers.add_child(w)
			if info.carrying:
				w._set_cargo(info.carrying, info.carry_count)  # idle with cargo: takes it to the stockpile
		for a: Array in data.get("animals", []):
			Animal.spawn(animals, world, a[0], a[1], a[2], a[3]).marked = a.size() > 4 and a[4]
		return

	Game.add_zone(Rect2i(cx - 1, cz - 1, 3, 3))  # starting stockpile
	for kind: String in Game.START_FOOD:
		Game.store(kind, Game.START_FOOD[kind])
	for i in WORKER_COUNT:
		var w := Worker.new()
		w.world = world
		_dress(w, i)
		w.color = COLORS[i % COLORS.size()]
		var x := cx + i - WORKER_COUNT / 2
		w.position = Vector3(x + 0.5, world.top_at(x, cz + 2), cz + 2.5)
		workers.add_child(w)

	for i in 40:  # a few herds around the new colony
		Animal.populate(animals, world)
	if debug_mode:  # (the flat map grows no trees near the origin, so houses are clear)
		for h in DEBUG_HOUSES:
			var rect := Rect2i(Vector2i(cx, cz) + h.offset, h.size)
			_build_house(rect, h.wall)
			debug_houses.append(rect)
		_build_test_area()
		_build_mine_area()
		_build_tower()
		add_child(preload("res://scripts/debug_panel.gd").new())


# Debug map test area, east and south of the stockpile (the tests build north and in the middle):
# workstations, iron ore and stone on the surface, bushes of every size, trees, a wheat and a
# carrot field at mixed growth stages, a stockpile holding some of every resource, one of each
# animal.
func _build_test_area() -> void:
	var y := world.top_at(0, 0)
	world.add_prop(Vector3i(12, y, 3), "kiln", Vector3i.FORWARD)
	world.add_prop(Vector3i(15, y, 3), "furnace", Vector3i.FORWARD)
	for x in range(12, 19):
		world.set_block(Vector3i(x, y - 1, 7), World.IRON_ORE)
		world.set_block(Vector3i(x, y - 1, 8), World.STONE)
	for i in 6:
		world.add_tree({"cell": Vector3i(12 + i * 2, y, 11), "kind": "bush", "size": i % 3, "variant": i})
	var trees := [["oak", 0], ["oak", 1], ["oak", 2], ["pine", 0], ["pine", 1], ["pine", 2]]
	for i in trees.size():
		world.add_tree({"cell": Vector3i(-12 + i * 3, y, 17), "kind": trees[i][0], "size": trees[i][1], "variant": i})
	var crops := ["wheat", "carrot"]
	for i in 2:
		var f := Game.add_farm(Rect2i(i * 4, 12, 3, 3))
		f.crop = crops[i]
		var k := 0
		for c: Vector3i in f.tiles:  # stages 0..3 spread over the field
			f.tiles[c].plant = f.crop
			f.tiles[c].sown = Game.now() - Farming.CROPS[f.crop].grow_days * (k % 4) / 3.0
			world.set_block(c + Vector3i.DOWN, World.FARMLAND)
			k += 1
	var z := Game.add_zone(Rect2i(-8, 11, 5, 2))
	var tiles: Array = z.tiles.keys()
	var kinds: Array = Game.RESOURCES.keys()
	for i in mini(tiles.size(), kinds.size()):
		Game.deposit(tiles[i], kinds[i], Game.RESOURCES[kinds[i]].per_tile / 2)
	for sp: String in ["rabbit", "deer", "boar"]:
		var p := Vector3(4 + ["rabbit", "deer", "boar"].find(sp) * 4 + 0.5, y, 22.5)
		Animal.spawn(animals, world, sp, p)
	Game.orders_changed.emit()


# Debug map, west of everything: a 16x16 hill (stone with iron veins, dirt and grass on top, edges
# sloping) to test the layer cut, x-ray and outlines. An open 2-high tunnel enters from the east
# into a chamber; a sealed cave with ore walls sits higher up, only visible cut or x-rayed.
func _build_mine_area() -> void:
	var y := world.top_at(0, 0)
	var r := Rect2i(-40, -2, 16, 16)
	var tunnel := Rect2i(-32, 5, 8, 2)  # from the chamber to the east face
	var chamber := Rect2i(-37, 3, 5, 6)  # 3 high
	var cave := Rect2i(-31, 9, 4, 3)  # sealed, layers y+4..y+5
	var cells := {}
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var edge := mini(mini(x - r.position.x, r.end.x - 1 - x), mini(z - r.position.y, r.end.y - 1 - z))
			var height := mini(9, 4 + edge * 2)
			for h in height:
				var t := World.STONE
				if h == height - 1:
					t = World.GRASS
				elif h >= height - 3:
					t = World.DIRT
				elif (x * 7 + z * 13 + h * 5) % 11 == 0 or (h == 2 and (x + z) % 5 == 0):
					t = World.IRON_ORE  # scattered specks + a vein along layer 2
				var p := Vector3i(x, y + h, z)
				if (tunnel.has_point(Vector2i(x, z)) and h < 2) or (chamber.has_point(Vector2i(x, z)) and h < 3):
					t = World.AIR
				elif cave.has_point(Vector2i(x, z)) and (h == 4 or h == 5):
					t = World.AIR
				elif cave.grow(1).has_point(Vector2i(x, z)) and h >= 3 and h <= 6 and t == World.STONE:
					t = World.IRON_ORE  # ore shell around the sealed cave
				cells[p] = t
	world.set_blocks(cells)
	mine = {"rect": r, "y": y, "chamber": Vector3(chamber.get_center().x + 0.5, y, chamber.get_center().y + 0.5),
		"cave_y": y + 4}


# Debug map, south-west: a 7x7 brick building with two floors (walls 3 high + slab, STOREY)
# to test the floor view. Door south, ladder against the west wall through a hole in the slab,
# a furnace downstairs and a kiln upstairs.
func _build_tower() -> void:
	var y := world.top_at(0, 0)
	var r := Rect2i(-22, 16, 7, 7)
	var door := Vector2i(r.position.x + 3, r.end.y - 1)
	var hole := Vector2i(r.position.x + 1, r.position.y + 3)
	var cells := {}
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var edge := x == r.position.x or x == r.end.x - 1 or z == r.position.y or z == r.end.y - 1
			for h in 2 * STOREY:
				var slab := h % STOREY == STOREY - 1
				if (edge and not (Vector2i(x, z) == door and h < 2)) or (slab and Vector2i(x, z) != hole):
					cells[Vector3i(x, y + h, z)] = World.BRICK
	world.set_blocks(cells)
	world.add_prop(Vector3i(door.x, y, door.y), "wood_door", Vector3i.FORWARD)
	for h in STOREY:
		world.add_ladder(Vector3i(hole.x, y + h, hole.y), Vector3i.LEFT)
	world.add_prop(Vector3i(r.position.x + 3, y, r.position.y + 1), "furnace", Vector3i.BACK)
	world.add_prop(Vector3i(r.position.x + 3, y + STOREY, r.position.y + 3), "kiln", Vector3i.BACK)
	tower = {"rect": r, "y": y}


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_F3:
		if perf.get_parent():
			perf.visible = not perf.visible
		else:  # first press: create it
			perf.position = Vector2(16, 230)
			perf.add_theme_font_size_override("font_size", 15)
			perf.add_theme_constant_override("outline_size", 5)
			perf.add_theme_color_override("font_outline_color", Color.BLACK)
			add_child(perf)


func _process(_delta: float) -> void:
	if perf.visible and perf.get_parent():
		var P := Performance
		perf.text = "FPS %d   (%.1f ms/quadro, %.1f ms física)
Draw calls %d   Triângulos %dk
VRAM %d MB   RAM %d MB   Nós %d
Colunas carregadas %d   Malhas %d   Árvores %d" % [
			P.get_monitor(P.TIME_FPS), P.get_monitor(P.TIME_PROCESS) * 1000, P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000,
			P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576, P.get_monitor(P.MEMORY_STATIC) / 1048576, P.get_monitor(P.OBJECT_NODE_COUNT),
			world.columns.size(), world.meshed.size(), world.tree_nodes.size()]
	var rig: Node3D = $CameraRig
	_keep_near_villagers(rig)
	world.focus = rig.position  # stream terrain around where the player looks
	# Glide the camera pivot over hills and valleys (the visible ones: under the layer cut).
	var ground := world.top_at(floori(rig.position.x), floori(rig.position.z), world.cut_y)
	rig.position.y = lerpf(rig.position.y, ground, minf(1.0, Game.real_dt * 4.0))


# Exploring means sending villagers: the camera can't wander farther than EXPLORE_RADIUS from
# the nearest one (and the world only generates around the camera).
func _keep_near_villagers(rig: Node3D) -> void:
	var here := Vector2(rig.position.x, rig.position.z)
	var nearest := Vector2.INF
	for w: Worker in workers.get_children():
		var p := Vector2(w.position.x, w.position.z)
		if here.distance_squared_to(p) < here.distance_squared_to(nearest):
			nearest = p
	if nearest != Vector2.INF and here.distance_to(nearest) > EXPLORE_RADIUS:
		var clamped := nearest + (here - nearest).normalized() * EXPLORE_RADIUS
		rig.position.x = clamped.x
		rig.position.z = clamped.y


# Hollow walls around rect, with a door in the middle of the side facing the stockpile.
func _build_house(rect: Rect2i, wall: String) -> void:
	var y := world.top_at(rect.position.x, rect.position.y)
	var to_stock := Vector2(Game.stockpile.x, Game.stockpile.z) - (Vector2(rect.position) + Vector2(rect.size) / 2.0)
	var door := Vector2i(rect.position.x + rect.size.x / 2, rect.end.y - 1 if to_stock.y > 0 else rect.position.y)
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var edge := x == rect.position.x or x == rect.end.x - 1 or z == rect.position.y or z == rect.end.y - 1
			for h in DEBUG_WALL_HEIGHT:
				if edge and not (Vector2i(x, z) == door and h < 2):
					world.set_block(Vector3i(x, y + h, z), Pieces.block_type(wall))
	world.add_prop(Vector3i(door.x, y, door.y), "wood_door", Vector3i.FORWARD)


# Alternating men and women; skin and hair spread so each villager is easy to tell apart.
func _dress(w: Worker, i: int) -> void:
	var female := i % 2 == 1
	var skin := (i * 2) % SKINS.size()
	var hair := (i * 3) % HAIRS.size() if skin < 3 else i % 2  # darker skin: black / dark brown hair
	var names: Array = FEMALE_NAMES if female else MALE_NAMES
	w.worker_name = names[(i / 2) % names.size()]
	w.look = {"female": female, "skin": SKINS[skin], "hair": HAIRS[hair],
		"shirt": SHIRTS[i % SHIRTS.size()], "vest": VESTS[(i + 1) % VESTS.size()]}

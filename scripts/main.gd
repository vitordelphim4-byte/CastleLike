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

var debug_houses: Array[Rect2i] = []

@onready var world: World = $World
@onready var workers: Node3D = $Workers


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
	var cx := 0  # the colony starts at the world origin (WorldGen keeps it flat and dry)
	var cz := 0
	Game.stockpile = data.stockpile if data else Vector3(cx + 0.5, world.top_at(cx, cz), cz + 0.5)
	$CameraRig.position = Game.stockpile
	# Load the start area up front (a short pause); the rest streams in around the camera.
	world.load_area(Game.stockpile, START_LOAD_RADIUS)
	add_child(Stockpile.new())

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
			world.load_area(info.position, 1, false)  # nav under them before they look for paths
			workers.add_child(w)
			if info.carrying:
				w._set_cargo(info.carrying, info.carry_count)  # idle with cargo: takes it to the stockpile
		return

	Game.add_zone(Rect2i(cx - 1, cz - 1, 3, 3))  # starting stockpile
	for i in WORKER_COUNT:
		var w := Worker.new()
		w.world = world
		_dress(w, i)
		w.color = COLORS[i % COLORS.size()]
		var x := cx + i - WORKER_COUNT / 2
		w.position = Vector3(x + 0.5, world.top_at(x, cz + 2), cz + 2.5)
		workers.add_child(w)

	if debug_mode:  # (the flat map grows no trees near the origin, so houses are clear)
		for h in DEBUG_HOUSES:
			var rect := Rect2i(Vector2i(cx, cz) + h.offset, h.size)
			_build_house(rect, h.wall)
			debug_houses.append(rect)


func _process(_delta: float) -> void:
	var rig: Node3D = $CameraRig
	_keep_near_villagers(rig)
	world.focus = rig.position  # stream terrain around where the player looks
	# Glide the camera pivot over hills and valleys.
	var ground := world.top_at(floori(rig.position.x), floori(rig.position.z))
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

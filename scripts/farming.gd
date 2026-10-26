class_name Farming
extends Node3D
## Growing zones (RimWorld-style, no seeds): the player draws a "Plantação" and picks its crop;
## farmers sow empty tiles (the ground becomes farmland) and harvest ripe ones. Crops always grow
## (no seasons yet). This node draws the plants of every farm tile, one model per (crop, stage).
## Farm data lives in Game.farms; numbers here, player docs in docs/crafting.md.

# grow_days: in-game days from sowing to ripe. yield: product units per tile harvest.
const CROPS := {
	"wheat": {"name": "Trigo", "grow_days": 1.5, "yield": 6, "product": "wheat"},
	"carrot": {"name": "Cenoura", "grow_days": 1.0, "yield": 4, "product": "carrot"},
}
const STAGES := 4  # sprout, young, grown, ripe
const VS := 1.0 / 16.0
const SPOTS := [3, 8, 13]  # plants per tile on a 3x3 grid (pixels)

static var _meshes := {}

var plants := {}  # tile -> MeshInstance3D


func _ready() -> void:
	add_to_group("cut_hide_children")  # World hides items above the layer cut
	Game.orders_changed.connect(_refresh)
	var t := Timer.new()  # growth shows over time
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_refresh)
	add_child(t)
	_refresh()


static func stage(t: Dictionary) -> int:
	return mini(int(Game.growth(t) * (STAGES - 1)), STAGES - 1) if t.plant else -1


func _refresh() -> void:
	var seen := {}
	for f in Game.farms:
		for c: Vector3i in f.tiles:
			var t: Dictionary = f.tiles[c]
			if t.plant == "":
				continue
			seen[c] = true
			if not plants.has(c):
				plants[c] = MeshInstance3D.new()
				plants[c].position = Vector3(c)
				add_child(plants[c])
			plants[c].mesh = crop_mesh(t.plant, stage(t))
	for c: Vector3i in plants.keys():
		if not seen.has(c):
			plants[c].queue_free()
			plants.erase(c)


static func crop_mesh(crop: String, st: int) -> ArrayMesh:
	var key := "%s_%d" % [crop, st]
	if not _meshes.has(key):
		var v := {}
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		for sx in SPOTS:
			for sz in SPOTS:
				var at := Vector3i(sx + rng.randi_range(-1, 1), 0, sz + rng.randi_range(-1, 1))
				if crop == "wheat":
					_wheat(v, at, st, rng)
				else:
					_carrot(v, at, st, rng)
		_meshes[key] = VoxelMesh.build(v, VS, Vector3.ZERO, 0.08)
	return _meshes[key]


# Wheat: a few stalks per spot, green and short, then tall and golden with heads.
static func _wheat(v: Dictionary, at: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var h: int = [2, 5, 8, 11][st]
	var stalk: Color = [Color(0.4, 0.7, 0.25), Color(0.45, 0.72, 0.25), Color(0.65, 0.72, 0.3), Color(0.85, 0.72, 0.3)][st]
	for off in [Vector3i(0, 0, 0), Vector3i(1, 0, 1), Vector3i(-1, 0, 0)]:
		var top := h - rng.randi_range(0, 1)
		for y in top:
			v[at + off + Vector3i(0, y, 0)] = stalk
		if st == STAGES - 1:  # grain head
			for y in range(top, top + 2):
				v[at + off + Vector3i(0, y, 0)] = Color(0.95, 0.82, 0.42)


# Carrot: a tuft of feathery leaves; ripe ones show the orange top at the ground.
static func _carrot(v: Dictionary, at: Vector3i, st: int, _rng: RandomNumberGenerator) -> void:
	var h: int = [2, 4, 6, 7][st]
	var leaf := Color(0.25, 0.6, 0.2)
	for y in h:
		v[at + Vector3i(0, y, 0)] = leaf
		if y >= h / 2:
			v[at + Vector3i(1, y, 0)] = leaf.lightened(0.15)
			v[at + Vector3i(-1, y, 0)] = leaf.lightened(0.1)
			v[at + Vector3i(0, y, 1)] = leaf
	if st == STAGES - 1:
		for off in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, -1)]:
			v[at + off] = Color(0.95, 0.5, 0.12)

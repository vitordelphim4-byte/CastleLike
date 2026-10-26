class_name Stockpile
extends Node3D
## Draws every stockpile zone: tinted ground tiles plus the goods on each tile, with one model per
## (kind, amount): wood = logs stacked in a pyramid (4-3-2-1), stone = bricks on a pallet, iron ore
## and charcoal = lumps heaped in an open crate, iron = bars stacked crosswise. Models are voxel
## meshes (1/16 block voxels) cached per (kind, amount).

const VS := 1.0 / 16.0
const LOG_LAYERS := [4, 3, 2, 1]  # logs per layer, bottom up (10 = Game.RESOURCES.wood.per_tile)

static var _meshes := {}

var ground: MeshInstance3D
var items := {}  # tile -> MeshInstance3D
var _tile_set := []  # tiles the ground mesh was built for


func _ready() -> void:
	add_to_group("cut_hide_children")  # World hides items above the layer cut
	Game.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var tiles := {}
	for z in Game.zones:
		tiles.merge(z.tiles)
	if tiles.keys() != _tile_set:
		_tile_set = tiles.keys()
		if is_instance_valid(ground):
			ground.queue_free()
		var cells := {}
		for c: Vector3i in tiles:
			cells[c + Vector3i.DOWN] = Color(Game.ORDER_COLORS.stock, 0.28)
		var mesh := VoxelMesh.shell(cells, true, 0.03, 0.45)
		ground = Game.overlay(mesh) if mesh else null
	for c: Vector3i in items.keys():
		if not tiles.has(c) or tiles[c].n == 0:
			items[c].queue_free()
			items.erase(c)
	for c: Vector3i in tiles:
		var t: Dictionary = tiles[c]
		if t.n == 0:
			continue
		if not items.has(c):
			items[c] = MeshInstance3D.new()
			items[c].position = Vector3(c)
			add_child(items[c])
		items[c].mesh = goods_mesh(t.kind, t.n)


static func goods_mesh(kind: String, n: int) -> ArrayMesh:
	var key := "%s_%d" % [kind, n]
	if not _meshes.has(key):
		var v := {}
		match kind:
			"wood": _logs(v, n)
			"stone": _bricks(v, n)
			"iron_ore": _crate(v, n, Color(0.5, 0.5, 0.52), Color(0.78, 0.45, 0.26))
			"charcoal": _crate(v, n, Color(0.13, 0.13, 0.14), Color(0.25, 0.24, 0.24))
			"iron": _bars(v, n)
			"berries": _basket(v, n)
			"carrot": _crate(v, n, Color(0.95, 0.5, 0.12), Color(0.3, 0.6, 0.2))
			"wheat": _sheaves(v, n)
			"meat": _meat(v, n)
		_meshes[key] = VoxelMesh.build(v, VS, Vector3.ZERO, 0.05)
	return _meshes[key]


# Logs along X, 14 long, 4x4 thick, each layer sitting in the grooves of the one below.
static func _logs(v: Dictionary, n: int) -> void:
	var bark := Color(0.42, 0.27, 0.13)
	var ring := Color(0.62, 0.45, 0.25)
	var core := Color(0.82, 0.67, 0.42)
	var placed := 0
	for layer in LOG_LAYERS.size():
		for i in LOG_LAYERS[layer]:
			if placed == n:
				return
			placed += 1
			var z: int = layer * 2 + i * 4
			var y: int = layer * 4
			VoxelMesh.fill(v, Vector3i(1, y, z), Vector3i(14, 4, 4), bark.darkened(0.1 * ((i + layer) % 2)))
			for x in [1, 14]:  # cut ends: light ring with a lighter core
				VoxelMesh.fill(v, Vector3i(x, y, z), Vector3i(1, 4, 4), ring)
				VoxelMesh.fill(v, Vector3i(x, y + 1, z + 1), Vector3i(1, 2, 2), core)
			for x in range(1, 15):  # round the log: drop its 4 long edges, so neighbors show a groove
				for corner in [Vector3i(x, y, z), Vector3i(x, y + 3, z), Vector3i(x, y, z + 3), Vector3i(x, y + 3, z + 3)]:
					v.erase(corner)


# Open plank crate with n lumps (4x4x4, 3x3 per layer) heaped inside; speck = second color.
static func _crate(v: Dictionary, n: int, base: Color, speck: Color) -> void:
	var plank := Color(0.58, 0.42, 0.24)
	VoxelMesh.fill(v, Vector3i(1, 0, 1), Vector3i(14, 1, 14), plank.darkened(0.15))
	for z in [1, 14]:
		VoxelMesh.fill(v, Vector3i(1, 1, z), Vector3i(14, 5, 1), plank.darkened(0.06))
	for x in [1, 14]:
		VoxelMesh.fill(v, Vector3i(x, 1, 1), Vector3i(1, 5, 14), plank)
	for i in n:
		var layer := i / 9
		var slot := i % 9
		var at := Vector3i(2 + (slot % 3) * 4, 1 + layer * 4, 2 + (slot / 3) * 4)
		for x in 4:
			for y in 4:
				for z in 4:
					if (x == 0 or x == 3) and (y == 3) and (z == 0 or z == 3):
						continue  # rounded top corners
					var c := at + Vector3i(x, y, z)
					v[c] = speck if hash(c) % 100 < 22 else base.darkened(0.06 * (hash(c) % 3))


# Wheat: sheaves lying down in a pyramid (3 then 2), stalks tied with a band, golden ears at one end.
static func _sheaves(v: Dictionary, n: int) -> void:
	var stalk := Color(0.82, 0.68, 0.32)
	var ear := Color(0.95, 0.82, 0.45)
	var layers := [[1, 6, 11], [3, 8]]  # z of each sheaf, bottom layer first
	var placed := 0
	for layer in layers.size():
		for z0: int in layers[layer]:
			if placed >= ceili(n / 3.0):
				return
			placed += 1
			var y0: int = layer * 3
			for x in range(1, 11):  # stalks, darker lines between them
				for y in 3:
					for z in 3:
						v[Vector3i(x, y0 + y, z0 + z)] = stalk.darkened(0.12 * ((y + z) % 2))
			for x in range(11, 15):  # ears: a little fatter than the stalks
				for y in range(-1 if layer > 0 else 0, 4):
					for z in range(-1, 4):
						if absi(y - 1) + absi(z - 1) <= 2 + int(x < 14):
							v[Vector3i(x, y0 + y, z0 + z)] = ear.darkened(0.08 * ((x + y + z) % 2))
			for y in 3:  # tie band
				for z in 3:
					v[Vector3i(4, y0 + y, z0 + z)] = Color(0.5, 0.33, 0.18)


# Raw meat on a cutting board: bone-in steaks and roasts with a white fat rim and marbling,
# 4 piles (2x2), stacked up as the tile fills.
static func _meat(v: Dictionary, n: int) -> void:
	VoxelMesh.fill(v, Vector3i(1, 0, 1), Vector3i(14, 1, 14), Color(0.6, 0.45, 0.27))
	var red := Color(0.74, 0.18, 0.17)
	var fat := Color(0.96, 0.88, 0.84)
	var height := [1, 1, 1, 1]  # top of each pile
	for i in n:
		var slot := i % 4
		var at := Vector3i(1 + (slot % 2) * 7, height[slot], 1 + (slot / 2) * 7)
		var roast := i % 3 == 2
		var size := Vector3i(5, 4, 5) if roast else Vector3i(6, 2, 6)
		for x in size.x:
			for y in size.y:
				for z in size.z:
					var corner := (x == 0 or x == size.x - 1) and (z == 0 or z == size.z - 1)
					if corner and (roast or y == size.y - 1):
						continue  # rounded cut
					var c := at + Vector3i(x, y, z)
					var col := red.darkened(0.08 * (hash(c) % 2))
					if roast and y % 2 == 1 and (x == 0 or z == 0 or x == size.x - 1 or z == size.z - 1):
						col = fat  # tied fat stripes round the roast
					elif not roast and (z == 0 or x == size.x - 1):
						col = fat  # fat rim on two sides of the steak
					elif hash(c) % 7 == 0:
						col = Color(0.9, 0.52, 0.5)  # marbling
					v[c] = col
		if not roast:
			VoxelMesh.fill(v, at + Vector3i(2, 0, 1), Vector3i(1, 2, 4), fat.lightened(0.05))  # T-bone
		height[slot] += size.y


# Round wicker basket filling up with red berries.
static func _basket(v: Dictionary, n: int) -> void:
	var wicker := Color(0.7, 0.53, 0.3)
	var level := 1 + int(5.0 * n / Game.RESOURCES.berries.per_tile)  # berries reach this height
	for x in range(2, 14):
		for z in range(2, 14):
			var r := Vector2(x + 0.5 - 8, z + 0.5 - 8).length()
			if r > 6.0:
				continue
			v[Vector3i(x, 0, z)] = wicker.darkened(0.15)
			if r > 4.9:  # wall, woven rows
				for y in range(1, 7):
					v[Vector3i(x, y, z)] = wicker.darkened(0.12 * ((x + z + y) % 2))
			else:
				for y in range(1, level + (1 if r < 2.5 else 0)):  # little heap in the middle
					var c := Vector3i(x, y, z)
					v[c] = Color(0.85, 0.12, 0.18) if hash(c) % 3 else Color(0.6, 0.08, 0.3)


# Iron bars (7x2x3) stacked in crossing layers of 4.
static func _bars(v: Dictionary, n: int) -> void:
	for i in n:
		var layer := i / 4
		var slot := i % 4
		var col := Color(0.6, 0.63, 0.7).lightened(0.06 * ((slot + layer) % 2))
		var y := layer * 2
		if layer % 2 == 0:
			VoxelMesh.fill(v, Vector3i(1 + (slot % 2) * 7, y, 2 + (slot / 2) * 7), Vector3i(7, 2, 3), col)
		else:
			VoxelMesh.fill(v, Vector3i(2 + (slot / 2) * 7, y, 1 + (slot % 2) * 7), Vector3i(3, 2, 7), col)


# Wooden pallet, then 6x3x6 bricks, 4 per layer, bottom up.
static func _bricks(v: Dictionary, n: int) -> void:
	var plank := Color(0.6, 0.45, 0.27)
	for z in [1, 7, 13]:
		VoxelMesh.fill(v, Vector3i(1, 0, z), Vector3i(14, 1, 2), plank.darkened(0.15))
	for x in [1, 5, 9, 13]:
		VoxelMesh.fill(v, Vector3i(x, 1, 1), Vector3i(2, 1, 14), plank)
	for i in n:
		var layer := i / 4
		var slot := i % 4
		var col := Color(0.6, 0.61, 0.64).darkened(0.08 * ((slot + layer) % 3))
		# 6x3x6 in a 7-voxel slot: the gap reads as mortar lines between bricks.
		VoxelMesh.fill(v, Vector3i(1 + (slot % 2) * 7, 2 + layer * 3, 1 + (slot / 2) * 7), Vector3i(6, 3, 6), col)

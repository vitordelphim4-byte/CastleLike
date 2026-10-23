class_name ResourceNode
extends Node3D
## A tree near the camera. Its data ({cell, kind: pine/oak, size: 0-2, variant, amount}) lives in
## World.trees so it survives this node being unloaded with its chunk. Models are shared per
## (kind, size, variant). Workers claim one unit of wood at a time; the tree falls when depleted.

const AMOUNTS := [2, 4, 6]  # wood by size: small, medium, large
const MAX_CHOPPERS := 2  # villagers working one tree at once
const VS := 0.2  # voxel size

static var _meshes := {}

var world: World
var data: Dictionary
var kind := "wood"  # what it yields (matches the "wood" order kind)
var claims := 0
var amount: int:
	get:
		return data.amount
var model := MeshInstance3D.new()


static func amount_for(size: int) -> int:
	return AMOUNTS[size]


func _ready() -> void:
	add_to_group("resources")
	var key := "%s_%d_%d" % [data.kind, data.size, data.variant]
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_meshes[key] = _tree(rng, data.kind == "pine", data.size)
	model.mesh = _meshes[key]
	model.rotation.y = hash(data.cell) % 4 * PI / 2
	add_child(model)


func available() -> int:
	return data.amount - claims


# One unit taken by a worker standing at `from`.
func take(from: Vector3) -> void:
	data.amount -= 1
	claims -= 1
	if data.amount > 0:
		var tw := create_tween()
		tw.tween_property(model, "position:x", 0.06, 0.05)
		tw.tween_property(model, "position:x", -0.04, 0.05)
		tw.tween_property(model, "position:x", 0.0, 0.05)
		return
	world.remove_tree(data.cell)
	remove_from_group("resources")
	# Topple away from the worker, then disappear.
	var away := position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	var axis := Vector3.UP.cross(away).normalized()
	var start := model.basis
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: model.basis = Basis(axis, a) * start, 0.0, PI / 2, 1.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.5)
	tw.tween_callback(queue_free)


# Pine (layered cone) or oak (trunk, branches, leaf blobs), scaled by size 0-2.
# Trunk is 2 voxels wide (3 for large trees), centered on the cell.
func _tree(rng: RandomNumberGenerator, pine: bool, size: int) -> ArrayMesh:
	var v := {}
	var bark := Color(0.42, 0.28, 0.15)
	var w := 3 if size == 2 else 2
	var c := w / 2.0  # trunk center in voxel coordinates
	if pine:
		var h: int = [rng.randi_range(10, 13), rng.randi_range(16, 20), rng.randi_range(23, 28)][size]
		var spread: float = [3.2, 5.0, 6.5][size]
		VoxelMesh.fill(v, Vector3i.ZERO, Vector3i(w, h, w), bark)
		for y in range(3 + size, h + 3):
			var t := float(y - 3 - size) / (h - 1)
			var r := (1.0 - t) * spread + 0.9 + (1.2 * (1.0 - t) if y % 3 == 0 else 0.0)  # flare every 3rd layer
			_disc(v, y, c, r, Color(0.12, 0.33, 0.18), Color(0.22, 0.48, 0.25), rng)
	else:
		var h: int = [rng.randi_range(6, 8), rng.randi_range(9, 13), rng.randi_range(14, 17)][size]
		var blob: Vector2 = [Vector2(2.5, 3.5), Vector2(3.5, 5.5), Vector2(4.5, 6.5)][size]
		var spread: float = [2.5, 4.0, 5.5][size]
		VoxelMesh.fill(v, Vector3i.ZERO, Vector3i(w, h, w), bark)
		for root in [Vector3i(-1, 0, 0), Vector3i(w, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, w)]:
			v[root] = bark.darkened(0.15)
		var blobs: Array[Vector3] = [Vector3(c, h + 1, c)]
		for i in rng.randi_range(1 + size, 2 + size * 2):
			blobs.append(Vector3(c + rng.randf_range(-spread, spread), h + rng.randf_range(-2, 3), c + rng.randf_range(-spread, spread)))
		for b in blobs:
			_line(v, Vector3(c, h - 3, c), b, bark)
		for b in blobs:
			_sphere(v, b, rng.randf_range(blob.x, blob.y), Color(0.2, 0.42, 0.15), Color(0.45, 0.7, 0.25), rng)
	return VoxelMesh.build(v, VS, Vector3(-c, 0, -c), 0.08)


# Rough leaf ball, lighter on top.
func _sphere(v: Dictionary, c: Vector3, r: float, dark: Color, light: Color, rng: RandomNumberGenerator) -> void:
	for x in range(floori(c.x - r), ceili(c.x + r) + 1):
		for y in range(floori(c.y - r), ceili(c.y + r) + 1):
			for z in range(floori(c.z - r), ceili(c.z + r) + 1):
				if Vector3(x + 0.5, y + 0.5, z + 0.5).distance_to(c) < r - rng.randf() * 0.8:
					var col := dark.lerp(light, clampf((y - c.y + r) / (2 * r), 0, 1))
					v[Vector3i(x, y, z)] = col.lightened(0.15) if rng.randf() < 0.1 else col


# One layer of pine needles: a rough disc around the trunk center, lighter at the rim.
func _disc(v: Dictionary, y: int, c: float, r: float, dark: Color, light: Color, rng: RandomNumberGenerator) -> void:
	for x in range(floori(c - r) - 1, ceili(c + r) + 1):
		for z in range(floori(c - r) - 1, ceili(c + r) + 1):
			var d := Vector2(x + 0.5 - c, z + 0.5 - c).length()
			if d < r - rng.randf() * 0.6:
				v[Vector3i(x, y, z)] = light if d > r - 1.2 else dark


func _line(v: Dictionary, a: Vector3, b: Vector3, col: Color) -> void:
	var steps := ceili(a.distance_to(b))
	for i in steps + 1:
		v[Vector3i(a.lerp(b, float(i) / maxi(steps, 1)).floor())] = col

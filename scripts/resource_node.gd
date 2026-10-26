class_name ResourceNode
extends Node3D
## A tree or berry bush near the camera. Its data ({cell, kind: pine/oak/bush, size: 0-2, variant,
## amount, regrow_at}) lives in World.trees so it survives this node being unloaded with its chunk.
## Models are shared per (kind, size, variant). Trees: workers claim one unit of wood at a time and
## the tree falls when depleted. Bushes: one villager picks all the berries; they grow back after
## REGROW_DAYS and the bush stays.

const AMOUNTS := [2, 4, 6]  # wood by size: small, medium, large
const BERRIES := [3, 5, 7]  # per bush harvest, by size: small, medium, large
const REGROW_DAYS := 1.0
const MAX_CHOPPERS := 2  # villagers working one tree at once
const VS := 0.2  # voxel size
const LOD_RANGE := 40.0  # trees farther than this from the camera use the half-resolution model
const BUSH_VS := 1.0 / 16.0  # bushes: 16 pixels per block, like a Minecraft leaf block
# Leaf cube (x/z width, height) and stem height in pixels, by size.
const BUSH_SHAPES := [Vector3i(10, 9, 0), Vector3i(13, 11, 2), Vector3i(14, 12, 4)]

static var _meshes := {}

var world: World
var data: Dictionary
var kind := "wood"  # what it yields: "wood" (trees) or "berries" (bushes)
var claims := 0
var amount: int:
	get:
		return data.amount
var model := MeshInstance3D.new()


static func amount_for(t: Dictionary) -> int:
	return BERRIES[t.size] if t.kind == "bush" else AMOUNTS[t.size]


func _ready() -> void:
	add_to_group("resources")
	if data.kind == "bush":
		kind = "berries"
		_show_bush()
		var t := Timer.new()  # berries growing back
		t.wait_time = 2.0
		t.autostart = true
		t.timeout.connect(func() -> void: if available() > 0 and model.mesh != _bush_mesh(true): _show_bush())
		add_child(t)
	else:
		var key := "%s_%d_%d" % [data.kind, data.size, data.variant]
		if not _meshes.has(key):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(key)
			_meshes[key] = _tree(rng, data.kind == "pine", data.size)
		var lods: Array = _meshes[key]
		# Full detail only up close; far away and for the sun's shadow a half-resolution copy.
		model.mesh = lods[0]
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.visibility_range_end = LOD_RANGE
		for shadow_only in [true, false]:
			var lod := MeshInstance3D.new()
			lod.mesh = lods[1]
			if shadow_only:
				lod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				lod.visibility_range_end = LOD_RANGE
			else:
				lod.visibility_range_begin = LOD_RANGE
			model.add_child(lod)
	model.rotation.y = hash(data.cell) % 4 * PI / 2
	add_child(model)


func available() -> int:
	if kind == "berries" and data.amount == 0:
		if not data.has("regrow_at"):  # loaded from a save: start growing again
			data.regrow_at = _now() + REGROW_DAYS
		if _now() >= data.regrow_at:
			data.amount = BERRIES[data.size]
	return data.amount - claims


# Game.now() looked up at run time: World uses this script, and tests compile World before autoloads.
func _now() -> float:
	return get_node("/root/Game").now()


# Bush: a villager picks every berry; they grow back later. Returns how many.
func harvest() -> int:
	var n: int = data.amount
	data.amount = 0
	data.regrow_at = _now() + REGROW_DAYS
	claims = maxi(0, claims - 1)
	_show_bush()
	return n


func _show_bush() -> void:
	model.mesh = _bush_mesh(data.amount > 0)


# Leaf-block bush: a cube of pixel leaves in mixed greens, with see-through gaps showing the dark
# inside, leaves hanging off the bottom edge, berries dotted on the outside. Large bushes sit on a
# short stem. Same shape with and without berries (only the berries are added).
func _bush_mesh(berries: bool) -> ArrayMesh:
	var key := "bush_%d_%d_%s" % [data.size, data.variant, berries]
	if not _meshes.has(key):
		var shape: Vector3i = BUSH_SHAPES[data.size]
		var w := shape.x
		var h := shape.y
		var base := shape.z  # stem height: the leaves start above it
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("bush_%d_%d" % [data.size, data.variant])
		var greens := [Color(0.2, 0.42, 0.13), Color(0.3, 0.55, 0.17), Color(0.42, 0.66, 0.2), Color(0.55, 0.74, 0.25)]
		var inner := Color(0.1, 0.22, 0.08)
		var v := {}
		if base > 0:
			VoxelMesh.fill(v, Vector3i(w / 2 - 1, 0, w / 2 - 1), Vector3i(2, base + 2, 2), Color(0.45, 0.32, 0.18))
		for x in w:
			for y in h:
				for z in w:
					var c := Vector3i(x, base + y, z)
					var edge := mini(mini(x, w - 1 - x), mini(mini(z, w - 1 - z), mini(y, h - 1 - y)))
					if edge == 0:
						if rng.randf() < 0.13:
							continue  # gap: you see the dark leaves inside
						var k := rng.randi() % greens.size()
						v[c] = greens[mini(k + (1 if y > h * 0.6 else 0), greens.size() - 1)]  # lighter on top
					elif edge == 1:
						v[c] = inner
		for x in w:  # leaves hanging off the bottom edge
			for z in w:
				if (x == 0 or z == 0 or x == w - 1 or z == w - 1) and rng.randf() < 0.3:
					for d in mini(rng.randi_range(1, 2), base):  # only bushes on a stem have room below
						v[Vector3i(x, base - 1 - d, z)] = greens[rng.randi() % 2]
		if berries:  # berries: little red / purple clusters on the outside faces
			var fruit := RandomNumberGenerator.new()
			fruit.seed = rng.seed + 1
			for c: Vector3i in v.keys():
				var outside := c.y >= base and (c.x == 0 or c.z == 0 or c.x == w - 1 or c.z == w - 1 or c.y == base + h - 1)
				if outside and v[c] != inner and fruit.randf() < 0.07:
					var col := Color(0.86, 0.1, 0.16) if fruit.randf() < 0.7 else Color(0.52, 0.1, 0.42)
					v[c] = col
					if fruit.randf() < 0.5 and v.has(c + Vector3i.DOWN):
						v[c + Vector3i.DOWN] = col.darkened(0.2)
		_meshes[key] = VoxelMesh.build(v, BUSH_VS, Vector3(-w / 2.0, 0, -w / 2.0), 0.0)
	return _meshes[key]


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
# Returns [full mesh, half-resolution mesh (2x2x2 voxels merged, ~4x fewer faces)].
# Trunk is 2 voxels wide (3 for large trees), centered on the cell.
func _tree(rng: RandomNumberGenerator, pine: bool, size: int) -> Array:
	var v := {}
	var bark := Color(0.42, 0.28, 0.15)
	# Sizes are tuned against a ~1.7-block villager: large trees tower 7-8x over them (enchanted forest).
	var w: int = [2, 3, 4][size]
	var c := w / 2.0  # trunk center in voxel coordinates
	if pine:
		var h: int = [rng.randi_range(14, 18), rng.randi_range(28, 36), rng.randi_range(52, 66)][size]
		var spread: float = [4.0, 7.0, 10.5][size]
		var bare := 3 + size * 3  # bare trunk under the lowest branches
		# Trunk stops inside the thick part of the cone: near the tip the needle layers are thinner than it.
		VoxelMesh.fill(v, Vector3i.ZERO, Vector3i(w, bare + int((h - bare) * 0.7), w), bark)
		for root in _roots(w, size):
			v[root] = bark.darkened(0.15)
		for y in range(bare, h + 3):
			var t := float(y - bare) / (h + 2 - bare)
			var r := (1.0 - t) * spread + 0.9 + (1.6 * (1.0 - t) if y % 4 == 0 else 0.0)  # flare every 4th layer
			_disc(v, y, c, r, Color(0.12, 0.33, 0.18), Color(0.22, 0.48, 0.25), rng)
	else:
		var h: int = [rng.randi_range(7, 9), rng.randi_range(13, 17), rng.randi_range(24, 30)][size]
		var blob: Vector2 = [Vector2(2.8, 3.8), Vector2(4.5, 6.5), Vector2(7.0, 9.5)][size]
		var spread: float = [3.0, 5.5, 9.0][size]
		VoxelMesh.fill(v, Vector3i.ZERO, Vector3i(w, h, w), bark)
		for root in _roots(w, size):
			v[root] = bark.darkened(0.15)
		var blobs: Array[Vector3] = [Vector3(c, h + 2, c)]
		for i in rng.randi_range(1 + size, 2 + size * 2):
			blobs.append(Vector3(c + rng.randf_range(-spread, spread), h + rng.randf_range(-2, 4) * (1 + size), c + rng.randf_range(-spread, spread)))
		for b in blobs:
			_line(v, Vector3(c, h * 0.6, c), b, bark, 1 + size / 2)
		for b in blobs:
			_sphere(v, b, rng.randf_range(blob.x, blob.y), Color(0.2, 0.42, 0.15), Color(0.45, 0.7, 0.25), rng)
	var coarse := {}
	for p: Vector3i in v:
		coarse[Vector3i(floori(p.x / 2.0), floori(p.y / 2.0), floori(p.z / 2.0))] = v[p]
	return [VoxelMesh.build(v, VS, Vector3(-c, 0, -c), 0.08), VoxelMesh.build(coarse, VS * 2, Vector3(-c, 0, -c) / 2, 0.08)]


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


# Branch from a to b, `thick` voxels square.
func _line(v: Dictionary, a: Vector3, b: Vector3, col: Color, thick := 1) -> void:
	var steps := ceili(a.distance_to(b))
	for i in steps + 1:
		VoxelMesh.fill(v, Vector3i(a.lerp(b, float(i) / maxi(steps, 1)).floor()), Vector3i.ONE * thick, col)


# Root flare around the trunk base: one voxel per side for small trees, buttresses for large ones.
func _roots(w: int, size: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var reach := 1 + size / 2  # how far the roots stick out (choppers stand in the next cell)
	for d in reach:
		var hgt := reach - d  # taller next to the trunk
		for y in hgt:
			for i in range(1, w - 1) if w > 2 else [0]:
				out.append_array([Vector3i(-1 - d, y, i), Vector3i(w + d, y, w - 1 - i), Vector3i(i, y, -1 - d), Vector3i(w - 1 - i, y, w + d)])
	return out

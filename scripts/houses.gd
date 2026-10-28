class_name Houses
## Ready-made buildings (one piece, built whole): voxel models on the Pieces grid (8 voxels per
## block). Front (door) is +Z. Not enterable: villagers go in through the door and disappear.

const PLASTER := Color(0.9, 0.88, 0.82)
const BEAM := Color(0.46, 0.28, 0.14)
const BEAM_DARK := Color(0.33, 0.2, 0.1)
const STONE := Color(0.6, 0.6, 0.58)
const TILE := Color(0.82, 0.43, 0.2)
const TILE_DARK := Color(0.68, 0.34, 0.15)
const GLOW := Color(1.0, 0.78, 0.3)
const LEAF := Color(0.38, 0.62, 0.2)
const FLOWERS := [Color(0.9, 0.2, 0.15), Color(0.95, 0.95, 0.9), Color(0.95, 0.75, 0.2)]

# Small house, 5x5 cells (40x40 voxels), 6 high. Stone plinth, timber-framed plaster walls, gable
# tile roof with the ridge along X, a dormer over the door side, stone chimney on the -X gable.
const W0 := 6  # walls: x 6..33, z 8..31
const W1 := 33
const D0 := 8
const D1 := 31
const EAVE := 20  # roof height at its edge


static func small_house(v: Dictionary) -> void:
	# Body: plinth + plaster up to just under the roof (solid: the inside is never seen).
	for x in range(W0, W1 + 1):
		for z in range(D0, D1 + 1):
			for y in _roof_y(z) - 1:
				v[Vector3i(x, y, z)] = _stone(x, y, z) if y < 4 else PLASTER
	_timber(v)
	# Door (front, middle) with an awning, steps and a lantern each side.
	_door(v, 17, 22)
	VoxelMesh.fill(v, Vector3i(16, 17, D1 + 1), Vector3i(8, 1, 3), BEAM)
	VoxelMesh.fill(v, Vector3i(16, 18, D1 + 1), Vector3i(8, 1, 2), BEAM_DARK)
	VoxelMesh.fill(v, Vector3i(16, 0, D1 + 1), Vector3i(8, 4, 2), STONE)
	VoxelMesh.fill(v, Vector3i(16, 0, D1 + 3), Vector3i(8, 2, 2), STONE.darkened(0.08))
	_lantern(v, Vector3i(15, 13, D1 + 1))
	_lantern(v, Vector3i(24, 13, D1 + 1))
	# Windows: two on the front, one on each gable, one on the back.
	_window(v, Vector3i(8, 8, D1), Vector3i.BACK)
	_window(v, Vector3i(28, 8, D1), Vector3i.BACK)
	_window(v, Vector3i(W1, 8, 18), Vector3i.RIGHT)
	_window(v, Vector3i(W1, 24, 18), Vector3i.RIGHT)
	_window(v, Vector3i(W0, 8, 22), Vector3i.LEFT)
	_window(v, Vector3i(18, 8, D0), Vector3i.FORWARD)
	_roof(v)
	_dormer(v)
	_chimney(v)
	# Yard: bushes with flowers along the plinth, a barrel and a crate by the door.
	for p in [Vector3i(7, 0, 33), Vector3i(10, 0, 34), Vector3i(29, 0, 33), Vector3i(4, 0, 30), Vector3i(35, 0, 12),
			Vector3i(35, 0, 26), Vector3i(4, 0, 9), Vector3i(20, 0, 5)]:
		_bush(v, p)
	VoxelMesh.fill(v, Vector3i(30, 0, 34), Vector3i(3, 4, 3), BEAM)
	VoxelMesh.fill(v, Vector3i(30, 1, 34), Vector3i(3, 1, 3), BEAM_DARK)
	VoxelMesh.fill(v, Vector3i(30, 3, 34), Vector3i(3, 1, 3), BEAM_DARK)
	VoxelMesh.fill(v, Vector3i(6, 0, 34), Vector3i(3, 3, 3), BEAM.lightened(0.1))
	VoxelMesh.fill(v, Vector3i(6, 1, 36), Vector3i(3, 1, 1), BEAM_DARK)


# Roof top height over row z: 1 voxel up per voxel in, from the eaves (z 4 / 35) to the ridge.
static func _roof_y(z: int) -> int:
	return EAVE + mini(z - 4, 35 - z)


static func _stone(x: int, y: int, z: int) -> Color:
	var k := hash(Vector3i(x / 3, y / 2, z / 3)) % 100 / 100.0
	return STONE.darkened(0.15 * k).lerp(LEAF, 0.4) if k > 0.93 else STONE.darkened(0.15 * k)


# Timber frame on the plaster: corner posts, sill, floor beam and top plate, studs, gable post.
static func _timber(v: Dictionary) -> void:
	var top := _roof_y(D0) - 2
	for x in range(W0, W1 + 1):
		for z in range(D0, D1 + 1):
			var edge_x := x == W0 or x == W1
			var edge_z := z == D0 or z == D1
			if not (edge_x or edge_z):
				continue
			for y in range(4, _roof_y(z) - 1):
				var c := Vector3i(x, y, z)
				var along := z if edge_x else x  # position along this wall
				var lo := W0 if edge_z else D0
				var hi := W1 if edge_z else D1
				var post := along <= lo + 1 or along >= hi - 1 or (along - lo) % 9 == 0
				var beam := y == 4 or y == 14 or y == top
				if edge_x and along == (D0 + D1) / 2 and y > top:
					post = true  # king post up the gable
				if post or beam:
					v[c] = BEAM if (along + y) % 5 else BEAM_DARK


# Door in the front wall from x0 to x1: planks, iron bands, frame.
static func _door(v: Dictionary, x0: int, x1: int) -> void:
	for x in range(x0 - 1, x1 + 2):
		for y in range(4, 18):
			var frame := x == x0 - 1 or x == x1 + 1 or y == 17
			var band := y == 7 or y == 13
			var col := BEAM_DARK if frame else (Color(0.2, 0.2, 0.22) if band else BEAM.darkened(0.12 * (x % 2)))
			v[Vector3i(x, y, D1)] = col
			if frame:
				v[Vector3i(x, y, D1 + 1)] = BEAM_DARK
	v[Vector3i((x0 + x1) / 2, 10, D1 + 1)] = Color(0.15, 0.15, 0.16)  # ring handle
	v[Vector3i((x0 + x1) / 2 + 1, 10, D1 + 1)] = Color(0.15, 0.15, 0.16)


static func _lantern(v: Dictionary, p: Vector3i) -> void:
	VoxelMesh.fill(v, p + Vector3i(0, 3, 0), Vector3i(1, 1, 2), Color(0.15, 0.15, 0.16))  # bracket
	VoxelMesh.fill(v, p + Vector3i(0, 0, 1), Vector3i(1, 3, 1), GLOW)
	v[p + Vector3i(0, 2, 2)] = Color(0.15, 0.15, 0.16)
	v[p + Vector3i(0, 0, 2)] = Color(0.15, 0.15, 0.16)


# 4x5 lit window on the wall face at p (bottom-left), facing n: cross bars, shutters, flower box.
static func _window(v: Dictionary, p: Vector3i, n: Vector3i) -> void:
	var side := Vector3i(absi(n.z), 0, absi(n.x))  # along the wall
	for i in range(-2, 6):
		for y in range(-1, 6):
			var c := p + side * i + Vector3i(0, y, 0)
			if i >= 0 and i < 4 and y >= 0 and y < 5:
				v[c] = BEAM_DARK if i == 1 or y == 2 else GLOW
			elif i < -1 or i > 4:
				if y >= 0 and y < 5:
					v[c + n] = BEAM.lightened(0.05 * (y % 2))  # open shutters
			else:
				v[c] = BEAM_DARK
	for i in range(-1, 5):  # flower box
		var c := p + side * i + Vector3i(0, -2, 0) + n
		v[c] = BEAM
		v[c + n] = BEAM_DARK
		v[c + Vector3i.UP] = LEAF if i % 2 else FLOWERS[absi(hash(c)) % FLOWERS.size()]


# Gable roof, ridge along X, overhanging the walls by 3 at the gables and 4 at the eaves.
static func _roof(v: Dictionary) -> void:
	for x in range(W0 - 3, W1 + 4):
		for z in range(4, 36):
			var top := _roof_y(z)
			var row := mini(z - 4, 35 - z)
			var edge := x == W0 - 3 or x == W1 + 3
			for y in [top - 1, top]:
				var col := TILE if (row / 2 + (x + row % 2) / 3) % 2 else TILE_DARK
				if edge:
					col = BEAM  # barge boards
				elif y == top - 1:
					col = col.darkened(0.15)
				v[Vector3i(x, y, z)] = col
			if row >= 15:
				v[Vector3i(x, top + 1, z)] = BEAM if edge else TILE_DARK.darkened(0.15)  # ridge cap


# Little gabled dormer with a window, on the front slope.
static func _dormer(v: Dictionary) -> void:
	var x0 := 23
	var x1 := 30
	var front := 27
	for x in range(x0, x1 + 1):
		for z in range(18, front + 1):
			for y in range(_roof_y(z) - 1, 32):
				v[Vector3i(x, y, z)] = BEAM if x == x0 or x == x1 or z == front and y == 31 else PLASTER
	_window(v, Vector3i(25, 27, front), Vector3i.BACK)
	for x in range(x0 - 1, x1 + 2):
		var h := 32 + mini(x - (x0 - 1), x1 + 1 - x) / 2
		for z in range(17, front + 2):
			for y in [h, h + 1]:
				if y >= _roof_y(z):
					v[Vector3i(x, y, z)] = TILE if y == h + 1 else TILE_DARK


# Square stone chimney outside the -X gable, past the ridge.
static func _chimney(v: Dictionary) -> void:
	for x in range(0, 5):
		for z in range(15, 21):
			for y in 45:
				var rim := y >= 42
				var flue := y >= 43 and x in [1, 2, 3] and z in [17, 18]
				if flue:
					if y == 43:
						v[Vector3i(x, y, z)] = Color(0.12, 0.1, 0.09)  # soot at the bottom of the hole
					continue
				v[Vector3i(x, y, z)] = STONE.lightened(0.08) if rim else _stone(x, y, z)


static func _bush(v: Dictionary, p: Vector3i) -> void:
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in 3:
				if absi(x) + absi(z) + y > 3 or not (p + Vector3i(x, y, z)).x in range(0, 40) \
						or not (p + Vector3i(x, y, z)).z in range(0, 40):
					continue
				var c := p + Vector3i(x, y, z)
				if v.has(c):
					continue
				v[c] = FLOWERS[absi(hash(c)) % 3] if hash(c) % 9 == 0 else LEAF.darkened(0.1 * (hash(c) % 3))

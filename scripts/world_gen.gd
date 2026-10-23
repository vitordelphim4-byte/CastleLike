class_name WorldGen
## Procedural terrain for the infinite world: a pure function of (seed, x, z), so any chunk can be
## generated at any time, in any order, and always comes out the same.
## Layers: rolling plains + ridged mountains (behind a mask) + rivers carved along the "zero line"
## of a noise + lakes (everything below WATER_LEVEL fills with water) + moisture (forests).
## biome() is the hook for future biomes (desert, snow fields, swamp...).

const WATER_LEVEL := 18
const START_RADIUS := 24.0  # flat, river-free land around the origin where the colony starts
const START_HEIGHT := 24.0
const START_CLEAR := 7.0  # no trees right at the stockpile
const FLAT_TOP := 10  # debug map ground height
const TREE_GRID := 4  # one tree candidate per 4x4 blocks
const ORE_DEPTH := 10  # ore veins only in the top layers of stone (below that nobody digs)
const IRON_THRESHOLD := 0.62  # higher = rarer iron veins

var flat := false
var world_seed := 0
var plains := FastNoiseLite.new()
var mountain_mask := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var rivers := FastNoiseLite.new()
var moisture := FastNoiseLite.new()
var iron := FastNoiseLite.new()


func _init(seed_value: int, is_flat := false) -> void:
	world_seed = seed_value
	flat = is_flat
	_setup(plains, 1, 0.006, 4, FastNoiseLite.FRACTAL_FBM)
	_setup(mountain_mask, 2, 0.0025, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(ridges, 3, 0.012, 4, FastNoiseLite.FRACTAL_RIDGED)
	_setup(rivers, 4, 0.0035, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(moisture, 5, 0.008, 3, FastNoiseLite.FRACTAL_FBM)
	_setup(iron, 6, 0.09, 1, FastNoiseLite.FRACTAL_NONE)


func _setup(n: FastNoiseLite, salt: int, freq: float, octaves: int, fractal: int) -> void:
	n.seed = world_seed * 31 + salt
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = fractal


# Terrain surface height at a column (top block = int(height)).
func height(x: int, z: int) -> float:
	if flat:
		return FLAT_TOP
	var h := 22.0 + plains.get_noise_2d(x, z) * 7.0
	var m := _mountains(x, z)
	h += m * (ridges.get_noise_2d(x, z) + 1.0) * 0.5 * 34.0
	var away := smoothstep(0.6, 1.0, Vector2(x, z).length() / START_RADIUS)  # 0 inside the start area
	h = lerpf(START_HEIGHT, h, away)
	# River valleys: where the river noise crosses zero, outside mountains and the start area.
	var carve := (1.0 - smoothstep(0.02, 0.07, absf(rivers.get_noise_2d(x, z)))) * (1.0 - m) * away
	return lerpf(h, WATER_LEVEL - 2.5, carve)


func _mountains(x: int, z: int) -> float:
	return smoothstep(0.1, 0.45, mountain_mask.get_noise_2d(x, z))


# Biome of a column given its surface height. Add new biomes here.
func biome(x: int, z: int, top: int) -> String:
	if flat:
		return "plains"
	if top < WATER_LEVEL:
		return "water"
	if top == WATER_LEVEL:  # one layer of sand right at the waterline
		return "beach"
	if top >= 46:
		return "snow"
	if top >= 34:
		return "mountain"
	if moisture.get_noise_2d(x, z) > 0.12:
		return "forest"
	return "plains"


# Blocks (index lx + 16 * (lz + 16 * y)) and trees for chunk (cx, cz).
func generate(cx: int, cz: int, size: int, sy: int) -> Dictionary:
	var blocks := PackedByteArray()
	blocks.resize(size * size * sy)
	# Heights with a 1-block border so steepness can be judged at the chunk edges.
	var hs := PackedFloat32Array()
	hs.resize((size + 2) * (size + 2))
	for z in size + 2:
		for x in size + 2:
			hs[x + (size + 2) * z] = height(cx * size + x - 1, cz * size + z - 1)
	var trees: Array[Dictionary] = []
	var tops := PackedInt32Array()
	tops.resize(size * size)
	for lz in size:
		for lx in size:
			var wx := cx * size + lx
			var wz := cz * size + lz
			var k := (lx + 1) + (size + 2) * (lz + 1)
			var top := clampi(int(hs[k]), 1, sy - 3)
			tops[lx + size * lz] = top
			var steep := maxf(maxf(absf(hs[k] - hs[k - 1]), absf(hs[k] - hs[k + 1])),
				maxf(absf(hs[k] - hs[k - size - 2]), absf(hs[k] - hs[k + size + 2]))) > 2.5
			var b := biome(wx, wz, top)
			var surf := World.GRASS
			var sub := World.DIRT
			match b:
				"water", "beach":
					surf = World.SAND
					sub = World.SAND
				"snow":
					surf = World.SNOW
					sub = World.STONE
				"mountain":
					surf = World.STONE
					sub = World.STONE
			if steep and surf == World.GRASS:
				surf = World.STONE
			for y in top + 1:
				blocks[lx + size * (lz + size * y)] = surf if y == top else (sub if y > top - 3 else World.STONE)
			# Iron veins in stone near the surface (they show on mountain faces and cliffs).
			for y in range(maxi(1, top - ORE_DEPTH), top + 1):
				var i := lx + size * (lz + size * y)
				if blocks[i] == World.STONE and iron.get_noise_3d(wx, y * 1.4, wz) > IRON_THRESHOLD:
					blocks[i] = World.IRON_ORE
			if not flat:  # the debug plain sits below water level and must stay dry
				for y in range(top + 1, WATER_LEVEL + 1):
					blocks[lx + size * (lz + size * y)] = World.WATER
	_plant(cx, cz, size, tops, blocks, trees)
	return {"blocks": blocks, "trees": trees}


# Forests are dense with mixed tree sizes; plains get a few scattered trees, mountains some pines.
func _plant(cx: int, cz: int, size: int, tops: PackedInt32Array, blocks: PackedByteArray, trees: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	var cells := size / TREE_GRID
	for gz in cells:
		for gx in cells:
			rng.seed = hash(Vector3i(cx * cells + gx, cz * cells + gz, world_seed))
			var lx := gx * TREE_GRID + rng.randi() % TREE_GRID
			var lz := gz * TREE_GRID + rng.randi() % TREE_GRID
			var wx := cx * size + lx
			var wz := cz * size + lz
			var top := tops[lx + size * lz]
			var surf := blocks[lx + size * (lz + size * top)]
			var b := biome(wx, wz, top)
			var density: float = {"forest": 0.85, "plains": 0.07, "mountain": 0.12}.get(b, 0.0)
			if flat:
				density = 0.05 if Vector2(wx, wz).length() > 26 else 0.0
			if Vector2(wx, wz).length() < START_CLEAR or rng.randf() >= density:
				continue
			if surf != World.GRASS and not (b == "mountain" and surf == World.STONE):
				continue
			var pine := b == "mountain" or rng.randf() < (0.6 if b == "forest" else 0.3)
			var roll := rng.randf()
			var tree_size := 2 if roll < (0.3 if b == "forest" else 0.1) else (1 if roll < 0.75 else 0)
			trees.append({"cell": Vector3i(wx, top + 1, wz), "kind": "pine" if pine else "oak",
				"size": tree_size, "variant": rng.randi() % 4})

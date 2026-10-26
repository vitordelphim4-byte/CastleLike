class_name WorldGen
## Procedural terrain for the infinite world: a pure function of (seed, x, z), so any chunk can be
## generated at any time, in any order, and always comes out the same.
## Layers: continents (lake basins / lowlands / highlands) + hills whose roughness varies + ridged
## mountains (more of them in highlands) + rivers along the "zero line" of a noise + lakes
## (everything below WATER_LEVEL fills with water). Temperature x moisture pick the biome.
## Shapes are domain-warped so coasts and ranges aren't noise-blob round.
## The spawn is searched per seed (dry, gentle land near wood), so every world starts somewhere new.

const DEPTH := 64  # Phase 10a: underground added under the old world, which sits this much higher
const WATER_LEVEL := 18 + DEPTH
const START_RADIUS := 16.0  # flattened area around the spawn (fully flat inside 65%) so the colony has room to start
const START_CLEAR := 7.0  # no trees right at the stockpile
const SPAWN_TRIES := 200  # candidate spots tried when searching the spawn
const SPAWN_RANGE := 1500.0  # how far from the origin the spawn may land
const FLAT_TOP := 10 + DEPTH  # debug map ground height
const MOUNTAIN_HEIGHT := 85.0  # tallest peak above the plains (World.SY must fit it)
const WARP := 40.0  # blocks the domain warp shifts shapes by
const TREE_GRID := 4  # one tree candidate per 4x4 blocks
const ORE_DEPTH := 10  # iron noise specks in the top layers of stone (they show on cliffs)
const IRON_THRESHOLD := 0.62  # higher = rarer iron specks
const DEEP_TOP := 32  # deepslate below about this (the boundary waves a few blocks per column)
const BEDROCK_MAX := 3  # bedrock: layer 0 everywhere, ragged up to this
# Ore veins (Minecraft style): per column, `count` random walks of `size` blocks through stone, from
# `depth` blocks under the surface down. Iron: everywhere, bigger veins in deepslate. Coal: shallow.
const VEINS := {
	World.COAL_ORE: {"count": 7, "size": [5, 12], "depth": [3, 40]},
	World.IRON_ORE: {"count": 4, "size": [3, 7], "depth": [6, 999]},
}
# Per biome: tree chance per TREE_GRID cell, share of pines, berry-bush chance where no tree grew.
const TREES := {
	"forest": [0.85, 0.45, 0.25], "taiga": [0.75, 1.0, 0.1], "plains": [0.07, 0.3, 0.08],
	"tundra": [0.05, 1.0, 0.0], "mountain": [0.12, 1.0, 0.0],
}

var flat := false
var world_seed := 0
var spawn := Vector2i.ZERO  # colony start (x, z)
var _spawn_h := 0.0
var continent := FastNoiseLite.new()
var roughness := FastNoiseLite.new()
var warp := FastNoiseLite.new()
var plains := FastNoiseLite.new()
var mountain_mask := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var rivers := FastNoiseLite.new()
var temperature := FastNoiseLite.new()
var moisture := FastNoiseLite.new()
var iron := FastNoiseLite.new()


func _init(seed_value: int, is_flat := false) -> void:
	world_seed = seed_value
	flat = is_flat
	_setup(plains, 1, 0.006, 4, FastNoiseLite.FRACTAL_FBM)
	_setup(mountain_mask, 2, 0.0025, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(ridges, 3, 0.009, 4, FastNoiseLite.FRACTAL_RIDGED)
	_setup(rivers, 4, 0.0035, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(moisture, 5, 0.005, 3, FastNoiseLite.FRACTAL_FBM)
	_setup(iron, 6, 0.09, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(continent, 7, 0.0012, 3, FastNoiseLite.FRACTAL_FBM)
	_setup(roughness, 8, 0.004, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(temperature, 9, 0.0016, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(warp, 10, 0.006, 2, FastNoiseLite.FRACTAL_FBM)
	if not flat:
		_find_spawn()


func _setup(n: FastNoiseLite, salt: int, freq: float, octaves: int, fractal: int) -> void:
	n.seed = world_seed * 31 + salt
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = fractal


# Terrain surface height at a column (top block = int(height)).
func height(x: int, z: int) -> float:
	if flat:
		return FLAT_TOP
	var away := smoothstep(START_RADIUS * 0.65, START_RADIUS, Vector2(x - spawn.x, z - spawn.y).length())
	return lerpf(_spawn_h, _raw_height(x, z), away)


# Height before the spawn area is flattened.
func _raw_height(x: int, z: int) -> float:
	var wx := x + warp.get_noise_2d(x, z) * WARP
	var wz := z + warp.get_noise_2d(z + 7919, x - 3571) * WARP
	var c := continent.get_noise_2d(wx, wz)
	var h := 21.0 + DEPTH + c * 24.0  # lake basins (under water) .. lowlands .. highlands
	var hills := lerpf(1.5, 10.0, smoothstep(-0.35, 0.45, roughness.get_noise_2d(x, z)))
	h += plains.get_noise_2d(x, z) * hills
	var m := _mountains(wx, wz, c)
	h += m * pow((ridges.get_noise_2d(x, z) + 1.0) * 0.5, 1.4) * MOUNTAIN_HEIGHT  # pow: steep peaks, gentle foothills
	# River valleys: where the river noise crosses zero, outside mountains.
	var carve := (1.0 - smoothstep(0.02, 0.07, absf(rivers.get_noise_2d(wx, wz)))) * (1.0 - m)
	return lerpf(h, WATER_LEVEL - 2.5, carve)


func _mountains(wx: float, wz: float, c: float) -> float:
	return smoothstep(0.1, 0.45, mountain_mask.get_noise_2d(wx, wz) + c * 0.35)  # highlands rise into ranges


# Biome of a column given its surface height. Add new biomes here (and in TREES / generate()).
func biome(x: int, z: int, top: int) -> String:
	if flat:
		return "plains"
	if top < WATER_LEVEL:
		return "water"
	if top == WATER_LEVEL:  # one layer of sand right at the waterline
		return "beach"
	if top >= 80 + DEPTH:
		return "snow"
	if top >= 40 + DEPTH:
		return "mountain"
	var t := temperature.get_noise_2d(x, z) - (top - WATER_LEVEL) * 0.006  # colder higher up
	var m := moisture.get_noise_2d(x, z)
	if t < -0.25:
		return "taiga" if m > -0.05 else "tundra"
	if t > 0.22 and m < -0.02:
		return "desert"
	if m > 0.08:
		return "forest"
	return "plains"


# Spawn: random spots (from the seed) until one is dry, gentle and has wood within reach.
func _find_spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for i in SPAWN_TRIES:
		var a := rng.randf() * TAU
		var p := Vector2i(Vector2(cos(a), sin(a)) * rng.randf() * SPAWN_RANGE)
		if _good_spawn(p):
			spawn = p
			_spawn_h = floorf(_raw_height(p.x, p.y)) + 0.5
			return
	spawn = Vector2i.ZERO  # ponytail: no good spot in SPAWN_TRIES (never seen): start at the origin, raised above water
	_spawn_h = maxf(floorf(_raw_height(0, 0)), WATER_LEVEL + 2) + 0.5


func _good_spawn(p: Vector2i) -> bool:
	var h := _raw_height(p.x, p.y)
	if h < WATER_LEVEL + 2 or biome(p.x, p.y, int(h)) not in ["plains", "forest", "taiga"]:
		return false
	var wood := biome(p.x, p.y, int(h)) != "plains"
	for k in 8:
		var d := Vector2(cos(k * TAU / 8), sin(k * TAU / 8))
		var q := Vector2i(Vector2(p) + d * START_RADIUS)
		if absf(_raw_height(q.x, q.y) - h) > 3.0:  # too steep to flatten without a cliff
			return false
		var r := Vector2i(Vector2(p) + d * 28.0)
		wood = wood or biome(r.x, r.y, int(_raw_height(r.x, r.y))) in ["forest", "taiga"]
	return wood


# Blocks (index lx + 16 * (lz + 16 * y)) and trees for chunk (cx, cz).
func generate(cx: int, cz: int, size: int, sy: int) -> Dictionary:
	# Heights with a 1-block border so steepness can be judged at the chunk edges.
	var hs := PackedFloat32Array()
	hs.resize((size + 2) * (size + 2))
	var low := sy
	for z in size + 2:
		for x in size + 2:
			hs[x + (size + 2) * z] = height(cx * size + x - 1, cz * size + z - 1)
			low = mini(low, int(hs[x + (size + 2) * z]))
	# Layers under every column's soil are whole layers of stone / deepslate: built a layer at a
	# time. Only bedrock, the wavy deepslate edge and what's above `lo` go block by block.
	var lo := clampi(low - 3, 0, sy)
	var layer := PackedByteArray()
	layer.resize(size * size)
	var blocks := PackedByteArray()
	for y in lo:
		layer.fill(World.DEEPSLATE if y < DEEP_TOP else World.STONE)
		blocks.append_array(layer)
	blocks.resize(size * size * sy)
	var bands := [Vector2i(0, mini(BEDROCK_MAX, lo)), Vector2i(clampi(DEEP_TOP - 3, 0, lo), clampi(DEEP_TOP + 3, 0, lo))]
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
				"water", "beach", "desert":
					surf = World.SAND
					sub = World.SAND
				"tundra":
					surf = World.SNOW
				"snow":
					surf = World.SNOW
					sub = World.STONE
				"mountain":
					surf = World.STONE
					sub = World.STONE
			if steep and surf == World.GRASS:
				surf = World.STONE
			# Underground, bottom up: bedrock, deepslate (wavy top), stone, then the biome's soil.
			var hc := hash(Vector3i(wx, wz, world_seed))
			var bedrock := hc % BEDROCK_MAX
			var deep := DEEP_TOP + (hc >> 8) % 7 - 3
			for r: Vector2i in bands + [Vector2i(lo, top + 1)]:
				for y in range(r.x, r.y):
					_fill(blocks, lx + size * (lz + size * y), y, top, surf, sub, bedrock, deep)
			# Iron veins in stone near the surface (they show on mountain faces and cliffs).
			for y in range(maxi(1, top - ORE_DEPTH), top + 1):
				var i := lx + size * (lz + size * y)
				if blocks[i] == World.STONE and iron.get_noise_3d(wx, y * 1.4, wz) > IRON_THRESHOLD:
					blocks[i] = World.IRON_ORE
			if not flat:  # the debug plain sits below water level and must stay dry
				for y in range(top + 1, WATER_LEVEL + 1):
					blocks[lx + size * (lz + size * y)] = World.WATER
	if not flat:
		_veins(cx, cz, size, tops, blocks)
	_plant(cx, cz, size, tops, blocks, trees)
	return {"blocks": blocks, "trees": trees}


# Ore veins: random walks that only turn stone / deepslate into ore. They stay inside the column
# (a vein reaching the border stops there) so generation stays per-column.
# One block of a column's underground, bottom up: bedrock, deepslate (wavy top), stone, then the
# biome's soil.
func _fill(blocks: PackedByteArray, i: int, y: int, top: int, surf: int, sub: int, bedrock: int, deep: int) -> void:
	var t := World.STONE
	if y == top:
		t = surf
	elif y > top - 3:
		t = sub
	elif y <= bedrock:
		t = World.BEDROCK
	elif y < deep:
		t = World.DEEPSLATE
	blocks[i] = t


func _veins(cx: int, cz: int, size: int, tops: PackedInt32Array, blocks: PackedByteArray) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, cz, world_seed + 77))
	for ore: int in VEINS:
		var v: Dictionary = VEINS[ore]
		for k in v.count:
			var p := Vector3i(rng.randi() % size, 0, rng.randi() % size)
			var top := tops[p.x + size * p.z]
			var lo := maxi(BEDROCK_MAX + 1, top - int(v.depth[1]))
			var hi: int = top - int(v.depth[0])
			if hi <= lo:
				continue
			p.y = rng.randi_range(lo, hi)
			var n: int = rng.randi_range(v.size[0], v.size[1]) * (2 if ore == World.IRON_ORE and p.y < DEEP_TOP else 1)
			for s in n:
				var i := p.x + size * (p.z + size * p.y)
				if blocks[i] == World.STONE or blocks[i] == World.DEEPSLATE:
					blocks[i] = ore
				p += [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD][rng.randi() % 6]
				p = p.clamp(Vector3i(0, BEDROCK_MAX + 1, 0), Vector3i(size - 1, top - 1, size - 1))


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
			var mix: Array = TREES.get(b, [0.0, 0.0, 0.0])
			var density: float = mix[0]
			if flat:
				density = 0.05 if Vector2(wx, wz).length() > 26 else 0.0
			if Vector2(wx - spawn.x, wz - spawn.y).length() < START_CLEAR:
				continue
			if rng.randf() >= density:
				# No tree here: maybe a berry bush (on grass).
				var bush_chance: float = mix[2] if not flat else 0.0
				if surf == World.GRASS and rng.randf() < bush_chance:
					var r := rng.randf()
					trees.append({"cell": Vector3i(wx, top + 1, wz), "kind": "bush", "size": 0 if r < 0.4 else (1 if r < 0.8 else 2),
						"variant": rng.randi() % 4})
				continue
			if surf != World.GRASS and not (b == "mountain" and surf == World.STONE) and not (b == "tundra" and surf == World.SNOW):
				continue
			var pine: bool = rng.randf() < mix[1]
			var roll := rng.randf()
			var tree_size := 2 if roll < (0.3 if b in ["forest", "taiga"] else 0.1) else (1 if roll < 0.75 else 0)
			trees.append({"cell": Vector3i(wx, top + 1, wz), "kind": "pine" if pine else "oak",
				"size": tree_size, "variant": rng.randi() % 4})

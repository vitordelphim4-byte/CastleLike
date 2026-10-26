class_name WorldGen
## Procedural terrain for the infinite world: a pure function of (seed, x, z), so any chunk can be
## generated at any time, in any order, and always comes out the same.
## Layers: continents (lake basins / lowlands / highlands) + hills whose roughness varies + ridged
## mountains (more of them in highlands) + rivers along the "zero line" of a noise + lakes
## (everything below WATER_LEVEL fills with water). Temperature x moisture pick the biome.
## Rivers run downhill to the sea: streams up high, wide rivers near the coast (river()).
## Shapes are domain-warped so coasts and ranges aren't noise-blob round.
## Underground (Phase 10): bedrock, deepslate, ore veins, "spaghetti" tunnels (air where two 3D
## noises are both near zero) and "cheese" halls (a low-frequency 3D noise over a limit), as in
## Minecraft 1.18+. Some tunnels open to the surface (cave mouths) and rare ravines crack it open.
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
const CAVE_FREQ := 0.022
const CAVE_WIDTH := 0.11  # each tunnel noise must be within this of zero (bigger = fatter tunnels)
const CAVE_ROOF := 4  # tunnels stay this many blocks under the surface (10d opens some)
const HALL_FREQ := 0.011
const HALL_DEEP := 0.30  # hall noise limit at the bottom (lower = more and bigger halls)...
const HALL_HIGH := 0.62  # ...rising to this at sea level: halls are a deep thing
const HALL_ROOF := 12  # halls stay this many blocks under the surface
const ENTRANCE_MASK := 0.3  # higher = fewer cave mouths
const RAVINE_MASK := 0.42  # higher = fewer ravines
const RAVINE_WIDTH := 0.022  # |line noise| under this at the top (about 4-6 blocks wide)
const RAVINE_DEPTH := 55  # deepest a ravine goes, mid-mask
const OPEN_CLEAR := START_RADIUS + 16.0  # no mouths or ravines this close to the spawn
const MOUTH_DEPTH := 24  # how deep the game shows the caves around a cave mouth
const RIVER_BAND_WIDE := 0.075  # river noise half-band near the sea (wide rivers)...
const RIVER_BAND_NARROW := 0.02  # ...and up high (streams)
const RIVER_HIGH := 12.0  # blocks over the sea where rivers are fully stream-like
const RIVER_DEPTH_SEA := 3.0  # water depth near the sea...
const RIVER_DEPTH_HIGH := 1.0  # ...and up high
const RIVER_SMOOTH := 16  # blocks the land is blurred over for the water surface
const RIVER_BELOW := 2  # water surface this far under the blurred land
const RIVER_WET := 0.35  # bed cut deep enough here to hold river water
# Ground checked around a river spot so its water stays below every bank (see _river).
const BANK_RING: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2), Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, 1), Vector2i(0, -1)]
const RIVER_TERRACE := 7.0  # river surface steps above the sea: a waterfall at each step
const AQUIFER_SIZE := Vector3i(32, 24, 32)  # underground lake regions
const AQUIFER_CHANCE := 0.35  # share of regions with a water level
const AQUIFER_ROOF := 8  # no underground lakes this close to the surface
const CAVE_FALL_CHANCE := 0.12  # per column: a spring in the roof of a tall hall
const CAVE_FALL_MIN := 6  # air under the roof for a cave waterfall
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
var _flow_cache := {}  # Vector2i -> Vector2 (river_flow)
var _aquifer_cache := {}  # Vector3i region -> water level (-1 dry)
var _river_cache := {}  # Vector2i -> Vector4 (river): asked for again and again by neighbors
var cave_a := FastNoiseLite.new()  # spaghetti tunnels: where both are near zero
var cave_b := FastNoiseLite.new()
var cave_hall := FastNoiseLite.new()  # cheese halls: where it's high
var entrance := FastNoiseLite.new()  # 2D: where it's high, tunnels may open to the surface
var ravine_line := FastNoiseLite.new()  # 2D: ravines run along its zero line...
var ravine_mask := FastNoiseLite.new()  # ...where this is high (rare)


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
	_setup(cave_a, 11, CAVE_FREQ, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(cave_b, 12, CAVE_FREQ, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(cave_hall, 13, HALL_FREQ, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(entrance, 14, 0.01, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(ravine_line, 15, 0.004, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(ravine_mask, 16, 0.003, 1, FastNoiseLite.FRACTAL_NONE)
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


# Height before the spawn area is flattened: the land, with river beds cut into it.
func _raw_height(x: int, z: int) -> float:
	var land := _land(x, z)
	var r := river(x, z, land)
	return land if r.x <= 0.0 else lerpf(land, r.y - r.z, r.x)


# Height of the land, without rivers.
func _land(x: int, z: int) -> float:
	var wx := x + warp.get_noise_2d(x, z) * WARP
	var wz := z + warp.get_noise_2d(z + 7919, x - 3571) * WARP
	var c := continent.get_noise_2d(wx, wz)
	var h := 21.0 + DEPTH + c * 24.0  # lake basins (under water) .. lowlands .. highlands
	var hills := lerpf(1.5, 10.0, smoothstep(-0.35, 0.45, roughness.get_noise_2d(x, z)))
	h += plains.get_noise_2d(x, z) * hills
	var m := _mountains(wx, wz, c)
	h += m * pow((ridges.get_noise_2d(x, z) + 1.0) * 0.5, 1.4) * MOUNTAIN_HEIGHT  # pow: steep peaks, gentle foothills
	return h


# Rivers (Phase 10e4) run along the zero line of a noise, outside mountains. Their water surface
# follows the land around them (a blurred height, a little under it, never under the sea), so they
# go downhill to the sea in 1-block steps. High up they're narrow, shallow streams; near the sea,
# wide and deep rivers. Returns (how much the bed is cut here 0..1, water surface y, depth), or
# ZERO away from rivers; w = the surface before the terrace steps. `land` = _land(x, z) when the
# caller has it.
func river(x: int, z: int, land := NAN) -> Vector4:
	var key := Vector2i(x, z)
	if _river_cache.has(key):
		return _river_cache[key]
	if _river_cache.size() > 200000:
		_river_cache.clear()
	var r := _river(x, z, land)
	_river_cache[key] = r
	return r


func _river(x: int, z: int, land: float) -> Vector4:
	var wx := x + warp.get_noise_2d(x, z) * WARP
	var wz := z + warp.get_noise_2d(z + 7919, x - 3571) * WARP
	var n := absf(rivers.get_noise_2d(wx, wz))
	if n >= RIVER_BAND_WIDE:
		return Vector4.ZERO
	var m := _mountains(wx, wz, continent.get_noise_2d(wx, wz))
	if m >= 1.0:
		return Vector4.ZERO
	if is_nan(land):
		land = _land(x, z)
	# Above the sea the surface goes in RIVER_TERRACE steps: flat stretches and waterfalls between.
	var raw := floorf(_river_level(x, z)) - RIVER_BELOW
	var level := raw
	if level > WATER_LEVEL + RIVER_TERRACE:
		level = WATER_LEVEL + floorf((level - WATER_LEVEL) / RIVER_TERRACE) * RIVER_TERRACE
	# Never above the lowest ground around (RIVER_BANK blocks): on a slope the river cuts a channel
	# into it instead of hanging off it in loose steps.
	var low := land
	for d: Vector2i in BANK_RING:
		low = minf(low, _land(x + d.x, z + d.y))
	var s := maxf(WATER_LEVEL, minf(level, floorf(low) - 1.0))
	var high := clampf((s - WATER_LEVEL) / RIVER_HIGH, 0.0, 1.0)  # 0 at sea level .. 1 up high
	var band := lerpf(RIVER_BAND_WIDE, RIVER_BAND_NARROW, high)
	var carve := (1.0 - smoothstep(band * 0.4, band, n)) * (1.0 - m)
	return Vector4(carve, s, lerpf(RIVER_DEPTH_SEA, RIVER_DEPTH_HIGH, high), raw) if carve > 0.0 else Vector4.ZERO


# The land blurred over RIVER_SMOOTH blocks: what a river's surface follows.
func _river_level(x: int, z: int) -> float:
	var d := RIVER_SMOOTH
	return (_land(x + d, z + d) + _land(x - d, z + d) + _land(x + d, z - d) + _land(x - d, z - d)) / 4.0


# Which way the river at (x, z) runs (downhill along the blurred land), ZERO if no river here.
# Cached: the water mesh asks for every river surface cell.
func river_flow(x: int, z: int) -> Vector2:
	var key := Vector2i(x, z)
	if _flow_cache.has(key):
		return _flow_cache[key]
	var f := Vector2.ZERO
	if river(x, z).x > RIVER_WET:
		var g := Vector2(_river_level(x + 4, z) - _river_level(x - 4, z), _river_level(x, z + 4) - _river_level(x, z - 4))
		if g.length() > 0.05:
			f = -g.normalized()
	if _flow_cache.size() > 100000:
		_flow_cache.clear()
	_flow_cache[key] = f
	return f


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
	var wet_top := -1  # highest river water placed (the drain pass looks up to there)
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
			# River water over this spot (its surface y), away from the start area; -1 = none.
			var r := river(wx, wz) if not flat else Vector4.ZERO
			var river_top := int(r.y) if r.x > 0.0 and top < r.y and Vector2(wx - spawn.x, wz - spawn.y).length() > START_RADIUS else -1
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
			if river_top >= 0:
				surf = World.SAND  # river bed
			# Underground, bottom up: bedrock, deepslate (wavy top), stone, then the biome's soil.
			var hc := hash(Vector3i(wx, wz, world_seed))
			var bedrock := hc % BEDROCK_MAX
			var deep := DEEP_TOP + (hc >> 8) % 7 - 3
			for span: Vector2i in bands + [Vector2i(lo, top + 1)]:
				for y in range(span.x, span.y):
					_fill(blocks, lx + size * (lz + size * y), y, top, surf, sub, bedrock, deep)
			# Iron veins in stone near the surface (they show on mountain faces and cliffs).
			for y in range(maxi(1, top - ORE_DEPTH), top + 1):
				var i := lx + size * (lz + size * y)
				if blocks[i] == World.STONE and iron.get_noise_3d(wx, y * 1.4, wz) > IRON_THRESHOLD:
					blocks[i] = World.IRON_ORE
			if not flat:  # the debug plain sits below water level and must stay dry
				for y in range(top + 1, maxi(WATER_LEVEL, river_top) + 1):
					blocks[lx + size * (lz + size * y)] = World.WATER
				if river_top >= 0:
					_river_fall(blocks, wx, wz, lx + size * lz, size * size, river_top, r.w)
					wet_top = maxi(wet_top, river_top)
	if wet_top > WATER_LEVEL:
		_drain_rivers(blocks, cx, cz, size, hs, wet_top)
	# How deep under the ground this column is open to the sky (cave mouth / ravine; 0 = closed):
	# the game shows the caves down to there.
	var open_depth := 0
	if not flat:
		_veins(cx, cz, size, tops, blocks)
		open_depth = _ravines(cx, cz, size, tops, blocks)
		if _tunnels(cx, cz, size, tops, blocks):
			open_depth = maxi(open_depth, MOUTH_DEPTH)
	var springs: Array[Vector3i] = []
	if not flat:
		_cave_fall(cx, cz, size, tops, blocks, springs)
	_plant(cx, cz, size, tops, blocks, trees)  # skips spots carved open (no soil left on top)
	return {"blocks": blocks, "trees": trees, "opened": open_depth > 0, "open_depth": open_depth, "springs": springs}


# River water must sit in its bed: river sources above the sea with air beside or under them are
# taken out, again and again until none is left (taking one out can open its neighbor). Spots in
# the next columns are judged from their height and river (hs has a 1-block border).
func _drain_rivers(blocks: PackedByteArray, cx: int, cz: int, size: int, hs: PackedFloat32Array, wet_top: int) -> void:
	var area := size * size
	var changed := true
	while changed:
		changed = false
		for y in range(wet_top, WATER_LEVEL, -1):
			for lz in size:
				for lx in size:
					var i := lx + size * lz + area * y
					var t := blocks[i]
					if t == World.FALLING:  # a waterfall needs water above it
						if not World.is_water(blocks[i + area]):
							blocks[i] = World.AIR
							changed = true
						continue
					if t != World.WATER and t != World.FLOW_7:
						continue
					# A source must be held on every side and below; a fall's top (flowing 7) must
					# have a source beside it feeding it.
					var dry := t == World.WATER and blocks[i - area] == World.AIR
					var fed := false
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if dry:
							break
						var nx := lx + d.x
						var nz := lz + d.y
						var nb := World.AIR
						if nx >= 0 and nz >= 0 and nx < size and nz < size:
							nb = blocks[nx + size * nz + area * y]
						else:  # next column: ground, river water, or air?
							var top := int(hs[(nx + 1) + (size + 2) * (nz + 1)])
							var rn := river(cx * size + nx, cz * size + nz)
							if y <= top:
								nb = World.STONE
							elif rn.x > 0.0 and top < rn.y and y <= rn.y:
								nb = World.WATER
						fed = fed or nb == World.WATER
						dry = t == World.WATER and nb == World.AIR
					if t == World.FLOW_7:
						dry = not fed
					if dry:
						blocks[i] = World.AIR
						changed = true


# River waterfall: a river spot right below a higher stretch of the same river gets the falling
# water, from its own surface up to the stretch above (flowing 7 on top, as Minecraft would leave it).
func _river_fall(blocks: PackedByteArray, wx: int, wz: int, i: int, area: int, surface: int, raw: float) -> void:
	# A neighbor can only be a terrace higher if this spot is near the top of its terrace.
	if raw <= WATER_LEVEL + RIVER_TERRACE or fposmod(raw - WATER_LEVEL, RIVER_TERRACE) < RIVER_TERRACE - 2.0:
		return
	var up := surface
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var r := river(wx + d.x, wz + d.y)
		if r.x > 0.0 and r.y > up and height(wx + d.x, wz + d.y) < r.y:  # that stretch really holds water here
			up = int(r.y)
	if up <= surface + 1:
		return
	for y in range(surface + 1, up + 1):
		if blocks[i + area * y] == World.AIR:
			blocks[i + area * y] = World.FLOW_7 if y == up else World.FALLING


# Cave waterfall: sometimes, a spring in the roof of a tall hall (CAVE_FALL_MIN+ of air under it).
# Only the source goes in; the game wakes it (`springs`) and the water falls and pools on its own.
func _cave_fall(cx: int, cz: int, size: int, tops: PackedInt32Array, blocks: PackedByteArray, springs: Array[Vector3i]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, cz, world_seed + 991))
	if rng.randf() >= CAVE_FALL_CHANCE:
		return
	var area := size * size
	for attempt in 6:
		var i := rng.randi() % area
		var air := 0
		for y in range(tops[i] - HALL_ROOF, BEDROCK_MAX, -1):
			if blocks[i + area * y] == World.AIR:
				air += 1
				continue
			if air >= CAVE_FALL_MIN and blocks[i + area * (y + air + 1)] in [World.STONE, World.DEEPSLATE]:
				var roof := y + air + 1
				blocks[i + area * roof] = World.WATER
				springs.append(Vector3i(cx * size + i % size, roof, cz * size + i / size))
				return
			air = 0


# Entrances and ravines stay off water, beaches and the colony's start area.
func _can_open(wx: int, wz: int, top: int) -> bool:
	return top > WATER_LEVEL + 1 and Vector2(wx - spawn.x, wz - spawn.y).length() > OPEN_CLEAR and river(wx, wz).x <= 0.0


# Ravines: narrow, deep cracks along the zero line of a noise (like rivers), only where a rare mask
# is high; deepest mid-mask, narrower toward the bottom. Returns the deepest cut here (0 = none).
func _ravines(cx: int, cz: int, size: int, tops: PackedInt32Array, blocks: PackedByteArray) -> int:
	var carved := 0
	var area := size * size
	for lz in size:
		for lx in size:
			var wx := cx * size + lx
			var wz := cz * size + lz
			var i := lx + size * lz
			var m := ravine_mask.get_noise_2d(wx, wz)
			if m < RAVINE_MASK or not _can_open(wx, wz, tops[i]):
				continue
			var r := absf(ravine_line.get_noise_2d(wx, wz))
			if r >= RAVINE_WIDTH:
				continue
			var depth := int(RAVINE_DEPTH * smoothstep(RAVINE_MASK, RAVINE_MASK + 0.15, m))
			var bottom := maxi(BEDROCK_MAX + 1, tops[i] - depth)
			for y in range(bottom, tops[i] + 1):
				var taper := 0.35 + 0.65 * float(y - bottom) / maxf(1.0, depth)  # wide at the top
				if r < RAVINE_WIDTH * taper and blocks[i + area * y] != World.WATER:
					blocks[i + area * y] = World.AIR
					carved = maxi(carved, tops[i] - y)
	return carved


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


# Caves: spaghetti tunnels (both tunnel noises near zero) and cheese halls (the hall noise over a
# limit that drops with depth: halls grow deeper down; what stays solid inside them are pillars).
# Where the entrance mask is high, tunnels may break the surface (cave mouths). True if they did.
# The noise comes in whole 16x16 slices per layer from get_image_3d (C++), not a call per block:
# noise (x, z, y) with the column's offset, 0..255 for -1..1. Ore walls stay (the veins went in
# first), bedrock and water are never carved.
func _tunnels(cx: int, cz: int, size: int, tops: PackedInt32Array, blocks: PackedByteArray) -> bool:
	var y0 := BEDROCK_MAX + 1
	var high := 0
	var roof := PackedInt32Array()  # highest y a tunnel may take per spot: under the roof, or the top
	roof.resize(size * size)
	for i in size * size:
		var wx := cx * size + i % size
		var wz := cz * size + i / size
		var mouth := entrance.get_noise_2d(wx, wz) > ENTRANCE_MASK and _can_open(wx, wz, tops[i])
		roof[i] = tops[i] if mouth else tops[i] - CAVE_ROOF
		high = maxi(high, roof[i])
	var h := high - y0 + 1
	if h <= 0:
		return false
	var opened := false
	var lake_low := World.SY
	var lake_high := -1
	var levels := PackedInt32Array()  # the column sits in one aquifer region per height band
	for band in World.SY / AQUIFER_SIZE.y + 1:
		levels.append(_aquifer(cx * size, band * AQUIFER_SIZE.y, cz * size))
	var a := _slices(cave_a, cx, cz, size, y0, h)
	var b := _slices(cave_b, cx, cz, size, y0, h)
	var c := _slices(cave_hall, cx, cz, size, y0, h)
	var lim := CAVE_WIDTH * 127.5
	var area := size * size
	for k in h:
		var y := y0 + k
		var da: PackedByteArray = a[k]
		var db: PackedByteArray = b[k]
		var dc: PackedByteArray = c[k]
		var up := clampf(float(y - y0) / (WATER_LEVEL - y0), 0.0, 1.0)
		var hall := 127.5 * (1.0 + lerpf(HALL_DEEP, HALL_HIGH, up))
		for i in area:
			var tunnel := absf(da[i] - 127.5) < lim and absf(db[i] - 127.5) < lim and y <= roof[i]
			if (tunnel or (dc[i] > hall and y <= tops[i] - HALL_ROOF)) and blocks[i + area * y] != World.WATER:
				var wet := y < tops[i] - AQUIFER_ROOF and y <= levels[y / AQUIFER_SIZE.y]
				blocks[i + area * y] = World.WATER if wet else World.AIR
				if wet:
					lake_low = mini(lake_low, y)
					lake_high = maxi(lake_high, y)
				opened = opened or y > tops[i] - CAVE_ROOF
	if lake_high >= 0:
		_drain_lakes(blocks, cx, cz, size, tops, lake_low, lake_high)
	return opened


# Underground lakes (Minecraft aquifers): the underground is split in regions of AQUIFER_SIZE; some
# have a water level, and cave air under it is water. Returns that level, -1 for a dry region.
func _aquifer(wx: int, y: int, wz: int) -> int:
	var key := Vector3i(floori(float(wx) / AQUIFER_SIZE.x), y / AQUIFER_SIZE.y, floori(float(wz) / AQUIFER_SIZE.z))
	if _aquifer_cache.has(key):
		return _aquifer_cache[key]
	var h := hash(Vector4i(key.x, key.y, key.z, world_seed))
	var level := -1
	if (h % 1000) / 1000.0 < AQUIFER_CHANCE:
		level = key.y * AQUIFER_SIZE.y + 3 + (h >> 10) % (AQUIFER_SIZE.y - 4)
	if _aquifer_cache.size() > 50000:
		_aquifer_cache.clear()
	_aquifer_cache[key] = level
	return level


# Lakes stay in their basins: underground water with air beside or under it is taken out, again
# and again until none is left. A spot in the next column counts as water if it's cave there and
# under the same aquifer level, as air if it's cave, else as rock.
func _drain_lakes(blocks: PackedByteArray, cx: int, cz: int, size: int, tops: PackedInt32Array, low: int, high: int) -> void:
	var area := size * size
	var todo: Array[Vector3i] = []  # (lx, y, lz) to check: everything once, then around what drained
	for y in range(low, high + 1):
		for lz in size:
			for lx in size:
				if blocks[lx + size * lz + area * y] == World.WATER:
					todo.append(Vector3i(lx, y, lz))
	while not todo.is_empty():
		var p: Vector3i = todo.pop_back()
		var i := p.x + size * p.z
		if blocks[i + area * p.y] != World.WATER or p.y >= tops[i]:
			continue
		var dry := blocks[i + area * (p.y - 1)] == World.AIR
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if dry:
				break
			var nx := p.x + d.x
			var nz := p.z + d.y
			if nx >= 0 and nz >= 0 and nx < size and nz < size:
				dry = blocks[nx + size * nz + area * p.y] == World.AIR
			else:
				var wx := cx * size + nx
				var wz := cz * size + nz
				dry = _cave_at(wx, p.y, wz) and p.y > _aquifer(wx, p.y, wz)
		if not dry:
			continue
		blocks[i + area * p.y] = World.AIR
		todo.append(p + Vector3i.UP)  # water above / beside it may hang now
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := p.x + d.x
			var nz := p.z + d.y
			if nx >= 0 and nz >= 0 and nx < size and nz < size:
				todo.append(Vector3i(nx, p.y, nz))


# Is (wx, y, wz) carved as tunnel or hall? One block, for neighbors outside the column.
func _cave_at(wx: int, y: int, wz: int) -> bool:
	if absf(cave_a.get_noise_3d(wx, wz, y)) < CAVE_WIDTH and absf(cave_b.get_noise_3d(wx, wz, y)) < CAVE_WIDTH:
		return true
	var up := clampf(float(y - BEDROCK_MAX - 1) / (WATER_LEVEL - BEDROCK_MAX - 1), 0.0, 1.0)
	return cave_hall.get_noise_3d(wx, wz, y) > lerpf(HALL_DEEP, HALL_HIGH, up)


# Noise n over the column (cx, cz), layers y0..y0+h-1: one byte array per layer, index lx + size * lz.
# ponytail: moves the shared noise's offset (put back after), so generation must stay on one thread
# (10g changes it).
func _slices(n: FastNoiseLite, cx: int, cz: int, size: int, y0: int, h: int) -> Array:
	n.offset = Vector3(cx * size, cz * size, y0)
	var out := []
	for img: Image in n.get_image_3d(size, size, h, false, false):
		out.append(img.get_data())
	n.offset = Vector3.ZERO  # single-block lookups (_cave_at) need it at the origin
	return out


# Ore veins: random walks that only turn stone / deepslate into ore. They stay inside the column
# (a vein reaching the border stops there) so generation stays per-column.
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

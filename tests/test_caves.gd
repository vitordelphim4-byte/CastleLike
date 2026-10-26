extends SceneTree
## Run: godot --headless --path . -s tests/test_caves.gd
## Phase 10b/10c: tunnels and halls. Over 7x7 columns of a real seed: 5-15% of the underground is
## cave air, nothing is carved within CAVE_ROOF of the surface, bedrock and water are intact, and
## a column comes out identical however many other columns were generated before it (the noise
## offset trick must not leak between columns). In 3 seeds, near the spawn, the deep caves let a
## villager walk at least HALL_WALK blocks (nav on a real World node). 10d: some cave mouth near
## the spawn leads on foot from the surface into a cave 8+ blocks down, and nothing is carved open
## (within CAVE_ROOF of the surface) inside OPEN_CLEAR of the spawn.


func _initialize() -> void:
	var gen := WorldGen.new(1000)
	var home := Vector2i(gen.spawn.x >> 4, gen.spawn.y >> 4)
	var first: PackedByteArray = gen.generate(home.x, home.y, World.CHUNK, World.SY).blocks
	var air := 0
	var under := 0
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var b: PackedByteArray = gen.generate(home.x + cx, home.y + cz, World.CHUNK, World.SY).blocks
			for lz in World.CHUNK:
				for lx in World.CHUNK:
					var wx := home.x * 16 + cx * 16 + lx
					var wz := home.y * 16 + cz * 16 + lz
					var top := int(gen.height(wx, wz))
					top = clampi(top, 1, World.SY - 3)
					for y in World.SY:
						var t := b[lx + World.CHUNK * (lz + World.CHUNK * y)]
						if y <= WorldGen.BEDROCK_MAX and y == 0 and t != World.BEDROCK:
							return _fail("bedrock carved")
						if y > top - WorldGen.CAVE_ROOF and y <= top and t == World.AIR and not _may_open(gen, wx, wz, top):
							return _fail("tunnel within %d of the surface at y %d (top %d)" % [WorldGen.CAVE_ROOF, y, top])
						if y > WorldGen.BEDROCK_MAX and y <= top - WorldGen.CAVE_ROOF:
							under += 1
							air += int(t == World.AIR)
	var pct := 100.0 * air / under
	print("cave air: %.1f%% of the underground" % pct)
	if pct < 5.0 or pct > 15.0:
		return _fail("cave air %.1f%% outside 5-15%%" % pct)
	if gen.generate(home.x, home.y, World.CHUNK, World.SY).blocks != first:
		return _fail("same column, different blocks after generating others")
	if WorldGen.new(1000).generate(home.x, home.y, World.CHUNK, World.SY).blocks != first:
		return _fail("same seed, different tunnels")
	for sd in [1000, 8919, 16838]:
		var walk := _longest_deep_walk(sd)
		print("seed %d: deep walk %.0f blocks" % [sd, walk])
		if walk < HALL_WALK:
			return _fail("seed %d: no deep cave to walk %d blocks in near the spawn" % [sd, HALL_WALK])
	for sd in [1000, 8919, 16838]:
		var g := WorldGen.new(sd)
		for cx in range(-3, 4):
			for cz in range(-3, 4):
				var c := Vector2i((g.spawn.x >> 4) + cx, (g.spawn.y >> 4) + cz)
				var b: PackedByteArray = g.generate(c.x, c.y, World.CHUNK, World.SY).blocks
				for lz in World.CHUNK:
					for lx in World.CHUNK:
						var wx := c.x * 16 + lx
						var wz := c.y * 16 + lz
						if Vector2(wx - g.spawn.x, wz - g.spawn.y).length() > WorldGen.OPEN_CLEAR:
							continue
						var top := clampi(int(g.height(wx, wz)), 1, World.SY - 3)
						for y in range(top - WorldGen.CAVE_ROOF + 1, top + 1):
							if b[lx + 16 * (lz + 16 * y)] == World.AIR:
								return _fail("seed %d: opening at (%d, %d, %d), inside the start area" % [sd, wx, y, wz])
		if not _mouth_walkable(sd):
			return _fail("seed %d: no cave mouth near the spawn leads on foot into the caves" % sd)
	print("test_caves OK")
	quit()


const HALL_WALK := 16


# Where a cave mouth or ravine is allowed to break the surface (else: CAVE_ROOF of rock on top).
func _may_open(g: WorldGen, wx: int, wz: int, top: int) -> bool:
	var mouth := g.entrance.get_noise_2d(wx, wz) > WorldGen.ENTRANCE_MASK
	return g._can_open(wx, wz, top) and (mouth or g.ravine_mask.get_noise_2d(wx, wz) >= WorldGen.RAVINE_MASK)


# Real World around the spawn (nav only): among deep walkable cells (15+ under the ground), the
# longest straight-line distance a path actually covers, over a sample of pairs.
func _longest_deep_walk(sd: int) -> float:
	var w := World.new()
	w.world_seed = sd
	root.add_child(w)
	if w.gen == null:  # _ready hasn't run yet inside _initialize
		w.gen = WorldGen.new(sd)
	var sp := Vector3(w.gen.spawn.x, 0, w.gen.spawn.y)
	w.load_area(sp, 2, false)
	var deep: Array[Vector3] = []
	for id in w.astar.get_point_ids():
		var p := w.astar.get_point_position(id)
		if p.y < w.ground_at(floori(p.x), floori(p.z)) - 15:
			deep.append(p)
	var best := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for k in mini(400, deep.size()):
		var a := deep[rng.randi() % deep.size()]
		var b := deep[rng.randi() % deep.size()]
		var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		if d <= best:
			continue
		var path := w.find_path(a, b)
		if not path.is_empty() and path[-1].distance_to(b) < 1.5 and path[0].distance_to(a) < 1.5:
			best = d
	w.queue_free()
	return best


# Columns with a mouth (generate's "opened"), nearest the spawn first: on a real World, some
# surface cell outside reaches a cave cell 8+ under the ground. Up to 8 mouths tried.
func _mouth_walkable(sd: int) -> bool:
	var g := WorldGen.new(sd)
	var home := Vector2i(g.spawn.x >> 4, g.spawn.y >> 4)
	var mouths: Array[Vector2i] = []
	for r in range(1, 10):
		for cx in range(-r, r + 1):
			for cz in range(-r, r + 1):
				if maxi(absi(cx), absi(cz)) == r and g.generate(home.x + cx, home.y + cz, 16, World.SY).opened:
					mouths.append(home + Vector2i(cx, cz))
	for c in mouths.slice(0, 8):
		var w := World.new()
		w.world_seed = sd
		root.add_child(w)
		if w.gen == null:
			w.gen = WorldGen.new(sd)
		w.load_area(Vector3(c.x * 16 + 8, 0, c.y * 16 + 8), 1, false)
		var outside: Array[Vector3] = []
		var inside: Array[Vector3] = []
		for id in w.astar.get_point_ids():
			var p := w.astar.get_point_position(id)
			var ground := w.ground_at(floori(p.x), floori(p.z))
			if p.y >= ground - 1:
				outside.append(p)
			elif p.y < ground - 8:
				inside.append(p)
		var ok := false
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		for k in mini(60, inside.size()):
			var a := outside[rng.randi() % outside.size()]
			var b := inside[rng.randi() % inside.size()]
			var path := w.find_path(a, b)
			if not path.is_empty() and path[0].distance_to(a) < 1.5 and path[-1].distance_to(b) < 1.5:
				ok = true
				break
		w.queue_free()
		if ok:
			return true
	return false


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)

extends SceneTree
## Run: godot --headless --path . -s tests/test_rivers.gd
## Phase 10e4: mixed rivers. In 3 seeds, within 300 blocks of the spawn: rivers up high are narrow
## streams and rivers at sea level are wide; streams have a current; their water stays in its bed
## (few surface cells open to the air on the side); no river water in the start area. Waterfalls:
## seed 1000 has river falls (falling columns 4+ tall) near the spawn, and a cave spring, once the
## water runs on a real World, falls to the hall floor and spreads there.

const R := 300


func _initialize() -> void:
	for sd in [1000, 8919, 16838]:
		var g := WorldGen.new(sd)
		var widths := {"high": [], "low": []}
		var flowing := 0
		var high_n := 0
		for x in range(g.spawn.x - R, g.spawn.x + R, 6):
			for z in range(g.spawn.y - R, g.spawn.y + R, 6):
				var r := g.river(x, z)
				if r.x < 0.9:
					continue
				var kind := "high" if r.y >= WorldGen.WATER_LEVEL + 10 else ("low" if r.y == WorldGen.WATER_LEVEL else "")
				if kind == "":
					continue
				widths[kind].append(mini(_run(g, x, z, Vector2i(1, 0)), _run(g, x, z, Vector2i(0, 1))))
				if kind == "high":
					high_n += 1
					flowing += int(g.river_flow(x, z) != Vector2.ZERO)
		var hi := _mean(widths.high)
		var lo := _mean(widths.low)
		print("seed %d: stream width %.1f (%d), river width %.1f (%d), streams flowing %d/%d" % [sd, hi, widths.high.size(), lo, widths.low.size(), flowing, high_n])
		if widths.high.size() > 0 and hi > 5.0:
			return _fail("seed %d: streams up high too wide (%.1f)" % [sd, hi])
		if widths.low.size() > 0 and lo < 5.0:
			return _fail("seed %d: rivers at sea level too narrow (%.1f)" % [sd, lo])
		if high_n > 0 and flowing < high_n * 0.8:
			return _fail("seed %d: only %d of %d stream spots have a current" % [sd, flowing, high_n])
		var open := _open_sides(g)
		print("  river surface open to the air on a side: %.1f%%" % (open * 100.0))
		if open > 0.03:
			return _fail("seed %d: river water spilling out of its bed (%.0f%%)" % [sd, open * 100.0])
	var g := WorldGen.new(1000)
	var home := Vector2i(g.spawn.x >> 4, g.spawn.y >> 4)
	var tallest := 0
	var spring := Vector3i(-1, -1, -1)
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var res := g.generate(home.x + cx, home.y + cz, 16, World.SY)
			if spring.y < 0 and not res.springs.is_empty():
				spring = res.springs[0]
			for i in 256:
				var run := 0
				for y in range(WorldGen.WATER_LEVEL, World.SY):
					run = run + 1 if res.blocks[i + 256 * y] == World.FALLING else 0
					tallest = maxi(tallest, run)
	print("tallest river fall: %d falling blocks" % tallest)
	if tallest < 4:
		return _fail("no river waterfall 4+ tall near the spawn")
	if spring.y < 0:
		return _fail("no cave spring near the spawn")
	var w := World.new()
	w.world_seed = 1000
	root.add_child(w)
	if w.gen == null:
		w.gen = WorldGen.new(1000)
	w.fluids.world = w
	w.load_area(Vector3(spring), 1, false)
	w.fluids.wake(spring)
	for k in 80:
		w.fluids.step()
	var fall := 0
	var y := spring.y - 1
	while World.is_water(w.get_block(Vector3i(spring.x, y, spring.z))):
		fall += 1
		y -= 1
	var pool := 0
	for dx in range(-7, 8):
		for dz in range(-7, 8):
			for dy in range(-8, 2):  # the floor isn't flat: the water runs on down
				if dx != 0 or dz != 0:
					pool += int(World.is_water(w.get_block(Vector3i(spring.x + dx, y + dy, spring.z + dz))))
	print("cave waterfall: %d blocks down, %d water cells spread around its foot" % [fall, pool])
	if fall < WorldGen.CAVE_FALL_MIN or pool < 5:
		return _fail("cave spring at %s: fell %d, pool %d" % [spring, fall, pool])
	print("test_rivers OK")
	quit()


# Cells in a row (both ways) where the bed holds river water.
func _run(g: WorldGen, x: int, z: int, d: Vector2i) -> int:
	var n := 1
	for sgn in [1, -1]:
		for k in range(1, 30):
			if g.river(x + d.x * k * sgn, z + d.y * k * sgn).x <= WorldGen.RIVER_WET:
				break
			n += 1
	return n


func _mean(a: Array) -> float:
	return 0.0 if a.is_empty() else a.reduce(func(s, v): return s + v, 0.0) / a.size()


# Over generated columns around the spawn: share of river water surface cells (above sea level)
# with air beside them at the same height, i.e. water hanging out of the bed. No river water may
# sit inside the start area.
func _open_sides(g: WorldGen) -> float:
	var surface := 0
	var open := 0
	var home := Vector2i(g.spawn.x >> 4, g.spawn.y >> 4)
	for cx in range(-8, 9):
		for cz in range(-8, 9):
			var c := home + Vector2i(cx, cz)
			var b: PackedByteArray = g.generate(c.x, c.y, 16, World.SY).blocks
			for lz in range(1, 15):
				for lx in range(1, 15):
					for y in range(WorldGen.WATER_LEVEL + 1, World.SY - 1):
						var i := lx + 16 * (lz + 16 * y)
						if b[i] != World.WATER or b[i + 256] != World.AIR:
							continue
						var wx := c.x * 16 + lx
						var wz := c.y * 16 + lz
						if Vector2(wx - g.spawn.x, wz - g.spawn.y).length() < WorldGen.START_RADIUS:
							_fail("river water inside the start area at (%d, %d)" % [wx, wz])
						surface += 1
						for o in [1, -1, 16, -16]:
							if b[i + o] == World.AIR:
								open += 1
								break
	return 0.0 if surface == 0 else float(open) / surface


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)

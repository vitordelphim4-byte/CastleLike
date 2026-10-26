extends SceneTree
## Run: godot --headless --path . -s tests/test_rivers.gd
## Phase 10e4: mixed rivers. In 3 seeds, within 300 blocks of the spawn: rivers up high are narrow
## streams and rivers at sea level are wide; streams have a current; their water stays in its bed
## (few surface cells open to the air on the side); no river water in the start area.

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
		if open > 0.2:
			return _fail("seed %d: river water spilling out of its bed (%.0f%%)" % [sd, open * 100.0])
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

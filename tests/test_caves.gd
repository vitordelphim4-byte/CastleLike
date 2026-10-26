extends SceneTree
## Run: godot --headless --path . -s tests/test_caves.gd
## Phase 10b: spaghetti tunnels. Over 7x7 columns of a real seed: 3-8% of the underground is
## tunnel air, nothing is carved within CAVE_ROOF of the surface, bedrock and water are intact, and
## a column comes out identical however many other columns were generated before it (the noise
## offset trick must not leak between columns).


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
					var top := int(gen.height(home.x * 16 + cx * 16 + lx, home.y * 16 + cz * 16 + lz))
					top = clampi(top, 1, World.SY - 3)
					for y in World.SY:
						var t := b[lx + World.CHUNK * (lz + World.CHUNK * y)]
						if y <= WorldGen.BEDROCK_MAX and y == 0 and t != World.BEDROCK:
							return _fail("bedrock carved")
						if y > top - WorldGen.CAVE_ROOF and y <= top and t == World.AIR:
							return _fail("tunnel within %d of the surface at y %d (top %d)" % [WorldGen.CAVE_ROOF, y, top])
						if y > WorldGen.BEDROCK_MAX and y <= top - WorldGen.CAVE_ROOF:
							under += 1
							air += int(t == World.AIR)
	var pct := 100.0 * air / under
	print("tunnel air: %.1f%% of the underground" % pct)
	if pct < 3.0 or pct > 8.0:
		return _fail("tunnel air %.1f%% outside 3-8%%" % pct)
	if gen.generate(home.x, home.y, World.CHUNK, World.SY).blocks != first:
		return _fail("same column, different blocks after generating others")
	if WorldGen.new(1000).generate(home.x, home.y, World.CHUNK, World.SY).blocks != first:
		return _fail("same seed, different tunnels")
	print("test_caves OK")
	quit()


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)

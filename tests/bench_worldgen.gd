extends SceneTree
## Run: godot --headless --path . -s tests/bench_worldgen.gd [-- seeds]
## World generation benchmark + variety check:
## - speed: WorldGen.generate per column, and the full pipeline (generate + nav + meshes) per column
## - memory: static memory per loaded column
## - variety: spawn spot and biome mix around it for several seeds (they should all differ)

const SAMPLE_R := 160  # blocks around the spawn sampled for the biome mix
const GEN_R := 3  # columns around the spawn generated for timing (7x7)

var failed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 8
	var gen_ms := 0.0
	var gen_n := 0
	var spawns := {}
	var mixes := {}
	print("seed        spawn          h  biome     | biome mix within %d blocks" % SAMPLE_R)
	for i in seeds:
		var s := 1000 + i * 7919
		var gen := WorldGen.new(s)
		var sp: Vector2i = gen.get("spawn") if gen.get("spawn") != null else Vector2i.ZERO
		var cc := Vector2i(sp.x >> 4, sp.y >> 4)
		var t := Time.get_ticks_usec()
		for x in range(-GEN_R, GEN_R + 1):
			for z in range(-GEN_R, GEN_R + 1):
				gen.generate(cc.x + x, cc.y + z, World.CHUNK, World.SY)
				gen_n += 1
		gen_ms += (Time.get_ticks_usec() - t) / 1000.0
		var mix := {}
		for x in range(-SAMPLE_R, SAMPLE_R + 1, 8):
			for z in range(-SAMPLE_R, SAMPLE_R + 1, 8):
				var b := gen.biome(sp.x + x, sp.y + z, int(gen.height(sp.x + x, sp.y + z)))
				mix[b] = mix.get(b, 0) + 1
		var total := 0
		for b in mix:
			total += mix[b]
		var parts := []
		for b in mix:
			parts.append("%s %d%%" % [b, roundi(100.0 * mix[b] / total)])
		var h := int(gen.height(sp.x, sp.y))
		var sb := gen.biome(sp.x, sp.y, h)
		print("%-10d  %-13s  %-2d %-9s | %s" % [s, str(sp), h, sb, ", ".join(parts)])
		_check(sb not in ["water", "beach"], "seed %d spawns on dry land (%s)" % [s, sb])
		spawns[sp] = true
		mixes[str(mix.keys())] = true

	print("\nWorldGen.generate: %.2f ms/column (%d columns)" % [gen_ms / gen_n, gen_n])

	# Full pipeline on a real World node: generate + nav + meshes, and memory per column.
	var world := World.new()
	world.world_seed = 4242
	root.add_child(world)
	await process_frame
	var sp: Vector2i = world.gen.get("spawn") if world.gen.get("spawn") != null else Vector2i.ZERO
	var mem := OS.get_static_memory_usage()
	var t := Time.get_ticks_usec()
	world.load_area(Vector3(sp.x, 40, sp.y), 4, false)
	var nav_ms := (Time.get_ticks_usec() - t) / 1000.0
	var nav_mem := OS.get_static_memory_usage() - mem
	var cols := world.columns.size()
	t = Time.get_ticks_usec()
	world.load_area(Vector3(sp.x, 40, sp.y), 4)
	var mesh_ms := (Time.get_ticks_usec() - t) / 1000.0
	var mesh_mem := OS.get_static_memory_usage() - mem - nav_mem
	print("World gen + nav: %.2f ms/column, %d KB/column (%d columns)" % [nav_ms / cols, nav_mem / 1024 / cols, cols])
	print("World meshes:    %.2f ms/column, %d KB/column" % [mesh_ms / world.meshed.size(), mesh_mem / 1024 / world.meshed.size()])
	# Second area: tree models are cached by now, so this is the cost while exploring.
	var n := world.meshed.size()
	mem = OS.get_static_memory_usage()
	t = Time.get_ticks_usec()
	world.load_area(Vector3(sp.x + 400, 40, sp.y), 4)
	print("Exploring (gen + nav + meshes, trees cached): %.2f ms/column, %d KB/column" % [
		(Time.get_ticks_usec() - t) / 1000.0 / (world.meshed.size() - n), (OS.get_static_memory_usage() - mem) / 1024 / (world.meshed.size() - n)])

	_check(spawns.size() == seeds, "every seed spawns somewhere else (%d of %d distinct)" % [spawns.size(), seeds])
	if not failed:
		print("bench_worldgen OK")
	quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL: ", what)

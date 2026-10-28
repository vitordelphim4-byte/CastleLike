extends SceneTree
## Run: godot --headless --path . -s tests/bench_explore.gd
## Phase 10g: exploring like the game does. The world streams around a focus moving east at a
## steady speed, one frame at a time (stream() with its per-frame budget). Reports how long the
## world's own work takes per frame (average and worst) and how many columns got meshed, with and
## without the background generation thread.

const FRAMES := 600
const SPEED := 0.5  # blocks per frame (30 blocks/s at 60 fps: a fast camera pan)


func _initialize() -> void:
	for ahead in [0, 12]:
		var w := World.new()
		w.world_seed = 4242
		w.GEN_AHEAD = ahead
		root.add_child(w)
		await process_frame
		var start := Vector3(w.gen.spawn.x, 0, w.gen.spawn.y)
		w.load_area(start, 2)
		var worst := 0.0
		var total := 0.0
		var seen := {}  # columns meshed at some point (unloading shrinks w.meshed)
		for f in FRAMES:
			w.focus = start + Vector3(f * SPEED, 0, 0)
			var t := Time.get_ticks_usec()
			w.stream(World.STREAM_BUDGET_MS)
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			total += ms
			if f > 10:
				worst = maxf(worst, ms)
			for c: Vector2i in w.meshed:
				seen[c] = true
			await process_frame
		print("%-22s world work per frame: avg %.1f ms, worst %.1f ms; %d columns meshed in %d frames" % [
			"worker thread" if ahead > 0 else "no thread", total / FRAMES, worst, seen.size(), FRAMES])
		w.queue_free()
		await process_frame
	quit()

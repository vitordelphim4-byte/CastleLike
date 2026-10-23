extends SceneTree
## Run: godot --headless --path . -s tests/test_day_night.gd
## Clock advances and wraps into the next day, pause stops it, light always shines from above
## (sun by day, dim moon by night), clock text formats hours.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	var sun: DirectionalLight3D = root.get_node("Main/Sun")
	await process_frame

	game.time_of_day = 0.5
	await process_frame
	var noon_energy := sun.light_energy
	_check(sun.basis.z.y > 0.5, "noon light comes from above: %s" % sun.basis.z)

	game.time_of_day = 0.0
	await process_frame
	_check(sun.basis.z.y > 0.1, "moon light comes from above: %s" % sun.basis.z)
	_check(sun.light_energy < noon_energy * 0.5, "night darker: %f vs %f" % [sun.light_energy, noon_energy])

	game.time_of_day = 0.9999
	game.day = 1
	game._process(1.0)
	_check(game.day == 2 and game.time_of_day < 0.01, "wraps to day 2: day %d t %f" % [game.day, game.time_of_day])

	game.set_speed(0)
	await process_frame  # this frame's delta was computed before the speed change
	var t: float = game.time_of_day
	await process_frame
	await process_frame
	_check(game.time_of_day == t, "paused clock stands still: %f -> %f scale %f" % [t, game.time_of_day, Engine.time_scale])
	game.toggle_game_pause()
	_check(game.speed == 1 and Engine.time_scale == 1.0, "unpause restores speed: %d" % game.speed)

	game.time_of_day = 0.5
	_check(game.clock_text() == "Dia 2 · 12:00", "clock text: %s" % game.clock_text())

	if not failed:
		print("test_day_night OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true

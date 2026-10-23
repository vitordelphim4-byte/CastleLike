extends SceneTree
func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	for i in 30: await process_frame
	var game = root.get_node("Game")
	var w = game.world
	var s := Vector3i(game.stockpile.floor())
	var y: int = w.top_at(s.x, s.z - 4)
	w.add_prop(Vector3i(s.x - 3, y, s.z - 5), "furnace", Vector3i.FORWARD)
	w.add_prop(Vector3i(s.x, y, s.z - 5), "furnace", Vector3i.FORWARD)
	w.add_prop(Vector3i(s.x + 3, y, s.z - 4), "kiln", Vector3i.FORWARD)
	w.add_prop(Vector3i(s.x + 5, y, s.z - 4), "kiln", Vector3i.FORWARD)
	w.set_station_active(Vector3i(s.x, y, s.z - 5), true)
	w.set_station_active(Vector3i(s.x + 5, y, s.z - 4), true)
	for x in range(s.x - 3, s.x + 6):
		w.set_block(Vector3i(x, y - 1, s.z - 7), World.IRON_ORE)
	var tiles: Array = game.zones[0].tiles.keys()
	game.deposit(tiles[0], "iron_ore", 18)
	game.deposit(tiles[1], "charcoal", 12)
	game.deposit(tiles[2], "iron", 20)
	game.deposit(tiles[3], "iron_ore", 6)
	for wk in get_nodes_in_group("workers"):
		for k in wk.priorities: wk.priorities[k] = 0
		wk.position.z += 3
	root.get_node("Main/StationPanel").open(Vector3i(s.x, y, s.z - 5))
	var rig = root.get_node("Main/CameraRig")
	rig.position = Vector3(s.x + 1, y, s.z - 2)
	rig.distance = 9.0
	rig.rotation.y = 0.35
	rig.pitch = deg_to_rad(30)
	rig._update_cam()
	game.time_of_day = float(OS.get_cmdline_user_args()[1])
	for i in 120: await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()

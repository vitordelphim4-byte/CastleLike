extends SceneTree
## Run (needs a window, not --headless): godot --path . -s tests/screenshot.gd -- <out.png> [distance] [mode] [time_of_day] [seed]
## Starts the game with all workers chopping, waits, saves a screenshot.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shot.png"
	var scene := "res://debug.tscn" if args.size() > 2 and args[2] in ["debug", "ui", "roof", "xray", "hill", "hill_cut", "hill_cave", "tower", "tower0", "tower1", "tower_low"] else "res://main.tscn"
	var game := root.get_node("Game")
	if args.size() > 4:
		game.start_seed = int(args[4])
	root.add_child(load(scene).instantiate())
	await process_frame
	if args.size() > 3:
		game.time_of_day = float(args[3])
	var home := Vector2i(int(game.stockpile.x), int(game.stockpile.z))
	var trees: Dictionary = game.add_order("wood", Rect2i(home - Vector2i(32, 32), Vector2i(64, 64)))
	trees.marker.visible = false  # whole-map area would clutter the shot
	var workers := root.get_tree().get_nodes_in_group("workers")
	if args.size() > 2 and args[2] == "work":
		root.get_tree().get_first_node_in_group("work_tab").toggle()
	if args.size() > 2 and args[2] == "build":  # show blueprints, finished blocks and dig marks
		var s := Vector3i(game.stockpile.floor())
		var y: int = game.world.top_at(s.x, s.z - 3)
		for x in range(s.x - 3, s.x + 4):
			game.world.set_block(Vector3i(x, y, s.z - 3), World.BRICK)
			game.world.set_block(Vector3i(x, y, s.z - 4), World.WOOD)
		var bp: Array[Vector3i] = []
		for x in range(s.x - 3, s.x + 4):
			bp.append(Vector3i(x, y + 1, s.z - 3))
		game.place_blueprints(bp)
		game.dig_depth = 2
		game.add_order("dig", Rect2i(s.x + 2, s.z, 3, 3))
	if args.size() > 2 and args[2] == "ladder":  # 4-high brick wall with a ladder
		var s := Vector3i(game.stockpile.floor())
		var y: int = game.world.top_at(s.x, s.z - 3)
		for x in range(s.x - 2, s.x + 3):
			for h in 4:
				game.world.set_block(Vector3i(x, y + h, s.z - 3), World.BRICK)
		for h in 4:
			game.world.add_ladder(Vector3i(s.x, y + h, s.z - 2), Vector3i.FORWARD)
	if args.size() > 2 and args[2] == "ui":  # one of every piece built + build menu open
		var s := Vector3i(game.stockpile.floor())
		var y: int = game.world.top_at(s.x, s.z)
		var x := s.x - 6
		for item: String in Pieces.ITEMS:
			var c := Vector3i(x, y, s.z - 3)
			if Pieces.is_block(item):
				game.world.set_block(c, Pieces.block_type(item))
			elif item == "ladder":
				game.world.set_block(c + Vector3i.FORWARD, World.BRICK)
				game.world.add_prop(c, item, Vector3i.FORWARD)
			else:
				game.world.add_prop(c, item, Vector3i.BACK)
			x += 1
		game.build_item = "stone_window"
		game.set_building(true)
		game.mark_demolish([Vector3i(s.x - 5, y, s.z - 3), Vector3i(s.x - 1, y, s.z - 3)] as Array[Vector3i], true)
		for i in workers.size():  # line them up facing the camera, idle
			for work in workers[i].priorities:
				workers[i].priorities[work] = 0
			workers[i].position = Vector3(s.x - 1.5 + i, y, s.z - 1.5)
			workers[i].rotation.y = PI
	if args.size() > 2 and args[2] == "roof":  # finished roofs on the debug houses, built instantly
		var houses: Array = root.get_node("Main").debug_houses
		var base: int = game.world.top_at(houses[0].position.x, houses[0].position.y)
		var specs := [["hip", "wood", false], ["gable", "stone", true]]
		for i in 2:
			var plan := Roofs.plan(houses[i], base, specs[i][0], specs[i][1], true, specs[i][2])
			for c: Vector3i in plan:
				if Pieces.is_block(plan[c].item):
					game.world.set_block(c, Pieces.block_type(plan[c].item))
				else:
					game.world.add_prop(c, plan[c].item, plan[c].dir)
		for w in workers:
			for work in w.priorities:
				w.priorities[work] = 0
	if args.size() > 2 and args[2] == "xray":  # villagers walled in a stone hill: x-ray + outlines
		var s := Vector3i(game.stockpile.floor())
		var y: int = game.world.top_at(s.x, s.z)
		for x in range(s.x - 4, s.x + 5):
			for z in range(s.z - 2, s.z + 7):
				for h in 4:
					if not (h < 2 and absi(x - s.x) < 3 and z >= s.z + 1 and z <= s.z + 3):
						game.world.set_block(Vector3i(x, y + h, z), World.STONE)
		for i in workers.size():
			for work in workers[i].priorities:
				workers[i].priorities[work] = 0
			workers[i].position = Vector3(s.x - 1.5 + i * 0.8, y, s.z + 2.5)
		workers[0].selected = true
	var rig: Node3D = root.get_node("Main/CameraRig")
	var view_spot = null
	if args.size() > 2 and args[2] in ["world", "cut", "deep", "caves"]:  # look at a mountain with water nearby
		var gen: WorldGen = game.world.gen
		var best := -1.0
		for x in range(home.x - 160, home.x + 161, 8):
			for z in range(home.y - 160, home.y + 161, 8):
				if gen.biome(x, z, int(gen.height(x, z))) != "mountain":
					continue
				for a in 12:
					var d := Vector2(cos(a * TAU / 12), sin(a * TAU / 12)) * 30
					var wx := x + int(d.x)
					var wz := z + int(d.y)
					if gen.biome(wx, wz, int(gen.height(wx, wz))) == "water":
						var score := 200.0 - Vector2(x - home.x, z - home.y).length()
						if score > best:
							best = score
							view_spot = Vector3((x + wx) / 2.0, 0, (z + wz) / 2.0)
		if view_spot == null:
			view_spot = game.stockpile
	if args.size() > 2 and args[2].begins_with("tower"):  # debug 2-floor building, floor view
		var panel: Node = null
		for n in root.get_node("Main").get_children():
			if n.has_method("_view_tower"):
				panel = n
		match args[2]:
			"tower": panel._go_tower()
			"tower0": panel._view_tower(3)
			"tower1": panel._view_tower(7)
			"tower_low": panel._view_tower(1)
		view_spot = rig.position
	if args.size() > 2 and args[2].begins_with("hill"):  # debug hill (Phase 9), via the debug panel
		var panel: Node = null
		for n in root.get_node("Main").get_children():
			if n.has_method("_villager_in"):
				panel = n
		panel._villager_in()
		if args[2] == "hill_cut":
			panel._dig_tunnel()
		elif args[2] == "hill_cave":
			panel._cut(6)
		view_spot = rig.position
	rig.distance = float(args[1]) if args.size() > 1 else 14.0
	if rig.distance < 8:
		rig.pitch = deg_to_rad(25)
	for i in (500 if view_spot != null else 200):
		await process_frame
		var offsets := {"ui": Vector3(1, 0, -3), "roof": Vector3(-3, 0, 0)}
		if view_spot != null:
			rig.position.x = view_spot.x
			rig.position.z = view_spot.z
		else:
			rig.position = game.stockpile + offsets.get(args[2], Vector3.ZERO) if args.size() > 2 else workers[0].position
		rig._update_cam()
	if args.size() > 2 and args[2] in ["cut", "deep", "caves"]:  # slice the ground under the camera: 4 / 24 layers down, or at the deepslate edge
		var under: int = game.world.top_at(floori(rig.position.x), floori(rig.position.z)) - (24 if args[2] == "caves" else 4)
		game.world.set_cut(WorldGen.DEEP_TOP + 1 if args[2] == "deep" else under)
		for i in 150:  # deep sections stream in after the cut turns on
			await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()

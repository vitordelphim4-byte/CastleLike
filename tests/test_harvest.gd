extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_harvest.gd
## Workers must deliver wood to the stockpile within 60 simulated seconds.


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var empty: Dictionary = game.add_order("dig", Rect2i(0, 0, 1, 1))
	empty.cells.clear()  # an order with nothing left to do: workers must fall through to wood
	game.add_order("wood", Rect2i(-48, -48, 96, 96))
	for frame in 3600:
		await process_frame
		if game.stock.wood > 0:
			print("test_harvest OK (frame %d)" % frame)
			quit()
			return
	printerr("FAIL: no wood delivered")
	quit(1)

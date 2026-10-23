extends SceneTree
## Run: godot --headless --path . -s tests/test_explore_limit.gd
## The camera can't get farther than EXPLORE_RADIUS from the nearest villager; moving a villager
## out lets it follow.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var main := root.get_node("Main")
	var rig: Node3D = root.get_node("Main/CameraRig")
	await process_frame
	var limit: float = main.EXPLORE_RADIUS
	rig.position = Vector3(1000, rig.position.y, 0)
	await process_frame
	_check(Vector2(rig.position.x, rig.position.z).length() <= limit + 10, "camera pulled back, at %s" % rig.position)
	_check(rig.position.x > limit - 10, "pulled back only to the edge, not further: %s" % rig.position)

	var scout = root.get_tree().get_nodes_in_group("workers")[0]
	scout.position = Vector3(400, scout.position.y, 0)  # a villager out exploring
	rig.position = Vector3(500, rig.position.y, 0)
	await process_frame
	_check(absf(rig.position.x - 500) < 0.01, "camera may go where a villager is, at %s" % rig.position)
	if not failed:
		print("test_explore_limit OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true

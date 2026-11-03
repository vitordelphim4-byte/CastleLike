extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_mobs.gd
## Monsters (Phase 13) on the debug map, north of the stockpile: a zombie knocks out an unarmed
## villager and moves on; with permadeath on, a villager dies.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var mob_script = load("res://scripts/mob.gd")
	var worker_script = load("res://scripts/worker.gd")
	var main := root.get_node("Main")
	var w = game.world
	game.hunger = false
	var workers := get_nodes_in_group("workers")
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 0
	var s := Vector3i(game.stockpile.floor())
	var victim = workers[0]
	victim.position = Vector3(s.x + 0.5, w.top_at(s.x, s.z - 12), s.z - 11.5)
	victim.move_to(victim.position)
	victim.hp = 3  # a few hits: the zombie is slow and the villager runs
	var zombie = mob_script.spawn(main.mobs, w, "zombie", Vector3(s.x + 0.5, w.top_at(s.x, s.z - 20), s.z - 19.5))

	var downed := false
	for frame in 9000:
		await process_frame
		if victim.state == worker_script.DOWNED:
			downed = true
			break
	_check(downed, "zombie knocked the villager out (hp %d, zombie %s)" % [victim.hp, zombie.STATE_NAMES[zombie.state]])
	for frame in 60:
		await process_frame
	_check(zombie.target != victim, "zombie leaves a downed villager alone")

	game.permadeath = true
	victim.heal()
	for wk in workers:
		wk.hp = 1
	var dead := false
	for frame in 12000:
		await process_frame
		if not get_nodes_in_group("dead").is_empty():
			dead = true
			break
	_check(dead, "permadeath: a villager died")
	_check(get_nodes_in_group("workers").size() == workers.size() - 1, "the dead left the villagers")
	if not failed:
		print("test_mobs OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true

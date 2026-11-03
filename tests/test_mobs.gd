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
	victim.hp = 3  # a few hits
	victim.speed = 1.0  # else it outruns the zombie (it runs from monsters close by)
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

	# Guards: a soldier and an archer kill a zombie going for a peasant.
	for m in get_nodes_in_group("mobs"):
		m.hurt(999, null)
	game.permadeath = false
	for wk in workers:
		wk.heal()
		wk.move_to(wk.position)
	victim.speed = 4.0
	var soldier = workers[1]
	var archer = workers[2]
	soldier.priorities["soldier"] = 1
	archer.priorities["archer"] = 1
	_place(victim, w, s + Vector3i(0, 0, -12))
	_place(soldier, w, s + Vector3i(3, 0, -12))
	_place(archer, w, s + Vector3i(-3, 0, -9))
	zombie = mob_script.spawn(main.mobs, w, "zombie", Vector3(s.x + 0.5, w.top_at(s.x, s.z - 22), s.z - 21.5))
	var fought := false
	var shot := false
	for frame in 6000:
		await process_frame
		fought = fought or (soldier.job_kind == "defend" and soldier.state == worker_script.WORKING)
		shot = shot or (archer.job_kind == "defend" and archer.state == worker_script.WORKING)
		if zombie.state == mob_script.DEAD:
			break
	_check(zombie.state == mob_script.DEAD, "guards killed the zombie (hp %d)" % zombie.hp)
	_check(fought and shot, "soldier fought (%s) and archer shot (%s)" % [fought, shot])
	_check(victim.state != worker_script.DOWNED and victim.hp > 0, "peasant still up: hp %d" % victim.hp)
	if not failed:
		print("test_mobs OK")
	quit(1 if failed else 0)


func _place(wk, w, c: Vector3i) -> void:
	wk.position = Vector3(c.x + 0.5, w.top_at(c.x, c.z), c.z + 0.5)
	wk.move_to(wk.position)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true

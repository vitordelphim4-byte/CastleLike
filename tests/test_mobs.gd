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
	_check(zombie.state == mob_script.DEAD, "guards killed the zombie (hp %d; soldier %s %s hp %d, archer %s %s)" % [zombie.hp,
		soldier.job_kind, soldier.state, soldier.hp, archer.job_kind, archer.state])
	_check(fought and shot, "soldier fought (%s) and archer shot (%s)" % [fought, shot])
	_check(victim.state != worker_script.DOWNED and victim.hp > 0, "peasant still up: hp %d" % victim.hp)

	# Skeleton warrior: picks the soldier over a closer peasant; the guards bring it down.
	for wk in workers:
		wk.heal()
	_place(victim, w, s + Vector3i(0, 0, -16))
	_place(soldier, w, s + Vector3i(4, 0, -12))
	_place(archer, w, s + Vector3i(-3, 0, -8))
	var skel = mob_script.spawn(main.mobs, w, "skeleton", Vector3(s.x + 0.5, w.top_at(s.x, s.z - 21), s.z - 20.5))
	var first_target = null
	for frame in 6000:
		await process_frame
		if first_target == null and skel.target:
			first_target = skel.target
		if skel.state == mob_script.DEAD:
			break
	_check(first_target == soldier, "skeleton went for the guard first (got %s)" % [first_target.worker_name if first_target else "nobody"])
	_check(skel.state == mob_script.DEAD, "guards killed the skeleton (hp %d)" % skel.hp)

	# Skeleton archer: shoots from range, backs off from the soldier, still dies.
	for wk in workers:
		wk.heal()
	archer.priorities["archer"] = 0  # only the soldier: it has to walk up to it
	_place(soldier, w, s + Vector3i(0, 0, -10))
	var bowman = mob_script.spawn(main.mobs, w, "skeleton_archer", Vector3(s.x + 0.5, w.top_at(s.x, s.z - 20), s.z - 19.5))
	var aimed := false
	var kited := false
	for frame in 6000:
		await process_frame
		aimed = aimed or bowman.state == mob_script.ATTACK
		kited = kited or bowman.state == mob_script.KITE
		if bowman.state == mob_script.DEAD:
			break
	_check(aimed and kited, "skeleton archer shot (%s) and backed off (%s)" % [aimed, kited])
	_check(bowman.state == mob_script.DEAD, "guards killed the skeleton archer (hp %d)" % bowman.hp)

	# Wolves: one alone circles without biting; once a second one joins, the pack attacks.
	for wk in workers:
		wk.heal()
		for k in wk.priorities:
			wk.priorities[k] = 0
	for t in main.get_children():  # no herds: a wolf would hunt a deer instead
		if t is Timer:
			t.stop()
	for a in get_nodes_in_group("animals"):
		a.free()
	_place(victim, w, s + Vector3i(0, 0, -12))
	var wolf =mob_script.spawn(main.mobs, w, "wolf", Vector3(s.x + 0.5, w.top_at(s.x, s.z - 22), s.z - 21.5))
	var circled := false
	for frame in 900:
		await process_frame
		circled = circled or wolf.state == mob_script.CIRCLE
	var bitten := workers.any(func(x) -> bool: return x.hp < x.MAX_HP)
	_check(circled and not bitten, "lone wolf circles (%s) without biting (%s)" % [circled, bitten])
	mob_script.spawn(main.mobs, w, "wolf", wolf.position + Vector3(1, 0, 0))
	var ran := false
	for frame in 3000:
		await process_frame
		ran = ran or wolf.state == mob_script.KITE
		bitten = workers.any(func(x) -> bool: return x.hp < x.MAX_HP)
		if bitten and ran:
			break
	_check(bitten and ran, "pack of two bites (%s) and steps back (%s)" % [bitten, ran])
	wolf.hurt(2, victim)
	await process_frame
	_check(wolf.fled and wolf.state == mob_script.FLEE, "badly hurt wolf runs away")
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

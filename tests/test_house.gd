extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_house.gd
## Ready-made house: one blueprint built whole from several loads of wood; at night tired villagers
## sleep inside (2 beds, hidden), the rest doze outside; in the morning, rested, they come out.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var w: World = game.world
	game.hunger = false
	game.time_of_day = 0.3
	var workers := get_nodes_in_group("workers")
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 1 if k == "build" else 0
		wk.rest = 1.0

	# A flat, free 5x5 spot near the colony.
	var home := Vector3i(game.stockpile.floor())
	var base := Vector3i(0, -1, 0)
	for r in range(4, 30):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				if base.y < 0 and _flat(game, w, home.x + dx, home.z + dz):
					base = Vector3i(home.x + dx, w.top_at(home.x + dx, home.z + dz), home.z + dz)
	_check(base.y >= 0, "flat spot for the house: %s" % base)
	if base.y < 0:
		quit(1)
		return
	game.store("wood", 40)
	var wood_before: int = game.stock.wood
	game.build_item = "small_house"
	game.build_rot = 0
	game.place_blueprints([base] as Array[Vector3i])
	_check(game.blueprints.has(base) and game.blueprints[base].left == 30, "house planned, 30 wood to bring")
	var trips := 0
	var last_left := 30
	for frame in 20000:
		await process_frame
		if game.blueprints.has(base) and game.blueprints[base].left < last_left:
			last_left = game.blueprints[base].left
			trips += 1
		if w.props.has(base):
			break
	_check(w.props.has(base) and w.props[base].item == "small_house", "house built")
	_check(trips >= 3, "built over several trips: %d" % (trips + 1))
	_check(wood_before - game.stock.wood == 30, "cost 30 wood: %d" % (wood_before - game.stock.wood))
	_check(not w.walkable(base + Vector3i(2, 0, 2)), "house blocks walking")

	# Night: 2 sleep inside, the others doze outside.
	game.time_of_day = 0.9
	for wk in workers:
		wk.rest = 0.5
	var inside := 0
	var outside := 0
	for frame in 6000:
		await process_frame
		inside = workers.filter(func(o) -> bool: return o.state == o.SLEEPING and o.bed == base).size()
		outside = workers.filter(func(o) -> bool: return o.state == o.SLEEPING and o.bed == o.NO_SPOT).size()
		if inside + outside == workers.size():
			break
	_check(inside == 2, "2 beds taken: %d" % inside)
	_check(outside == workers.size() - 2, "the rest doze outside: %d" % outside)
	_check(workers.filter(func(o) -> bool: return o.bed == base and not o.visible).size() == 2, "sleepers inside are hidden")
	var gain: float = workers.filter(func(o) -> bool: return o.bed == base)[0].rest
	var gain_out: float = workers.filter(func(o) -> bool: return o.bed == o.NO_SPOT)[0].rest
	for frame in 600:
		await process_frame
	gain = workers.filter(func(o) -> bool: return o.bed == base)[0].rest - gain
	gain_out = workers.filter(func(o) -> bool: return o.bed == o.NO_SPOT)[0].rest - gain_out
	_check(gain > gain_out * 1.5 and gain_out > 0, "bed rests faster: %.3f vs %.3f" % [gain, gain_out])

	# Morning, rested: everyone up and visible, standing outside the house.
	game.time_of_day = 0.3
	for wk in workers:
		wk.rest = 1.0
	for frame in 30:
		await process_frame
	_check(workers.all(func(o) -> bool: return o.visible and o.state != o.SLEEPING), "all awake in the morning")
	_check(workers.all(func(o) -> bool: return not Rect2(base.x, base.z, 5, 5).has_point(Vector2(o.position.x, o.position.z))),
		"nobody stuck inside the walls")
	quit(1 if failed else 0)


func _flat(game, w: World, x: int, z: int) -> bool:
	var y := w.top_at(x, z)
	for i in 5:
		for k in 5:
			var c := Vector3i(x + i, y, z + k)
			if w.top_at(x + i, z + k) != y or not game._free(c) or not game._free(c + Vector3i.UP):
				return false
	# keep the door side clear too
	for i in 5:
		if w.top_at(x + i, z + 5) != y:
			return false
	return true


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failed = true

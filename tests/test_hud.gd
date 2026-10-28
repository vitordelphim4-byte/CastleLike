extends SceneTree
## Run: godot --headless --path . -s tests/test_hud.gd
## Top bar + hint bar (Fase 11b): one roster card per villager, starving shows the "!" badge,
## pixel icons for every resource, hint bar changes with the mode, order panel counts (Fase 11c).

var failed := false


func _initialize() -> void:
	var game := root.get_node("Game")
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var bar = main.get_node("TopBar")
	var workers := root.get_tree().get_nodes_in_group("workers")
	_check(bar.cards.size() == workers.size(), "one card per villager: %d" % bar.cards.size())
	for kind: String in game.RESOURCES:
		_check(UiIcons.resource(kind) != null, "pixel icon for " + kind)

	var w = workers[0]
	w.food = 0.0
	bar._refresh_cards()
	_check(bar.cards[w].badge.visible and bar.cards[w].level == 2, "starving: badge + level 2")
	w.food = 0.2
	bar._refresh_cards()
	_check(not bar.cards[w].badge.visible and bar.cards[w].level == 1, "hungry: no badge, level 1")
	w.food = 1.0
	bar._refresh_cards()
	_check(bar.cards[w].level == 0, "fed: level 0")

	var s := Vector3i(game.stockpile.floor())
	var dig: Dictionary = game.add_order("dig", Rect2i(s.x + 2, s.z, 3, 3))
	_check(game.order_info(dig) == "%d blocos" % dig.cells.size(), "dig info: %s" % game.order_info(dig))
	var home := Vector2i(s.x, s.z)
	var trees: Dictionary = game.add_order("wood", Rect2i(home - Vector2i(32, 32), Vector2i(64, 64)))
	var n := 0
	for r in root.get_tree().get_nodes_in_group("resources"):
		if r.kind == "wood" and r.available() > 0 and trees.area.has_point(Vector2i(floori(r.position.x), floori(r.position.z))):
			n += 1
	_check(n > 0 and game.order_info(trees).begins_with(str(n) + " "), "wood info: %s (%d)" % [game.order_info(trees), n])

	var hud = main.get_node("HUD")
	_check(_text(hud).contains("Trabalho"), "default hints: %s" % _text(hud))
	game.set_building(true)
	_check(_text(hud).contains("CONSTRUIR"), "build hints: %s" % _text(hud))
	game.set_building(false)
	_check(not _text(hud).contains("CONSTRUIR"), "back to default hints")

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _text(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false):
		if not c.is_queued_for_deletion():
			out += c.text + " "
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL: ", what)

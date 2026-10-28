extends SceneTree
## Run: godot --headless --path . -s tests/test_hud.gd
## Top bar + hint bar (Fase 11b): one roster card per villager, starving shows the "!" badge,
## pixel icons for every resource, hint bar changes with the mode, order panel counts (Fase 11c), villager panel and alerts (11d), tooltip and key blink (11e).

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

	# 11d: villager panel follows the selection
	var panel = main.get_node("VillagerPanel")
	bar._focus(workers[1])
	_check(panel.visible and panel.worker == workers[1], "panel opens on select")
	panel.close()
	_check(not panel.visible, "panel closes")
	bar._focus(workers[2])
	_check(panel.visible and panel.worker == workers[2], "panel reopens for another villager")

	# 11d: alerts
	var alerts = main.get_node("Alerts")
	workers[3].food = 0.0
	alerts._tick(0.5)
	_check(alerts.active.has("starving") and alerts.active.starving.level == "danger", "starving alert")
	alerts._tick(60.0)
	_check(alerts.active.has("starving"), "danger stays while it lasts")
	workers[3].food = 1.0
	alerts._tick(0.5)
	_check(not alerts.active.has("starving"), "danger clears when fed")
	var y: int = game.world.top_at(s.x, s.z - 6)
	var bp: Array[Vector3i] = []
	for x in range(s.x - 15, s.x + 16):
		bp.append(Vector3i(x, y + 1, s.z - 6))
	game.place_blueprints(bp)
	alerts._tick(0.5)
	_check(alerts.active.has("material:wood"), "not enough wood alert: %s" % alerts.active.keys())
	alerts._tick(7.0)
	_check(not alerts.active.has("material:wood"), "info alert expires")
	alerts._tick(0.5)
	_check(not alerts.active.has("material:wood"), "does not fire again while it holds")

	# 11e: rich tooltip says what's missing
	var need: int = game.stock["stone"] + 5
	var tip_b = load("res://scripts/tip_button.gd").new().tip("Muro", "X", "teste", {"stone": need})
	root.add_child(tip_b)
	var tip: Control = tip_b._make_custom_tooltip("")
	_check(_text(tip).contains("faltam 5"), "tooltip shortfall: %s" % _text(tip))
	tip.free()
	tip_b.queue_free()

	var hud = main.get_node("HUD")
	_check(_text(hud).contains("Trabalho"), "default hints: %s" % _text(hud))
	var press := InputEventKey.new()
	press.keycode = KEY_T
	press.pressed = true
	hud._input(press)
	var cap: Label = hud.rows.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "T")[0]
	_check(cap.get_theme_stylebox("normal").content_margin_top == 2, "key cap blinks on its shortcut")
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

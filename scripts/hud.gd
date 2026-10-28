extends PanelContainer
## Bottom-center hint bar: what the keys do in the current mode, as parchment key caps + a word each.
## One row per context (mode, then the view cut / x-ray when on). Clicks pass through to the world.

const KEY_CAPS := {KEY_SPACE: "Espaço", KEY_ESCAPE: "Esc", KEY_SHIFT: "Shift", KEY_PAGEUP: "PgUp",
	KEY_PAGEDOWN: "PgDn", KEY_HOME: "Home", KEY_EQUAL: "+", KEY_KP_ADD: "+", KEY_MINUS: "−", KEY_KP_SUBTRACT: "−"}

var rows := VBoxContainer.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.card("normal")
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)
	Game.mode_changed.connect(_refresh)
	_refresh()


# Blink the key cap of a shortcut as it's used (only listens, never eats the key).
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var cap: String = KEY_CAPS.get(e.keycode, OS.get_keycode_string(e.keycode))
	for k: Label in rows.find_children("*", "Label", true, false):
		if k.text == cap and k.has_theme_stylebox_override("normal"):
			UiFx.blink_key(k)


func _refresh() -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	if Game.building:
		if Game.build_tool == "demolish":
			_row("DEMOLIR", [[["Esq"], "arrastar · marcar"], [["Shift"], "desmarca"], [["X"], "construir"],
				[["Esc"], "sair"]])
		elif Game.build_tool == "roof":
			_row("TELHADO", [[["Esq"], "arrastar de canto a canto da parede"], [["R"], "gira a cumeeira"],
				[["X"], "demolir"], [["Esc"], "sair"]])
		else:
			_row("CONSTRUIR " + Pieces.ITEMS[Game.build_item].name.to_upper(), [[["Esq"], "arrastar · planejar"],
				[["Roda", "+", "−"], "altura"], [["R"], "girar"], [["Shift"], "apaga planos"], [["X"], "demolir"],
				[["Esc"], "sair"]])
	elif Game.pending_area:
		var title: String = Game.ORDER_NAMES[Game.pending_area.kind].to_upper()
		if Game.pending_area.order:
			title += " (EDITANDO #%d)" % Game.pending_area.order.id
		var items := [[["Esq"], "arrastar sobre os blocos do chão"]]
		if Game.pending_area.kind == "hunt":
			items.append([["Clique"], "num animal: só ele"])
		if Game.pending_area.kind == "dig":
			items.append([["Roda", "+", "−"], "profundidade: %d camada(s)" % Game.dig_depth])
		items.append([["Dir", "Esc"], "cancelar"])
		_row(title, items)
	else:
		_row("", [[["T"], "Trabalho"], [["B"], "Construção"], [["Espaço"], "Pausa"], [["1", "2", "3"], "Velocidade"]])
	var w := Game.world
	if w and w.cut_y < World.SY:
		_row("CORTE NA CAMADA %d" % w.cut_y, [[["PgUp", "PgDn"], "camada (Shift = 5)"], [["Home"], "desliga"]])
	if w and w.xray_cursor:
		_row("RAIO-X NO CURSOR", [[["V"], "desliga"]])


# title (gold, may be empty) + items: [[keys...], "what it does"].
func _row(title: String, items: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(row)
	if title:
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 12)
		t.add_theme_color_override("font_color", UiTheme.GOLD)
		row.add_child(t)
	for item: Array in items:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pair)
		for key: String in item[0]:
			pair.add_child(UiTheme.key_label(key))
		var l := Label.new()
		l.text = item[1]
		pair.add_child(l)


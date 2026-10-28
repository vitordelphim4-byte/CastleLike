extends PanelContainer
## Top bar: resources (their stockpile pile as icon) and one card per villager showing what they're
## doing right now. Clicking a card selects that villager and moves the camera to them.

var row := HBoxContainer.new()
var res_labels := {}  # resource -> Label
var cards := {}  # Worker -> activity Label
var food_bars := {}  # Worker -> ProgressBar (hunger)
var res_icons := {}  # resource -> TextureRect
const ALWAYS_SHOWN := ["wood", "stone"]  # other resources only show once you have some
var clock := Label.new()
var speed_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.topbar())
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for kind: String in Game.RESOURCES:
		var icon := TextureRect.new()
		var pile := Stockpile.goods_mesh(kind, Game.RESOURCES[kind].per_tile)
		icon.texture = Game.render_icon("res_" + kind, func() -> Node3D:
			var m := MeshInstance3D.new()
			m.mesh = pile
			m.position = Vector3(-0.5, 0, -0.5)
			return m, Vector3(0, 0.3, 0), 1.25)
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Game.RESOURCES[kind].name.capitalize()
		row.add_child(icon)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		l.custom_minimum_size = Vector2(26, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		res_labels[kind] = l
		res_icons[kind] = icon
	row.add_child(VSeparator.new())
	_add_clock()
	row.add_child(VSeparator.new())
	Game.changed.connect(_refresh_resources)
	_refresh_resources()
	_add_cards.call_deferred()  # villagers spawn in Main._ready, after ours
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.ignore_time_scale = true  # keep refreshing while paused
	t.timeout.connect(_refresh_cards)
	add_child(t)


# Clock + pause / 1x / 2x / 3x (also Space and 1/2/3).
func _add_clock() -> void:
	clock.add_theme_font_size_override("font_size", 14)
	clock.custom_minimum_size = Vector2(100, 0)
	clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(clock)
	for s: int in Game.SPEEDS:
		var b := Button.new()
		b.text = "❚❚" if s == 0 else "▶".repeat(s)
		b.tooltip_text = "Pausar (Espaço)" if s == 0 else "Velocidade %dx (tecla %d)" % [s, s]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 0)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(Game.set_speed.bind(s))
		row.add_child(b)
		speed_buttons.append(b)


func _add_cards() -> void:
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		var card := Button.new()
		card.custom_minimum_size = Vector2(128, 34)
		card.focus_mode = Control.FOCUS_NONE
		card.pressed.connect(_focus.bind(w))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(h)
		var face := TextureRect.new()
		face.texture = w.portrait()
		face.custom_minimum_size = Vector2(30, 30)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(face)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", -2)
		h.add_child(v)
		var name_label := Label.new()
		name_label.text = "■ " + w.worker_name
		name_label.add_theme_color_override("font_color", w.color.lightened(0.25))
		name_label.add_theme_font_size_override("font_size", 13)
		v.add_child(name_label)
		var act := Label.new()
		act.add_theme_font_size_override("font_size", 11)
		act.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		act.clip_text = true
		v.add_child(act)
		var bar := ProgressBar.new()  # hunger: full = green, hungry = yellow, starving = red
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", StyleBoxFlat.new())
		v.add_child(bar)
		food_bars[w] = bar
		card.tooltip_text = "Barra: fome (cheia = alimentado)"
		row.add_child(card)
		cards[w] = act
	_refresh_cards()


func _refresh_resources() -> void:
	for kind in res_labels:
		res_labels[kind].text = "∞" if Game.infinite else str(Game.stock[kind])
		var shown: bool = kind in ALWAYS_SHOWN or Game.stock[kind] > 0
		res_labels[kind].visible = shown
		res_icons[kind].visible = shown


func _refresh_cards() -> void:
	clock.text = Game.clock_text()
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(Game.SPEEDS[i] == Game.speed)
	for w: Worker in cards:
		cards[w].text = w.activity()
		var bar: ProgressBar = food_bars[w]
		bar.value = w.food
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
		fill.bg_color = Color(0.4, 0.85, 0.35) if w.food >= Worker.HUNGRY else (Color(0.95, 0.8, 0.25) if w.food > 0 else Color(0.95, 0.25, 0.2))


func _focus(w: Worker) -> void:
	for other: Worker in cards:
		other.selected = other == w
	var rig: Node3D = get_node("../CameraRig")
	rig.position = w.position
	Game.world.cut_to(w.position)
	Game.mode_changed.emit()

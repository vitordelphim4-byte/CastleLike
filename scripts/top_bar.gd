extends PanelContainer
## Top bar: resources (pixel icons) on the left, clock and game speed on the right. Under it, centered,
## the villager roster: one card per villager with what they're doing and how hungry they are
## (compact tiles from COMPACT villagers on; hovering a tile shows its full card). Clicking a card
## selects that villager and moves the camera to them.

const ALWAYS_SHOWN := ["wood", "stone"]  # other resources only show once you have some
const COMPACT := 9  # villagers from which the roster switches to small tiles

var res_labels := {}  # resource -> Label
var res_icons := {}  # resource -> TextureRect
var day_label := UiTheme.num(22)
var time_label := UiTheme.num(22)
var speed_buttons: Array[Button] = []
var roster := HBoxContainer.new()
var cards := {}  # Worker -> card parts (see _card)
var hover_card := {}  # full card shown under a hovered compact tile
var _hovered: Worker


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.topbar())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	for kind: String in Game.RESOURCES:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		row.add_child(pair)
		var icon := TextureRect.new()
		icon.texture = UiIcons.resource(kind)
		if icon.texture == null:  # no pixel icon yet: render its stockpile pile
			icon.texture = _pile_icon(kind)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # 16 px art at 2x
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Game.RESOURCES[kind].name.capitalize()
		pair.add_child(icon)
		var l := UiTheme.num(22)
		l.custom_minimum_size = Vector2(24, 0)
		pair.add_child(l)
		res_labels[kind] = l
		res_icons[kind] = pair
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_add_clock(row)
	Game.changed.connect(_refresh_resources)
	_refresh_resources()
	roster.add_theme_constant_override("separation", 6)
	roster.anchor_left = 0.5
	roster.anchor_right = 0.5
	roster.offset_top = 46
	roster.grow_horizontal = Control.GROW_DIRECTION_BOTH
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child.call_deferred(roster)
	_add_cards.call_deferred()  # villagers spawn in Main._ready, after ours
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.ignore_time_scale = true  # keep refreshing while paused
	t.timeout.connect(_refresh_cards)
	add_child(t)


# Clock in a sunken box + pause / 1x / 2x / 3x (also Space and 1/2/3).
func _add_clock(row: HBoxContainer) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.well())
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	var dia := Label.new()
	dia.text = "DIA"
	dia.add_theme_font_size_override("font_size", 12)
	dia.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	h.add_child(dia)
	h.add_child(day_label)
	var sep := ColorRect.new()
	sep.color = UiTheme.WOOD_BASE
	sep.custom_minimum_size = Vector2(2, 12)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	h.add_child(time_label)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 6)
	row.add_child(speeds)
	for s: int in Game.SPEEDS:
		var b := Button.new()
		b.text = "II" if s == 0 else "%d×" % s
		b.tooltip_text = "Pausar (Espaço)" if s == 0 else "Velocidade %dx (tecla %d)" % [s, s]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 24)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_override("font", UiTheme.NUM)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(Game.set_speed.bind(s))
		speeds.add_child(b)
		speed_buttons.append(b)


func _add_cards() -> void:
	var workers := get_tree().get_nodes_in_group("workers")
	var compact := workers.size() >= COMPACT
	for w: Worker in workers:
		var parts := _card(w, compact)
		parts.card.pressed.connect(_focus.bind(w))
		if compact:
			parts.card.mouse_entered.connect(_hover.bind(w, parts.card))
			parts.card.mouse_exited.connect(_hover.bind(null, null))
		roster.add_child(parts.card)
		cards[w] = parts
	if compact:
		hover_card = _card(null, false)
		hover_card.card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_card.card.visible = false
		get_parent().add_child(hover_card.card)
	_refresh_cards()


# One villager card: full (portrait, name, activity, hunger bar) or a compact tile (portrait + bar).
# Returns its parts so the refresh can fill them; w = null builds an empty one (the hover card).
func _card(w: Worker, compact: bool) -> Dictionary:
	var card := Button.new()
	card.custom_minimum_size = Vector2(34, 40) if compact else Vector2(128, 42)  # mock: 34, too short for 2 lines of text
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("hover", UiTheme.card("hover"))
	var box: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	box.add_theme_constant_override("separation", 2 if compact else 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(26, 26)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(face)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := {"card": card, "face": face, "bar": bar, "level": -1, "selected": null}
	if compact:
		box.add_child(bar)
	else:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(v)
		var name_label := Label.new()
		name_label.add_theme_font_override("font", UiTheme.BOLD)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.clip_text = true
		v.add_child(name_label)
		var act := Label.new()
		act.add_theme_font_size_override("font_size", 12)
		act.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		act.clip_text = true
		v.add_child(act)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
		v.add_child(bar)
		parts.name = name_label
		parts.act = act
	var badge := Label.new()  # starving
	badge.text = "!"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", UiTheme.BOLD)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("#FFF3E0"))
	var red := StyleBoxFlat.new()
	red.bg_color = UiTheme.DANGER
	red.set_border_width_all(2)
	red.border_color = UiTheme.OUTLINE
	badge.add_theme_stylebox_override("normal", red)
	badge.size = Vector2(16, 16)
	badge.position = Vector2(card.custom_minimum_size.x - 10, -6)
	badge.visible = false
	card.add_child(badge)
	parts.badge = badge
	if w:
		_set_worker(parts, w)
	return parts


func _set_worker(parts: Dictionary, w: Worker) -> void:
	parts.face.texture = w.portrait()
	parts.card.tooltip_text = "%s — fome: barra cheia = alimentado" % w.worker_name
	if "name" in parts:
		parts.name.text = w.worker_name
		parts.name.add_theme_color_override("font_color", w.color.lightened(0.25))


func _hover(w: Worker, tile: Control) -> void:
	_hovered = w
	hover_card.card.visible = w != null
	if w:
		_set_worker(hover_card, w)
		hover_card.selected = null
		hover_card.card.position = tile.global_position + Vector2(tile.size.x / 2 - 64, tile.size.y + 8)
		_fill(hover_card, w)


func _refresh_resources() -> void:
	for kind in res_labels:
		res_labels[kind].text = "∞" if Game.infinite else str(Game.stock[kind])
		res_labels[kind].add_theme_font_override("font", UiTheme.FONT if Game.infinite else UiTheme.NUM)  # VT323's ∞ reads as "00"
		res_icons[kind].visible = kind in ALWAYS_SHOWN or Game.stock[kind] > 0


func _refresh_cards() -> void:
	var minutes := int(Game.time_of_day * 24 * 60)
	day_label.text = str(Game.day)
	time_label.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(Game.SPEEDS[i] == Game.speed)
	for w: Worker in cards:
		_fill(cards[w], w)
	if _hovered:
		_fill(hover_card, _hovered)


func _fill(parts: Dictionary, w: Worker) -> void:
	if "act" in parts:
		parts.act.text = w.activity()
	parts.bar.value = w.food
	var level := 0 if w.food >= Worker.HUNGRY else (1 if w.food > 0 else 2)
	if level != parts.level:
		parts.level = level
		parts.bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(level))
		parts.badge.visible = level == 2
	if w.selected != parts.selected:
		parts.selected = w.selected
		var sb := UiTheme.card("selected" if w.selected else "normal")
		for s: String in ["normal", "pressed", "hover_pressed", "disabled"]:
			parts.card.add_theme_stylebox_override(s, sb)


func _focus(w: Worker) -> void:
	for other: Worker in cards:
		other.selected = other == w
	var rig: Node3D = get_node("../CameraRig")
	rig.position = w.position
	Game.world.cut_to(w.position)
	Game.mode_changed.emit()


func _pile_icon(kind: String) -> Texture2D:
	var pile := Stockpile.goods_mesh(kind, Game.RESOURCES[kind].per_tile)
	return Game.render_icon("res_" + kind, func() -> Node3D:
		var m := MeshInstance3D.new()
		m.mesh = pile
		m.position = Vector3(-0.5, 0, -0.5)
		return m, Vector3(0, 0.3, 0), 1.25)


class_name Menu
extends Control
## Title screen (menu.tscn) and in-game pause menu (Esc, in main.tscn) share this script.
## Title: Continue / New game (name + seed) / Load (with delete) / Quit.
## Pause: Resume / Save / Load / Main menu / Quit. In game it also autosaves every AUTOSAVE_SECONDS
## (real time), saves on F5, and saves before leaving to the title or quitting.

const AUTOSAVE_SECONDS := 300.0
const MAIN_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://menu.tscn"

@export var in_game := false

var page := VBoxContainer.new()  # current page's contents
var toast := Label.new()
var confirm := ConfirmationDialog.new()
var _speed_before := 1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55) if in_game else Color(0.1, 0.13, 0.18)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", preload("res://scripts/build_menu.gd").panel_style())
	center.add_child(panel)
	page.custom_minimum_size = Vector2(420, 0)
	page.add_theme_constant_override("separation", 8)
	panel.add_child(page)
	confirm.ok_button_text = "Apagar"
	confirm.cancel_button_text = "Cancelar"
	add_child(confirm)
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 6)
	toast.position = Vector2(20, 860)
	if in_game:
		add_to_group("pause_menu")
		visible = false
		# The toast must show while the menu is hidden: a sibling in the HUD layer.
		get_parent().add_child.call_deferred(toast)
		var t := Timer.new()
		t.wait_time = AUTOSAVE_SECONDS
		t.ignore_time_scale = true
		t.autostart = true
		t.timeout.connect(save.bind("Jogo salvo automaticamente"))
		add_child(t)
	else:
		add_child(toast)
	_main_page()


func _input(e: InputEvent) -> void:
	if not in_game or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_F5:
		save()
		get_viewport().set_input_as_handled()
	elif visible:
		if e.keycode == KEY_ESCAPE:
			close()
		get_viewport().set_input_as_handled()  # no game hotkeys behind the menu


func open() -> void:
	_speed_before = Game.speed
	Game.set_speed(0)
	_main_page()
	visible = true


func close() -> void:
	visible = false
	Game.set_speed(_speed_before)


func save(msg := "Jogo salvo") -> void:
	if Game.infinite:
		_toast("O mapa de debug não é salvo")
		return
	_toast(msg if SaveGame.write(get_parent()) else "ERRO: não foi possível salvar")


# --- Pages ---

func _clear() -> void:
	for c in page.get_children():
		c.queue_free()


func _main_page() -> void:
	_clear()
	_title("Pausado" if in_game else "CastleLike")
	var saves := SaveGame.list()
	if in_game:
		_button("Continuar", close)
		_button("Salvar  (F5)", func() -> void: save(); close())
		_button("Carregar", _load_page)
		_button("Menu principal", func() -> void: save(); _go(TITLE_SCENE))
		_button("Sair do jogo", func() -> void: save(); get_tree().quit())
	else:
		var cont := _button("Continuar", func() -> void: _load(saves[0].path))
		cont.disabled = saves.is_empty()
		if saves:
			cont.tooltip_text = "%s — %s" % [saves[0].name, saves[0].clock]
		_button("Novo jogo", _new_page)
		_button("Carregar", _load_page).disabled = saves.is_empty()
		_button("Sair", get_tree().quit)


func _new_page() -> void:
	_clear()
	_title("Novo jogo")
	page.add_child(_label("Nome do mundo"))
	var name_edit := LineEdit.new()
	name_edit.text = _free_name("Mundo %d" % (SaveGame.list().size() + 1))
	page.add_child(name_edit)
	page.add_child(_label("Semente (vazio = aleatória)"))
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "aleatória"
	page.add_child(seed_edit)
	_button("Criar mundo", func() -> void:
		var text := seed_edit.text.strip_edges()
		Game.start_seed = text.to_int() if text.is_valid_int() else (hash(text) if text else 0)
		Game.world_name = _free_name(name_edit.text.strip_edges() if name_edit.text.strip_edges() else "Mundo")
		_go(MAIN_SCENE))
	_button("Voltar", _main_page)


func _load_page() -> void:
	_clear()
	_title("Carregar")
	var saves := SaveGame.list()
	if saves.is_empty():
		page.add_child(_label("Nenhum jogo salvo."))
	for s in saves:
		var row := HBoxContainer.new()
		var d := Time.get_datetime_dict_from_unix_time(s.time + Time.get_time_zone_from_system().bias * 60)
		var info := _label("%s\nDia %d · %s · salvo em %02d/%02d %02d:%02d" % [s.name, s.day,
			s.clock.get_slice("· ", 1), d.day, d.month, d.hour, d.minute])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		row.add_child(_small_button("Carregar", _load.bind(s.path)))
		row.add_child(_small_button("Apagar", _ask_delete.bind(s)))
		page.add_child(row)
	_button("Voltar", _main_page)


func _ask_delete(s: Dictionary) -> void:
	confirm.dialog_text = "Apagar o mundo \"%s\"?\nIsso não pode ser desfeito." % s.name
	for c in confirm.confirmed.get_connections():
		confirm.confirmed.disconnect(c.callable)
	confirm.confirmed.connect(func() -> void: SaveGame.delete(s.path); _load_page())
	confirm.popup_centered()


func _load(path: String) -> void:
	var data := SaveGame.read(path)
	if data.is_empty():
		_toast("ERRO: save corrompido")
		return
	if in_game:
		save()
	for s in SaveGame.list():
		if s.path == path:
			Game.world_name = s.name
	Game.pending_load = data
	_go(MAIN_SCENE)


func _go(scene: String) -> void:
	Game.set_speed(1)
	get_tree().change_scene_to_file(scene)


# --- Helpers ---

# name, or "name (2)", "name (3)"... so a new world never overwrites an existing save.
func _free_name(base: String) -> String:
	var n := base
	var i := 2
	while FileAccess.file_exists(SaveGame.path_for(n)):
		n = "%s (%d)" % [base, i]
		i += 1
	return n


func _toast(msg: String) -> void:
	toast.text = msg
	toast.modulate.a = 1.0
	var tw := toast.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(2.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)


func _title(text: String) -> void:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(l)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	page.add_child(b)
	return b


func _small_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b

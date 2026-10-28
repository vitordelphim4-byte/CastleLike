extends PanelContainer
## Layer-cut slider on the right edge (Phase 9): drag, click or scroll it to pick the highest layer
## shown, one block per step. The top notch shows everything. Its range follows the natural ground
## under the camera; the label says how far the cut is above (+) or below (-) that ground.

const BELOW := 80  # layers under the camera's ground the slider reaches (down to the bedrock)
const ABOVE := 24  # layers above it; one more notch on top = no cut

var slider := VSlider.new()
var label := Label.new()
var _ground := -1
var _syncing := false  # changing the range clamps the value and emits value_changed


func _ready() -> void:
	UiDrag.attach(self)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Altura"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(52, 0)
	box.add_child(label)
	slider.custom_minimum_size = Vector2(0, 300)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.step = 1
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = "Esconde tudo acima da altura escolhida (PageUp / PageDown, Home mostra tudo)"
	slider.value_changed.connect(_on_value)
	box.add_child(slider)
	_place.call_deferred()


# Top-right corner under the top bar, once the size is known.
func _place() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	position.y = 56


func _process(_delta: float) -> void:
	var w := Game.world
	if w == null:
		return
	if not w.cut_changed.is_connected(_sync):
		w.cut_changed.connect(_sync)
	var g := w.ground_at(floori(w.focus.x), floori(w.focus.z))
	if g != _ground:
		_ground = g
		_sync()


# Range around the camera's ground, handle on the current cut (no signal: that would set it back).
func _sync() -> void:
	var w := Game.world
	_syncing = true
	slider.min_value = maxi(1, _ground - BELOW)
	slider.max_value = _ground + ABOVE + 1
	var off := w.cut_y >= World.SY
	slider.set_value_no_signal(slider.max_value if off else clampi(w.cut_y, int(slider.min_value), int(slider.max_value) - 1))
	_syncing = false
	var d := w.cut_y - _ground
	label.text = "Tudo" if off else ("Chão" if d == 0 else "%+d" % d)


func _on_value(v: float) -> void:
	if _syncing:
		return
	Game.world.set_cut(World.SY if v >= slider.max_value else int(v))
	Game.mode_changed.emit()

class_name UiFx
## Small UI motion from the HUD spec, always in whole pixels: panels slide in, buttons shake on an
## error, key caps blink when their shortcut is used.

const SLIDE := 16.0  # px
const SLIDE_TIME := 0.12


## Slide a panel that just became visible in from `from` (e.g. Vector2.LEFT = from the left edge).
static func slide_in(c: Control, from: Vector2) -> void:
	var home := c.position
	var t := c.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.set_ignore_time_scale(true)
	t.tween_method(func(k: float) -> void: c.position = (home + from * SLIDE * (1.0 - k)).round(), 0.0, 1.0, SLIDE_TIME)


## Error: shake ±2 px three times (150 ms) with a red ring for 300 ms.
static func shake(c: Control) -> void:
	var home := c.position
	var t := c.create_tween()
	t.set_ignore_time_scale(true)
	for i in 3:
		t.tween_property(c, "position:x", home.x + 2, 0.025)
		t.tween_property(c, "position:x", home.x - 2, 0.025)
	t.tween_property(c, "position:x", home.x, 0.0)
	var ring := ReferenceRect.new()
	ring.border_color = UiTheme.DANGER
	ring.border_width = 2
	ring.editor_only = false
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(ring)
	c.get_tree().create_timer(0.3, true, false, true).timeout.connect(ring.queue_free)


## Key cap pressed look for 100 ms.
static func blink_key(k: Label) -> void:
	k.add_theme_stylebox_override("normal", UiTheme.keycap_pressed())
	k.get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(k):
			k.add_theme_stylebox_override("normal", UiTheme.keycap()))

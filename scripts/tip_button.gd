class_name TipButton
extends Button
## Button with a rich parchment tooltip (HUD mock): name + shortcut key cap, a short description,
## and the cost with its icon; when the stockpile can't pay, a red "faltam N" (in ink, not red text).

var tip_title := ""
var tip_key := ""
var tip_desc := ""
var tip_cost := {}  # resource -> amount


## Sets the tooltip parts (tooltip_text must be non-empty for Godot to ask for a tooltip).
func tip(title: String, key := "", desc := "", cost := {}) -> TipButton:
	tip_title = title
	tip_key = key
	tip_desc = desc
	tip_cost = cost
	tooltip_text = title
	return self


func _make_custom_tooltip(_for_text: String) -> Object:
	var game = get_node("/root/Game")  # not the Game global: UiTheme uses this class before autoloads exist
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size.x = 200
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := _ink(tip_title, 16)
	title.add_theme_font_override("font", UiTheme.BOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if tip_key:
		head.add_child(UiTheme.key_label(tip_key))
	if tip_desc:
		var d := _ink(tip_desc, 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		d.custom_minimum_size.x = 240
		v.add_child(d)
	for kind: String in tip_cost:
		var line := ColorRect.new()
		line.color = UiTheme.PARCH_DARK
		line.custom_minimum_size.y = 2
		v.add_child(line)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var icon := TextureRect.new()
		icon.texture = UiIcons.resource(kind)
		row.add_child(icon)
		var n := UiTheme.num(18, UiTheme.INK)
		n.text = str(tip_cost[kind])
		row.add_child(n)
		var have: int = game.stock[kind]
		row.add_child(_ink("%s · você tem %s" % [game.RESOURCES[kind].name, "∞" if game.infinite else str(have)], 12))
		if have < tip_cost[kind] and not game.infinite:
			var stop := TextureRect.new()
			stop.texture = UiIcons.x2(UiIcons.glyph("stop"))
			stop.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			row.add_child(stop)
			var short := _ink("faltam %d" % (tip_cost[kind] - have), 12)
			short.add_theme_font_override("font", UiTheme.BOLD)
			row.add_child(short)
	return v


static func _ink(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiTheme.INK)
	return l

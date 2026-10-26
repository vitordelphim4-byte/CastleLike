extends Control
## World generation debugger: top-down map of any seed, layer by layer.
## Run: run_worldgen_debug.bat [seed]  (or godot --path . res://worldgen_debug.tscn -- [seed])
## Keys: 1-7 layer, WASD / arrows pan, +/- zoom, N new seed, R back to spawn, Enter play this seed.
## Mouse: hover shows every value WorldGen computes at that column.

const SIZE := 320  # map pixels per side (drawn 2x)
const LAYERS := ["Bioma", "Altura", "Temperatura", "Umidade", "Continente", "Montanhas", "Rios"]
const BIOME_COLORS := {
	"water": Color(0.2, 0.4, 0.8), "beach": Color(0.9, 0.85, 0.6), "plains": Color(0.55, 0.78, 0.35),
	"forest": Color(0.15, 0.5, 0.18), "taiga": Color(0.2, 0.4, 0.35), "tundra": Color(0.85, 0.9, 0.95),
	"desert": Color(0.93, 0.8, 0.45), "mountain": Color(0.5, 0.5, 0.52), "snow": Color(1, 1, 1),
}
const HELP := """1-7 camada: Bioma, Altura, Temperatura, Umidade, Continente, Montanhas, Rios
WASD / setas: mover    + / -: zoom
N: novo seed    R: voltar ao spawn
Enter: jogar este seed

Vermelho = spawn, amarelo = origem.
Camadas 5-7 mostram o ruído sem domain warp (aproximado)."""

var gen: WorldGen
var center := Vector2.ZERO  # world (x, z) at the middle of the map
var zoom := 4.0  # blocks per pixel
var layer := 0
var tex := TextureRect.new()
var info := Label.new()
var seed_edit := LineEdit.new()


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	tex.position = Vector2(16, 56)
	tex.size = Vector2(SIZE * 2, SIZE * 2)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(tex)
	seed_edit.position = Vector2(16, 12)
	seed_edit.size = Vector2(220, 32)
	seed_edit.placeholder_text = "seed (Enter aplica)"
	seed_edit.text_submitted.connect(func(t: String) -> void:
		_new_world(t.to_int() if t.is_valid_int() else hash(t))
		seed_edit.release_focus())
	add_child(seed_edit)
	info.position = Vector2(SIZE * 2 + 32, 56)
	info.add_theme_font_size_override("font_size", 15)
	add_child(info)
	var help := Label.new()
	help.position = Vector2(SIZE * 2 + 32, 330)
	help.size.x = 420
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.text = HELP
	add_child(help)
	var args := OS.get_cmdline_user_args()
	_new_world(int(args[0]) if args.size() > 0 and args[0].is_valid_int() else randi())


func _new_world(s: int) -> void:
	var t := Time.get_ticks_usec()
	gen = WorldGen.new(s)
	center = Vector2(gen.spawn)
	seed_edit.text = str(s)
	print("seed %d: spawn %s found in %.1f ms" % [s, gen.spawn, (Time.get_ticks_usec() - t) / 1000.0])
	_redraw()


func _redraw() -> void:
	var t := Time.get_ticks_usec()
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for py in SIZE:
		for px in SIZE:
			var w := _to_world(Vector2(px, py))
			img.set_pixel(px, py, _color(w.x, w.y))
	# Spawn (red) and origin (yellow) markers.
	for m: Array in [[Vector2(gen.spawn), Color.RED], [Vector2.ZERO, Color.YELLOW]]:
		var p: Vector2 = (m[0] - center) / zoom + Vector2.ONE * SIZE / 2
		for d in range(-4, 5):
			for q: Vector2i in [Vector2i(int(p.x) + d, int(p.y)), Vector2i(int(p.x), int(p.y) + d)]:
				if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE:
					img.set_pixelv(q, m[1])
	tex.texture = ImageTexture.create_from_image(img)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	get_window().title = "Gerador de mundo — seed %d — %s — %.1f blocos/px — mapa em %.0f ms (%.1f µs/coluna)" % [
		gen.world_seed, LAYERS[layer], zoom, ms, ms * 1000.0 / (SIZE * SIZE)]


func _to_world(px: Vector2) -> Vector2i:
	return Vector2i(((px - Vector2.ONE * SIZE / 2) * zoom + center).floor())


func _color(x: int, z: int) -> Color:
	var h := gen.height(x, z)
	match layer:
		0:
			var c: Color = BIOME_COLORS.get(gen.biome(x, z, int(h)), Color.MAGENTA)  # magenta = biome without a color here
			return c.darkened(clampf((40.0 - h) * 0.01, -0.3, 0.3))  # a little relief
		1:
			if h < WorldGen.WATER_LEVEL:
				return Color(0.1, 0.2, 0.5).lerp(Color(0.3, 0.5, 0.9), h / WorldGen.WATER_LEVEL)
			var k := clampf((h - WorldGen.WATER_LEVEL) / 90.0, 0, 1)
			return Color.from_hsv(0.33 - k * 0.33, 0.6, 0.4 + k * 0.6)
		2: return _signed(gen.temperature.get_noise_2d(x, z), Color(0.2, 0.4, 1), Color(1, 0.3, 0.1))
		3: return _signed(gen.moisture.get_noise_2d(x, z), Color(0.8, 0.6, 0.3), Color(0.1, 0.5, 0.9))
		4: return _signed(gen.continent.get_noise_2d(x, z), Color(0.1, 0.2, 0.6), Color(0.6, 0.5, 0.3))
		5: return Color.BLACK.lerp(Color.WHITE, gen._mountains(x, z, gen.continent.get_noise_2d(x, z)))
		_: return Color.BLACK.lerp(Color(0.3, 0.6, 1), 1.0 - smoothstep(0.02, 0.07, absf(gen.rivers.get_noise_2d(x, z))))


func _signed(v: float, neg: Color, pos: Color) -> Color:
	return Color(0.5, 0.5, 0.5).lerp(pos if v > 0 else neg, clampf(absf(v) * 2.0, 0, 1))


func _process(_delta: float) -> void:
	var m := tex.get_local_mouse_position() / 2
	if not Rect2(Vector2.ZERO, Vector2.ONE * SIZE).has_point(m):
		return
	var w := _to_world(m)
	var h := gen.height(w.x, w.y)
	var c := gen.continent.get_noise_2d(w.x, w.y)
	info.text = "x %d   z %d\naltura %.1f (topo %d)\nbioma %s\ntemperatura %.2f\numidade %.2f\ncontinente %.2f\nmontanha %.2f\nrio %.3f\ndist. do spawn %d" % [
		w.x, w.y, h, int(h), gen.biome(w.x, w.y, int(h)), gen.temperature.get_noise_2d(w.x, w.y),
		gen.moisture.get_noise_2d(w.x, w.y), c, gen._mountains(w.x, w.y, c), gen.rivers.get_noise_2d(w.x, w.y),
		Vector2(w).distance_to(Vector2(gen.spawn))]


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed) or seed_edit.has_focus():
		return
	var step := zoom * SIZE / 4
	match e.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7: layer = e.keycode - KEY_1
		KEY_W, KEY_UP: center.y -= step
		KEY_S, KEY_DOWN: center.y += step
		KEY_A, KEY_LEFT: center.x -= step
		KEY_D, KEY_RIGHT: center.x += step
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom = maxf(0.5, zoom / 2)
		KEY_MINUS, KEY_KP_SUBTRACT: zoom = minf(32.0, zoom * 2)
		KEY_R: center = Vector2(gen.spawn)
		KEY_N: _new_world(randi())
		KEY_ENTER, KEY_KP_ENTER:
			Game.start_seed = gen.world_seed
			get_tree().change_scene_to_file("res://main.tscn")
			return
		_: return
	_redraw()

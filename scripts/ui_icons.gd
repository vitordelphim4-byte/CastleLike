class_name UiIcons
## Pixel-art icons from the HUD mock (HUD.dc.html), drawn in code: one character per pixel, "." empty.
## 16x16 art; shown at 2x (32 px) with nearest filtering.

const PAL := {
	"o": "#140C07", "a": "#B07B45", "b": "#8F5E33", "c": "#6B4325", "e": "#D9B07A",
	"S": "#EEF0F4", "s": "#C7CAD0", "t": "#8A8E96", "u": "#4A4D55", "W": "#F3F4F7", "l": "#E89A5A",
	"r": "#B5562F", "K": "#5A5A68", "k": "#3A3A44", "w": "#9A9AAA", "j": "#24242A",
	"P": "#E86A5A", "R": "#C8402F", "D": "#7A1F17", "g": "#6FAE3E", "G": "#3E6B22",
	"Y": "#F6E08A", "y": "#E8C25A", "h": "#B8902E", "O": "#E0782E", "Q": "#F2A65A", "q": "#A84E1A",
	"M": "#E88080", "m": "#C24A4A", "n": "#7A2A2A", "B": "#C9B48C", "X": "#F3E6C8",
}

const RESOURCES := {
	"wood": ["", "", "", "....oooooooooo..", "...oeeoaaaaaaao.", "..oeaaeoabaaabo.", "..oeacaeobbbbbo.",
		"..oeaaaeobbcbbo.", "..oeacaeobbbbbo.", "..oeaaeocbcccbo.", "...oeeoccccccco.", "....oooooooooo.."],
	"stone": ["", "", "......oooo......", "....ooSsstoo....", "...oSsssttttoo..", "..oSssstttttuto.",
		"..oSsstttttuuto.", "..ostttttttuuuo.", "..otttttuttuuuo.", "...ottttuuuuuo..", "....oouuuuuoo...",
		"......ooooo....."],
	"iron_ore": ["", "", "......oooo......", "....ooSsstoo....", "...oSssstlrtoo..", "..oSslrtttttuto.",
		"..oSsstttlruuto.", "..ostlrttttuuuo.", "..otttttulruuuo.", "...ottttuuuuuo..", "....oouuuuuoo...",
		"......ooooo....."],
	"charcoal": ["", "", "......oooo......", "....oowKKkoo....", "...owKKKkkkkoo..", "..owKKKkkkkkjko.",
		"..owKKkkkkkjjko.", "..oKkkkkkkkjjjo.", "..okkkkkjkkjjjo.", "...okkkkjjjjjo..", "....oojjjjjoo...",
		"......ooooo....."],
	"iron": ["", "", "", "", "", "....oooooooooo..", "...oWWWWWWWWso..", "..oWsssssssssto.", ".ooooooooooooto.",
		".osssssssssssuo.", ".otttttttttttuo.", ".ouuuuuuuuuuuuo.", ".oooooooooooooo."],
	"berries": ["", "", ".......oo.......", "......oco.oo....", "......oc.ogGo...", "...oooocoooo....",
		"..oPPRRcRRRRo...", ".oPWPRRRRRRRRo..", ".oPPRRRRRRRRRo..", ".oPRRRRRRRRRDo..", ".oRRRRRRRRRRDo..",
		".oRRRRRRRRRDDo..", "..oRRRRRRRDDo...", "...oRRoooRDo....", "....oo...oo....."],
	"wheat": ["", "...oo..oo..oo...", "..oYyooYyooYyo..", "..oyhooyhooyho..", "..oYyooYyooYyo..",
		"..oyhooyhooyho..", "...oho.oho.oho..", "....ohoohooho...", ".....ohhhhho....", "....occcccco....",
		".....ohhhho.....", "....ohohhoho....", "...oho.oo.oho...", "...oo......oo..."],
	"carrot": ["", "..........o.o...", ".........ogogo..", "........ogGgGo..", ".......oQoGgo...",
		"......oQOOoo....", ".....oQOOOqo....", "....oQOOOqo.....", "...oQOOOqo......", "..oQOOqqo.......",
		"..oOOqqo........", ".oOqqo..........", ".oqo............", ".oo............."],
	"meat": ["", "", "........oooo....", "......ooMMmmo...", ".....oMMmmmmno..", "....oMmmmmmmnno.",
		"....oMmmmmmmmno.", "....ommmmmmmnno.", ".....ommmmmnno..", "....oXonnnnoo...", "...oXXBoooo.....",
		".ooXXBo.........", "oXXoBo..........", "oXBBo...........", ".ooo............"],
}

static var _cache := {}


## Texture for a resource kind (Game.RESOURCES key); null if it has no pixel icon yet.
static func resource(kind: String) -> Texture2D:
	return _paint("res_" + kind, RESOURCES.get(kind, []), PAL)


static func _paint(key: String, rows: Array, pal: Dictionary) -> Texture2D:
	if rows.is_empty():
		return null
	if key not in _cache:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] in pal:
					img.set_pixel(x, y, Color(pal[row[x]]))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


# Order / zone icons (mock ORDER_ICONS): a 10x10 glyph on a 14x14 colored plate with outline and bevel.
# Each kind has its own plate color AND glyph, so it reads without color.
const OPAL := {"o": "#140C07", "i": "#E4E6EA", "I": "#8A8E96", "w": "#8F5E33", "a": "#C99560", "x": "#F3E6C8",
	"p": "#5A1F3A", "P": "#9A3A6A", "g": "#4E8A2A", "G": "#B8E07A", "c": "#4A2E1A"}
const ORDERS := {
	"wood": ["#6E9B3A", ["..oo......", ".oiio.....", "oiiiio....", "oiiIowo...", ".ooIowwo..", "..oo.owwo.",
		".....owwo.", "......owwo", ".......owo", "........oo"]],
	"gather": ["#D0637A", ["..oo..oo..", ".oPPooPPo.", ".oPpooPpo.", "..oooooo..", ".oaaaaaao.", ".owawawao.",
		".oaaaaaao.", ".owawawao.", "..oaaaao..", "...oooo..."]],
	"hunt": ["#C4672E", ["......oooo", "......oiio", ".....oiiio", "....oxoiio", "...oxo.oo.", "..oxo.....",
		".oxo......", "oaxo......", "oaao......", "ooo......."]],
	"dig": ["#7E8CC4", [".oooooooo.", "oiiiiiiiio", "oIo.oo.oIo", "oo..ow..oo", "....ow....", "....ow....",
		"....ow....", "....ow....", "....ow....", "....oo...."]],
	"stock": ["#D9B44A", ["oooooooooo", "oaowwwwoao", "oawowwowao", "oawwoowwao", "oawwoowwao", "oawowwowao",
		"oaowwwwoao", "oaaaaaaaao", "oaaaaaaaao", "oooooooooo"]],
	"farm": ["#4FA39A", ["...oo.oo..", "..oGgoGgo.", "..oggoggo.", "...oogoo..", "....ogo...", "....ogo...",
		"oooooooooo", "owcwcwcwco", "occcccccco", "oooooooooo"]],
}

# Small glyphs (X = light text color, R = red, A = gold, o = outline).
const GPAL := {"o": "#140C07", "X": "#F3E6C8", "R": "#C8402F", "A": "#E8B04A", "W": "#6B4325", "w": "#B07B45",
	"G": "#6FAE3E", "Y": "#E5A23A"}
const GLYPHS := {
	# 6x6 row actions
	"pause": ["XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX"],
	"resume": ["XX....", "XXXX..", "XXXXXX", "XXXXXX", "XXXX..", "XX...."],
	"edit": ["....XX", "...XXX", "..XXX.", ".XXX..", "XXX...", "XX...."],
	"close": ["XX..XX", ".XXXX.", "..XX..", "..XX..", ".XXXX.", "XX..XX"],
	# 10x10 build tools
	"build": ["..........", ".oooooooo.", ".owwwwwwo.", ".owWWWWWo.", ".owWWWWWo.", ".owWWWWWo.", ".owWWWWWo.",
		".owWWWWWo.", ".oooooooo.", ".........."],
	"demolish": ["oo......oo", "oRo....oRo", ".oRo..oRo.", "..oRooRo..", "...oRRo...", "...oRRo...",
		"..oRooRo..", ".oRo..oRo.", "oRo....oRo", "oo......oo"],
	"rotate": ["...oooo...", "..oXXXXo..", ".oXooooXo.", "oXo....oXo", "oXo..oXXXX", "oXo...oXXo",
		"oXo....oXo", ".oXo......", "..oXXXo...", "...ooo...."],
	# 7x7 status: ok square / warning triangle / stopped diamond
	"ok": ["ooooooo", "oGGGGGo", "oGGGGGo", "oGGGGGo", "oGGGGGo", "oGGGGGo", "ooooooo"],
	"warn": ["...o...", "..oYo..", "..oYo..", ".oYYYo.", ".oYYYo.", "oYYYYYo", "ooooooo"],
	"stop": ["...o...", "..oRo..", ".oRRRo.", "oRRRRRo", ".oRRRo.", "..oRo..", "...o..."],
}


## 14x14 order/zone icon (shown at 2x = 28 px). kind: Game.ORDER_NAMES key.
static func order(kind: String) -> Texture2D:
	var key := "ord_" + kind
	if key not in _cache:
		var plate := Color(ORDERS[kind][0])
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color(OPAL.o))
		img.fill_rect(Rect2i(1, 1, 12, 12), plate.lerp(Color.WHITE, 0.28))
		img.fill_rect(Rect2i(2, 2, 11, 11), plate.darkened(0.25))
		img.fill_rect(Rect2i(2, 2, 10, 10), plate)
		var rows: Array = ORDERS[kind][1]
		for y in rows.size():
			for x in rows[y].length():
				if rows[y][x] in OPAL:
					img.set_pixel(x + 2, y + 2, Color(OPAL[rows[y][x]]))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Small UI glyph (see GLYPHS): row actions, build tools, status.
static func glyph(name: String) -> Texture2D:
	var rows: Array = GLYPHS[name]
	var key := "gl_" + name
	if key not in _cache:
		var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				if rows[y][x] in GPAL:
					img.set_pixel(x, y, Color(GPAL[rows[y][x]]))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Work type icon for the work tab header (Game.WORKS key): reuses resource and tool art.
static func job(work: String) -> Texture2D:
	match work:
		"build": return glyph("build")
		"dig": return resource("iron_ore")
		"farm": return resource("wheat")
		"gather": return resource("berries")
		"hunt": return resource("meat")
		"craft": return resource("iron")
	return resource(work)


## Same texture at 2x (nearest), for controls that draw icons at native size (Button, TextureRect).
static func x2(t: Texture2D) -> Texture2D:
	var key := "x2_%d" % t.get_instance_id()
	if key not in _cache:
		var img := t.get_image()
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

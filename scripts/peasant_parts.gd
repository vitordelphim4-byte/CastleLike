class_name PeasantParts
## Voxel body parts of a Warcraft 3-style peasant, built once per look and shared.
## A look ({female, skin, hair, shirt, vest}) varies body parts; tools and cargo ignore it.
## Each mesh's origin is its joint (hip, shoulder, neck...). Front faces -Z.

const S := 0.075  # voxel size in world units

const SKIN := Color(0.95, 0.74, 0.58)
const HAIR := Color(0.42, 0.26, 0.12)
const SHIRT := Color(0.82, 0.68, 0.45)
const VEST := Color(0.5, 0.32, 0.17)
const BELT := Color(0.28, 0.18, 0.1)
const GOLD := Color(0.9, 0.75, 0.25)
const PANTS := Color(0.42, 0.4, 0.33)
const BOOTS := Color(0.3, 0.2, 0.12)
const WOOD := Color(0.5, 0.33, 0.18)
const IRON := Color(0.62, 0.64, 0.68)

const DEFAULT_LOOK := {"female": false, "skin": SKIN, "hair": HAIR, "shirt": SHIRT, "vest": VEST}

static var _cache := {}


static func mesh(part: String, look := {}) -> ArrayMesh:
	var key := part + str(look)
	if not _cache.has(key):
		var l := DEFAULT_LOOK.merged(look, true)
		match part:
			"leg": _cache[key] = leg()
			"torso": _cache[key] = torso(l)
			"skirt": _cache[key] = skirt(l)
			"scarf": _cache[key] = scarf()
			"head": _cache[key] = head(l)
			"arm": _cache[key] = arm(l)
			"axe": _cache[key] = axe()
			"pickaxe": _cache[key] = pickaxe()
			"hammer": _cache[key] = hammer()
			"cargo_wood": _cache[key] = cargo_wood()
			"cargo_stone": _cache[key] = cargo_stone()
			"cargo_iron_ore": _cache[key] = cargo_lump(Color(0.5, 0.5, 0.52), Color(0.78, 0.45, 0.26))
			"cargo_charcoal": _cache[key] = cargo_lump(Color(0.13, 0.13, 0.14), Color(0.26, 0.25, 0.25))
			"cargo_iron": _cache[key] = cargo_bar()
			"cargo_berries": _cache[key] = cargo_basket()
			"cargo_carrot": _cache[key] = cargo_lump(Color(0.95, 0.5, 0.12), Color(0.3, 0.6, 0.2))
			"cargo_wheat": _cache[key] = cargo_sheaf()
			"cargo_meat": _cache[key] = cargo_lump(Color(0.72, 0.22, 0.2), Color(0.95, 0.85, 0.8))
			"bow": _cache[key] = bow()
	return _cache[key]


static func leg() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 2, 0), Vector3i(3, 5, 3), PANTS)
	VoxelMesh.fill(v, Vector3i(0, 0, -1), Vector3i(3, 2, 4), BOOTS)  # boot toe sticks out front
	return VoxelMesh.build(v, S, Vector3(-1.5, -7, -1.5))


# Men: shirt + open vest. Women: shirt + laced bodice (the skirt is a separate part at the hip).
static func torso(l: Dictionary) -> ArrayMesh:
	var v := {}
	var shirt: Color = l.shirt
	var vest: Color = l.vest
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 8, 5), shirt)
	VoxelMesh.fill(v, Vector3i(0, 2, 4), Vector3i(8, 6, 1), vest)  # back
	VoxelMesh.fill(v, Vector3i(0, 2, 0), Vector3i(1, 6, 5), vest)  # sides
	VoxelMesh.fill(v, Vector3i(7, 2, 0), Vector3i(1, 6, 5), vest)
	if l.female:
		VoxelMesh.fill(v, Vector3i(1, 2, 0), Vector3i(6, 4, 1), vest)  # bodice
		for y in [2, 4]:
			v[Vector3i(3, y, -1)] = shirt  # lacing
			v[Vector3i(4, y + 1, -1)] = shirt
	else:
		VoxelMesh.fill(v, Vector3i(1, 2, 0), Vector3i(2, 6, 1), vest)  # open vest front
		VoxelMesh.fill(v, Vector3i(5, 2, 0), Vector3i(2, 6, 1), vest)
		VoxelMesh.fill(v, Vector3i(6, 0, -1), Vector3i(2, 2, 1), vest.darkened(0.2))  # pouch
	VoxelMesh.fill(v, Vector3i(0, 1, 0), Vector3i(8, 1, 5), BELT)
	VoxelMesh.fill(v, Vector3i(3, 1, -1), Vector3i(2, 1, 1), GOLD)  # buckle
	return VoxelMesh.build(v, S, Vector3(-4, 0, -2.5))


# Hangs from the hip over the upper legs, flaring a little toward the hem.
static func skirt(l: Dictionary) -> ArrayMesh:
	var v := {}
	var col: Color = l.vest.lightened(0.15)
	VoxelMesh.fill(v, Vector3i(0, -3, 0), Vector3i(8, 3, 5), col)
	VoxelMesh.fill(v, Vector3i(-1, -5, -1), Vector3i(10, 2, 7), col)
	VoxelMesh.fill(v, Vector3i(-1, -5, -1), Vector3i(10, 1, 7), col.darkened(0.2))  # hem
	return VoxelMesh.build(v, S, Vector3(-4, 0, -2.5))


# Neckerchief, white so the material can tint it with the task-group color.
static func scarf() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 1, 5), Color.WHITE)
	VoxelMesh.fill(v, Vector3i(3, -2, -1), Vector3i(2, 3, 1), Color.WHITE)  # knot hanging in front
	return VoxelMesh.build(v, S, Vector3(-4, 0, -2.5), 0.03)


# Men: bowl cut + stubble. Women: long hair down the back and sides + a braid, no stubble.
static func head(l: Dictionary) -> ArrayMesh:
	var v := {}
	var skin: Color = l.skin
	var hair: Color = l.hair
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(7, 7, 7), skin)
	VoxelMesh.fill(v, Vector3i(0, 6, 0), Vector3i(7, 1, 7), hair)  # top
	if l.female:
		VoxelMesh.fill(v, Vector3i(0, 0, 6), Vector3i(7, 7, 1), hair)  # back, to the neck
		VoxelMesh.fill(v, Vector3i(0, 1, 2), Vector3i(1, 6, 5), hair)  # sides past the ears
		VoxelMesh.fill(v, Vector3i(6, 1, 2), Vector3i(1, 6, 5), hair)
		VoxelMesh.fill(v, Vector3i(0, 5, 0), Vector3i(3, 1, 1), hair)  # parted fringe
		VoxelMesh.fill(v, Vector3i(4, 5, 0), Vector3i(3, 1, 1), hair)
		VoxelMesh.fill(v, Vector3i(3, -3, 7), Vector3i(1, 6, 1), hair)  # braid
		v[Vector3i(3, 1, 0)] = skin.darkened(0.25)  # lips
	else:
		var stubble := skin.lerp(hair, 0.45)
		VoxelMesh.fill(v, Vector3i(0, 2, 6), Vector3i(7, 5, 1), hair)  # bowl cut
		VoxelMesh.fill(v, Vector3i(0, 4, 2), Vector3i(1, 3, 5), hair)
		VoxelMesh.fill(v, Vector3i(6, 4, 2), Vector3i(1, 3, 5), hair)
		VoxelMesh.fill(v, Vector3i(0, 5, 0), Vector3i(7, 1, 1), hair)  # fringe
		VoxelMesh.fill(v, Vector3i(1, 0, 0), Vector3i(5, 2, 1), stubble)
		VoxelMesh.fill(v, Vector3i(0, 0, 1), Vector3i(1, 2, 3), stubble)
		VoxelMesh.fill(v, Vector3i(6, 0, 1), Vector3i(1, 2, 3), stubble)
		v[Vector3i(-1, 3, 3)] = skin  # ears (hidden under long hair on women)
		v[Vector3i(7, 3, 3)] = skin
	v[Vector3i(2, 3, 0)] = Color(0.1, 0.1, 0.15)  # eyes
	v[Vector3i(4, 3, 0)] = Color(0.1, 0.1, 0.15)
	v[Vector3i(2, 4, 0)] = hair.darkened(0.2)  # brows
	v[Vector3i(4, 4, 0)] = hair.darkened(0.2)
	VoxelMesh.fill(v, Vector3i(3, 2, -1), Vector3i(1, 2, 1), skin.darkened(0.1))  # nose
	return VoxelMesh.build(v, S, Vector3(-3.5, 0, -3.5))


static func arm(l: Dictionary) -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(2, 2, 2), l.skin)
	VoxelMesh.fill(v, Vector3i(0, 2, 0), Vector3i(2, 5, 2), l.shirt)
	VoxelMesh.fill(v, Vector3i(0, 5, 0), Vector3i(2, 2, 2), l.vest)
	return VoxelMesh.build(v, S, Vector3(-1, -7, -1))


# Tools: handle along +Y, grip near origin.
static func axe() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(1, 13, 1), WOOD)
	VoxelMesh.fill(v, Vector3i(1, 9, 0), Vector3i(2, 4, 1), IRON)
	VoxelMesh.fill(v, Vector3i(3, 8, 0), Vector3i(1, 6, 1), IRON.lightened(0.3))  # blade edge
	return VoxelMesh.build(v, S, Vector3(-0.5, -2, -0.5))


static func pickaxe() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(1, 13, 1), WOOD)
	VoxelMesh.fill(v, Vector3i(-3, 11, 0), Vector3i(7, 1, 1), IRON)
	v[Vector3i(-4, 10, 0)] = IRON.lightened(0.3)
	v[Vector3i(4, 10, 0)] = IRON.lightened(0.3)
	return VoxelMesh.build(v, S, Vector3(-0.5, -2, -0.5))


static func hammer() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(1, 10, 1), WOOD)
	VoxelMesh.fill(v, Vector3i(-1, 9, -1), Vector3i(3, 2, 3), IRON)
	return VoxelMesh.build(v, S, Vector3(-0.5, -2, -0.5))


# Cargo carried in both arms.
static func cargo_wood() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 3, 3), Color(0.45, 0.3, 0.15))
	VoxelMesh.fill(v, Vector3i(0, 1, 1), Vector3i(8, 1, 1), Color(0.8, 0.65, 0.4))  # light core shows at the ends
	return VoxelMesh.build(v, S, Vector3(-4, -1.5, -1.5), 0.12)


static func cargo_lump(base: Color, speck: Color) -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(4, 3, 4), base)
	for c in [Vector3i(1, 2, 1), Vector3i(3, 1, 2), Vector3i(0, 1, 3), Vector3i(2, 0, 0)]:
		v[c] = speck
	v.erase(Vector3i(0, 2, 0))
	return VoxelMesh.build(v, S, Vector3(-2, -1.5, -2), 0.15)


static func cargo_basket() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(5, 3, 4), Color(0.7, 0.53, 0.3))
	VoxelMesh.fill(v, Vector3i(1, 2, 1), Vector3i(3, 2, 2), Color(0.85, 0.12, 0.18))
	v[Vector3i(2, 3, 1)] = Color(0.6, 0.08, 0.3)
	return VoxelMesh.build(v, S, Vector3(-2.5, -1.5, -2), 0.1)


# Short bow held upright in the left hand, origin at the grip. Front (toward the target) is -Z:
# the grip leads, the limbs curve back toward the archer (+Z) and the string runs tip to tip behind
# them, with an arrow nocked on it pointing forward.
static func bow() -> ArrayMesh:
	var v := {}
	var wood := Color(0.5, 0.33, 0.17)
	for y in range(-5, 6):
		var bend := 0 if absi(y) < 2 else (1 if absi(y) < 4 else 2)
		v[Vector3i(0, y, bend)] = wood
	for y in range(-5, 6):
		v[Vector3i(0, y, 3)] = Color(0.9, 0.88, 0.8)  # string
	v[Vector3i(0, 0, 0)] = Color(0.3, 0.2, 0.1)  # grip wrap
	for z in range(-4, 3):
		v[Vector3i(1, 0, z)] = Color(0.6, 0.45, 0.28)  # arrow shaft
	v[Vector3i(1, 0, -5)] = Color(0.6, 0.62, 0.66)  # arrowhead
	v[Vector3i(1, 1, 2)] = Color.WHITE  # fletching
	v[Vector3i(1, -1, 2)] = Color.WHITE
	return VoxelMesh.build(v, S, Vector3(-0.5, -0.5, -0.5), 0.0)


static func cargo_sheaf() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(3, 7, 3), Color(0.88, 0.74, 0.35))
	VoxelMesh.fill(v, Vector3i(0, 3, 0), Vector3i(3, 1, 3), Color(0.55, 0.38, 0.2))
	return VoxelMesh.build(v, S, Vector3(-1.5, -3.5, -1.5), 0.1)


static func cargo_bar() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(6, 2, 3), Color(0.6, 0.63, 0.7))
	VoxelMesh.fill(v, Vector3i(1, 2, 1), Vector3i(4, 1, 1), Color(0.75, 0.78, 0.84))
	return VoxelMesh.build(v, S, Vector3(-3, -1, -1.5), 0.08)


static func cargo_stone() -> ArrayMesh:
	var v := {}
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(4, 4, 4), Color(0.58, 0.58, 0.6))
	for c in [Vector3i(0, 3, 0), Vector3i(3, 3, 3), Vector3i(3, 0, 0)]:
		v.erase(c)  # chipped corners
	return VoxelMesh.build(v, S, Vector3(-2, -2, -2), 0.15)

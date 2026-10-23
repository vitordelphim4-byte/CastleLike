class_name Pieces
## Build catalog (Castle Story style): every placeable piece with its shape, material, cost,
## voxel model and menu preview. Add a piece: add an ITEMS entry (and a model in _voxels if the
## shape is new).

const S := 0.125  # prop voxel size: 8 per block
const MATS := {
	"wood": {"main": Color(0.68, 0.5, 0.3), "dark": Color(0.42, 0.28, 0.15), "block": World.WOOD},
	"stone": {"main": Color(0.68, 0.66, 0.62), "dark": Color(0.45, 0.44, 0.42), "block": World.BRICK},
}
# Shape behavior. solid: blocks walking, supports blocks; floor: stand height inside the cell;
# climb: ladder; tall: also fills the cell above; size: footprint in cells (x, y, z) from the base
# corner; faces: needs a facing direction; light: glows; stack: the build height setting applies
# (others are always placed one high); station: a workstation with bills (Crafting).
const SHAPES := {
	"block": {"solid": true, "stack": true},
	"slab": {"solid": false, "floor": 0.5},
	"stairs": {"solid": false, "floor": 0.5, "faces": true},
	"window": {"solid": true, "faces": true},
	"door": {"solid": false, "tall": true, "faces": true},
	"ladder": {"solid": false, "climb": true, "faces": true, "stack": true},
	"torch": {"solid": false, "light": Color(1, 0.7, 0.4)},
	"lantern": {"solid": true, "light": Color(1, 0.85, 0.55)},
	# Roof pieces: walkable (you climb the roof you're building), hold up the roof piece above them.
	"roof": {"solid": false, "floor": 0.5, "faces": true, "roof": true},
	"roof_corner": {"solid": false, "floor": 0.5, "faces": true, "roof": true},
	"roof_inner": {"solid": false, "floor": 0.5, "faces": true, "roof": true},
	"ridge": {"solid": false, "floor": 0.5, "faces": true, "roof": true},
	"peak": {"solid": false, "floor": 0.5, "roof": true},
	"kiln": {"solid": true, "faces": true, "size": Vector3i(1, 2, 1), "station": true},
	"furnace": {"solid": true, "faces": true, "size": Vector3i(2, 2, 2), "station": true},
}
const GROUPS := ["Madeira", "Pedra", "Telhado", "Utilidades", "Produção", "Iluminação"]
# Shingle colors (two alternating rows): wood = red-brown shingles, stone = blue-grey slate.
const ROOF_COLORS := {"wood": [Color(0.62, 0.33, 0.2), Color(0.52, 0.27, 0.16)],
	"stone": [Color(0.44, 0.49, 0.57), Color(0.36, 0.4, 0.47)]}
# id -> name, menu group, shape, material (= resource it costs), cost
const ITEMS := {
	"wood_block": {"name": "Bloco de madeira", "group": "Madeira", "shape": "block", "mat": "wood", "cost": 1},
	"wood_slab": {"name": "Meio bloco de madeira", "group": "Madeira", "shape": "slab", "mat": "wood", "cost": 1},
	"wood_stairs": {"name": "Degrau de madeira", "group": "Madeira", "shape": "stairs", "mat": "wood", "cost": 1},
	"wood_window": {"name": "Janela de madeira", "group": "Madeira", "shape": "window", "mat": "wood", "cost": 1},
	"wood_door": {"name": "Porta de madeira", "group": "Madeira", "shape": "door", "mat": "wood", "cost": 2},
	"stone_block": {"name": "Bloco de pedra", "group": "Pedra", "shape": "block", "mat": "stone", "cost": 1},
	"stone_slab": {"name": "Meio bloco de pedra", "group": "Pedra", "shape": "slab", "mat": "stone", "cost": 1},
	"stone_stairs": {"name": "Degrau de pedra", "group": "Pedra", "shape": "stairs", "mat": "stone", "cost": 1},
	"stone_window": {"name": "Janela de pedra", "group": "Pedra", "shape": "window", "mat": "stone", "cost": 1},
	"wood_roof": {"name": "Rampa de telhado (telha)", "group": "Telhado", "shape": "roof", "mat": "wood", "cost": 1},
	"wood_roof_corner": {"name": "Canto externo (telha)", "group": "Telhado", "shape": "roof_corner", "mat": "wood", "cost": 1},
	"wood_roof_inner": {"name": "Canto interno (telha)", "group": "Telhado", "shape": "roof_inner", "mat": "wood", "cost": 1},
	"wood_ridge": {"name": "Cumeeira (telha)", "group": "Telhado", "shape": "ridge", "mat": "wood", "cost": 1},
	"wood_peak": {"name": "Ponta do telhado (telha)", "group": "Telhado", "shape": "peak", "mat": "wood", "cost": 1},
	"stone_roof": {"name": "Rampa de telhado (ardósia)", "group": "Telhado", "shape": "roof", "mat": "stone", "cost": 1},
	"stone_roof_corner": {"name": "Canto externo (ardósia)", "group": "Telhado", "shape": "roof_corner", "mat": "stone", "cost": 1},
	"stone_roof_inner": {"name": "Canto interno (ardósia)", "group": "Telhado", "shape": "roof_inner", "mat": "stone", "cost": 1},
	"stone_ridge": {"name": "Cumeeira (ardósia)", "group": "Telhado", "shape": "ridge", "mat": "stone", "cost": 1},
	"stone_peak": {"name": "Ponta do telhado (ardósia)", "group": "Telhado", "shape": "peak", "mat": "stone", "cost": 1},
	"ladder": {"name": "Escada de mão", "group": "Utilidades", "shape": "ladder", "mat": "wood", "cost": 1},
	"kiln": {"name": "Carvoaria", "group": "Produção", "shape": "kiln", "mat": "stone", "cost": 6},
	"furnace": {"name": "Fornalha", "group": "Produção", "shape": "furnace", "mat": "stone", "cost": 8},
	"torch": {"name": "Tocha", "group": "Iluminação", "shape": "torch", "mat": "wood", "cost": 1},
	"lantern": {"name": "Poste de luz", "group": "Iluminação", "shape": "lantern", "mat": "stone", "cost": 2},
}
const GLASS := Color(0.62, 0.85, 1.0)
const FLAME := Color(1, 0.72, 0.2)
const EMBER := Color(1, 0.45, 0.1)
# Workstation chimney top (node space) where smoke comes out.
const SMOKE_AT := {"kiln": Vector3(0, 1.85, 0), "furnace": Vector3(0, 2.7, -0.06)}

static var _meshes := {}
static var _terrain_mat: ShaderMaterial


static func shape(item: String) -> Dictionary:
	return SHAPES[ITEMS[item].shape]


static func size(item: String) -> Vector3i:
	var sh := shape(item)
	return sh.get("size", Vector3i(1, 2, 1) if sh.get("tall", false) else Vector3i.ONE)


# Where a piece's node goes for base cell c: the middle of its footprint, on the floor.
static func origin(item: String, c: Vector3i) -> Vector3:
	var sz := size(item)
	return Vector3(c) + Vector3(sz.x / 2.0, 0, sz.z / 2.0)


static func stacks(item: String) -> bool:
	return shape(item).get("stack", false)


static func is_block(item: String) -> bool:
	return ITEMS[item].shape == "block"


static func block_type(item: String) -> int:
	return MATS[ITEMS[item].mat].block


# Node showing the piece, origin at the cell's bottom center, back (wall side) toward `dir`.
static func instance(item: String, dir := Vector3i.FORWARD) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	if is_block(item):
		mi.mesh = _block_mesh(block_type(item))
		mi.position = Vector3(-0.5, 0, -0.5)
		n.add_child(mi)
	elif ITEMS[item].shape == "door":
		var hinge := Node3D.new()  # World.open_door swings this
		hinge.name = "Hinge"
		hinge.position = Vector3(-0.5, 0, 0)
		mi.mesh = mesh(item)
		mi.position = Vector3(0.5, 0, 0)
		hinge.add_child(mi)
		n.add_child(hinge)
	else:
		mi.mesh = mesh(item)
		n.add_child(mi)
	n.rotation.y = atan2(-dir.x, -dir.z)
	if shape(item).get("station", false):
		_add_fire(n, item)
	var light = shape(item).get("light")
	if light:
		var l := OmniLight3D.new()
		l.light_color = light
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.position = Vector3(0, 0.85, 0)
		n.add_child(l)
	return n


static func mesh(item: String) -> ArrayMesh:
	if not _meshes.has(item):
		var sz := size(item)
		_meshes[item] = VoxelMesh.build(_voxels(item), S, Vector3(-4 * sz.x, 0, -4 * sz.z), 0.07)
	return _meshes[item]


# Hidden glow in the station's opening + smoke from its chimney; World.set_station_active shows them.
static func _add_fire(n: Node3D, item: String) -> void:
	var key := item + "_fire"
	if not _meshes.has(key):
		var v := {}
		if item == "furnace":
			VoxelMesh.fill(v, Vector3i(6, 2, 8), Vector3i(4, 2, 3), EMBER)
			VoxelMesh.fill(v, Vector3i(7, 2, 9), Vector3i(2, 3, 2), FLAME)
		else:
			VoxelMesh.fill(v, Vector3i(3, 3, 5), Vector3i(2, 1, 2), EMBER)
			v[Vector3i(3, 4, 5)] = FLAME
		var sz := size(item)
		_meshes[key] = VoxelMesh.build(v, S, Vector3(-4 * sz.x, 0, -4 * sz.z), 0.1)
	var fire := MeshInstance3D.new()
	fire.name = "Fire"
	fire.mesh = _meshes[key]
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.material_override = glow
	fire.visible = false
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.6, 0.3)
	l.light_energy = 1.6
	l.omni_range = 5.0
	l.position = Vector3(0, 0.4, 0.6 if item == "furnace" else 0.3)
	fire.add_child(l)
	n.add_child(fire)
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 14
	smoke.lifetime = 3.0
	smoke.position = SMOKE_AT[item]
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.8
	smoke.gravity = Vector3(0.12, 0.1, 0)  # a little drift
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = grow
	var puff := BoxMesh.new()
	puff.size = Vector3.ONE * 0.28
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(0.45, 0.45, 0.47, 0.75)
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = puff_mat
	smoke.mesh = puff
	n.add_child(smoke)


# A unit cube with the terrain shader, so block previews show the real planks/bricks texture.
static func _block_mesh(t: int) -> ArrayMesh:
	var key := "block_%d" % t
	if _meshes.has(key):
		return _meshes[key]
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = preload("res://shaders/terrain.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(World.COLORS[t], 1.0)
	for n in VoxelMesh.DIRS:
		VoxelMesh.add_face(st, Vector3.ZERO, Vector3(n), [col, col, col, col], 1.0, Vector2(t, 0))
	st.set_material(_terrain_mat)
	_meshes[key] = st.commit()
	return _meshes[key]


# Roof surface height (voxels, 1..8) over the 8x8 cell. Slopes rise toward the back (-Z, z = 0),
# like stairs; corners are low on the front (+Z) and left (-X); ridge runs along X; peak is a pyramid.
static func _roof_height(s: String) -> Callable:
	match s:
		"roof": return func(_x: int, z: int) -> int: return 8 - z
		"roof_corner": return func(x: int, z: int) -> int: return mini(8 - z, x + 1)
		"roof_inner": return func(x: int, z: int) -> int: return maxi(8 - z, 8 - x)
		"ridge": return func(_x: int, z: int) -> int: return 8 - int(absf(z - 3.5) * 2)
		"peak": return func(x: int, z: int) -> int: return 8 - int(maxf(absf(x - 3.5), absf(z - 3.5)) * 2)
	return Callable()


# Voxel models on an 8x8x8 grid per cell (door: 8x16). The back / wall side is z = 0 (-Z).
static func _voxels(item: String) -> Dictionary:
	var m: Color = MATS[ITEMS[item].mat].main
	var d: Color = MATS[ITEMS[item].mat].dark
	var v := {}
	var roof_height := _roof_height(ITEMS[item].shape)
	if roof_height.is_valid():
		var shingles: Array = ROOF_COLORS[ITEMS[item].mat]
		for x in 8:
			for z in 8:
				var h: int = clampi(roof_height.call(x, z), 1, 8)
				for y in h:
					# Top two layers are shingles in alternating rows; beams underneath.
					v[Vector3i(x, y, z)] = shingles[(y + z / 2) % 2] if y >= h - 2 else d
		return v
	match ITEMS[item].shape:
		"slab":
			VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 4, 8), m)
			VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 1, 8), d)
		"stairs":  # rises toward the back
			VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(8, 4, 8), m)
			VoxelMesh.fill(v, Vector3i(0, 4, 0), Vector3i(8, 4, 4), m)
			VoxelMesh.fill(v, Vector3i(0, 3, 7), Vector3i(8, 1, 1), d)  # step nosing
			VoxelMesh.fill(v, Vector3i(0, 7, 3), Vector3i(8, 1, 1), d)
		"window":
			for x in 8:
				for y in 8:
					var frame := x == 0 or x == 7 or y == 0 or y == 7
					var bar := x == 3 or x == 4 or y == 3 or y == 4
					if frame:
						VoxelMesh.fill(v, Vector3i(x, y, 2), Vector3i(1, 1, 4), d if item.begins_with("wood") else m)
					else:
						v[Vector3i(x, y, 4)] = d if bar else GLASS
			VoxelMesh.fill(v, Vector3i(0, 0, 1), Vector3i(8, 1, 6), m)  # sill
		"door":
			for y in 16:
				for x in 8:
					var frame := x == 0 or x == 7 or y == 15
					v[Vector3i(x, y, 3)] = d if frame or y in [3, 12] or (x == y / 2 and y > 3 and y < 12) else m
					v[Vector3i(x, y, 4)] = d if frame else m.darkened(0.08 * (x % 2))  # plank seams
			v[Vector3i(6, 7, 2)] = Color(0.85, 0.75, 0.3)  # handle
			v[Vector3i(6, 7, 5)] = Color(0.85, 0.75, 0.3)
		"ladder":
			VoxelMesh.fill(v, Vector3i(1, 0, 0), Vector3i(1, 8, 1), d)
			VoxelMesh.fill(v, Vector3i(6, 0, 0), Vector3i(1, 8, 1), d)
			for y in [1, 3, 5, 7]:
				VoxelMesh.fill(v, Vector3i(2, y, 0), Vector3i(4, 1, 1), m)
		"torch":
			VoxelMesh.fill(v, Vector3i(3, 0, 3), Vector3i(2, 5, 2), d)
			VoxelMesh.fill(v, Vector3i(3, 5, 3), Vector3i(2, 1, 2), m)
			VoxelMesh.fill(v, Vector3i(3, 6, 3), Vector3i(2, 2, 2), FLAME)
			v[Vector3i(3, 7, 3)] = Color(1, 0.95, 0.6)
		"lantern":
			VoxelMesh.fill(v, Vector3i(2, 0, 2), Vector3i(4, 1, 4), d)
			VoxelMesh.fill(v, Vector3i(3, 1, 3), Vector3i(2, 4, 2), m)
			VoxelMesh.fill(v, Vector3i(2, 5, 2), Vector3i(4, 2, 4), Color(1, 0.85, 0.45))
			for c in [Vector3i(2, 5, 2), Vector3i(5, 5, 2), Vector3i(2, 5, 5), Vector3i(5, 5, 5)]:
				VoxelMesh.fill(v, c, Vector3i(1, 2, 1), d)
			VoxelMesh.fill(v, Vector3i(2, 7, 2), Vector3i(4, 1, 4), d)
		"furnace":
			_furnace(v)
		"kiln":
			_kiln(v)
	return v


# Castle Story furnace on a 16x16 grid (2x2 cells): stone plinth, tapered clay body with panel seams,
# arched stone-framed mouth in front (+Z), square chimney on top.
static func _furnace(v: Dictionary) -> void:
	var stone := Color(0.64, 0.63, 0.6)
	var clay := Color(0.8, 0.48, 0.25)
	var seam := Color(0.64, 0.36, 0.18)
	VoxelMesh.fill(v, Vector3i(0, 0, 0), Vector3i(16, 2, 16), stone)
	VoxelMesh.fill(v, Vector3i(0, 1, 0), Vector3i(16, 1, 1), stone.darkened(0.12))
	for y in range(2, 14):
		var inset := int((y - 2) / 2.5)
		for x in range(1 + inset, 15 - inset):
			for z in range(1 + inset, 14 - inset):
				var line := y % 4 == 1 or x == 7 or z == 7
				v[Vector3i(x, y, z)] = seam if line else clay.darkened(0.05 * ((x + y) % 2))
	VoxelMesh.fill(v, Vector3i(6, 14, 5), Vector3i(4, 6, 4), seam)  # chimney
	VoxelMesh.fill(v, Vector3i(5, 20, 4), Vector3i(6, 2, 6), clay)  # rim
	VoxelMesh.fill(v, Vector3i(7, 15, 6), Vector3i(2, 7, 2), Color.BLACK)
	for y in range(15, 22):
		for x in [7, 8]:
			for z in [6, 7]:
				v.erase(Vector3i(x, y, z))  # hollow flue
	# Mouth: carve an arch into the front, dark inside, stone frame around it.
	for y in range(2, 8):
		for x in range(6, 10):
			if y == 7 and (x == 6 or x == 9):
				continue
			for z in range(8, 16):
				v.erase(Vector3i(x, y, z))
			v[Vector3i(x, y, 7)] = Color(0.12, 0.08, 0.06)
	for y in range(2, 9):
		var zf := 12 - int((y - 2) / 2.5)
		var frame: Array = [5, 10] if y < 7 else ([6, 9] if y == 7 else [6, 7, 8, 9])
		for x in frame:
			for z in range(8, zf + 1):
				if v.has(Vector3i(x, y, z)):
					v[Vector3i(x, y, z)] = stone.lightened(0.05 * (y % 2))


# Valheim charcoal kiln on an 8x16 grid (1x2 cells): an egg of dark mortared stones with a
# six-sided mouth and chute in front (+Z) and a vent on top.
static func _kiln(v: Dictionary) -> void:
	for x in 8:
		for y in 15:
			for z in 8:
				var dy := (y + 0.5 - 6.0) / (9.0 if y >= 6 else 7.0)
				var d := Vector3((x + 0.5 - 4.0) / 4.0, dy, (z + 0.5 - 4.0) / 4.0)
				if d.length_squared() < 1.0:
					var k := hash(Vector3i(x / 2, (y + x % 2) / 2, z / 2)) % 100 / 100.0
					v[Vector3i(x, y, z)] = Color(0.3, 0.33, 0.36).lerp(Color(0.46, 0.48, 0.5), k)
	for y in range(12, 15):
		for x in [3, 4]:
			for z in [3, 4]:
				v.erase(Vector3i(x, y, z))  # vent
	for y in range(3, 6):
		for x in range(2 if y == 4 else 3, 6 if y == 4 else 5):
			for z in range(5, 8):
				v.erase(Vector3i(x, y, z))  # six-sided mouth
			v[Vector3i(x, y, 4)] = Color(0.08, 0.06, 0.05)
	VoxelMesh.fill(v, Vector3i(3, 2, 5), Vector3i(2, 1, 3), Color(0.55, 0.56, 0.57))  # chute

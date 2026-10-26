class_name Animal
extends Node3D
## Wild animal (RimWorld-style wildlife): grazes, wanders, runs from villagers that come close.
## Hunted: deer and rabbits flee, boars charge whoever hurt them and scare them off. Dead animals
## lie on their side as a corpse ("corpses" group) until a hunter butchers it into raw meat.
## populate() keeps a few herds around the colony. Voxel models, 16 pixels per block.

const SPECIES := {
	"rabbit": {"name": "Coelho", "speed": 4.5, "hp": 1, "meat": 2, "flee": 4.0, "herd": [1, 3],
		"biomes": ["plains", "forest", "taiga", "tundra"],
		"body": Vector3i(5, 4, 7), "leg": Vector3i(1, 2, 1), "head": Vector3i(4, 4, 4),
		"fur": Color(0.62, 0.52, 0.42), "belly": Color(0.85, 0.82, 0.76)},
	"deer": {"name": "Cervo", "speed": 5.0, "hp": 3, "meat": 6, "flee": 7.0, "herd": [2, 4],
		"biomes": ["forest", "plains", "taiga"],
		"body": Vector3i(6, 6, 12), "leg": Vector3i(2, 10, 2), "head": Vector3i(5, 5, 5),
		"fur": Color(0.7, 0.48, 0.28), "belly": Color(0.93, 0.88, 0.78),
		"neck": true},  # head part = tall neck + head, pivoting at the front of the back (grazing)
	"boar": {"name": "Javali", "speed": 4.0, "hp": 4, "meat": 5, "flee": 0.0, "herd": [1, 2], "aggressive": true,
		"biomes": ["forest"],
		"body": Vector3i(8, 7, 12), "leg": Vector3i(2, 4, 2), "head": Vector3i(6, 5, 5),
		"fur": Color(0.33, 0.24, 0.18), "belly": Color(0.28, 0.2, 0.15)},
}
const VS := 1.0 / 16.0
const MAX_ALIVE := 14
const SPAWN_MIN := 18.0  # herds appear this far from a villager...
const SPAWN_MAX := 45.0  # ...and no farther (the world's paths only exist near the camera)
enum { IDLE, WANDER, FLEE, CHARGE, DEAD }

static var _meshes := {}

var species := "deer"
var world: World
var hp := 1
var state := IDLE
var path := PackedVector3Array()
var timer := 0.0
var anim_t := 0.0
var foe: Node3D  # boar: who it's charging
var calm := 0.0  # boar: seconds before it may charge again
var claimed := false  # corpse being butchered
var marked := false:  # clicked with the hunt tool: hunters go after it wherever it is
	set(v):
		marked = v
		if is_instance_valid(_mark):
			_mark.visible = v
var _mark: MeshInstance3D
var body := Node3D.new()
var head := Node3D.new()
var legs: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("corpses" if state == DEAD else "animals")
	var sp: Dictionary = SPECIES[species]
	if hp <= 0:
		hp = sp.hp
	var b: Vector3i = sp.body
	var l: Vector3i = sp.leg
	body.position.y = l.y * VS
	add_child(body)
	var bm := MeshInstance3D.new()
	bm.mesh = _part_mesh("body")
	body.add_child(bm)
	head.position = Vector3(0, (b.y - 1) * VS, -b.z / 2.0 * VS)
	if sp.get("neck", false):
		head.position = Vector3(0, (b.y - 2) * VS, (-b.z / 2.0 + 1) * VS)
	body.add_child(head)
	var hm := MeshInstance3D.new()
	hm.mesh = _part_mesh("head")
	head.add_child(hm)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := MeshInstance3D.new()
			leg.mesh = _part_mesh("leg")
			leg.position = Vector3(sx * (b.x / 2.0 - l.x / 2.0 - 0.5) * VS, l.y * VS, sz * (b.z / 2.0 - l.x / 2.0 - 1) * VS)
			add_child(leg)
			legs.append(leg)
	timer = randf_range(0.5, 4.0)
	_mark = MeshInstance3D.new()  # red arrow over the head
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.3, 0.3, 0.08)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.95, 0.2, 0.15)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material = red
	_mark.mesh = arrow
	_mark.rotation.z = PI  # point down
	_mark.position.y = (sp.leg.y + sp.body.y) * VS + 0.9
	_mark.visible = marked
	add_child(_mark)
	if state == DEAD:
		_lie_down(false)


func display_name() -> String:
	return SPECIES[species].name


func _process(delta: float) -> void:
	anim_t += delta
	if state == DEAD:
		return
	calm = maxf(0.0, calm - delta)
	var sp: Dictionary = SPECIES[species]
	if state in [IDLE, WANDER] and sp.flee > 0:
		var threat := _nearest_worker(sp.flee)
		if threat:
			_flee_from(threat.position)
	if state == CHARGE:
		_charge(delta)
	elif not path.is_empty():
		_walk(delta, sp.speed * (1.4 if state == FLEE else 0.5))
	else:
		if state != IDLE:
			state = IDLE
			timer = randf_range(2.0, 6.0)
		timer -= delta
		if timer <= 0:
			_wander()
	_animate(delta)


# Hit by a hunter's arrow.
func hurt(dmg: int, attacker: Node3D) -> void:
	if state == DEAD:
		return
	hp -= dmg
	if hp <= 0:
		state = DEAD
		path.clear()
		remove_from_group("animals")
		add_to_group("corpses")
		marked = false
		_lie_down(true)
	elif SPECIES[species].get("aggressive", false):
		foe = attacker
		state = CHARGE
		calm = 0.0
	else:
		_flee_from(attacker.position)


func _wander() -> void:
	var to := position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = WANDER if not path.is_empty() else IDLE
	timer = randf_range(2.0, 6.0)


func _flee_from(from: Vector3) -> void:
	var away := position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	var to := position + away * 10.0
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = FLEE


# Boar: run at the foe, knock them back on contact, then calm down for a while.
func _charge(delta: float) -> void:
	if not is_instance_valid(foe):
		state = IDLE
		return
	if position.distance_to(foe.position) < 1.1:
		if foe.has_method("scare"):
			foe.scare(self)
		state = IDLE
		calm = 6.0
		timer = 2.0
		return
	timer -= delta
	if timer <= 0 or path.is_empty():
		timer = 0.5
		path = world.find_path(position, foe.position)
	if not path.is_empty():
		_walk(delta, SPECIES[species].speed * 1.3)


func _nearest_worker(radius: float) -> Node3D:
	for w in get_tree().get_nodes_in_group("workers"):
		if w.position.distance_to(position) < radius:
			return w
	return null


func _walk(delta: float, speed: float) -> void:
	var to := path[0] - position
	var step := speed * delta
	if to.length() <= step:
		position = path[0]
		path.remove_at(0)
	else:
		position += to.normalized() * step
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 10.0))


func _animate(delta: float) -> void:
	var moving := not path.is_empty() or state == CHARGE
	var rate := 16.0 if state in [FLEE, CHARGE] else 9.0
	var swing := sin(anim_t * rate) * 0.6 if moving else 0.0
	for i in legs.size():
		legs[i].rotation.x = swing * (1 if i in [0, 3] else -1)  # diagonal pairs
	var graze := not moving and fmod(anim_t, 6.0) < 3.5  # head down eating, then up looking around
	var k := 1.0 - exp(-8.0 * delta)
	var down := -1.0 if SPECIES[species].get("neck", false) else -0.7
	head.rotation.x = lerpf(head.rotation.x, down if graze else 0.15, k)
	body.position.y = SPECIES[species].leg.y * VS + (absf(swing) * 0.6 * VS if moving else 0.0)


func _lie_down(animated: bool) -> void:
	for leg in legs:
		leg.rotation.x = 0
	var target := Vector3(0, rotation.y, PI / 2)
	if animated:
		var tw := create_tween()
		tw.tween_property(self, "rotation", target, 0.4).set_trans(Tween.TRANS_QUAD)
	else:
		rotation = target


func _part_mesh(part: String) -> ArrayMesh:
	var key := "%s_%s" % [species, part]
	if not _meshes.has(key):
		_meshes[key] = _build(species, part)
	return _meshes[key]


# Box body (belly lighter), head sticking forward from the front top with species details, thin legs.
static func _build(sp_id: String, part: String) -> ArrayMesh:
	if sp_id == "deer":
		return _deer(part)
	var sp: Dictionary = SPECIES[sp_id]
	var fur: Color = sp.fur
	var v := {}
	match part:
		"body":
			var b: Vector3i = sp.body
			VoxelMesh.fill(v, Vector3i.ZERO, b, fur)
			VoxelMesh.fill(v, Vector3i(1, 0, 1), Vector3i(b.x - 2, 1, b.z - 2), sp.belly)
			match sp_id:
				"rabbit": VoxelMesh.fill(v, Vector3i(b.x / 2 - 1, 2, b.z), Vector3i(2, 2, 2), Color.WHITE)  # tail
				"deer": VoxelMesh.fill(v, Vector3i(b.x / 2 - 1, b.y - 3, b.z), Vector3i(2, 2, 1), Color(0.95, 0.93, 0.88))
				"boar":  # bristly ridge along the back
					VoxelMesh.fill(v, Vector3i(b.x / 2 - 1, b.y, 1), Vector3i(2, 1, b.z - 3), fur.darkened(0.35))
			return VoxelMesh.build(v, VS, Vector3(-b.x / 2.0, 0, -b.z / 2.0), 0.06)
		"head":
			var h: Vector3i = sp.head
			VoxelMesh.fill(v, Vector3i.ZERO, h, fur)
			var eye := Color(0.08, 0.06, 0.05)
			v[Vector3i(0, h.y - 2, 1)] = eye
			v[Vector3i(h.x - 1, h.y - 2, 1)] = eye
			match sp_id:
				"rabbit":
					for x in [0, h.x - 1]:
						VoxelMesh.fill(v, Vector3i(x, h.y, h.z - 2), Vector3i(1, 4, 1), fur)  # long ears
					v[Vector3i(h.x / 2, 1, 0)] = Color(0.9, 0.6, 0.6)  # nose
				"deer":
					VoxelMesh.fill(v, Vector3i(1, 0, -2), Vector3i(h.x - 2, 2, 2), fur.darkened(0.1))  # muzzle
					v[Vector3i(h.x / 2, 1, -2)] = eye
					for x in [0, h.x - 1]:  # antlers: trunk with two tines
						var dx := -1 if x == 0 else 1
						VoxelMesh.fill(v, Vector3i(x, h.y, h.z - 2), Vector3i(1, 4, 1), Color(0.5, 0.4, 0.3))
						v[Vector3i(x + dx, h.y + 2, h.z - 2)] = Color(0.5, 0.4, 0.3)
						v[Vector3i(x + dx * 2, h.y + 4, h.z - 2)] = Color(0.5, 0.4, 0.3)
						v[Vector3i(x, h.y + 4, h.z - 3)] = Color(0.5, 0.4, 0.3)
				"boar":
					VoxelMesh.fill(v, Vector3i(1, 0, -2), Vector3i(h.x - 2, 3, 2), fur.lightened(0.1))  # snout
					v[Vector3i(2, 1, -2)] = Color(0.75, 0.55, 0.5)
					v[Vector3i(h.x - 3, 1, -2)] = Color(0.75, 0.55, 0.5)
					for x in [0, h.x - 1]:
						VoxelMesh.fill(v, Vector3i(x, 0, -2), Vector3i(1, 2, 1), Color(0.95, 0.92, 0.82))  # tusks
						v[Vector3i(x, h.y, h.z - 2)] = fur.darkened(0.2)  # ears
			# The head's back face sits at the neck; it reaches forward (-Z) and a bit below the back line.
			return VoxelMesh.build(v, VS, Vector3(-h.x / 2.0, -h.y / 3.0, -h.z), 0.06)
		_:  # leg
			var l: Vector3i = sp.leg
			VoxelMesh.fill(v, Vector3i.ZERO, l, fur.darkened(0.1))
			v[Vector3i(0, 0, 0)] = fur.darkened(0.5)  # hoof / paw
			return VoxelMesh.build(v, VS, Vector3(-l.x / 2.0, -l.y, -l.x / 2.0), 0.0)


# Deer after the references: slim tan body, white belly and chest, long thin legs with dark hooves,
# tall neck, head with a black-tipped muzzle and white band, ears out to the sides, big branching
# antlers, short tail dark on top and white underneath. Fur pixels vary a little in shade.
static func _deer(part: String) -> ArrayMesh:
	var sp: Dictionary = SPECIES.deer
	var fur: Color = sp.fur
	var white: Color = sp.belly
	var shade := func(c: Vector3i) -> Color: return fur.darkened(0.07 * (hash(c) % 3)) if hash(c) % 5 else fur.lightened(0.05)
	var v := {}
	match part:
		"body":
			var b: Vector3i = sp.body
			for x in b.x:
				for y in b.y:
					for z in b.z:
						var c := Vector3i(x, y, z)
						v[c] = shade.call(c)
			VoxelMesh.fill(v, Vector3i(1, 0, 2), Vector3i(b.x - 2, 1, b.z - 4), white)  # belly
			VoxelMesh.fill(v, Vector3i(1, 0, 0), Vector3i(b.x - 2, 3, 1), white)  # chest
			VoxelMesh.fill(v, Vector3i(2, b.y - 3, b.z), Vector3i(2, 3, 1), white)  # tail, white underneath
			VoxelMesh.fill(v, Vector3i(2, b.y - 1, b.z), Vector3i(2, 1, 1), fur.darkened(0.45))
			return VoxelMesh.build(v, VS, Vector3(-b.x / 2.0, 0, -b.z / 2.0), 0.04)
		"head":
			# Origin at the neck's base (front top of the body); the head reaches forward (-Z) at the top.
			for y in 8:
				for x in range(1, 4):
					for z in range(1, 4):
						var c := Vector3i(x, y, z)
						v[c] = white if z == 1 and y < 4 else shade.call(c)  # pale throat
			for x in 5:
				for y in range(7, 11):
					for z in range(-1, 4):
						var c := Vector3i(x, y, z)
						v[c] = shade.call(c)
			VoxelMesh.fill(v, Vector3i(1, 7, -4), Vector3i(3, 2, 3), fur.lightened(0.08))  # muzzle
			VoxelMesh.fill(v, Vector3i(1, 7, -4), Vector3i(3, 1, 3), white)  # white band under it
			VoxelMesh.fill(v, Vector3i(1, 8, -4), Vector3i(3, 1, 1), Color(0.1, 0.08, 0.07))  # black nose tip
			v[Vector3i(0, 9, 0)] = Color(0.06, 0.05, 0.05)  # eyes
			v[Vector3i(4, 9, 0)] = Color(0.06, 0.05, 0.05)
			for side in [-1, 1]:
				var ex := -1 if side < 0 else 5
				VoxelMesh.fill(v, Vector3i(ex + mini(side, 0), 9, 2), Vector3i(2, 2, 1), fur.darkened(0.15))  # ears
				# Antler: a beam rising and leaning out, tines pointing forward.
				var antler := Color(0.42, 0.28, 0.18)
				var bx := 1 if side < 0 else 3
				for y in range(11, 18):
					var out := 0 if y < 13 else (1 if y < 15 else 2)
					v[Vector3i(bx + side * out, y, 2)] = antler
				v[Vector3i(bx + side, 13, 1)] = antler
				v[Vector3i(bx + side, 13, 0)] = antler
				v[Vector3i(bx + side * 2, 16, 1)] = antler
				v[Vector3i(bx + side * 2, 16, 0)] = antler
				v[Vector3i(bx + side * 3, 17, 2)] = antler
			return VoxelMesh.build(v, VS, Vector3(-2.5, 0, -2), 0.04)
		_:  # leg: thin, dark hoof
			var l: Vector3i = sp.leg
			VoxelMesh.fill(v, Vector3i.ZERO, l, fur.darkened(0.05))
			VoxelMesh.fill(v, Vector3i.ZERO, Vector3i(l.x, 2, l.z), Color(0.16, 0.12, 0.1))
			return VoxelMesh.build(v, VS, Vector3(-l.x / 2.0, -l.y, -l.x / 2.0), 0.0)


# Keeps up to MAX_ALIVE animals around the colony: tops up with a herd of a species that lives in
# the biome found at a random spot SPAWN_MIN..SPAWN_MAX from a villager.
static func populate(parent: Node, w: World) -> void:
	var alive := parent.get_tree().get_nodes_in_group("animals").size()
	var workers := parent.get_tree().get_nodes_in_group("workers")
	if alive >= MAX_ALIVE or workers.is_empty():
		return
	var near: Vector3 = workers.pick_random().position
	var a := randf() * TAU
	var at := near + Vector3(cos(a), 0, sin(a)) * randf_range(SPAWN_MIN, SPAWN_MAX)
	var c := Vector3i(floori(at.x), 0, floori(at.z))
	c.y = w.top_at(c.x, c.z)
	if not w.nav_built.has(Vector2i(c.x >> 4, c.z >> 4)) or not w.walkable(c):
		return
	var b := w.gen.biome(c.x, c.z, c.y - 1)
	var options := SPECIES.keys().filter(func(s: String) -> bool: return b in SPECIES[s].biomes)
	if options.is_empty():
		return
	var sp: String = options.pick_random()
	for i in randi_range(SPECIES[sp].herd[0], SPECIES[sp].herd[1]):
		var p := Vector3i(c.x + randi_range(-2, 2), 0, c.z + randi_range(-2, 2))
		p.y = w.top_at(p.x, p.z)
		if w.walkable(p):
			spawn(parent, w, sp, Vector3(p) + Vector3(0.5, 0, 0.5))


static func spawn(parent: Node, w: World, sp: String, pos: Vector3, hp_left := 0, dead := false) -> Animal:
	var an := Animal.new()
	an.species = sp
	an.world = w
	an.position = pos
	an.rotation.y = randf() * TAU
	an.hp = hp_left
	if dead:
		an.state = DEAD
	parent.add_child(an)
	return an

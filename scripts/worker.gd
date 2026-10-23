class_name Worker
extends Node3D
## Peasant worker (Warcraft 3 style voxel model, animated limbs).
## RimWorld-style: picks jobs from global orders by its own work priorities (1 = first .. 4, 0 = never):
## chop trees in tree areas, dig marked blocks, build blueprints with material fetched from the
## stockpile, demolish marked constructions (Construction work, like RimWorld's deconstruct),
## work station bills (Crafting: fetch the ingredients, work at the station, haul the product).

enum { IDLE, MANUAL, TO_STOCK, TO_WORK, WORKING, FETCH, GATHER }

const WORK_TIME := {"wood": 2.5, "dig": 1.2, "dig_stone": 2.0, "dig_ore": 2.5, "build": 1.0, "demolish": 1.0}
const S := PeasantParts.S
const DEFAULT_PRIORITY := 3
const TOOLS := {"wood": "axe", "dig": "pickaxe", "build": "hammer", "demolish": "hammer", "craft": "hammer"}
const DIG_YIELD := {World.STONE: "stone", World.IRON_ORE: "iron_ore"}  # dug block -> resource
const REACH := 1.9  # horizontal distance at which a block can be dug/placed
const NO_SPOT := Vector3i(0, -1, 0)

@export var speed := 4.0

var world: World
var worker_name := ""
var color := Color(0.6, 0.55, 0.5)  # neckerchief, also used in the work tab
var look := {}  # PeasantParts look: {female, skin, hair, shirt, vest}
var priorities := {}  # work -> 0 (disabled) or 1 (highest) .. 4
var path := PackedVector3Array()
var state := IDLE
var carrying := ""
var carry_count := 0
var timer := 0.0
var anim_t := 0.0
var falling := false
var unreachable := {}  # trees / cells we failed to reach; cleared whenever terrain changes
# Current job: kind "" (none), "wood" (tree), "dig" (order cell), "build" (blueprint cell),
# "demolish" (marked cell), "craft" (station base cell, recipe job_recipe)
var job_kind := ""
var job_recipe := ""
var job_need := {}  # craft: ingredients still to fetch (kind -> amount)
var held := {}  # craft: ingredients in hand (kind -> amount)
var tree: ResourceNode
var job_cell := Vector3i.ZERO
var job_task := {}
var stock_tile := Vector3i.ZERO  # stockpile tile we're taking cargo to / fetching material from
var no_room := false  # holding cargo with every stockpile tile full
var job_spot := NO_SPOT  # cell beside the tree we chop from, so two choppers don't overlap
var ring: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var tool: MeshInstance3D
var cargo: MeshInstance3D
var scarf_mat := StandardMaterial3D.new()
var selected := false:
	set(v):
		selected = v
		ring.visible = v


func _init() -> void:
	for work in Game.WORKS:
		priorities[work] = DEFAULT_PRIORITY


func _ready() -> void:
	add_to_group("workers")
	world.terrain_changed.connect(func() -> void: unreachable.clear())
	leg_l = _part("leg", Vector3(-1.5 * S, 7 * S, 0))
	leg_r = _part("leg", Vector3(1.5 * S, 7 * S, 0))
	_part("torso", Vector3(0, 7 * S, 0))
	if look.get("female", false):
		_part("skirt", Vector3(0, 7 * S, 0))
	var scarf := _part("scarf", Vector3(0, 15 * S, 0))
	scarf_mat.vertex_color_use_as_albedo = true
	scarf_mat.vertex_color_is_srgb = true
	scarf_mat.albedo_color = color
	scarf.material_override = scarf_mat
	_part("head", Vector3(0, 16 * S, 0))
	arm_l = _part("arm", Vector3(-5 * S, 14.5 * S, 0))
	arm_r = _part("arm", Vector3(5 * S, 14.5 * S, 0))
	tool = MeshInstance3D.new()
	tool.position = Vector3(0, -6 * S, 0)
	tool.rotation.x = -PI / 2  # handle points forward when the arm hangs
	arm_r.add_child(tool)
	cargo = _part("cargo_wood", Vector3(0, 11 * S, -5 * S))
	ring = Game.box(self, Vector3(1.0, 0.03, 1.0), Vector3(0, 0.02, 0), Color(0.2, 1, 0.3))
	ring.visible = false
	_set_cargo("")


# Player order: drop current job, walk there, then go back to work.
func move_to(target: Vector3) -> void:
	_drop_job()
	path = world.find_path(position, target)
	state = MANUAL


# One line for the colonist bar: what this villager is doing right now.
func activity() -> String:
	var res: String = Game.RESOURCES[carrying].name if carrying else ""
	if no_room and state == IDLE:
		return "Sem espaço no estoque (%s)" % res
	match state:
		MANUAL:
			return "Indo (sua ordem)"
		TO_STOCK:
			return "Guardando %s" % res
		FETCH:
			return "Buscando material"
		GATHER:
			return "Buscando %s" % Game.RESOURCES[job_need.keys()[0]].name if job_need else "Buscando ingredientes"
		TO_WORK, WORKING:
			var verb: String = "Indo " if state == TO_WORK else ""
			match job_kind:
				"wood": return verb + ("cortar árvore" if verb else "Cortando árvore")
				"dig": return verb + ("escavar" if verb else "Escavando")
				"demolish": return verb + ("demolir" if verb else "Demolindo")
				"craft":
					var what: String = Crafting.RECIPES[job_recipe].name.to_lower()
					return (verb + "fazer " if verb else "Fazendo ") + what
				"build":
					var piece: String = Pieces.ITEMS[Game.blueprints[job_cell].item].name.to_lower() \
						if Game.blueprints.has(job_cell) else ""
					return (verb + "construir " if verb else "Construindo ") + piece
	return "Ocioso"


func _process(delta: float) -> void:
	anim_t += delta
	if not path.is_empty():
		_walk(delta)
	else:
		_settle()
		_update_state(delta)
	_animate()


# Pop out of a block placed on us; fall into a hole dug under us. After landing, make sure
# we're not trapped.
func _settle() -> void:
	var feet := Vector3i(position.floor())
	if world.is_solid(feet):
		position.y = feet.y + 1
	elif feet.y > 0 and not world.is_solid(feet + Vector3i.DOWN) and not world.is_ladder(feet) \
			and not world.is_roof(feet):
		position.y = feet.y - 1
		falling = true
	elif falling:
		falling = false
		_ensure_exit()


# Dug into a pit with no way back to the stockpile: put up a free emergency ladder against the
# lowest pit wall, from our feet to its rim (the top rung steps onto the rim).
func _ensure_exit() -> void:
	var out := world.find_path(position, Game.stockpile)
	if not out.is_empty() and out[-1].distance_to(Game.stockpile) < 1.5:
		return
	var feet := Vector3i(position.floor())
	var wall := Vector3i.ZERO
	var rim := World.SY
	for d in World.H_DIRS:
		var top := world.top_at(feet.x + d.x, feet.z + d.z)
		if top >= feet.y + 2 and top < rim:
			rim = top
			wall = d
	if wall == Vector3i.ZERO:
		return
	for y in range(feet.y, rim):
		var c := Vector3i(feet.x, y, feet.z)
		if not world.is_solid(c) and not world.props.has(c):
			world.add_ladder(c, wall)


func _update_state(delta: float) -> void:
	match state:
		IDLE:
			_think()
			if state == IDLE:
				_spread()
		MANUAL:
			state = IDLE
		TO_STOCK:
			if _near(_tile_pos(stock_tile), 0.9):
				var left := Game.deposit(stock_tile, carrying, carry_count)
				_set_cargo(carrying if left > 0 else "", left)  # tile filled up meanwhile: try another
			state = IDLE
		FETCH:
			var item: String = Game.blueprints[job_cell].item if Game.blueprints.has(job_cell) else ""
			if item and _near(_tile_pos(stock_tile), 0.9) \
					and Game.withdraw(stock_tile, Pieces.ITEMS[item].mat, Pieces.ITEMS[item].cost):
				_set_cargo(Pieces.ITEMS[item].mat, Pieces.ITEMS[item].cost)
				_go_to_job()
			else:
				_fail()
		GATHER:
			var kind: String = job_need.keys()[0]
			if _job_valid() and _near(_tile_pos(stock_tile), 0.9) and Game.withdraw(stock_tile, kind, job_need[kind]):
				held[kind] = job_need[kind]
				job_need.erase(kind)
				cargo.mesh = PeasantParts.mesh("cargo_" + kind)
				_next_ingredient()
			else:
				_drop_job()
		TO_WORK:
			if _job_valid() and _in_reach():
				state = WORKING
				anim_t = 0
				timer = _work_time()
				if job_kind == "craft":
					world.set_station_active(job_cell, true)
			else:
				_fail()
		WORKING:
			if not _job_valid():
				_drop_job()
				return
			var target := _job_target()
			rotation.y = atan2(position.x - target.x, position.z - target.z)
			timer -= delta
			if timer <= 0:
				_finish_job()


func _finish_job() -> void:
	match job_kind:
		"wood":
			_set_cargo("wood")
			tree.take(position)
		"dig":
			var was := world.get_block(job_cell)
			Game.dig_done(job_task, job_cell)
			world.set_block(job_cell, World.AIR)
			if DIG_YIELD.has(was):
				_set_cargo(DIG_YIELD[was])
			_ensure_exit()  # digging beside us can cut the way out too
		"build":
			var bp: Dictionary = Game.blueprints[job_cell]
			Game.blueprint_done(job_cell)
			if Pieces.is_block(bp.item):
				world.set_block(job_cell, Pieces.block_type(bp.item))
			else:
				world.add_prop(job_cell, bp.item, bp.dir)
			_set_cargo("")
		"demolish":
			# ponytail: refunds one unit even for pieces that cost more (doors, posts)
			var refund := Game.demolish_refund(job_cell)
			Game.demolish_done(job_cell)
			if world.props.has(job_cell):
				world.remove_prop(job_cell)
			else:
				world.set_block(job_cell, World.AIR)
			_set_cargo(refund)
			_ensure_exit()
		"craft":
			world.set_station_active(job_cell, false)
			Game.stations[job_cell].claimed = false
			held.clear()
			var out: Dictionary = Crafting.RECIPES[job_recipe].out
			_set_cargo(out.keys()[0], out.values()[0])  # idle with cargo: hauls it to the stockpile
	job_kind = ""
	tree = null
	job_spot = NO_SPOT
	state = IDLE


func _think() -> void:
	if carrying != "":
		var tile = Game.deposit_tile(carrying, position)
		no_room = tile == null
		if tile != null:
			stock_tile = tile
			path = world.find_path(position, _tile_pos(stock_tile))
			state = TO_STOCK
		return
	if not _find_job():
		return
	tool.mesh = PeasantParts.mesh(TOOLS[job_kind])
	if job_kind == "build":
		var item: Dictionary = Pieces.ITEMS[Game.blueprints[job_cell].item]
		var tile = Game.withdraw_tile(item.mat, item.cost, position)
		if tile == null:
			_fail()  # the stock is split over tiles too small for this piece's cost
			return
		stock_tile = tile
		path = world.find_path(position, _tile_pos(stock_tile))
		state = FETCH
	elif job_kind == "craft":
		job_need = Crafting.RECIPES[job_recipe].in.duplicate()
		_next_ingredient()
	else:
		_go_to_job()


func _work_time() -> float:
	if job_kind == "craft":
		return Crafting.RECIPES[job_recipe].time
	if job_kind == "dig":
		match world.get_block(job_cell):
			World.STONE: return WORK_TIME.dig_stone
			World.IRON_ORE: return WORK_TIME.dig_ore
	return WORK_TIME[job_kind]


# Craft: walk to the next ingredient's tile, or to the station once everything is in hand.
func _next_ingredient() -> void:
	if job_need.is_empty():
		_go_to_job()
		return
	var kind: String = job_need.keys()[0]
	var tile = Game.withdraw_tile(kind, job_need[kind], position)
	if tile == null:
		_drop_job()  # someone else took it meanwhile
		return
	stock_tile = tile
	path = world.find_path(position, _tile_pos(stock_tile))
	state = GATHER


func _go_to_job() -> void:
	# Target cells are solid/blocked -> the path ends beside them.
	path = world.find_path(position, _tree_spot() if job_kind == "wood" else _job_target())
	state = TO_WORK


func _tile_pos(c: Vector3i) -> Vector3:
	return Vector3(c) + Vector3(0.5, 0, 0.5)


# Nearest free side of the tree (not taken by the other chopper); the tree itself if none.
func _tree_spot() -> Vector3:
	var taken := {}
	for o: Worker in get_tree().get_nodes_in_group("workers"):
		if o != self and o.tree == tree:
			taken[o.job_spot] = true
	var best := tree.position
	var best_d := INF
	job_spot = NO_SPOT
	for d in World.H_DIRS:
		for dy in [0, 1, -1]:
			var c := Vector3i(tree.position.floor()) + d + Vector3i(0, dy, 0)
			if not world.in_bounds(c) or not world.astar.has_point(world.idx(c)) \
					or world.astar.is_point_disabled(world.idx(c)):
				continue
			if not taken.has(c) and position.distance_squared_to(Vector3(c)) < best_d:
				best_d = position.distance_squared_to(Vector3(c))
				job_spot = c
				best = Vector3(c) + Vector3(0.5, 0, 0.5)
			break  # one standing height per side
	return best


# Idle on top of another villager: step to a random free cell next to us.
func _spread() -> void:
	for o: Worker in get_tree().get_nodes_in_group("workers"):
		if o != self and o.path.is_empty() and position.distance_squared_to(o.position) < 0.16:
			var d: Vector3i = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
				Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, -1)].pick_random()
			var c := Vector3i(position.floor()) + d
			if world.walkable(c) and not world.blocked.has(c):
				path = world.find_path(position, Vector3(c) + Vector3(0.5, 0, 0.5))
			return


# RimWorld rule: priority 1 works first; at equal priority, work-tab column order decides.
# Within one work type, the nearest job wins. Claims it.
func _find_job() -> bool:
	for level in range(1, 5):
		for work: String in Game.WORKS:
			if priorities[work] == level:
				var kind := _find_work(work)
				if kind:
					job_kind = kind
					return true
	return false


# Claims the nearest job of this work type; returns its job kind or "".
# ponytail: linear scans each idle frame; spatial lookup if counts reach thousands
func _find_work(work: String) -> String:
	var best_d := INF
	var kind := work
	match work:
		"wood":
			if not Game.has_room("wood"):
				return ""  # nowhere to put it
			for r: ResourceNode in get_tree().get_nodes_in_group("resources"):
				var d := position.distance_squared_to(r.position)
				if d < best_d and r.available() > 0 and r.claims < ResourceNode.MAX_CHOPPERS and not unreachable.has(r) \
						and Game.ordered("wood", Vector2i(floori(r.position.x), floori(r.position.z))):
					best_d = d
					tree = r
			if tree:
				tree.claims += 1
		"dig":
			for o in Game.orders:
				if o.kind != "dig" or o.paused:
					continue
				for c: Vector3i in o.cells:
					var d := position.distance_squared_to(Vector3(c))
					if d < best_d and not o.cells[c] and _diggable(c) and not unreachable.has(c):
						best_d = d
						job_cell = c
						job_task = o
			if best_d < INF:
				job_task.cells[job_cell] = true
		"craft":
			for base: Vector3i in Game.stations.keys():
				var st := Game.station(base)  # drops stations that were demolished
				if st.is_empty() or st.claimed or unreachable.has(base):
					continue
				var d := position.distance_squared_to(Vector3(base))
				if d < best_d:
					var id := Crafting.next_recipe(st)
					if id:
						best_d = d
						job_cell = base
						job_recipe = id
			if best_d < INF:
				Game.stations[job_cell].claimed = true
		"build":  # building and demolishing are both construction work
			for c: Vector3i in Game.blueprints:
				var bp: Dictionary = Game.blueprints[c]
				var d := position.distance_squared_to(Vector3(c))
				if d < best_d and not bp.claimed and Game.supported(c) and not unreachable.has(c) \
						and Game.has_stock(Pieces.ITEMS[bp.item].mat, Pieces.ITEMS[bp.item].cost):
					best_d = d
					job_cell = c
			for c: Vector3i in Game.demolish:
				var d := position.distance_squared_to(Vector3(c))
				if d < best_d and not Game.demolish[c] and not unreachable.has(c):
					best_d = d
					job_cell = c
					kind = "demolish"
			if best_d < INF:
				if kind == "demolish":
					Game.demolish[job_cell] = true
				else:
					Game.blueprints[job_cell].claimed = true
	return kind if best_d < INF else ""


# Dig top-down: the block must be exposed above and not hold a tree, blueprint or built piece
# (ladders are fine: a shaft keeps going under its ladder).
func _diggable(c: Vector3i) -> bool:
	var above := c + Vector3i.UP
	return world.is_solid(c) and not world.is_solid(above) and not world.blocked.has(above) \
		and not Game.planned.has(above) and (not world.props.has(above) or world.is_ladder(above))


func _job_valid() -> bool:
	match job_kind:
		"wood": return is_instance_valid(tree) and tree.amount > 0 \
			and Game.ordered("wood", Vector2i(floori(tree.position.x), floori(tree.position.z)))
		"dig": return not job_task.paused and job_task.cells.has(job_cell) and _diggable(job_cell)
		"build": return Game.blueprints.has(job_cell) and not world.is_solid(job_cell)
		"demolish": return Game.demolish.has(job_cell) and Game.demolish_target(job_cell) != null
		"craft": return not Game.station(job_cell).is_empty()
	return false


func _job_target() -> Vector3:
	if job_kind == "wood":
		return tree.position
	if job_kind == "craft":
		return Pieces.origin(Game.stations[job_cell].item, job_cell) + Vector3(0, 0.5, 0)
	return Vector3(job_cell) + Vector3(0.5, 0.5, 0.5)


func _in_reach() -> bool:
	var t := _job_target()
	if job_kind == "wood":
		return _near(t)
	if job_kind == "craft":  # stand anywhere next to the station's footprint
		var sz := Pieces.size(Game.stations[job_cell].item)
		return _near(t, maxi(sz.x, sz.z) / 2.0 + 1.3)
	var dy := job_cell.y - floori(position.y)
	return Vector2(t.x - position.x, t.z - position.z).length() <= REACH and dy >= -2 and dy <= 2


func _near(p: Vector3, r := 1.6) -> bool:
	return Vector2(p.x - position.x, p.z - position.z).length() <= r and absf(p.y - position.y) < 2


# Couldn't reach / do it: remember, release, try something else (cargo goes back to the stockpile).
func _fail() -> void:
	if job_kind == "wood" and tree:
		unreachable[tree] = true
	elif job_kind != "":
		unreachable[job_cell] = true
	_drop_job()


func _drop_job() -> void:
	match job_kind:
		"wood":
			if is_instance_valid(tree):
				tree.claims -= 1
		"dig":
			if job_task.cells.has(job_cell):
				job_task.cells[job_cell] = false
		"build":
			if Game.blueprints.has(job_cell):
				Game.blueprints[job_cell].claimed = false
		"demolish":
			if Game.demolish.has(job_cell):
				Game.demolish[job_cell] = false
		"craft":
			world.set_station_active(job_cell, false)
			if Game.stations.has(job_cell):
				Game.stations[job_cell].claimed = false
			# ponytail: ingredients in hand go straight back to the stockpile (no walk back)
			for kind: String in held:
				Game.store(kind, held[kind])
			held.clear()
			job_need.clear()
	job_kind = ""
	tree = null
	job_spot = NO_SPOT
	path.clear()
	state = IDLE


# Limb poses: walk swing, two-handed tool strike, arms forward when carrying.
func _animate() -> void:
	var walking := not path.is_empty()
	var swing := sin(anim_t * 12) * 0.7 if walking else 0.0
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	var feet := Vector3i(position.floor())
	if walking and world.is_ladder(feet) and absf(path[0].y - position.y) > 0.05:
		# Climbing: face the wall, hands alternate on the rungs.
		var d: Vector3i = world.props[feet].dir
		rotation.y = atan2(-d.x, -d.z)
		var climb := sin(anim_t * 10) * 0.4
		arm_l.rotation.x = 2.6 + climb
		arm_r.rotation.x = 2.6 - climb
		leg_l.rotation.x = climb
		leg_r.rotation.x = -climb
	elif state == WORKING:
		var c := fmod(anim_t * 1.4, 1.0)
		var a := lerpf(0.6, 2.8, c / 0.7) if c < 0.7 else lerpf(2.8, 0.6, (c - 0.7) / 0.3)  # slow raise, fast strike
		arm_l.rotation.x = a
		arm_r.rotation.x = a
	elif carrying != "" or not held.is_empty():
		arm_l.rotation.x = 1.3
		arm_r.rotation.x = 1.3
	else:
		arm_l.rotation.x = -swing * 0.7
		arm_r.rotation.x = swing * 0.7
	var loaded := carrying != "" or not held.is_empty()
	cargo.visible = loaded and state != WORKING
	tool.visible = job_kind != "" and (not loaded or state == WORKING)


func _set_cargo(kind: String, n := 1) -> void:
	carrying = kind
	carry_count = n if kind != "" else 0
	cargo.visible = kind != ""
	if kind != "":
		cargo.mesh = PeasantParts.mesh("cargo_" + kind)


# Face picture for the colonist bar.
func portrait() -> Texture2D:
	var head := MeshInstance3D.new()
	head.mesh = PeasantParts.mesh("head", look)
	return Game.render_icon("face_%d" % get_instance_id(), func() -> Node3D: return head,
		Vector3(0, 0.25, 0), 0.75, Vector3(0.6, 0.3, -2.0))  # face looks toward -Z


func _part(part: String, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = PeasantParts.mesh(part, look)
	m.position = pos
	add_child(m)
	return m


func _walk(delta: float) -> void:
	var to := path[0] - position
	var step := speed * delta
	if to.length() <= step:
		position = path[0]
		path.remove_at(0)
		if not path.is_empty():
			world.open_door(Vector3i(path[0].floor()))  # about to step through a door
	else:
		position += to.normalized() * step
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)

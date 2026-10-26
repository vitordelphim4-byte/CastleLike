class_name Worker
extends Node3D
## Peasant worker (Warcraft 3 style voxel model, animated limbs).
## RimWorld-style: picks jobs from global orders by its own work priorities (1 = first .. 4, 0 = never):
## chop trees in tree areas, dig marked blocks, build blueprints with material fetched from the
## stockpile, demolish marked constructions (Construction work, like RimWorld's deconstruct),
## work station bills (Crafting: fetch the ingredients, work at the station, haul the product),
## pick berries from bushes in harvest areas (Gathering), sow and harvest growing zones (Farming),
## shoot animals in hunting areas with a bow and butcher the corpses into raw meat (Hunting).
## Hunger (RimWorld-style, simple): `food` drains over a day; below HUNGRY the villager walks to the
## stockpile and eats before taking the next job. At 0 (no food anywhere) it walks and works at half
## speed.

enum { IDLE, MANUAL, TO_STOCK, TO_WORK, WORKING, FETCH, GATHER, TO_EAT, EATING }

const HUNGRY := 0.3
const EAT_TIME := 3.0
const STARVING_SLOWDOWN := 0.5
const WADE_SLOWDOWN := 0.5  # walking with the feet in water
const BOW_RANGE := 10.0  # hunters shoot from up to this far (farther than deer notice them)
const HIT_CHANCE := 0.75
const ARROW_SPEED := 25.0
const WORK_TIME := {"wood": 2.5, "gather": 2.0, "sow": 1.5, "harvest": 1.5, "hunt": 1.2, "butcher": 2.5, "dig": 1.2, "dig_stone": 2.0, "dig_ore": 2.5, "dig_deep": 3.5, "build": 1.0, "demolish": 1.0}
const S := PeasantParts.S
const DEFAULT_PRIORITY := 3
const TOOLS := {"wood": "axe", "dig": "pickaxe", "build": "hammer", "demolish": "hammer", "craft": "hammer"}
# Dug block -> resource. Coal ore gives the same charcoal the kiln makes (both burn).
const DIG_YIELD := {World.STONE: "stone", World.IRON_ORE: "iron_ore", World.DEEPSLATE: "stone", World.COAL_ORE: "charcoal"}
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
var prey: Node3D  # hunt: the animal we're after; butcher: the corpse
var forced := false  # player-ordered job (right click): ignores orders/priorities, then back to normal
var pending := {}  # {kind, target}: an order given while carrying; done after the cargo is put away
var returns := {}  # kind -> amount still in hand from an interrupted craft, walked back one kind at a time
var scared := 0.0  # seconds left running from a boar
var bow: MeshInstance3D
var tree: ResourceNode
var job_cell := Vector3i.ZERO
var job_task := {}
var stock_tile := Vector3i.ZERO  # stockpile tile we're taking cargo to / fetching material from
var no_room := false  # holding cargo with every stockpile tile full
var food := 1.0  # 1 = full, 0 = starving
var eat_count := 0
var eat_value := 0.0  # hunger filled per unit of what we're eating
var job_spot := NO_SPOT  # cell beside the tree we chop from, so two choppers don't overlap
var ring: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var tool: MeshInstance3D
var cargo: MeshInstance3D
var body: Node3D  # hip pivot holding torso, head and arms: bobs, leans and twists
var head: MeshInstance3D
var chips := CPUParticles3D.new()  # wood chips / dirt / stone dust at each strike
var _look_yaw := 0.0  # idle: where the head turns next
var _look_timer := 0.0
var _last_phase := 0.0
var scarf_mat := StandardMaterial3D.new()
const SILHOUETTE := preload("res://shaders/silhouette_mat.tres")  # outline when behind walls
var outline_parts: Array[MeshInstance3D] = []
var outlined := false


# On only while terrain hides us (InputCtrl checks): in plain view our own arms and the grass in
# front would light it up.
func set_outline(on: bool) -> void:
	if on == outlined:
		return
	outlined = on
	for m in outline_parts:
		m.material_overlay = SILHOUETTE if on else null


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
	body = Node3D.new()
	body.position = Vector3(0, 7 * S, 0)
	add_child(body)
	if look.get("female", false):
		_part("skirt", Vector3.ZERO, body)
	_part("torso", Vector3.ZERO, body)
	var scarf := _part("scarf", Vector3(0, 8 * S, 0), body)
	scarf_mat.vertex_color_use_as_albedo = true
	scarf_mat.vertex_color_is_srgb = true
	scarf_mat.albedo_color = color
	scarf.material_override = scarf_mat
	head = _part("head", Vector3(0, 9 * S, 0), body)
	arm_l = _part("arm", Vector3(-5 * S, 7.5 * S, 0), body)
	arm_r = _part("arm", Vector3(5 * S, 7.5 * S, 0), body)
	tool = MeshInstance3D.new()
	tool.position = Vector3(0, -6 * S, 0)
	tool.rotation.x = -PI / 2  # handle points forward when the arm hangs
	arm_r.add_child(tool)
	bow = MeshInstance3D.new()  # left hand, upright when the arm is raised to aim
	bow.mesh = PeasantParts.mesh("bow")
	bow.position = Vector3(0, -6 * S, 0)
	bow.rotation.x = -PI / 2
	bow.visible = false
	arm_l.add_child(bow)
	cargo = _part("cargo_wood", Vector3(0, 4 * S, -5 * S), body)
	_setup_chips()
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):  # before the ring
		m.set_instance_shader_parameter("tint", color)
		outline_parts.append(m)
	ring = Game.box(self, Vector3(1.0, 0.03, 1.0), Vector3(0, 0.02, 0), Color(0.2, 1, 0.3))
	ring.visible = false
	_set_cargo("")


# Player order: drop current job, walk there, then go back to work.
func move_to(target: Vector3) -> void:
	_drop_job()
	pending = {}
	path = world.find_path(position, target)
	state = MANUAL


# One line for the colonist bar: what this villager is doing right now.
func activity() -> String:
	var text := _activity()
	return "▶ " + text if forced and job_kind != "" else text


func _activity() -> String:
	var res: String = Game.RESOURCES[carrying].name if carrying else ""
	if no_room and state == IDLE:
		return "Sem espaço no estoque (%s)" % res
	if food <= 0 and state == IDLE:
		return "Faminto — sem comida!"
	if scared > 0:
		return "Fugindo do javali!"
	match state:
		TO_EAT:
			return "Indo comer"
		EATING:
			return "Comendo"
		MANUAL:
			return "Indo (sua ordem)"
		TO_STOCK:
			return "Guardando %s%s" % [res, " → depois a sua ordem" if pending else ""]
		FETCH:
			return "Buscando material"
		GATHER:
			return "Buscando %s" % Game.RESOURCES[job_need.keys()[0]].name if job_need else "Buscando ingredientes"
		TO_WORK, WORKING:
			var verb: String = "Indo " if state == TO_WORK else ""
			match job_kind:
				"wood": return verb + ("cortar árvore" if verb else "Cortando árvore")
				"gather": return verb + ("colher frutas" if verb else "Colhendo frutas")
				"sow": return verb + ("plantar" if verb else "Plantando")
				"hunt":
					var what: String = prey.display_name().to_lower() if is_instance_valid(prey) else ""
					return (verb + "caçar " if verb else "Caçando ") + what
				"butcher": return verb + ("limpar a caça" if verb else "Limpando a caça")
				"harvest":
					var t := Game.farm_tile(job_cell)
					var crop: String = Farming.CROPS[t.plant].name.to_lower() if t and t.plant else ""
					return (verb + "colher " if verb else "Colhendo ") + crop
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
	scared = maxf(0.0, scared - delta)
	# Hunting: stop walking as soon as the prey is in bow range.
	if job_kind == "hunt" and state == TO_WORK and not path.is_empty() and _job_valid() and _in_reach():
		path.clear()
	if Game.hunger:
		food = maxf(0.0, food - delta / Game.DAY_LENGTH)
	if not path.is_empty():
		_walk(delta)
	else:
		_settle()
		_update_state(delta)
	_animate(delta)


# Pop out of a block placed on us; fall into a hole dug under us. After landing, make sure
# we're not trapped.
func _settle() -> void:
	var feet := Vector3i(position.floor())
	if world.is_solid(feet):
		position.y = feet.y + 1
	elif World.is_water(world.get_block(feet)) and not world.wadeable(feet):
		# Swimming (deep water, or nothing under it): float up, then swim to the nearest footing.
		if World.is_water(world.get_block(feet + Vector3i.UP)):
			position.y = feet.y + 1
		else:
			var to := world.nearest_footing(position)
			if to != Vector3.INF:
				path = PackedVector3Array([to])
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
		TO_EAT:
			var t := Game.zone_tile(stock_tile)
			var per: float = Game.RESOURCES[t.kind].get("food", 0.0) if t and t.n > 0 else 0.0
			eat_count = mini(ceili((1.0 - food) / per), t.n) if per > 0 else 0
			eat_value = per
			if eat_count > 0 and _near(_tile_pos(stock_tile), 0.9) and Game.withdraw(stock_tile, t.kind, eat_count):
				state = EATING
				timer = EAT_TIME
				anim_t = 0
			else:
				state = IDLE
		EATING:
			timer -= delta
			if timer <= 0:
				food = minf(1.0, food + eat_count * eat_value)
				state = IDLE
		TO_WORK:
			if job_kind == "hunt":
				if not _job_valid():
					_end_hunt()
					return
				if not _in_reach():
					path = world.find_path(position, prey.position)  # it moved: follow
					if path.is_empty():
						_fail()
					return
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
				if job_kind == "hunt":
					_end_hunt()
				else:
					_drop_job()
				return
			var target := _job_target()
			rotation.y = atan2(position.x - target.x, position.z - target.z)
			timer -= delta * (STARVING_SLOWDOWN if food <= 0 else 1.0)
			if timer <= 0:
				_finish_job()


func _finish_job() -> void:
	match job_kind:
		"hunt":
			_shoot()
			state = TO_WORK  # keep after it until it's down
			return
		"butcher":
			_set_cargo("meat", Animal.SPECIES[prey.species].meat)
			prey.queue_free()
		"wood":
			_set_cargo("wood")
			tree.take(position)
		"gather":
			var n := tree.harvest()
			if n > 0:
				_set_cargo("berries", n)
		"sow":
			var t := Game.farm_tile(job_cell)
			t.plant = Game.farm_of(job_cell).crop
			t.sown = Game.now()
			t.claimed = false
			var soil := job_cell + Vector3i.DOWN
			if world.get_block(soil) in [World.GRASS, World.DIRT]:
				world.set_block(soil, World.FARMLAND)
			Game.orders_changed.emit()
		"harvest":
			var t := Game.farm_tile(job_cell)
			var crop: Dictionary = Farming.CROPS[t.plant]
			t.plant = ""
			t.claimed = false
			_set_cargo(crop.product, crop.yield)
			Game.orders_changed.emit()
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
	forced = false
	tree = null
	job_spot = NO_SPOT
	state = IDLE


func _think() -> void:
	if carrying == "" and returns:
		var kind: String = returns.keys()[0]
		_set_cargo(kind, returns[kind])
		returns.erase(kind)
	if carrying == "" and pending:
		var order := pending
		pending = {}
		if not (order.target is Object and not is_instance_valid(order.target)) and command(order.kind, order.target):
			return
	if carrying != "":
		var tile = Game.deposit_tile(carrying, position)
		no_room = tile == null
		if no_room:
			pending = {}  # nowhere to put the cargo: the order can't wait forever
		if tile != null:
			stock_tile = tile
			path = world.find_path(position, _tile_pos(stock_tile))
			state = TO_STOCK
		return
	if food < HUNGRY and _go_eat():
		return
	if not _find_job():
		return
	tool.mesh = PeasantParts.mesh(TOOLS[job_kind]) if TOOLS.has(job_kind) else null
	tool.rotation.y = AXE_TURN if job_kind == "wood" else 0.0
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


# Hungry: walk to the nearest stockpile tile with enough food to fill up (else any with food).
# False if there's no food anywhere.
func _go_eat() -> bool:
	var tile = Game.food_tile(position, 1.0 - food)
	if tile == null:
		return false
	stock_tile = tile
	path = world.find_path(position, _tile_pos(stock_tile))
	state = TO_EAT
	return true


# Player order (right click on a target): do this now, whatever the work tab says, then go back to
# normal work. kind: wood / gather (target = tree node), hunt / butcher (animal), harvest / dig
# (cell). Carrying something: walks it to the stockpile first, then does the order.
# False if it can't be done (nothing left to pick, block not diggable...).
func command(kind: String, target: Variant) -> bool:
	_drop_job()
	if carrying != "":
		pending = {"kind": kind, "target": target}  # put the cargo away first (_think), then do it
		return true
	match kind:
		"wood", "gather":
			if target.available() <= 0:
				return false
			tree = target
			tree.claims += 1
		"hunt":
			prey = target
		"butcher":
			if target.claimed:
				return false
			prey = target
			prey.claimed = true
		"harvest":
			job_cell = target
			Game.farm_tile(job_cell).claimed = true
		"dig":
			if not _diggable(target):
				return false
			job_cell = target
			# A one-block task of our own (not listed with the player's orders).
			job_task = {"kind": "dig", "area": Rect2i(), "paused": false, "cells": {job_cell: true}, "marker": null}
	job_kind = kind
	forced = true
	state = IDLE
	tool.mesh = PeasantParts.mesh(TOOLS[job_kind]) if TOOLS.has(job_kind) else null
	tool.rotation.y = AXE_TURN if job_kind == "wood" else 0.0
	_go_to_job()
	return true


# The prey is down (or left the hunting area). An ordered hunt carries on into butchering it.
func _end_hunt() -> void:
	var kill: Node3D = prey if forced and is_instance_valid(prey) and prey.state == Animal.DEAD else null
	_drop_job()
	if kill:
		command("butcher", kill)


# A boar hit us: drop the job and run away from it for a moment.
func scare(from: Node3D) -> void:
	_drop_job()
	var away := position - from.position
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	var to := position + away * 6.0
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = MANUAL
	scared = 2.5


# Loose an arrow at the prey; it hits (or lands near) when it arrives.
func _shoot() -> void:
	var target := prey
	var from := global_position + Vector3(0, 1.0, 0)
	var to: Vector3 = target.global_position + Vector3(0, 0.35, 0)
	var hit := randf() < HIT_CHANCE
	if not hit:
		to += Vector3(randf_range(-1.2, 1.2), -0.3, randf_range(-1.2, 1.2))
	var arrow := MeshInstance3D.new()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.03, 0.03, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.32, 0.2)
	shaft.material = mat
	arrow.mesh = shaft
	world.add_child(arrow)
	arrow.global_position = from
	arrow.look_at(to)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", to, from.distance_to(to) / ARROW_SPEED)
	tw.tween_callback(func() -> void:
		if hit and is_instance_valid(target):
			target.hurt(1, self)
		arrow.queue_free())


func _work_time() -> float:
	if job_kind == "craft":
		return Crafting.RECIPES[job_recipe].time
	if job_kind == "dig":
		match world.get_block(job_cell):
			World.STONE: return WORK_TIME.dig_stone
			World.IRON_ORE, World.COAL_ORE: return WORK_TIME.dig_ore
			World.DEEPSLATE: return WORK_TIME.dig_deep
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
	var to := _tree_spot() if job_kind in ["wood", "gather"] else _job_target()
	if job_kind == "hunt" or job_kind == "butcher":
		to = prey.position
	path = world.find_path(position, to)
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
			if priorities.get(work, 0) == level:
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
				if d < best_d and r.kind == "wood" and r.available() > 0 and r.claims < ResourceNode.MAX_CHOPPERS \
						and not unreachable.has(r) \
						and Game.ordered("wood", Vector2i(floori(r.position.x), floori(r.position.z))):
					best_d = d
					tree = r
			if tree:
				tree.claims += 1
		"hunt":  # corpses to butcher first, then animals inside hunting areas
			if not Game.has_room("meat"):
				return ""
			for c in get_tree().get_nodes_in_group("corpses"):
				var d := position.distance_squared_to(c.position)
				if d < best_d and not c.claimed and not unreachable.has(c):
					best_d = d
					prey = c
					kind = "butcher"
			if best_d == INF:
				for a in get_tree().get_nodes_in_group("animals"):
					var d := position.distance_squared_to(a.position)
					if d < best_d and not unreachable.has(a) and (a.marked \
							or Game.ordered("hunt", Vector2i(floori(a.position.x), floori(a.position.z)))):
						best_d = d
						prey = a
			if kind == "butcher":
				prey.claimed = true
		"farm":  # ripe crops first (RimWorld harvests before sowing), else the nearest empty tile
			var sow_d := INF
			var sow_cell := NO_SPOT
			for f in Game.farms:
				for c: Vector3i in f.tiles:
					var t: Dictionary = f.tiles[c]
					if t.claimed or unreachable.has(c):
						continue
					var d := position.distance_squared_to(Vector3(c))
					if t.plant != "":
						if d < best_d and Game.growth(t) >= 1.0 and Game.has_room(Farming.CROPS[t.plant].product):
							best_d = d
							job_cell = c
					elif d < sow_d:
						sow_d = d
						sow_cell = c
			kind = "harvest"
			if best_d == INF and sow_cell != NO_SPOT:
				best_d = sow_d
				job_cell = sow_cell
				kind = "sow"
			if best_d < INF:
				Game.farm_tile(job_cell).claimed = true
		"gather":
			if not Game.has_room("berries"):
				return ""
			for r: ResourceNode in get_tree().get_nodes_in_group("resources"):
				var d := position.distance_squared_to(r.position)
				if d < best_d and r.kind == "berries" and r.claims == 0 and r.available() > 0 and not unreachable.has(r) \
						and Game.ordered("gather", Vector2i(floori(r.position.x), floori(r.position.z))):
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


# The block must be exposed (open above, or on a side: tunnels into hills) and not hold a tree,
# blueprint or built piece (ladders are fine: a shaft keeps going under its ladder).
func _diggable(c: Vector3i) -> bool:
	var above := c + Vector3i.UP
	if not world.is_solid(c) or world.get_block(c) == World.BEDROCK or world.blocked.has(above) or Game.planned.has(above) \
			or (world.props.has(above) and not world.is_ladder(above)):
		return false
	if not world.is_solid(above):
		return true
	for d in World.H_DIRS:
		if not world.is_solid(c + d):
			return true
	return false


func _job_valid() -> bool:
	match job_kind:
		"gather": return is_instance_valid(tree) and tree.amount > 0 \
			and (forced or Game.ordered("gather", Vector2i(floori(tree.position.x), floori(tree.position.z))))
		"wood": return is_instance_valid(tree) and tree.amount > 0 \
			and (forced or Game.ordered("wood", Vector2i(floori(tree.position.x), floori(tree.position.z))))
		"dig": return not job_task.paused and job_task.cells.has(job_cell) and _diggable(job_cell)
		"build": return Game.blueprints.has(job_cell) and not world.is_solid(job_cell)
		"demolish": return Game.demolish.has(job_cell) and Game.demolish_target(job_cell) != null
		"craft": return not Game.station(job_cell).is_empty()
		"hunt": return is_instance_valid(prey) and prey.state != Animal.DEAD and (forced or prey.marked \
			or Game.ordered("hunt", Vector2i(floori(prey.position.x), floori(prey.position.z))))
		"butcher": return is_instance_valid(prey) and prey.state == Animal.DEAD
		"sow": return Game.farm_tile(job_cell).get("plant", "x") == ""
		"harvest":
			var t := Game.farm_tile(job_cell)
			return t and t.plant != "" and Game.growth(t) >= 1.0
	return false


func _job_target() -> Vector3:
	if job_kind == "wood" or job_kind == "gather":
		return tree.position
	if job_kind == "craft":
		return Pieces.origin(Game.stations[job_cell].item, job_cell) + Vector3(0, 0.5, 0)
	if job_kind == "hunt" or job_kind == "butcher":
		return prey.position + Vector3(0, 0.4, 0)
	return Vector3(job_cell) + Vector3(0.5, 0.5, 0.5)


func _in_reach() -> bool:
	var t := _job_target()
	if job_kind == "wood" or job_kind == "gather":
		return _near(t)
	if job_kind == "sow" or job_kind == "harvest":
		return _near(t, 1.2)
	if job_kind == "hunt":
		return _near(t, BOW_RANGE) and absf(t.y - position.y) < 4.0
	if job_kind == "butcher":
		return _near(t, 1.4)
	if job_kind == "craft":  # stand anywhere next to the station's footprint
		var sz := Pieces.size(Game.stations[job_cell].item)
		return _near(t, maxi(sz.x, sz.z) / 2.0 + 1.3)
	var dy := job_cell.y - floori(position.y)
	return Vector2(t.x - position.x, t.z - position.z).length() <= REACH and dy >= -2 and dy <= 2


func _near(p: Vector3, r := 1.6) -> bool:
	return Vector2(p.x - position.x, p.z - position.z).length() <= r and absf(p.y - position.y) < 2


# Couldn't reach / do it: remember, release, try something else (cargo goes back to the stockpile).
func _fail() -> void:
	if job_kind in ["wood", "gather"] and tree:
		unreachable[tree] = true
	elif job_kind in ["hunt", "butcher"] and is_instance_valid(prey):
		unreachable[prey] = true
	elif job_kind != "":
		unreachable[job_cell] = true
	_drop_job()


func _drop_job() -> void:
	match job_kind:
		"wood", "gather":
			if is_instance_valid(tree):
				tree.claims = maxi(0, tree.claims - 1)
		"dig":
			if job_task.cells.has(job_cell):
				job_task.cells[job_cell] = false
		"build":
			if Game.blueprints.has(job_cell):
				Game.blueprints[job_cell].claimed = false
		"demolish":
			if Game.demolish.has(job_cell):
				Game.demolish[job_cell] = false
		"sow", "harvest":
			var t := Game.farm_tile(job_cell)
			if t:
				t.claimed = false
		"butcher":
			if is_instance_valid(prey):
				prey.claimed = false
		"craft":
			world.set_station_active(job_cell, false)
			if Game.stations.has(job_cell):
				Game.stations[job_cell].claimed = false
			for kind: String in held:  # carried back to the stockpile (_think), one kind per trip
				returns[kind] = returns.get(kind, 0) + held[kind]
			held.clear()
			job_need.clear()
	job_kind = ""
	forced = false
	tree = null
	prey = null
	job_spot = NO_SPOT
	path.clear()
	state = IDLE


# Procedural animation. Each frame picks a target pose (limb angles, body lean/twist/height, head
# turn) for what we're doing, then every part eases toward it, so changes blend instead of snapping.
# Rotations: +x on an arm/leg swings it forward (up), -x on the body leans forward.
const HEAVY := ["stone", "iron_ore", "iron"]  # carried in both arms, heavy step
const LIGHT := ["berries", "charcoal"]  # carried in one hand
const BLEND := 14.0  # how fast parts ease toward the pose (higher = snappier)
const AXE_TURN := deg_to_rad(45.0)  # axe turned left around the arm so the side swing leads with the blade


func _animate(delta: float) -> void:
	var walking := not path.is_empty()
	var loaded := carrying != "" or not held.is_empty()
	var load_kind: String = carrying if carrying != "" else (held.keys().back() if held else "")
	var heavy := loaded and load_kind in HEAVY
	var step := sin(anim_t * (9.0 if heavy else 12.0))
	var swing := step * (0.45 if heavy else 0.7) if walking else 0.0
	var pose := {
		"leg_l": Vector3(swing, 0, 0), "leg_r": Vector3(-swing, 0, 0),
		"arm_l": Vector3(-swing * 0.7, 0, 0.05), "arm_r": Vector3(swing * 0.7, 0, -0.05),
		"body": Vector3(-0.06 if walking else 0.0, 0, step * 0.04 if walking else 0.0),
		"body_y": absf(step) * 0.7 * S if walking else sin(anim_t * 2.0) * 0.25 * S,  # bob / breathe
		"head": Vector3.ZERO,
	}
	var feet := Vector3i(position.floor())
	if walking and world.is_ladder(feet) and absf(path[0].y - position.y) > 0.05:
		# Climbing: face the wall, hands alternate on the rungs.
		var d: Vector3i = world.props[feet].dir
		rotation.y = atan2(-d.x, -d.z)
		var climb := sin(anim_t * 10) * 0.4
		pose.arm_l = Vector3(2.6 + climb, 0, 0)
		pose.arm_r = Vector3(2.6 - climb, 0, 0)
		pose.leg_l = Vector3(climb + 0.3, 0, 0)
		pose.leg_r = Vector3(-climb + 0.3, 0, 0)
		pose.body = Vector3.ZERO
		pose.head = Vector3(-0.3, 0, 0)  # looking up the ladder
	elif state == WORKING:
		_work_pose(pose)
	elif state == EATING:  # hand to mouth, chewing nods
		pose.arm_l = Vector3(0.6, 0, 0.1)
		pose.arm_r = Vector3(2.4 + sin(anim_t * 6) * 0.3, 0, -0.25)
		pose.head = Vector3(0.1 + sin(anim_t * 6) * 0.08, 0, 0)
	elif loaded:
		if load_kind == "wood":  # log on the right shoulder
			pose.arm_r = Vector3(2.9, 0, -0.5)
		elif load_kind in LIGHT:  # one hand
			pose.arm_r = Vector3(1.2, 0, -0.1)
		else:  # both arms, leaning back against the weight
			pose.arm_l = Vector3(1.3, 0, 0.1)
			pose.arm_r = Vector3(1.3, 0, -0.1)
			pose.body.x = 0.1
	elif not walking:
		# Idle: look around now and then.
		_look_timer -= delta
		if _look_timer <= 0:
			_look_timer = randf_range(2.0, 5.0)
			_look_yaw = randf_range(-0.7, 0.7) if randf() < 0.7 else 0.0
		pose.head = Vector3(0, _look_yaw, 0)
	if food < HUNGRY and state != EATING:
		pose.head.x += 0.25  # hungry: head down
	var k := 1.0 - exp(-BLEND * delta)
	leg_l.rotation = leg_l.rotation.lerp(pose.leg_l, k)
	leg_r.rotation = leg_r.rotation.lerp(pose.leg_r, k)
	arm_l.rotation = arm_l.rotation.lerp(pose.arm_l, k)
	arm_r.rotation = arm_r.rotation.lerp(pose.arm_r, k)
	body.rotation = body.rotation.lerp(pose.body, k)
	body.position.y = lerpf(body.position.y, 7 * S + pose.body_y, k)
	head.rotation = head.rotation.lerp(pose.head, k)
	_place_cargo(load_kind)
	cargo.visible = loaded and state != WORKING
	tool.visible = tool.mesh != null and job_kind != "" and (not loaded or state == WORKING)
	bow.visible = job_kind == "hunt" and not loaded


# Tool work: slow wind-up, fast strike, chips fly at the moment of impact.
func _work_pose(pose: Dictionary) -> void:
	match job_kind:
		"wood":  # axe: side swing from over the right shoulder, body twisting into it
			var t := _strike(1.3)
			pose.arm_l = Vector3(lerpf(1.1, 2.2, t), 0, lerpf(0.2, -0.3, t))
			pose.arm_r = Vector3(lerpf(1.1, 2.3, t), 0, lerpf(0.0, -0.5, t))
			pose.body = Vector3(-0.1, lerpf(-0.35, 0.55, t), 0)
		"dig", "demolish":  # pickaxe / sledge: overhead, bending into the blow
			var t := _strike(1.2)
			pose.arm_l = Vector3(lerpf(0.5, 3.0, t), 0, 0.1)
			pose.arm_r = Vector3(lerpf(0.5, 3.0, t), 0, -0.1)
			pose.body = Vector3(lerpf(-0.4, 0.15, t), 0, 0)
			pose.head = Vector3(0.2, 0, 0)
		"build", "craft":  # hammer: quick one-handed taps, other hand steadying the work
			var t := _strike(2.4)
			pose.arm_l = Vector3(1.1, 0, 0.15)
			pose.arm_r = Vector3(lerpf(1.0, 2.2, t), 0, -0.1)
			pose.body = Vector3(-0.15, 0, 0)
			pose.head = Vector3(0.25, 0, 0)
		"hunt":  # bow up in the left hand, right hand drawing the string back
			var draw := clampf(1.0 - timer / WORK_TIME.hunt, 0.0, 1.0)
			pose.arm_l = Vector3(1.55, 0, 0.15)
			pose.arm_r = Vector3(1.5, 0, lerpf(-0.1, 0.55, draw))
			pose.body = Vector3(0, -0.25, 0)
			pose.head = Vector3(0, 0.2, 0)
		"gather", "sow", "harvest", "butcher":  # crouch, hands picking / planting / cutting in turn
			pose.leg_l = Vector3(0.9, 0, 0)
			pose.leg_r = Vector3(0.9, 0, 0)
			pose.body_y = -2.5 * S
			pose.body = Vector3(-0.35, 0, 0)
			pose.arm_l = Vector3(1.4 + sin(anim_t * 5) * 0.35, 0, 0.1)
			pose.arm_r = Vector3(1.4 - sin(anim_t * 5) * 0.35, 0, -0.1)
			pose.head = Vector3(0.35, 0, 0)


# Strike cycle at `rate` per second: 0 = tool down at the target, 1 = fully raised. Raising takes
# 70% of the cycle, the blow the last 30%; the impact (cycle wrapping) throws chips.
func _strike(rate: float) -> float:
	var c := fmod(anim_t * rate, 1.0)
	if anim_t < 0.05:
		_last_phase = c  # new job: no impact on the first frame
	if c < _last_phase:
		_hit()
	_last_phase = c
	return c / 0.7 if c < 0.7 else 1.0 - (c - 0.7) / 0.3


func _hit() -> void:
	var col := Color(0.62, 0.45, 0.25)  # wood chips
	match job_kind:
		"dig":
			var b := world.get_block(job_cell)
			col = World.COLORS.get(b, Color(0.45, 0.3, 0.18))
			if b == World.GRASS:
				col = World.COLORS[World.DIRT]
		"build", "craft", "demolish":
			col = Color(0.75, 0.72, 0.68)  # dust
		"gather", "sow", "harvest", "hunt", "butcher":
			return
	chips.color = col
	chips.global_position = _job_target()
	chips.restart()


func _setup_chips() -> void:
	chips.top_level = true  # stays where the strike landed
	chips.emitting = false
	chips.one_shot = true
	chips.amount = 6
	chips.lifetime = 0.6
	chips.explosiveness = 1.0
	chips.direction = Vector3.UP
	chips.spread = 60.0
	chips.initial_velocity_min = 1.5
	chips.initial_velocity_max = 2.5
	chips.gravity = Vector3(0, -9, 0)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.06
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	cube.material = mat
	chips.mesh = cube
	add_child(chips)


# Cargo sits where it's carried: log across the right shoulder, light goods in the right hand,
# heavy ones held in front.
func _place_cargo(kind: String) -> void:
	if kind == "wood":
		cargo.position = Vector3(3 * S, 8.5 * S, 0)
		cargo.rotation = Vector3(0, PI / 2, 0)
	elif kind in LIGHT:
		cargo.position = Vector3(5 * S, 1.5 * S, -3 * S)
		cargo.rotation = Vector3.ZERO
	else:
		cargo.position = Vector3(0, 4 * S, -5 * S)
		cargo.rotation = Vector3.ZERO


func _set_cargo(kind: String, n := 1) -> void:
	carrying = kind
	carry_count = n if kind != "" else 0
	cargo.visible = kind != ""
	if kind != "":
		cargo.mesh = PeasantParts.mesh("cargo_" + kind)


# Face picture for the colonist bar.
func portrait() -> Texture2D:
	var face := MeshInstance3D.new()
	face.mesh = PeasantParts.mesh("head", look)
	return Game.render_icon("face_%d" % get_instance_id(), func() -> Node3D: return face,
		Vector3(0, 0.25, 0), 0.75, Vector3(0.6, 0.3, -2.0))  # face looks toward -Z


func _part(part: String, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = PeasantParts.mesh(part, look)
	m.position = pos
	parent.add_child(m)
	return m


func _walk(delta: float) -> void:
	var to := path[0] - position
	var step := speed * delta * (STARVING_SLOWDOWN if food <= 0 else 1.0)
	if World.is_water(world.get_block(Vector3i(position.floor()))):
		step *= WADE_SLOWDOWN
	if to.length() <= step:
		position = path[0]
		path.remove_at(0)
		if not path.is_empty():
			world.open_door(Vector3i(path[0].floor()))  # about to step through a door
	else:
		position += to.normalized() * step
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)

class_name Mob
extends Node3D
## Hostile monster (Phase 13, debug map only for now: spawned from the F1 panel).
## Rethinks every THINK seconds: picks a target (villagers that are up and outside, wolves also
## deer and rabbits), then chases, attacks, backs off or circles depending on its kind:
##   zombie: slow, never gives up, calls the zombies around it (horde); its grab slows the victim.
##   skeleton (warrior): goes for the guards first; its shield stops some arrows from the front.
##   skeleton_archer: shoots from range with a clear line, backs off when someone comes close,
##     prefers villagers standing still at work.
##   wolf: hunts in packs (alone it circles at a distance), picks the villager farthest from the
##     guards, bites and steps back, runs away when badly hurt.
## Whoever hits it becomes its target (taunt): that's how a soldier pulls it off a peasant.
## Dead mobs lie down and vanish after a while.

const KINDS := {
	"zombie": {"name": "Zumbi", "hp": 6, "speed": 2.0, "dmg": 1, "reach": 1.2, "cooldown": 1.5, "sight": 14.0,
		"look": {"skin": Color(0.45, 0.62, 0.36), "hair": Color(0.16, 0.2, 0.12), "shirt": Color(0.35, 0.42, 0.55),
			"vest": Color(0.3, 0.24, 0.18)}},
	"skeleton": {"name": "Esqueleto guerreiro", "hp": 5, "speed": 3.5, "dmg": 2, "reach": 1.3, "cooldown": 1.2,
		"sight": 16.0, "weapon": "sword", "shield": 0.4,
		"look": {"skin": Color(0.88, 0.86, 0.78), "hair": Color(0.88, 0.86, 0.78), "shirt": Color(0.8, 0.78, 0.7),
			"vest": Color(0.42, 0.4, 0.36)}},
	"skeleton_archer": {"name": "Esqueleto arqueiro", "hp": 3, "speed": 3.0, "dmg": 1, "reach": 12.0, "cooldown": 2.0,
		"sight": 18.0, "weapon": "bow", "ranged": true,
		"look": {"skin": Color(0.88, 0.86, 0.78), "hair": Color(0.88, 0.86, 0.78), "shirt": Color(0.8, 0.78, 0.7),
			"vest": Color(0.3, 0.3, 0.34)}},
	"wolf": {"name": "Lobo", "hp": 3, "speed": 6.0, "dmg": 1, "reach": 1.1, "cooldown": 1.0, "sight": 16.0, "pack": true},
}
enum { IDLE, WANDER, CHASE, ATTACK, KITE, CIRCLE, FLEE, DEAD }
const STATE_NAMES := ["parado", "vagando", "perseguindo", "atacando", "recuando", "rodeando", "fugindo", "morto"]
const THINK := 0.5
const HORDE := 10.0  # zombies this close join a zombie that found a target
const KITE_DIST := 5.0  # archer: backs off when a target is closer than this
const CIRCLE_DIST := 6.0  # lone wolf: circles its prey this far out
const PACK_RADIUS := 12.0  # wolves this close count as one pack
const FLEE_HP := 0.4  # wolf: runs away below this share of its hp
const ROT_TIME := 10.0  # dead body stays this long
const S := PeasantParts.S

static var show_ai := false  # debug panel: label over each mob with its state and target

var kind := "zombie"
var world: World
var hp := 1
var state := IDLE
var target: Node3D
var path := PackedVector3Array()
var timer := 0.0  # wander: wait before the next stroll
var think := 0.0
var cool := 0.0  # seconds before the next attack
var anim_t := 0.0
var circle_a := 0.0  # wolf: where on the circle around the prey it heads next
var fled := false  # wolf: badly hurt, keeps away for good
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var label: Label3D


func _ready() -> void:
	add_to_group("mobs")
	var k: Dictionary = KINDS[kind]
	hp = k.hp
	if kind == "wolf":
		_build_wolf()
	else:
		_build_humanoid(k)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 6
	label.pixel_size = 0.006
	label.position.y = 2.1
	label.visible = show_ai
	add_child(label)
	think = randf() * THINK  # don't all think on the same frame


func display_name() -> String:
	return KINDS[kind].name


func _process(delta: float) -> void:
	anim_t += delta
	label.visible = show_ai
	if state == DEAD:
		return
	cool = maxf(0.0, cool - delta)
	think -= delta
	if think <= 0:
		think = THINK
		_think()
	if state == ATTACK:
		_attack()
	elif not path.is_empty():
		var fast := state in [CHASE, KITE, FLEE, CIRCLE]
		_walk(delta, KINDS[kind].speed * (1.0 if fast else 0.4))
	elif state in [IDLE, WANDER]:
		state = IDLE
		timer -= delta
		if timer <= 0:
			_wander()
	if show_ai:
		label.text = "%s · %s · %d hp%s" % [display_name(), STATE_NAMES[state], hp,
			"\n→ " + target.display_name() if _ok(target) else ""]
	_animate(delta)


# Hit by a villager (sword, arrow) or the debug panel (attacker null).
func hurt(dmg: int, attacker: Node3D) -> void:
	if state == DEAD:
		return
	var k: Dictionary = KINDS[kind]
	if attacker and k.get("shield", 0.0) > 0 and position.distance_to(attacker.position) > 2.5:
		var to := attacker.position - position
		var front := -global_transform.basis.z
		if front.dot(Vector3(to.x, 0, to.z).normalized()) > 0.3 and randf() < k.shield:
			return  # arrow from the front: on the shield
	hp -= dmg
	if hp <= 0:
		_die()
		return
	if k.get("pack", false) and hp <= k.hp * FLEE_HP:
		fled = true
		_away_from(attacker.position if attacker else position + Vector3.FORWARD, 12.0, FLEE)
		return
	if attacker and _ok(attacker):
		target = attacker
		think = 0.0  # react now


func _die() -> void:
	state = DEAD
	path.clear()
	target = null
	remove_from_group("mobs")
	var tw := create_tween()
	tw.tween_property(self, "rotation", Vector3(0, rotation.y, PI / 2), 0.4).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(ROT_TIME)
	tw.tween_callback(queue_free)


# Can be attacked: a villager that's up and outside, or (wolves) a live wild animal.
static func _ok(t: Node3D) -> bool:
	if not is_instance_valid(t):
		return false
	if t is Worker:
		return t.targetable()
	return t.is_in_group("animals")


func _think() -> void:
	if Game.mobs_passive:
		target = null
		if state not in [IDLE, WANDER]:
			state = IDLE
			path.clear()
		return
	var k: Dictionary = KINDS[kind]
	if state == FLEE and not path.is_empty():
		return
	if fled:  # wounded wolf: only wanders now
		if state not in [IDLE, WANDER]:
			state = IDLE
		return
	if not _ok(target) or (kind != "zombie" and position.distance_to(target.position) > k.sight * 1.5):
		target = _pick_target()
		if target and kind == "zombie":
			for z in get_tree().get_nodes_in_group("mobs"):
				if z != self and z.kind == "zombie" and not _ok(z.target) and z.position.distance_to(position) < HORDE:
					z.target = target
	if not target:
		if state not in [IDLE, WANDER]:
			state = IDLE
			path.clear()
		return
	var d := position.distance_to(target.position)
	if k.get("ranged", false):
		if d < KITE_DIST:
			_away_from(target.position, 6.0, KITE)
		elif d <= k.reach and Mob.clear_line(world, position, target.position):
			state = ATTACK
			path.clear()
		else:
			_chase()
		return
	if kind == "wolf":
		if state == KITE and not path.is_empty():
			return  # stepping back after a bite
		if _pack_size() < 2 and target is Worker:
			_circle()
			return
	if d <= k.reach:
		state = ATTACK
		path.clear()
	else:
		_chase()


func _pick_target() -> Node3D:
	var k: Dictionary = KINDS[kind]
	var guards := get_tree().get_nodes_in_group("workers").filter(func(w: Worker) -> bool: return w.armed() != "")
	var best: Node3D = null
	var best_s := INF
	var options: Array = get_tree().get_nodes_in_group("workers")
	if kind == "wolf":
		options = options + get_tree().get_nodes_in_group("animals").filter(
			func(a: Animal) -> bool: return not Animal.SPECIES[a.species].get("aggressive", false))
	for t: Node3D in options:
		var d := position.distance_to(t.position)
		if d > k.sight or not _ok(t):
			continue
		var s := d
		match kind:
			"skeleton":
				if t in guards:
					s -= 100.0  # guards first
			"skeleton_archer":
				if not Mob.clear_line(world, position, t.position):
					continue
				if t is Worker and t.state == Worker.WORKING:
					s -= 4.0  # standing still: easy shot
			"wolf":
				var guard_d := 30.0
				for g: Worker in guards:
					guard_d = minf(guard_d, g.position.distance_to(t.position))
				s -= guard_d  # the farther from the guards, the better
				if t is Worker:
					s -= 6.0  # villagers over game
		if s < best_s:
			best_s = s
			best = t
	return best


func _chase() -> void:
	state = CHASE
	path = world.find_path(position, target.position)


# Run (or back off) dist away from `from`.
func _away_from(from: Vector3, dist: float, as_state: int) -> void:
	var away := position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	var to := position + away * dist
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = as_state


# Lone wolf: walk around the prey at CIRCLE_DIST, waiting for the pack.
func _circle() -> void:
	circle_a += 0.6
	var c := target.position
	var to := c + Vector3(cos(circle_a), 0, sin(circle_a)) * CIRCLE_DIST
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = CIRCLE


func _pack_size() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("mobs"):
		if m.kind == "wolf" and not m.fled and m.position.distance_to(position) < PACK_RADIUS:
			n += 1
	return n


func _attack() -> void:
	if not _ok(target):
		state = IDLE
		return
	var k: Dictionary = KINDS[kind]
	var to := target.position - position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)
	if to.length() > k.reach + 0.5:
		think = 0.0  # it got away
		return
	if cool > 0:
		return
	cool = k.cooldown
	anim_t = 0.0  # strike animation from the start
	if k.get("ranged", false):
		Worker.shoot(self, target, k.dmg)
		return
	target.hurt(k.dmg, self)
	if kind == "zombie" and target is Worker:
		target.slowed = 2.0
	if kind == "wolf":  # hit and run
		_away_from(target.position, 3.0, KITE)


# Samples the segment at chest height: no solid block in the way.
# ponytail: point sampling every 0.25, a voxel DDA if it gets slow or misses corners
static func clear_line(w: World, a: Vector3, b: Vector3) -> bool:
	var from := a + Vector3(0, 1.2, 0)
	var to := b + Vector3(0, 1.0, 0)
	var n := ceili(from.distance_to(to) / 0.25)
	for i in range(1, n):
		if w.is_solid(Vector3i(from.lerp(to, float(i) / n).floor())):
			return false
	return true


func _wander() -> void:
	var to := position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	to.y = world.top_at(floori(to.x), floori(to.z))
	path = world.find_path(position, to)
	state = WANDER if not path.is_empty() else IDLE
	timer = randf_range(2.0, 6.0)


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


func _animate(_delta: float) -> void:
	var moving := not path.is_empty()
	var rate := 14.0 if state in [CHASE, KITE, FLEE, CIRCLE] else 8.0
	var swing := sin(anim_t * rate) * 0.6 if moving else 0.0
	if kind == "wolf":
		for i in legs.size():
			legs[i].rotation.x = swing * (1 if i in [0, 3] else -1)
		return
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
	var strike := state == ATTACK and anim_t < 0.4
	match kind:
		"zombie":  # arms stretched out in front, reaching
			arms[0].rotation.x = 1.5 + swing * 0.15
			arms[1].rotation.x = 1.5 - swing * 0.15 + (0.6 if strike else 0.0)
		"skeleton_archer":
			var aim := state == ATTACK
			arms[0].rotation.x = 1.55 if aim else -swing * 0.7
			arms[1].rotation.x = 1.5 if aim else swing * 0.7
		_:  # sword: raised, then swung down
			arms[0].rotation.x = -swing * 0.7
			arms[1].rotation.x = (2.6 - anim_t * 5.0) if strike else swing * 0.7


# Peasant body (PeasantParts) with the mob's colors, weapon in hand.
func _build_humanoid(k: Dictionary) -> void:
	var look: Dictionary = k.look
	legs.append(_part("leg", Vector3(-1.5 * S, 7 * S, 0), look, self))
	legs.append(_part("leg", Vector3(1.5 * S, 7 * S, 0), look, self))
	var body := Node3D.new()
	body.position = Vector3(0, 7 * S, 0)
	add_child(body)
	_part("torso", Vector3.ZERO, look, body)
	_part("head", Vector3(0, 9 * S, 0), look, body)
	arms.append(_part("arm", Vector3(-5 * S, 7.5 * S, 0), look, body))
	arms.append(_part("arm", Vector3(5 * S, 7.5 * S, 0), look, body))
	if k.has("weapon"):
		var wpn := MeshInstance3D.new()
		wpn.mesh = PeasantParts.mesh(k.weapon)
		wpn.position = Vector3(0, -6 * S, 0)
		wpn.rotation.x = -PI / 2
		(arms[0] if k.weapon == "bow" else arms[1]).add_child(wpn)


func _part(part: String, pos: Vector3, look: Dictionary, parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = PeasantParts.mesh(part, look)
	m.position = pos
	parent.add_child(m)
	return m


# Grey quadruped from Animal's voxel builder (its "wolf" entry is mesh only, never spawned there).
func _build_wolf() -> void:
	var sp: Dictionary = Animal.SPECIES.wolf
	var vs := Animal.VS
	var b: Vector3i = sp.body
	var l: Vector3i = sp.leg
	var body := MeshInstance3D.new()
	body.mesh = Animal._build("wolf", "body")
	body.position.y = l.y * vs
	add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = Animal._build("wolf", "head")
	head.position = Vector3(0, (b.y - 1) * vs, -b.z / 2.0 * vs)
	body.add_child(head)
	var leg_mesh := Animal._build("wolf", "leg")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.position = Vector3(sx * (b.x / 2.0 - l.x / 2.0 - 0.5) * vs, l.y * vs, sz * (b.z / 2.0 - l.x / 2.0 - 1) * vs)
			add_child(leg)
			legs.append(leg)


static func spawn(parent: Node, w: World, k: String, pos: Vector3) -> Mob:
	var m := Mob.new()
	m.kind = k
	m.world = w
	m.position = pos
	m.rotation.y = randf() * TAU
	parent.add_child(m)
	return m

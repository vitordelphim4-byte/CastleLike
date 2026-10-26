class_name Fluids
extends Node
## Minecraft-style water (Phase 10e1), without the infinite-source rule. World.WATER is a source
## (level 8), FLOW_1..FLOW_7 flowing water, FALLING a falling column. Every TICK, cells that changed
## or sit next to a change are updated:
## - a source stays (sources are only placed / removed by hand, never made);
## - other water keeps only the level its neighbors give it: falling if water is right above it,
##   else the best sideways neighbor minus 1 (a source or falling column gives 7), or dries up;
## - water falls first (into air or flowing water below); only if it can't, it spreads sideways one
##   level lower, toward the nearest drop within SEEK blocks when there is one, else all around.
## Still water costs nothing: only the active cells are simulated.

const TICK := 0.25  # s of game time between steps (Minecraft: 5 ticks)
const MAX_CELLS := 4000  # updated per step; the rest wait for the next one
const SEEK := 4  # how far sideways water looks for a drop

var world: World
var active := {}  # Vector3i -> true: cells to update next step
var speed := 1.0  # debug: x10
var _t := 0.0


func _process(delta: float) -> void:
	if active.is_empty():
		return
	_t += delta * speed
	if _t >= TICK:
		_t = 0.0
		step()


# A cell (and its neighbors) may have to change: dug, built, or its water changed.
func wake(p: Vector3i) -> void:
	active[p] = true
	for d in VoxelMesh.DIRS:
		active[p + d] = true


# One update of every active cell. Reads the world as it was, then applies all changes at once.
func step() -> void:
	var cells: Array = active.keys()
	if cells.size() > MAX_CELLS:
		cells = cells.slice(0, MAX_CELLS)
	for p: Vector3i in cells:
		active.erase(p)
	var changes := {}
	for p: Vector3i in cells:
		if world.in_bounds(p):
			_update(p, changes)
	if not changes.is_empty():
		world.apply_water(changes)


func _update(p: Vector3i, changes: Dictionary) -> void:
	var t := world.get_block(p)
	if not World.is_water(t):
		return  # dry cells only get water pushed into them (so it can prefer a direction)
	var level := World.water_level(t)
	if t != World.WATER:  # sources stay; the rest follow their neighbors
		var want := _support(p)
		if want != level or (want == 8) != (t == World.FALLING):
			_put(changes, p, _type(want, want == 8))
		level = want
		t = _type(want, want == 8)
	if level == 0:
		return
	var below := p + Vector3i.DOWN
	if _takes(below, 8):
		_put(changes, below, World.FALLING)
		return
	if _falls_through(below):
		return  # lands on water that's still falling: no spreading from here
	var side := 7 if t == World.WATER or t == World.FALLING else level - 1
	if side < 1:
		return
	for q in _flow_dirs(p):
		if _takes(q, side):
			_put(changes, q, _type(side, false))


# The level p should hold (sources aside): 8 (falling) under water, else the best sideways feed.
func _support(p: Vector3i) -> int:
	if World.is_water(world.get_block(p + Vector3i.UP)):
		return 8
	var best := 0
	for d in World.H_DIRS:
		var n := p + d
		var tn := world.get_block(n)
		if not World.is_water(tn) or _takes(n + Vector3i.DOWN, 8) or _falls_through(n + Vector3i.DOWN):
			continue  # dry, or it falls instead of spreading
		best = maxi(best, 7 if tn == World.WATER or tn == World.FALLING else World.water_level(tn) - 1)
	return best


# Sideways directions water takes from p: toward the nearest drop within SEEK, else all open ones.
func _flow_dirs(p: Vector3i) -> Array[Vector3i]:
	var open: Array[Vector3i] = []
	var best := SEEK + 1
	var toward: Array[Vector3i] = []
	for d in World.H_DIRS:
		var q := p + d
		if not _passable(q):
			continue
		open.append(q)
		var dist := _drop_distance(q, d)
		if dist < best:
			best = dist
			toward = [q]
		elif dist == best and dist <= SEEK:
			toward.append(q)
	return toward if best <= SEEK else open


# Steps from q (1 = q itself has a drop under it) to a drop, walking sideways away from where the
# water came from; SEEK + 1 if none.
func _drop_distance(q: Vector3i, from: Vector3i) -> int:
	var frontier: Array[Vector3i] = [q]
	var seen := {q: true, q - from: true}
	for dist in range(1, SEEK + 1):
		var next: Array[Vector3i] = []
		for c in frontier:
			if _takes(c + Vector3i.DOWN, 8):
				return dist
			for d in World.H_DIRS:
				var n := c + d
				if not seen.has(n) and _passable(n):
					seen[n] = true
					next.append(n)
		frontier = next
	return SEEK + 1


# Water can be in q (air or flowing water, nothing built there).
func _passable(q: Vector3i) -> bool:
	var t := world.get_block(q)
	return world.in_bounds(q) and (t == World.AIR or (World.is_water(t) and t != World.WATER)) \
		and not world.props.has(q) and not world.blocked.has(q)


# q would take water at `level` (8 = falling): air, or flowing water lower than that.
func _takes(q: Vector3i, level: int) -> bool:
	if not _passable(q):
		return false
	var t := world.get_block(q)
	return t == World.AIR or (t != World.FALLING and World.water_level(t) < level)


func _falls_through(q: Vector3i) -> bool:
	return world.get_block(q) == World.FALLING


func _type(level: int, falling: bool) -> int:
	if level <= 0:
		return World.AIR
	if falling:
		return World.FALLING
	return World.FLOW_1 + mini(level, 7) - 1


# Several feeds into one cell in the same step: the strongest wins.
func _put(changes: Dictionary, p: Vector3i, t: int) -> void:
	if changes.has(p) and World.water_level(changes[p]) >= World.water_level(t) and t != World.AIR:
		return
	if changes.has(p) and t == World.AIR:
		return  # something already feeds it this step
	changes[p] = t

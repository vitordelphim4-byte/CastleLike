class_name Roofs
## Automatic roof planner. Turns a rectangle on top of a building into ordinary roof-piece
## blueprints (so every piece can still be edited by hand afterwards).
##   gable ("Duas águas"): two slopes meeting at a ridge; gable ends are closed with wall blocks.
##   hip ("Quatro águas"): slopes on all four sides, outer corners, ridge / peak on top.
##   flat ("Plano"): one layer of blocks.
## Ring k from the edge sits k blocks above `base` (the layer right above the wall tops).

const TYPES := {"gable": "Duas águas", "hip": "Quatro águas", "flat": "Plano"}
const SIDES: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]


# rect: building footprint (x, z). along_x: gable ridge runs along X (else along Z).
# overhang: roof sticks out one block past the walls, one block lower.
# Returns cell -> {item, dir}.
static func plan(rect: Rect2i, base: int, type: String, mat: String, along_x: bool, overhang: bool) -> Dictionary:
	var r := rect.grow(1) if overhang else rect
	var b := base - 1 if overhang else base
	var out := {}
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			if type == "flat":
				out[Vector3i(x, b, z)] = {"item": mat + "_block", "dir": Vector3i.FORWARD}
				continue
			var dist := {Vector3i.LEFT: x - r.position.x, Vector3i.RIGHT: r.end.x - 1 - x,
				Vector3i.FORWARD: z - r.position.y, Vector3i.BACK: r.end.y - 1 - z}
			if type == "gable":  # only the two eave sides slope
				for side in ([Vector3i.LEFT, Vector3i.RIGHT] if along_x else [Vector3i.FORWARD, Vector3i.BACK]):
					dist.erase(side)
			var k: int = dist.values().min()
			var low: Array[Vector3i] = []
			for side: Vector3i in dist:
				if dist[side] == k:
					low.append(side)
			out[Vector3i(x, b + k, z)] = _piece(mat, low)
			# Close the triangle under the slopes at the gable ends of the building.
			var gable_end := (x == rect.position.x or x == rect.end.x - 1) if along_x \
				else (z == rect.position.y or z == rect.end.y - 1)
			if type == "gable" and gable_end and rect.has_point(Vector2i(x, z)):
				for y in range(base, b + k):
					out[Vector3i(x, y, z)] = {"item": mat + "_block", "dir": Vector3i.FORWARD}
	return out


# Eave sides of a roof: where the slopes come down (ladder goes there, not on a gable end).
static func eave_sides(type: String, along_x: bool) -> Array[Vector3i]:
	if type == "gable":
		return [Vector3i.FORWARD, Vector3i.BACK] if along_x else [Vector3i.LEFT, Vector3i.RIGHT]
	return SIDES


# Piece for a cell whose low (outer) sides are `low`. Pieces rise toward their `dir`.
static func _piece(mat: String, low: Array[Vector3i]) -> Dictionary:
	if low.size() == 1:
		return {"item": mat + "_roof", "dir": -low[0]}
	if low.size() == 2 and low[0] == -low[1]:  # middle of an odd width: ridge along the other axis
		return {"item": mat + "_ridge", "dir": Vector3i.FORWARD if low[0].x == 0 else Vector3i.RIGHT}
	if low.size() == 2:
		# Outer corner model is low on its front (+Z = -dir) and left side; pick the dir that fits.
		var dir := -low[0]
		if _left(dir) != low[1]:
			dir = -low[1]
		return {"item": mat + "_roof_corner", "dir": dir}
	return {"item": mat + "_peak", "dir": Vector3i.FORWARD}


# World direction of a piece's local -X when its back faces dir (see Pieces.instance rotation).
static func _left(dir: Vector3i) -> Vector3i:
	return Vector3i(dir.z, 0, -dir.x)

class_name SaveGame
## Save files: user://saves/<name>.save, zstd-compressed. A small header (name, day, clock) comes
## first so the load list can show it without reading the whole world.
## The world is stored as its seed + only the columns that changed (the rest regenerates the same),
## plus trees that were cut, built pieces, orders, blueprints, stock, villagers and the clock.
## Jobs in progress aren't saved: villagers pick them up again.

const DIR := "user://saves/"
const VERSION := 3  # 3: world WorldGen.DEPTH deeper; 2: stockpile zones (1: one stockpile + global stock)


static func path_for(world_name: String) -> String:
	return DIR + world_name.validate_filename() + ".save"


# Headers of every save, newest first: {name, day, clock, path, time}.
static func list() -> Array[Dictionary]:
	DirAccess.make_dir_recursive_absolute(DIR)
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".save"):
			continue
		var file := FileAccess.open_compressed(DIR + f, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file == null:
			continue
		var head = file.get_var()
		if head is Dictionary and head.get("version", 0) <= VERSION:
			head.path = DIR + f
			head.time = FileAccess.get_modified_time(DIR + f)
			out.append(head)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time > b.time)
	return out


static func read(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var head = file.get_var()
	var data = file.get_var()
	if not data is Dictionary:
		return {}
	if head is Dictionary and head.get("version", 0) < 3:
		_deepen(data)
	return data


# Saves before version 3: the world moved WorldGen.DEPTH blocks up. Every saved cell and position
# rises with it (directions don't); saved columns get the new underground under them when they
# load (World.saved_bottom).
static func _deepen(d: Dictionary) -> void:
	var up := Vector3i(0, WorldGen.DEPTH, 0)
	var pad := PackedByteArray()
	pad.resize(World.CHUNK * World.CHUNK * WorldGen.DEPTH)
	for c: Vector2i in d.columns:
		d.columns[c] = pad + d.columns[c]
	d.saved_bottom = WorldGen.DEPTH
	d.trees = _raised(d.trees, up)
	for p: Array in d.props:
		p[0] += up
	for z: Dictionary in d.get("zones", []):
		z.tiles = _raised(z.tiles, up)
	for f: Dictionary in d.get("farms", []):
		f.tiles = _raised(f.tiles, up)
	d.stations = _raised(d.get("stations", {}), up)
	for o: Dictionary in d.orders:
		o.cells = o.cells.map(func(c: Vector3i) -> Vector3i: return c + up)
	d.blueprints = _raised(d.blueprints, up)
	d.demolish = d.demolish.map(func(c: Vector3i) -> Vector3i: return c + up)
	for w: Dictionary in d.workers:
		w.position += Vector3(up)
	for a: Array in d.get("animals", []):
		a[1] += Vector3(up)
	d.stockpile += Vector3(up)
	d.camera[0] += Vector3(up)


static func _raised(cells: Dictionary, up: Vector3i) -> Dictionary:
	var out := {}
	for c: Vector3i in cells:
		out[c + up] = cells[c]
	return out


static func delete(path: String) -> void:
	DirAccess.remove_absolute(path)


# Writes the running game under Game.world_name. Goes through a temp file so a crash mid-write
# never destroys the previous save.
static func write(main: Node) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_for(Game.world_name)
	var tmp := path + ".tmp"
	var file := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return false
	file.store_var({"version": VERSION, "name": Game.world_name, "day": Game.day, "clock": Game.clock_text()})
	file.store_var(capture(main))
	file.close()
	return DirAccess.rename_absolute(tmp, path) == OK


static func capture(main: Node) -> Dictionary:
	var w: World = Game.world
	var cols := {}
	for c: Vector2i in w.dirty:
		cols[c] = w.columns[c]
	var trees := w.tree_left.duplicate()  # cut-down trees (0)
	for cell: Vector3i in w.trees:
		var t: Dictionary = w.trees[cell]
		if t.amount < ResourceNode.amount_for(t):
			trees[cell] = t.amount
	var props := []
	for c: Vector3i in w.props:
		if w.props[c].base == c:
			props.append([c, w.props[c].item, w.props[c].dir])
	var zones := []
	for z in Game.zones:
		var tiles := {}
		for c: Vector3i in z.tiles:
			tiles[c] = [z.tiles[c].kind, z.tiles[c].n]
		zones.append({"id": z.id, "area": z.area, "tiles": tiles})
	var farms := []
	for f in Game.farms:
		var tiles := {}
		for c: Vector3i in f.tiles:
			tiles[c] = [f.tiles[c].plant, f.tiles[c].sown]
		farms.append({"id": f.id, "area": f.area, "crop": f.crop, "tiles": tiles})
	var stations := {}
	for base: Vector3i in Game.stations:
		stations[base] = {"item": Game.stations[base].item, "bills": Game.stations[base].bills}
	var orders := []
	for o in Game.orders:
		orders.append({"id": o.id, "kind": o.kind, "area": o.area, "paused": o.paused, "cells": o.cells.keys()})
	var bps := {}
	for c: Vector3i in Game.blueprints:
		bps[c] = {"item": Game.blueprints[c].item, "dir": Game.blueprints[c].dir, "left": Game.blueprints[c].left}
	var workers := []
	for wk: Worker in main.get_tree().get_nodes_in_group("workers"):
		workers.append({"name": wk.worker_name, "color": wk.color, "look": wk.look, "priorities": wk.priorities,
			"position": wk.position, "carrying": wk.carrying, "carry_count": wk.carry_count,
			"food": wk.food, "rest": wk.rest, "returns": _in_hand(wk)})
	var animals := []
	for a in main.get_tree().get_nodes_in_group("animals") + main.get_tree().get_nodes_in_group("corpses"):
		animals.append([a.species, a.position, a.hp, a.state == Animal.DEAD, a.marked])
	var rig: Node3D = main.get_node("CameraRig")
	return {
		"animals": animals,
		"seed": w.gen.world_seed, "columns": cols, "trees": trees, "props": props,
		"zones": zones, "zone_count": Game._zone_count, "stations": stations, "farms": farms,
		"farm_count": Game._farm_count, "stockpile": Game.stockpile, "time_of_day": Game.time_of_day, "day": Game.day,
		"orders": orders, "order_count": Game._order_count, "blueprints": bps, "demolish": Game.demolish.keys(),
		"workers": workers, "camera": [rig.position, rig.rotation.y, rig.distance, rig.pitch],
	}


# Goods a villager holds besides `carrying`: craft ingredients (the job itself isn't saved) and
# leftovers of an interrupted craft. They're walked back to the stockpile after loading.
static func _in_hand(wk: Worker) -> Dictionary:
	var out: Dictionary = wk.returns.duplicate()
	for kind: String in wk.held:
		out[kind] = out.get(kind, 0) + wk.held[kind]
	return out


# Before anything generates: terrain and trees come from the save where it has them.
static func apply_world(w: World, data: Dictionary) -> void:
	w.gen = WorldGen.new(data.seed, w.flat)
	w.saved_columns = data.columns
	w.saved_bottom = data.get("saved_bottom", 0)
	w.tree_left = data.trees


# After the world exists: pieces, plans, orders, clock, camera. Villagers are spawned by Main.
static func apply_game(main: Node, data: Dictionary) -> void:
	var w: World = Game.world
	for p: Array in data.props:
		w.add_prop(p[0], p[1], p[2])
	for base: Vector3i in data.get("stations", {}):
		var st: Dictionary = data.stations[base]
		Game.stations[base] = {"item": st.item, "bills": st.bills, "claimed": false}
	if data.has("zones"):
		for s: Dictionary in data.zones:
			var tiles := {}
			for c: Vector3i in s.tiles:
				tiles[c] = {"kind": s.tiles[c][0], "n": s.tiles[c][1]}
			Game.zones.append({"id": s.id, "area": s.area, "tiles": tiles})
		Game._zone_count = data.zone_count
		Game._zones_reshaped()
	else:  # version 1: one 3x3 stockpile at the colony home holding the global stock
		var s := Vector3i(Vector3(data.stockpile).floor())
		Game.add_zone(Rect2i(s.x - 1, s.z - 1, 3, 3))
		for kind: String in data.stock:
			Game.store(kind, data.stock[kind])
	for s: Dictionary in data.get("farms", []):
		var tiles := {}
		for c: Vector3i in s.tiles:
			tiles[c] = {"plant": s.tiles[c][0], "sown": s.tiles[c][1], "claimed": false}
		Game.farms.append({"id": s.id, "area": s.area, "crop": s.crop, "tiles": tiles})
	Game._farm_count = data.get("farm_count", 0)
	if Game.farms:
		Game._zones_reshaped()
	Game.time_of_day = data.time_of_day
	Game.day = data.day
	var plan := {}
	for c: Vector3i in data.blueprints:
		plan[c] = data.blueprints[c]
	Game.place_plan(plan)
	for c: Vector3i in plan:
		if Game.blueprints.has(c) and plan[c].has("left"):
			Game.blueprints[c].left = plan[c].left  # material already delivered stays
	Game.mark_demolish(Array(data.demolish, TYPE_VECTOR3I, "", null), true)
	for s: Dictionary in data.orders:
		var o := Game.add_order(s.kind, s.area)
		o.id = s.id
		o.paused = s.paused
		if s.kind == "dig":
			o.cells = {}
			for c: Vector3i in s.cells:
				o.cells[c] = false
		Game.refresh_marker(o)
	Game._order_count = data.order_count
	Game.orders_changed.emit()
	Game.changed.emit()
	var rig: Node3D = main.get_node("CameraRig")
	rig.position = data.camera[0]
	rig.rotation.y = data.camera[1]
	rig.distance = data.camera[2]
	rig.pitch = data.camera[3]
	rig._update_cam()

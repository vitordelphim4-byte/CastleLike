extends SceneTree
## Run: godot --headless --path . -s tests/test_deep.gd
## Phase 10a: deeper world. Over a few columns of a real seed: bedrock at the bottom, deepslate
## under DEEP_TOP, plain stone above it, coal and iron veins in the ground (never in the air or the
## soil), surface well above the old depth. Plus the old-save migration: positions rise by DEPTH,
## directions don't, saved columns get the generator's underground below them.


func _initialize() -> void:
	var gen := WorldGen.new(1000)
	var counts := {}
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			var c := Vector2i((gen.spawn.x >> 4) + cx, (gen.spawn.y >> 4) + cz)
			var blocks: PackedByteArray = gen.generate(c.x, c.y, World.CHUNK, World.SY).blocks
			for lz in World.CHUNK:
				for lx in World.CHUNK:
					var top := 0
					for y in World.SY:
						var t := blocks[lx + World.CHUNK * (lz + World.CHUNK * y)]
						if t != World.AIR and t != World.WATER:
							top = y
						counts[t] = counts.get(t, 0) + 1
						if y == 0 and t != World.BEDROCK:
							return _fail("no bedrock at y 0")
						if y > WorldGen.BEDROCK_MAX and t == World.BEDROCK:
							return _fail("bedrock at y %d" % y)
						if t == World.DEEPSLATE and y >= WorldGen.DEEP_TOP + 3:
							return _fail("deepslate too high: %d" % y)
						if t == World.STONE and y < WorldGen.DEEP_TOP - 3:
							return _fail("plain stone too deep: %d" % y)
					var ground := int(gen.height(c.x * World.CHUNK + lx, c.y * World.CHUNK + lz))  # ravines may cut lower
					if ground < WorldGen.DEPTH:
						return _fail("surface at %d, under the added depth" % ground)
	for t in [World.DEEPSLATE, World.COAL_ORE, World.IRON_ORE]:
		if counts.get(t, 0) == 0:
			return _fail("no block of type %d in 25 columns" % t)
	print("ore per column: coal %.0f, iron %.0f" % [counts[World.COAL_ORE] / 25.0, counts[World.IRON_ORE] / 25.0])

	var col := PackedByteArray()
	col.resize(World.CHUNK * World.CHUNK * 128)
	var old := {"columns": {Vector2i(0, 0): col}, "trees": {Vector3i(1, 20, 1): 0},
		"props": [[Vector3i(2, 20, 2), "wood_door", Vector3i.FORWARD]], "zones": [], "farms": [],
		"stations": {}, "orders": [{"cells": [Vector3i(3, 19, 3)]}], "blueprints": {Vector3i(4, 21, 4): {"dir": Vector3i.BACK}},
		"demolish": [], "workers": [{"position": Vector3(5.5, 20, 5.5)}], "animals": [["deer", Vector3(6, 20, 6)]],
		"stockpile": Vector3(0.5, 20, 0.5), "camera": [Vector3(0, 20, 0), 0.0, 40.0, 1.0]}
	load("res://scripts/save_game.gd")._deepen(old)  # by path: SaveGame needs the Game autoload
	var d := WorldGen.DEPTH
	if old.props[0][0].y != 20 + d or old.props[0][2] != Vector3i.FORWARD or not old.trees.has(Vector3i(1, 20 + d, 1)) \
			or old.orders[0].cells[0].y != 19 + d or not old.blueprints.has(Vector3i(4, 21 + d, 4)) \
			or old.workers[0].position.y != 20 + d or old.animals[0][1].y != 20 + d or old.stockpile.y != 20 + d \
			or old.camera[0].y != 20 + d or old.columns[Vector2i(0, 0)].size() != World.CHUNK * World.CHUNK * (128 + d) \
			or old.saved_bottom != d:
		return _fail("old save migration: %s" % old)
	print("test_deep OK")
	quit()


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)

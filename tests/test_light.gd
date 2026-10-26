extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_light.gd
## Phase 10f, sky light (Minecraft 0..15) on the flat debug map: open ground is 15; a room sealed
## under the ground is 0; dig a shaft into it and the shaft gets 15 while the room fills with light
## fading 1 per block away from it; the shader's least light is on only while cutting / x-raying.


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	await process_frame
	var w: World = root.get_node("Game").world
	var o := Vector3i(70, 0, -70)  # empty plain
	var y := w.top_at(o.x, o.z)
	if w.light_at(Vector3i(o.x, y, o.z)) != 15:
		return _fail("open ground should have light 15, got %d" % w.light_at(Vector3i(o.x, y, o.z)))
	var room := {}  # 7 long, 3 wide, 2 high, 8 under the ground
	for x in 7:
		for z in 3:
			for h in 2:
				room[Vector3i(o.x + x, y - 8 + h, o.z + z)] = World.AIR
	w.set_blocks(room)
	var far := Vector3i(o.x + 6, y - 8, o.z + 1)
	if w.light_at(far) != 0:
		return _fail("sealed room should be dark, got %d" % w.light_at(far))
	var shaft := {}
	for h in range(-6, 0):
		shaft[Vector3i(o.x, y + h, o.z + 1)] = World.AIR
	w.set_blocks(shaft)
	var in_shaft := w.light_at(Vector3i(o.x, y - 3, o.z + 1))
	var under := w.light_at(Vector3i(o.x, y - 8, o.z + 1))
	var beside := w.light_at(Vector3i(o.x + 1, y - 8, o.z + 1))
	var end := w.light_at(far)
	print("light: shaft %d, under it %d, next to that %d, far end %d" % [in_shaft, under, beside, end])
	if in_shaft != 15 or under != 15 or beside != 14 or end != 9:
		return _fail("light should fall 1 per block from the shaft: %d %d %d %d" % [in_shaft, under, beside, end])
	if w.material.get_shader_parameter("min_light") != 0.0:
		return _fail("no least light without a cut")
	w.set_cut(y - 4)
	if w.material.get_shader_parameter("min_light") <= 0.0:
		return _fail("cutting should light the inside a little")
	w.set_cut(World.SY)
	print("test_light OK")
	quit()


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)

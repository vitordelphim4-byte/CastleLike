extends SceneTree
## Run (needs a window, not --headless): godot --path . -s tests/bench_render.gd
## Rendering benchmark: average frame time, draw calls, triangles and VRAM in the real game,
## with each expensive effect switched off in turn, to see what costs the most.

const WARMUP := 600  # frames to let the world stream in
const FRAMES := 180  # frames measured per configuration


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # measure real cost, not 60 fps cap
	var game := root.get_node("Game")
	game.start_seed = 12345  # same world every run, so results compare
	root.add_child(load("res://main.tscn").instantiate())
	var main := root.get_node("Main")
	var env: Environment = main.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = main.get_node("Sun")
	var rig: Node3D = main.get_node("CameraRig")
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # again: the window exists now
	Engine.max_fps = 0
	game.time_of_day = 0.4
	rig.distance = 45.0
	rig.pitch = deg_to_rad(40)
	rig._update_cam()
	for i in WARMUP:
		await process_frame
	var configs := [
		["tudo ligado", func() -> void: pass],
		["sem neblina volumétrica", func() -> void: env.volumetric_fog_enabled = false],
		["sem SSAO", func() -> void: env.ssao_enabled = false],
		["sem glow", func() -> void: env.glow_enabled = false],
		["sem sombras do sol", func() -> void: sun.shadow_enabled = false],
		["sem grama (tufos)", func() -> void: _show_tufts(game.world, false)],
		["sem árvores", func() -> void: _show_trees(game.world, false)],
		["tudo ligado (de novo)", func() -> void: pass],
	]
	var base := 0.0
	print("%-26s %8s %8s %8s %8s %8s" % ["config", "ms", "fps", "draws", "tris(k)", "VRAM MB"])
	for c: Array in configs:
		c[1].call()
		for i in 20:
			await process_frame
		var t := Time.get_ticks_usec()
		for i in FRAMES:
			await process_frame
		var ms := (Time.get_ticks_usec() - t) / 1000.0 / FRAMES
		if base == 0.0:
			base = ms
		var P := Performance
		print("%-26s %8.2f %8.0f %8d %8d %8d   %s" % [c[0], ms, 1000.0 / ms,
			P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576, "" if c[0].begins_with("tudo") else "(%+.2f ms)" % (ms - base)])
		_restore(env, sun, game.world)
	print("GPU: %s" % RenderingServer.get_video_adapter_name())
	quit()


func _restore(env: Environment, sun: DirectionalLight3D, world: Node) -> void:
	env.volumetric_fog_enabled = true
	env.ssao_enabled = true
	env.glow_enabled = true
	sun.shadow_enabled = true
	_show_tufts(world, true)
	_show_trees(world, true)


func _show_tufts(world: Node, on: bool) -> void:
	for n in world.find_children("*", "MultiMeshInstance3D", true, false):
		n.visible = on


func _show_trees(world: Node, on: bool) -> void:
	for n in world.tree_nodes.values():
		n.visible = on

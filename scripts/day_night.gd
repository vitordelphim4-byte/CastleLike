extends DirectionalLight3D
## Day/night cycle: the sun crosses the sky from Game.time_of_day; at night the same light becomes
## a dim blue moon on the opposite side. Sky, ambient light and fog follow a keyframe table.

const MIN_ELEVATION := 0.2  # keeps shadows from stretching across the whole map at dawn/dusk
# time, sky top, horizon (also fog), light color, light energy, ambient color, ambient energy.
# Light energy dips to ~0 at 0.25 / 0.75, where the light swaps between moon and sun.
const NIGHT := [0.0, Color(0.02, 0.03, 0.09), Color(0.06, 0.08, 0.18), Color(0.72, 0.8, 1.0), 0.35, Color(0.45, 0.52, 0.85), 0.32]
const DAY := [0.0, Color(0.28, 0.52, 0.9), Color(0.7, 0.84, 0.95), Color(1.0, 0.95, 0.85), 1.6, Color(0.78, 0.8, 0.86), 0.55]
var keys := [  # var: slice() is not allowed in a const
	[0.0] + NIGHT.slice(1),
	[0.2] + NIGHT.slice(1),
	[0.25, Color(0.15, 0.2, 0.4), Color(0.8, 0.45, 0.35), Color(1.0, 0.5, 0.3), 0.05, Color(0.6, 0.5, 0.7), 0.32],
	[0.28, Color(0.3, 0.45, 0.78), Color(1.0, 0.7, 0.45), Color(1.0, 0.72, 0.45), 1.2, Color(0.9, 0.75, 0.65), 0.45],
	[0.36] + DAY.slice(1),
	[0.64] + DAY.slice(1),
	[0.7, Color(0.32, 0.48, 0.82), Color(1.0, 0.72, 0.45), Color(1.0, 0.75, 0.45), 1.4, Color(0.95, 0.8, 0.65), 0.5],
	[0.73, Color(0.2, 0.25, 0.5), Color(1.0, 0.5, 0.3), Color(1.0, 0.5, 0.28), 0.6, Color(0.85, 0.6, 0.6), 0.4],
	[0.75, Color(0.1, 0.12, 0.3), Color(0.5, 0.3, 0.35), Color(0.8, 0.5, 0.5), 0.05, Color(0.55, 0.5, 0.8), 0.32],
	[0.8] + NIGHT.slice(1),
	[1.0] + NIGHT.slice(1),
]


@onready var env: Environment = get_node("../WorldEnvironment").environment
@onready var sky: ProceduralSkyMaterial = env.sky.sky_material
# Floating motes around the camera focus: pollen by day, fireflies at night (enchanted-forest mood).
@onready var pollen := _motes(Color(1.0, 0.95, 0.7), 0.0, 0.05, 160)
@onready var fireflies := _motes(Color(0.75, 1.0, 0.35), 4.0, 0.12, 70)


func _motes(col: Color, glow: float, size: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.local_coords = false  # motes stay put in the world while the camera moves
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 4, 22)
	p.position.y = 3
	p.direction = Vector3.UP
	p.spread = 180
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	var fade := Curve.new()  # fade in and out instead of popping
	fade.add_point(Vector2(0, 0))
	fade.add_point(Vector2(0.2, 1))
	fade.add_point(Vector2(0.8, 1))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col
	if glow > 0:  # bright enough to bloom
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	q.material = m
	p.mesh = q
	get_node("../CameraRig").add_child.call_deferred(p)
	return p


func _process(_delta: float) -> void:
	var t := Game.time_of_day
	# Sun rises in the east (+X) at 0.25, peaks at 0.5, sets in the west at 0.75; tilted south.
	var a := (t - 0.25) * TAU
	var dir := Vector3(cos(a), sin(a), 0.45)
	if dir.y < 0:
		dir = Vector3(-dir.x, -dir.y, dir.z)  # moon, opposite the sun
	dir.y = maxf(dir.y, MIN_ELEVATION)
	basis = Basis.looking_at(-dir.normalized())

	var i := 0
	while keys[i + 1][0] < t:
		i += 1
	var k0: Array = keys[i]
	var k1: Array = keys[i + 1]
	var f := smoothstep(k0[0], k1[0], t)
	var horizon: Color = k0[2].lerp(k1[2], f)
	sky.sky_top_color = k0[1].lerp(k1[1], f)
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon
	sky.ground_bottom_color = horizon.darkened(0.3)
	env.fog_light_color = horizon
	light_color = k0[3].lerp(k1[3], f)
	light_energy = lerpf(k0[4], k1[4], f)
	env.ambient_light_color = k0[5].lerp(k1[5], f)
	env.ambient_light_energy = lerpf(k0[6], k1[6], f)
	var night := t < 0.24 or t > 0.76
	pollen.emitting = not night
	fireflies.emitting = night
	if Game.world:
		Game.world.water_material.set_shader_parameter("daylight", clampf(env.ambient_light_energy / 0.55, 0, 1))

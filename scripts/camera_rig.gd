extends Node3D
## RTS camera. WASD move, Q/E rotate, wheel zoom, middle-drag orbit.

@export var move_speed := 30.0
@export var rotate_speed := 1.5
@export var zoom_min := 8.0
@export var zoom_max := 70.0  # beyond this the streamed world's edge would show through the fog

var distance := 40.0
var pitch := deg_to_rad(55.0)

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	_update_cam()


func _process(_delta: float) -> void:
	var v := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if v != Vector3.ZERO:
		position += basis * v.normalized() * move_speed * (distance / 40.0) * Game.real_dt
	rotation.y += (float(Input.is_key_pressed(KEY_Q)) - float(Input.is_key_pressed(KEY_E))) * rotate_speed * Game.real_dt


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(zoom_min, distance * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(zoom_max, distance * 1.1)
		_update_cam()
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		rotation.y -= e.relative.x * 0.005
		pitch = clampf(pitch + e.relative.y * 0.005, deg_to_rad(15), deg_to_rad(85))
		_update_cam()


func _update_cam() -> void:
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * distance
	cam.rotation = Vector3(-pitch, 0, 0)

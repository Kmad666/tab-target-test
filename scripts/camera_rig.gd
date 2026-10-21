class_name CameraRig
extends Node3D
## Classic WoW camera:
##  - Left mouse drag: orbit the camera, character keeps facing the same way.
##  - Right mouse drag: steer, the character turns with the camera.
##  - Both buttons: run forward (read by the player).
##  - Mouse wheel: zoom.
##  - A quick click (no drag) on an enemy targets it.

const SENSITIVITY := 0.006
const DRAG_THRESHOLD := 4.0

var player: Player
var camera: Camera3D
var lmb_held := false
var rmb_held := false

var yaw_offset := 0.0           # camera yaw relative to the character
var pitch := -0.32
var distance := 10.0
var target_distance := 10.0

var _press_pos := Vector2.ZERO
var _drag := 0.0
var _dragging := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 400.0
	add_child(camera)
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_drag_button(mb)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = maxf(2.0, target_distance - 1.2)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = minf(25.0, target_distance + 1.2)
	elif event is InputEventMouseMotion and (lmb_held or rmb_held):
		var mm := event as InputEventMouseMotion
		if not _dragging:
			_drag += mm.relative.length()
			if _drag > DRAG_THRESHOLD:
				_dragging = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _dragging:
			if rmb_held:
				player.rotation.y -= mm.relative.x * SENSITIVITY
			else:
				yaw_offset -= mm.relative.x * SENSITIVITY
			pitch = clampf(pitch - mm.relative.y * SENSITIVITY, -1.45, 0.35)


func _on_drag_button(mb: InputEventMouseButton) -> void:
	var is_left := mb.button_index == MOUSE_BUTTON_LEFT
	if mb.pressed:
		if not lmb_held and not rmb_held:
			_press_pos = mb.position
			_drag = 0.0
			_dragging = false
		if is_left:
			lmb_held = true
		else:
			rmb_held = true
			# Right mouse snaps the character to face where the camera looks.
			player.rotation.y += yaw_offset
			yaw_offset = 0.0
	else:
		if is_left:
			lmb_held = false
		else:
			rmb_held = false
		if not _dragging:
			_click_select(mb.position)
		if not lmb_held and not rmb_held and _dragging:
			_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.warp_mouse(_press_pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		lmb_held = false
		rmb_held = false
		_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _click_select(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 300.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider is Node and hit.collider.is_in_group("enemies"):
		player.set_target(hit.collider)


func _process(delta: float) -> void:
	if player == null:
		return
	distance = lerpf(distance, target_distance, 1.0 - exp(-10.0 * delta))
	var pivot := player.global_position + Vector3(0, 1.8, 0)
	var yaw := player.rotation.y + yaw_offset
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, distance)
	var pos := pivot + offset
	pos.y = maxf(pos.y, 0.3)
	camera.global_position = pos
	camera.look_at(pivot, Vector3.UP)

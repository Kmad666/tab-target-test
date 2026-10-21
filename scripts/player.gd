class_name Player
extends CharacterBody3D
## The hooded caster: WoW-style movement, tab targeting and channeled Force Lightning.
## The model is built from primitives in code and animated procedurally.

signal target_changed(new_target: Node3D)
signal channel_started
signal channel_stopped(reason: String)
signal error_message(text: String)

const RUN_SPEED := 7.0
const BACK_SPEED := 4.5
const TURN_SPEED := PI           # radians per second (180 degrees)
const GRAVITY := 25.0
const SPELL_RANGE := 30.0        # yards (1 unit = 1 yard)
const TARGET_RANGE := 50.0       # how far Tab looks for enemies
const TICK_TIME := 0.5           # seconds between lightning damage ticks
const TICK_DAMAGE := 45.0
const SPELL_NAME := "Force Lightning"

var display_name := "Hooded One"
var target: Node3D = null
var channeling := false
var channel_time := 0.0
var autorun := false
var is_moving := false
var cam_rig: Node = null          # set by main, gives us mouse button state
var fingertip: Marker3D           # where the lightning comes out

var _tick_timer := 0.0
var _move_local := Vector3.ZERO
var _t := 0.0
var _hover := 0.0
var _cast_blend := 0.0
var _lean_fwd := 0.0
var _lean_side := 0.0

var _model: Node3D
var _body: Node3D
var _torso: Node3D
var _hood: Node3D
var _arms := {}
var _cloud: CPUParticles3D
var _cloud_core: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.9
	col.shape = cap
	col.position.y = 0.95
	add_child(col)
	_build_model()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("target_next"):
		cycle_target()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("spell_1"):
		try_cast()
	elif event.is_action_pressed("cancel"):
		if channeling:
			stop_channel("Cancelled")
		elif target:
			set_target(null)
	elif event.is_action_pressed("autorun"):
		autorun = not autorun


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	var lmb: bool = cam_rig != null and cam_rig.lmb_held
	var rmb: bool = cam_rig != null and cam_rig.rmb_held

	var fwd := 0.0
	var strafe := 0.0
	var turn := 0.0
	if Input.is_action_pressed("move_forward"):
		fwd += 1.0
	if Input.is_action_pressed("move_back"):
		fwd -= 1.0
		autorun = false
	if lmb and rmb:
		fwd = clampf(fwd + 1.0, -1.0, 1.0)
	if autorun and fwd >= 0.0:
		fwd = 1.0
	if Input.is_action_pressed("strafe_left"):
		strafe -= 1.0
	if Input.is_action_pressed("strafe_right"):
		strafe += 1.0
	# A/D turn, unless the right mouse button is held, then they strafe.
	if Input.is_action_pressed("turn_left"):
		if rmb:
			strafe -= 1.0
		else:
			turn += 1.0
	if Input.is_action_pressed("turn_right"):
		if rmb:
			strafe += 1.0
		else:
			turn -= 1.0
	strafe = clampf(strafe, -1.0, 1.0)

	if channeling and is_instance_valid(target):
		_face_target(delta)
	else:
		rotation.y += turn * TURN_SPEED * delta

	_move_local = Vector3(strafe, 0.0, -fwd)
	is_moving = _move_local.length_squared() > 0.0
	if is_moving and channeling:
		stop_channel("Interrupted")

	var speed := BACK_SPEED if fwd < 0.0 else RUN_SPEED
	var dir := Vector3.ZERO
	if is_moving:
		dir = (transform.basis * _move_local).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	_update_channel(delta)


func _face_target(delta: float) -> void:
	var d := target.global_position - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-12.0 * delta))


# ---------------------------------------------------------------- targeting

func set_target(t: Node3D) -> void:
	if t == target:
		return
	if channeling:
		stop_channel("Interrupted")
	if is_instance_valid(target) and target.has_method("set_targeted"):
		target.set_targeted(false)
	target = t
	if is_instance_valid(target) and target.has_method("set_targeted"):
		target.set_targeted(true)
	target_changed.emit(target)


## Tab: nearest enemies in front first, cycling on repeated presses.
func cycle_target() -> void:
	var forward := -global_transform.basis.z
	var in_front := []
	var behind := []
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(e.global_position)
		if d > TARGET_RANGE:
			continue
		var to_e: Vector3 = (e.global_position - global_position).normalized()
		if forward.dot(to_e) > 0.0:
			in_front.append(e)
		else:
			behind.append(e)
	var by_dist := func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	in_front.sort_custom(by_dist)
	behind.sort_custom(by_dist)
	var list: Array = in_front if not in_front.is_empty() else behind
	if list.is_empty():
		return
	var i := list.find(target)
	set_target(list[(i + 1) % list.size()])


func distance_to_target() -> float:
	if not is_instance_valid(target):
		return INF
	var d := global_position.distance_to(target.global_position)
	return maxf(0.0, d - 0.5)   # measure to the edge of the target, like WoW


func target_in_range() -> bool:
	return distance_to_target() <= SPELL_RANGE


# ---------------------------------------------------------------- casting

func try_cast() -> void:
	if channeling:
		return
	if not is_instance_valid(target):
		error_message.emit("You have no target.")
		return
	if is_moving:
		error_message.emit("You can't do that while moving.")
		return
	if not target_in_range():
		error_message.emit("Out of range.")
		return
	channeling = true
	channel_time = 0.0
	_tick_timer = 0.2
	channel_started.emit()


func stop_channel(reason: String) -> void:
	if not channeling:
		return
	channeling = false
	channel_stopped.emit(reason)


func _update_channel(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(target):
		stop_channel("Interrupted")
		return
	if not target_in_range():
		stop_channel("Out of range")
		error_message.emit("Out of range.")
		return
	channel_time += delta
	_tick_timer -= delta
	while _tick_timer <= 0.0:
		_tick_timer += TICK_TIME
		if target.has_method("take_damage"):
			target.take_damage(TICK_DAMAGE)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	_t += delta
	_hover = move_toward(_hover, 1.0 if is_moving else 0.0, delta * 3.0)
	var blend_speed := 7.0 if channeling else 3.5
	_cast_blend = move_toward(_cast_blend, 1.0 if channeling else 0.0, delta * blend_speed)
	var cb := smoothstep(0.0, 1.0, _cast_blend)
	var hv := smoothstep(0.0, 1.0, _hover)

	# Hunched over; straightens a little while casting.
	var breath := sin(_t * 1.7)
	var lean := lerpf(0.45, 0.22, cb)
	_torso.rotation.x = -(lean + breath * 0.025)
	_hood.rotation.x = lean * 0.75 + breath * 0.015

	# Hover on the dark cloud while moving.
	_body.position.y = hv * 0.45 + sin(_t * 2.4) * 0.05 * hv
	var k := 1.0 - exp(-6.0 * delta)
	_lean_fwd = lerpf(_lean_fwd, -_move_local.z, k)
	_lean_side = lerpf(_lean_side, _move_local.x, k)
	_model.rotation.x = -0.15 * _lean_fwd * hv
	_model.rotation.z = -0.12 * _lean_side * hv
	_cloud.emitting = _hover > 0.05
	_cloud_core.visible = _hover > 0.01
	_cloud_core.scale = Vector3(1.25, 0.45, 1.25) * maxf(hv, 0.001)
	_cloud_core.rotation.y += delta * 1.5

	# Eyes burn brighter while casting.
	_eye_mat.emission_energy_multiplier = lerpf(3.0, 6.0, cb) + sin(_t * 30.0) * 0.4 * cb
	_eye_light.light_energy = lerpf(0.3, 0.8, cb)

	# Arms: T-rex pose by default, right arm points a finger at the target when casting.
	var aim_pitch := 0.0
	var right: Dictionary = _arms["right"]
	if is_instance_valid(target) and target.has_method("get_hit_point"):
		var sh: Vector3 = right["shoulder"].global_position
		var hit: Vector3 = target.get_hit_point()
		aim_pitch = atan2(hit.y - sh.y, Vector2(hit.x - sh.x, hit.z - sh.z).length())
	for side_name in ["right", "left"]:
		var arm: Dictionary = _arms[side_name]
		var side: float = arm["side"]
		var tw := sin(_t * 2.3 + side) * 0.05
		var idle := [0.6 + breath * 0.03, 0.12 * side, 1.65 + tw, -1.1 + tw * 1.5,
				0.6 + 0.1 * sin(_t * 3.0 + side), 0.6 + 0.1 * sin(_t * 3.0 + side)]
		var pose := idle
		if side_name == "right":
			var tremble := sin(_t * 41.0) * 0.02 * cb
			var cast := [PI / 2.0 + lean + aim_pitch + tremble, -0.05 * side, 0.04, 0.08, 1.5, 0.0]
			pose = []
			for i in idle.size():
				pose.append(lerpf(idle[i], cast[i], cb))
		else:
			# Off hand clenches into a claw while the power flows.
			pose[2] += 0.25 * cb
			pose[4] += 0.6 * cb
			pose[5] += 0.6 * cb
		_apply_arm(arm, pose)


func _apply_arm(arm: Dictionary, p: Array) -> void:
	arm["shoulder"].rotation = Vector3(p[0], 0.0, p[1])
	arm["elbow"].rotation.x = p[2]
	arm["wrist"].rotation.x = p[3]
	var fingers: Array = arm["fingers"]
	for i in fingers.size():
		var c: float = p[5] if i == 0 else p[4]
		fingers[i][0].rotation.x = -c
		fingers[i][1].rotation.x = -c * 1.2


# ---------------------------------------------------------------- model

func _build_model() -> void:
	var cloak := LowPoly.mat(Color(0.1, 0.085, 0.12))
	var void_mat := LowPoly.mat(Color(0.0, 0.0, 0.0), 1.0)
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bone := LowPoly.mat(Color(0.86, 0.82, 0.72), 0.7)
	_eye_mat = LowPoly.glow(Color(1.0, 0.08, 0.04), 3.0)

	_model = LowPoly.pivot(self)
	_body = LowPoly.pivot(_model)

	# Lower robe, flaring out at the bottom.
	LowPoly.add(_body, LowPoly.cyl(0.3, 0.58, 0.95, 9), cloak, Vector3(0, 0.47, 0))

	# Upper body pivots at the waist so he can hunch.
	_torso = LowPoly.pivot(_body, Vector3(0, 0.8, 0))
	LowPoly.add(_torso, LowPoly.cyl(0.2, 0.3, 0.75, 8), cloak, Vector3(0, 0.36, 0))
	LowPoly.add(_torso, LowPoly.cyl(0.16, 0.42, 0.3, 8), cloak, Vector3(0, 0.62, 0))

	# Hood with a black void for a face and two red eyes.
	_hood = LowPoly.pivot(_torso, Vector3(0, 0.8, 0))
	LowPoly.add(_hood, LowPoly.sphere(0.26, 8, 5), cloak, Vector3(0, 0.13, 0.02), Vector3.ZERO, Vector3(1.0, 1.12, 1.18))
	LowPoly.add(_hood, LowPoly.cyl(0.0, 0.12, 0.3, 6), cloak, Vector3(0, 0.3, 0.16), Vector3(0.9, 0, 0))
	LowPoly.add(_hood, LowPoly.sphere(0.19, 8, 5), void_mat, Vector3(0, 0.11, -0.2), Vector3.ZERO, Vector3(0.95, 1.12, 0.55))
	LowPoly.add(_hood, LowPoly.torus(0.17, 0.23, 10, 5), cloak, Vector3(0, 0.11, -0.27), Vector3(PI / 2.0, 0, 0), Vector3(0.95, 1.0, 1.15))
	for side in [1.0, -1.0]:
		LowPoly.add(_hood, LowPoly.sphere(0.03, 6, 4), _eye_mat, Vector3(0.065 * side, 0.12, -0.3),
				Vector3(0, 0, 0.35 * side), Vector3(1.5, 0.75, 0.6), false)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.15, 0.1)
	_eye_light.omni_range = 0.6
	_eye_light.light_energy = 0.5
	_eye_light.position = Vector3(0, 0.12, -0.45)
	_hood.add_child(_eye_light)

	_arms["right"] = _build_arm(1.0, cloak, bone)
	_arms["left"] = _build_arm(-1.0, cloak, bone)

	# The hover cloud: a dark core plus trailing smoke.
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.roughness = 1.0
	_cloud_core = LowPoly.add(_body, LowPoly.sphere(0.6, 7, 4), smoke_mat, Vector3(0, -0.08, 0))
	var core_mat := smoke_mat.duplicate() as StandardMaterial3D
	core_mat.vertex_color_use_as_albedo = false
	core_mat.albedo_color = Color(0.1, 0.08, 0.13, 0.9)
	_cloud_core.material_override = core_mat
	_cloud_core.visible = false

	_cloud = CPUParticles3D.new()
	_cloud.amount = 64
	_cloud.lifetime = 1.2
	_cloud.local_coords = false
	_cloud.mesh = LowPoly.flat(LowPoly.sphere(0.22, 6, 4))
	_cloud.material_override = smoke_mat
	_cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_cloud.emission_sphere_radius = 0.55
	_cloud.direction = Vector3(0, -1, 0)
	_cloud.spread = 70.0
	_cloud.initial_velocity_min = 0.3
	_cloud.initial_velocity_max = 1.0
	_cloud.gravity = Vector3(0, 0.6, 0)
	_cloud.scale_amount_min = 0.8
	_cloud.scale_amount_max = 1.7
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_cloud.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.12, 0.2, 0.95))
	grad.set_color(1, Color(0.05, 0.04, 0.07, 0.0))
	_cloud.color_ramp = grad
	_cloud.emitting = false
	_cloud.position = Vector3(0, -0.05, 0)
	_body.add_child(_cloud)


## Builds one skeletal arm in a cloak sleeve. side = 1 for right, -1 for left.
func _build_arm(side: float, cloak: Material, bone: Material) -> Dictionary:
	var shoulder := LowPoly.pivot(_torso, Vector3(0.3 * side, 0.6, -0.02))
	LowPoly.add(shoulder, LowPoly.cyl(0.09, 0.15, 0.4, 7), cloak, Vector3(0, -0.17, 0))
	var elbow := LowPoly.pivot(shoulder, Vector3(0, -0.34, 0))
	LowPoly.add(elbow, LowPoly.sphere(0.035, 6, 4), bone)
	for x in [-0.022, 0.022]:
		LowPoly.add(elbow, LowPoly.cyl(0.016, 0.02, 0.3, 5), bone, Vector3(x, -0.15, 0))
	var wrist := LowPoly.pivot(elbow, Vector3(0, -0.3, 0))
	LowPoly.add(wrist, LowPoly.sphere(0.025, 5, 3), bone)
	LowPoly.add(wrist, LowPoly.box(Vector3(0.085, 0.08, 0.025)), bone, Vector3(0, -0.045, 0))

	# Index finger sits on the inner (thumb) side of the hand.
	var fingers := []
	var xs := [-0.033 * side, -0.011 * side, 0.011 * side, 0.033 * side]
	for i in 4:
		var k1 := LowPoly.pivot(wrist, Vector3(xs[i], -0.085, 0))
		var len1 := 0.06 if i < 3 else 0.048
		LowPoly.add(k1, LowPoly.cyl(0.008, 0.01, len1, 4), bone, Vector3(0, -len1 / 2.0, 0))
		var k2 := LowPoly.pivot(k1, Vector3(0, -len1, 0))
		var len2 := 0.055
		LowPoly.add(k2, LowPoly.cyl(0.002, 0.008, len2, 4), bone, Vector3(0, -len2 / 2.0, 0))
		fingers.append([k1, k2])
		if i == 0 and side > 0.0:
			fingertip = Marker3D.new()
			fingertip.position = Vector3(0, -len2, 0)
			k2.add_child(fingertip)
	var thumb := LowPoly.pivot(wrist, Vector3(-0.045 * side, -0.03, 0))
	thumb.rotation = Vector3(-0.3, 0, -0.5 * side)
	LowPoly.add(thumb, LowPoly.cyl(0.003, 0.01, 0.06, 4), bone, Vector3(0, -0.03, 0))
	return {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "fingers": fingers, "side": side}

class_name Player
extends CharacterBody3D
## The hooded caster: WoW-style movement, tab targeting and channeled Force Lightning.
## The cartoon model is built from smooth shapes in code and animated procedurally.

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
var _cloud_root: Node3D
var _puffs: Array = []
var _cloud: CPUParticles3D
var _eye_mat: StandardMaterial3D


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

const ROBE_COLOR := Color(0.36, 0.14, 0.55)
const LINING_COLOR := Color(0.06, 0.42, 0.5)
const EYE_COLOR := Color(1.0, 0.1, 0.05)


func _process(delta: float) -> void:
	_t += delta
	_hover = move_toward(_hover, 1.0 if is_moving else 0.0, delta * 3.0)
	var blend_speed := 7.0 if channeling else 3.5
	_cast_blend = move_toward(_cast_blend, 1.0 if channeling else 0.0, delta * blend_speed)
	var cb := smoothstep(0.0, 1.0, _cast_blend)
	var hv := smoothstep(0.0, 1.0, _hover)

	# Slightly stooped, scheming posture; leans in while casting.
	var breath := sin(_t * 1.6)
	var lean := lerpf(0.14, 0.3, cb)
	_torso.rotation.x = -(lean + breath * 0.02)
	_hood.rotation.x = lean * 0.55 + breath * 0.015
	_hood.rotation.z = sin(_t * 0.7) * 0.07 * (1.0 - cb)

	# Hover on the dark cloud while moving.
	_body.position.y = hv * 0.5 + sin(_t * 2.4) * 0.05 * hv
	var k := 1.0 - exp(-6.0 * delta)
	_lean_fwd = lerpf(_lean_fwd, -_move_local.z, k)
	_lean_side = lerpf(_lean_side, _move_local.x, k)
	_model.rotation.x = -0.15 * _lean_fwd * hv
	_model.rotation.z = -0.12 * _lean_side * hv
	_cloud_root.visible = _hover > 0.01
	_cloud_root.scale = Vector3.ONE * maxf(hv, 0.001)
	_cloud_root.rotation.y += delta * 1.2
	for i in _puffs.size():
		var puff: MeshInstance3D = _puffs[i]
		puff.scale = puff.get_meta("base") * (1.0 + 0.13 * sin(_t * 3.2 + i * 1.7))
	_cloud.emitting = _hover > 0.05

	# Eyes burn brighter while casting.
	var eye_energy := lerpf(2.5, 5.0, cb) + sin(_t * 30.0) * 0.5 * cb
	_eye_mat.albedo_color = EYE_COLOR * eye_energy

	# Arms: "behold" pose with wiggling fingers; right hand points at the target when casting.
	var aim_pitch := 0.0
	var right: Dictionary = _arms["right"]
	if is_instance_valid(target) and target.has_method("get_hit_point"):
		var sh: Vector3 = right["shoulder"].global_position
		var hit: Vector3 = target.get_hit_point()
		aim_pitch = atan2(hit.y - sh.y, Vector2(hit.x - sh.x, hit.z - sh.z).length())
	for side_name in ["right", "left"]:
		var arm: Dictionary = _arms[side_name]
		var phase := 0.0 if side_name == "right" else 1.3
		var idle := _idle_pose(phase)
		var cast: Dictionary
		if side_name == "right":
			var tremble := sin(_t * 41.0) * 0.02
			cast = {"sh": Vector3(PI / 2.0 + lean + aim_pitch + tremble, 0.0, -0.1),
					"el": Vector3(0.04, 0.0, 0.0), "wr": Vector3(0.05, 0.0, 0.0),
					"idx": 0.0, "fing": 1.5, "th": 0.9}
		else:
			cast = idle.duplicate()
			cast["sh"] += Vector3(0.1, 0.0, 0.12)
			cast["el"] += Vector3(0.0, 0.0, 0.2)
			cast["idx"] = 1.0
			cast["fing"] = 1.2
		_apply_arm(arm, _blend_pose(idle, cast, cb))


func _idle_pose(phase: float) -> Dictionary:
	var sway := sin(_t * 1.6 + phase)
	var wiggle := _t * 3.0 + phase
	return {
		"sh": Vector3(0.3 + sway * 0.03, 0.0, 1.0 + sway * 0.04),
		"el": Vector3(0.3, 0.0, 0.95),
		"wr": Vector3(-0.15, -1.35, 0.25 + sway * 0.05),
		"idx": 0.25 + 0.2 * sin(wiggle),
		"fing": 0.45 + 0.2 * sin(wiggle + 0.9),
		"th": 0.25,
	}


func _blend_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a:
		if a[key] is Vector3:
			out[key] = (a[key] as Vector3).lerp(b[key], t)
		else:
			out[key] = lerpf(a[key], b[key], t)
	return out


func _apply_arm(arm: Dictionary, p: Dictionary) -> void:
	var side: float = arm["side"]
	var mirror := func(v: Vector3) -> Vector3: return Vector3(v.x, v.y * side, v.z * side)
	arm["shoulder"].rotation = mirror.call(p["sh"])
	arm["elbow"].rotation = mirror.call(p["el"])
	arm["wrist"].rotation = mirror.call(p["wr"])
	var fingers: Array = arm["fingers"]
	for i in fingers.size():
		var c: float = p["idx"] if i == 0 else p["fing"]
		fingers[i][0].rotation.x = -c
		fingers[i][1].rotation.x = -c * 1.1
	arm["thumb"].rotation.x = -p["th"]


# ---------------------------------------------------------------- model

func _build_model() -> void:
	var robe := Toon.outlined(Toon.mat(ROBE_COLOR, {"use_inner": true, "inner_color": LINING_COLOR}))
	var glove := Toon.outlined(Toon.mat(Color(0.97, 0.96, 0.93), {"shade": Color(0.62, 0.62, 0.8)}))
	var gold := Toon.outlined(Toon.mat(Color(1.0, 0.78, 0.25), {"shade": Color(0.62, 0.45, 0.4), "rim_strength": 0.8}))
	var gem := Toon.glow(Color(1.0, 0.15, 0.1), 1.6)
	_eye_mat = Toon.glow(EYE_COLOR, 2.5)

	_model = Toon.pivot(self)
	_body = Toon.pivot(_model)

	# Long robe pooling on the ground, with cloth folds and a lined hem.
	Toon.add(_body, Toon.lathe([Vector2(0.68, 0.0), Vector2(0.65, 0.07), Vector2(0.55, 0.26),
			Vector2(0.44, 0.5), Vector2(0.35, 0.7), Vector2(0.3, 0.88)], 32, 7, 0.09), robe)

	# Upper body pivots at the waist.
	_torso = Toon.pivot(_body, Vector3(0, 0.82, 0))
	Toon.add(_torso, Toon.lathe([Vector2(0.3, -0.04), Vector2(0.31, 0.2), Vector2(0.3, 0.36),
			Vector2(0.22, 0.46), Vector2(0.12, 0.5)], 24), robe, Vector3.ZERO, Vector3.ZERO, Vector3(1.22, 1, 1))
	# Shoulder mantle that drapes down from the hood.
	Toon.add(_torso, Toon.lathe([Vector2(0.5, 0.25), Vector2(0.45, 0.35), Vector2(0.32, 0.45),
			Vector2(0.18, 0.5)], 32, 8, 0.06), robe, Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1, 1.05))
	# Gold clasp with a red gem.
	Toon.add(_torso, Toon.torus(0.035, 0.062, 18, 8), gold, Vector3(0, 0.43, -0.4), Vector3(PI / 2.0 - 0.5, 0, 0))
	Toon.add(_torso, Toon.ball(0.036, 12, 8), gem, Vector3(0, 0.43, -0.41))

	# Deep hood, opening forward. The inside is pure black, so the face is a void.
	_hood = Toon.pivot(_torso, Vector3(0, 0.74, -0.02))
	var hood_mat := Toon.outlined(Toon.mat(ROBE_COLOR, {"use_inner": true, "inner_color": Color(0, 0, 0)}))
	var peak := func(v: Vector3) -> Vector3:
		var w := Vector3(v.x, v.z, -v.y)          # turn the cup to open toward -Z (forward)
		var t := clampf(w.y / 0.29, 0.0, 1.0) * clampf(w.z / 0.29, 0.0, 1.0)
		t *= t
		w.y += t * 0.24
		w.z += t * 0.2
		if w.y < 0.0:
			w.x *= 1.0 + 0.4 * clampf(-w.y / 0.29, 0.0, 1.0)
		return w
	Toon.add(_hood, Toon.lathe([Vector2(0.0, -0.3), Vector2(0.15, -0.27), Vector2(0.25, -0.17),
			Vector2(0.29, -0.04), Vector2(0.29, 0.09), Vector2(0.25, 0.21), Vector2(0.21, 0.3)], 26, 0, 0.0, peak),
			hood_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.08, 1.0))
	# Thick rolled rim around the opening.
	Toon.add(_hood, Toon.torus(0.19, 0.25, 26, 8), robe, Vector3(0, 0, -0.3), Vector3(PI / 2.0, 0, 0), Vector3(1.0, 1.0, 1.1))
	# Angry red eyes deep inside.
	for side in [1.0, -1.0]:
		Toon.add(_hood, Toon.ball(0.035, 12, 8), _eye_mat, Vector3(0.075 * side, 0.0, -0.17),
				Vector3(0, 0, 0.4 * side), Vector3(1.7, 0.75, 0.5))

	_arms["right"] = _build_arm(1.0, robe, glove)
	_arms["left"] = _build_arm(-1.0, robe, glove)
	_build_cloud()


## One arm: puffy upper sleeve, wide bell sleeve with lining, big white cartoon glove.
## side = 1 for right, -1 for left.
func _build_arm(side: float, robe: Material, glove: Material) -> Dictionary:
	var shoulder := Toon.pivot(_torso, Vector3(0.34 * side, 0.5, 0.02))
	Toon.add(shoulder, Toon.ball(0.15, 16, 10), robe, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.9, 1))
	Toon.add(shoulder, Toon.cyl(0.12, 0.13, 0.3, 16), robe, Vector3(0, -0.15, 0))
	var elbow := Toon.pivot(shoulder, Vector3(0, -0.31, 0))
	Toon.add(elbow, Toon.ball(0.13, 16, 10), robe)
	Toon.add(elbow, Toon.lathe([Vector2(0.23, -0.34), Vector2(0.18, -0.24), Vector2(0.145, -0.12),
			Vector2(0.125, 0.0)], 24, 5, 0.08), robe)
	var wrist := Toon.pivot(elbow, Vector3(0, -0.33, 0))
	var hand := Toon.pivot(wrist)
	hand.scale = Vector3.ONE * 1.3

	# Glove: cuff, palm, three chunky fingers and a thumb. The palm faces local +Z.
	Toon.add(hand, Toon.cyl(0.075, 0.095, 0.1, 16), glove, Vector3(0, 0.02, 0))
	Toon.add(hand, Toon.ball(0.105, 16, 10), glove, Vector3(0, -0.11, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.62))
	var fingers := []
	for i in 3:
		var k1 := Toon.pivot(hand, Vector3((i - 1) * 0.058 * -side, -0.17, 0.0))
		Toon.add(k1, Toon.capsule(0.036, 0.11), glove, Vector3(0, -0.04, 0))
		var k2 := Toon.pivot(k1, Vector3(0, -0.075, 0))
		Toon.add(k2, Toon.capsule(0.034, 0.1), glove, Vector3(0, -0.035, 0))
		fingers.append([k1, k2])
		if i == 0 and side > 0.0:
			fingertip = Marker3D.new()
			fingertip.position = Vector3(0, -0.085, 0)
			k2.add_child(fingertip)
	var thumb := Toon.pivot(hand, Vector3(-0.085 * side, -0.09, 0.02))
	thumb.rotation.z = -0.65 * side
	Toon.add(thumb, Toon.capsule(0.037, 0.12), glove, Vector3(0, -0.045, 0))
	return {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "fingers": fingers,
			"thumb": thumb, "side": side}


## A cartoon storm cloud he rides on while moving.
func _build_cloud() -> void:
	var cloud_mat := Toon.outlined(Toon.mat(Color(0.24, 0.2, 0.32), {"shade": Color(0.5, 0.45, 0.7), "rim_strength": 0.5}))
	_cloud_root = Toon.pivot(_model, Vector3(0, 0.12, 0))
	_cloud_root.visible = false
	var puff_mesh := Toon.ball(0.3, 14, 8)
	var spots := [Vector3(0, 0.02, 0), Vector3(0.45, 0, 0.1), Vector3(-0.42, 0, 0.18), Vector3(0.15, 0, 0.48),
			Vector3(-0.2, 0, -0.45), Vector3(0.38, 0.02, -0.32), Vector3(-0.5, 0.02, -0.15), Vector3(0.0, -0.08, 0.0)]
	var sizes := [1.4, 1.0, 0.95, 0.85, 0.9, 0.8, 0.75, 1.2]
	for i in spots.size():
		var base: Vector3 = Vector3(1.0, 0.75, 1.0) * sizes[i]
		var puff := Toon.add(_cloud_root, puff_mesh, cloud_mat, spots[i], Vector3.ZERO, base)
		puff.set_meta("base", base)
		_puffs.append(puff)

	# Small puffs that trail behind.
	_cloud = CPUParticles3D.new()
	_cloud.amount = 24
	_cloud.lifetime = 0.9
	_cloud.local_coords = false
	_cloud.mesh = Toon.ball(0.13, 10, 6)
	_cloud.material_override = Toon.mat(Color(0.24, 0.2, 0.32), {"shade": Color(0.5, 0.45, 0.7)})
	_cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_cloud.emission_sphere_radius = 0.45
	_cloud.direction = Vector3(0, 1, 0)
	_cloud.spread = 60.0
	_cloud.initial_velocity_min = 0.2
	_cloud.initial_velocity_max = 0.6
	_cloud.gravity = Vector3.ZERO
	_cloud.scale_amount_min = 0.8
	_cloud.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_cloud.scale_amount_curve = curve
	_cloud.emitting = false
	_cloud_root.add_child(_cloud)

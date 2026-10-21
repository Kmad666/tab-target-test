extends Node3D
## Builds the test level: a flat grass plane, sky, sun, the hooded caster,
## a training dummy, the camera, the lightning effect and the HUD.

const DUMMY_POSITION := Vector3(0, 0, -20)


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_ground()

	var dummy := TrainingDummy.new()
	dummy.position = DUMMY_POSITION
	add_child(dummy)

	var player := Player.new()
	add_child(player)

	var rig := CameraRig.new()
	rig.player = player
	add_child(rig)
	player.cam_rig = rig

	var lightning := ForceLightning.new()
	lightning.player = player
	add_child(lightning)

	var hud := HUD.new()
	add_child(hud)
	hud.setup(player)


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("turn_left", [KEY_A, KEY_LEFT])
	_bind("turn_right", [KEY_D, KEY_RIGHT])
	_bind("strafe_left", [KEY_Q])
	_bind("strafe_right", [KEY_E])
	_bind("target_next", [KEY_TAB])
	_bind("spell_1", [KEY_1])
	_bind("cancel", [KEY_ESCAPE])
	_bind("autorun", [KEY_NUMLOCK])
	_bind("toggle_help", [KEY_F1, KEY_H])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.45, 0.75)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.55, 0.62, 0.55)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground() -> void:
	# Soft rolling-meadow colors come from noise in the toon shader, so the plane is one cheap quad.
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var ground := Toon.add(self, plane, Toon.mat(Color(0.3, 0.5, 0.2), {
			"ground_noise": true, "ground_alt": Color(0.23, 0.42, 0.16),
			"shade": Color(0.55, 0.6, 0.75), "rim_strength": 0.0}))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Grass clumps: three blades each, drawn in one batch.
	var blade := Toon.cyl(0.0, 0.05, 0.42, 4, false)
	var tuft := MultiMesh.new()
	tuft.transform_format = MultiMesh.TRANSFORM_3D
	tuft.mesh = blade
	tuft.instance_count = 2400
	var i := 0
	while i < tuft.instance_count:
		var center := Vector3(rng.randf_range(-90, 90), 0.0, rng.randf_range(-90, 90))
		if center.distance_to(DUMMY_POSITION) < 1.6 or center.length() < 1.5:
			continue
		for b in 3:
			if i >= tuft.instance_count:
				break
			var lean := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.15, 0.45))
			lean = lean.scaled(Vector3.ONE * rng.randf_range(0.6, 1.2))
			var pos := center + Vector3(rng.randf_range(-0.12, 0.12), 0.18, rng.randf_range(-0.12, 0.12))
			tuft.set_instance_transform(i, Transform3D(lean, pos))
			i += 1
	var tuft_mi := MultiMeshInstance3D.new()
	tuft_mi.multimesh = tuft
	tuft_mi.material_override = Toon.mat(Color(0.2, 0.4, 0.14), {"shade": Color(0.6, 0.65, 0.8), "rim_strength": 0.0})
	tuft_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tuft_mi)

	# Rounded boulders.
	var rock_mat := Toon.outlined(Toon.mat(Color(0.62, 0.62, 0.68), {"shade": Color(0.5, 0.5, 0.72)}))
	var rock_mesh := Toon.ball(0.5, 12, 7)
	for r in 30:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(12.0, 90.0)
		var s := rng.randf_range(0.4, 1.3)
		Toon.add(self, rock_mesh, rock_mat, Vector3(cos(ang) * dist, 0.05, sin(ang) * dist),
				Vector3(0, rng.randf() * TAU, 0), Vector3(s * rng.randf_range(0.9, 1.5), s * 0.55, s))

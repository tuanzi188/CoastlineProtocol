extends SceneTree
## Studio rig for the infantry silhouette: deterministic pose driving,
## multi-angle captures and anthropometric checks. No gameplay loaded.
##
## Run:  Godot --path . --resolution 1280x720 --script res://tests/soldier_preview.gd
## Add `-- baseline` to capture without asserting (used to record the before state).

const SoldierModel = preload("res://scripts/soldier_model.gd")
const SoldierRig = preload("res://scripts/soldier_rig.gd")
const STEP: float = 1.0 / 60.0
const RUN_SAMPLE: float = 4.3

var studio: Node3D
var camera: Camera3D
var model: Node3D
var checks: Array[Dictionary] = []
var metrics: Dictionary = {}
var baseline: bool = false
var has_joints: bool = false
var foot_key: String = ""
var rig_mode: bool = false


func _initialize() -> void:
	call_deferred("run")


func check(label: String, value: bool, detail: String = "") -> void:
	checks.append({"name": label, "pass": value, "detail": detail})
	print(("PASS " if value else "FAIL ") + label + " " + detail)


func measure(label: String, value: float) -> void:
	metrics[label] = snappedf(value, 0.0001)
	print("METRIC %s %.4f" % [label, value])


func drive(target: Node3D, seconds: float, speed: float, aiming: bool, reloading: bool, dead: bool, dip: float = 0.0) -> void:
	for _frame: int in range(int(seconds / STEP)):
		target.call("animate", speed, aiming, reloading, dead, STEP, dip)
	await process_frame


func shot(label: String, at: Vector3, target: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.position = at
	camera.look_at(target, Vector3.UP)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var prefix: String = "soldier_b_" if baseline else ("soldier_rig_" if rig_mode else "soldier_")
	root.get_texture().get_image().save_png("res://tests/" + prefix + label + ".png")


## Model-space AABB of every mesh instance, keyed "Segment@ParentJoint".
func boxes(root_node: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var inverse: Transform3D = root_node.global_transform.affine_inverse()
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var instance: MeshInstance3D = node as MeshInstance3D
			var relative: Transform3D = inverse * instance.global_transform
			var local: AABB = relative * instance.mesh.get_aabb()
			result["%s@%s" % [String(node.name), (node.get_parent() as Node).name]] = local
			if OS.get_cmdline_user_args().has("raw"):
				print("RAW %s mesh=%s xform=%s" % [String(node.name), instance.mesh.get_aabb(), instance.transform])
		for child: Node in node.get_children():
			stack.append(child)
	return result


func union_of(collection: Dictionary) -> AABB:
	var result: AABB = collection.values()[0] as AABB
	for key: String in collection.keys():
		result = result.merge(collection[key] as AABB)
	return result


func lowest_of(collection: Dictionary) -> float:
	var result: float = 100.0
	for key: String in collection.keys():
		result = minf(result, (collection[key] as AABB).position.y)
	return result


func build_studio() -> void:
	studio = Node3D.new()
	root.add_child(studio)
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6fa8c8")
	sky_material.sky_horizon_color = Color("c6dbe0")
	sky_material.ground_bottom_color = Color("759795")
	sky_material.ground_horizon_color = Color("c6dbe0")
	sky_material.sky_curve = 0.17
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b4cfda")
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	studio.add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	studio.add_child(sun)
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("8b9089")
	floor_material.roughness = 0.95
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(9, 9)
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.name = "StudioFloor"
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_material
	studio.add_child(floor_instance)
	camera = Camera3D.new()
	camera.name = "StudioCamera"
	camera.near = 0.01
	camera.far = 60.0
	camera.fov = 40.0
	studio.add_child(camera)
	camera.current = true
	await process_frame


func run() -> void:
	baseline = "baseline" in OS.get_cmdline_user_args()
	rig_mode = OS.get_cmdline_user_args().has("rig")
	await build_studio()
	model = SoldierRig.new() if rig_mode else SoldierModel.new()
	model.name = "Soldier"
	model.call("build", 0)
	studio.add_child(model)
	await process_frame
	await process_frame

	var rest: Dictionary = boxes(model)
	var union: AABB = union_of(rest)
	measure("stature_m", union.size.y)
	measure("sole_offset_m", lowest_of(rest))
	measure("mesh_segments", float(rest.size()))
	has_joints = model.get("_hips") != null and model.get("_shoulders") != null
	if has_joints:
		measure("hip_height_m", (model.get("_hips")[0] as Node3D).global_position.y)
		measure("shoulder_span_m", (model.get("_shoulders")[0] as Node3D).global_position.distance_to(
			(model.get("_shoulders")[1] as Node3D).global_position))
	if rest.has("Torso@Torso"):
		var torso: AABB = rest["Torso@Torso"] as AABB
		measure("torso_width_m", torso.size.x)
		measure("carrier_depth_m", torso.size.z)
	if rest.has("Pelvis@Body"):
		measure("pelvis_width_m", (rest["Pelvis@Body"] as AABB).size.x)
	if rest.has("Head@Neck"):
		var head: AABB = rest["Head@Neck"] as AABB
		measure("head_width_m", head.size.x)
		measure("helmet_top_m", head.end.y)
	if rest.has("Thigh@Hip_L"):
		measure("thigh_width_m", (rest["Thigh@Hip_L"] as AABB).size.x)
	if rest.has("Shin@Knee_L"):
		measure("shin_width_m", (rest["Shin@Knee_L"] as AABB).size.x)
	if rest.has("Foot@Ankle_L"):
		var foot: AABB = rest["Foot@Ankle_L"] as AABB
		measure("foot_length_m", foot.size.z)
		measure("foot_height_m", foot.size.y)
	for key: String in rest.keys():
		print("AABB %s %s" % [key, rest[key]])
	var muzzle: Marker3D = model.get("muzzle") as Marker3D
	measure("muzzle_forward_m", -muzzle.global_position.z)
	measure("muzzle_height_m", muzzle.global_position.y)

	# Stride probes over a settled cycle at running speed.
	await drive(model, 2.0, RUN_SAMPLE, false, false, false)
	var lowest_geometry: float = 100.0
	var max_knee: float = 0.0
	var min_knee: float = 100.0
	var pelvis_yaw: float = 0.0
	var slip: float = 0.0
	var humerus_min: float = 9.0
	var humerus_max: float = 0.0
	var ulna_min: float = 9.0
	var ulna_max: float = 0.0
	if not rest.has("Foot@Ankle_L"):
		print("RIG MODE: skeletal probes unavailable, measuring the hull only")
		has_joints = false
		foot_key = ""
	else:
		foot_key = "Foot@Ankle_L"
	var previous_foot: float = (rest[foot_key] as AABB).position.z if foot_key != "" else 0.0
	var was_grounded: bool = true
	var stance_hits: int = 0
	var slip_hits: int = 0
	for _tick: int in range(150):
		await drive(model, 0.06, RUN_SAMPLE, false, false, false)
		var sampled: Dictionary = boxes(model)
		lowest_geometry = minf(lowest_geometry, lowest_of(sampled))
		if foot_key == "":
			continue
		var foot: AABB = sampled[foot_key] as AABB
		# A planted foot must travel backwards at exactly the gait speed; a foot
		# in the air may travel any amount, so only grounded samples are compared.
		var grounded: bool = foot.position.y < 0.020
		stance_hits += 1 if grounded else 0
		if grounded and was_grounded:
			slip = maxf(slip, absf(absf(foot.position.z - previous_foot) / 0.06 - RUN_SAMPLE))
			slip_hits += 1
		previous_foot = foot.position.z
		was_grounded = grounded
		for knee: Node3D in (model.get("_knees") if has_joints else []):
			var bend: float = absf(knee.rotation.x)
			max_knee = maxf(max_knee, bend)
			min_knee = minf(min_knee, bend)
		if has_joints:
			pelvis_yaw = maxf(pelvis_yaw, absf((model.get("_body") as Node3D).rotation.y))
		for index: int in (range(2) if has_joints else []):
			var shoulder: Node3D = (model.get("_shoulders") as Array)[index] as Node3D
			var elbow: Node3D = (model.get("_elbows") as Array)[index] as Node3D
			var length: float = shoulder.global_position.distance_to(elbow.global_position)
			humerus_min = minf(humerus_min, length)
			humerus_max = maxf(humerus_max, length)
			var wrist: Vector3 = ((model.get("_wrists") as Array)[index] as Node3D).global_position
			var fore: float = elbow.global_position.distance_to(wrist)
			ulna_min = minf(ulna_min, fore)
			ulna_max = maxf(ulna_max, fore)
	measure("stride_lowest_geometry_m", lowest_geometry)
	measure("stance_foot_slip_mps", slip / maxf(1.0, float(slip_hits)) if slip_hits > 0 else 0.0)
	measure("stance_foot_slip_peak_mps", slip)
	measure("stance_share", float(stance_hits) / 150.0)
	measure("knee_max_rad", max_knee)
	measure("knee_min_rad", min_knee)
	measure("pelvis_yaw_rad", pelvis_yaw)
	measure("humerus_min_m", humerus_min)
	measure("humerus_max_m", humerus_max)
	measure("ulna_min_m", ulna_min)
	measure("ulna_max_m", ulna_max)

	# A landing squash must bend the knees without burying the boots.
	await drive(model, 1.0, 0.0, false, false, false)
	await drive(model, 0.5, 2.5, false, false, false, 0.11)
	var dipped: Dictionary = boxes(model)
	measure("dip_lowest_geometry_m", lowest_of(dipped))
	if has_joints:
		measure("dip_knee_rad", absf((model.get("_knees") as Array)[0].rotation.x))
	await drive(model, 1.0, 0.0, false, false, false)

	await shot("01_three_quarter", Vector3(2.05, 1.45, -2.35), Vector3(0.0, 1.02, 0.0), 38.0)
	await shot("02_front", Vector3(0.0, 1.35, -3.1), Vector3(0.0, 1.05, 0.0), 34.0)
	await shot("03_side", Vector3(3.1, 1.30, 0.0), Vector3(0.0, 1.02, 0.0), 34.0)
	await shot("04_back", Vector3(0.0, 1.40, 3.1), Vector3(0.0, 1.05, 0.0), 34.0)
	await drive(model, 1.2, 0.0, false, false, false)
	await shot("05_idle", Vector3(1.85, 1.55, -2.05), Vector3(0.0, 1.15, 0.0), 32.0)
	await shot("06_face", Vector3(0.38, 1.70, -0.66), Vector3(0.0, 1.64, -0.04), 24.0)
	await shot("07_helmet_back", Vector3(-0.44, 1.84, 0.66), Vector3(0.0, 1.72, 0.02), 24.0)
	await shot("08_torso", Vector3(0.66, 1.30, -0.90), Vector3(0.02, 1.24, 0.0), 26.0)
	await shot("09_boots", Vector3(0.38, 0.30, -0.64), Vector3(0.0, 0.12, -0.04), 24.0)
	await shot("10_hands_rifle", Vector3(0.62, 1.42, -0.86), Vector3(0.04, 1.24, -0.34), 24.0)

	await drive(model, 2.0, RUN_SAMPLE, false, false, false)
	for index: int in range(4):
		await shot("1%d_stride" % (index + 1), Vector3(2.85, 1.10, 0.0), Vector3(0.0, 0.94, 0.0), 32.0)
		await drive(model, 0.135, RUN_SAMPLE, false, false, false)
	await drive(model, 0.4, RUN_SAMPLE, false, false, false)
	await shot("20_run_front", Vector3(0.35, 1.30, -2.9), Vector3(0.0, 1.02, 0.0), 34.0)
	await drive(model, 1.4, 0.0, true, false, false)
	await shot("21_aim", Vector3(1.85, 1.62, -1.85), Vector3(0.0, 1.30, -0.20), 32.0)
	await shot("22_aim_side", Vector3(2.6, 1.55, 0.35), Vector3(0.0, 1.30, -0.25), 32.0)
	await drive(model, 1.4, 0.0, false, false, false)
	await drive(model, 0.75, 0.0, false, true, false)
	await shot("23_reload", Vector3(0.92, 1.44, -1.02), Vector3(0.0, 1.16, -0.22), 30.0)
	await drive(model, 1.2, 0.0, false, false, false)
	model.call("flinch")
	await drive(model, 0.12, 0.0, false, false, false)
	await shot("24_flinch", Vector3(1.95, 1.48, -1.90), Vector3(0.0, 1.15, 0.0), 34.0)

	var fallen: Node3D = SoldierModel.new()
	fallen.name = "SoldierFall"
	fallen.call("build", 1)
	fallen.position = Vector3(2.7, 0.0, 0.0)
	studio.add_child(fallen)
	await process_frame
	await drive(fallen, 0.35, 0.0, false, false, true)
	await shot("25_fall_buckle", Vector3(2.7, 0.95, 2.6), Vector3(2.7, 0.50, 0.0), 34.0)
	await drive(fallen, 0.45, 0.0, false, false, true)
	await shot("26_fall_topple", Vector3(2.7, 0.95, 2.6), Vector3(2.7, 0.35, 0.0), 34.0)
	await drive(fallen, 2.0, 0.0, false, false, true)
	var prone_boxes: Dictionary = boxes(fallen)
	for key: String in prone_boxes.keys():
		print("FALLEN %s %s" % [key, prone_boxes[key]])
	var prone: AABB = union_of(prone_boxes)
	measure("fallen_height_m", prone.size.y)
	measure("fallen_sink_m", prone.position.y)
	measure("fallen_length_m", prone.size.z)
	await shot("27_dead_settled", Vector3(2.7, 1.30, 2.9), Vector3(2.7, 0.25, 0.0), 34.0)

	report()



func report() -> void:
	if not baseline:
		# Each rule names the metric it needs; a rule whose metric the current rig
		# does not expose is skipped rather than failed.
		var rules: Array = [
			["stature reads human 1.72-1.95 m", "stature_m", 1.72, 1.95, "%.3f"],
			["sole sits on the ground plane", "sole_offset_m", -0.012, 0.012, "%.4f"],
			["legs carry 48-58% of stature", "leg_share", 0.48, 0.58, "%.3f"],
			["shoulder span 0.36-0.48 m", "shoulder_span_m", 0.36, 0.48, "%.3f"],
			["shoulder yoke reads 0.40-0.50 m", "torso_width_m", 0.40, 0.50, "%.3f"],
			["hip shelf reads 0.30-0.38 m", "pelvis_width_m", 0.30, 0.38, "%.3f"],
			["thigh reads as a leg not a pylon", "thigh_width_m", 0.14, 0.21, "%.3f"],
			["shin tapers below the knee", "shin_taper", 0.0, 0.80, "%.2f"],
			["boot is foot-sized", "foot_length_m", 0.20, 0.29, "%.3f"],
			["boot stays below the ankle joint", "foot_height_m", 0.0, 0.16, "%.3f"],
			["nothing buries into the floor mid-stride", "stride_lowest_geometry_m", -0.012, 10.0, "%.4f"],
			["foot is planted for part of the cycle", "stance_share", 0.20, 0.85, "%.2f"],
			["knee flexes through a human range", "knee_max_rad", 0.05, 1.40, "%.2f"],
			["pelvis counter-rotates while walking", "pelvis_yaw_rad", 0.03, 10.0, "%.3f"],
			["humerus keeps its length", "humerus_delta_m", 0.0, 0.004, "%.4f"],
			["ulna keeps its length", "ulna_delta_m", 0.0, 0.004, "%.4f"],
			["landing squash keeps boots on the deck", "dip_lowest_geometry_m", -0.012, 10.0, "%.4f"],
			["landing squash bends the knees", "dip_knee_rad", 0.25, 10.0, "%.3f"],
			["corpse flattens to a lying hull", "fallen_height_m", 0.0, 0.78, "%.2f"],
			["corpse lies out full length", "fallen_length_m", 1.75, 10.0, "%.2f"],
			["corpse does not sink into the deck", "fallen_sink_m", -0.05, 10.0, "%.3f"],
			["muzzle stays ahead of the chest", "muzzle_forward_m", 0.55, 10.0, "%.2f"],
			["muzzle sits at chest height", "muzzle_height_m", 1.05, 10.0, "%.2f"],
			["rig stays under 22 mesh segments", "mesh_segments", 0.0, 22.0, "%.0f"],
		]
		if metrics.has("stature_m") and metrics.has("hip_height_m"):
			metrics["leg_share"] = metrics["hip_height_m"] / metrics["stature_m"]
		if metrics.has("shin_width_m") and metrics.has("thigh_width_m"):
			metrics["shin_taper"] = metrics["shin_width_m"] / metrics["thigh_width_m"]
		if metrics.has("humerus_max_m") and metrics.has("humerus_min_m"):
			metrics["humerus_delta_m"] = metrics["humerus_max_m"] - metrics["humerus_min_m"]
		if metrics.has("ulna_max_m") and metrics.has("ulna_min_m"):
			metrics["ulna_delta_m"] = metrics["ulna_max_m"] - metrics["ulna_min_m"]
		for rule: Array in rules:
			var key: String = rule[1]
			if not metrics.has(key):
				print("SKIP  %s (metric not exposed by this rig)" % rule[0])
				continue
			var value: float = metrics[key]
			check(rule[0], value >= rule[2] and value <= rule[3], rule[4] % value)
	var failures: int = 0
	for entry: Dictionary in checks:
		if not entry.pass:
			failures += 1
	var out: String = "res://tests/soldier_rig_results.json" if rig_mode else "res://tests/soldier_results.json"
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"mode": "baseline" if baseline else "assert",
		"passed": checks.size() - failures,
		"failed": failures,
		"metrics": metrics,
		"checks": checks,
	}, "  "))
	file.close()
	print("SOLDIER_RESULT %s %d/%d" % ["baseline" if baseline else "assert", checks.size() - failures, checks.size()])
	quit(1 if (failures > 0 and not baseline) else 0)

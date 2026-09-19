extends Node3D
## Anatomically proportioned infantry rig for a 1.80 m stature, facing local -Z.
## Limbs run on two-bone IK so bone lengths never change between poses and the
## soles stay planted instead of sweeping through the ground.
##
## Each segment merges all of its primitives into one multi-surface mesh, and
## finished meshes are cached per colour variant, so nine soldiers share at most
## four geometry uploads.

const Form = preload("res://scripts/procedural_form.gd")

# --- Anthropometry, metres ---------------------------------------------------
const HIP_Y: float = 0.955
const HIP_X: float = 0.095
const THIGH: float = 0.455
const SHIN: float = 0.435
const ANKLE: float = 0.075
const BOOT_HALF: float = 0.118
const PRONE_LIFT: float = 0.325
const SPINE_Y: float = 1.000
const SHOULDER_Y: float = 1.420
const SHOULDER_X: float = 0.185
const HUMERUS: float = 0.335
const ULNA: float = 0.265
const HEAD_Y: float = 1.530
const STATURE: float = 1.813
const RUN_SPEED: float = 4.3

const CADENCE: float = 0.250
const CADENCE_GAIN: float = 0.225

# --- Weapon sockets, rifle local space --------------------------------------
const GRIP_TRIGGER: Vector3 = Vector3(0.0, -0.052, 0.030)
const GRIP_SUPPORT: Vector3 = Vector3(0.0, -0.026, -0.215)
const MUZZLE_AT: Vector3 = Vector3(0.0, 0.012, -0.700)

static var _mesh_cache: Dictionary = {}
static var _paint_cache: Dictionary = {}

var muzzle: Marker3D
var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _weapon: Node3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _wrists: Array[Node3D] = []
var _built: bool = false
var _variant: int = 0
var _phase: float = 0.0
var _bob: float = 0.0
var _fall: float = 0.0
var _flinch: float = 0.0
var _reload_phase: float = -1.0
var _aim_blend: float = 0.0


func build(variant: int = 0) -> void:
	if _built:
		return
	_built = true
	_variant = posmod(variant, 4)
	var parts: Dictionary = _shared_parts()
	_body = _joint(self, "Body", Vector3.ZERO)
	_part(_body, parts, "Pelvis")
	_torso = _joint(_body, "Torso", Vector3(0, SPINE_Y, 0))
	_part(_torso, parts, "Torso")
	_head = _joint(_torso, "Neck", Vector3(0, HEAD_Y - SPINE_Y, 0))
	_part(_head, parts, "Head")
	_weapon = _joint(_torso, "Rifle", Vector3(0.095, 0.155, -0.135))
	_part(_weapon, parts, "Rifle")
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = MUZZLE_AT
	_weapon.add_child(muzzle)
	for side: float in [-1.0, 1.0]:
		var tag: String = "_L" if side < 0.0 else "_R"
		var hip: Node3D = _joint(_body, "Hip" + tag, Vector3(side * HIP_X, HIP_Y, 0))
		_hips.append(hip)
		_part(hip, parts, "Thigh")
		var knee: Node3D = _joint(hip, "Knee" + tag, Vector3(0, -THIGH, 0))
		_knees.append(knee)
		_part(knee, parts, "Shin")
		var ankle: Node3D = _joint(knee, "Ankle" + tag, Vector3(0, -SHIN, 0))
		_ankles.append(ankle)
		_part(ankle, parts, "Foot")
		var shoulder: Node3D = _joint(_torso, "Shoulder" + tag, Vector3(side * SHOULDER_X, SHOULDER_Y - SPINE_Y, 0))
		_shoulders.append(shoulder)
		_part(shoulder, parts, "UpperArm")
		var elbow: Node3D = _joint(shoulder, "Elbow" + tag, Vector3(0, -HUMERUS, 0))
		_elbows.append(elbow)
		_part(elbow, parts, "ForeArm")
		var wrist: Node3D = _joint(elbow, "Wrist" + tag, Vector3(0, -ULNA, 0))
		_wrists.append(wrist)
		_part(wrist, parts, "HandL" if side < 0.0 else "HandR")
	_pose_stance(0.0, 0.0, false, 0.0)


func flinch() -> void:
	_flinch = 1.0


func animate(speed: float, aiming: bool, reloading: bool, dead: bool, delta: float, dip: float = 0.0) -> void:
	if not _built:
		build()
	if delta <= 0.0:
		return
	if dead:
		_collapse(delta)
		return
	var stride: float = clampf(speed / RUN_SPEED, 0.0, 1.0)
	_flinch = maxf(0.0, _flinch - delta * 3.2)
	var gait: float = clampf(speed / 0.6, 0.0, 1.0)
	_phase = fmod(_phase + delta * (CADENCE + speed * CADENCE_GAIN) * gait, 1.0)
	var ease_in: float = 1.0 - exp(-13.0 * delta)
	_aim_blend = lerpf(_aim_blend, 1.0 if aiming else 0.0, 1.0 - exp(-9.0 * delta))
	if reloading:
		_reload_phase = fmod(_reload_phase + delta * 0.50, 1.0) if _reload_phase >= 0.0 else 0.0
	else:
		_reload_phase = -1.0

	# A landing squash lowers the pelvis and lets the IK bend the knees, which
	# keeps the soles on the floor instead of driving them through it.
	_bob = lerpf(_bob, -0.020 * (1.0 - cos(TAU * 2.0 * _phase)) * 0.5 * stride - dip, ease_in)
	_body.position.y = _bob
	_body.rotation = Vector3(
		lerpf(_body.rotation.x, 0.032 * stride, ease_in),
		lerpf(_body.rotation.y, 0.078 * sin(TAU * _phase) * stride, ease_in),
		lerpf(_body.rotation.z, 0.034 * sin(TAU * _phase) * stride, ease_in))
	_torso.position.y = SPINE_Y
	_torso.rotation = Vector3(
		lerpf(_torso.rotation.x, 0.060 * stride + 0.16 * _flinch, ease_in),
		lerpf(_torso.rotation.y, -0.110 * sin(TAU * _phase) * stride, ease_in),
		lerpf(_torso.rotation.z, -0.028 * sin(TAU * _phase) * stride, ease_in))
	_head.rotation = Vector3(
		lerpf(_head.rotation.x, -0.060 * stride - 0.205 * _aim_blend + 0.26 * _flinch, ease_in),
		lerpf(_head.rotation.y, 0.042 * sin(TAU * _phase) * stride - 0.12 * _flinch, ease_in),
		lerpf(_head.rotation.z, -0.018 * sin(TAU * _phase) * stride, ease_in))
	_carry_weapon(stride, reloading, ease_in)
	for index: int in range(2):
		_plant_leg(index, stride, dip, delta)
		_pose_arm(index)


func _plant_leg(index: int, stride: float, dip: float, delta: float) -> void:
	var side: float = -1.0 if index == 0 else 1.0
	# Stance shortens and the stride lengthens as the gait turns into a run,
	# which is what keeps the swept-back foot from lagging the body.
	var cycle: float = fmod(_phase + 0.5 * float(index), 1.0)
	var stance: float = lerpf(0.48, 0.34, stride)
	var ahead: float = 0.36 * stride
	var behind: float = 0.55 * stride
	var hip: Vector3 = Vector3(side * HIP_X, HIP_Y, 0)
	var forward: float = 0.0
	var lift: float = 0.0
	var pitch: float = 0.0
	if cycle < stance:
		var t: float = cycle / stance
		forward = lerpf(ahead, -behind, t)
		pitch = lerpf(0.13, -0.28, clampf((t - 0.60) / 0.40, 0.0, 1.0))
	else:
		var t: float = (cycle - stance) / (1.0 - stance)
		forward = lerpf(-behind, ahead, t * t * (3.0 - 2.0 * t))
		lift = sin(PI * t) * (0.055 + 0.075 * stride) * stride
		pitch = lerpf(-0.28, 0.13, t)
	pitch *= stride
	# Rolling onto the heel or the toe would drive that end through the
	# deck, so the ankle rises by however much the boot pivots down.
	var clearance: float = BOOT_HALF * absf(sin(pitch))
	var target: Vector3 = Vector3(side * (HIP_X + 0.014), ANKLE + lift + dip + clearance, -forward)
	# The knee sits ahead of the hip-to-ankle line, which is what keeps the joint
	# from hyperextending when the leg reaches behind the body.
	var solved: Array = _two_bone(hip, target, THIGH, SHIN, Vector3(0, 0.0, -1))
	var upper: Quaternion = _align(solved[0] as Vector3)
	_hips[index].quaternion = upper
	_knees[index].quaternion = upper.inverse() * _align(solved[1] as Vector3)
	# The shin is tilted by the gait; the boot has to cancel that or it lands
	# toe-down and reads as standing on a wedge.
	var shin: Vector3 = solved[1] as Vector3
	var sole: Vector3 = Vector3(pitch - atan2(-shin.z, -shin.y), side * 0.13, -atan2(shin.x, -shin.y))
	_ankles[index].rotation = _ankles[index].rotation.lerp(sole, 1.0 - exp(-17.0 * delta))


func _carry_weapon(stride: float, reloading: bool, ease_in: float) -> void:
	var ready: Vector3 = Vector3(0.095, 0.155, -0.135)
	var aimed: Vector3 = Vector3(0.032, 0.352, -0.298)
	var place: Vector3 = ready.lerp(aimed, _aim_blend)
	var tilt: Vector3 = Vector3(
		lerpf(-0.15, 0.0, _aim_blend) + 0.028 * sin(TAU * _phase) * stride,
		lerpf(0.11, 0.0, _aim_blend),
		lerpf(0.07, 0.015, _aim_blend) + 0.020 * sin(PI * _phase) * stride)
	if _reload_phase >= 0.0:
		# Cant the magazine well up toward the support hand.
		var roll: float = sin(PI * clampf(_reload_phase / 0.62, 0.0, 1.0))
		place += Vector3(-0.026 * roll, 0.048 * roll, 0.052 * roll)
		tilt += Vector3(0.20 * roll, -0.14 * roll, -0.58 * roll)
	_weapon.position = _weapon.position.lerp(place, ease_in)
	_weapon.rotation = tilt


func _pose_arm(index: int) -> void:
	var side: float = -1.0 if index == 0 else 1.0
	var shoulder: Vector3 = Vector3(side * SHOULDER_X, SHOULDER_Y - SPINE_Y, 0)
	var socket: Vector3 = GRIP_TRIGGER if index == 1 else GRIP_SUPPORT
	if _reload_phase >= 0.0 and index == 0:
		var reach: float = sin(PI * clampf(_reload_phase / 0.62, 0.0, 1.0))
		socket = Vector3(-0.024, -0.090 - 0.030 * reach, -0.170)
	var grip: Vector3 = _weapon.transform * socket
	var solved: Array = _two_bone(shoulder, grip, HUMERUS, ULNA, Vector3(side * 0.62, -0.68, 0.42))
	var upper: Quaternion = _align(solved[0] as Vector3)
	_shoulders[index].quaternion = upper
	_elbows[index].quaternion = upper.inverse() * _align(solved[1] as Vector3)


func _collapse(delta: float) -> void:
	_fall = minf(1.0, _fall + delta * 1.30)
	# Knees give first, then the centre of mass passes beyond the base of
	# support and the whole rig rotates down onto the deck.
	var buckle: float = clampf(_fall / 0.32, 0.0, 1.0)
	var topple: float = clampf((_fall - 0.24) / 0.54, 0.0, 1.0)
	topple = topple * topple * (3.0 - 2.0 * topple)
	var settle: float = clampf((_fall - 0.70) / 0.30, 0.0, 1.0)
	var give: float = buckle * (1.0 - topple)
	# Lie fully flat (90 deg) and lift the pivot so the chest/back rest on the
	# deck instead of the toes and muzzle poking through it.
	_body.position.y = PRONE_LIFT * topple - 0.055 * give
	_body.rotation = Vector3(-1.57 * topple, 0.07 * topple, 0.11 * topple)
	_torso.rotation = Vector3(0.22 * give + 0.03 * topple, 0.14 * settle, -0.09 * topple)
	_head.rotation = Vector3(-0.26 * give - 0.16 * topple + 0.10 * settle, 0.20 * settle, 0.18 * settle)
	for index: int in range(2):
		var side: float = -1.0 if index == 0 else 1.0
		var fold: float = 1.42 if index == 0 else 1.08
		_hips[index].rotation = Vector3(0.58 * give + 0.04 * topple, 0, side * 0.14 * buckle)
		_knees[index].rotation = Vector3(-(fold * give + 0.18 * topple), 0, 0)
		# When prone the shin is horizontal, so the ankle must roll 90 deg for the
		# sole to face the deck and the toes to point along the body instead of down.
		_ankles[index].rotation = Vector3(0.20 * give - 1.55 * topple, side * 0.13, 0)
		# Arms are posed in torso space, so they have to lie along the body axis
		# that is already horizontal; a world-space direction would fling them up.
		var upper: Quaternion = _align(Vector3(side * 0.72, -0.66, 0.22).normalized())
		_shoulders[index].quaternion = upper
		_elbows[index].quaternion = upper.inverse() * _align(Vector3(side * 0.80, -0.55, 0.24).normalized())
	# Once the torso is horizontal the rifle's forward axis points straight at
	# the deck, so it has to swing down alongside the body instead.
	_weapon.rotation = Vector3(1.40 * topple, -0.10 * topple, -0.12 * topple)
	_weapon.position = Vector3(0.095 + 0.34 * topple, 0.155 - 0.02 * topple, -0.135 + 0.16 * topple)


func _pose_stance(speed: float, dip: float, dead: bool, delta: float) -> void:
	# Settle the rig into a neutral pose before the first rendered frame.
	for _tick: int in range(24):
		if dead:
			_collapse(1.0 / 60.0)
		else:
			animate(speed, false, false, false, 1.0 / 60.0, dip)


func _two_bone(root: Vector3, target: Vector3, first: float, second: float, pole: Vector3) -> Array:
	var reach: Vector3 = target - root
	var distance: float = clampf(reach.length(), absf(first - second) + 0.02, first + second - 0.006)
	var axis: Vector3 = (reach / reach.length()) if reach.length_squared() > 0.000001 else Vector3.DOWN
	# The chain is solved against the clamped target, never the requested one, so
	# an out-of-reach foot stops short instead of overshooting through the deck.
	target = root + axis * distance
	var cosine: float = clampf((first * first + distance * distance - second * second) / (2.0 * first * distance), -1.0, 1.0)
	var offset: float = acos(cosine)
	var lateral: Vector3 = pole - axis * pole.dot(axis)
	if lateral.length_squared() < 0.0001:
		lateral = Vector3(0, 0, 1) - axis * axis.z
	var upper: Vector3 = (axis * cos(offset) + lateral.normalized() * sin(offset)).normalized()
	return [upper, (target - (root + upper * first)).normalized()]


func _align(direction: Vector3) -> Quaternion:
	if direction.y > 0.9998:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(Vector3.DOWN, direction.normalized())


func _joint(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node


func _part(parent: Node3D, parts: Dictionary, key: String) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = key
	instance.mesh = parts[key]
	parent.add_child(instance)
	return instance


# --- Shared geometry ---------------------------------------------------------
func _shared_parts() -> Dictionary:
	if _mesh_cache.has(_variant):
		return _mesh_cache[_variant]
	var paints: Dictionary = _paints(_variant)
	var parts: Dictionary = {}
	var table: Array = [
		["Pelvis", _pelvis_form], ["Torso", _torso_form], ["Head", _head_form],
		["Thigh", _thigh_form], ["Shin", _shin_form], ["Foot", _foot_form],
		["UpperArm", _upper_arm_form], ["ForeArm", _forearm_form],
		["HandR", _hand_right_form], ["HandL", _hand_left_form], ["Rifle", _rifle_form],
	]
	for entry: Array in table:
		var form: RefCounted = Form.new()
		entry[1].call(form)
		parts[entry[0]] = _finish(form, paints)
	_mesh_cache[_variant] = parts
	return parts


func _finish(form: RefCounted, paints: Dictionary) -> ArrayMesh:
	var mesh: ArrayMesh = form.commit()
	var keys: Array = form.surface_keys()
	for index: int in range(mesh.get_surface_count()):
		mesh.surface_set_material(index, paints[keys[min(index, keys.size() - 1)]])
	return mesh


func _paints(variant: int) -> Dictionary:
	if _paint_cache.has(variant):
		return _paint_cache[variant]
	var uniforms: Array[Color] = [Color("5a6757"), Color("6a6558"), Color("51636b"), Color("726753")]
	var result: Dictionary = {
		"cloth": _paint(uniforms[variant]),
		"armor": _paint(Color("333f39"), 0.10),
		"webbing": _paint(Color("857f68")),
		"boots": _paint(Color("242826"), 0.06),
		"skin": _paint(Color("b98c6b") if variant % 2 == 0 else Color("8e674e")),
		"dark": _paint(Color("463529")),
		"steel": _paint(Color("2f373b"), 0.72),
		"lens": _paint(Color("26404a"), 0.55),
		"rubber": _paint(Color("1b1f1d"), 0.04),
		"sclera": _paint(Color("d8d2c6")),
	}
	_paint_cache[variant] = result
	return result


func _paint(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.90 if metal == 0.0 else 0.42
	material.metallic = metal
	return material


# --- Segment geometry -------------------------------------------------------
# Vertical limbs are authored pointing down from their joint, so a loft section
# reads as (half width lateral, half depth fore-aft).
func _pelvis_form(form: RefCounted) -> void:
	form.add_loft(
		[Vector3(0, 0.845, 0.004), Vector3(0, 0.905, 0.007), Vector3(0, 0.965, 0.005), Vector3(0, 1.018, 0.0)],
		[Vector2(0.149, 0.104), Vector2(0.161, 0.115), Vector2(0.156, 0.112), Vector2(0.146, 0.106)],
		"cloth", 16, 5)
	for side: float in [-1.0, 1.0]:
		form.add_ellipsoid(Vector3(0.060, 0.064, 0.060), Vector3(side * HIP_X, HIP_Y, 0), "cloth")
		form.add_ellipsoid(Vector3(0.052, 0.040, 0.048), Vector3(side * 0.128, 0.876, 0.006), "cloth")
	form.add_revolve(
		[Vector2(0.147, 0.977), Vector2(0.156, 0.983), Vector2(0.156, 1.007), Vector2(0.147, 1.013)],
		"webbing", Vector2(1.0, 0.72), Vector3.ZERO, 22)
	form.add_box(Vector3(0.032, 0.028, 0.013), Vector3(0, 0.995, -0.113), "dark")
	form.add_box(Vector3(0.072, 0.086, 0.040), Vector3(0.062, 0.965, 0.104), "webbing")
	form.add_box(Vector3(0.058, 0.070, 0.034), Vector3(-0.070, 0.972, 0.108), "webbing")


func _torso_form(form: RefCounted) -> void:
	form.add_loft(
		[Vector3(0, 0.000, 0.004), Vector3(0, 0.070, 0.006), Vector3(0, 0.150, 0.003),
			Vector3(0, 0.240, -0.003), Vector3(0, 0.330, -0.008), Vector3(0, 0.408, -0.010),
			Vector3(0, 0.452, -0.004), Vector3(0, 0.488, 0.002), Vector3(0, 0.556, 0.004)],
		[Vector2(0.147, 0.106), Vector2(0.141, 0.101), Vector2(0.147, 0.107), Vector2(0.160, 0.113),
			Vector2(0.172, 0.118), Vector2(0.175, 0.112), Vector2(0.132, 0.094), Vector2(0.060, 0.064),
			Vector2(0.048, 0.052)],
		"cloth", 18, 5)
	for side: float in [-1.0, 1.0]:
		form.add_ellipsoid(Vector3(0.054, 0.062, 0.056), Vector3(side * 0.178, 0.392, 0.002), "cloth")
		form.add_ellipsoid(Vector3(0.062, 0.040, 0.050), Vector3(side * 0.098, 0.432, -0.004), "cloth")
		form.add_ellipsoid(Vector3(0.056, 0.090, 0.036), Vector3(side * 0.110, 0.272, 0.080), "cloth")
	# Carrier: cummerbund, then plates rounded to the torso instead of slabs.
	form.add_loft(
		[Vector3(0, 0.052, 0.006), Vector3(0, 0.160, -0.002), Vector3(0, 0.300, -0.008), Vector3(0, 0.412, -0.010)],
		[Vector2(0.160, 0.119), Vector2(0.167, 0.126), Vector2(0.182, 0.132), Vector2(0.184, 0.125)],
		"armor", 16, 5)
	form.add_ellipsoid(Vector3(0.152, 0.158, 0.026), Vector3(0, 0.248, -0.122), "armor")
	form.add_ellipsoid(Vector3(0.158, 0.162, 0.022), Vector3(0, 0.254, 0.122), "armor")
	for side: float in [-1.0, 1.0]:
		form.add_loft(
			[Vector3(side * 0.086, 0.436, -0.112), Vector3(side * 0.098, 0.482, -0.050),
				Vector3(side * 0.104, 0.476, 0.030), Vector3(side * 0.092, 0.424, 0.108)],
			[Vector2(0.029, 0.010), Vector2(0.030, 0.011), Vector2(0.030, 0.011), Vector2(0.028, 0.010)],
			"armor", 10, 5, Vector3.UP)
	for index: int in range(3):
		var lane: float = float(index - 1) * 0.088
		form.add_box(Vector3(0.068, 0.124, 0.040), Vector3(lane, 0.200, -0.148), "webbing")
		form.add_ellipsoid(Vector3(0.034, 0.022, 0.021), Vector3(lane, 0.262, -0.148), "webbing")
		form.add_box(Vector3(0.052, 0.008, 0.036), Vector3(lane, 0.266, -0.156), "dark")
	form.add_box(Vector3(0.112, 0.092, 0.032), Vector3(0.112, 0.348, -0.132), "webbing")
	form.add_box(Vector3(0.038, 0.050, 0.026), Vector3(0.126, 0.444, -0.116), "dark")
	form.add_box(Vector3(0.026, 0.026, 0.062), Vector3(0.126, 0.482, -0.106), "steel")
	# Pack: one rounded pouch sitting close to the back plate.
	form.add_ellipsoid(Vector3(0.138, 0.152, 0.056), Vector3(0, 0.288, 0.186), "cloth")
	form.add_box(Vector3(0.206, 0.014, 0.014), Vector3(0, 0.356, 0.214), "webbing")
	form.add_box(Vector3(0.206, 0.014, 0.014), Vector3(0, 0.222, 0.214), "webbing")
	form.add_revolve(
		[Vector2(0.056, 0.468), Vector2(0.068, 0.486), Vector2(0.067, 0.510), Vector2(0.054, 0.520)],
		"cloth", Vector2(1.0, 1.06), Vector3.ZERO, 18)
func _head_form(form: RefCounted) -> void:
	form.add_ellipsoid(Vector3(0.0775, 0.0980, 0.1025), Vector3(0, 0.1500, 0.0060), "skin")
	form.add_ellipsoid(Vector3(0.0720, 0.0800, 0.0680), Vector3(0, 0.1330, 0.0500), "skin")
	form.add_ellipsoid(Vector3(0.0700, 0.0600, 0.0560), Vector3(0, 0.1880, -0.0440), "skin")
	form.add_loft(
		[Vector3(0, 0.1040, 0.0300), Vector3(0, 0.0580, 0.0040), Vector3(0, 0.0280, -0.0300)],
		[Vector2(0.0555, 0.0610), Vector2(0.0460, 0.0615), Vector2(0.0280, 0.0430)],
		"skin", 14, 5)
	form.add_ellipsoid(Vector3(0.0235, 0.0200, 0.0200), Vector3(0, 0.0205, -0.0495), "skin")
	for side: float in [-1.0, 1.0]:
		form.add_ellipsoid(Vector3(0.0295, 0.0260, 0.0275), Vector3(side * 0.0440, 0.0880, -0.0295), "skin")
		form.add_ellipsoid(Vector3(0.0095, 0.0215, 0.0145), Vector3(side * 0.0755, 0.1280, 0.0110), "skin")
		form.add_ellipsoid(Vector3(0.0045, 0.0110, 0.0070), Vector3(side * 0.0775, 0.1260, 0.0090), "dark")
		form.add_ellipsoid(Vector3(0.0165, 0.0105, 0.0080), Vector3(side * 0.0305, 0.1345, -0.0660), "dark")
		form.add_ellipsoid(Vector3(0.0105, 0.0095, 0.0080), Vector3(side * 0.0305, 0.1340, -0.0700), "sclera")
		form.add_ellipsoid(Vector3(0.0045, 0.0045, 0.0040), Vector3(side * 0.0305, 0.1340, -0.0775), "dark")
		form.add_ellipsoid(Vector3(0.0190, 0.0055, 0.0100), Vector3(side * 0.0310, 0.1495, -0.0660), "dark")
	form.add_ellipsoid(Vector3(0.0500, 0.0130, 0.0180), Vector3(0, 0.1490, -0.0690), "skin")
	form.add_loft(
		[Vector3(0, 0.1500, -0.0690), Vector3(0, 0.1240, -0.0870), Vector3(0, 0.1040, -0.0940), Vector3(0, 0.0960, -0.0830)],
		[Vector2(0.0075, 0.0100), Vector2(0.0095, 0.0125), Vector2(0.0135, 0.0150), Vector2(0.0110, 0.0125)],
		"skin", 10, 5)
	form.add_ellipsoid(Vector3(0.0210, 0.0085, 0.0110), Vector3(0, 0.0620, -0.0710), "skin")
	form.add_box(Vector3(0.0235, 0.0022, 0.0050), Vector3(0, 0.0610, -0.0790), "dark")
	# Hair only peeks out below the shell line at the nape and temples.
	form.add_ellipsoid(Vector3(0.0700, 0.0300, 0.0520), Vector3(0, 0.1180, 0.0560), "dark")
	for side: float in [-1.0, 1.0]:
		form.add_ellipsoid(Vector3(0.0120, 0.0260, 0.0300), Vector3(side * 0.0680, 0.1260, 0.0140), "dark")
	# Shell: a shallow-brimmed dome. The old profile flared to a plate at brow
	# height, which hid the eyes and read as a witch hat.
	form.add_revolve(
		[Vector2(0.000, 0.108), Vector2(0.040, 0.106), Vector2(0.068, 0.099), Vector2(0.089, 0.086),
			Vector2(0.101, 0.068), Vector2(0.108, 0.046), Vector2(0.112, 0.022), Vector2(0.114, 0.004),
			Vector2(0.110, -0.004), Vector2(0.101, -0.002), Vector2(0.070, 0.002), Vector2(0.000, 0.004)],
		"cloth", Vector2(1.0, 1.05), Vector3(0, 0.1700, 0.0040), 32)
	form.add_box(Vector3(0.090, 0.044, 0.020), Vector3(0, 0.1960, 0.0980), "webbing")
	form.add_box(Vector3(0.068, 0.026, 0.008), Vector3(0, 0.2350, -0.0930), "cloth")
	form.add_box(Vector3(0.034, 0.022, 0.014), Vector3(0, 0.2620, -0.0520), "armor")
	for side: float in [-1.0, 1.0]:
		form.add_strut(Vector3(side * 0.1040, 0.2380, -0.0300), Vector3(side * 0.1080, 0.1960, 0.0550), 0.0060, "armor")
		form.add_loft(
			[Vector3(side * 0.0980, 0.1760, 0.0060), Vector3(side * 0.0740, 0.1080, -0.0120),
				Vector3(side * 0.0340, 0.0320, -0.0320)],
			[Vector2(0.0058, 0.0036), Vector2(0.0056, 0.0034), Vector2(0.0054, 0.0032)],
			"webbing", 8, 5)
		form.add_box(Vector3(0.015, 0.019, 0.010), Vector3(side * 0.0460, 0.0580, -0.0330), "dark")
	# Goggles ride on the shell front, above the brim.
	form.add_loft(
		[Vector3(-0.0640, 0.1820, -0.0720), Vector3(0, 0.1880, -0.1000), Vector3(0.0640, 0.1820, -0.0720)],
		[Vector2(0.0160, 0.0110), Vector2(0.0170, 0.0120), Vector2(0.0160, 0.0110)],
		"rubber", 10, 5, Vector3.RIGHT)
	form.add_box(Vector3(0.1060, 0.0240, 0.0070), Vector3(0, 0.1840, -0.1060), "lens")
func _thigh_form(form: RefCounted) -> void:
	# The taper is carried by the loft itself; separate muscle blobs read as a
	# string of balls under the trousers.
	form.add_loft(
		[Vector3(0, 0.000, 0.002), Vector3(0.003, -0.070, 0.006), Vector3(0.002, -0.112, 0.006),
			Vector3(0.001, -0.182, 0.005), Vector3(-0.001, -0.262, 0.004), Vector3(-0.002, -0.340, 0.003),
			Vector3(-0.001, -0.410, 0.002), Vector3(0, -0.455, 0.0)],
		[Vector2(0.066, 0.074), Vector2(0.081, 0.090), Vector2(0.086, 0.094), Vector2(0.085, 0.093),
			Vector2(0.079, 0.087), Vector2(0.066, 0.073), Vector2(0.057, 0.062), Vector2(0.053, 0.057)],
		"cloth", 16, 6)
	form.add_box(Vector3(0.012, 0.104, 0.086), Vector3(0.081, -0.208, -0.006), "cloth")
	form.add_box(Vector3(0.010, 0.011, 0.082), Vector3(0.086, -0.156, -0.006), "webbing")
func _shin_form(form: RefCounted) -> void:
	# Calf volume comes from sweeping the loft centre back, not from a ball.
	form.add_loft(
		[Vector3(0, 0.000, 0.002), Vector3(0, -0.050, 0.008), Vector3(0, -0.112, 0.014),
			Vector3(0, -0.172, 0.013), Vector3(0, -0.244, 0.007), Vector3(0, -0.322, 0.002),
			Vector3(0, -0.392, 0.0), Vector3(0, -0.435, 0.0)],
		[Vector2(0.055, 0.058), Vector2(0.057, 0.068), Vector2(0.056, 0.074), Vector2(0.050, 0.070),
			Vector2(0.040, 0.055), Vector2(0.030, 0.036), Vector2(0.027, 0.030), Vector2(0.026, 0.028)],
		"cloth", 16, 6)
	form.add_ellipsoid(Vector3(0.040, 0.036, 0.016), Vector3(0, -0.014, -0.042), "armor")
func _foot_form(form: RefCounted) -> void:
	# Authored around the ankle joint; the sole has to land exactly at -ANKLE.
	form.add_loft(
		[Vector3(0, 0.010, 0.004), Vector3(0, -0.024, 0.000), Vector3(0, -0.050, -0.006)],
		[Vector2(0.038, 0.044), Vector2(0.043, 0.049), Vector2(0.044, 0.052)],
		"boots", 14, 5)
	form.add_revolve(
		[Vector2(0.034, 0.014), Vector2(0.043, 0.008), Vector2(0.044, -0.006), Vector2(0.036, -0.013)],
		"boots", Vector2(1.0, 1.14), Vector3(0, -0.002, 0.004), 16)
	form.add_ellipsoid(Vector3(0.0425, 0.0235, 0.0720), Vector3(0, -0.0490, -0.0760), "boots")
	form.add_ellipsoid(Vector3(0.0375, 0.0300, 0.0300), Vector3(0, -0.0440, 0.0290), "boots")
	form.add_loft(
		[Vector3(0, -0.0640, 0.0560), Vector3(0, -0.0680, 0.0100), Vector3(0, -0.0660, -0.0580),
			Vector3(0, -0.0620, -0.1160), Vector3(0, -0.0560, -0.1520)],
		[Vector2(0.0100, 0.0330), Vector2(0.0075, 0.0400), Vector2(0.0085, 0.0440),
			Vector2(0.0105, 0.0455), Vector2(0.0085, 0.0350)],
		"rubber", 12, 5, Vector3.UP)
	for index: int in range(5):
		form.add_box(Vector3(0.0700, 0.0050, 0.0090), Vector3(0, -0.0740, 0.0300 - index * 0.0360), "rubber")
	for index: int in range(4):
		var t: float = float(index) / 3.0
		form.add_box(Vector3(0.0620 - t * 0.0140, 0.0060, 0.0080),
			Vector3(0, -0.0300 - t * 0.0140, -0.0180 - t * 0.0620), "webbing")
	form.add_box(Vector3(0.0100, 0.0300, 0.0120), Vector3(0, -0.0480, 0.0520), "webbing")


func _upper_arm_form(form: RefCounted) -> void:
	form.add_loft(
		[Vector3(0, 0.000, 0.0), Vector3(0.004, -0.062, 0.002), Vector3(0.003, -0.120, 0.003),
			Vector3(0.001, -0.190, 0.003), Vector3(0, -0.262, 0.002), Vector3(0, -0.335, 0.0)],
		[Vector2(0.046, 0.050), Vector2(0.053, 0.055), Vector2(0.050, 0.052), Vector2(0.044, 0.047),
			Vector2(0.036, 0.039), Vector2(0.031, 0.033)],
		"cloth", 14, 6)
	form.add_revolve(
		[Vector2(0.028, 0.016), Vector2(0.036, 0.008), Vector2(0.036, -0.010), Vector2(0.029, -0.017)],
		"cloth", Vector2(1.0, 1.0), Vector3(0, -0.296, 0.0), 14)
func _forearm_form(form: RefCounted) -> void:
	form.add_loft(
		[Vector3(0, 0.000, 0.0), Vector3(0.004, -0.052, 0.004), Vector3(0.003, -0.096, 0.004),
			Vector3(0.001, -0.150, 0.002), Vector3(0, -0.210, 0.0), Vector3(0, -0.265, 0.0)],
		[Vector2(0.037, 0.040), Vector2(0.041, 0.039), Vector2(0.038, 0.036), Vector2(0.031, 0.030),
			Vector2(0.024, 0.023), Vector2(0.021, 0.019)],
		"cloth", 14, 6)
	form.add_ellipsoid(Vector3(0.025, 0.022, 0.018), Vector3(0, -0.018, 0.025), "armor")
	form.add_revolve(
		[Vector2(0.020, 0.014), Vector2(0.027, 0.006), Vector2(0.027, -0.012), Vector2(0.020, -0.018)],
		"webbing", Vector2(1.0, 1.0), Vector3(0, -0.232, 0.0), 14)
func _hand_right_form(form: RefCounted) -> void:
	_hand_form(form, 1.0)


func _hand_left_form(form: RefCounted) -> void:
	_hand_form(form, -1.0)


func _hand_form(form: RefCounted, side: float) -> void:
	# A fist wrapped around a bar: separated fingers with visible valleys, which
	# is what stops both hands from reading as one mitten at close range.
	form.add_loft(
		[Vector3(0, 0.000, 0.002), Vector3(0, -0.026, -0.014), Vector3(0, -0.048, -0.028)],
		[Vector2(0.028, 0.020), Vector2(0.030, 0.026), Vector2(0.028, 0.027)],
		"webbing", 12, 5)
	form.add_ellipsoid(Vector3(0.0275, 0.0155, 0.0330), Vector3(0, -0.0285, -0.0125), "webbing")
	for index: int in range(4):
		var lane: float = (float(index) - 1.5) * 0.0142 * side
		var radius: float = 0.0084 - absf(float(index) - 1.5) * 0.0007
		form.add_ellipsoid(Vector3(radius * 1.05, radius, radius), Vector3(lane, -0.0470, -0.0330), "webbing")
		form.add_loft(
			[Vector3(lane, -0.0490, -0.0360), Vector3(lane, -0.0560, -0.0580),
				Vector3(lane, -0.0400, -0.0740), Vector3(lane, -0.0140, -0.0640)],
			[Vector2(radius, radius * 0.86), Vector2(radius * 0.95, radius * 0.82),
				Vector2(radius * 0.86, radius * 0.74), Vector2(radius * 0.70, radius * 0.60)],
			"webbing", 8, 4)
		form.add_ellipsoid(Vector3(radius * 0.80, radius * 0.62, radius * 0.70), Vector3(lane, -0.0130, -0.0620), "dark")
		form.add_box(Vector3(radius * 1.30, 0.0035, 0.0070), Vector3(lane, -0.0300, -0.0770), "dark")
	form.add_loft(
		[Vector3(side * 0.0250, -0.0240, -0.0100), Vector3(side * 0.0330, -0.0120, -0.0300),
			Vector3(side * 0.0230, 0.0010, -0.0480)],
		[Vector2(0.0092, 0.0084), Vector2(0.0088, 0.0080), Vector2(0.0072, 0.0066)],
		"webbing", 8, 4)
	form.add_ellipsoid(Vector3(0.0150, 0.0200, 0.0170), Vector3(side * 0.0215, -0.0260, -0.0040), "webbing")


func _rifle_form(form: RefCounted) -> void:
	form.add_box(Vector3(0.0400, 0.0460, 0.3000), Vector3(0, 0.0120, -0.0600), "steel")
	form.add_box(Vector3(0.0360, 0.0340, 0.1900), Vector3(0, -0.0200, -0.0400), "armor")
	form.add_box(Vector3(0.0240, 0.0100, 0.3000), Vector3(0, 0.0400, -0.0600), "armor")
	for index: int in range(9):
		form.add_box(Vector3(0.0280, 0.0045, 0.0080), Vector3(0, 0.0465, -0.2000 + index * 0.0280), "armor")
	form.add_box(Vector3(0.0060, 0.0170, 0.0560), Vector3(0.0195, 0.0060, -0.0560), "dark")
	form.add_box(Vector3(0.0140, 0.0200, 0.0260), Vector3(0.0210, 0.0140, -0.0140), "armor")
	form.add_box(Vector3(0.0300, 0.0130, 0.0180), Vector3(0, 0.0210, 0.0940), "steel")
	form.add_loft(
		[Vector3(0, 0.0080, -0.1700), Vector3(0, 0.0060, -0.3180), Vector3(0, 0.0040, -0.4600)],
		[Vector2(0.0245, 0.0265), Vector2(0.0235, 0.0255), Vector2(0.0205, 0.0225)],
		"armor", 12, 5, Vector3.UP)
	for index: int in range(3):
		var lane: float = -0.2120 - index * 0.0760
		form.add_box(Vector3(0.0520, 0.0110, 0.0440), Vector3(0, -0.0200, lane), "dark")
		for side: float in [-1.0, 1.0]:
			form.add_box(Vector3(0.0110, 0.0130, 0.0440), Vector3(side * 0.0215, 0.0020, lane), "dark")
	form.add_strut(Vector3(0, 0.0120, -0.4580), Vector3(0, 0.0120, -0.6420), 0.0105, "steel")
	form.add_box(Vector3(0.0230, 0.0320, 0.0280), Vector3(0, 0.0220, -0.4700), "steel")
	form.add_box(Vector3(0.0090, 0.0200, 0.0110), Vector3(0, 0.0430, -0.4700), "armor")
	form.add_strut(Vector3(0, 0.0120, -0.6420), Vector3(0, 0.0120, -0.6980), 0.0165, "armor")
	for index: int in range(3):
		form.add_box(Vector3(0.0360, 0.0050, 0.0070), Vector3(0, 0.0120, -0.6520 - index * 0.0140), "dark")
		form.add_box(Vector3(0.0050, 0.0360, 0.0070), Vector3(0, 0.0120, -0.6520 - index * 0.0140), "dark")
	form.add_strut(Vector3(0, 0.0060, 0.0980), Vector3(0, 0.0140, 0.2620), 0.0170, "armor")
	form.add_box(Vector3(0.0380, 0.0860, 0.0240), Vector3(0, 0.0060, 0.2760), "boots")
	form.add_box(Vector3(0.0300, 0.0300, 0.1500), Vector3(0, 0.0360, 0.1800), "boots")
	form.add_loft(
		[Vector3(0, -0.0100, 0.0280), Vector3(0, -0.0520, 0.0460), Vector3(0, -0.0900, 0.0620)],
		[Vector2(0.0175, 0.0205), Vector2(0.0185, 0.0215), Vector2(0.0155, 0.0185)],
		"boots", 10, 5)
	form.add_box(Vector3(0.0080, 0.0050, 0.0460), Vector3(0, -0.0430, -0.0160), "steel")
	form.add_box(Vector3(0.0060, 0.0200, 0.0080), Vector3(0, -0.0300, -0.0180), "steel")
	form.add_loft(
		[Vector3(0, -0.0260, -0.0200), Vector3(0, -0.0840, -0.0320), Vector3(0, -0.1420, -0.0560), Vector3(0, -0.1780, -0.0840)],
		[Vector2(0.0155, 0.0300), Vector2(0.0155, 0.0295), Vector2(0.0145, 0.0275), Vector2(0.0120, 0.0235)],
		"armor", 10, 5)
	form.add_box(Vector3(0.0340, 0.0280, 0.0740), Vector3(0, 0.0630, -0.0780), "armor")
	form.add_box(Vector3(0.0260, 0.0220, 0.0080), Vector3(0, 0.0630, -0.1140), "lens")
	form.add_box(Vector3(0.0120, 0.0140, 0.0120), Vector3(0.0200, 0.0480, -0.0520), "steel")
	form.add_box(Vector3(0.0160, 0.0240, 0.0100), Vector3(0, 0.0480, 0.0260), "armor")
	form.add_loft(
		[Vector3(-0.0200, -0.0100, 0.1080), Vector3(-0.0260, -0.0560, -0.0600), Vector3(-0.0200, -0.0300, -0.2400)],
		[Vector2(0.0075, 0.0055), Vector2(0.0070, 0.0050), Vector2(0.0068, 0.0048)],
		"webbing", 8, 5)

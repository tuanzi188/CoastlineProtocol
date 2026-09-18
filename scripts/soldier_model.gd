extends Node3D
## Original articulated infantry silhouette, facing local -Z.

var muzzle: Marker3D
var _body: Node3D
var _torso: Node3D
var _weapon: Node3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _left_hand: MeshInstance3D
var _phase: float = 0.0
var _fall: float = 0.0
var _reload_phase: float = 0.0
var _built: bool = false


func build(variant: int = 0) -> void:
	if _built:
		return
	_built = true
	var colors: Array[Color] = [Color("586653"), Color("686456"), Color("52646b"), Color("716650")]
	var cloth: StandardMaterial3D = _material(colors[posmod(variant, colors.size())])
	var armor: StandardMaterial3D = _material(Color("323e38"))
	var webbing: StandardMaterial3D = _material(Color("85816a"))
	var boots: StandardMaterial3D = _material(Color("252a28"))
	var skin: StandardMaterial3D = _material(Color("b98c6b") if variant % 2 == 0 else Color("8e674e"))
	var steel: StandardMaterial3D = _material(Color("30383c"), 0.65)
	var lens: StandardMaterial3D = _material(Color("263e46"), 0.45)
	_body = _pivot(self, "Body", Vector3.ZERO)
	_box(_body, Vector3(0.35, 0.21, 0.24), Vector3(0, 0.94, 0), cloth)
	_box(_body, Vector3(0.38, 0.055, 0.26), Vector3(0, 1.025, 0), boots)
	for side: float in [-1.0, 1.0]:
		var hip: Node3D = _pivot(_body, "Hip", Vector3(side * 0.115, 0.94, 0))
		_hips.append(hip)
		_capsule(hip, 0.095, 0.43, Vector3(0, -0.20, 0), cloth)
		_box(hip, Vector3(0.075, 0.18, 0.15), Vector3(side * 0.085, -0.16, 0), cloth)
		var knee: Node3D = _pivot(hip, "Knee", Vector3(0, -0.40, 0))
		_knees.append(knee)
		_sphere(knee, Vector3(0.17, 0.17, 0.17), Vector3.ZERO, cloth)
		_box(knee, Vector3(0.14, 0.14, 0.07), Vector3(0, 0, -0.075), armor)
		_capsule(knee, 0.078, 0.38, Vector3(0, -0.18, 0.01), cloth)
		_box(knee, Vector3(0.17, 0.15, 0.29), Vector3(0, -0.445, -0.055), boots)
	_torso = _pivot(_body, "Torso", Vector3(0, 1.04, 0))
	_capsule(_torso, 0.22, 0.57, Vector3(0, 0.28, 0), cloth).scale.z = 0.62
	_box(_torso, Vector3(0.43, 0.40, 0.28), Vector3(0, 0.27, 0), armor)
	_box(_torso, Vector3(0.32, 0.37, 0.18), Vector3(0, 0.28, 0.22), cloth)
	for side: float in [-1.0, 1.0]:
		_box(_torso, Vector3(0.065, 0.44, 0.034), Vector3(side * 0.14, 0.29, -0.15), webbing)
	for index: int in range(3):
		_box(_torso, Vector3(0.10, 0.16, 0.09), Vector3(float(index - 1) * 0.12, 0.16, -0.19), webbing)
	_capsule(_torso, 0.072, 0.15, Vector3(0, 0.56, 0), skin)
	_sphere(_torso, Vector3(0.27, 0.34, 0.27), Vector3(0, 0.72, -0.005), skin)
	_sphere(_torso, Vector3(0.33, 0.24, 0.33), Vector3(0, 0.835, 0.01), cloth)
	_box(_torso, Vector3(0.34, 0.035, 0.34), Vector3(0, 0.78, -0.015), armor)
	_box(_torso, Vector3(0.26, 0.082, 0.045), Vector3(0, 0.745, -0.139), boots)
	for side: float in [-1.0, 1.0]:
		_box(_torso, Vector3(0.102, 0.058, 0.015), Vector3(side * 0.065, 0.746, -0.165), lens)
		_box(_torso, Vector3(0.022, 0.17, 0.032), Vector3(side * 0.127, 0.66, -0.025), boots)
	_box(_torso, Vector3(0.05, 0.06, 0.065), Vector3(0, 0.675, -0.136), skin)
	_box(_torso, Vector3(0.13, 0.025, 0.025), Vector3(0, 0.605, -0.098), boots)
	_weapon = _pivot(_torso, "Rifle", Vector3(0.13, 0.27, -0.25))
	_box(_weapon, Vector3(0.075, 0.11, 0.30), Vector3(0, 0, -0.12), steel)
	_box(_weapon, Vector3(0.072, 0.095, 0.26), Vector3(0, 0.015, -0.40), webbing)
	_box(_weapon, Vector3(0.07, 0.12, 0.19), Vector3(0, -0.01, 0.12), boots)
	_box(_weapon, Vector3(0.04, 0.11, 0.06), Vector3(0, -0.09, 0), boots).rotation.x = -0.2
	_box(_weapon, Vector3(0.055, 0.18, 0.075), Vector3(0, -0.12, -0.16), steel).rotation.x = -0.18
	_box(_weapon, Vector3(0.025, 0.03, 0.48), Vector3(0, 0.071, -0.22), boots)
	_box(_weapon, Vector3(0.047, 0.06, 0.075), Vector3(0, 0.11, -0.12), steel)
	var barrel: MeshInstance3D = _capsule(_weapon, 0.017, 0.22, Vector3(0, 0.01, -0.62), steel)
	barrel.rotation.x = PI * 0.5
	for index: int in range(5):
		_box(_weapon, Vector3(0.078, 0.019, 0.022), Vector3(0, 0.025, -0.31 - float(index) * 0.042), boots)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.01, -0.745)
	_weapon.add_child(muzzle)
	# Both hands stay attached to the rifle; articulated arms follow the grip points.
	_capsule(_weapon, 0.047, 0.115, Vector3(0.008, -0.10, 0.015), webbing)
	_left_hand = _capsule(_weapon, 0.046, 0.12, Vector3(-0.005, -0.045, -0.40), webbing)
	_left_hand.rotation.x = PI * 0.5
	for side: float in [-1.0, 1.0]:
		_sphere(_torso, Vector3(0.19, 0.20, 0.20), Vector3(side * 0.255, 0.44, 0), cloth)
		_upper_arms.append(_capsule(_torso, 0.072, 1.0, Vector3.ZERO, cloth))
		_forearms.append(_capsule(_torso, 0.061, 1.0, Vector3.ZERO, cloth))
		_elbows.append(_sphere(_torso, Vector3(0.13, 0.13, 0.13), Vector3.ZERO, armor))
	animate(0.0, false, false, false, 0.0)


func animate(speed: float, aiming: bool, reloading: bool, dead: bool, delta: float) -> void:
	if not _built:
		build()
	var blend: float = 1.0 - exp(-12.0 * delta)
	if dead:
		_fall = minf(1.0, _fall + delta * 1.6)
		var eased: float = sin(_fall * PI * 0.5)
		_body.rotation = Vector3(-1.48 * eased, 0.16 * eased, 0.13 * eased)
		_body.position.y = 0.24 * eased
		_hips[0].rotation = Vector3(0.25, 0, -0.20) * eased
		_hips[1].rotation = Vector3(-0.15, 0, 0.25) * eased
		_knees[0].rotation.x = 0.65 * eased
		_knees[1].rotation.x = 0.35 * eased
		_weapon.rotation.z = -0.5 * eased
		return
	_phase += delta * speed * 2.7
	var stride: float = clampf(speed / 4.3, 0.0, 1.0)
	for index: int in range(2):
		var wave: float = sin(_phase + float(index) * PI)
		_hips[index].rotation.x = lerpf(_hips[index].rotation.x, wave * 0.58 * stride, blend)
		_knees[index].rotation.x = lerpf(_knees[index].rotation.x, maxf(0.0, -wave) * 0.85 * stride, blend)
	_torso.position.y = 1.04 + absf(sin(_phase)) * 0.026 * stride
	_reload_phase = _reload_phase + delta * 6.0 if reloading else 0.0
	var weapon_position: Vector3 = Vector3(0.13, 0.39 if aiming else 0.27, -0.25)
	var weapon_rotation: Vector3 = Vector3.ZERO if aiming else Vector3(-0.20, 0, 0)
	if reloading:
		weapon_position.y = 0.23 + sin(_reload_phase) * 0.025
		weapon_rotation = Vector3(0.12, -0.15, -0.55)
	_weapon.position = _weapon.position.lerp(weapon_position, blend)
	_weapon.rotation = _weapon.rotation.lerp(weapon_rotation, blend)
	for index: int in range(2):
		var side: float = -1.0 if index == 0 else 1.0
		var shoulder: Vector3 = Vector3(side * 0.255, 0.44, 0)
		var elbow: Vector3 = Vector3(side * 0.31, 0.16, -0.19)
		var grip: Vector3 = Vector3(-0.005, -0.045, -0.40) if index == 0 else Vector3(0.008, -0.10, 0.015)
		if reloading and index == 0:
			grip = Vector3(-0.04, -0.16 + sin(_reload_phase) * 0.055, -0.16)
		if index == 0:
			_left_hand.position = grip
		var hand: Vector3 = _weapon.transform * grip
		if index == 0:
			elbow = (shoulder + hand) * 0.5 + Vector3(-0.055, -0.12, 0.025)
		_pose_segment(_upper_arms[index], shoulder, elbow)
		_pose_segment(_forearms[index], elbow, hand)
		_elbows[index].position = elbow


func _pose_segment(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var displacement: Vector3 = end - start
	mesh.transform = Transform3D(Basis(Quaternion(Vector3.UP, displacement.normalized())).scaled_local(Vector3(1, displacement.length(), 1)), (start + end) * 0.5)


func _pivot(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node


func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88 if metal == 0.0 else 0.4
	material.metallic = metal
	return material


func _mesh(parent: Node3D, geometry: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = geometry
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry: BoxMesh = BoxMesh.new()
	geometry.size = size
	return _mesh(parent, geometry, at, material)


func _capsule(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry: CapsuleMesh = CapsuleMesh.new()
	geometry.radius = radius
	geometry.height = height
	geometry.radial_segments = 8
	geometry.rings = 3
	return _mesh(parent, geometry, at, material)


func _sphere(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry: SphereMesh = SphereMesh.new()
	geometry.radius = 0.5
	geometry.height = 1.0
	geometry.radial_segments = 12
	geometry.rings = 6
	var instance: MeshInstance3D = _mesh(parent, geometry, at, material)
	instance.scale = size
	return instance

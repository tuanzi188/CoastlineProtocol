extends Node3D
## ModernSoldier-backed infantry rig.
##
## The GLB is a flat set of low-poly parts (no skeleton, no clips). Each limb is
## reparented under a pivot at its joint so procedural locomotion can drive a
## modern-soldier silhouette. The authored rifle is replaced with the same
## procedural carbine the rest of the prototype uses.

const MODEL_PATH: String = "res://assets/characters/ModernSoldier.glb"
const RUN_SPEED: float = 4.3
const MODEL_SCALE: float = 1.05
const Form = preload("res://scripts/procedural_form.gd")

const UNIFORM_TINTS: Array[Color] = [
	Color("8b9478"),
	Color("7d8a86"),
	Color("9a8f76"),
	Color("78857f"),
]

static var _rifle_mesh: ArrayMesh
static var _paint_cache: Dictionary = {}

var muzzle: Marker3D
var _model: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _rifle: MeshInstance3D
var _rifle_base: Vector3
var _phase: float = 0.0
var _hit_left: float = 0.0
var _fire_left: float = 0.0
var _dead_blend: float = 0.0
var _built: bool = false


func build(variant: int = 0) -> void:
	if _built:
		return
	_built = true
	var packed: PackedScene = load(MODEL_PATH)
	_model = packed.instantiate() as Node3D
	_model.name = "ModernSoldier"
	# The authored mesh faces +Z; the game's forward is -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)

	_arm_l = _pivot("ArmLPivot", Vector3(-0.22, 1.25, 0.0))
	_arm_r = _pivot("ArmRPivot", Vector3(0.22, 1.25, 0.0))
	_leg_l = _pivot("LegLPivot", Vector3(-0.08, 0.70, 0.0))
	_leg_r = _pivot("LegRPivot", Vector3(0.08, 0.70, 0.0))
	_head = _pivot("HeadPivot", Vector3(0.0, 1.52, 0.0))

	_adopt(_arm_l, "ArmL")
	_adopt(_arm_l, "HandL")
	_adopt(_arm_r, "ArmR")
	_adopt(_arm_r, "HandR")
	_adopt(_leg_l, "LegL")
	_adopt(_leg_l, "BootL")
	_adopt(_leg_r, "LegR")
	_adopt(_leg_r, "BootR")
	_adopt(_head, "Head")
	_adopt(_head, "Helmet")
	_adopt(_head, "Visor")

	_add_body_fill()

	# The authored rifle is a thin placeholder; hide it and mount the carbine.
	for hidden: String in ["Rifle", "RifleBarrel"]:
		var node: MeshInstance3D = _model.find_child(hidden, true, false) as MeshInstance3D
		if node != null:
			node.hide()

	_bulk("Torso", Vector3(1.18, 1.0, 1.18))
	_bulk("Vest", Vector3(1.15, 1.0, 1.12))
	_bulk("ArmL", Vector3(1.08, 1.0, 1.08))
	_bulk("ArmR", Vector3(1.08, 1.0, 1.08))
	_bulk("LegL", Vector3(1.08, 1.0, 1.08))
	_bulk("LegR", Vector3(1.08, 1.0, 1.08))
	_bulk("Head", Vector3(1.04, 1.0, 1.04))

	_attach_rifle()
	_tint_uniform(variant)


## The source GLB has no waist or neck geometry, so the torso, legs and head
## would otherwise float apart during animation. Two primitives close the gaps.
func _add_body_fill() -> void:
	var pelvis: MeshInstance3D = MeshInstance3D.new()
	pelvis.name = "Pelvis"
	var pelvis_box: BoxMesh = BoxMesh.new()
	pelvis_box.size = Vector3(0.235, 0.24, 0.15)
	pelvis.mesh = pelvis_box
	pelvis.position = Vector3(0.0, 1.00, 0.0)
	_model.add_child(pelvis)

	var neck: MeshInstance3D = MeshInstance3D.new()
	neck.name = "Neck"
	var neck_cylinder: CylinderMesh = CylinderMesh.new()
	neck_cylinder.top_radius = 0.055
	neck_cylinder.bottom_radius = 0.065
	neck_cylinder.height = 0.20
	neck.mesh = neck_cylinder
	neck.position = Vector3(0.0, 1.46, 0.0)
	_model.add_child(neck)


func _pivot(pivot_name: String, at: Vector3) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = pivot_name
	pivot.position = at
	_model.add_child(pivot)
	return pivot


func _adopt(parent: Node3D, node_name: String) -> Node3D:
	var node: Node3D = _model.find_child(node_name, true, false) as Node3D
	if node == null:
		push_warning("ModernSoldier rig: missing part %s" % node_name)
		return null
	var original: Vector3 = _model_position(node)
	var parent_position: Vector3 = _model_position(parent)
	node.owner = null
	node.reparent(parent, false)
	node.position = original - parent_position
	return node


func _bulk(part_name: String, part_scale: Vector3) -> void:
	var node: Node3D = _model.find_child(part_name, true, false) as Node3D
	if node != null:
		node.scale = part_scale


## Sum of translations up to the model root. Pivots are created unrotated and
## unscaled, so this is exact while the rig is being assembled.
func _model_position(node: Node3D) -> Vector3:
	var position: Vector3 = Vector3.ZERO
	var current: Node = node
	while current != null and current != _model:
		var node_3d: Node3D = current as Node3D
		if node_3d != null:
			position += node_3d.position
		current = current.get_parent()
	return position


func _attach_rifle() -> void:
	var hand: Node3D = Node3D.new()
	hand.name = "RifleHand"
	hand.position = Vector3(0.0, -0.295, -0.02)
	_arm_r.add_child(hand)
	_rifle = MeshInstance3D.new()
	_rifle.name = "RifleMesh"
	_rifle.mesh = _get_rifle_mesh()
	_rifle.transform = Transform3D(
		Basis.from_euler(Vector3(0, PI, 0)) * Basis.from_scale(Vector3(0.82, 0.82, 0.82)),
		Vector3(0.02, -0.06, -0.14))
	_rifle_base = _rifle.position
	hand.add_child(_rifle)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.010, -0.64)
	_rifle.add_child(muzzle)


func _get_rifle_mesh() -> ArrayMesh:
	if _rifle_mesh != null:
		return _rifle_mesh
	var paints: Dictionary = {
		"steel": _paint(Color("303739"), 0.65, 0.58, 0.40),
		"armor": _paint(Color("343e37"), 0.0, 0.80, 0.26),
		"boots": _paint(Color("242826"), 0.0, 0.90, 0.20),
		"lens": _paint(Color("293e43"), 0.0, 0.24, 0.55),
	}
	var form: RefCounted = Form.new()
	_rifle_form(form)
	_rifle_mesh = form.commit()
	var keys: Array = form.surface_keys()
	for index: int in range(_rifle_mesh.get_surface_count()):
		_rifle_mesh.surface_set_material(index, paints[keys[index]])
	return _rifle_mesh


func _rifle_form(form: RefCounted) -> void:
	form.add_box(Vector3(0.0400, 0.0460, 0.3000), Vector3(0, 0.0120, -0.0600), "steel")
	form.add_box(Vector3(0.0360, 0.0340, 0.1900), Vector3(0, -0.0200, -0.0400), "armor")
	form.add_box(Vector3(0.0240, 0.0100, 0.3000), Vector3(0, 0.0400, -0.0600), "armor")
	form.add_loft(
		[Vector3(0, 0.0080, -0.1700), Vector3(0, 0.0060, -0.3180), Vector3(0, 0.0040, -0.4600)],
		[Vector2(0.0245, 0.0265), Vector2(0.0235, 0.0255), Vector2(0.0205, 0.0225)],
		"armor", 12, 5, Vector3.UP)
	form.add_strut(Vector3(0, 0.0120, -0.4580), Vector3(0, 0.0120, -0.6400), 0.0105, "steel")
	form.add_strut(Vector3(0, 0.0120, -0.6400), Vector3(0, 0.0120, -0.6940), 0.0165, "armor")
	form.add_loft(
		[Vector3(0, -0.0100, 0.0280), Vector3(0, -0.0520, 0.0460), Vector3(0, -0.0900, 0.0620)],
		[Vector2(0.0175, 0.0205), Vector2(0.0185, 0.0215), Vector2(0.0155, 0.0185)],
		"boots", 10, 5)
	form.add_loft(
		[Vector3(0, -0.0260, -0.0200), Vector3(0, -0.0840, -0.0320), Vector3(0, -0.1420, -0.0560), Vector3(0, -0.1780, -0.0840)],
		[Vector2(0.0155, 0.0300), Vector2(0.0155, 0.0295), Vector2(0.0145, 0.0275), Vector2(0.0120, 0.0235)],
		"armor", 10, 5)
	form.add_box(Vector3(0.0340, 0.0280, 0.0740), Vector3(0, 0.0630, -0.0780), "armor")
	form.add_box(Vector3(0.0260, 0.0220, 0.0080), Vector3(0, 0.0630, -0.1140), "lens")
	form.add_strut(Vector3(0, 0.0060, 0.0980), Vector3(0, 0.0140, 0.2400), 0.0170, "armor")
	form.add_box(Vector3(0.0380, 0.0860, 0.0240), Vector3(0, 0.0060, 0.2540), "boots")


func _paint(color: Color, metal: float = 0.0, roughness: float = 0.90, specular: float = 0.20) -> StandardMaterial3D:
	var key: String = "%s/%.3f/%.3f/%.3f" % [color.to_html(), metal, roughness, specular]
	if _paint_cache.has(key):
		return _paint_cache[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	material.metallic_specular = specular
	_paint_cache[key] = material
	return material


func _tint_uniform(variant: int) -> void:
	var tint: Color = UNIFORM_TINTS[posmod(variant, UNIFORM_TINTS.size())]
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var part: String = String(mesh_instance.name)
		if part == "Pelvis":
			mesh_instance.material_override = _paint(tint, 0.0, 0.90, 0.20)
			continue
		if part == "Neck":
			mesh_instance.material_override = _paint(Color("b98d6f"), 0.0, 0.86, 0.20)
			continue
		if part == "Head":
			_override_surface(mesh_instance, Color("b98d6f"), 0.0, 0.86)
			continue
		if part == "Visor":
			_override_surface(mesh_instance, Color("16282b"), 0.35, 0.24)
			continue
		if not (part == "Torso" or part == "Vest" or part == "ArmL" or part == "ArmR"
				or part == "LegL" or part == "LegR" or part == "Helmet" or part == "Pelvis"):
			continue
		_override_surface(mesh_instance, tint, 0.0, 0.88)


func _override_surface(mesh_instance: MeshInstance3D, tint: Color, metal: float, roughness: float) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface: int in range(mesh.get_surface_count()):
		var source: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
		if source == null:
			continue
		var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		material.albedo_color = material.albedo_color * tint
		material.metallic = metal
		material.roughness = roughness
		mesh_instance.set_surface_override_material(surface, material)


func flinch() -> void:
	_hit_left = 0.28


func fire() -> void:
	_fire_left = 0.12


func animate(speed: float, aiming: bool, reloading: bool, dead: bool, delta: float, dip: float = 0.0) -> void:
	if not _built:
		return
	_hit_left = maxf(0.0, _hit_left - delta)
	_fire_left = maxf(0.0, _fire_left - delta)
	var moving: float = clampf(speed / RUN_SPEED, 0.0, 1.0)
	if moving > 0.05:
		_phase += delta * lerpf(4.0, 11.0, moving)
	var swing: float = sin(_phase) * 0.55 * moving
	var arm_swing: float = sin(_phase) * 0.30 * moving
	var aim: float = 1.0 if aiming else 0.0
	var reload: float = 1.0 if reloading else 0.0
	var blend: float = 1.0 - exp(-12.0 * delta)

	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing, blend)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing, blend)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_swing + aim * 1.05, blend)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -arm_swing + aim * 1.18 + reload * 0.55, blend)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -aim * 0.10, blend)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, aim * 0.42, blend)
	_head.rotation.x = lerpf(_head.rotation.x, aim * 0.08, blend)

	if dead:
		_dead_blend = minf(1.0, _dead_blend + delta * 2.4)
	else:
		_dead_blend = maxf(0.0, _dead_blend - delta * 4.0)
	_model.rotation.z = -PI * 0.5 * _dead_blend
	_model.position.y = -dip * 0.9 - 0.12 * _dead_blend
	_model.position.x = sin(_hit_left * 42.0) * 0.035 * _hit_left
	_rifle.position = _rifle_base - Vector3(0.0, 0.0, _fire_left * 0.55)

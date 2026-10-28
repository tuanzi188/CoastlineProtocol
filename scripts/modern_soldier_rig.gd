extends Node3D
## ModernSoldier-backed infantry rig.
##
## The GLB is a flat set of low-poly parts (no skeleton, no clips). Each limb is
## reparented under a pivot at its joint so procedural locomotion can drive a
## modern-soldier silhouette. Upper-body lean, body bob and aim twist run on a
## waist pivot; the legs stay planted. The authored rifle is replaced with the
## same procedural carbine the rest of the prototype uses.

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
var _hips: Node3D
var _hips_base: Vector3
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _rifle: MeshInstance3D
var _rifle_base: Vector3
var _magazine: MeshInstance3D
var _magazine_base: Vector3
var _phase: float = 0.0
var _idle_time: float = 0.0
var _hit_left: float = 0.0
var _fire_left: float = 0.0
var _reload_blend: float = 0.0
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

	_hips_base = Vector3(0.0, 0.98, 0.0)
	_hips = _pivot("HipsPivot", _hips_base)
	_arm_l = _pivot("ArmLPivot", Vector3(-0.22, 1.25, 0.0))
	_arm_r = _pivot("ArmRPivot", Vector3(0.22, 1.25, 0.0))
	_leg_l = _pivot("LegLPivot", Vector3(-0.08, 0.70, 0.0))
	_leg_r = _pivot("LegRPivot", Vector3(0.08, 0.70, 0.0))
	_head = _pivot("HeadPivot", Vector3(0.0, 1.52, 0.0))

	# Upper body rides the waist pivot; legs stay on the model root.
	_adopt(_hips, "ArmLPivot")
	_adopt(_hips, "ArmRPivot")
	_adopt(_hips, "HeadPivot")
	_adopt(_hips, "Torso")
	_adopt(_hips, "Vest")
	_adopt(_hips, "Pouch1")
	_adopt(_hips, "Pouch2")
	_adopt(_hips, "Pouch3")

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

	_add_body_fill()
	_add_gear(variant)
	_attach_rifle()
	_tint_uniform(variant)


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


## The source GLB has no waist or neck geometry, so the torso, legs and head
## would otherwise float apart during animation. Two primitives close the gaps.
func _add_body_fill() -> void:
	_detail_box(_hips, "Pelvis", Vector3(0.235, 0.24, 0.15), Vector3(0.0, 0.02, 0.0), Color("4a5344"))
	_detail_cylinder(_hips, "Neck", 0.055, 0.065, 0.20, Vector3(0.0, 0.48, 0.0), Color("b98d6f"))


## Small silhouette props: backpack, straps, pads, helmet mount, armband,
## holster and antenna. All are primitives, so they cost almost nothing.
func _add_gear(variant: int) -> void:
	var accent: Color = Color("65dedc") if variant % 2 == 0 else Color("edd7a8")
	_detail_box(_hips, "Backpack", Vector3(0.22, 0.26, 0.12), Vector3(0.0, 0.27, 0.14), Color("3f4a3c"))
	_detail_box(_hips, "StrapL", Vector3(0.030, 0.22, 0.020), Vector3(-0.07, 0.25, -0.075), Color("2b3129"))
	_detail_box(_hips, "StrapR", Vector3(0.030, 0.22, 0.020), Vector3(0.07, 0.25, -0.075), Color("2b3129"))
	_detail_cylinder(_hips, "Antenna", 0.006, 0.006, 0.34, Vector3(0.09, 0.48, 0.16), Color("202623"))
	_detail_box(_arm_l, "ShoulderPadL", Vector3(0.13, 0.08, 0.13), Vector3(0.0, 0.02, 0.0), Color("3a4437"))
	_detail_box(_arm_r, "ShoulderPadR", Vector3(0.13, 0.08, 0.13), Vector3(0.0, 0.02, 0.0), Color("3a4437"))
	_detail_box(_leg_l, "KneePadL", Vector3(0.12, 0.12, 0.10), Vector3(0.0, -0.28, -0.055), Color("2f3833"))
	_detail_box(_leg_r, "KneePadR", Vector3(0.12, 0.12, 0.10), Vector3(0.0, -0.28, -0.055), Color("2f3833"))
	_detail_box(_head, "HelmetMount", Vector3(0.06, 0.05, 0.05), Vector3(0.0, 0.20, -0.08), Color("242b28"))
	_detail_box(_arm_l, "Armband", Vector3(0.115, 0.035, 0.115), Vector3(0.0, -0.12, 0.0), accent)
	_detail_box(_leg_r, "Holster", Vector3(0.07, 0.14, 0.05), Vector3(0.065, -0.20, 0.02), Color("262c28"))
	_detail_box(_hips, "Radio", Vector3(0.035, 0.09, 0.045), Vector3(0.10, 0.18, -0.095), Color("202623"))


func _detail_box(parent: Node3D, detail_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = detail_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = at
	instance.material_override = _paint(color, 0.0, 0.92, 0.18)
	parent.add_child(instance)
	return instance


func _detail_cylinder(parent: Node3D, detail_name: String, top: float, bottom: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = detail_name
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	instance.mesh = cylinder
	instance.position = at
	instance.material_override = _paint(color, 0.25, 0.55, 0.30)
	parent.add_child(instance)
	return instance


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
	_magazine = _detail_box(_rifle, "Magazine", Vector3(0.028, 0.095, 0.045), Vector3(0.0, -0.025, 0.02), Color("2a302c"))
	_magazine_base = _magazine.position
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
		if part == "HandL" or part == "HandR":
			_override_surface(mesh_instance, Color("2b302c"), 0.0, 0.90)
			continue
		if part == "BootL" or part == "BootR":
			_override_surface(mesh_instance, Color("202522"), 0.0, 0.92)
			continue
		if part.begins_with("Pouch"):
			_override_surface(mesh_instance, tint.darkened(0.18), 0.0, 0.90)
			continue
		if not (part == "Torso" or part == "Vest" or part == "ArmL" or part == "ArmR"
				or part == "LegL" or part == "LegR" or part == "Helmet"):
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
	_idle_time += delta
	var moving: float = clampf(speed / RUN_SPEED, 0.0, 1.0)
	if moving > 0.05:
		_phase += delta * lerpf(4.0, 11.0, moving)
	var swing: float = sin(_phase) * 0.55 * moving
	var arm_swing: float = sin(_phase) * 0.30 * moving
	var aim: float = 1.0 if aiming else 0.0
	var reload: float = 1.0 if reloading else 0.0
	var blend: float = 1.0 - exp(-12.0 * delta)
	_reload_blend = lerpf(_reload_blend, reload, 1.0 - exp(-10.0 * delta))

	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing, blend)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing, blend)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_swing + aim * 1.05 - _fire_left * 0.25, blend)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -arm_swing + aim * 1.18 + reload * 0.55 + sin(_reload_blend * PI) * 0.25, blend)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -aim * 0.10, blend)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, aim * 0.42, blend)
	_head.rotation.x = lerpf(_head.rotation.x, aim * 0.08, blend)

	# Waist dynamics: forward lean when running, bob on each step, sway, and a
	# small aim twist. The legs are siblings, so the feet stay planted.
	var bob: float = absf(sin(_phase * 2.0)) * 0.028 * moving
	var breathe: float = sin(_idle_time * 1.6) * 0.004 * (1.0 - moving)
	_hips.rotation.x = lerpf(_hips.rotation.x, -0.16 * moving + 0.05 * aim - _fire_left * 0.08, blend)
	_hips.rotation.y = lerpf(_hips.rotation.y, -0.06 * aim, blend)
	_hips.rotation.z = lerpf(_hips.rotation.z, sin(_phase) * 0.05 * moving + sin(_hit_left * 46.0) * 0.06 * _hit_left, blend)
	_hips.position.y = _hips_base.y + bob + breathe
	_hips.position.x = sin(_phase) * 0.018 * moving

	# Reload: magazine drops out, left hand works the well.
	_magazine.position = _magazine_base - Vector3(0.0, 0.13 * _reload_blend, 0.0)
	_magazine.visible = _reload_blend > 0.03

	if dead:
		_dead_blend = minf(1.0, _dead_blend + delta * 2.4)
	else:
		_dead_blend = maxf(0.0, _dead_blend - delta * 4.0)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.55 * _dead_blend, blend)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.55 * _dead_blend, blend)
	_leg_l.rotation.z = lerpf(_leg_l.rotation.z, -0.18 * _dead_blend, blend)
	_leg_r.rotation.z = lerpf(_leg_r.rotation.z, 0.18 * _dead_blend, blend)
	_head.rotation.z = lerpf(_head.rotation.z, 0.28 * _dead_blend, blend)
	_model.rotation.z = -PI * 0.5 * _dead_blend
	_model.position.y = -dip * 0.9 - 0.12 * _dead_blend
	_model.position.x = sin(_hit_left * 42.0) * 0.035 * _hit_left
	_rifle.position = _rifle_base - Vector3(0.0, 0.0, _fire_left * 0.55)

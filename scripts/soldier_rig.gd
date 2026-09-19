extends Node3D
## KayKit-backed infantry: a real skinned humanoid driven by authored
## animation clips instead of procedural joint solving.
##
## Deliberately exposes the same surface as the procedural rig
## (`build`, `animate`, `flinch`, `muzzle`) so `enemy.gd` can swap either one
## without changing its locomotion contract.

const Form = preload("res://scripts/procedural_form.gd")

const PACKS: Array[String] = [
	"res://assets/characters/Knight.glb",
	"res://assets/characters/Rogue.glb",
	"res://assets/characters/Barbarian.glb",
	"res://assets/characters/Mage.glb",
]
const RUN_SPEED: float = 4.3
const NECK_HEIGHT: float = 1.620
const GEAR_KEEP: Array[String] = ["Body", "Head", "Helmet", "Cape", "LegLeft", "LegRight",
	"ArmLeft", "ArmRight"]
const CLIP_IDLE: StringName = &"Idle"
const CLIP_WALK: StringName = &"Walking_A"
const CLIP_RUN: StringName = &"Running_A"
const CLIP_AIM: StringName = &"1H_Ranged_Aiming"
const CLIP_RELOAD: StringName = &"1H_Ranged_Reload"
const CLIP_FIRE: StringName = &"1H_Ranged_Shoot"
const CLIP_HIT: StringName = &"Hit_A"
const CLIP_DEATH: StringName = &"Death_A"

var muzzle: Marker3D
var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _rifle: Node3D
var _built: bool = false
var _clip: StringName = &""
var _hit_left: float = 0.0
var _fire_left: float = 0.0
var _dead: bool = false
var _speed: float = 0.0


func build(variant: int = 0) -> void:
	if _built:
		return
	_built = true
	var packed: PackedScene = load(PACKS[posmod(variant, PACKS.size())])
	_model = packed.instantiate() as Node3D
	add_child(_model)
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	# The rig is advanced from animate() so a paused match freezes mid-pose and
	# the preview harness can step it deterministically.
	_player.set_process(false)
	_player.speed_scale = 1.0
	_player.play("Idle")
	_player.advance(0.0)
	_strip_gear()
	_attach_rifle()
	# Bone poses are only valid once the skin has been evaluated, so the stature
	# fit is deferred to the first animate() call rather than done here.
	_fit_stature()


## The imported file carries every weapon and shield in the pack on the hand
## slots, so anything that is not armour has to go before the rifle is added.
func _strip_gear() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		var keep: bool = false
		for fragment: String in GEAR_KEEP:
			if String(instance.name).ends_with(fragment):
				keep = true
		if not keep:
			instance.hide()


var _fitted: bool = false


func _fit_stature() -> void:
	if _fitted:
		return
	var head: int = _skeleton.find_bone("head")
	if head < 0:
		return
	var neck_y: float = _skeleton.get_bone_global_pose(head).origin.y
	if neck_y <= 0.05:
		return
	_fitted = true
	scale = scale * (NECK_HEIGHT / neck_y)


func flinch() -> void:
	_hit_left = 0.42


func fire() -> void:
	_fire_left = 0.22


func animate(speed: float, aiming: bool, reloading: bool, dead: bool, delta: float, dip: float = 0.0) -> void:
	if not _built:
		build()
	if delta <= 0.0:
		return
	_fit_stature()
	_speed = lerpf(_speed, speed, 1.0 - exp(-8.0 * delta))
	var next: StringName = _desired_clip(speed, aiming, reloading, dead)
	_hit_left = maxf(0.0, _hit_left - delta)
	_fire_left = maxf(0.0, _fire_left - delta)
	if next != _clip:
		_clip = next
		_player.play(next)
		_player.advance(0.0)
	_player.speed_scale = _rate_for(next, speed)
	_player.advance(delta)
	if _rifle:
		# A landing squash reads through the hips; the authored clips already own
		# the limbs, so only the root is offset.
		_model.position.y = -dip * 0.9
		_rifle.rotation.x = lerpf(_rifle.rotation.x, -0.10 if aiming else 0.05, 1.0 - exp(-9.0 * delta))


func _desired_clip(speed: float, aiming: bool, reloading: bool, dead: bool) -> StringName:
	if dead:
		return CLIP_DEATH
	if _hit_left > 0.0:
		return CLIP_HIT
	if reloading:
		return CLIP_RELOAD
	if aiming:
		return CLIP_AIM
	if speed > 3.1:
		return CLIP_RUN
	if speed > 0.35:
		return CLIP_WALK
	return CLIP_IDLE


func _rate_for(clip: StringName, speed: float) -> float:
	if clip == CLIP_RUN:
		return clampf(speed / RUN_SPEED, 0.6, 1.45)
	if clip == CLIP_WALK:
		return clampf(speed / 2.2, 0.55, 1.3)
	return 1.0


func _attach_rifle() -> void:
	var slot: int = _skeleton.find_bone("handslot.r")
	if slot < 0:
		slot = _skeleton.find_bone("hand.r")
	if slot < 0:
		return
	var socket: BoneAttachment3D = BoneAttachment3D.new()
	socket.name = "RifleSlot"
	socket.bone_name = _skeleton.get_bone_name(slot)
	_skeleton.add_child(socket)
	_rifle = Node3D.new()
	_rifle.name = "Rifle"
	socket.add_child(_rifle)
	var paints: Dictionary = {
		"steel": _paint(Color("2f373b"), 0.72),
		"armor": _paint(Color("333f39"), 0.10),
		"boots": _paint(Color("242826"), 0.06),
		"webbing": _paint(Color("857f68")),
		"dark": _paint(Color("463529")),
		"lens": _paint(Color("26404a"), 0.55),
	}
	var form: RefCounted = Form.new()
	_rifle_form(form)
	var mesh: ArrayMesh = form.commit()
	var keys: Array = form.surface_keys()
	for index: int in range(mesh.get_surface_count()):
		mesh.surface_set_material(index, paints[keys[min(index, keys.size() - 1)]])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "RifleMesh"
	instance.mesh = mesh
	instance.transform = Transform3D(Basis.from_euler(Vector3(0, PI, 0)) * Basis.from_scale(Vector3(0.82, 0.82, 0.82)), Vector3(0.02, -0.06, -0.14))
	_rifle.add_child(instance)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.transform = instance.transform * Transform3D(Basis(), Vector3(0.0, 0.010, -0.62))
	_rifle.add_child(muzzle)


func _paint(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55 if metal == 0.0 else 0.42
	material.metallic = metal
	return material


## Carried over from the procedural rig so the soldier still reads as armed
## rather than holding an invisible weapon.
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

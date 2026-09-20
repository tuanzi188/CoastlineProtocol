extends StaticBody3D

signal defeated(target: Node3D)
var moving: bool = false
var health: int = 100
var down: bool = false
var last_headshot: bool = false
var auto_respawn: bool = true
var rapid_respawn: bool = false
var move_speed: float = 1.1
var move_distance: float = 1.7
var _home: Vector3
var _clock: float = 0.0
var _reset_left: float = 0.0
var _pivot: Node3D
var _shape: CollisionShape3D
var _plate_material: StandardMaterial3D
var _flash: float = 0.0
var _limbs: Array[Node3D] = []

func _ready() -> void:
	_home = position
	_clock = position.x * 1.7
	_pivot = Node3D.new()
	_pivot.position.y = 0.10
	add_child(_pivot)
	_plate_material = _material(Color("a7b2a0"))
	var uniform := _material(Color("4d6260"))
	var dark := _material(Color("263637"))
	var armor := _material(Color("8a8668"))
	var visor := _material(Color("304c59"))
	visor.metallic = 0.6
	visor.roughness = 0.22
	var orange := _material(Color("df8b4b"))
	# Separate joint pivots let the moving training mannequin stride and fold down.
	for side: float in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side*0.19,0.89,0)
		_pivot.add_child(leg)
		_limbs.append(leg)
		_capsule(leg,Vector3(0,-0.21,0),0.125,0.46,uniform)
		_capsule(leg,Vector3(0,-0.58,0.015),0.105,0.40,uniform)
		_box(leg,Vector3(0,-0.41,0.115),Vector3(0.18,0.17,0.08),armor)
		_box(leg,Vector3(0,-0.80,0.075),Vector3(0.24,0.16,0.38),dark)
		var arm := Node3D.new()
		arm.position = Vector3(side*0.38,1.42,0)
		_pivot.add_child(arm)
		_limbs.append(arm)
		_capsule(arm,Vector3(side*0.045,-0.19,0),0.105,0.42,uniform)
		_capsule(arm,Vector3(side*0.06,-0.47,0.05),0.085,0.29,uniform)
		_box(arm,Vector3(side*0.06,-0.64,0.075),Vector3(0.14,0.17,0.14),dark)
		_box(arm,Vector3(side*0.03,-0.09,0.08),Vector3(0.19,0.17,0.12),armor)
	_box(_pivot,Vector3(0,1.16,0),Vector3(0.62,0.68,0.30),uniform)
	_box(_pivot,Vector3(0,1.23,0.17),Vector3(0.58,0.53,0.14),_plate_material)
	_box(_pivot,Vector3(0,1.18,-0.23),Vector3(0.46,0.49,0.22),armor)
	_box(_pivot,Vector3(0,0.86,0.01),Vector3(0.65,0.12,0.35),dark)
	for x: float in [-0.19,0,0.19]:
		_box(_pivot,Vector3(x,1.03,0.28),Vector3(0.15,0.19,0.09),armor)
	_capsule(_pivot,Vector3(0,1.68,0),0.18,0.41,armor)
	_capsule(_pivot,Vector3(0,1.79,-0.015),0.235,0.35,uniform)
	_box(_pivot,Vector3(0,1.73,0.172),Vector3(0.33,0.13,0.085),visor)
	_box(_pivot,Vector3(0,1.54,0.10),Vector3(0.23,0.11,0.19),dark)
	_box(_pivot,Vector3(0,1.36,0.255),Vector3(0.19,0.075,0.04),orange)
	for side: float in [-1,1]:
		_box(_pivot,Vector3(side*0.23,1.71,0),Vector3(0.09,0.20,0.14),dark)
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.135
	mesh.bottom_radius = 0.135
	mesh.height = 0.012
	mesh.radial_segments = 24
	ring.mesh = mesh
	ring.rotation.x = PI/2
	ring.position = Vector3(0,1.22,0.265)
	ring.material_override = orange
	_pivot.add_child(ring)
	_box(self,Vector3(0,0.04,0),Vector3(0.85,0.08,0.62),dark)
	_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.82,1.9,0.49)
	_shape.position = Vector3(0,1.08,0)
	_shape.shape = shape
	add_child(_shape)
	add_to_group("training_targets")

func _physics_process(delta: float) -> void:
	_clock += delta
	_flash = maxf(0,_flash-delta)
	_plate_material.albedo_color = Color("fff3c5") if _flash>0 else Color("a7b2a0")
	if down:
		_pivot.rotation.x = lerp_angle(_pivot.rotation.x,-PI/2,1-exp(-12*delta))
		if auto_respawn:
			_reset_left -= delta
			if _reset_left<=0: reset_target()
	else:
		_pivot.rotation.x = lerp_angle(_pivot.rotation.x,0,1-exp(-10*delta))
		if moving:
			position.x = _home.x + sin(_clock*move_speed)*move_distance
			if get_parent().has_method("get_height"):
				position.y = get_parent().get_height(position.x,position.z)
			for i: int in range(_limbs.size()):
				_limbs[i].rotation.x = sin(_clock*7.0+i*PI)*0.16

func receive_hit(damage: int,point: Vector3) -> bool:
	if down: return false
	last_headshot = to_local(point).y>1.72
	health -= damage*3 if last_headshot else damage
	_flash = 0.1
	if health<=0:
		down = true
		_shape.set_deferred("disabled",true)
		_reset_left = 1.25 if rapid_respawn else 3.8
		defeated.emit(self)
		return true
	return false

func reset_target() -> void:
	health = 100
	down = false
	last_headshot = false
	_reset_left = 0
	if is_instance_valid(_shape): _shape.set_deferred("disabled",false)

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	return m

func _capsule(parent: Node3D,pos: Vector3,radius: float,height: float,material: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height,radius*2)
	mesh.radial_segments = 10
	mesh.rings = 3
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)

func _box(parent: Node3D,pos: Vector3,size: Vector3,material: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)

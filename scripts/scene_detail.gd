extends Node3D

## Optional second-pass environment dressing. Add this node under main, then call build(world).
## All materials are local so world.gd's palette and batching remain untouched.

var materials: Dictionary = {}
var prop_count: int = 0
var world_ref: Node3D
var _built: bool = false


func build(world: Node3D) -> void:
	if _built:
		return
	_built = true
	world_ref = world
	_make_materials()
	_build_house_details()
	_build_warehouse_door()
	_build_cover_objects()
	_build_ammo_station()
	_build_service_props()
	_build_jeep()


func _make_materials() -> void:
	var palette: Dictionary = {
		"ivory": Color("d8d5be"),
		"blue": Color("7197a5"),
		"blue_dark": Color("3a6271"),
		"roof": Color("ad6249"),
		"roof_dark": Color("7b493c"),
		"wood": Color("7f684d"),
		"wood_light": Color("ad9772"),
		"dark": Color("293d44"),
		"glass": Color("446a79"),
		"white": Color("eee8d7"),
		"concrete": Color("a3aaa0"),
		"sand": Color("d9c399"),
		"steel": Color("6d807e"),
		"rust": Color("a66345"),
		"orange": Color("eaa84b"),
		"red": Color("b65343"),
		"paint": Color("ded8ba"),
		"rubber": Color("202a2b"),
		"olive": Color("58674f"),
		"canvas": Color("7d8469"),
		"brass": Color("b7904c"),
		"warning": Color("d87d37"),
		"ammo": Color("b9a65d")
	}
	for key: String in palette:
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[key]
		material.roughness = 0.84
		materials[key] = material
	var glass: StandardMaterial3D = materials["glass"]
	glass.metallic = 0.22
	glass.roughness = 0.2
	var rubber: StandardMaterial3D = materials["rubber"]
	rubber.roughness = 0.98


func _height(x: float, z: float) -> float:
	if world_ref == null:
		return 0.0
	return float(world_ref.call("get_height", x, z))


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, key: String, solid: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = materials[key]
	instance.position = pos
	parent.add_child(instance)
	prop_count += 1
	if solid:
		_add_box_collision(instance, size)
	return instance


func _add_box_collision(parent: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)


func _add_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, key: String, solid: bool = false, segments: int = 10) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	instance.mesh = mesh
	instance.material_override = materials[key]
	instance.position = pos
	parent.add_child(instance)
	prop_count += 1
	if solid:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		shape_node.shape = shape
		body.add_child(shape_node)
		instance.add_child(body)
	return instance


func _add_sphere(parent: Node3D, pos: Vector3, scale_value: Vector3, key: String, solid: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	instance.mesh = mesh
	instance.scale = scale_value
	instance.material_override = materials[key]
	instance.position = pos
	parent.add_child(instance)
	prop_count += 1
	if solid:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * 1.35
		shape_node.shape = shape
		body.add_child(shape_node)
		instance.add_child(body)
	return instance


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, key: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = materials[key]
	instance.position = pos
	parent.add_child(instance)
	prop_count += 1
	return instance


func _add_beam(parent: Node3D, a: Vector3, b: Vector3, width: float, key: String, solid: bool = false) -> MeshInstance3D:
	var beam := _add_box(parent, (a + b) * 0.5, Vector3(width, width, a.distance_to(b)), key, solid)
	var direction := b - a
	beam.basis = Basis.looking_at(direction, Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	return beam


func _side_window(root: Node3D, side: float, center_y: float, center_z: float) -> void:
	var x := side * 0.19
	# The root is shifted by the caller to each house wall, so these are local wall details.
	_add_box(root, Vector3(x, center_y + 0.82, center_z), Vector3(0.12, 0.12, 1.92), "white")
	_add_box(root, Vector3(x, center_y - 0.82, center_z), Vector3(0.12, 0.12, 1.92), "white")
	_add_box(root, Vector3(x, center_y, center_z - 0.9), Vector3(0.12, 1.78, 0.12), "white")
	_add_box(root, Vector3(x, center_y, center_z + 0.9), Vector3(0.12, 1.78, 0.12), "white")
	# Paired timber shutters sit proud of the existing side glazing.
	_add_box(root, Vector3(x + side * 0.055, center_y, center_z - 1.17), Vector3(0.11, 1.36, 0.34), "wood")
	_add_box(root, Vector3(x + side * 0.055, center_y, center_z + 1.17), Vector3(0.11, 1.36, 0.34), "wood")


func _build_house_details() -> void:
	var houses: Array[Dictionary] = [
		{"center": Vector3(-23.0, 21.0, 0.0), "size": Vector3(12.0, 7.1, 10.0), "tag": "IVORY HOUSE"},
		{"center": Vector3(-45.0, 17.0, 0.0), "size": Vector3(11.0, 7.0, 11.0), "tag": "BLUE HOUSE"},
		{"center": Vector3(-24.0, -3.0, 0.0), "size": Vector3(12.0, 4.0, 10.0), "tag": "BLUE COTTAGE"}
	]
	for house: Dictionary in houses:
		var center: Vector3 = house["center"]
		var size: Vector3 = house["size"]
		var root := Node3D.new()
		root.name = "ArchitecturalDetail_%s" % house["tag"]
		root.position = Vector3(center.x, _height(center.x, center.y), center.y)
		add_child(root)
		var floors: int = 2 if size.y > 6.0 else 1
		for floor_index: int in range(floors):
			var window_y := 1.9 + float(floor_index) * 3.4
			for side: float in [-1.0, 1.0]:
				for window_z: float in [-2.3, 1.6]:
					var wall_root := Node3D.new()
					wall_root.position.x = side * (size.x * 0.5)
					root.add_child(wall_root)
					_side_window(wall_root, side, window_y, window_z)
		# Two rear corner downpipes leave the front entrance and approach clear.
		for side: float in [-1.0, 1.0]:
			var pipe_x := side * (size.x * 0.5 + 0.34)
			var pipe_y := (size.y + 0.28) * 0.5
			_add_cylinder(root, Vector3(pipe_x, pipe_y, -size.z * 0.5 - 0.25), 0.075, size.y + 0.28, "steel", false, 8)
			_add_box(root, Vector3(pipe_x, size.y + 0.14, -size.z * 0.5 - 0.12), Vector3(0.12, 0.09, 0.34), "steel")
		# One condenser per house is mounted on the east side, above foot traffic.
		var ac_y := 2.25 if floors == 1 else 2.75
		var ac_x := size.x * 0.5 + 0.42
		_add_box(root, Vector3(ac_x, ac_y, -0.55), Vector3(1.25, 0.62, 0.5), "steel")
		_add_box(root, Vector3(ac_x + 0.27, ac_y, -0.55), Vector3(0.06, 0.39, 0.34), "dark")
		_add_cylinder(root, Vector3(ac_x + 0.34, ac_y, -0.55), 0.19, 0.08, "dark", false, 8).rotation.z = PI * 0.5
		_add_box(root, Vector3(ac_x, ac_y - 0.47, -0.55), Vector3(1.45, 0.08, 0.62), "wood")


func _build_warehouse_door() -> void:
	var root := Node3D.new()
	root.name = "DepotRollerDoorDetail"
	root.position = Vector3(34.0, _height(34.0, -12.0), -12.0)
	add_child(root)
	# The 11-wide opening remains open from ground through the existing front facade.
	_add_box(root, Vector3(-5.72, 3.25, 13.78), Vector3(0.34, 6.5, 0.42), "steel", true)
	_add_box(root, Vector3(5.72, 3.25, 13.78), Vector3(0.34, 6.5, 0.42), "steel", true)
	_add_box(root, Vector3(0.0, 6.42, 13.78), Vector3(11.75, 0.38, 0.42), "steel", true)
	_add_box(root, Vector3(0.0, 6.05, 14.02), Vector3(10.8, 0.08, 0.08), "orange")
	for x: float in [-4.8, -2.4, 0.0, 2.4, 4.8]:
		_add_box(root, Vector3(x, 5.97, 14.03), Vector3(0.055, 0.18, 0.08), "dark")
	for side: float in [-1.0, 1.0]:
		for y: float in [1.2, 3.0, 4.8]:
			_add_box(root, Vector3(side * 5.7, y, 14.03), Vector3(0.08, 0.09, 0.08), "orange")
	_label(root, Vector3(0.0, 6.84, 14.08), "ROLLER  07", 0.010)


func _build_cover_objects() -> void:
	_cover_group(Vector3(-61.0, 28.0, 0.0), 0.08, "COVER  A")
	_cover_group(Vector3(27.0, -30.0, 0.0), -0.2, "COVER  B")
	_cover_group(Vector3(53.0, 8.0, 0.0), 0.1, "COVER  C")


func _cover_group(pos: Vector3, yaw: float, label_text: String) -> void:
	var root := Node3D.new()
	root.name = "Cover_%s" % label_text.replace(" ", "_")
	root.position = Vector3(pos.x, _height(pos.x, pos.y), pos.y)
	root.rotation.y = yaw
	add_child(root)
	# Staggered sandbags make three low pieces of cover with clear lanes around them.
	for row: int in range(2):
		for column: int in range(3):
			var x := -1.35 + float(column) * 1.35 + (0.48 if row == 1 else 0.0)
			var z := -0.35 + float(row) * 0.62
			_add_sphere(root, Vector3(x, 0.38 + float(row) * 0.38, z), Vector3(0.82, 0.36, 0.43), "sand", true)
	# A short jersey barrier anchors the bags and gives the object a distinct silhouette.
	_add_box(root, Vector3(0.0, 0.46, 0.95), Vector3(4.0, 0.78, 0.55), "concrete", true)
	_add_box(root, Vector3(0.0, 0.91, 0.95), Vector3(2.9, 0.16, 0.45), "concrete")
	_add_box(root, Vector3(0.0, 0.91, 0.67), Vector3(2.5, 0.12, 0.05), "warning")
	_label(root, Vector3(0.0, 1.25, 0.97), label_text, 0.008)


func _build_ammo_station() -> void:
	var root := Node3D.new()
	root.name = "RangeAmmoStation"
	root.position = Vector3(23.0, _height(23.0, -24.0), -24.0)
	add_child(root)
	_add_box(root, Vector3(0.0, 0.16, 0.0), Vector3(2.25, 0.24, 1.45), "concrete", true)
	_add_box(root, Vector3(0.0, 1.02, 0.0), Vector3(1.75, 1.48, 1.18), "olive", true)
	_add_box(root, Vector3(0.0, 1.13, 0.62), Vector3(1.28, 0.72, 0.05), "dark")
	_add_box(root, Vector3(0.0, 1.73, 0.0), Vector3(1.95, 0.12, 1.3), "ammo")
	_add_box(root, Vector3(0.0, 1.02, -0.62), Vector3(1.4, 0.92, 0.06), "blue_dark")
	_add_box(root, Vector3(-0.9, 2.16, 0.0), Vector3(0.08, 0.78, 0.08), "steel")
	_add_box(root, Vector3(0.9, 2.16, 0.0), Vector3(0.08, 0.78, 0.08), "steel")
	_add_box(root, Vector3(0.0, 2.56, 0.0), Vector3(2.05, 0.62, 0.12), "blue_dark")
	_add_box(root, Vector3(-0.92, 2.56, 0.08), Vector3(0.08, 0.43, 0.08), "orange")
	_label(root, Vector3(0.0, 2.67, 0.08), "AMMO  //  07", 0.010)
	_label(root, Vector3(0.0, 1.36, 0.66), "RELOAD", 0.007)
	# Two visible sealed cans make the station read as a usable range prop.
	for x: float in [-0.58, 0.58]:
		_add_box(root, Vector3(x, 0.55, -0.82), Vector3(0.48, 0.55, 0.42), "ammo", true)
		_add_box(root, Vector3(x, 0.84, -0.82), Vector3(0.38, 0.06, 0.34), "red")


func _build_service_props() -> void:
	# Loose service tires sit outside the depot, away from the roller-door approach.
	var tire_root := Node3D.new()
	tire_root.name = "DepotServiceTires"
	tire_root.position = Vector3(48.0, _height(48.0, -4.0), -4.0)
	add_child(tire_root)
	for i: int in range(3):
		var tire := _add_cylinder(tire_root, Vector3(0.0, 0.48 + float(i) * 0.42, 0.0), 0.43, 0.24, "rubber", false, 12)
		tire.rotation.z = PI * 0.5
		var hub := _add_cylinder(tire_root, Vector3(0.14, 0.48 + float(i) * 0.42, 0.0), 0.14, 0.26, "steel", false, 10)
		hub.rotation.z = PI * 0.5
	# One material-shared MultiMesh keeps the depot's perimeter bollards inexpensive.
	var bollard_mesh := CylinderMesh.new()
	bollard_mesh.top_radius = 0.11
	bollard_mesh.bottom_radius = 0.13
	bollard_mesh.height = 1.0
	bollard_mesh.radial_segments = 8
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = bollard_mesh
	var bollard_positions: Array[Vector3] = []
	for z: float in [-8.0, -4.0, 4.0, 8.0]:
		bollard_positions.append(Vector3(48.7, _height(48.7, z) + 0.5, z))
	multi.instance_count = bollard_positions.size()
	for i: int in range(bollard_positions.size()):
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, bollard_positions[i]))
	var bollards := MultiMeshInstance3D.new()
	bollards.name = "DepotBollardMultiMesh"
	bollards.multimesh = multi
	bollards.material_override = materials["orange"]
	add_child(bollards)
	prop_count += 1
	for z: float in [-8.0, -4.0, 4.0, 8.0]:
		_add_box(self, Vector3(48.7, _height(48.7, z) + 0.93, z), Vector3(0.24, 0.09, 0.24), "white")


func _add_torus(parent: Node3D, pos: Vector3, inner_radius: float, outer_radius: float, key: String) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	torus.rings = 8
	torus.ring_segments = 12
	return _add_mesh(parent, torus, pos, key)


func _build_jeep() -> void:
	var jeep := Node3D.new()
	jeep.name = "CoastalMilitaryJeep"
	jeep.position = Vector3(-8.0, _height(-8.0, 24.0), 24.0)
	jeep.rotation.y = -0.12
	add_child(jeep)
	# Low chassis is the only large collision volume, leaving the nearby house entry open.
	_add_box(jeep, Vector3(0.0, 0.72, 0.0), Vector3(2.75, 0.42, 4.35), "dark", true)
	_add_box(jeep, Vector3(0.0, 1.08, 0.55), Vector3(2.58, 0.52, 2.45), "olive", false)
	_add_box(jeep, Vector3(0.0, 1.28, -1.45), Vector3(2.48, 0.48, 1.18), "olive", false)
	_add_box(jeep, Vector3(0.0, 1.53, -0.88), Vector3(2.4, 0.1, 0.08), "dark")
	# Four separate low-poly tire meshes and steel hubs.
	for x: float in [-1.34, 1.34]:
		for z: float in [-1.42, 1.42]:
			var wheel := _add_cylinder(jeep, Vector3(x, 0.68, z), 0.53, 0.3, "rubber", false, 12)
			wheel.rotation.z = PI * 0.5
			var hub := _add_cylinder(jeep, Vector3(x + (-0.17 if x < 0.0 else 0.17), 0.68, z), 0.2, 0.32, "steel", false, 10)
			hub.rotation.z = PI * 0.5
	# Open cab, seats, and the canvas roof.
	_add_box(jeep, Vector3(-0.62, 1.47, 0.55), Vector3(0.82, 0.18, 0.92), "canvas")
	_add_box(jeep, Vector3(0.62, 1.47, 0.55), Vector3(0.82, 0.18, 0.92), "canvas")
	_add_box(jeep, Vector3(-0.62, 1.85, 0.93), Vector3(0.82, 0.65, 0.14), "canvas")
	_add_box(jeep, Vector3(0.62, 1.85, 0.93), Vector3(0.82, 0.65, 0.14), "canvas")
	_add_box(jeep, Vector3(0.0, 2.47, 0.52), Vector3(2.16, 0.12, 1.8), "canvas")
	# Windshield glass, four slim frame members, and two side mirrors.
	_add_box(jeep, Vector3(0.0, 1.95, -0.67), Vector3(2.1, 1.12, 0.06), "glass")
	_add_beam(jeep, Vector3(-1.08, 1.42, -0.7), Vector3(-1.08, 2.5, -0.7), 0.09, "steel")
	_add_beam(jeep, Vector3(1.08, 1.42, -0.7), Vector3(1.08, 2.5, -0.7), 0.09, "steel")
	_add_beam(jeep, Vector3(-1.08, 2.5, -0.7), Vector3(1.08, 2.5, -0.7), 0.09, "steel")
	for x: float in [-1.36, 1.36]:
		_add_box(jeep, Vector3(x, 2.02, -0.78), Vector3(0.28, 0.16, 0.38), "steel")
		_add_box(jeep, Vector3(x + (0.12 if x < 0.0 else -0.12), 2.02, -0.79), Vector3(0.06, 0.1, 0.24), "glass")
	# Steering wheel and simple spokes in front of the driver's seat.
	var steering := _add_torus(jeep, Vector3(-0.58, 1.88, -0.9), 0.18, 0.24, "dark")
	steering.rotation.x = PI * 0.5
	_add_beam(jeep, Vector3(-0.58, 1.88, -0.9), Vector3(-0.58, 1.88, -0.59), 0.055, "steel")
	_add_beam(jeep, Vector3(-0.58, 1.88, -0.9), Vector3(-0.36, 1.88, -0.9), 0.055, "steel")
	# Front grille, bumper, tow points, and warm headlamps.
	_add_box(jeep, Vector3(0.0, 1.14, -2.08), Vector3(2.38, 0.34, 0.16), "steel", false)
	for x: float in [-0.72, -0.24, 0.24, 0.72]:
		_add_box(jeep, Vector3(x, 1.25, -2.18), Vector3(0.07, 0.44, 0.06), "dark")
	for x: float in [-0.78, 0.78]:
		var lamp := _add_cylinder(jeep, Vector3(x, 1.35, -2.17), 0.19, 0.09, "white", false, 10)
		lamp.rotation.x = PI * 0.5
	_add_box(jeep, Vector3(0.0, 0.83, -2.28), Vector3(2.85, 0.2, 0.2), "dark")
	_add_box(jeep, Vector3(-1.15, 1.02, -2.3), Vector3(0.18, 0.25, 0.2), "brass")
	_add_box(jeep, Vector3(1.15, 1.02, -2.3), Vector3(0.18, 0.25, 0.2), "brass")
	_label(jeep, Vector3(0.0, 2.57, 0.58), "CP-08", 0.007)


func _label(parent: Node3D, pos: Vector3, text: String, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 128
	label.pixel_size = pixel * 40.0 / float(label.font_size)
	label.position = pos
	label.modulate = Color("f0e9d6")
	label.outline_size = 4
	label.outline_modulate = Color(0.05, 0.07, 0.08, 0.85)
	label.no_depth_test = false
	label.double_sided = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	label.font = font
	parent.add_child(label)

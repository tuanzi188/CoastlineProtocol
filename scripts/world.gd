extends Node3D

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var materials: Dictionary = {}
var targets: Array[Node3D] = []
var visited: Dictionary = {}
var terrain: StaticBody3D
var water: MeshInstance3D

func _ready() -> void:
	rng.seed = 734109
	_palette()
	_environment()
	_terrain()
	_coast()
	_roads()
	_town()
	_warehouse(Vector3(34, 0, -12))
	_hill_outpost()
	_nature()
	_details()
	_batch_static_boxes()

func _batch_static_boxes() -> void:
	var batches: Dictionary = {}
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.mesh is BoxMesh or not materials.values().has(instance.material_override):
			continue
		var key: int = instance.material_override.get_instance_id()
		if not batches.has(key):
			batches[key] = {"material":instance.material_override,"transforms":[]}
		var transform: Transform3D = global_transform.affine_inverse() * instance.global_transform
		transform.basis = transform.basis.scaled_local((instance.mesh as BoxMesh).size)
		batches[key]["transforms"].append(transform)
		# Keep collision children in place; only static rendering is batched.
		instance.mesh = null
	for key: int in batches:
		var batch: Dictionary = batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		mm.mesh = cube
		mm.instance_count = batch["transforms"].size()
		for i: int in range(mm.instance_count):
			mm.set_instance_transform(i,batch["transforms"][i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = mm
		visual.material_override = batch["material"]
		add_child(visual)

func get_height(x: float, z: float) -> float:
	var coast_line: float = 88.0 + sin(x * 0.028) * 10.0
	var base: float = 2.5 + sin(x * 0.021) * 0.55 + cos(z * 0.036) * 0.35
	var hill: float = 24.0 * exp(-((x + 32.0) * (x + 32.0) / 2200.0 + (z + 89.0) * (z + 89.0) / 1700.0))
	hill += 13.0 * exp(-((x - 108.0) * (x - 108.0) / 1600.0 + (z + 66.0) * (z + 66.0) / 2200.0))
	var town_flat: float = 1.0 - smoothstep(36.0, 69.0, Vector2(x + 13.0, z - 3.0).length())
	base = lerpf(base + hill, 2.9, town_flat * 0.96)
	var wh_flat: float = 1.0 - smoothstep(15.0, 27.0, Vector2(x - 34.0, z + 12.0).length())
	base = lerpf(base, 3.0, wh_flat)
	var beach: float = smoothstep(coast_line - 26.0, coast_line + 20.0, z)
	base = lerpf(base, -4.5, beach)
	var edge: float = maxf(absf(x) - 134.0, -z - 147.0)
	base = lerpf(base, -6.0, smoothstep(0.0, 40.0, edge))
	return base

func get_zone(pos: Vector3) -> String:
	if pos.z > 60: return "南岸海滩 / SOUTH SHORE"
	if pos.z < -57: return "北部山坡 / NORTH RIDGE"
	if pos.x > 20 and pos.z < 20: return "物流仓库 / DEPOT 07"
	if pos.z < -20 and pos.x > -8 and pos.x < 25: return "北部开阔地 / NORTH FIELD"
	if pos.x < -9 and pos.z < 37: return "海岸房区 / COASTAL VILLAGE"
	return "海岸公路 / COAST ROAD"

func reset_targets() -> void:
	for target: Node3D in targets:
		target.reset_target()

func mat(key: String) -> Material:
	return materials[key] as Material

func _palette() -> void:
	var colors: Dictionary = {
		"ivory":"d8d5be", "blue":"7197a5", "blue_dark":"3a6271", "roof":"ad6249",
		"roof_dark":"7b493c", "wood":"7f684d", "wood_light":"ad9772", "dark":"293d44",
		"glass":"446a79", "white":"eee8d7", "concrete":"a3aaa0", "road":"555e5d",
		"sand":"d9c399", "steel":"6d807e", "rust":"a66345", "orange":"eaa84b",
		"leaf":"63875b", "leaf_light":"819a60", "leaf_dark":"486a51", "trunk":"6a5843",
		"rock":"929489", "cyan":"65ced0", "red":"b65343", "paint":"ded8ba"}
	for key: String in colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(colors[key])
		m.roughness = 0.87
		materials[key] = m
	var glass: StandardMaterial3D = materials["glass"]
	glass.metallic = 0.3
	glass.roughness = 0.22

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4a87ad")
	sky_mat.sky_horizon_color = Color("c6dbe0")
	sky_mat.ground_bottom_color = Color("759795")
	sky_mat.ground_horizon_color = Color("c6dbe0")
	sky_mat.sky_curve = 0.17
	sky_mat.sun_angle_max = 5.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4cfda")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("adcbd0")
	env.fog_light_energy = 0.8
	env.fog_density = 0.0010
	env.fog_sky_affect = 0.14
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

func _terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step: float = 4.0
	var side: int = 91
	# Shared grid vertices so generate_normals() averages across faces; loose
	# per-quad vertices flat-shade every 4 m tile and stair-step the slopes.
	for iz: int in range(side):
		for ix: int in range(side):
			var x: float = -180.0 + ix * step
			var z: float = -180.0 + iz * step
			var h: float = get_height(x, z)
			var grain: float = float(((ix * 73856093) ^ (iz * 19349663)) % 51) / 1000.0 - 0.025
			var grass := Color(0.38 + grain, 0.48 + grain, 0.285 + grain)
			var beach_weight: float = 1.0 - smoothstep(0.4, 2.6, h)
			st.set_color(grass.lerp(Color("cbb890"), beach_weight))
			st.add_vertex(Vector3(x, h, z))
	for iz: int in range(side - 1):
		for ix: int in range(side - 1):
			var a: int = iz * side + ix
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + side)
			st.add_index(a + 1)
			st.add_index(a + side + 1)
			st.add_index(a + side)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	terrain = StaticBody3D.new()
	terrain.name = "IslandTerrain"
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	terrain.add_child(collider)
	add_child(terrain)
	var ocean_shader := Shader.new()
	ocean_shader.code = "shader_type spatial; render_mode cull_disabled; uniform vec3 deep_color : source_color = vec3(0.035,0.32,0.40); uniform vec3 crest_color : source_color = vec3(0.25,0.64,0.65); varying vec3 world_pos; void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; VERTEX.y += sin(world_pos.x*0.09+TIME*0.8)*0.11+cos(world_pos.z*0.13+TIME*0.6)*0.09;} void fragment(){float waves=sin(world_pos.x*0.34+world_pos.z*0.18+TIME*1.3)*cos(world_pos.z*0.44-TIME*0.85); float foam=pow(max(0.0,waves),14.0); ALBEDO=mix(deep_color,crest_color,0.2+0.4*sin(world_pos.z*0.025)+foam*0.65); ROUGHNESS=0.24; METALLIC=0.22; NORMAL=normalize(vec3(sin(world_pos.x*0.22+TIME)*0.10,cos(world_pos.z*0.26+TIME)*0.09,1.0));}"
	var ocean_mat := ShaderMaterial.new()
	ocean_mat.shader = ocean_shader
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	plane.subdivide_width = 110
	plane.subdivide_depth = 110
	water.mesh = plane
	water.material_override = ocean_mat
	water.position.y = -0.35
	add_child(water)

func _coast() -> void:
	# Pale ribbons follow the actual coastline instead of a straight beach edge.
	for row: int in range(3):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in range(70):
			var x: float = -139.0 + i * 4.0
			var z1: float = 88.0 + sin(x * 0.028) * 10.0 + row * 3.2
			var z2: float = 88.0 + sin((x + 4) * 0.028) * 10.0 + row * 3.2
			for v: Vector3 in [Vector3(x,-0.12,z1),Vector3(x+4,-0.12,z2),Vector3(x,-0.12,z1+0.34),Vector3(x+4,-0.12,z2),Vector3(x+4,-0.12,z2+0.34),Vector3(x,-0.12,z1+0.34)]: st.add_vertex(v)
		st.generate_normals()
		var foam := MeshInstance3D.new()
		foam.mesh = st.commit()
		foam.material_override = mat("white")
		add_child(foam)
	var pier_y: float = 1.1
	_box(self, Vector3(55,pier_y,93),Vector3(4,0.3,28),"wood",true)
	for z: int in range(80, 109, 4):
		for x: float in [53.2,56.8]:
			_cylinder(self,Vector3(x,-0.3,z),0.17,4.4,"wood",true)
		_box(self,Vector3(55,pier_y+0.18,z),Vector3(4,0.03,0.07),"wood_light",false)
	_boat(Vector3(61,0.2,104))
	for i: int in range(6):
		var x: float = -230.0 + i * 105.0
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radial_segments = 9
		sphere.rings = 4
		rock.mesh = sphere
		rock.scale = Vector3(70, rng.randf_range(18,44), 40)
		rock.position = Vector3(x,-12,-310-rng.randf_range(0,70))
		rock.material_override = mat("blue_dark")
		add_child(rock)

func _roads() -> void:
	_ribbon(Vector2(-127,40),Vector2(128,40),7.5,"road")
	_ribbon(Vector2(1,65),Vector2(1,-44),6.5,"road")
	_ribbon(Vector2(1,2),Vector2(61,2),5.5,"road")
	for x: int in range(-124,127,6):
		if abs(x) < 7: continue
		_box(self,Vector3(x,get_height(x,40)+0.07,40),Vector3(1.8,0.015,0.16),"paint",false)
	for z: int in range(-41,64,6):
		if abs(z-40) < 7 or abs(z-2) < 5: continue
		_box(self,Vector3(1,get_height(1,z)+0.07,z),Vector3(0.16,0.015,1.8),"paint",false)
	for x: int in range(-105,116,16):
		if x > 44 and x < 67: continue
		var y: float = get_height(x,46)
		_cylinder(self,Vector3(x,y+0.65,46),0.1,1.3,"white",false)
		_box(self,Vector3(x,y+1.08,46),Vector3(0.23,0.12,0.23),"orange",false)
	_ribbon(Vector2(-5,-42),Vector2(-31,-83),3.6,"sand")
	_ribbon(Vector2(-31,-83),Vector2(-49,-106),3.0,"sand")

func _ribbon(a: Vector2,b: Vector2,width: float,key: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = ceili(a.distance_to(b)/2.0)
	var side: Vector2 = (b-a).normalized().orthogonal()*width*0.5
	for i: int in range(count):
		var p: Vector2 = a.lerp(b,float(i)/count)
		var q: Vector2 = a.lerp(b,float(i+1)/count)
		var ps: Array[Vector2] = [p+side,q+side,p-side,q+side,q-side,p-side]
		for v: Vector2 in ps: st.add_vertex(Vector3(v.x,get_height(v.x,v.y)+0.045,v.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat(key)
	add_child(mi)

func _town() -> void:
	_house(Vector3(-23,0,21),Vector3(12,7.1,10),"ivory",0)
	_house(Vector3(-45,0,17),Vector3(11,7.0,11),"blue",0)
	_house(Vector3(-24,0,-3),Vector3(12,4.0,10),"blue",0)
	_house(Vector3(-49,0,-10),Vector3(13,4.1,11),"ivory",PI/2)
	_house(Vector3(-78,0,20),Vector3(10,4.0,9),"ivory",0.1)
	for pos: Vector3 in [Vector3(-15,0,31),Vector3(-35,0,4),Vector3(-65,0,23)]:
		_crate(pos,Vector3(1.4,1.3,1.4))
	for x: int in range(-56,-12,4):
		if x > -30 and x < -19: continue
		var y: float = get_height(x,32)
		_box(self,Vector3(x,y+0.55,32),Vector3(3.7,1.1,0.24),"concrete",true)
	for z: int in range(-15,29,7):
		var y: float = get_height(-61,z)
		_box(self,Vector3(-61,y+0.65,z),Vector3(0.24,1.3,6.6),"concrete",true)
	_label(self,Vector3(-23,5.8,26.2),"COASTAL  /  01",0.028)
	_sign(Vector3(-7,0,36),"房区  ←   VILLAGE","仓库  ↑   DEPOT 07")

func _house(pos: Vector3,size: Vector3,key: String,angle: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x,get_height(pos.x,pos.z),pos.z)
	root.rotation.y = angle
	add_child(root)
	var w: float=size.x
	var h: float=size.y
	var d: float=size.z
	_box(root,Vector3(0,0.06,0),Vector3(w+0.25,0.18,d+0.25),"concrete",true)
	# Front door and large window apertures are physical gaps, not painted rectangles.
	var floor_count: int = 2 if h>6 else 1
	for floor_i: int in range(floor_count):
		var by: float=floor_i*3.4
		_box(root,Vector3(0,by+2.92,d/2),Vector3(w,0.96,0.25),key,true)
		_box(root,Vector3(-w/2+0.75,by+1.28,d/2),Vector3(1.5,2.35,0.25),key,true)
		_box(root,Vector3(w/2-0.75,by+1.28,d/2),Vector3(1.5,2.35,0.25),key,true)
		for x: float in [-2.0,2.0]:
			_box(root,Vector3(x,by+1.28,d/2),Vector3(1.2,2.35,0.25),key,true)
		for x: float in [-w/2+2.85,w/2-2.85]:
			_box(root,Vector3(x,by+0.55,d/2),Vector3(2.7,0.98,0.26),key,true)
			_box(root,Vector3(x,by+1.05,d/2+0.13),Vector3(2.8,0.12,0.43),"white",false)
			_box(root,Vector3(x,by+1.78,d/2),Vector3(0.08,1.42,0.3),"wood",false)
		if floor_i==1:
			_box(root,Vector3(0,by+1.25,d/2),Vector3(2.8,2.35,0.25),key,true)
			_box(root,Vector3(0,3.43,0.8),Vector3(w,0.16,d-1.6),"wood",true)
			# Rear strip is the stairwell opening.
			for i: int in range(17):
				_box(root,Vector3(-w/2+0.6+i*0.55,0.10+i*0.1,-d/2+0.88),Vector3(0.58,0.2+i*0.2,1.5),"wood",false)
			_ramp(root,Vector3(-w/2+0.32,0.14,-d/2+0.88),Vector3(-w/2+9.55,3.45,-d/2+0.88),1.5,"wood")
		_box(root,Vector3(-w/2,by+1.78,0),Vector3(0.25,3.4,d),key,true)
		_box(root,Vector3(w/2,by+1.78,0),Vector3(0.25,3.4,d),key,true)
		_box(root,Vector3(0,by+1.78,-d/2),Vector3(w,3.4,0.25),key,true)
		for side: float in [-1,1]:
			for z: float in [-2.3,1.6]:
				_box(root,Vector3(side*(w/2+0.14),by+1.9,z),Vector3(0.05,1.5,1.6),"glass",false)
				_box(root,Vector3(side*(w/2+0.18),by+1.12,z),Vector3(0.15,0.12,1.9),"white",false)
		_box(root,Vector3(0,by+0.11,d/2+0.23),Vector3(2.9,0.18,0.8),"concrete",true)
	_box(root,Vector3(0,0.12,d/2+0.73),Vector3(3.2,0.22,0.65),"concrete",true)
	_roof(root,w+0.9,d+0.9,h,2.05,"roof")
	_box(root,Vector3(-w/2+1.4,h+1.2,-1.5),Vector3(0.8,2.6,0.8),"ivory",true)
	_box(root,Vector3(-w/2+1.4,h+2.53,-1.5),Vector3(1.0,0.15,1.0),"dark",false)
	_box(root,Vector3(w/2-2.0,0.7,-1),Vector3(2.6,1.2,0.85),"wood",true)
	_box(root,Vector3(-w/2+1.5,0.48,0.5),Vector3(1.5,0.8,2.8),"blue_dark",true)
	_box(root,Vector3(-w/2+1.5,0.94,-0.5),Vector3(1.3,0.18,0.65),"ivory",false)

func _roof(root: Node3D,w: float,d: float,y: float,rise: float,key: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a:=Vector3(-w/2,y,-d/2)
	var b:=Vector3(w/2,y,-d/2)
	var c:=Vector3(-w/2,y,d/2)
	var dd:=Vector3(w/2,y,d/2)
	var e:=Vector3(0,y+rise,-d/2)
	var f:=Vector3(0,y+rise,d/2)
	for v: Vector3 in [a,e,c,c,e,f,e,b,f,f,b,dd,a,b,e,c,f,dd]: st.add_vertex(v)
	st.generate_normals()
	var mesh: ArrayMesh=st.commit()
	var mi:=MeshInstance3D.new()
	mi.mesh=mesh
	var roof_material: StandardMaterial3D = mat(key).duplicate() as StandardMaterial3D
	roof_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override=roof_material
	root.add_child(mi)
	var body:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	cs.shape=mesh.create_trimesh_shape()
	body.add_child(cs)
	root.add_child(body)
	for z: float in [-d/2,d/2]:
		_beam(root,Vector3(-w/2,y,z),Vector3(0,y+rise,z),0.1,"roof_dark")
		_beam(root,Vector3(0,y+rise,z),Vector3(w/2,y,z),0.1,"roof_dark")
	for i: int in range(1,13):
		var z: float=lerpf(-d/2,d/2,float(i)/13)
		_beam(root,Vector3(-w/2,y+0.02,z),Vector3(0,y+rise+0.02,z),0.035,"roof_dark")
		_beam(root,Vector3(0,y+rise+0.02,z),Vector3(w/2,y+0.02,z),0.035,"roof_dark")

func _warehouse(pos: Vector3) -> void:
	var root:=Node3D.new()
	root.position=Vector3(pos.x,get_height(pos.x,pos.z),pos.z)
	add_child(root)
	_box(root,Vector3(0,0.06,0),Vector3(22,0.2,27),"concrete",true)
	_box(root,Vector3(-11,3.3,0),Vector3(0.3,6.6,27),"steel",true)
	_box(root,Vector3(11,3.3,0),Vector3(0.3,6.6,27),"steel",true)
	_box(root,Vector3(0,3.3,-13.5),Vector3(22,6.6,0.3),"steel",true)
	for x: float in [-8.3,8.3]: _box(root,Vector3(x,3.3,13.5),Vector3(5.4,6.6,0.3),"steel",true)
	_box(root,Vector3(0,5.85,13.5),Vector3(11.2,1.5,0.3),"blue_dark",true)
	_roof(root,23.0,28.0,6.6,2.5,"blue_dark")
	for z: int in range(-12,14,4):
		for x: float in [-10.6,10.6]: _box(root,Vector3(x,3.3,z),Vector3(0.24,6.6,0.24),"dark",false)
		_beam(root,Vector3(-10.6,6.6,z),Vector3(0,8.9,z),0.13,"dark")
		_beam(root,Vector3(0,8.9,z),Vector3(10.6,6.6,z),0.13,"dark")
	for x: int in range(-10,11):
		_box(root,Vector3(x,3.2,-13.68),Vector3(0.05,6.2,0.06),"blue_dark",false)
	for z: int in range(-13,14):
		for x: float in [-11.18,11.18]: _box(root,Vector3(x,3.2,z),Vector3(0.06,6.2,0.05),"blue_dark",false)
	_label(root,Vector3(0,6.0,13.78),"DEPOT   07",0.032)
	for x: float in [-6.7,6.7]:
		for z: float in [-7.5,-1.5,5.0]:
			_box(root,Vector3(x,1.05,z),Vector3(3.1,2.0,2.5),"wood_light",true)
			for off: float in [-1.3,1.3]: _box(root,Vector3(x+off,1.05,z+1.28),Vector3(0.15,2.0,0.07),"wood",false)
			_box(root,Vector3(x,2.5,z),Vector3(2.4,0.9,2),"wood",true)
		_box(root,Vector3(x,3.8,-2),Vector3(3.8,0.18,19),"dark",true)
	for x: float in [-5.2,5.2]:
		_cylinder(root,Vector3(x,0.6,14.2),0.14,1.2,"orange",true)
	_box(root,Vector3(0,0.12,14),Vector3(11,0.18,1.0),"concrete",true)
	_container(Vector3(62,0,-12),"rust")
	_container(Vector3(62,0,-28),"blue_dark")
	_crate(Vector3(50,0,8),Vector3(2.2,2,2.2))
	_sign(Vector3(18,0,11),"07  物流仓库","DEPOT / SUPPLY")

func _container(pos: Vector3,key: String) -> void:
	var y: float=get_height(pos.x,pos.z)
	_box(self,Vector3(pos.x,y+1.6,pos.z),Vector3(5.6,3.2,12),key,true)
	for z: int in range(-5,6):
		for side: float in [-1,1]: _box(self,Vector3(pos.x+side*2.83,y+1.6,pos.z+z),Vector3(0.06,3.0,0.08),"dark",false)
	_box(self,Vector3(pos.x,y+1.6,pos.z+6.04),Vector3(0.07,3.0,0.06),"white",false)
	_label(self,Vector3(pos.x,y+2.35,pos.z+6.07),"C P   /   0 7",0.034)

func _hill_outpost() -> void:
	var p:=Vector3(-34,0,-89)
	p.y=get_height(p.x,p.z)
	_box(self,p+Vector3(0,0.08,0),Vector3(12,0.18,10),"concrete",true)
	for i: int in range(8):
		_box(self,p+Vector3(-5+i*1.45,0.6,-4.2),Vector3(1.4,1.2,0.65),"wood_light",true)
	var mast: Vector3=p+Vector3(3,0,0)
	_cylinder(self,mast+Vector3(0,5.5,0),0.12,11,"dark",true)
	var flag:=MeshInstance3D.new()
	var flag_mesh:=PlaneMesh.new()
	flag_mesh.size=Vector2(2.6,1.3)
	flag_mesh.subdivide_width=16
	flag.mesh=flag_mesh
	flag.rotation_degrees=Vector3(90,0,0)
	flag.position=mast+Vector3(1.3,10.1,0)
	var sh:=Shader.new()
	sh.code="shader_type spatial; render_mode cull_disabled; void vertex(){VERTEX.y+=sin(VERTEX.x*3.5+TIME*3.0)*0.13*(VERTEX.x+1.3);} void fragment(){ALBEDO=vec3(0.90,0.55,0.19); ROUGHNESS=0.9;}"
	var sm:=ShaderMaterial.new()
	sm.shader=sh
	flag.material_override=sm
	add_child(flag)
	_sign(Vector3(-30,0,-77),"北部山坡 / 观测点","NORTH RIDGE  ·  27 M")
	for pos: Vector3 in [p+Vector3(-4,0,1),p+Vector3(-3,0,3)]: _crate(pos,Vector3(1.3,1.2,1.3))
	# Distant landmark: an open-frame water tower.
	var t:=Vector3(-91,get_height(-91,-37),-37)
	for x: float in [-2.0,2.0]:
		for z: float in [-2.0,2.0]:
			_beam(self,t+Vector3(x*1.4,0,z*1.4),t+Vector3(x,11,z),0.2,"steel")
		_beam(self,t+Vector3(x*1.4,1,-2.8),t+Vector3(x,10,2),0.11,"steel")
	_cylinder(self,t+Vector3(0,12.5,0),3.4,4.0,"ivory",true)
	_cylinder(self,t+Vector3(0,14.6,0),3.6,0.2,"dark",false)

func _nature() -> void:
	for i: int in range(205):
		var x: float=rng.randf_range(-141,140)
		var z: float=rng.randf_range(-144,83)
		var y: float=get_height(x,z)
		if y<1.8 or absf(z-40)<10 or absf(x-1)<9: continue
		if x>-89 and x<78 and z>-60 and z<34: continue
		if Vector2(x+34,z+89).length()<13: continue
		if absf(x-(-5+(z+42)*0.64))<5 and z<-40 and z>-109: continue
		_tree(Vector3(x,y,z),rng.randf_range(0.85,1.5),i%4==0)
	for i: int in range(105):
		var x: float=rng.randf_range(-135,136)
		var z: float=rng.randf_range(-143,82)
		var y: float=get_height(x,z)
		if y<0.6 or absf(z-40)<9 or absf(x-1)<7: continue
		if x>-85 and x<77 and z>-60 and z<36: continue
		var mi:=MeshInstance3D.new()
		var sphere:=SphereMesh.new()
		sphere.radial_segments=7
		sphere.rings=3
		mi.mesh=sphere
		mi.material_override=mat("rock")
		mi.position=Vector3(x,y+0.3,z)
		mi.scale=Vector3(rng.randf_range(1.2,3.5),rng.randf_range(0.8,2.1),rng.randf_range(1.0,3.0))
		mi.rotation.y=rng.randf()*TAU
		add_child(mi)
		mi.create_convex_collision()
	for pos: Vector3 in [Vector3(-11,0,28),Vector3(-64,0,40),Vector3(19,0,42),Vector3(-40,0,60),Vector3(72,0,46),Vector3(-67,0,-27)]:
		pos.y=get_height(pos.x,pos.z)
		_tree(pos,1.1,false)
	# Instanced meadow blades add close-range texture without hundreds of draw calls.
	var mm:=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.use_colors=true
	var blade:=PrismMesh.new()
	blade.size=Vector3(0.13,0.46,0.10)
	mm.mesh=blade
	var transforms: Array[Transform3D]=[]
	for i: int in range(8000):
		var x: float=rng.randf_range(-135,135)
		var z: float=rng.randf_range(-140,73)
		var y: float=get_height(x,z)
		if y<2.3 or absf(z-40)<6 or absf(x-1)<5: continue
		if x>-85 and x<77 and z>-60 and z<35: continue
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU),Vector3(x,y+0.2,z)))
	mm.instance_count=transforms.size()
	for i: int in range(transforms.size()):
		mm.set_instance_transform(i,transforms[i])
		mm.set_instance_color(i,Color("8c9a60").lerp(Color("b3af74"),rng.randf()))
	var grass_mat:=StandardMaterial3D.new()
	grass_mat.vertex_color_use_as_albedo=true
	grass_mat.roughness=1
	var inst:=MultiMeshInstance3D.new()
	inst.multimesh=mm
	inst.material_override=grass_mat
	inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

func _tree(pos: Vector3,s: float,pine: bool) -> void:
	_cylinder(self,pos+Vector3(0,2.5*s,0),0.24*s,5*s,"trunk",true)
	if pine:
		for j: int in range(3):
			var cone:=MeshInstance3D.new()
			var cm:=CylinderMesh.new()
			cm.top_radius=0
			cm.bottom_radius=(2.4-j*0.45)*s
			cm.height=3.6*s
			cm.radial_segments=8
			cone.mesh=cm
			cone.position=pos+Vector3(0,(4.0+j*1.2)*s,0)
			cone.material_override=mat("leaf_dark" if j%2==0 else "leaf")
			add_child(cone)
	else:
		for j: int in range(4):
			var crown:=MeshInstance3D.new()
			var sm:=SphereMesh.new()
			sm.radial_segments=8
			sm.rings=4
			crown.mesh=sm
			crown.scale=Vector3(3.8,2.7,3.5)*s*(1.0 if j==0 else 0.68)
			crown.position=pos+Vector3(0,5.7*s,0) if j==0 else pos+Vector3(sin(j*2.1)*1.9,4.8,cos(j*2.1)*1.6)*s
			crown.material_override=mat("leaf_light" if j%2==0 else "leaf")
			add_child(crown)

func _details() -> void:
	for x: int in range(-112,122,32):
		var y: float=get_height(x,34)
		_cylinder(self,Vector3(x,y+4.8,34),0.13,9.6,"wood",true)
		_box(self,Vector3(x,y+8.7,34),Vector3(2.6,0.17,0.16),"dark",false)
		if x<100:
			for off: float in [-1,1]:
				for j: int in range(8):
					var xx: float=x+j*4.0
					var ya: float=y+9.0-sin(float(j)/8*PI)*0.8
					var yb: float=lerpf(y,get_height(x+32,34),float(j+1)/8)+9.0-sin(float(j+1)/8*PI)*0.8
					_beam(self,Vector3(xx+off,ya,34),Vector3(xx+4+off,yb,34),0.018,"dark")
	_truck(Vector3(21,0,22))
	for i: int in range(4):
		var p:=Vector3(47+i*1.15,0,15)
		p.y=get_height(p.x,p.z)
		_cylinder(self,p+Vector3(0,0.6,0),0.4,1.2,"rust",true)
		for h: float in [0.25,0.95]: _cylinder(self,p+Vector3(0,h,0),0.415,0.07,"dark",false)
	_sign(Vector3(6,0,53),"海岸行动 / COASTLINE","SECTOR 07   ·   COAST ROAD")

func _truck(pos: Vector3) -> void:
	var r:=Node3D.new()
	r.position=Vector3(pos.x,get_height(pos.x,pos.z),pos.z)
	r.rotation.y=-0.12
	add_child(r)
	_box(r,Vector3(0,0.9,0),Vector3(2.6,0.4,6),"dark",true)
	_box(r,Vector3(0,1.6,-1.8),Vector3(2.5,1.7,2),"leaf_dark",true)
	_box(r,Vector3(0,2.12,-2.82),Vector3(2.18,0.66,0.04),"glass",false)
	_box(r,Vector3(0,1.43,-3.02),Vector3(2.5,0.6,0.44),"leaf_dark",true)
	_box(r,Vector3(0,1.45,1.1),Vector3(2.5,0.8,3.65),"wood",true)
	for x: float in [-1.25,1.25]:
		for z: float in [-1.8,1.9]:
			var wheel: MeshInstance3D=_cylinder(r,Vector3(x,0.62,z),0.62,0.36,"dark",false)
			wheel.rotation.z=PI/2
	for x: float in [-0.84,0.84]: _box(r,Vector3(x,1.45,-3.27),Vector3(0.4,0.27,0.05),"ivory",false)

func _boat(pos: Vector3) -> void:
	_box(self,pos,Vector3(2.2,0.65,5),"blue_dark",true)
	_box(self,pos+Vector3(0,0.38,0),Vector3(1.8,0.14,4.5),"wood_light",false)
	for x: float in [-1.0,1.0]: _box(self,pos+Vector3(x,0.5,0),Vector3(0.17,0.45,5),"white",false)
	_box(self,pos+Vector3(0,0.55,-2.3),Vector3(2,0.4,0.18),"white",false)
	_box(self,pos+Vector3(0,0.9,0.4),Vector3(1.4,0.15,0.48),"wood",false)

func _crate(pos: Vector3,size: Vector3) -> void:
	var p:=Vector3(pos.x,get_height(pos.x,pos.z)+size.y/2,pos.z)
	_box(self,p,size,"wood_light",true)
	for side: float in [-1,1]:
		_box(self,p+Vector3(side*size.x*0.37,0,size.z/2+0.015),Vector3(0.1,size.y,0.05),"wood",false)
	_box(self,p+Vector3(0,0,size.z/2+0.04),Vector3(size.x,0.12,0.07),"wood",false)

func _sign(pos: Vector3,title: String,sub: String) -> void:
	var y: float=get_height(pos.x,pos.z)
	for off: float in [-1.45,1.45]: _box(self,Vector3(pos.x+off,y+1.35,pos.z),Vector3(0.12,2.7,0.12),"dark",true)
	_box(self,Vector3(pos.x,y+2.4,pos.z),Vector3(3.7,1.25,0.13),"blue_dark",true)
	_box(self,Vector3(pos.x-1.72,y+2.4,pos.z+0.08),Vector3(0.09,1.02,0.04),"orange",false)
	_label(self,Vector3(pos.x,y+2.64,pos.z+0.083),title,0.0095)
	_label(self,Vector3(pos.x,y+2.14,pos.z+0.085),sub,0.0070)

func _label(parent: Node3D,pos: Vector3,text: String,pixel: float) -> void:
	var label:=Label3D.new()
	label.text=text
	# Rasterise at 128 px and shrink pixel_size to match: at 40 px the CJK
	# strokes merge into blobs once the outline is applied.
	label.font_size=128
	label.pixel_size=pixel*40.0/float(label.font_size)
	label.position=pos
	label.modulate=Color("f0e9d6")
	label.outline_size=4
	label.outline_modulate=Color(0.05,0.07,0.08,0.85)
	label.no_depth_test=false
	# The mirrored backface reads as ghost text through thin boards.
	label.double_sided=false
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Segoe UI"])
	label.font=font
	parent.add_child(label)

func _box(parent: Node3D,pos: Vector3,size: Vector3,key: String,solid: bool) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	mi.mesh=mesh
	mi.material_override=mat(key)
	mi.position=pos
	parent.add_child(mi)
	if solid:
		var body:=StaticBody3D.new()
		var cs:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=size
		cs.shape=shape
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _cylinder(parent: Node3D,pos: Vector3,radius: float,height: float,key: String,solid: bool) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=10
	mi.mesh=mesh
	mi.material_override=mat(key)
	mi.position=pos
	parent.add_child(mi)
	if solid:
		var body:=StaticBody3D.new()
		var cs:=CollisionShape3D.new()
		var shape:=CylinderShape3D.new()
		shape.height=height
		shape.radius=radius
		cs.shape=shape
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _beam(parent: Node3D,a: Vector3,b: Vector3,width: float,key: String) -> void:
	var mi: MeshInstance3D=_box(parent,(a+b)/2,Vector3(width,width,a.distance_to(b)),key,false)
	mi.basis = Basis.looking_at(b-a,Vector3.UP if absf((b-a).normalized().dot(Vector3.UP))<0.99 else Vector3.RIGHT)

func _ramp(parent: Node3D,a: Vector3,b: Vector3,width: float,key: String) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [a-Vector3(0,0,width/2),b-Vector3(0,0,width/2),a+Vector3(0,0,width/2),b-Vector3(0,0,width/2),b+Vector3(0,0,width/2),a+Vector3(0,0,width/2)]: st.add_vertex(v)
	st.generate_normals()
	var mesh: ArrayMesh=st.commit()
	var mi:=MeshInstance3D.new()
	mi.mesh=mesh
	mi.material_override=mat(key)
	parent.add_child(mi)
	var body:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	cs.shape=mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)

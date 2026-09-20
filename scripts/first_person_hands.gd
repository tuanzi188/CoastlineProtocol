extends Node3D

var left: Node3D
var right: Node3D
var finger_count: int = 0
var mesh_count: int = 0
var _materials: Dictionary = {}
var _left_rest: Transform3D
var _trigger: Node3D
var _trigger_rest: Vector3
var _magazine: Node3D
var _magazine_rest: Vector3
var _built: bool = false
var render_mesh_count: int = 0

func build(magazine: Node3D) -> void:
	if _built: return
	_built=true
	_magazine=magazine
	_magazine_rest=magazine.position
	_materials["fabric"]=_surface(Color("45514b"),0.97,1.0)
	_materials["leather"]=_surface(Color("88785d"),0.86,0.35)
	_materials["palm"]=_surface(Color("635b4b"),0.94,0.28)
	_materials["rubber"]=_surface(Color("353c38"),0.78,0.12)
	_materials["stitch"]=_surface(Color("5d5647"),0.95,0.0)
	_materials["cuff"]=_surface(Color("3b443e"),0.95,0.7)
	left=Node3D.new()
	left.name="SupportHand"
	add_child(left)
	right=Node3D.new()
	right.name="TriggerHand"
	add_child(right)
	_left_hand()
	_right_hand()
	var finish=preload("res://scripts/weapon_finish.gd")
	finish.merge_children(left,"SupportGlove")
	finish.merge_children(right,"TriggerGlove")
	finish.merge_children(_trigger,"TriggerFingerMesh")
	render_mesh_count=3
	_left_rest=left.transform

func animate(delta: float,reloading: bool,progress: float,kick: float) -> void:
	var offset:=Vector3.ZERO
	var rotation_target:=Vector3.ZERO
	var mag_drop: float=0.0
	if reloading:
		var reach: float=smoothstep(0.02,0.23,progress)*(1.0-smoothstep(0.78,0.98,progress))
		mag_drop=smoothstep(0.27,0.43,progress)*(1.0-smoothstep(0.55,0.74,progress))*0.16
		offset=Vector3(0.053,-0.057-mag_drop,0.23)*reach
		rotation_target=Vector3(-0.14,0.10,0.04)*reach
	left.position=left.position.lerp(offset,1.0-exp(-20.0*delta))
	left.rotation=left.rotation.lerp(rotation_target,1.0-exp(-20.0*delta))
	_magazine.position=_magazine_rest+Vector3(0,-mag_drop,mag_drop*0.1)
	_trigger.position=_trigger_rest+Vector3(0,0,minf(kick,1)*0.004)

func reset_pose() -> void:
	left.transform=_left_rest
	_magazine.position=_magazine_rest
	_trigger.position=_trigger_rest

func _surface(color: Color,roughness: float,weave: float) -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode cull_disabled; uniform vec4 base_color:source_color; uniform float roughness=0.9; uniform float weave=0.5; void fragment(){vec2 footprint=fwidth(UV); float detail=1.0-smoothstep(0.003,0.015,max(footprint.x,footprint.y)); float grain=fract(sin(dot(UV*180.0,vec2(12.9898,78.233)))*43758.5453); float thread=sin(UV.x*420.0)*sin(UV.y*320.0); float panel=pow(abs(sin(UV.x*3.14159)),0.5); float shade=0.95+panel*0.05+detail*((grain-0.5)*0.06+thread*weave*0.024); ALBEDO=base_color.rgb*shade; ROUGHNESS=clamp(roughness+(grain-0.5)*0.04*detail,0.0,1.0);}"
	var m:=ShaderMaterial.new()
	m.shader=shader
	m.set_shader_parameter("base_color",color)
	m.set_shader_parameter("roughness",roughness)
	m.set_shader_parameter("weave",weave)
	return m

func _left_hand() -> void:
	# Forearms extend behind the camera frustum; no rounded stump is exposed.
	_loft(left,[Vector3(-0.43,-0.48,0.31),Vector3(-0.32,-0.34,0.09),Vector3(-0.22,-0.23,-0.15),Vector3(-0.133,-0.145,-0.322),Vector3(-0.113,-0.123,-0.358)],[Vector2(0.095,0.084),Vector2(0.090,0.078),Vector2(0.073,0.065),Vector2(0.048,0.044),Vector2(0.040,0.037)],"fabric",20,4)
	_loft(left,[Vector3(-0.140,-0.150,-0.309),Vector3(-0.130,-0.141,-0.329),Vector3(-0.116,-0.127,-0.352)],[Vector2(0.050,0.046),Vector2(0.049,0.045),Vector2(0.043,0.040)],"cuff",20,2)
	_loft(left,[Vector3(-0.116,-0.122,-0.348),Vector3(-0.099,-0.103,-0.379),Vector3(-0.076,-0.080,-0.421),Vector3(-0.067,-0.072,-0.453),Vector3(-0.067,-0.073,-0.469)],[Vector2(0.030,0.027),Vector2(0.033,0.024),Vector2(0.035,0.023),Vector2(0.029,0.021),Vector2(0.014,0.013)],"leather",20,4)
	_ellipsoid(left,Vector3(-0.061,-0.069,-0.421),Vector3(0.019,0.025,0.054),"palm")
	for i: int in range(4):
		var z: float=-0.475+i*0.025
		var r: float=0.0107 if i<3 else 0.0093
		var points: Array[Vector3]=[Vector3(-0.072,-0.066,z),Vector3(-0.052,-0.081,z-0.001),Vector3(-0.016,-0.083,z-0.002),Vector3(0.026,-0.077,z-0.002),Vector3(0.049,-0.052,z),Vector3(0.052,-0.025,z+0.002)]
		_finger(left,points,r)
		_ellipsoid(left,Vector3(-0.076,-0.072,z),Vector3(0.012,0.013,0.010),"rubber")
		_seam(left,[Vector3(-0.052,-0.091,z-0.006),Vector3(-0.012,-0.094,z-0.006),Vector3(0.020,-0.087,z-0.006)],0.0007)
	_finger(left,[Vector3(-0.095,-0.085,-0.380),Vector3(-0.077,-0.058,-0.378),Vector3(-0.064,-0.032,-0.393),Vector3(-0.054,-0.010,-0.410),Vector3(-0.048,-0.005,-0.428)],0.014)
	_ellipsoid(left,Vector3(-0.100,-0.091,-0.387),Vector3(0.018,0.029,0.026),"leather")
	for i: int in range(3):
		_ellipsoid(left,Vector3(-0.098,-0.084,-0.414-i*0.017),Vector3(0.009,0.018,0.007),"rubber")
	_seam(left,[Vector3(-0.176,-0.167,-0.291),Vector3(-0.256,-0.237,-0.103),Vector3(-0.343,-0.349,0.098)],0.0012,"cuff")
	# Cloth gathers remain flush with the sleeve, not rigid rings.
	for i: int in range(3):
		var t: float=float(i)*0.017
		_seam(left,[Vector3(-0.178-t,-0.128-t,-0.309+t*1.7),Vector3(-0.159-t,-0.104-t,-0.310+t*1.7),Vector3(-0.123-t,-0.100-t,-0.323+t*1.7)],0.0023,"cuff")

func _right_hand() -> void:
	_loft(right,[Vector3(0.36,-0.49,0.47),Vector3(0.245,-0.34,0.31),Vector3(0.125,-0.229,0.153),Vector3(0.076,-0.184,0.090)],[Vector2(0.100,0.084),Vector2(0.081,0.071),Vector2(0.052,0.047),Vector2(0.035,0.032)],"fabric",20,5)
	_loft(right,[Vector3(0.120,-0.225,0.148),Vector3(0.107,-0.212,0.130),Vector3(0.086,-0.191,0.104)],[Vector2(0.053,0.048),Vector2(0.050,0.046),Vector2(0.039,0.036)],"cuff",20,3)
	_loft(right,[Vector3(0.076,-0.179,0.084),Vector3(0.059,-0.155,0.059),Vector3(0.051,-0.117,0.041),Vector3(0.053,-0.085,0.026),Vector3(0.050,-0.076,0.022)],[Vector2(0.025,0.024),Vector2(0.028,0.030),Vector2(0.026,0.035),Vector2(0.023,0.031),Vector2(0.012,0.021)],"leather",20,4)
	for i: int in range(3):
		var y: float=-0.122-i*0.024
		var z: float=0.028+i*0.006
		_finger(right,[Vector3(0.057,y,z),Vector3(0.039,y,-0.011+i*0.005),Vector3(0.007,y,-0.019+i*0.005),Vector3(-0.029,y,-0.009+i*0.007),Vector3(-0.035,y,0.017+i*0.007)],0.0107-i*0.0007)
		_ellipsoid(right,Vector3(0.079,y,0.022+i*0.006),Vector3(0.009,0.009,0.017),"rubber")
	_trigger=Node3D.new()
	_trigger.name="TriggerFinger"
	right.add_child(_trigger)
	_trigger_rest=_trigger.position
	_finger(_trigger,[Vector3(0.056,-0.088,0.021),Vector3(0.048,-0.083,-0.011),Vector3(0.033,-0.090,-0.043),Vector3(0.014,-0.093,-0.055),Vector3(0.006,-0.093,-0.042)],0.010)
	_finger(right,[Vector3(0.050,-0.139,0.069),Vector3(0.031,-0.119,0.065),Vector3(0.005,-0.104,0.058),Vector3(-0.023,-0.098,0.043),Vector3(-0.037,-0.108,0.024)],0.0135)
	_ellipsoid(right,Vector3(0.052,-0.149,0.077),Vector3(0.024,0.030,0.012),"leather")
	_ellipsoid(right,Vector3(0.080,-0.126,0.044),Vector3(0.008,0.031,0.023),"rubber")
	_seam(right,[Vector3(0.153,-0.219,0.130),Vector3(0.254,-0.310,0.273),Vector3(0.377,-0.444,0.445)],0.0013,"cuff")

func _finger(parent: Node3D,points: Array[Vector3],radius: float) -> void:
	finger_count+=1
	var radii: Array[Vector2]=[]
	for i: int in range(points.size()):
		var fraction: float=float(i)/float(points.size()-1)
		var r: float=radius*lerpf(1.1,0.75,fraction)
		radii.append(Vector2(r,r*0.91))
	var end_direction: Vector3=(points[-1]-points[-2]).normalized()
	var path: Array[Vector3]=points.duplicate()
	path.append(points[-1]+end_direction*radius*0.50)
	radii.append(Vector2(radius*0.42,radius*0.4))
	path.append(path[-1]+end_direction*radius*0.22)
	radii.append(Vector2(0.0005,0.0005))
	_loft(parent,path,radii,"leather",12,3)
	for i: int in range(1,points.size()-1):
		if i%2==0:
			_ellipsoid(parent,points[i]+Vector3(0,-radius*0.4,0),Vector3(radius*0.9,radius*0.65,radius*0.65),"palm")

func _seam(parent: Node3D,points: Array[Vector3],radius: float,key: String="stitch") -> void:
	var radii: Array[Vector2]=[]
	for p: Vector3 in points: radii.append(Vector2(radius,radius))
	_loft(parent,points,radii,key,6,3)

func _ellipsoid(parent: Node3D,point: Vector3,radii: Vector3,key: String) -> MeshInstance3D:
	var mesh:=SphereMesh.new()
	mesh.radius=1.0
	mesh.height=2.0
	mesh.radial_segments=16
	mesh.rings=8
	var instance:=MeshInstance3D.new()
	instance.mesh=mesh
	instance.position=point
	instance.scale=radii
	instance.material_override=_materials[key]
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	mesh_count+=1
	return instance

func _loft(parent: Node3D,points: Array[Vector3],radii: Array[Vector2],key: String,sides: int,subdivisions: int) -> void:
	var centers: Array[Vector3]=[]
	var widths: Array[Vector2]=[]
	for i: int in range(points.size()-1):
		for j: int in range(subdivisions):
			var t: float=float(j)/subdivisions
			centers.append(points[i].cubic_interpolate(points[i+1],points[maxi(0,i-1)],points[mini(points.size()-1,i+2)],t))
			widths.append(radii[i].lerp(radii[i+1],t))
	centers.append(points[-1])
	widths.append(radii[-1])
	var vertices: Array[Vector3]=[]
	var normals: Array[Vector3]=[]
	var reference:=Vector3.RIGHT
	for i: int in range(centers.size()):
		var tangent: Vector3=(centers[mini(i+1,centers.size()-1)]-centers[maxi(i-1,0)]).normalized()
		var axis: Vector3=reference-tangent*reference.dot(tangent)
		if axis.length()<0.1: axis=Vector3.UP-tangent*tangent.y
		axis=axis.normalized()
		reference=axis
		var other: Vector3=tangent.cross(axis).normalized()
		for j: int in range(sides+1):
			var theta: float=float(j)/sides*TAU
			vertices.append(centers[i]+axis*cos(theta)*widths[i].x+other*sin(theta)*widths[i].y)
			normals.append((axis*cos(theta)/maxf(widths[i].x,0.0001)+other*sin(theta)/maxf(widths[i].y,0.0001)).normalized())
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(centers.size()-1):
		for j: int in range(sides):
			var a: int=i*(sides+1)+j
			var b: int=a+sides+1
			for index: int in [a,b,a+1,a+1,b,b+1]:
				st.set_normal(normals[index])
				st.set_uv(Vector2(float(index%(sides+1))/sides,float(index/(sides+1))/float(centers.size()-1)))
				st.add_vertex(vertices[index])
	var instance:=MeshInstance3D.new()
	instance.mesh=st.commit()
	instance.material_override=_materials[key]
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	mesh_count+=1

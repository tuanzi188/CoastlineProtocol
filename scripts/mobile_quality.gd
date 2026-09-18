extends RefCounted

static func apply(game: Node3D) -> Dictionary:
	var viewport: Viewport=game.get_viewport()
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.scaling_3d_scale=0.8
	Engine.max_fps=60
	var shadow_count: int=0
	var detail_count: int=0
	for node: Node in game.find_children("*","DirectionalLight3D",true,false):
		var light:=node as DirectionalLight3D
		light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
		light.directional_shadow_max_distance=65
		shadow_count+=1
	for node: Node in game.world.find_children("*","MeshInstance3D",true,false):
		var instance:=node as MeshInstance3D
		if instance.mesh is SphereMesh or instance.mesh is CylinderMesh:
			instance.visibility_range_end=105
			instance.visibility_range_end_margin=12
			detail_count+=1
		if instance.mesh is PlaneMesh and (instance.mesh as PlaneMesh).size.x>1000:
			var mesh:=PlaneMesh.new()
			mesh.size=Vector2(1000,1000)
			mesh.subdivide_width=36
			mesh.subdivide_depth=36
			instance.mesh=mesh
	for node: Node in game.world.find_children("*","MultiMeshInstance3D",true,false):
		var grass:=node as MultiMeshInstance3D
		if grass.multimesh.mesh is PrismMesh:
			grass.multimesh.visible_instance_count=mini(1800,grass.multimesh.instance_count)
			grass.visibility_range_end=55
	for node: Node in game.details.find_children("*","GeometryInstance3D",true,false):
		var detail:=node as GeometryInstance3D
		detail.visibility_range_end=80
		detail.visibility_range_end_margin=8
	return {"scale_3d":0.8,"fps_cap":60,"shadow_lights":shadow_count,"distance_limited_details":detail_count}

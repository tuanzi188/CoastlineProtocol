extends RefCounted

## Rendering tiers, applied by main.gd for the active platform. A key a tier
## omits is left exactly as the world authored it, so a tier can take a subset of
## the cuts instead of inheriting the whole mobile profile.
##
## Range culling only pays off for instances with a small AABB that actually
## leaves range. The grass MultiMesh spans the whole island so a range on it
## never trips, which is why mobile's saving comes from visible_instance_count
## and why this file sets no ranges for desktop at all.
const TIERS: Dictionary = {
	"mobile": {
		"msaa": false,
		"scale": 0.8,
		"fps_cap": 60,
		"shadow_orthogonal": 65.0,
		"prop_range": 105.0,
		"ocean_subdivide": 36,
		"grass_instances": 1800,
		"detail_range": 80.0,
	},
	# Measured, not assumed: giving ~600 small props a visibility_range_end cost
	# 19 fps on average in --combat-tour, because a range controller is created per
	# instance whether or not anything is ever far enough to cull, and gameplay
	# framings keep the whole island in range. Only the menu (viewed from outside
	# the island) benefited. This tier stays empty until something cheaper to
	# filter is added; do not re-introduce per-prop distance culling here.
	"desktop": {},
}


static func apply(game: Node3D, tier: String = "mobile") -> Dictionary:
	var spec: Dictionary = TIERS[tier]
	var viewport: Viewport=game.get_viewport()
	if spec.is_empty():
		# Do not even walk the scene looking for work this tier declines to do.
		return {"tier":tier,"scale_3d":viewport.scaling_3d_scale,"fps_cap":Engine.max_fps,"shadow_lights":0,"distance_limited_details":0}
	if spec.has("msaa"):
		viewport.msaa_3d=Viewport.MSAA_DISABLED
	if spec.has("scale"):
		viewport.scaling_3d_scale=float(spec["scale"])
	if spec.has("fps_cap"):
		Engine.max_fps=int(spec["fps_cap"])
	var shadow_count: int=0
	var detail_count: int=0
	if spec.has("shadow_orthogonal"):
		var shadow_distance: float=float(spec["shadow_orthogonal"])
		for node: Node in game.find_children("*","DirectionalLight3D",true,false):
			var light:=node as DirectionalLight3D
			light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
			light.directional_shadow_max_distance=shadow_distance
			shadow_count+=1
	for node: Node in game.world.find_children("*","MeshInstance3D",true,false):
		var instance:=node as MeshInstance3D
		if spec.has("prop_range") and (instance.mesh is SphereMesh or instance.mesh is CylinderMesh):
			instance.visibility_range_end=float(spec["prop_range"])
			instance.visibility_range_end_margin=12
			detail_count+=1
		if spec.has("ocean_subdivide") and instance.mesh is PlaneMesh and (instance.mesh as PlaneMesh).size.x>1000:
			var mesh:=PlaneMesh.new()
			mesh.size=Vector2(1000,1000)
			mesh.subdivide_width=int(spec["ocean_subdivide"])
			mesh.subdivide_depth=int(spec["ocean_subdivide"])
			instance.mesh=mesh
	if spec.has("grass_instances"):
		for node: Node in game.world.find_children("*","MultiMeshInstance3D",true,false):
			var grass:=node as MultiMeshInstance3D
			if grass.multimesh.mesh is PrismMesh:
				grass.multimesh.visible_instance_count=mini(int(spec["grass_instances"]),grass.multimesh.instance_count)
	if spec.has("detail_range"):
		for node: Node in game.details.find_children("*","GeometryInstance3D",true,false):
			var detail:=node as GeometryInstance3D
			detail.visibility_range_end=float(spec["detail_range"])
			detail.visibility_range_end_margin=8
	return {"tier":tier,"scale_3d":viewport.scaling_3d_scale,"fps_cap":Engine.max_fps,"shadow_lights":shadow_count,"distance_limited_details":detail_count}


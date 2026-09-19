extends Node

const STEP: float = 2.0
## Chunk sizes are expressed in grid cells, not rows, so one frame of the build
## never issues more than a couple hundred physics queries even on a wide row.
const BUILD_CHUNK: int = 48
const LINK_CHUNK: int = 24
## Ring search radius, in cells, that replaces AStar3D's full-graph linear scan.
const SEARCH_RADIUS: int = 3
var graph: AStar3D = AStar3D.new()
var cells: Dictionary = {}
var world: Node3D
var ids: PackedInt64Array = PackedInt64Array()
var ready_for_paths: bool = false
var _query: PhysicsShapeQueryParameters3D

func build(island: Node3D,exclude: Array[RID]) -> void:
	world=island
	graph.clear()
	cells.clear()
	ids.clear()
	var shape:=CapsuleShape3D.new()
	shape.radius=0.34
	shape.height=1.48
	_query=PhysicsShapeQueryParameters3D.new()
	_query.shape=shape
	_query.exclude=exclude
	_query.collision_mask=1
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var next_id: int=0
	var scanned: int=0
	for z: int in range(-110,66,2):
		for x: int in range(-106,100,2):
			scanned+=1
			if scanned%BUILD_CHUNK==0: await get_tree().process_frame
			var y: float=world.get_height(x,z)
			if y<1.2: continue
			var floor_query:=PhysicsRayQueryParameters3D.create(Vector3(x,y+0.65,z),Vector3(x,y-1.0,z),1,exclude)
			var floor_hit: Dictionary=space.intersect_ray(floor_query)
			if floor_hit.is_empty() or (floor_hit.normal as Vector3).y<0.70: continue
			y=(floor_hit.position as Vector3).y
			var p:=Vector3(x,y+0.04,z)
			if not _clear(p,space): continue
			graph.add_point(next_id,p)
			cells[Vector2i(x,z)]=next_id
			ids.append(next_id)
			next_id+=1
	var connections: int=0
	for cell: Vector2i in cells:
		connections+=1
		if connections%LINK_CHUNK==0: await get_tree().process_frame
		var id: int=cells[cell]
		var a: Vector3=graph.get_point_position(id)
		for direction: Vector2i in [Vector2i(2,0),Vector2i(0,2),Vector2i(2,2),Vector2i(-2,2)]:
			var other: Vector2i=cell+direction
			if not cells.has(other): continue
			if direction.x!=0 and direction.y!=0 and (not cells.has(cell+Vector2i(direction.x,0)) or not cells.has(cell+Vector2i(0,direction.y))): continue
			var b: Vector3=graph.get_point_position(cells[other])
			if absf(a.y-b.y)>1.4: continue
			if not _clear((a+b)*0.5,space): continue
			var ray:=PhysicsRayQueryParameters3D.create(a+Vector3.UP*0.9,b+Vector3.UP*0.9,1,exclude)
			if not space.intersect_ray(ray).is_empty(): continue
			graph.connect_points(id,cells[other],true)
	ready_for_paths=ids.size()>0
	print("COMBAT_NAV_READY nodes=%d" % ids.size())

func _clear(p: Vector3,space: PhysicsDirectSpaceState3D) -> bool:
	_query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*1.0)
	return space.intersect_shape(_query,1).is_empty()

func path(from: Vector3,to: Vector3) -> PackedVector3Array:
	if not ready_for_paths: return PackedVector3Array()
	var a: int=_closest_id(from)
	var b: int=_closest_id(to)
	if a<0 or b<0: return PackedVector3Array()
	return graph.get_point_path(a,b,true)

func nearest(point: Vector3) -> Vector3:
	if not ready_for_paths: return point
	return graph.get_point_position(_closest_id(point))


## AStar3D.get_closest_point() scans every node in the graph, which at this size
## costs thousands of distance checks per call. Cell keys already are the world
## coordinates quantised to STEP, so a fixed (2R+1)^2 window replaces the scan.
## The window keeps the true nearest rather than the first hit, so a path may
## start from the same node the linear scan would have chosen.
func _closest_id(p: Vector3) -> int:
	var step: int = int(STEP)
	var reach: int = SEARCH_RADIUS*step
	var base := Vector2i(roundi(p.x/STEP)*step,roundi(p.z/STEP)*step)
	var best: int = -1
	var best_distance: float = INF
	for dx: int in range(base.x-reach,base.x+reach+1,step):
		for dz: int in range(base.y-reach,base.y+reach+1,step):
			var found: Variant = cells.get(Vector2i(dx,dz))
			if found == null: continue
			var offset: Vector3 = graph.get_point_position(int(found)) - p
			var distance: float = offset.length_squared()
			if distance < best_distance:
				best_distance = distance
				best = int(found)
	return best if best >= 0 else graph.get_closest_point(p)

func random_point(rng: RandomNumberGenerator) -> Vector3:
	if ids.is_empty(): return Vector3.ZERO
	return graph.get_point_position(ids[rng.randi_range(0,ids.size()-1)])

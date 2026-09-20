extends RefCounted
## Boot-time geometry only; the finished meshes and their materials are shared.
static var _finished: Dictionary[StringName, ArrayMesh] = {}


static func beveled_box(size: Vector3, chamfer: float = 0.004, taper: float = 1.0, rake: float = 0.0) -> ArrayMesh:
	var half: Vector3 = size * 0.5
	var cut: float = minf(chamfer, minf(half.x, minf(half.y, half.z)) * 0.45)
	var inner: Vector3 = half - Vector3.ONE * cut
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six broad faces, twelve narrow edge facets, eight corner facets.
	for axis: int in range(3):
		var u: int = (axis + 1) % 3
		var v: int = (axis + 2) % 3
		for sign_axis: float in [-1.0, 1.0]:
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = sign_axis
			var points: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point: Vector3 = Vector3.ZERO
				point[axis] = sign_axis * half[axis]
				point[u] = corner.x * inner[u]
				point[v] = corner.y * inner[v]
				points.append(point)
			_polygon(tool, points, normal, size, taper, rake)
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for end: float in [-1.0, 1.0]:
					var a: Vector3 = Vector3.ZERO
					a[axis] = end * inner[axis]
					a[u] = su * half[u]
					a[v] = sv * inner[v]
					var b: Vector3 = a
					b[u] = su * inner[u]
					b[v] = sv * half[v]
					if end < 0.0:
						points.append(a)
						points.append(b)
					else:
						points.append(b)
						points.append(a)
				var normal: Vector3 = Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				_polygon(tool, points, normal.normalized(), size, taper, rake)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var signs: Vector3 = Vector3(sx, sy, sz)
				var points: Array[Vector3] = []
				for axis: int in range(3):
					var point: Vector3 = inner * signs
					point[axis] = half[axis] * signs[axis]
					points.append(point)
				_polygon(tool, points, signs.normalized(), size, taper, rake)
	tool.index()
	return tool.commit()


static func _polygon(tool: SurfaceTool, points: Array[Vector3], outward: Vector3, size: Vector3, taper: float, rake: float) -> void:
	# Godot front faces wind clockwise. Recompute flat normals after tapering.
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0.0:
		points.reverse()
	for index: int in range(points.size()):
		var depth: float = clampf(0.5 - points[index].y / size.y, 0.0, 1.0)
		points[index].x *= lerpf(1.0, taper, depth)
		points[index].z = points[index].z * lerpf(1.0, taper, depth) + rake * depth
	for index: int in range(1, points.size() - 1):
		var normal: Vector3 = -(points[index] - points[0]).cross(points[index + 1] - points[0]).normalized()
		var u: Vector3 = normal.cross(Vector3.UP).normalized() if absf(normal.y) < 0.9 else Vector3.RIGHT
		var v: Vector3 = normal.cross(u)
		for point: Vector3 in [points[0], points[index], points[index + 1]]:
			tool.set_normal(normal)
			tool.set_uv(Vector2(point.dot(u), point.dot(v)) * 8.0)
			tool.add_vertex(point)


static func crown() -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(16):
		var a: float = TAU * float(index) / 16.0
		var b: float = TAU * float(index + 1) / 16.0
		var outer_a: Vector3 = Vector3(cos(a) * 0.028, sin(a) * 0.028, 0.0055)
		var outer_b: Vector3 = Vector3(cos(b) * 0.028, sin(b) * 0.028, 0.0055)
		var inner_a: Vector3 = Vector3(cos(a) * 0.011, sin(a) * 0.011, -0.001)
		var inner_b: Vector3 = Vector3(cos(b) * 0.011, sin(b) * 0.011, -0.001)
		_polygon(tool, [outer_a, outer_b, inner_b, inner_a], Vector3.FORWARD, Vector3.ONE, 1.0, 0.0)
		_polygon(tool, [inner_a, inner_b, inner_b + Vector3(0, 0, 0.012), inner_a + Vector3(0, 0, 0.012)], -Vector3(cos(a + PI / 16.0), sin(a + PI / 16.0), 0), Vector3.ONE, 1.0, 0.0)
	tool.index()
	return tool.commit()


static func merge_children(parent: Node3D, name: String) -> MeshInstance3D:
	var label: StringName = StringName(name)
	var parts: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			parts.append(child as MeshInstance3D)
	var merged: ArrayMesh = _finished.get(label) as ArrayMesh
	if merged == null:
		merged = ArrayMesh.new()
		var groups: Dictionary[Material, SurfaceTool] = {}
		for part: MeshInstance3D in parts:
			var normal_basis: Basis = part.transform.basis.inverse().transposed()
			for surface: int in range(part.mesh.get_surface_count()):
				var material: Material = part.get_active_material(surface)
				if not groups.has(material):
					var group: SurfaceTool = SurfaceTool.new()
					group.begin(Mesh.PRIMITIVE_TRIANGLES)
					group.set_material(material)
					groups[material] = group
				var tool: SurfaceTool = groups[material]
				var arrays: Array = part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count: int = indices.size() if not indices.is_empty() else vertices.size()
				for offset: int in range(count):
					var source: int = offset
					if part.transform.basis.determinant() < 0.0:
						source = offset - offset % 3 + (2 - offset % 3)
					var vertex: int = indices[source] if not indices.is_empty() else source
					tool.set_normal((normal_basis * normals[vertex]).normalized())
					tool.set_uv(uv[vertex] if not uv.is_empty() else Vector2.ZERO)
					tool.add_vertex(part.transform * vertices[vertex])
		for material: Material in groups:
			var tool: SurfaceTool = groups[material]
			tool.index()
			tool.commit(merged)
		_finished[label] = merged
	for part: MeshInstance3D in parts:
		parent.remove_child(part)
		part.free()
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	instance.mesh = merged
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

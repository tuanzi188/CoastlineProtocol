extends RefCounted
## Form builder for procedurally modelled characters. Every primitive added to
## one instance is merged into a single multi-surface ArrayMesh, so a body
## segment costs one scene node no matter how much anatomical detail it carries.
##
## Surface materials are deliberately left unset: the caller caches the
## committed mesh and binds per-character colours at runtime with
## GeometryInstance3D.set_surface_material_override(), which lets all soldiers
## share one copy of the geometry.

var _tools: Dictionary = {}
var _order: Array = []
var _vertices: Dictionary = {}


## Material keys in surface order, skipping anything that produced no geometry.
func surface_keys() -> Array:
	return _order.filter(func(key: String) -> bool: return int(_vertices[key]) > 0)


func vertex_count() -> int:
	var total: int = 0
	for key: String in _order:
		total += int(_vertices[key])
	return total


func commit() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	for key: String in _order:
		var tool: SurfaceTool = _tools[key] as SurfaceTool
		_tools[key] = null
		if int(_vertices[key]) > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
	return mesh


func add_box(size: Vector3, at: Vector3, key: String, rotation: Vector3 = Vector3.ZERO) -> void:
	var geometry: BoxMesh = BoxMesh.new()
	geometry.size = size
	add_primitive(geometry, Transform3D(Basis.from_euler(rotation), at), key)


func add_ellipsoid(radii: Vector3, at: Vector3, key: String, rotation: Vector3 = Vector3.ZERO) -> void:
	var geometry: SphereMesh = SphereMesh.new()
	geometry.radius = 1.0
	geometry.height = 2.0
	geometry.radial_segments = 20
	geometry.rings = 12
	add_primitive(geometry, Transform3D(Basis.from_euler(rotation).scaled(radii), at), key)


## Capsule stretched between two joints, used for gear and weapon hard parts.
func add_strut(start: Vector3, end: Vector3, radius: float, key: String) -> void:
	if start.distance_to(end) < 0.0005:
		return
	var geometry: CapsuleMesh = CapsuleMesh.new()
	geometry.radius = radius
	geometry.height = start.distance_to(end) + radius * 2.0
	geometry.radial_segments = 16
	geometry.rings = 6
	var orientation: Basis = Basis(Quaternion(Vector3.UP, (end - start).normalized()))
	add_primitive(geometry, Transform3D(orientation, (start + end) * 0.5), key)


func add_primitive(source: PrimitiveMesh, at: Transform3D, key: String) -> void:
	var arrays: Array = source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var paired_uv: bool = uvs.size() == vertices.size()
	# Normals ride the basis instead of its inverse-transpose, which is only
	# inaccurate past roughly 2:1 axis ratios; ellipsoids stay inside that.
	var sequence: PackedInt32Array = indices if indices.size() > 0 else _identity_range(vertices.size())
	for source_index: int in sequence:
		_vertex(key, at * vertices[source_index], (at.basis * normals[source_index]).normalized(), uvs[source_index] if paired_uv else Vector2.ZERO)


## Sweeps an elliptical section along a spline. `sections[i]` is
## (half width, half depth) measured on a frame carried along the path, which
## is what lets a limb be flatter front-to-back than side-to-side.
func add_loft(points: Array, sections: Array, key: String, sides: int = 14, subdivisions: int = 5, frame0: Vector3 = Vector3.RIGHT) -> void:
	var centers: Array = []
	var widths: Array = []
	for index: int in range(points.size() - 1):
		for step: int in range(subdivisions):
			var t: float = float(step) / float(subdivisions)
			centers.append(points[index].cubic_interpolate(points[index + 1], points[maxi(0, index - 1)], points[mini(points.size() - 1, index + 2)], t))
			widths.append((sections[index] as Vector2).lerp(sections[index + 1], t))
	centers.append(points[-1])
	widths.append(sections[-1])
	var rings: Array = []
	var reference: Vector3 = frame0
	for index: int in range(centers.size()):
		var tangent: Vector3 = (centers[mini(index + 1, centers.size() - 1)] - centers[maxi(index - 1, 0)]).normalized()
		var axis: Vector3 = reference - tangent * reference.dot(tangent)
		if axis.length_squared() < 0.01:
			axis = Vector3.UP - tangent * tangent.y
		axis = axis.normalized()
		reference = axis
		var other: Vector3 = tangent.cross(axis).normalized()
		var ring: PackedVector3Array = PackedVector3Array()
		var normals: PackedVector3Array = PackedVector3Array()
		for side: int in range(sides + 1):
			var theta: float = float(side) / float(sides) * TAU
			var cosine: float = cos(theta)
			var sine: float = sin(theta)
			var half: Vector2 = widths[index]
			ring.append(centers[index] + axis * cosine * half.x + other * sine * half.y)
			normals.append((axis * cosine / maxf(half.x, 0.0001) + other * sine / maxf(half.y, 0.0001)).normalized())
		rings.append([ring, normals])
	for index: int in range(rings.size() - 1):
		var near: Array = rings[index]
		var far: Array = rings[index + 1]
		var v0: float = float(index) / float(rings.size() - 1)
		var v1: float = float(index + 1) / float(rings.size() - 1)
		for side: int in range(sides):
			var u0: float = float(side) / float(sides)
			var u1: float = float(side + 1) / float(sides)
			_quad(key,
				near[0][side], near[1][side], Vector2(u0, v0),
				near[0][side + 1], near[1][side + 1], Vector2(u1, v0),
				far[0][side + 1], far[1][side + 1], Vector2(u1, v1),
				far[0][side], far[1][side], Vector2(u0, v1))
	_cap(key, centers[0], rings[0], -1)
	_cap(key, centers[-1], rings[-1], 1)


## Revolves a (radius, height) profile about local Y, squashed into an ellipse.
func add_revolve(profile: Array, key: String, squash: Vector2 = Vector2.ONE, at: Vector3 = Vector3.ZERO, steps: int = 20) -> void:
	var rings: Array = []
	for index: int in range(profile.size()):
		var before: Vector2 = profile[maxi(0, index - 1)]
		var point: Vector2 = profile[index]
		var after: Vector2 = profile[mini(profile.size() - 1, index + 1)]
		var run: float = after.y - before.y
		var rise: float = after.x - before.x
		var outward: Vector2 = Vector2(run, -rise)
		if outward.length_squared() < 0.000001:
			outward = Vector2(1.0, 0.0)
		outward = outward.normalized()
		var ring: PackedVector3Array = PackedVector3Array()
		var normals: PackedVector3Array = PackedVector3Array()
		for step: int in range(steps + 1):
			var theta: float = float(step) / float(steps) * TAU
			var cosine: float = cos(theta)
			var sine: float = sin(theta)
			ring.append(Vector3(cosine * point.x * squash.x, point.y, sine * point.x * squash.y) + at)
			normals.append(Vector3(cosine * outward.x * squash.x, outward.y, sine * outward.x * squash.y).normalized())
		rings.append([ring, normals])
	for index: int in range(rings.size() - 1):
		var near: Array = rings[index]
		var far: Array = rings[index + 1]
		for step: int in range(steps):
			_quad(key,
				near[0][step], near[1][step], Vector2.ZERO,
				near[0][step + 1], near[1][step + 1], Vector2.ZERO,
				far[0][step + 1], far[1][step + 1], Vector2.ZERO,
				far[0][step], far[1][step], Vector2.ZERO)
	if profile[0].x > 0.001:
		_cap(key, Vector3(0, profile[0].y, 0) + at, rings[0], -1)
	if profile[-1].x > 0.001:
		_cap(key, Vector3(0, profile[-1].y, 0) + at, rings[-1], 1)


func _cap(key: String, center: Vector3, ring: Array, direction: int) -> void:
	var points: PackedVector3Array = ring[0]
	var normal: Vector3 = Vector3.UP * float(direction)
	for side: int in range(points.size() - 1):
		_vertex(key, center, normal, Vector2.ZERO)
		_vertex(key, points[side + 1], normal, Vector2.ZERO)
		_vertex(key, points[side], normal, Vector2.ZERO)


func _quad(key: String, a: Vector3, na: Vector3, ua: Vector2, b: Vector3, nb: Vector3, ub: Vector2, c: Vector3, nc: Vector3, uc: Vector2, d: Vector3, nd: Vector3, ud: Vector2) -> void:
	_vertex(key, a, na, ua)
	_vertex(key, b, nb, ub)
	_vertex(key, c, nc, uc)
	_vertex(key, a, na, ua)
	_vertex(key, c, nc, uc)
	_vertex(key, d, nd, ud)


func _vertex(key: String, point: Vector3, normal: Vector3, uv: Vector2) -> void:
	var tool: SurfaceTool = _tool(key)
	tool.set_normal(normal)
	tool.set_uv(uv)
	tool.add_vertex(point)
	_vertices[key] = int(_vertices[key]) + 1


func _tool(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = tool
		_order.append(key)
		_vertices[key] = 0
	return _tools[key]


func _identity_range(count: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(count)
	for index: int in range(count):
		result[index] = index
	return result

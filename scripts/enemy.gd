extends CharacterBody3D

signal eliminated(bot: Node3D, killer: Node)

const SoldierModel = preload("res://scripts/soldier_rig.gd")
const SEPARATION_RANGE: float = 1.6
const STEP_EASE_MAX: float = 0.34
var game: Node3D
var bot_id: int = 0
var health: int = 100
var dead: bool = false
var active: bool = false
var last_headshot: bool = false
var state: String = "巡逻"
var ammo: int = 24
var shots_fired: int = 0
var damage_dealt: int = 0
var target: Node3D
var model: Node3D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _capsule: CollisionShape3D
var _flash: MeshInstance3D
var _tracer: MeshInstance3D
var _muzzle: Marker3D
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _path_left: float = 0.0
var _goal: Vector3
var _has_goal: bool = false
var _last_seen: Vector3
var _memory_left: float = 0.0
var _scan_left: float = 0.0
var _reaction_left: float = 0.0
var _shot_left: float = 0.0
var _burst_left: int = 0
var _reload_left: float = 0.0
var _strafe_left: float = 0.0
var _strafe_sign: float = 1.0
var _effect_left: float = 0.0
var _visible_target: bool = false
# The collider must clear a step instantly, so the visual body carries the
# opposite offset and eases home; teleporting the root makes the soldier hop.
var _step_ease: float = 0.0
var _land_dip: float = 0.0
var _approach_velocity_y: float = 0.0
var _grounded: bool = false
# Measured travel per frame, so the walk cycle stays honest when a wall eats the
# intended velocity or separation pushes the bot further than it asked to move.
var _travel_speed: float = 0.0
var _separation: Vector3 = Vector3.ZERO
# Perception issues up to ten rays per scan for every bot; one reusable query
# object and exclude list keeps that from allocating on each cast.
var _ray_query: PhysicsRayQueryParameters3D
var _self_rid: Array[RID] = []


func _ready() -> void:
	_rng.randomize()
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.025
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.95
	_capsule = CollisionShape3D.new()
	_capsule.name = "SoldierCapsule"
	_capsule.shape = shape
	_capsule.position.y = 0.975
	add_child(_capsule)
	model = SoldierModel.new()
	model.name = "Soldier"
	model.call("build", bot_id)
	add_child(model)
	_muzzle = model.get("muzzle") as Marker3D
	_build_effects()
	_scan_left = _rng.randf_range(0.0, 0.2)
	_strafe_sign = -1.0 if bot_id % 2 == 0 else 1.0
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = 1
	_ray_query.hit_from_inside = true
	_self_rid = [get_rid()]
	_ray_query.exclude = _self_rid


func _physics_process(delta: float) -> void:
	_effect_left = maxf(0.0, _effect_left - delta)
	_step_ease = lerpf(_step_ease, 0.0, 1.0 - exp(-17.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-9.0 * delta))
	model.position.y = -_step_ease
	var running: bool = active and not dead and is_instance_valid(game) and bool(game.get("running"))
	_flash.visible = running and _effect_left > 0.0
	_tracer.visible = _flash.visible
	if dead:
		velocity = Vector3.ZERO
		_travel_speed = 0.0
		model.call("animate", 0.0, false, false, true, delta, 0.0)
		return
	if not running:
		velocity = Vector3.ZERO
		_travel_speed = 0.0
		model.call("animate", 0.0, false, false, false, delta, 0.0)
		return
	_scan_left -= delta
	_path_left -= delta
	_reaction_left = maxf(0.0, _reaction_left - delta)
	_shot_left = maxf(0.0, _shot_left - delta)
	_strafe_left -= delta
	_memory_left = maxf(0.0, _memory_left - delta)
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left == 0.0:
			ammo = 24
	if not _is_combatant(target):
		target = null
		_visible_target = false
	if _scan_left <= 0.0:
		_scan_left = 0.18
		_scan()
	if ammo <= 0 and _reload_left <= 0.0:
		_reload_left = 2.0
		_burst_left = 0
		_strafe_left = 0.0
	var center: Vector3 = game.get("zone_center") as Vector3
	var radius: float = float(game.get("zone_radius"))
	var offset: Vector3 = global_position - center
	offset.y = 0.0
	var escaping: bool = offset.length() > maxf(1.0, radius - 5.0)
	var speed: float = 2.5
	if escaping:
		state = "进圈"
		_set_goal(_ground(center + offset.normalized() * maxf(0.0, radius * 0.60)))
		speed = 4.3
	elif _visible_target and is_instance_valid(target):
		state = "换弹" if _reload_left > 0.0 else "交战"
		speed = 4.3 if _reload_left > 0.0 or health < 35 else 2.5
		if _strafe_left <= 0.0:
			_strafe_left = 2.0
			_strafe_sign *= -1.0
			var toward: Vector3 = _last_seen - global_position
			toward.y = 0.0
			var distance: float = toward.length()
			toward = toward.normalized()
			var sideways: Vector3 = Vector3(-toward.z, 0, toward.x) * _strafe_sign
			var advance: float = clampf(distance - 19.0, -3.0, 7.0)
			if health < 35 or _reload_left > 0.0:
				advance = -7.0
			_set_goal(_ground(global_position + toward * advance + sideways * _rng.randf_range(3.0, 6.0)))
	elif _memory_left > 0.0:
		state = "换弹" if _reload_left > 0.0 else "搜索"
		_set_goal(_last_seen)
		speed = 4.3
		if _flat_distance(global_position, _last_seen) < 1.2:
			_has_goal = false
			rotation.y += delta * 0.8
	else:
		target = null
		state = "换弹" if _reload_left > 0.0 else "巡逻"
		if not _has_goal or _flat_distance(global_position, _goal) < 1.2:
			var nav: Object = game.get("nav") as Object
			var point: Vector3 = nav.call("random_point", _rng) as Vector3
			var radial: Vector3 = point - center
			radial.y = 0.0
			if radial.length() > radius * 0.8:
				point = _ground(center + radial.normalized() * radius * 0.65)
			_set_goal(point)
	_move(delta, speed)
	if _visible_target and is_instance_valid(target):
		var aim: Vector3 = _last_seen - global_position
		aim.y = 0.0
		if aim.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-aim.x, -aim.z), 1.0 - exp(-7.0 * delta))
		if _reload_left <= 0.0 and _reaction_left <= 0.0 and _shot_left <= 0.0 and (-global_basis.z).dot(aim.normalized()) > 0.90:
			_fire()
	model.call("animate", _travel_speed, _visible_target, _reload_left > 0.0, false, delta, _land_dip)


func _is_combatant(node: Node3D) -> bool:
	if not is_instance_valid(node) or node == self or node.is_queued_for_deletion():
		return false
	return not bool(node.get("dead")) and bool(node.get("active")) and float(node.get("health")) > 0.0


func _scan() -> void:
	var candidates: Array[Node3D] = []
	var player: Node3D = game.get("player") as Node3D
	if is_instance_valid(player):
		candidates.append(player)
	var bots: Array = game.get("bots") as Array
	for entry: Variant in bots:
		var bot: Node3D = entry as Node3D
		if is_instance_valid(bot):
			candidates.append(bot)
	var nearest: Node3D = null
	var nearest_distance: float = 55.0
	for candidate: Node3D in candidates:
		if not _is_combatant(candidate):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		var distance: float = offset.length()
		if distance > nearest_distance:
			continue
		offset.y = 0.0
		if distance > 12.0 and (-global_basis.z).dot(offset.normalized()) < 0.5:
			continue
		if not _can_see(candidate):
			continue
		nearest = candidate
		nearest_distance = distance
	var previous: Node3D = target
	var was_visible: bool = _visible_target
	_visible_target = nearest != null
	if nearest != null:
		target = nearest
		_last_seen = nearest.global_position
		_memory_left = 6.0
		if previous != nearest or not was_visible:
			_reaction_left = _rng.randf_range(0.6, 1.1)
			_burst_left = 0
			_strafe_left = 0.0
	elif _memory_left <= 0.0:
		target = null


func _can_see(candidate: Node3D) -> bool:
	var result: Dictionary = _ray(global_position + Vector3.UP * 1.72, candidate.global_position + Vector3.UP * 1.25)
	return not result.is_empty() and result.get("collider") == candidate


func _ray(start: Vector3, end: Vector3) -> Dictionary:
	_ray_query.from = start
	_ray_query.to = end
	return get_world_3d().direct_space_state.intersect_ray(_ray_query)


func hear_shot(source: Vector3, shooter: Node3D) -> void:
	if dead or not active or shooter == self or not is_instance_valid(game) or not bool(game.get("running")):
		return
	if global_position.distance_to(source) > 45.0 or _visible_target:
		return
	# Store only the sound location; do not acquire or track the unseen shooter.
	_last_seen = _ground(source)
	_memory_left = 6.0
	state = "搜索"
	_set_goal(_last_seen)


func _set_goal(point: Vector3) -> void:
	_goal = point
	_has_goal = true


func _ground(point: Vector3) -> Vector3:
	var world: Object = game.get("world") as Object
	return Vector3(point.x, float(world.call("get_height", point.x, point.z)) + 0.05, point.z)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _move(delta: float, speed: float) -> void:
	var direction: Vector3 = Vector3.ZERO
	if _has_goal:
		if _path_left <= 0.0:
			_path_left = 0.8
			var nav: Object = game.get("nav") as Object
			_path = nav.call("path", global_position, _goal) as PackedVector3Array
			_path_index = 1 if _path.size()>1 and _flat_distance(global_position,_path[0])<1.5 else 0
		while _path_index < _path.size() and _flat_distance(global_position, _path[_path_index]) < 0.65:
			_path_index += 1
		if _path_index < _path.size():
			direction = _path[_path_index] - global_position
			direction.y = 0.0
			direction = direction.normalized()
		else:
			_has_goal = false
	var push: Vector3 = Vector3.ZERO
	var bots: Array = game.get("bots") as Array
	for entry: Variant in bots:
		var other: Node3D = entry as Node3D
		if not is_instance_valid(other) or other == self or bool(other.get("dead")):
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var distance: float = away.length()
		if distance > 0.01 and distance < SEPARATION_RANGE:
			# A smooth ramp replaces the old hard cutoff. Two bots parked at that
			# threshold used to switch the force on and off and twitch together.
			push += away / distance * smoothstep(SEPARATION_RANGE, 0.45, distance)
	_separation = _separation.lerp(push, 1.0 - exp(-8.0 * delta))
	direction = (direction + _separation * 1.4).limit_length(1.0)
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 12.0)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = maxf(-40.0, velocity.y - 19.0 * delta)
	# Sampled before move_and_slide resets it, so a landing still has an impact
	# velocity to react to.
	_approach_velocity_y = velocity.y
	_try_step(delta)
	var before: Vector3 = global_position
	move_and_slide()
	_travel_speed = Vector2(global_position.x - before.x,global_position.z - before.z).length() / maxf(delta,0.0001)
	var landed: bool = is_on_floor()
	if landed and not _grounded and _approach_velocity_y < -5.0:
		_land_dip = clampf((-_approach_velocity_y - 5.0) / 12.0, 0.0, 1.0) * 0.11
	_grounded = landed
	if not _visible_target and direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-5.0 * delta))


func _try_step(delta: float) -> void:
	if not is_on_floor(): return
	var motion:=Vector3(velocity.x,0,velocity.z)*delta
	if motion.length()<0.005 or not test_move(global_transform,motion): return
	var raised: Transform3D=global_transform
	raised.origin.y+=0.30
	var ahead: Vector3=motion.normalized()*(motion.length()+0.36)
	if test_move(global_transform,Vector3.UP*0.30) or test_move(raised,ahead): return
	raised.origin+=ahead
	var hit:=KinematicCollision3D.new()
	if test_move(raised,Vector3.DOWN*0.34,hit) and hit.get_normal().y>0.72:
		var rise: float=0.30+hit.get_travel().y
		if rise>0.025:
			var lift: float=rise+0.015
			global_position.y+=lift
			# The collider has to be on top of the step this frame, so the visible
			# body takes the opposite offset and climbs back into place instead of
			# popping up by the full height.
			_step_ease=minf(_step_ease+lift,STEP_EASE_MAX)


func _fire() -> void:
	if dead or not active or not bool(game.get("running")) or ammo <= 0 or not _is_combatant(target):
		return
	# Recheck LOS at the instant of firing, not only on the perception tick.
	if not _can_see(target):
		_visible_target = false
		return
	if _burst_left <= 0:
		_burst_left = _rng.randi_range(2, 4)
	ammo -= 1
	shots_fired += 1
	_burst_left -= 1
	_shot_left = 0.22 if _burst_left > 0 else _rng.randf_range(0.8, 1.2)
	var start: Vector3 = _muzzle.global_position
	var chest: Vector3 = target.global_position + Vector3.UP * 1.25
	var distance: float = start.distance_to(chest)
	var spread: float = 0.012 + distance * 0.00065
	var direction: Vector3 = (chest - start).normalized()
	direction = (direction + global_basis.x * _rng.randf_range(-spread, spread) + Vector3.UP * _rng.randf_range(-spread, spread)).normalized()
	var end: Vector3 = start + direction * 80.0
	# A protruding barrel must not bypass a wall between the body and muzzle.
	var hit: Dictionary = _ray(global_position + Vector3.UP * 1.42, start)
	if hit.is_empty():
		hit = _ray(start, end)
	if not hit.is_empty():
		end = hit["position"] as Vector3
		var collider: Node3D = hit["collider"] as Node3D
		var player: Node3D = game.get("player") as Node3D
		var bots: Array = game.get("bots") as Array
		if is_instance_valid(collider) and (collider == player or bots.has(collider)) and _is_combatant(collider) and collider.has_method("take_damage"):
			var before: float = float(collider.get("health"))
			collider.call("take_damage", 8, global_position, self)
			damage_dealt += maxi(0, int(before - float(collider.get("health"))))
	_show_tracer(start, end)
	_effect_left = 0.055
	var hearer: Node3D = game.get("player") as Node3D
	var ear: Vector3 = hearer.camera.global_position if is_instance_valid(hearer) else global_position
	Audio.gunshot(start, _sound_blocked(ear, start), ear.distance_to(start) > 42.0)
	var listeners: Array = game.get("bots") as Array
	for entry: Variant in listeners:
		var listener: Node3D = entry as Node3D
		if is_instance_valid(listener) and listener != self and listener.has_method("hear_shot"):
			listener.call("hear_shot", global_position, self)


func receive_hit(damage: int, point: Vector3) -> bool:
	if dead or damage <= 0:
		return false
	last_headshot = to_local(point).y > 1.65
	var attacker: Node = get_meta("last_attacker") as Node if has_meta("last_attacker") else null
	if has_meta("last_attacker"): remove_meta("last_attacker")
	if not is_instance_valid(attacker):
		attacker = null
	var source: Vector3 = point
	if attacker is Node3D:
		source = (attacker as Node3D).global_position
	_apply_damage(roundi(float(damage) * (2.5 if last_headshot else 1.0)), source, attacker)
	return dead


func take_damage(amount: int, source: Vector3, attacker: Node = null) -> void:
	if dead or amount <= 0:
		return
	last_headshot = false
	_apply_damage(amount, source, attacker)


func _apply_damage(amount: int, source: Vector3, attacker: Node) -> void:
	health = maxi(0, health - amount)
	if health <= 0:
		dead = true
		active = false
		state = "阵亡"
		target = null
		velocity = Vector3.ZERO
		_capsule.set_deferred("disabled", true)
		_flash.hide()
		_tracer.hide()
		eliminated.emit(self, attacker)
	elif is_instance_valid(attacker) and not _visible_target:
		_last_seen = _ground(source)
		_memory_left = 6.0
		_set_goal(_last_seen)
		state = "搜索"


## Wall occlusion for the listener, not the target: a shot that is perfectly
## audible to whoever is aimed at still has to reach the ear it is reported to.
func _sound_blocked(ear: Vector3, source: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ear, source, 1, [get_rid()])
	var player: Node3D = game.get("player") as Node3D
	if is_instance_valid(player):
		query.exclude = [get_rid(), player.get_rid()]
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _build_effects() -> void:
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.80, 0.43)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = glow.albedo_color
	var flash_mesh: SphereMesh = SphereMesh.new()
	flash_mesh.radius = 0.055
	flash_mesh.height = 0.11
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	_flash = MeshInstance3D.new()
	_flash.mesh = flash_mesh
	_flash.material_override = glow
	_flash.scale = Vector3(1, 1, 2)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)
	_flash.hide()
	_tracer = MeshInstance3D.new()
	var tracer_mesh: BoxMesh = BoxMesh.new()
	tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
	_tracer.mesh = tracer_mesh
	_tracer.material_override = glow
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracer)
	_tracer.top_level = true
	_tracer.hide()


func _show_tracer(start: Vector3, end: Vector3) -> void:
	var length: float = start.distance_to(end)
	if length < 0.01:
		return
	_tracer.global_position = (start + end) * 0.5
	var direction: Vector3 = (end - start).normalized()
	_tracer.global_basis = Basis(Quaternion(Vector3.FORWARD, direction)).scaled_local(Vector3(1, 1, length))

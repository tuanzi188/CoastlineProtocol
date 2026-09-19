extends CharacterBody3D
## Self-contained coastal FPS controller. The owner controls active and mouse capture.

signal shot_fired
signal target_hit(killed: bool)
signal hit_confirmed(killed: bool, headshot: bool, point: Vector3)
signal reload_started
signal damaged(amount: float, source: Vector3)
signal died(attacker: Node)

enum Stance { STAND, CROUCH, PRONE }

## A fixed ring of MeshInstance3D that all share one geometry and one material.
## Building a fresh mesh per shot meant seven new surfaces and GPU uploads every
## 0.1 s; the ring uploads once at boot and afterwards only writes transforms.
## Lifetime and drift live in parallel arrays rather than String-named metadata,
## which was read and re-boxed twice per slot every render frame.
class EffectPool:
	var nodes: Array[MeshInstance3D] = []
	var left: PackedFloat32Array = PackedFloat32Array()
	var drift: PackedVector3Array = PackedVector3Array()
	var tracks_drift: bool = false
	var next_slot: int = 0

	func setup(capacity: int, geometry: Mesh, material: Material, host: Node, with_drift: bool) -> void:
		tracks_drift = with_drift
		for index: int in range(capacity):
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.mesh = geometry
			instance.material_override = material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visible = false
			host.add_child(instance)
			nodes.append(instance)
			left.append(0.0)
			if with_drift:
				drift.append(Vector3.ZERO)

	func acquire(lifetime: float) -> int:
		var slot: int = next_slot
		next_slot = (next_slot + 1) % nodes.size()
		left[slot] = lifetime
		nodes[slot].visible = true
		return slot

	func clear() -> void:
		for slot: int in range(nodes.size()):
			left[slot] = 0.0
			if tracks_drift:
				drift[slot] = Vector3.ZERO
			nodes[slot].visible = false

var health: float = 100.0
var armor: float = 50.0
var dead: bool = false
var medkits: int = 2
var healing: bool = false
var heal_left: float = 0.0

var camera: Camera3D
var ammo: int = 30
var reserve: int = 180
var reloading: bool = false
var aiming: bool = false
var sprinting: bool = false
var crouching: bool = false
var prone: bool = false
var lean: float = 0.0
var shots_fired: int = 0
var hits: int = 0
var kills: int = 0
var headshots: int = 0
var horizontal_speed: float = 0.0
var active: bool = false
var mouse_sensitivity: float = 1.0
var base_fov: float = 78.0
var view_motion: bool = true

const WALK_SPEED: float = 5.4
const SPRINT_SPEED: float = 8.8
const CROUCH_SPEED: float = 2.8
const PRONE_SPEED: float = 1.5
const JUMP_SPEED: float = 4.8
const GRAVITY: float = 19.0
const JUMP_BUFFER_TIME: float = 0.12
const COYOTE_TIME: float = 0.1
const MAGAZINE_SIZE: int = 30
const RELOAD_TIME: float = 1.8
const FIRE_INTERVAL: float = 0.1
const MOUSE_SENSITIVITY: float = 0.0022
## Ring capacities. At ten shots per second a 0.045 s tracer and a 0.19 s spark
## never need more slots than this, and the ring steals the oldest on overflow.
const MAX_TRACERS: int = 12
const MAX_SPARKS: int = 48
const SPARK_COUNT: int = 4
const MAX_IMPACTS: int = 24
const IMPACT_LIFETIME: float = 8.0
const TRACER_LIFETIME: float = 0.045
# Indexed by Stance; constants so the controller does not allocate a table every
# render frame just to read one number.
const EYE_HEIGHT_BY_STANCE: Array[float] = [1.62, 1.02, 0.52]
const CAPSULE_HEIGHT_BY_STANCE: Array[float] = [1.8, 1.2, 0.66]
const SPREAD_BY_STANCE: Array[float] = [1.0, 0.72, 0.5]
# Horizontal sway per shot, replayed in order so the climb can be learned.
const RECOIL_SWAY: Array[float] = [0.0, 0.9, -0.55, -1.0, 0.65, 1.0, -0.85, -0.35, 0.75, -0.95, 0.45, 0.15]
const RECOIL_CLIMB_FIRST: float = 0.0205
const RECOIL_CLIMB_SETTLED: float = 0.0092
const RECOIL_SWAY_STEP: float = 0.0058
const RECOIL_MAX_PITCH: float = 0.115
const RECOIL_MAX_YAW: float = 0.055
## Terrain, bots and targets all live on physics layer 1.
const HIT_MASK: int = 1
const RECOIL_RECOVERY_DELAY: float = 0.26
const SPRINT_FOV_GAIN: float = 6.5
const STEP_EASE_MAX: float = 0.34

var _head: Node3D
var _body_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _standing_probe: CapsuleShape3D
var _stand_probe: PhysicsShapeQueryParameters3D
var _hands: Node3D
var _weapon: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _muzzle_light: OmniLight3D
var _surface: String = "grass"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pitch: float = 0.0
var _recoil: float = 0.0
var _recoil_yaw: float = 0.0
var _burst: int = 0
var _recovery_left: float = 0.0
var _step_ease: float = 0.0
var _land_dip: float = 0.0
var _sprint_fov: float = 0.0
var _approach_velocity_y: float = 0.0
var _stance: int = Stance.STAND
var _eye_height: float = 1.62
var _grounded: bool = false
var _kick: float = 0.0
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _flash_left: float = 0.0
var _ads: float = 0.0
var _bob_phase: float = 0.0
var _step_distance: float = 0.0
var _jump_buffer_left: float = 0.0
var _coyote_left: float = 0.0
# Landing-buffered jumps retain a floor flag until the next move_and_slide().
var _jump_consumed: bool = false
var _mouse_sway: Vector2 = Vector2.ZERO
var _effects_host: Node
var _tracer_pool: EffectPool
var _spark_pool: EffectPool
var _impacts: Array[Node3D] = []
var _impact_left: PackedFloat32Array = PackedFloat32Array()
var _impact_next: int = 0
var _tracer_geometry: CylinderMesh
var _spark_geometry: BoxMesh
var _impact_geometry: PlaneMesh
var _tracer_material: StandardMaterial3D
var _spark_material: StandardMaterial3D
var _impact_material: StandardMaterial3D


func _ready() -> void:
	_rng.randomize()
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(48.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.025
	max_slides = 6
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_body_shape = CollisionShape3D.new()
	_body_shape.name = "PlayerCapsule"
	_body_shape.shape = _capsule
	_body_shape.position.y = 0.9
	add_child(_body_shape)
	# The probe clears the floor slightly, while covering the standing headroom.
	_standing_probe = CapsuleShape3D.new()
	_standing_probe.radius = 0.32
	_standing_probe.height = 1.76
	_stand_probe = PhysicsShapeQueryParameters3D.new()
	_stand_probe.shape = _standing_probe
	_stand_probe.margin = 0.005
	_stand_probe.exclude = [get_rid()]
	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 1.62
	add_child(_head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = base_fov
	camera.near = 0.035
	_head.add_child(camera)
	_build_weapon()
	_tracer_material = _material(Color(1.0, 0.79, 0.40), 0.0, 1.0, true)
	_spark_material = _material(Color(1.0, 0.57, 0.19), 0.0, 1.0, true)
	_impact_material = _material(Color(0.045, 0.04, 0.035), 0.0, 1.0)
	_impact_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_effects()


## Geometry is authored once and shared by every slot. The tracer is a unit-height
## cylinder stretched along its own axis, so one mesh covers all engagement ranges.
func _build_effects() -> void:
	_tracer_geometry = CylinderMesh.new()
	_tracer_geometry.top_radius = 0.008
	_tracer_geometry.bottom_radius = 0.004
	_tracer_geometry.height = 1.0
	_tracer_geometry.radial_segments = 5
	_spark_geometry = BoxMesh.new()
	_spark_geometry.size = Vector3(0.013, 0.013, 0.036)
	_impact_geometry = PlaneMesh.new()
	_impact_geometry.size = Vector2(0.055, 0.055)
	_effects_host = _effect_parent()
	if _effects_host == null:
		return
	_tracer_pool = EffectPool.new()
	_tracer_pool.setup(MAX_TRACERS, _tracer_geometry, _tracer_material, _effects_host, false)
	_spark_pool = EffectPool.new()
	_spark_pool.setup(MAX_SPARKS, _spark_geometry, _spark_material, _effects_host, true)


func _unhandled_input(event: InputEvent) -> void:
	if not active or dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var relative: Vector2 = motion.screen_relative
		var sensitivity: float = MOUSE_SENSITIVITY * mouse_sensitivity * lerpf(1.0, 0.67, _ads)
		rotate_y(-relative.x * sensitivity)
		_pitch = clampf(_pitch - relative.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		if view_motion:
			_mouse_sway = (_mouse_sway + relative * 0.0005).clamp(Vector2(-0.045, -0.045), Vector2(0.045, 0.045))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var controls: bool = active and not dead
	# Cancellation takes priority over completing a heal on this tick.
	if healing:
		if not controls or Input.is_action_pressed("fire") or Input.is_action_pressed("sprint"):
			Audio.heal_cancel()
			_cancel_heal()
		else:
			heal_left = maxf(0.0, heal_left - delta)
			if heal_left <= 0.0:
				health = minf(health + 60.0, 100.0)
				medkits -= 1
				_cancel_heal()
				Audio.heal_finish()
	if controls and InputMap.has_action("heal") and Input.is_action_just_pressed("heal"):
		if not Input.is_action_pressed("fire") and not Input.is_action_pressed("sprint"):
			start_heal()
	if reloading and controls:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left <= 0.0:
			var amount: int = mini(MAGAZINE_SIZE - ammo, reserve)
			ammo += amount
			reserve -= amount
			reloading = false
			Audio.reload_finish()
	# Going lower is always allowed; rising has to clear the standing probe.
	if controls and Input.is_action_just_pressed("prone"):
		_set_stance(Stance.STAND if prone else Stance.PRONE)
	if controls and Input.is_action_just_pressed("crouch") and prone:
		_set_stance(Stance.CROUCH)
	if not prone:
		if controls and Input.is_action_pressed("crouch"):
			_set_stance(Stance.CROUCH)
		elif crouching and _can_stand():
			_set_stance(Stance.STAND)
	aiming = controls and Input.is_action_pressed("aim") and not reloading
	var input_vector: Vector2 = Vector2.ZERO
	if controls:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprinting = controls and not healing and Input.is_action_pressed("sprint") and input_vector.y < -0.2 and _stance == Stance.STAND and not aiming and not Input.is_action_pressed("fire")
	var speed: float = WALK_SPEED
	if _stance == Stance.CROUCH:
		speed = CROUCH_SPEED
	elif _stance == Stance.PRONE:
		speed = PRONE_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if healing:
		speed *= 0.4
	var direction: Vector3 = global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var acceleration: float = 32.0 if is_on_floor() else 10.0
	if input_vector.is_zero_approx():
		acceleration = 38.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if not controls:
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
	else:
		if Input.is_action_just_pressed("jump") and not prone:
			_jump_buffer_left = JUMP_BUFFER_TIME
		if is_on_floor() and not _jump_consumed:
			_coyote_left = COYOTE_TIME
		else:
			_coyote_left = maxf(0.0, _coyote_left - delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -45.0)
	elif not _jump_consumed:
		velocity.y = 0.0
	_try_buffered_jump()
	_try_step(delta)
	_approach_velocity_y = velocity.y
	move_and_slide()
	var landed: bool = is_on_floor()
	if landed and not _grounded and _approach_velocity_y < -5.0:
		# Sink the view in proportion to the impact so a drop reads as a landing
		# rather than a hard cut back to standing height.
		_land_dip = clampf((-_approach_velocity_y - 5.0) / 12.0, 0.0, 1.0) * 0.095
	_grounded = landed
	if is_on_floor() and velocity.y <= 0.0:
		_jump_consumed = false
		_coyote_left = COYOTE_TIME if controls else 0.0
		# Consume a buffered press on the landing tick, before it can expire.
		_try_buffered_jump()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if global_position.y < -12.0:
		global_position = Vector3(0.0, 5.0, 46.0)
		velocity = Vector3.ZERO
		horizontal_speed = 0.0
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_jump_consumed = false
	_update_lean(delta, controls)
	if controls and not healing:
		if Input.is_action_just_pressed("reload"):
			_start_reload()
		if Input.is_action_pressed("fire") and not reloading and _cooldown <= 0.0:
			if ammo > 0:
				_fire()
			else:
				# The click lands before the auto-reload so an empty magazine is
				# audible instead of a silent dead trigger.
				Audio.dry_fire()
				_start_reload()
	_update_footsteps(delta, controls)


func _update_lean(delta: float, controls: bool) -> void:
	var target: float = 0.0
	if controls and not prone and not sprinting:
		if Input.is_action_pressed("lean_left"):
			target -= 1.0
		if Input.is_action_pressed("lean_right"):
			target += 1.0
	lean = lerpf(lean, target, 1.0 - exp(-13.0 * delta))


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return
	var smooth: float = 1.0 - exp(-14.0 * delta)
	var can_aim: bool = aiming and active and not dead and not reloading
	_ads = lerpf(_ads, 1.0 if can_aim else 0.0, smooth)
	# The collider changes height instantly so collision never lags the view;
	# only the eye line is eased.
	_eye_height = lerpf(_eye_height, EYE_HEIGHT_BY_STANCE[_stance], smooth)
	_step_ease = lerpf(_step_ease, 0.0, 1.0 - exp(-17.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-9.0 * delta))
	_sprint_fov = lerpf(_sprint_fov, 1.0 if sprinting and active and is_on_floor() else 0.0, 1.0 - exp(-6.5 * delta))
	camera.fov = lerpf(base_fov, 54.0, _ads) + _sprint_fov * SPRINT_FOV_GAIN * (1.0 - _ads)
	_head.position.y = _eye_height - _step_ease - _land_dip
	_recovery_left = maxf(0.0, _recovery_left - delta)
	if _recovery_left <= 0.0:
		# Two-stage return: the bulk of the climb snaps back so the sight clears,
		# then the last sliver creeps home. One linear rate leaves the crosshair
		# sitting high far longer than it feels like it should.
		_recoil = move_toward(_recoil, 0.0, delta * (0.10 if _recoil > 0.03 else 0.024))
		_recoil_yaw = move_toward(_recoil_yaw, 0.0, delta * 0.055)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-19.0 * delta))
	_head.rotation.x = clampf(_pitch + _recoil, deg_to_rad(-87.0), deg_to_rad(87.0))
	_head.rotation.y = _recoil_yaw + deg_to_rad(6.0) * lean
	_head.rotation.z = deg_to_rad(2.6) * lean
	_head.position.x = lerpf(_head.position.x, 0.26 * lean, smooth)
	_mouse_sway = _mouse_sway.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta)) if view_motion else Vector2.ZERO
	var movement: float = clampf(horizontal_speed / WALK_SPEED, 0.0, 1.5) if view_motion and is_on_floor() and active else 0.0
	if view_motion:
		_bob_phase += delta * horizontal_speed * 2.05
	var bob: Vector3 = Vector3(sin(_bob_phase) * 0.012, absf(cos(_bob_phase)) * 0.013, 0.0) * movement * (1.0 - _ads * 0.94)
	var base_position: Vector3 = Vector3(0.265, -0.235, -0.40).lerp(Vector3(0.0, -0.105, -0.26), _ads)
	var sway: Vector3 = Vector3(-_mouse_sway.x, _mouse_sway.y, 0.0) * (1.0 - _ads * 0.97)
	var lowering: float = 0.0
	var reload_roll: float = 0.0
	if reloading:
		var progress: float = clampf(1.0 - _reload_left / RELOAD_TIME, 0.0, 1.0)
		lowering = sin(progress * PI) * 0.055
		reload_roll = sin(progress * PI) * -0.35
	if view_motion and sprinting and active:
		lowering += 0.105
	var reload_pose: float = sin(clampf(1.0-_reload_left/RELOAD_TIME,0.0,1.0)*PI) if reloading else 0.0
	var target_position: Vector3 = base_position + bob + sway + Vector3(0.0, -lowering, _kick * 0.048) + Vector3(-0.10,0.20,-0.18)*reload_pose
	_weapon.position = _weapon.position.lerp(target_position, smooth)
	var target_rotation: Vector3 = Vector3(_kick * 0.04 - lowering * 1.5, _mouse_sway.x * (1.0 - _ads), reload_roll + (0.14 if view_motion and sprinting and active else 0.0))
	_weapon.rotation = _weapon.rotation.lerp(target_rotation, smooth)
	_hands.animate(delta,reloading,clampf(1.0-_reload_left/RELOAD_TIME,0.0,1.0),_kick)
	_flash_left = maxf(0.0, _flash_left - delta)
	_flash.visible = _flash_left > 0.0 and active and not dead
	_muzzle_light.visible = _flash.visible
	_update_effects(delta)


func _try_buffered_jump() -> void:
	if not active or dead or _stance != Stance.STAND or _jump_consumed or _jump_buffer_left <= 0.0 or _coyote_left <= 0.0:
		return
	velocity.y = JUMP_SPEED
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_jump_consumed = true


func _try_step(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.005 or not test_move(global_transform, motion):
		return
	var raised: Transform3D = global_transform
	raised.origin.y += 0.30
	var ahead: Vector3 = motion.normalized() * (motion.length() + 0.36)
	if test_move(global_transform, Vector3.UP * 0.30) or test_move(raised, ahead):
		return
	raised.origin += ahead
	var landing := KinematicCollision3D.new()
	if test_move(raised, Vector3.DOWN * 0.34, landing) and landing.get_normal().dot(Vector3.UP) > 0.72:
		var rise: float = 0.30 + landing.get_travel().y
		if rise > 0.025:
			var lift: float = rise + 0.015
			global_position.y += lift
			# The body clears the step immediately, but the view is dropped by the
			# same amount and climbs back over ~0.1 s. Without this the camera
			# snaps upward on every kerb and stair.
			_step_ease = minf(_step_ease + lift, STEP_EASE_MAX)


func _set_stance(next_stance: int) -> void:
	if next_stance == Stance.STAND and not _can_stand():
		return
	if next_stance == _stance:
		return
	_stance = next_stance
	prone = _stance == Stance.PRONE
	crouching = _stance == Stance.CROUCH
	_capsule.height = CAPSULE_HEIGHT_BY_STANCE[_stance]
	_body_shape.position.y = _capsule.height * 0.5


func _can_stand() -> bool:
	# Reused query object: this runs every physics tick while crouched, and the
	# parameters plus their exclude array were previously rebuilt each time.
	_stand_probe.transform = Transform3D(global_transform.basis.orthonormalized(), global_position + Vector3.UP * 0.92)
	_stand_probe.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(_stand_probe, 1).is_empty()


func take_damage(amount: int, source: Vector3, attacker: Node = null) -> void:
	if not active or dead or amount <= 0:
		return
	var absorbed: float = minf(armor, float(amount) * 0.35)
	armor -= absorbed
	var health_damage: float = minf(health, float(amount) - absorbed)
	health = maxf(0.0, health - health_damage)
	if health_damage > 0.0:
		Audio.player_hit()
	if healing:
		Audio.heal_cancel()
	_cancel_heal()
	if health <= 0.0:
		_die(attacker, health_damage, source)
	else:
		damaged.emit(health_damage, source)


func fall_out_of_world() -> void:
	# Leaving the island must be lethal; a full armor plate otherwise absorbs
	# 35% of any finite damage figure and leaves the player alive off-map.
	if not active or dead:
		return
	var lost: float = health
	health = 0.0
	armor = 0.0
	_cancel_heal()
	_die(null, lost, global_position)


func _die(attacker: Node, health_damage: float, source: Vector3) -> void:
	dead = true
	active = false
	reloading = false
	_reload_left = 0.0
	aiming = false
	sprinting = false
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_flash_left = 0.0
	if is_instance_valid(_flash):
		_flash.hide()
	if is_instance_valid(_muzzle_light):
		_muzzle_light.hide()
	damaged.emit(health_damage, source)
	died.emit(attacker)


func start_heal() -> void:
	if not active or dead or healing or health >= 100.0 or medkits <= 0:
		return
	reloading = false
	_reload_left = 0.0
	sprinting = false
	healing = true
	heal_left = 3.0
	Audio.heal_start()


func _cancel_heal() -> void:
	healing = false
	heal_left = 0.0


func collect_supply() -> void:
	reserve = mini(reserve + 60, 300)
	medkits = mini(medkits + 1, 4)
	armor = minf(armor + 20.0, 100.0)


func _start_reload() -> void:
	if not active or dead or healing or reloading or ammo >= MAGAZINE_SIZE or reserve <= 0:
		return
	reloading = true
	aiming = false
	_reload_left = RELOAD_TIME
	Audio.reload_start()
	reload_started.emit()


func _fire() -> void:
	if not active or dead or healing or reloading or ammo <= 0:
		return
	ammo -= 1
	shots_fired += 1
	_cooldown = FIRE_INTERVAL
	# Use the current look immediately, even if input arrived between render frames.
	_head.rotation.x = clampf(_pitch + _recoil, deg_to_rad(-87.0), deg_to_rad(87.0))
	_head.rotation.y = _recoil_yaw + deg_to_rad(6.0) * lean
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z
	if not aiming:
		var spread: float = (0.006 + clampf(horizontal_speed / SPRINT_SPEED, 0.0, 1.0) * 0.005) * SPREAD_BY_STANCE[_stance]
		if not is_on_floor():
			# Airborne is by far the worst accuracy state and has to be felt.
			spread += 0.007
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = sqrt(_rng.randf()) * spread
		direction = (direction + camera.global_transform.basis.x * cos(angle) * radius + camera.global_transform.basis.y * sin(angle) * radius).normalized()
	var end: Vector3 = origin + direction * 220.0
	# Layer 1 carries terrain, bots and targets alike (see enemy.gd's _ray), so the
	# default all-bits mask only widens the broadphase walk. The project has no
	# Area3D at all, so area traversal was pure query cost on every shot.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end, HIT_MASK)
	query.exclude = [get_rid()]
	query.hit_from_inside = true
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		end = result["position"] as Vector3
		# Muzzle distance check: if the camera hit point is beyond the muzzle's
		# reach (thin wall between camera and muzzle), the barrel doesn't actually
		# reach it — fall back to the wall in front of the muzzle.
		var muzzle_origin: Vector3 = _muzzle.global_position
		var muzzle_dist_sq: float = origin.distance_squared_to(muzzle_origin)
		if origin.distance_squared_to(end) > muzzle_dist_sq * 1.05:
			var barrel_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, muzzle_origin, HIT_MASK)
			barrel_query.exclude = [get_rid()]
			barrel_query.hit_from_inside = true
			var barrel_result: Dictionary = get_world_3d().direct_space_state.intersect_ray(barrel_query)
			if not barrel_result.is_empty():
				result = barrel_result
				end = result["position"] as Vector3
	if not result.is_empty():
		end = result["position"] as Vector3
		var collider: Object = result["collider"] as Object
		if is_instance_valid(collider) and collider.has_method("receive_hit"):
			collider.set_meta("last_attacker", self)
			var killed: bool = bool(collider.call("receive_hit", 34, end))
			var headshot: bool = false
			# Damageables need not expose last_headshot, and may free themselves on hit.
			# `in` is an O(1) existence probe; the old loop materialised the collider's
			# entire property list as an Array of Dictionaries on every impact.
			if is_instance_valid(collider) and "last_headshot" in collider:
				headshot = bool(collider.get("last_headshot"))
			hits += 1
			if killed:
				kills += 1
			if headshot:
				headshots += 1
			target_hit.emit(killed)
			hit_confirmed.emit(killed, headshot, end)
		var normal: Vector3 = result["normal"] as Vector3
		_spawn_sparks(end, normal)
		if is_instance_valid(collider):
			_spawn_impact(end, normal, collider)
	_spawn_tracer(muzzle_origin, end)
	# Pattern-driven climb: the opening shots kick hardest and the rate settles, so
	# the pull-down rhythm is learnable rather than random. Sway replays a fixed
	# sequence instead of drifting, which is what makes burst control feel fair.
	_burst += 1
	_recovery_left = RECOIL_RECOVERY_DELAY
	var ramp: float = clampf(float(_burst) / 6.0, 0.0, 1.0)
	var ads_scale: float = lerpf(1.0, 0.62, _ads)
	_recoil = minf(_recoil + lerpf(RECOIL_CLIMB_FIRST, RECOIL_CLIMB_SETTLED, ramp) * ads_scale, RECOIL_MAX_PITCH)
	var sway: float = RECOIL_SWAY[(_burst - 1) % RECOIL_SWAY.size()]
	_recoil_yaw = clampf(_recoil_yaw + sway * RECOIL_SWAY_STEP * ads_scale, -RECOIL_MAX_YAW, RECOIL_MAX_YAW)
	_kick = minf(_kick + 1.0, 1.8)
	_flash_left = 0.035
	_flash.rotation.z = _rng.randf_range(-PI, PI)
	_flash.visible = true
	_muzzle_light.visible = true
	Audio.own_weapon_shot()
	shot_fired.emit()


func get_accuracy() -> float:
	return 100.0 * float(hits) / float(shots_fired) if shots_fired > 0 else 0.0


func reset_loadout() -> void:
	health = 100.0
	armor = 50.0
	dead = false
	medkits = 2
	_cancel_heal()
	ammo = MAGAZINE_SIZE
	reserve = 180
	reloading = false
	aiming = false
	sprinting = false
	shots_fired = 0
	hits = 0
	kills = 0
	headshots = 0
	_stance = Stance.STAND
	crouching = false
	prone = false
	lean = 0.0
	_eye_height = 1.62
	_step_ease = 0.0
	_land_dip = 0.0
	_sprint_fov = 0.0
	_grounded = false
	_recoil = 0.0
	_recoil_yaw = 0.0
	_burst = 0
	_recovery_left = 0.0
	_approach_velocity_y = 0.0
	_capsule.height = 1.8
	_body_shape.position.y = 0.9
	_head.position = Vector3(0.0, 1.62, 0.0)
	_head.rotation = Vector3.ZERO
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_jump_consumed = false
	_cooldown = 0.0
	_reload_left = 0.0
	_recoil = 0.0
	_kick = 0.0
	_flash_left = 0.0
	_ads = 0.0
	_step_distance = 0.0
	_mouse_sway = Vector2.ZERO
	if is_instance_valid(camera):
		camera.fov = base_fov
		_hands.reset_pose()
		_flash.visible = false
		_muzzle_light.visible = false
	if _tracer_pool != null:
		_tracer_pool.clear()
	if _spark_pool != null:
		_spark_pool.clear()
	for impact: Node3D in _impacts:
		if is_instance_valid(impact):
			impact.queue_free()
	_impacts.clear()
	_impact_left.resize(0)


func _material(color: Color, metal: float = 0.0, roughness: float = 0.7, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material


func _mesh(parent: Node3D, geometry: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = geometry
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry: BoxMesh = BoxMesh.new()
	geometry.size = size
	return _mesh(parent, geometry, at, material)


func _tube(parent: Node3D, radius: float, length: float, at: Vector3, material: Material, sides: int = 12) -> MeshInstance3D:
	var geometry: CylinderMesh = CylinderMesh.new()
	geometry.top_radius = radius
	geometry.bottom_radius = radius
	geometry.height = length
	geometry.radial_segments = sides
	var instance: MeshInstance3D = _mesh(parent, geometry, at, material)
	instance.rotation.x = PI * 0.5
	return instance


func _limb(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry: CapsuleMesh = CapsuleMesh.new()
	geometry.radius = radius
	geometry.height = length
	geometry.radial_segments = 12
	geometry.rings = 4
	var instance: MeshInstance3D = _mesh(parent, geometry, at, material)
	instance.rotation.x = PI * 0.5
	return instance


func _build_weapon() -> void:
	_weapon = Node3D.new()
	_weapon.name = "TidebreakerRifle"
	_weapon.position = Vector3(0.265, -0.235, -0.40)
	camera.add_child(_weapon)
	var graphite: StandardMaterial3D = _material(Color("252e32"), 0.65, 0.38)
	var steel: StandardMaterial3D = _material(Color("596468"), 0.78, 0.32)
	var dark: StandardMaterial3D = _material(Color("101719"), 0.25, 0.65)
	var sand: StandardMaterial3D = _material(Color("3a3a30"), 0.15, 0.76)
	var rubber: StandardMaterial3D = _material(Color("30352e"), 0.0, 0.94)
	var teal: StandardMaterial3D = _material(Color("398c87"), 0.3, 0.48)
	var fabric: StandardMaterial3D = _material(Color("485c58"), 0.0, 0.95)
	var glove: StandardMaterial3D = _material(Color("2a2a2a"), 0.0, 0.9)
	var sight_dot: StandardMaterial3D = _material(Color("8cdec6"), 0.0, 0.5, true)
	# Angular receiver with a two-tone upper, side plates and service details.
	_box(_weapon, Vector3(0.105, 0.12, 0.33), Vector3(0.0, -0.02, -0.10), graphite)
	_box(_weapon, Vector3(0.095, 0.048, 0.34), Vector3(0.0, 0.044, -0.11), sand)
	_box(_weapon, Vector3(0.112, 0.052, 0.18), Vector3(0.0, -0.071, -0.095), dark)
	_box(_weapon, Vector3(0.006, 0.028, 0.102), Vector3(0.056, 0.013, -0.108), dark)
	_box(_weapon, Vector3(0.009, 0.013, 0.072), Vector3(0.059, 0.014, -0.11), steel)
	_box(_weapon, Vector3(0.018, 0.016, 0.028), Vector3(0.066, 0.022, -0.043), graphite)
	_box(_weapon, Vector3(0.008, 0.018, 0.058), Vector3(0.055, -0.043, 0.006), teal)
	for z: float in [-0.23, -0.035, 0.035]:
		var pin: MeshInstance3D = _tube(_weapon, 0.007, 0.113, Vector3(0.0, -0.026, z), steel, 8)
		pin.rotation = Vector3(0.0, 0.0, PI * 0.5)
	# Adjustable skeleton stock and shoulder pad.
	_tube(_weapon, 0.026, 0.18, Vector3(0.0, -0.015, 0.14), steel)
	_box(_weapon, Vector3(0.083, 0.063, 0.18), Vector3(0.0, -0.015, 0.22), sand)
	var stock_brace: MeshInstance3D = _box(_weapon, Vector3(0.052, 0.045, 0.17), Vector3(0.0, -0.075, 0.21), graphite)
	stock_brace.rotation.x = -0.30
	_box(_weapon, Vector3(0.092, 0.16, 0.035), Vector3(0.0, -0.055, 0.315), rubber)
	# Floating handguard, cooling slots and segmented accessory rails.
	_box(_weapon, Vector3(0.088, 0.093, 0.285), Vector3(0.0, -0.005, -0.414), sand)
	_box(_weapon, Vector3(0.076, 0.029, 0.26), Vector3(0.0, -0.059, -0.414), graphite)
	for index: int in range(7):
		var z: float = -0.30 - float(index) * 0.035
		for side: float in [-1.0, 1.0]:
			_box(_weapon, Vector3(0.003, 0.025, 0.019), Vector3(side * 0.045, 0.006, z), dark)
			_box(_weapon, Vector3(0.014, 0.017, 0.022), Vector3(side * 0.048, -0.035, z), graphite)
	_box(_weapon, Vector3(0.038, 0.012, 0.61), Vector3(0.0, 0.071, -0.239), dark)
	for index: int in range(23):
		_box(_weapon, Vector3(0.048, 0.009, 0.013), Vector3(0.0, 0.081, 0.045 - float(index) * 0.026), graphite)
	_tube(_weapon, 0.019, 0.22, Vector3(0.0, -0.004, -0.635), steel)
	_tube(_weapon, 0.028, 0.085, Vector3(0.0, -0.004, -0.755), graphite)
	_tube(_weapon, 0.020, 0.006, Vector3(0.0, -0.004, -0.80), dark)
	for index: int in range(3):
		_box(_weapon, Vector3(0.057, 0.009, 0.009), Vector3(0.0, 0.009, -0.735 - float(index) * 0.02), dark)
	# Magazine, spine and stamped ribs.
	var magazine: Node3D = Node3D.new()
	magazine.position = Vector3(0.0, -0.14, -0.17)
	magazine.rotation.x = -0.16
	_weapon.add_child(magazine)
	_box(magazine, Vector3(0.072, 0.17, 0.092), Vector3.ZERO, graphite)
	_box(magazine, Vector3(0.079, 0.022, 0.10), Vector3(0.0, -0.083, 0.0), rubber)
	for index: int in range(4):
		_box(magazine, Vector3(0.075, 0.006, 0.083), Vector3(0.0, -0.052 + float(index) * 0.032, 0.0), steel)
	var grip: MeshInstance3D = _box(_weapon, Vector3(0.062, 0.139, 0.063), Vector3(0.0, -0.13, 0.027), rubber)
	grip.rotation.x = -0.28
	_box(_weapon, Vector3(0.018, 0.012, 0.095), Vector3(0.0, -0.115, -0.049), graphite)
	_box(_weapon, Vector3(0.018, 0.049, 0.012), Vector3(0.0, -0.096, -0.089), graphite)
	# Open rectangular rear aperture: its center and front bead share y=0.105.
	# ADS translates that sight line exactly onto the camera's forward axis.
	for side: float in [-1.0, 1.0]:
		_box(_weapon, Vector3(0.010, 0.052, 0.017), Vector3(side * 0.025, 0.105, 0.033), dark)
	_box(_weapon, Vector3(0.060, 0.009, 0.017), Vector3(0.0, 0.131, 0.033), dark)
	_box(_weapon, Vector3(0.060, 0.009, 0.017), Vector3(0.0, 0.079, 0.033), dark)
	_box(_weapon, Vector3(0.006, 0.025, 0.012), Vector3(0.0, 0.0925, -0.51), graphite)
	_box(_weapon, Vector3(0.004, 0.004, 0.006), Vector3(0.0, 0.105, -0.504), sight_dot)
	for side: float in [-1.0, 1.0]:
		_box(_weapon, Vector3(0.008, 0.035, 0.019), Vector3(side * 0.022, 0.093, -0.51), graphite)
	_hands = preload("res://scripts/first_person_hands.gd").new()
	_hands.name = "FirstPersonHands"
	_weapon.add_child(_hands)
	_hands.build(magazine)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, -0.004, -0.811)
	_weapon.add_child(_muzzle)
	var flash_mesh: CylinderMesh = CylinderMesh.new()
	flash_mesh.top_radius = 0.003
	flash_mesh.bottom_radius = 0.043
	flash_mesh.height = 0.14
	flash_mesh.radial_segments = 5
	_flash = _mesh(_muzzle, flash_mesh, Vector3(0.0, 0.0, -0.055), _material(Color("ffd394"), 0.0, 1.0, true))
	_flash.rotation.x = -PI * 0.5
	_flash.visible = false
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.71, 0.35)
	_muzzle_light.light_energy = 1.2
	_muzzle_light.omni_range = 3.0
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	_muzzle.add_child(_muzzle_light)


func _effect_parent() -> Node:
	var scene: Node = get_tree().current_scene
	return scene if scene != null and scene != self else get_parent()


func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var displacement: Vector3 = end - start
	var length: float = displacement.length()
	if length < 0.01 or _tracer_pool == null:
		return
	var slot: int = _tracer_pool.acquire(TRACER_LIFETIME)
	var tracer: MeshInstance3D = _tracer_pool.nodes[slot]
	# The shared cylinder is unit height, so range is expressed as a local Y scale
	# instead of a rebuilt geometry.
	tracer.global_basis = Basis(Quaternion(Vector3.UP, displacement / length)).scaled(Vector3(1.0, length, 1.0))
	tracer.global_position = (start + end) * 0.5


func _spawn_sparks(point: Vector3, normal: Vector3) -> void:
	if _spark_pool == null:
		return
	for index: int in range(SPARK_COUNT):
		var slot: int = _spark_pool.acquire(_rng.randf_range(0.10, 0.19))
		var spark: MeshInstance3D = _spark_pool.nodes[slot]
		spark.global_position = point + normal * 0.018
		_spark_pool.drift[slot] = normal * _rng.randf_range(0.7, 1.8) + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(0.2, 1.1), _rng.randf_range(-0.8, 0.8))


func _spawn_impact(point: Vector3, normal: Vector3, collider: Object) -> void:
	# Inside-solid ray hits have no surface normal, so cannot host a decal.
	if normal.is_zero_approx():
		return
	var parent: Node3D = collider as Node3D
	if parent == null or parent.is_queued_for_deletion():
		return
	while _impacts.size() >= MAX_IMPACTS:
		var oldest: Node3D = _impacts.pop_front() as Node3D
		_impact_left.remove_at(0)
		if is_instance_valid(oldest):
			oldest.hide()
			oldest.queue_free()
	var impact: MeshInstance3D = _mesh(parent, _impact_geometry, Vector3.ZERO, _impact_material)
	var surface_normal: Vector3 = normal.normalized()
	impact.global_position = point + surface_normal * 0.003
	impact.global_basis = Basis(Quaternion(Vector3.UP, surface_normal))
	_impacts.append(impact)
	_impact_left.append(IMPACT_LIFETIME)


func _update_effects(delta: float) -> void:
	_tick_pool(_tracer_pool, delta)
	_tick_pool(_spark_pool, delta)
	for index: int in range(_impacts.size() - 1, -1, -1):
		var impact: Node3D = _impacts[index]
		if not is_instance_valid(impact):
			_impacts.remove_at(index)
			_impact_left.remove_at(index)
			continue
		var remaining: float = _impact_left[index] - delta
		if remaining <= 0.0:
			impact.queue_free()
			_impacts.remove_at(index)
			_impact_left.remove_at(index)
		else:
			_impact_left[index] = remaining


func _tick_pool(pool: EffectPool, delta: float) -> void:
	if pool == null:
		return
	for slot: int in range(pool.nodes.size()):
		var remaining: float = pool.left[slot] - delta
		if remaining <= 0.0:
			pool.left[slot] = 0.0
			if pool.tracks_drift:
				pool.drift[slot] = Vector3.ZERO
			if pool.nodes[slot].visible:
				pool.nodes[slot].visible = false
			continue
		pool.left[slot] = remaining
		if pool.tracks_drift:
			var drift: Vector3 = pool.drift[slot]
			drift.y -= 6.0 * delta
			pool.nodes[slot].global_position += drift * delta
			pool.drift[slot] = drift


func _exit_tree() -> void:
	_release_pool(_tracer_pool)
	_release_pool(_spark_pool)
	for impact: Node3D in _impacts:
		if is_instance_valid(impact) and not impact.is_queued_for_deletion():
			impact.queue_free()
	_impacts.clear()
	_impact_left.resize(0)


func _release_pool(pool: EffectPool) -> void:
	if pool == null:
		return
	for node: MeshInstance3D in pool.nodes:
		if is_instance_valid(node):
			node.queue_free()
	pool.nodes.clear()


func _update_footsteps(delta: float, controls: bool) -> void:
	if not controls or not is_on_floor() or horizontal_speed < 0.7:
		_step_distance = 0.0
		return
	_step_distance += horizontal_speed * delta
	var stride: float = 2.15 if sprinting else (1.45 if crouching else 1.85)
	if _step_distance < stride:
		return
	_step_distance = fmod(_step_distance, stride)
	_surface = _floor_surface()
	Audio.footstep(_surface)


## Footfalls have to know what they land on, so the surface is probed at the
## moment of the step rather than cached while crossing materials.
func _floor_surface() -> String:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.9,
		global_position - Vector3.UP * 1.2, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "grass"
	var floor_body: Node = hit["collider"] as Node
	if floor_body != null and floor_body.name == "IslandTerrain":
		return "sand" if global_position.y < 1.25 else "grass"
	return "concrete"

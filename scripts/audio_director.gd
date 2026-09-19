extends Node
## Procedural audio director: bus layout, layered synthesis, occlusion routing.
## Every sample is generated at load; the project ships no audio assets.

const RATE := 44100
const MASTER_HEADROOM_DB := -3.0
const MAX_VOICES := 10

var rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _pools: Dictionary = {}
var _gull_left: float = 18.0
var _surfaces: Dictionary = {}

const SURFACE_GRASS := "grass"
const SURFACE_SAND := "sand"
const SURFACE_CONCRETE := "concrete"
const SURFACE_WOOD := "wood"


func _ready() -> void:
	rng.seed = 20260918
	_build_buses()
	_build_streams()
	_start_ambience()


func _build_streams() -> void:
	var synth: RefCounted = preload("res://scripts/audio_synth.gd").new()
	synth.init(rng)
	_streams = synth.build_all(RATE)


func _process(delta: float) -> void:
	# Gulls are scheduled rather than baked into the loop so the bed never sounds
	# like the same six seconds repeating.
	_gull_left -= delta
	if _gull_left <= 0.0:
		_gull_left = rng.randf_range(14.0, 42.0)
		if rng.randf() < 0.7:
			one_shot("gull", "Space", -16.0, rng.randf_range(0.9, 1.15))


# ---------------------------------------------------------------- buses

func _build_buses() -> void:
	_add_bus("SFX", "Master")
	_add_bus("Muffled", "SFX")
	_add_bus("Ambient", "Master")
	_add_bus("UI", "Master")
	_add_bus("Space", "Master")
	_add_effect("Master", _limiter())
	_add_effect("Muffled", _lowpass(820.0))
	_add_effect("Space", _reverb(0.62, 0.42))
	_add_effect("Ambient", _lowpass(5200.0))
	_set_bus_volume("SFX", -2.0)
	_set_bus_volume("Muffled", -3.0)
	_set_bus_volume("Ambient", -14.0)
	_set_bus_volume("UI", -6.0)
	_set_bus_volume("Space", -12.0)


func _add_bus(bus_name: String, send_to: String) -> void:
	var index: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send_to)


func _bus_index(bus_name: String) -> int:
	return AudioServer.get_bus_index(bus_name)


func _set_bus_volume(bus_name: String, db: float) -> void:
	_bus_floor[bus_name] = db
	AudioServer.set_bus_volume_db(_bus_index(bus_name), db)


var _bus_floor: Dictionary = {"Master": 0.0}


func _add_effect(bus_name: String, effect: AudioEffect) -> void:
	AudioServer.add_bus_effect(_bus_index(bus_name), effect)


func _limiter() -> AudioEffect:
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = MASTER_HEADROOM_DB
	return limiter


func _lowpass(cut: float) -> AudioEffect:
	var filter: AudioEffect = ClassDB.instantiate(&"AudioEffectLowPassFilter")
	filter.set("cutoff_hz", cut)
	filter.set("resonance", 0.4)
	return filter


func _reverb(room_size: float, wet: float) -> AudioEffect:
	var reverb: AudioEffect = ClassDB.instantiate(&"AudioEffectReverb")
	reverb.set("room_size", room_size)
	reverb.set("wet", wet)
	reverb.set("dry", 0.55)
	reverb.set("hipass", 0.28)
	reverb.set("bypass", false)
	return reverb


# ---------------------------------------------------------------- playback

## `at` as Vector3.INF plays flat on the master; anything else goes 3D.
func one_shot(sound: String, bus: String = "SFX", volume_db: float = 0.0, pitch: float = 1.0,
		at: Vector3 = Vector3.INF, variation: float = 0.0) -> void:
	var variants: Array = _streams.get(sound, [])
	if variants.is_empty():
		return
	var stream: AudioStreamWAV = variants[rng.randi_range(0, variants.size() - 1)]
	var spatial: bool = at != Vector3.INF
	var player: Node = _acquire(bus, spatial)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * rng.randf_range(1.0 - variation, 1.0 + variation)
	if spatial:
		player.global_position = at
	player.play()


## Fixed voice pool per bus. Stealing the oldest keeps a firefight from allocating
## unbounded players while guaranteeing the voice we picked actually gets used.
func _acquire(bus: String, spatial: bool) -> Node:
	var pool: Array = _pool("3d:" + bus if spatial else "2d:" + bus)
	for existing: Node in pool:
		if is_instance_valid(existing) and not bool(existing.call("is_playing")):
			return existing
	if pool.size() >= MAX_VOICES:
		var oldest: Node = pool.pop_front() as Node
		if is_instance_valid(oldest):
			oldest.call("stop")
			pool.append(oldest)
			return oldest
	var created: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	created.bus = bus
	if spatial:
		# unit_size is where attenuation begins; without spread panning a shot to
		# the left would still arrive dead centre.
		created.unit_size = 5.0
		created.max_distance = 130.0
		created.max_db = 6.0
		created.panning_strength = 1.15
	else:
		created.max_polyphony = 3
	add_child(created)
	pool.append(created)
	return created


func loop(sound: String, bus: String, volume_db: float) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = _streams[sound][0]
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	return player


func _pool(key: String) -> Array:
	if not _pools.has(key):
		_pools[key] = []
	return _pools[key]


# ---------------------------------------------------------------- game cues

func gunshot(at: Vector3, occluded: bool, distant: bool) -> void:
	var bus := "Muffled" if occluded else "SFX"
	var gain := -11.0 if occluded else (0.0 if not distant else -4.0)
	one_shot("rifle", bus, gain, 1.0, at, 0.06)
	# Shells and the tail are deliberately dry-side; the muffled bus already
	# removes the high content an occluded shot would not carry anyway.
	if not occluded:
		one_shot("shell", "Space", -22.0, 1.0, at, 0.12)


func own_weapon_shot() -> void:
	one_shot("rifle", "SFX", 0.0, 1.0, Vector3.INF, 0.05)
	one_shot("shell", "SFX", -20.0, 1.0, Vector3.INF, 0.15)


func footstep(surface: String) -> void:
	one_shot("step_" + surface, "SFX", -3.0, 1.0, Vector3.INF, 0.09)


func dry_fire() -> void:
	one_shot("dry", "SFX", 0.0, 1.0, Vector3.INF, 0.06)


func reload_start() -> void:
	one_shot("reload_out", "SFX", -4.0, 1.0, Vector3.INF, 0.05)


func reload_finish() -> void:
	one_shot("reload_in", "SFX", -4.0, 1.0, Vector3.INF, 0.05)


func hit(confirmed_kill: bool, headshot: bool) -> void:
	if confirmed_kill:
		one_shot("kill", "SFX", 0.0, 1.0, Vector3.INF, 0.02)
		one_shot("plate" if headshot else "flesh", "Space", -10.0)
		return
	one_shot("plate" if headshot else "flesh", "SFX", -6.0, 1.0, Vector3.INF, 0.05)


func player_hit() -> void:
	one_shot("hurt", "SFX", -8.0, 1.0, Vector3.INF, 0.08)


func pickup() -> void:
	one_shot("pickup", "SFX", -5.0, 1.0, Vector3.INF, 0.03)


func heal_start() -> void:
	one_shot("heal_start", "SFX", -8.0, 1.0, Vector3.INF, 0.02)


func heal_finish() -> void:
	one_shot("heal_done", "SFX", -8.0, 1.0, Vector3.INF, 0.02)


func heal_cancel() -> void:
	one_shot("heal_cancel", "SFX", -10.0, 1.0, Vector3.INF, 0.02)


func zone_warning() -> void:
	one_shot("zone_warn", "Space", -6.0)


func zone_damage() -> void:
	one_shot("zone_hurt", "SFX", -14.0, 1.0, Vector3.INF, 0.02)


func eliminated() -> void:
	one_shot("down", "Space", -4.0)


func outcome(victory: bool) -> void:
	one_shot("victory" if victory else "defeat", "Space", -6.0)


func ui_move() -> void:
	one_shot("ui_tick", "UI", -10.0, 1.0, Vector3.INF, 0.02)


func ui_back() -> void:
	one_shot("ui_back", "UI", -10.0)


func ui_commit() -> void:
	one_shot("ui_commit", "UI", -8.0)


## Bus faders sit relative to the level each bus was built with, so the mix balance
## authored above survives whatever the player sets in the options panel.
func set_bus_level(bus_name: String, fraction: float) -> void:
	var index: int = _bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, _bus_floor[bus_name] + linear_to_db(maxf(0.0005, fraction)))
	AudioServer.set_bus_mute(index, fraction <= 0.001)


func _start_ambience() -> void:
	for name: String in ["waves", "wind"]:
		loop(name, "Ambient", 0.0)

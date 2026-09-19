extends RefCounted
## Sample synthesis for the audio director. Everything here is generated from
## primitives at load time; the project ships no audio assets.

const LOOP_RATE := 22050
const LOOP_SECONDS := 8.0

var _rng: RandomNumberGenerator


func init(rng: RandomNumberGenerator) -> void:
	_rng = rng


func build_all(rate: int) -> Dictionary:
	return {
		"rifle": [_rifle(rate, 0.0), _rifle(rate, 0.31), _rifle(rate, 0.67)],
		"shell": [_shell(rate)],
		"dry": [_dry(rate)],
		"reload_out": [_reload_out(rate)],
		"reload_in": [_reload_in(rate)],
		"flesh": [_flesh(rate)],
		"plate": [_plate(rate)],
		"kill": [_kill(rate)],
		"hurt": [_hurt(rate)],
		"pickup": [_pickup(rate)],
		"heal_start": [_heal_start(rate)],
		"heal_done": [_heal_done(rate)],
		"heal_cancel": [_heal_cancel(rate)],
		"zone_warn": [_zone_warn(rate)],
		"zone_hurt": [_zone_hurt(rate)],
		"down": [_down(rate)],
		"victory": [_fanfare(rate, true)],
		"defeat": [_fanfare(rate, false)],
		"ui_tick": [_ui_click(rate, 1750.0)],
		"ui_back": [_ui_click(rate, 880.0)],
		"ui_commit": [_ui_click(rate, 1320.0)],
		"gull": [_gull(rate)],
		"waves": [_waves()],
		"wind": [_wind()],
		"step_grass": _footfalls(rate, "grass"),
		"step_sand": _footfalls(rate, "sand"),
		"step_concrete": _footfalls(rate, "concrete"),
		"step_wood": _footfalls(rate, "wood"),
	}


# ---------------------------------------------------------------- buffers

func _buffer(seconds: float, rate: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(maxi(1, int(seconds * rate)))
	return data


## `offset` is in milliseconds.
func _mix(target: PackedFloat32Array, source: PackedFloat32Array, offset: float, gain: float,
		rate: int) -> void:
	var start: int = int(offset * 0.001 * rate)
	for index: int in range(source.size()):
		var at: int = start + index
		if at >= target.size():
			return
		target[at] += source[index] * gain


func _wav(data: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for index: int in range(data.size()):
		bytes.encode_s16(index * 2, int(clampf(data[index], -0.98, 0.98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = data.size()
	return stream


# ---------------------------------------------------------------- generators

## Noise through a one-pole lowpass, then a highpass taken as signal-minus-lowpass,
## shaped by an exponential decay and a sub-millisecond attack that kills the click.
func _noise_burst(seconds: float, lp_hz: float, hp_hz: float, decay: float,
		rate: int) -> PackedFloat32Array:
	var count: int = maxi(2, int(seconds * rate))
	var data := PackedFloat32Array()
	data.resize(count)
	var lp_alpha: float = clampf(1.0 - exp(-TAU * lp_hz / rate), 0.0, 1.0)
	var hp_alpha: float = clampf(1.0 - exp(-TAU * maxf(20.0, hp_hz) / rate), 0.0, 1.0)
	var lp_state: float = 0.0
	var hp_state: float = 0.0
	var attack: int = maxi(2, int(0.0006 * rate))
	for index: int in range(count):
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp_state += (white - lp_state) * lp_alpha
		hp_state += (lp_state - hp_state) * hp_alpha
		var time: float = float(index) / rate
		var envelope: float = exp(-time * decay)
		if index < attack:
			envelope *= float(index) / attack
		data[index] = (lp_state - hp_state) * envelope
	return data


func _sine_sweep(seconds: float, from_hz: float, to_hz: float, decay: float,
		rate: int) -> PackedFloat32Array:
	var count: int = maxi(2, int(seconds * rate))
	var data := PackedFloat32Array()
	data.resize(count)
	var phase: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / count
		phase += TAU * lerpf(from_hz, to_hz, progress) / rate
		data[index] = sin(phase) * exp(-float(index) / rate * decay)
	return data


func _ring(seconds: float, frequency: float, decay: float, rate: int) -> PackedFloat32Array:
	var count: int = maxi(2, int(seconds * rate))
	var data := PackedFloat32Array()
	data.resize(count)
	var attack: int = maxi(2, int(0.0008 * rate))
	for index: int in range(count):
		var time: float = float(index) / rate
		var value: float = sin(TAU * frequency * time) * exp(-time * decay)
		if index < attack:
			value *= float(index) / attack
		data[index] = value
	return data


# ---------------------------------------------------------------- weapons

func _rifle(rate: int, variant: float) -> AudioStreamWAV:
	var body := _buffer(0.52, rate)
	# Sonic crack. Without this bright transient a synthesized shot reads as a dull
	# thump no matter how loud it is played.
	_mix(body, _noise_burst(0.012, 9000.0, 3600.0, 260.0, rate), 0.0, 0.92, rate)
	_mix(body, _noise_burst(0.09, 2600.0, 320.0, 42.0 + variant * 12.0, rate), 0.0, 0.78, rate)
	_mix(body, _sine_sweep(0.13, 168.0 + variant * 34.0, 46.0, 26.0, rate), 0.0, 0.66, rate)
	# Baked tail: this build has no per-send reverb, so the room lives in the sample.
	_mix(body, _noise_burst(0.42, 1150.0, 180.0, 9.5, rate), 18.0, 0.20, rate)
	return _wav(body, rate)


func _shell(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.16, rate)
	_mix(body, _ring(0.05, 4200.0, 90.0, rate), 0.0, 0.30, rate)
	_mix(body, _noise_burst(0.03, 6500.0, 2600.0, 130.0, rate), 4.0, 0.22, rate)
	_mix(body, _ring(0.06, 2950.0, 55.0, rate), 40.0, 0.14, rate)
	return _wav(body, rate)


func _dry(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.09, rate)
	_mix(body, _noise_burst(0.008, 5200.0, 1900.0, 210.0, rate), 0.0, 0.55, rate)
	_mix(body, _ring(0.03, 1450.0, 120.0, rate), 1.0, 0.34, rate)
	_mix(body, _noise_burst(0.012, 3400.0, 1200.0, 150.0, rate), 13.0, 0.34, rate)
	_mix(body, _ring(0.04, 900.0, 90.0, rate), 15.0, 0.22, rate)
	return _wav(body, rate)


func _reload_out(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.3, rate)
	_mix(body, _noise_burst(0.01, 4200.0, 1400.0, 170.0, rate), 0.0, 0.42, rate)
	_mix(body, _ring(0.06, 620.0, 60.0, rate), 2.0, 0.30, rate)
	_mix(body, _noise_burst(0.11, 1500.0, 400.0, 16.0, rate), 60.0, 0.26, rate)
	_mix(body, _noise_burst(0.02, 5200.0, 2100.0, 190.0, rate), 150.0, 0.16, rate)
	return _wav(body, rate)


func _reload_in(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.34, rate)
	_mix(body, _noise_burst(0.014, 2600.0, 700.0, 120.0, rate), 0.0, 0.46, rate)
	_mix(body, _ring(0.07, 340.0, 55.0, rate), 1.0, 0.36, rate)
	# Bolt home is the loudest, most final transient of the sequence.
	_mix(body, _noise_burst(0.02, 6000.0, 2200.0, 200.0, rate), 170.0, 0.52, rate)
	_mix(body, _ring(0.09, 1180.0, 70.0, rate), 172.0, 0.30, rate)
	_mix(body, _noise_burst(0.06, 1800.0, 500.0, 40.0, rate), 190.0, 0.18, rate)
	return _wav(body, rate)


# ---------------------------------------------------------------- movement

func _footfalls(rate: int, surface: String) -> Array:
	var variants: Array = []
	for index: int in range(2):
		var body := _buffer(0.2, rate)
		match surface:
			"grass":
				_mix(body, _noise_burst(0.05, 1500.0 + index * 180.0, 260.0, 46.0, rate), 0.0, 0.40, rate)
				_mix(body, _noise_burst(0.09, 700.0, 120.0, 18.0, rate), 6.0, 0.20, rate)
			"sand":
				_mix(body, _noise_burst(0.07, 950.0 + index * 120.0, 150.0, 38.0, rate), 0.0, 0.42, rate)
				_mix(body, _noise_burst(0.12, 480.0, 90.0, 15.0, rate), 5.0, 0.16, rate)
			"concrete":
				_mix(body, _noise_burst(0.012, 7200.0, 2800.0, 230.0, rate), 0.0, 0.40, rate)
				_mix(body, _ring(0.05, 210.0 + index * 26.0, 62.0, rate), 1.0, 0.30, rate)
				_mix(body, _noise_burst(0.07, 3200.0, 900.0, 34.0, rate), 8.0, 0.16, rate)
			"wood":
				_mix(body, _noise_burst(0.014, 4600.0, 1500.0, 190.0, rate), 0.0, 0.34, rate)
				_mix(body, _ring(0.11, 255.0 + index * 40.0, 34.0, rate), 1.0, 0.34, rate)
				_mix(body, _ring(0.07, 640.0 + index * 60.0, 58.0, rate), 2.0, 0.16, rate)
		variants.append(_wav(body, rate))
	return variants


# ---------------------------------------------------------------- feedback

func _flesh(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.14, rate)
	_mix(body, _noise_burst(0.02, 1300.0, 220.0, 110.0, rate), 0.0, 0.52, rate)
	_mix(body, _ring(0.07, 132.0, 48.0, rate), 1.0, 0.44, rate)
	return _wav(body, rate)


func _plate(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.24, rate)
	_mix(body, _noise_burst(0.01, 8000.0, 3200.0, 240.0, rate), 0.0, 0.40, rate)
	_mix(body, _ring(0.16, 3150.0, 30.0, rate), 0.0, 0.34, rate)
	_mix(body, _ring(0.12, 4700.0, 42.0, rate), 1.0, 0.20, rate)
	return _wav(body, rate)


func _kill(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.3, rate)
	_mix(body, _ring(0.1, 1180.0, 22.0, rate), 0.0, 0.30, rate)
	_mix(body, _ring(0.2, 1760.0, 14.0, rate), 55.0, 0.30, rate)
	_mix(body, _noise_burst(0.02, 6000.0, 2400.0, 160.0, rate), 0.0, 0.16, rate)
	return _wav(body, rate)


func _hurt(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.3, rate)
	_mix(body, _noise_burst(0.03, 2200.0, 500.0, 90.0, rate), 0.0, 0.50, rate)
	_mix(body, _ring(0.14, 96.0, 30.0, rate), 0.0, 0.55, rate)
	_mix(body, _ring(0.22, 2400.0, 12.0, rate), 4.0, 0.07, rate)
	return _wav(body, rate)


func _pickup(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.42, rate)
	_mix(body, _ring(0.14, 880.0, 16.0, rate), 0.0, 0.30, rate)
	_mix(body, _ring(0.26, 1320.0, 10.0, rate), 70.0, 0.30, rate)
	return _wav(body, rate)


func _heal_start(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.5, rate)
	_mix(body, _noise_burst(0.45, 3400.0, 1100.0, 4.5, rate), 0.0, 0.34, rate)
	_mix(body, _ring(0.1, 210.0, 30.0, rate), 0.0, 0.10, rate)
	return _wav(body, rate)


func _heal_done(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.6, rate)
	_mix(body, _ring(0.24, 660.0, 8.0, rate), 0.0, 0.24, rate)
	_mix(body, _ring(0.36, 990.0, 6.0, rate), 90.0, 0.24, rate)
	return _wav(body, rate)


func _heal_cancel(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.24, rate)
	_mix(body, _noise_burst(0.03, 900.0, 180.0, 70.0, rate), 0.0, 0.36, rate)
	_mix(body, _sine_sweep(0.16, 300.0, 130.0, 22.0, rate), 0.0, 0.26, rate)
	return _wav(body, rate)


func _zone_warn(rate: int) -> AudioStreamWAV:
	var body := _buffer(1.5, rate)
	_mix(body, _sine_sweep(1.3, 420.0, 980.0, 2.2, rate), 0.0, 0.30, rate)
	_mix(body, _sine_sweep(1.3, 845.0, 1965.0, 2.6, rate), 0.0, 0.12, rate)
	return _wav(body, rate)


func _zone_hurt(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.4, rate)
	_mix(body, _ring(0.3, 62.0, 9.0, rate), 0.0, 0.52, rate)
	_mix(body, _noise_burst(0.06, 500.0, 90.0, 30.0, rate), 0.0, 0.20, rate)
	return _wav(body, rate)


func _down(rate: int) -> AudioStreamWAV:
	var body := _buffer(1.6, rate)
	_mix(body, _sine_sweep(1.4, 330.0, 58.0, 3.4, rate), 0.0, 0.42, rate)
	_mix(body, _noise_burst(0.5, 800.0, 120.0, 7.0, rate), 0.0, 0.30, rate)
	_mix(body, _ring(0.4, 118.0, 7.0, rate), 120.0, 0.20, rate)
	return _wav(body, rate)


func _fanfare(rate: int, victory: bool) -> AudioStreamWAV:
	var body := _buffer(1.9, rate)
	var notes: Array[float] = []
	if victory:
		notes = [523.0, 659.0, 784.0, 1046.0]
	else:
		notes = [392.0, 330.0, 262.0, 196.0]
	for step: int in range(notes.size()):
		var at: float = step * 190.0
		_mix(body, _ring(0.62, notes[step], 5.0, rate), at, 0.26, rate)
		if victory:
			_mix(body, _ring(0.62, notes[step] * 2.0, 7.0, rate), at, 0.07, rate)
	return _wav(body, rate)


func _ui_click(rate: int, frequency: float) -> AudioStreamWAV:
	var body := _buffer(0.07, rate)
	_mix(body, _ring(0.035, frequency, 90.0, rate), 0.0, 0.28, rate)
	_mix(body, _noise_burst(0.006, frequency * 3.0, frequency, 300.0, rate), 0.0, 0.14, rate)
	return _wav(body, rate)


func _gull(rate: int) -> AudioStreamWAV:
	var body := _buffer(0.9, rate)
	for cry: int in range(2):
		var at: float = cry * 260.0
		_mix(body, _sine_sweep(0.26, 1650.0, 900.0, 11.0, rate), at, 0.22, rate)
		_mix(body, _noise_burst(0.14, 3200.0, 1200.0, 22.0, rate), at + 30.0, 0.06, rate)
	return _wav(body, rate)


# ---------------------------------------------------------------- ambience

## Loop LFO periods divide the buffer exactly, so the seam is inaudible without a
## crossfade.
func _waves() -> AudioStreamWAV:
	var rate := LOOP_RATE
	var body := _buffer(LOOP_SECONDS, rate)
	var base := _noise_burst(LOOP_SECONDS, 620.0, 60.0, 0.0, rate)
	var foam := _noise_burst(LOOP_SECONDS, 1400.0, 240.0, 0.0, rate)
	var period: float = 1.0 / LOOP_SECONDS
	for index: int in range(body.size()):
		var time: float = float(index) / rate
		var swell: float = 0.5 + 0.5 * sin(TAU * period * time * 3.0)
		var ripple: float = 0.5 + 0.5 * sin(TAU * period * time * 11.0 + 0.7)
		body[index] = base[index] * (0.30 + 0.34 * swell) + foam[index] * 0.22 * ripple * ripple
	return _wav(body, rate, true)


func _wind() -> AudioStreamWAV:
	var rate := LOOP_RATE
	var body := _buffer(LOOP_SECONDS, rate)
	var source := _noise_burst(LOOP_SECONDS, 380.0, 40.0, 0.0, rate)
	var bright := _noise_burst(LOOP_SECONDS, 1900.0, 600.0, 0.0, rate)
	var period: float = 1.0 / LOOP_SECONDS
	for index: int in range(body.size()):
		var time: float = float(index) / rate
		var gust: float = 0.5 + 0.5 * sin(TAU * period * time * 2.0 + 0.4)
		gust *= 0.72 + 0.28 * sin(TAU * period * time * 7.0)
		body[index] = source[index] * (0.34 + 0.40 * gust) + bright[index] * 0.10 * gust
	return _wav(body, rate, true)

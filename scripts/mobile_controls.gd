extends Control
## Touch-only overlay in TacticalHUD's 1280 x 720 logical coordinate space.

const STICK_CENTER := Vector2(126.0, 556.0)
const STICK_RADIUS: float = 70.0
const DEADZONE: float = 0.12
const BACKGROUND := Color(0.025, 0.047, 0.056, 0.35)
const OUTLINE := Color(0.85, 0.94, 0.95, 0.65)
const CYAN := Color("65dedc")
const BUTTONS: Array[Dictionary] = [
	{"role": "fire", "center": Vector2(1163, 472), "radius": 49.0, "label": "开火"},
	{"role": "fire_left", "center": Vector2(68, 285), "radius": 30.0, "label": "开火"},
	{"role": "aim", "center": Vector2(1080, 366), "radius": 31.0, "label": "开镜"},
	{"role": "jump", "center": Vector2(1180, 586), "radius": 32.0, "label": "跳跃"},
	{"role": "crouch", "center": Vector2(1080, 588), "radius": 31.0, "label": "蹲下"},
	{"role": "prone", "center": Vector2(780, 588), "radius": 31.0, "label": "卧倒"},
	{"role": "lean_left", "center": Vector2(1150, 285), "radius": 27.0, "label": "左探"},
	{"role": "lean_right", "center": Vector2(1225, 285), "radius": 27.0, "label": "右探"},
	{"role": "reload", "center": Vector2(980, 588), "radius": 31.0, "label": "换弹"},
	{"role": "heal", "center": Vector2(880, 588), "radius": 31.0, "label": "治疗"},
	{"role": "interact", "center": Vector2(977, 470), "radius": 32.0, "label": "拾取"},
	{"role": "pause", "center": Vector2(1010, 55), "radius": 22.0, "label": "II"},
]

var touch_roles: Dictionary = {}
var stick_vector: Vector2 = Vector2.ZERO
var aim_toggled: bool = false
var crouch_toggled: bool = false
var prone_toggled: bool = false

var _game: Node3D
var _enabled: bool = false
var _focused: bool = true
var _held_actions: Dictionary = {}
var _tap_release_frames: Dictionary = {}
var _font: SystemFont


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2(1280, 720)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_enabled = false
	_sync_enabled()


func setup(game: Node3D) -> void:
	release_all()
	_game = game
	# Force a visibility refresh even when replacing an already active game.
	_enabled = false
	_sync_enabled()


func _process(_delta: float) -> void:
	_sync_enabled()
	if not is_visible_in_tree() and not touch_roles.is_empty():
		release_all()


func _physics_process(_delta: float) -> void:
	_sync_enabled()
	# Keep taps alive through a complete physics tick, including quick touch-up.
	for action: String in _tap_release_frames.keys():
		if Engine.get_physics_frames() > int(_tap_release_frames[action]):
			_set_action(action, 0.0)
			_tap_release_frames.erase(action)


func _sync_enabled() -> void:
	var wanted: bool = is_instance_valid(_game) and _focused
	if wanted:
		wanted = bool(_game.get("mobile_mode")) and bool(_game.get("running")) \
			and not bool(_game.get("paused")) and not bool(_game.get("finished"))
	if is_inside_tree() and get_tree().paused:
		wanted = false
	if wanted != _enabled:
		_enabled = wanted
		if not wanted:
			release_all()
		visible = wanted
		queue_redraw()
	elif not wanted and visible:
		hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		release_all()
		_sync_enabled()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true
		_sync_enabled()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			release_all()
	elif what == NOTIFICATION_EXIT_TREE:
		release_all()


func release_all() -> void:
	# Release only actions this overlay pressed; leave desktop input alone.
	for action: String in _held_actions.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_held_actions.clear()
	_tap_release_frames.clear()
	touch_roles.clear()
	stick_vector = Vector2.ZERO
	aim_toggled = false
	crouch_toggled = false
	prone_toggled = false
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_sync_enabled()
	if not _enabled or not is_visible_in_tree():
		return
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var owned: bool = false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.canceled or not touch.pressed:
			owned = touch_roles.has(touch.index)
			if owned:
				_release_touch(touch.index)
		else:
			owned = _press_touch(touch.index, inverse * touch.position)
	else:
		var drag := event as InputEventScreenDrag
		owned = touch_roles.has(drag.index)
		if owned:
			var role: String = touch_roles[drag.index]
			if role == "stick":
				_update_stick(inverse * drag.position)
			elif role == "look" or role == "fire" or role == "fire_left" or role == "aim":
				# Transform vectors without translation; sensitivity is per logical pixel.
				_look(inverse.basis_xform(drag.relative))
	if owned:
		get_viewport().set_input_as_handled()


func _press_touch(index: int, point: Vector2) -> bool:
	if touch_roles.has(index):
		return true
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(point):
		return false
	# Buttons have priority over the right-side look area.
	for button: Dictionary in BUTTONS:
		var center: Vector2 = button["center"]
		if point.distance_to(center) <= float(button["radius"]):
			var role: String = button["role"]
			if touch_roles.values().has(role):
				return false
			touch_roles[index] = role
			match role:
				"fire", "fire_left":
					_set_action("fire", 1.0)
				"jump":
					_set_action("jump", 1.0)
				"aim":
					aim_toggled = not aim_toggled
					_set_action("aim", 1.0 if aim_toggled else 0.0)
				"crouch":
					prone_toggled = false
					_set_action("prone", 0.0)
					crouch_toggled = not crouch_toggled
					_set_action("crouch", 1.0 if crouch_toggled else 0.0)
					_apply_movement()
				"prone":
					prone_toggled = not prone_toggled
					if prone_toggled:
						crouch_toggled = false
						_set_action("crouch", 0.0)
					_set_action("prone", 1.0 if prone_toggled else 0.0)
					_apply_movement()
				"lean_left":
					_set_action("lean_left", 1.0)
				"lean_right":
					_set_action("lean_right", 1.0)
				"reload", "heal", "interact":
					_tap(role)
				"pause":
					release_all()
					_game.call("_pause")
					_sync_enabled()
			queue_redraw()
			return true
	if point.x < 300.0 and point.y > 350.0:
		if touch_roles.values().has("stick"):
			return false
		touch_roles[index] = "stick"
		_update_stick(point)
		return true
	if point.x > 350.0 and not touch_roles.values().has("look"):
		touch_roles[index] = "look"
		return true
	return false


func _release_touch(index: int) -> void:
	var role: String = touch_roles[index]
	touch_roles.erase(index)
	match role:
		"stick":
			stick_vector = Vector2.ZERO
			_apply_movement()
		"fire", "fire_left":
			if not touch_roles.values().has("fire") and not touch_roles.values().has("fire_left"):
				_set_action("fire", 0.0)
		"jump":
			_set_action("jump", 0.0)
		"lean_left":
			_set_action("lean_left", 0.0)
		"lean_right":
			_set_action("lean_right", 0.0)
	queue_redraw()


func _update_stick(point: Vector2) -> void:
	stick_vector = ((point - STICK_CENTER) / STICK_RADIUS).limit_length(1.0)
	if stick_vector.length() <= DEADZONE:
		stick_vector = Vector2.ZERO
	_apply_movement()
	queue_redraw()


func _apply_movement() -> void:
	_set_action("move_left", maxf(0.0, -stick_vector.x))
	_set_action("move_right", maxf(0.0, stick_vector.x))
	_set_action("move_forward", maxf(0.0, -stick_vector.y))
	_set_action("move_back", maxf(0.0, stick_vector.y))
	var sprint: bool = -stick_vector.y > 0.86 and not crouch_toggled and not prone_toggled \
		and not Input.is_action_pressed("crouch")
	_set_action("sprint", 1.0 if sprint else 0.0)


func _set_action(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
		_held_actions[action] = true
	elif _held_actions.has(action):
		Input.action_release(action)
		_held_actions.erase(action)


func _tap(action: String) -> void:
	# A second tap must produce another just-pressed edge.
	_set_action(action, 0.0)
	_set_action(action, 1.0)
	_tap_release_frames[action] = Engine.get_physics_frames() + 1
	if action == "interact" and InputMap.has_action(action):
		# Main handles interaction in _unhandled_input, not by polling Input.
		var action_event := InputEventAction.new()
		action_event.action = action
		action_event.pressed = true
		action_event.strength = 1.0
		Input.parse_input_event(action_event)


func _look(relative: Vector2) -> void:
	var player: Node3D = _game.get("player") as Node3D
	if not is_instance_valid(player):
		return
	var sensitivity: float = float(player.get("mouse_sensitivity")) * 0.004
	if aim_toggled or bool(player.get("aiming")):
		sensitivity *= 0.67
	player.rotate_y(-relative.x * sensitivity)
	player.set("_pitch", clampf(float(player.get("_pitch")) - relative.y * sensitivity,
		deg_to_rad(-85.0), deg_to_rad(85.0)))


func _draw() -> void:
	if not _enabled or _font == null:
		return
	var stick_color: Color = CYAN if touch_roles.values().has("stick") else OUTLINE
	_disc(STICK_CENTER, STICK_RADIUS, stick_color)
	draw_arc(STICK_CENTER, STICK_RADIUS * DEADZONE, 0.0, TAU, 32, OUTLINE, 1.0, true)
	var knob: Vector2 = STICK_CENTER + stick_vector * STICK_RADIUS
	_disc(knob, 25.0, stick_color)
	draw_line(knob - Vector2(8, 0), knob + Vector2(8, 0), stick_color, 1.0, true)
	draw_line(knob - Vector2(0, 8), knob + Vector2(0, 8), stick_color, 1.0, true)
	_label("上推疾跑", STICK_CENTER + Vector2(0, 97), 14, OUTLINE)
	_label("左手移动 · 右手滑屏瞄准", Vector2(166, 397), 14, OUTLINE)
	for button: Dictionary in BUTTONS:
		var role: String = button["role"]
		var active: bool = touch_roles.values().has(role)
		if role == "aim":
			active = aim_toggled
		elif role == "crouch":
			active = crouch_toggled
		elif role == "prone":
			active = prone_toggled
		var color: Color = CYAN if active else OUTLINE
		var center: Vector2 = button["center"]
		_disc(center, float(button["radius"]), color)
		_label(button["label"], center, 15 if role == "lean_left" or role == "lean_right" else 18, color)


func _disc(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, BACKGROUND)
	draw_arc(center, radius, 0.0, TAU, 64, color, 1.5, true)


func _label(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5
	draw_string(_font, center + Vector2(-width * 0.5, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

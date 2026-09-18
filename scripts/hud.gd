extends CanvasLayer

signal start_requested
signal resume_requested
signal restart_requested
signal quit_requested

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const WHITE: Color = Color("ecf2f2")
const MUTED: Color = Color("a1b2b5")
const CYAN: Color = Color("65dedc")
const AMBER: Color = Color("e9b76e")
const PANEL: Color = Color(0.025, 0.047, 0.056, 0.86)
const HAIRLINE: Color = Color(0.8, 0.93, 0.94, 0.21)

# Drawing uses a fixed logical canvas; actual viewport dimensions set its scale.
class HUDSurface extends Control:
	var host: Node

	func _draw() -> void:
		if is_instance_valid(host):
			host.call("_draw_surface", self)

# Assigned by main after setup; cache property names only, never live values.
var game: Node3D:
	set(value):
		game = value
		_cache_properties(game, _game_properties)

var _game_properties: Dictionary = {}
var _player: Node3D
var _world: Node3D
var _surface: HUDSurface
var _font: SystemFont
var _buttons: Array[Button] = []
var _properties: Dictionary = {}
var _configured: bool = false
var _active: bool = true
var _menu_visible: bool = false
var _pause_menu: bool = false
var _hit_time: float = 0.0
var _kill_hit: bool = false
var _message: String = ""
var _message_time: float = 0.0
var _clock: float = 0.0
var _heading: float = 0.0
var _position: Vector3 = Vector3.ZERO
var _health: float = 0.0
var _health_known: bool = false
var _armor: float = 0.0
var _medkits: int = 0
var _healing: bool = false
var _heal_left: float = 0.0
var _alive_count: int = -1
var _elapsed: float = 0.0
var _phase: String = "行动准备"
var _zone_radius: float = -1.0
var _zone_center: Vector3 = Vector3.ZERO
var _zone_next_in: float = -1.0
var _outside_zone: bool = false
var _damage_time: float = 0.0
var _damage_strength: float = 0.0
var _damage_source: Vector3 = Vector3.ZERO
var _result_visible: bool = false
var _result_victory: bool = false
var _result_kills: int = 0
var _result_time: float = 0.0
var _result_rank: int = -1
var _ammo: int = 30
var _reserve: int = 120
var _last_ammo: int = -1
var _shots: int = 0
var _hits: int = 0
var _kills: int = 0
var _display_shots: int = 0
var _display_hits: int = 0
var _display_kills: int = 0
var _speed: float = 0.0
var _spread: float = 4.0
var _ads: bool = false
var _crouching: bool = false
var _prone: bool = false
var _lean: float = 0.0
var _running: bool = false
var _reloading: bool = false
var _reload_progress: float = 0.0
var _reload_elapsed: float = 0.0
var _zone: String = "海岸"
var _zone_timer: float = 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_ui()


func setup(player: Node3D, world: Node3D) -> void:
	_player = player
	_world = world
	_cache_properties(_player, _properties)
	_cache_properties(game, _game_properties)
	_damage_time = 0.0
	_zone = "海岸"
	hide_result()
	_configured = true
	_last_ammo = -1
	_shots = 0
	_hits = 0
	_kills = 0
	_zone_timer = 0.0
	_reload_elapsed = 0.0
	_hit_time = 0.0
	_message_time = 0.0
	_ensure_ui()
	_sample_player(0.0)
	_surface.queue_redraw()


func show_menu(is_pause: bool = false) -> void:
	_menu_visible = true
	_pause_menu = is_pause
	if is_inside_tree():
		_ensure_ui()
		_update_buttons()
		_surface.queue_redraw()


func hide_menu() -> void:
	_menu_visible = false
	_update_buttons()
	if is_instance_valid(_surface):
		_surface.queue_redraw()


func notify_hit(killed: bool) -> void:
	_hits += 1
	if killed:
		_kills += 1
	_hit_time = 0.3
	_kill_hit = killed


func notify_damage(amount: float, source: Vector3) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	_damage_time = 0.6
	_damage_strength = clampf(amount / 40.0, 0.35, 1.0)
	_damage_source = source
	if is_instance_valid(_surface):
		_surface.queue_redraw()


func show_result(victory: bool, kills: int, time: float) -> void:
	_result_visible = true
	_result_victory = victory
	_result_kills = maxi(0, kills)
	_result_time = maxf(0.0, time) if is_finite(time) else 0.0
	var survivors: int = int(_game_number("alive_count", -1.0))
	_result_rank = 1 if victory else (survivors + 1 if survivors >= 0 else -1)
	_damage_time = 0.0
	show_menu(true)


func hide_result() -> void:
	_result_visible = false
	_result_rank = -1
	_damage_time = 0.0
	_update_buttons()
	if is_instance_valid(_surface):
		_surface.queue_redraw()


func notify_message(text: String) -> void:
	_message = text
	_message_time = 3.5


func set_active(value: bool) -> void:
	_active = value
	if is_instance_valid(_surface):
		_surface.queue_redraw()


func _ensure_ui() -> void:
	if is_instance_valid(_surface):
		return
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	_font.allow_system_fallback = true
	_surface = HUDSurface.new()
	_surface.name = "TacticalHUD"
	_surface.host = self
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.size = DESIGN_SIZE
	add_child(_surface)
	_add_button(Rect2(40.0, 355.0, 356.0, 54.0), true, _on_primary)
	_add_button(Rect2(40.0, 421.0, 232.0, 42.0), false, _on_restart)
	_add_button(Rect2(284.0, 421.0, 112.0, 42.0), false, _on_quit)
	_update_buttons()
	_fit_viewport()


func _add_button(rect: Rect2, primary: bool, callback: Callable) -> void:
	var button: Button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 18 if primary else 15)
	button.add_theme_color_override("font_color", Color("102528") if primary else WHITE)
	button.add_theme_color_override("font_hover_color", Color("102528") if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", Color("102528") if primary else WHITE)
	button.add_theme_color_override("font_focus_color", Color("102528") if primary else WHITE)
	button.add_theme_stylebox_override("normal", _button_style(CYAN if primary else Color(1, 1, 1, 0.045), primary))
	button.add_theme_stylebox_override("hover", _button_style(Color("9bf1e8") if primary else Color(0.3, 0.7, 0.7, 0.18), primary))
	button.add_theme_stylebox_override("pressed", _button_style(Color("46aaa9") if primary else Color(0.3, 0.7, 0.7, 0.28), primary))
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = WHITE
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(3.0)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	_surface.add_child(button)
	_buttons.append(button)


func _button_style(color: Color, primary: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = CYAN if primary else HAIRLINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _update_buttons() -> void:
	if _buttons.size() != 3:
		return
	_buttons[0].text = "再来一局" if _result_visible else ("继续行动" if _pause_menu else "开始行动")
	_buttons[1].text = "重新开局"
	_buttons[2].text = "退出"
	for button: Button in _buttons:
		button.visible = _menu_visible
		if not _menu_visible:
			button.release_focus()


func _on_primary() -> void:
	if _result_visible:
		restart_requested.emit()
	elif _pause_menu:
		resume_requested.emit()
	else:
		start_requested.emit()


func _on_restart() -> void:
	restart_requested.emit()


func _on_quit() -> void:
	quit_requested.emit()


func _fit_viewport() -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var viewport_size: Vector2 = viewport_rect.size
	if _game_flag("mobile_mode"):
		var available: Rect2 = viewport_rect
		# Display safe areas are physical pixels, not stretched viewport units.
		if OS.has_feature("android") and DisplayServer.get_name() != "headless" and not "--mobile-preview" in OS.get_cmdline_user_args():
			var screen: int = DisplayServer.window_get_current_screen()
			var screen_bounds: Rect2 = Rect2(Vector2(DisplayServer.screen_get_position(screen)), Vector2(DisplayServer.screen_get_size(screen)))
			var safe: Rect2 = Rect2(DisplayServer.get_display_safe_area()).intersection(screen_bounds)
			if screen_bounds.has_area() and safe.has_area():
				available = Rect2(viewport_rect.position + (safe.position - screen_bounds.position) / screen_bounds.size * viewport_size, safe.size / screen_bounds.size * viewport_size)
		var mobile_ratio: float = minf(available.size.x / (DESIGN_SIZE.x + 32.0), available.size.y / (DESIGN_SIZE.y + 32.0))
		_surface.scale = Vector2.ONE * mobile_ratio
		_surface.position = available.position + (available.size - DESIGN_SIZE * mobile_ratio) * 0.5
		return
	var ratio: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_surface.scale = Vector2.ONE * ratio
	_surface.position = (viewport_size - DESIGN_SIZE * ratio) * 0.5


func _process(delta: float) -> void:
	if not is_instance_valid(_surface):
		return
	_fit_viewport()
	_clock += delta
	_hit_time = maxf(0.0, _hit_time - delta)
	_message_time = maxf(0.0, _message_time - delta)
	_damage_time = maxf(0.0, _damage_time - delta)
	if _configured:
		_sample_player(0.0 if _menu_visible else delta)
		_sample_game()
	if _game_flag("mobile_mode"):
		# These desktop-only labels are owned and updated by main.
		for property: String in ["_status", "_loot_hint"]:
			var label: Variant = _object_value(game, _game_properties, property, null)
			if is_instance_valid(label) and label is Control:
				label.hide()
	_surface.queue_redraw()


func _cache_properties(object: Object, cache: Dictionary) -> void:
	cache.clear()
	if is_instance_valid(object):
		for entry: Dictionary in object.get_property_list():
			cache[String(entry["name"])] = true


func _object_value(object: Object, cache: Dictionary, property: String, fallback: Variant) -> Variant:
	if is_instance_valid(object) and cache.has(property):
		var value: Variant = object.get(property)
		if value != null:
			return value
	return fallback


func _game_number(property: String, fallback: float) -> float:
	var value: Variant = _object_value(game, _game_properties, property, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


func _game_flag(property: String) -> bool:
	var value: Variant = _object_value(game, _game_properties, property, false)
	return value if value is bool else false


func _sample_game() -> void:
	_alive_count = maxi(-1, int(_game_number("alive_count", -1.0)))
	_elapsed = maxf(0.0, _game_number("elapsed", 0.0))
	_zone_radius = _game_number("zone_radius", -1.0)
	_zone_next_in = _game_number("zone_next_in", -1.0)
	var center: Variant = _object_value(game, _game_properties, "zone_center", null)
	if center is Vector3 and center.is_finite():
		_zone_center = center
	else:
		_zone_radius = -1.0
	_outside_zone = _zone_radius >= 0.0 and Vector2(_position.x - _zone_center.x, _position.z - _zone_center.z).length() > _zone_radius
	if _game_flag("finished"):
		_phase = "行动胜利" if _game_flag("won") else "行动结束"
	elif _game_flag("paused"):
		_phase = "行动暂停"
	elif _game_flag("running"):
		_phase = "安全区收缩" if _zone_next_in <= 0.0 and _zone_radius >= 0.0 else "生存行动"
	else:
		_phase = "行动准备"


func _time_text(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	return "%02d:%02d" % [floori(float(total) / 60.0), total % 60]


func _value(names: Array[String], fallback: Variant) -> Variant:
	for property: String in names:
		var value: Variant = _object_value(_player, _properties, property, null)
		if value != null:
			return value
	return fallback


func _number(names: Array[String], fallback: float) -> float:
	var value: Variant = _value(names, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


func _flag(names: Array[String], fallback: bool = false) -> bool:
	var value: Variant = _value(names, fallback)
	if value is bool:
		return bool(value)
	return fallback


func _sample_player(delta: float) -> void:
	if not is_instance_valid(_player):
		_health_known = false
		_health = 0.0
		_armor = 0.0
		_medkits = 0
		_healing = false
		return
	_position = _player.global_position
	_heading = wrapf(-rad_to_deg(_player.global_rotation.y), 0.0, 360.0)
	var health_value: float = _number(["health", "current_health", "hp"], -1.0)
	_health_known = health_value >= 0.0
	_health = clampf(health_value, 0.0, 100.0)
	_armor = maxf(0.0, _number(["armor"], 0.0))
	_medkits = maxi(0, int(_number(["medkits"], 0.0)))
	_healing = _flag(["healing"])
	_heal_left = maxf(0.0, _number(["heal_left"], 0.0))
	_ammo = maxi(0, int(_number(["ammo", "ammo_in_mag", "magazine_ammo", "current_ammo", "mag_ammo"], 30.0)))
	_reserve = maxi(0, int(_number(["reserve_ammo", "ammo_reserve", "reserve"], 120.0)))
	if _last_ammo >= 0 and _ammo < _last_ammo:
		_shots += _last_ammo - _ammo
	_last_ammo = _ammo
	_display_shots = maxi(0, int(_number(["shots_fired", "total_shots", "shots"], float(_shots))))
	_display_hits = maxi(0, int(_number(["hits", "shots_hit", "total_hits"], float(_hits))))
	_display_kills = maxi(0, int(_number(["kills", "total_kills"], float(_kills))))
	_ads = _flag(["is_ads", "ads", "aiming", "is_aiming"])
	_crouching = _flag(["is_crouching", "crouching", "crouched"])
	_prone = _flag(["prone", "is_prone"])
	_lean = float(_value(["lean"], 0.0))
	var velocity: Variant = _value(["velocity"], Vector3.ZERO)
	_speed = Vector2(velocity.x, velocity.z).length() if velocity is Vector3 else 0.0
	_running = _flag(["is_sprinting", "sprinting", "is_running", "running"], _speed > 5.5)
	_reloading = _flag(["is_reloading", "reloading"])
	var duration: float = maxf(0.01, _number(["reload_duration", "reload_time"], 1.8))
	if _reloading:
		_reload_elapsed += delta
		var remaining: float = _number(["_reload_left", "reload_time_left", "reload_remaining", "reload_timer"], -1.0)
		var fallback_progress: float = 1.0 - remaining / duration if remaining >= 0.0 else _reload_elapsed / duration
		_reload_progress = clampf(_number(["reload_progress"], fallback_progress), 0.0, 1.0)
	else:
		_reload_elapsed = 0.0
		_reload_progress = 0.0
	var target_spread: float = 4.0 + minf(_speed * 1.8, 15.0)
	_spread = lerpf(_spread, target_spread, 1.0 - exp(-12.0 * delta))
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = 0.2
		if is_instance_valid(_world) and _world.has_method("get_zone"):
			var zone_value: Variant = _world.call("get_zone", _position)
			if zone_value is String or zone_value is StringName:
				_zone = str(zone_value)


func _text(surface: Control, text: String, position: Vector2, font_size: int = 14, color: Color = WHITE, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# Shadow keeps the light type readable against sunlit terrain.
	surface.draw_string(_font, position + Vector2(0, 1), text, alignment, width, font_size, Color(0, 0, 0, color.a * 0.7))
	surface.draw_string(_font, position, text, alignment, width, font_size, color)


func _line(surface: Control, start: Vector2, end: Vector2, color: Color = HAIRLINE, width: float = 1.0) -> void:
	surface.draw_line(start, end, color, width, true)


func _fit_text(text: String, font_size: int, width: float) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var result: String = text
	while result.length() > 0 and _font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		result = result.left(result.length() - 1)
	return result + "…"


func _draw_surface(surface: Control) -> void:
	if _configured and _active and not _menu_visible:
		_draw_damage(surface)
		var mobile: bool = _game_flag("mobile_mode")
		if mobile:
			_draw_mobile_identity(surface)
			_draw_mobile_status(surface)
			_draw_mobile_weapon(surface)
		else:
			_draw_identity(surface)
			_draw_player_status(surface)
			_draw_weapon(surface)
			_draw_statistics(surface)
		_draw_compass(surface)
		_draw_map(surface)
		_draw_reticle(surface)
		_draw_message(surface)
	if _menu_visible:
		_draw_menu(surface)
		if _result_visible:
			_draw_result(surface)


func _draw_damage(surface: Control) -> void:
	if _damage_time <= 0.0:
		return
	var alpha: float = (_damage_time / 0.6) * _damage_strength
	# A fixed number of non-overlapping strips avoids full-screen textures.
	for index: int in range(10):
		var inset: float = float(index) * 5.0
		var color: Color = Color(0.85, 0.06, 0.06, alpha * 0.48 * pow(1.0 - float(index) / 10.0, 2.0))
		surface.draw_rect(Rect2(inset, inset, 1280.0 - inset * 2.0, 5.0), color)
		surface.draw_rect(Rect2(inset, 715.0 - inset, 1280.0 - inset * 2.0, 5.0), color)
		surface.draw_rect(Rect2(inset, inset + 5.0, 5.0, 710.0 - inset * 2.0), color)
		surface.draw_rect(Rect2(1275.0 - inset, inset + 5.0, 5.0, 710.0 - inset * 2.0), color)
	if not is_instance_valid(_player) or not _damage_source.is_finite():
		return
	var offset: Vector3 = _damage_source - _player.global_position
	var direction: Vector2 = Vector2(offset.x, offset.z)
	if direction.length_squared() < 0.01:
		return
	# World north is -Z; rotate by the inverse of the player's map heading.
	direction = direction.normalized().rotated(_player.global_rotation.y)
	var tangent: Vector2 = Vector2(-direction.y, direction.x)
	var center: Vector2 = DESIGN_SIZE * 0.5
	var arrow: PackedVector2Array = PackedVector2Array([
		center + direction * 91.0,
		center + direction * 73.0 + tangent * 9.0,
		center + direction * 78.0,
		center + direction * 73.0 - tangent * 9.0
	])
	surface.draw_colored_polygon(arrow, Color(1.0, 0.22, 0.18, alpha))


func _draw_identity(surface: Control) -> void:
	surface.draw_rect(Rect2(24, 24, 290, 66), Color(0.02, 0.04, 0.05, 0.55))
	_line(surface, Vector2(24, 24), Vector2(24, 90), CYAN, 2.0)
	_text(surface, "COASTLINE / 海岸行动", Vector2(39, 49), 19)
	_text(surface, "海岛生存 / 单人 AI 对抗", Vector2(40, 73), 12, MUTED)


func _draw_compass(surface: Control) -> void:
	var font_size: int = 15 if _game_flag("mobile_mode") else 12
	surface.draw_rect(Rect2(430, 19, 420, 62), Color(0.02, 0.04, 0.05, 0.4))
	var labels: Array[String] = ["北 N", "NE", "东 E", "SE", "南 S", "SW", "西 W", "NW"]
	for tick: int in range(0, 360, 15):
		var difference: float = wrapf(float(tick) - _heading, -180.0, 180.0)
		if absf(difference) > 58.0:
			continue
		var x: float = 640.0 + difference * 3.3
		var major: bool = tick % 45 == 0
		_line(surface, Vector2(x, 61), Vector2(x, 53 if major else 57), MUTED)
		if major:
			_text(surface, labels[int(float(tick) / 45.0)], Vector2(x - 25, 45), font_size, WHITE, 50, HORIZONTAL_ALIGNMENT_CENTER)
	surface.draw_colored_polygon(PackedVector2Array([Vector2(636, 21), Vector2(644, 21), Vector2(640, 27)]), CYAN)
	_text(surface, "%03d°" % (int(round(_heading)) % 360), Vector2(603, 78), font_size, CYAN, 74, HORIZONTAL_ALIGNMENT_CENTER)


func _map_point(x: float, z: float) -> Vector2:
	return Vector2(1082, 49) + Vector2((x + 180.0) / 360.0, (z + 180.0) / 360.0) * 148.0


func _map_block(surface: Control, x: float, z: float, dimensions: Vector2) -> void:
	var center: Vector2 = _map_point(x, z)
	var rect: Rect2 = Rect2(center - dimensions * 0.5, dimensions)
	surface.draw_rect(rect, Color("718486"))
	surface.draw_rect(rect, Color(0.8, 0.9, 0.9, 0.3), false, 1.0)


func _draw_map(surface: Control) -> void:
	var font_size: int = 15 if _game_flag("mobile_mode") else 11
	surface.draw_rect(Rect2(1068, 25, 178, 216), PANEL)
	surface.draw_rect(Rect2(1068, 25, 178, 216), HAIRLINE, false, 1.0)
	_text(surface, "SECTOR 07", Vector2(1082, 41), font_size, MUTED)
	_text(surface, "N ↑", Vector2(1203, 41), font_size, CYAN)
	surface.draw_rect(Rect2(1082, 49, 148, 148), Color("173941"))
	var terrain: PackedVector2Array = PackedVector2Array([
		_map_point(-180, -180), _map_point(180, -180), _map_point(180, 52),
		_map_point(116, 82), _map_point(62, 69), _map_point(16, 96),
		_map_point(-38, 77), _map_point(-98, 116), _map_point(-153, 90), _map_point(-180, 55)
	])
	surface.draw_colored_polygon(terrain, Color("344747"))
	var coast: PackedVector2Array = PackedVector2Array([
		_map_point(-180, 55), _map_point(-153, 90), _map_point(-98, 116),
		_map_point(-38, 77), _map_point(16, 96), _map_point(62, 69), _map_point(116, 82), _map_point(180, 52)
	])
	surface.draw_polyline(coast, Color("96a8a1"), 1.2, true)
	for grid: int in range(1, 4):
		var offset: float = float(grid) * 37.0
		_line(surface, Vector2(1082 + offset, 49), Vector2(1082 + offset, 197), Color(0.8, 0.9, 0.9, 0.055))
		_line(surface, Vector2(1082, 49 + offset), Vector2(1230, 49 + offset), Color(0.8, 0.9, 0.9, 0.055))
	var road: PackedVector2Array = PackedVector2Array([_map_point(-127, 40), _map_point(128, 40)])
	surface.draw_polyline(road, Color("82928b"), 2.0, true)
	_line(surface, _map_point(1, 65), _map_point(1, -44), Color("82928b"), 2.0)
	_line(surface, _map_point(1, 2), _map_point(61, 2), Color("82928b"), 1.5)
	var hill: Vector2 = _map_point(-30, -78)
	surface.draw_arc(hill, 14, 0, TAU, 32, Color(0.65, 0.76, 0.7, 0.22), 1.0, true)
	surface.draw_arc(hill, 9, 0, TAU, 24, Color(0.65, 0.76, 0.7, 0.22), 1.0, true)
	_map_block(surface, -28, 14, Vector2(7, 7))
	_map_block(surface, -49, 3, Vector2(5, 7))
	_map_block(surface, -40, 35, Vector2(5, 5))
	_map_block(surface, 34, -12, Vector2(11, 8))
	_draw_safety_circle(surface)
	_text(surface, "房区", _map_point(-130, 18), font_size, WHITE)
	_text(surface, "仓库", _map_point(56, -12), font_size, WHITE)
	_text(surface, "山坡", hill + Vector2(-12, -17), font_size, WHITE)
	_text(surface, "南 / 海域", Vector2(1130, 190), font_size, Color("90bcc3"))
	var marker: Vector2 = _map_point(clampf(_position.x, -174, 174), clampf(_position.z, -174, 174))
	var angle: float = deg_to_rad(_heading)
	var triangle: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [Vector2(0, -7), Vector2(4.5, 5), Vector2(0, 2.5), Vector2(-4.5, 5)]:
		triangle.append(marker + point.rotated(angle))
	surface.draw_circle(marker, 8.5, Color(0, 0, 0, 0.6))
	surface.draw_colored_polygon(triangle, CYAN)
	var countdown: String = "安全区等待同步"
	if _zone_radius >= 0.0:
		countdown = "下次收缩 " + _time_text(ceilf(_zone_next_in)) if _zone_next_in > 0.0 else "安全区正在收缩"
	_text(surface, countdown, Vector2(1082, 214), font_size, AMBER if _outside_zone else CYAN)
	var zone_status: String = "安全区半径 %.0f m" % _zone_radius if _zone_radius >= 0.0 else "安全区数据待同步"
	_text(surface, "圈外 · 尽快转移" if _outside_zone else zone_status, Vector2(1082, 232), font_size, AMBER if _outside_zone else MUTED)


var _circle_center: Vector3 = Vector3.INF
var _circle_radius: float = -2.0
var _circle_lines: Array[PackedVector2Array] = []


func _draw_safety_circle(surface: Control) -> void:
	if _zone_radius < 0.0:
		return
	# Clip once per zone change; do not clamp the circle's center or radius.
	if _circle_center != _zone_center or _circle_radius != _zone_radius:
		_circle_center = _zone_center
		_circle_radius = _zone_radius
		var points: PackedVector2Array = PackedVector2Array()
		var center: Vector2 = _map_point(_zone_center.x, _zone_center.z)
		var radius: float = _zone_radius * 148.0 / 360.0
		for index: int in range(65):
			points.append(center + Vector2.from_angle(TAU * float(index) / 64.0) * radius)
		var bounds: PackedVector2Array = PackedVector2Array([Vector2(1082, 49), Vector2(1230, 49), Vector2(1230, 197), Vector2(1082, 197)])
		_circle_lines = Geometry2D.intersect_polyline_with_polygon(points, bounds)
	for points: PackedVector2Array in _circle_lines:
		if points.size() >= 2:
			surface.draw_polyline(points, CYAN, 1.5, true)


func _draw_mobile_identity(surface: Control) -> void:
	surface.draw_rect(Rect2(24, 24, 280, 100), PANEL)
	_line(surface, Vector2(24, 24), Vector2(24, 124), CYAN, 2.0)
	_text(surface, "COASTLINE / 海岸行动", Vector2(38, 49), 18)
	var survivors: String = "%02d" % _alive_count if _alive_count >= 0 else "--"
	_text(surface, "存活 " + survivors, Vector2(38, 77), 18)
	_text(surface, "淘汰 %02d" % _display_kills, Vector2(182, 77), 18, AMBER)
	_text(surface, _phase, Vector2(38, 109), 15, MUTED)
	_text(surface, _time_text(_elapsed), Vector2(217, 109), 15, CYAN)


func _draw_mobile_status(surface: Control) -> void:
	surface.draw_rect(Rect2(360, 636, 450, 48), PANEL)
	var health_color: Color = CYAN if _health > 30.0 else AMBER
	_text(surface, "生命 %03d" % int(_health) if _health_known else "生命 --", Vector2(374, 658), 17, health_color)
	_text(surface, "护甲 %03d" % int(_armor), Vector2(515, 658), 17, CYAN)
	_text(surface, "医疗包 ×%d" % _medkits, Vector2(660, 658), 17)
	surface.draw_rect(Rect2(374, 670, 122, 4), HAIRLINE)
	surface.draw_rect(Rect2(374, 670, 122 * _health / 100.0, 4), health_color)
	surface.draw_rect(Rect2(515, 670, 122, 4), HAIRLINE)
	surface.draw_rect(Rect2(515, 670, 122 * clampf(_armor / 100.0, 0.0, 1.0), 4), CYAN)
	var hint: String = ""
	if _healing:
		hint = "治疗中 · 剩余 %.1f 秒" % _heal_left
	elif is_instance_valid(_object_value(game, _game_properties, "_closest_loot", null)):
		hint = "拾取补给 · 弹药 +60 · 医疗包 +1 · 护甲 +20"
	elif _health_known and _health < 100.0:
		hint = "医疗包耗尽" if _medkits == 0 else "使用医疗包恢复生命"
	if not hint.is_empty():
		surface.draw_rect(Rect2(360, 594, 450, 30), PANEL)
		_text(surface, _fit_text(hint, 16, 426), Vector2(372, 615), 16, AMBER if _healing else WHITE, 426, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_mobile_weapon(surface: Control) -> void:
	surface.draw_rect(Rect2(1050, 260, 195, 58), PANEL)
	_text(surface, "%02d" % _ammo, Vector2(1062, 290), 28, AMBER if _ammo <= 5 else WHITE)
	_text(surface, "/ %03d" % _reserve, Vector2(1120, 289), 18, MUTED, 111, HORIZONTAL_ALIGNMENT_RIGHT)
	var status: String = "换弹中 %d%%" % int(_reload_progress * 100.0) if _reloading else ("弹匣已空" if _ammo == 0 else "AR-01 / 自动")
	_text(surface, status, Vector2(1062, 310), 15, AMBER if _reloading or _ammo == 0 else CYAN)
	if _reloading:
		surface.draw_rect(Rect2(1050, 315, 195 * _reload_progress, 3), AMBER)


func _draw_player_status(surface: Control) -> void:
	surface.draw_rect(Rect2(24, 554, 254, 131), PANEL)
	_line(surface, Vector2(24, 554), Vector2(24, 685), CYAN, 2.0)
	_text(surface, _fit_text(_zone, 14, 151), Vector2(39, 577), 14)
	var state: String = "卧倒" if _prone else ("蹲伏" if _crouching else ("奔跑" if _running else "站立"))
	if absf(_lean) > 0.35:
		state += " · 探头"
	if _health_known and _health <= 0.0:
		state = "已淘汰"
	_text(surface, state, Vector2(197, 577), 12, MUTED, 66, HORIZONTAL_ALIGNMENT_RIGHT)
	_line(surface, Vector2(39, 587), Vector2(263, 587))
	_text(surface, "生命", Vector2(39, 613), 12, MUTED)
	_text(surface, "%03d" % int(_health) if _health_known else "—", Vector2(78, 614), 23, WHITE if _health > 30.0 else AMBER)
	_text(surface, "护甲 %03d" % int(_armor), Vector2(165, 613), 14, CYAN)
	surface.draw_rect(Rect2(39, 623, 224, 4), HAIRLINE)
	surface.draw_rect(Rect2(39, 623, 224 * _health / 100.0, 4), CYAN if _health > 30.0 else AMBER)
	_text(surface, "H 医疗包 ×%d" % _medkits, Vector2(39, 650), 12, WHITE)
	_text(surface, "F 拾取补给", Vector2(174, 650), 12, MUTED)
	var medical: String = "治疗中 · 剩余 %.1f 秒" % _heal_left if _healing else ("医疗包耗尽" if _medkits == 0 else "受伤时使用医疗包恢复生命")
	_text(surface, medical, Vector2(39, 673), 11, AMBER if _healing else MUTED)
	surface.draw_rect(Rect2(295, 657, 696, 28), Color(0.02, 0.04, 0.05, 0.64))
	_text(surface, "WASD 移动 · Shift 奔跑 · 空格 跳跃 · C 蹲伏 · Z 卧倒 · Q/E 探头 · 右键 瞄准 · R 换弹 · F 拾取 · Esc 菜单", Vector2(307, 676), 12, Color("c1cdcf"))


func _draw_weapon(surface: Control) -> void:
	surface.draw_rect(Rect2(1020, 570, 226, 115), PANEL)
	_text(surface, "AR-01 / 5.56", Vector2(1037, 592), 14, MUTED)
	_line(surface, Vector2(1037, 603), Vector2(1229, 603))
	_text(surface, "%02d" % _ammo, Vector2(1036, 653), 48, AMBER if _ammo <= 5 else WHITE)
	_text(surface, "/  %03d" % _reserve, Vector2(1120, 650), 20, MUTED, 107, HORIZONTAL_ALIGNMENT_RIGHT)
	var status: String = "换弹中  %d%%" % int(_reload_progress * 100.0) if _reloading else ("弹匣已空" if _ammo == 0 else "自动 / 就绪")
	_text(surface, status, Vector2(1037, 675), 11, AMBER if _reloading or _ammo == 0 else CYAN)
	if _reloading:
		surface.draw_rect(Rect2(1140, 668, 88, 3), HAIRLINE)
		surface.draw_rect(Rect2(1140, 668, 88 * _reload_progress, 3), AMBER)


func _draw_statistics(surface: Control) -> void:
	surface.draw_rect(Rect2(24, 102, 290, 72), PANEL)
	var survivors: String = "%02d" % _alive_count if _alive_count >= 0 else "—"
	_text(surface, "存活  " + survivors, Vector2(39, 132), 21, WHITE)
	_text(surface, "淘汰  %02d" % _display_kills, Vector2(189, 132), 19, AMBER)
	_text(surface, _phase, Vector2(39, 158), 12, MUTED)
	_text(surface, _time_text(_elapsed), Vector2(223, 158), 12, CYAN, 76, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_reticle(surface: Control) -> void:
	var center: Vector2 = DESIGN_SIZE * 0.5
	if not _ads:
		var color: Color = Color(0.94, 0.99, 1.0, 0.9)
		for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_line(surface, center + axis * _spread, center + axis * (_spread + 5.0), Color(0, 0, 0, 0.55), 3.0)
			_line(surface, center + axis * _spread, center + axis * (_spread + 5.0), color, 1.0)
		surface.draw_circle(center, 1.0, WHITE)
	if _hit_time > 0.0:
		var alpha: float = clampf(_hit_time / 0.18, 0.0, 1.0)
		var color: Color = AMBER if _kill_hit else WHITE
		color.a = alpha
		var distance: float = 7.0 + (0.3 - _hit_time) * 10.0
		for axis: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_line(surface, center + axis * distance, center + axis * (distance + 4.0), color, 1.5)
		if _kill_hit:
			_text(surface, "淘汰敌人", center + Vector2(-50, 42), 12, color, 100, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_message(surface: Control) -> void:
	if _message_time <= 0.0 or _message.is_empty():
		return
	var alpha: float = minf(1.0, _message_time)
	var message: String = _message.replace("\n", " ")
	var font_size: int = 14
	if _game_flag("mobile_mode"):
		message = message.replace("H 治疗", "医疗包治疗").replace("H 医疗包", "医疗包").replace("E 搜取", "拾取").replace("E 拾取", "拾取").replace("F 搜取", "拾取").replace("F 拾取", "拾取")
		font_size = 16
	surface.draw_rect(Rect2(440, 113, 400, 35), Color(0.02, 0.04, 0.05, 0.8 * alpha))
	_line(surface, Vector2(440, 113), Vector2(440, 148), Color(CYAN, alpha), 2.0)
	_text(surface, _fit_text(message, font_size, 370), Vector2(454, 136), font_size, Color(WHITE, alpha), 372, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_menu(surface: Control) -> void:
	surface.draw_rect(Rect2(0, 0, 440, 720), Color(0.018, 0.031, 0.038, 0.93))
	_line(surface, Vector2(440, 0), Vector2(440, 720), HAIRLINE)
	_line(surface, Vector2(40, 46), Vector2(69, 46), CYAN, 3.0)
	_text(surface, "COASTLINE PROTOCOL / 01", Vector2(40, 79), 12, CYAN)
	_text(surface, "海岸行动", Vector2(35, 153), 54)
	_text(surface, "单人生存 · AI 对抗", Vector2(40, 189), 19, MUTED)
	_line(surface, Vector2(40, 214), Vector2(396, 214))
	_text(surface, "房区搜寻、利用掩体、留意枪声", Vector2(40, 246), 15, Color("c4ced0"))
	_text(surface, "安全区持续收缩，成为最后的幸存者", Vector2(40, 273), 15, Color("c4ced0"))
	var chips: Array[String] = ["自主巡逻", "交火追击", "安全区", "补给"]
	var x: float = 40.0
	for chip: String in chips:
		var width: float = _font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20.0
		surface.draw_rect(Rect2(x, 301, width, 26), Color(0.7, 0.87, 0.87, 0.055))
		surface.draw_rect(Rect2(x, 301, width, 26), HAIRLINE, false, 1.0)
		_text(surface, chip, Vector2(x + 10, 319), 12, MUTED)
		x += width + 8.0
	_text(surface, "行动已结算" if _result_visible else ("行动已暂停" if _pause_menu else "行动准备就绪"), Vector2(40, 344), 11, AMBER)
	_line(surface, Vector2(40, 489), Vector2(396, 489))
	if _game_flag("mobile_mode"):
		_text(surface, "触屏操作", Vector2(40, 518), 17, WHITE)
		_text(surface, "左摇杆移动 / 上推疾跑", Vector2(40, 554), 17, MUTED)
		_text(surface, "右滑屏瞄准 / 开火键拖动压枪", Vector2(40, 588), 17, MUTED)
		_text(surface, "点按开镜 / 蹲下", Vector2(40, 622), 17, MUTED)
		_text(surface, "拾取 / 医疗包", Vector2(40, 656), 17, MUTED)
	else:
		_text(surface, "操作指南", Vector2(40, 518), 13, WHITE)
		_menu_key(surface, "WASD", "移动", Vector2(40, 550))
		_menu_key(surface, "Shift", "奔跑", Vector2(226, 550))
		_menu_key(surface, "空格", "跳跃", Vector2(40, 580))
		_menu_key(surface, "C", "蹲伏", Vector2(226, 580))
		_menu_key(surface, "右键", "瞄准", Vector2(40, 610))
		_menu_key(surface, "R", "换弹", Vector2(226, 610))
		_menu_key(surface, "左键", "射击", Vector2(40, 640))
		_menu_key(surface, "Esc", "菜单", Vector2(226, 640))
		_menu_key(surface, "H", "医疗包", Vector2(40, 670))
		_menu_key(surface, "F", "拾取补给", Vector2(226, 670))
		_menu_key(surface, "Z", "卧倒", Vector2(412, 550))
		_menu_key(surface, "Q / E", "左右探头", Vector2(412, 580))
		_menu_key(surface, "F11", "全屏", Vector2(412, 610))
	_text(surface, "原创低多边形场景 · 单人离线 · Godot 4", Vector2(40, 703), 11, MUTED)
	if not _result_visible:
		surface.draw_rect(Rect2(920, 625, 326, 60), Color(0.02, 0.04, 0.05, 0.68))
		_line(surface, Vector2(920, 625), Vector2(920, 685), CYAN, 2.0)
		_text(surface, "SECTOR 07 / COASTAL SURVIVAL", Vector2(938, 650), 12, WHITE)
		_text(surface, "海岛生存  /  单人 AI 对抗", Vector2(938, 672), 11, MUTED)


func _draw_result(surface: Control) -> void:
	var accent: Color = CYAN if _result_victory else AMBER
	surface.draw_rect(Rect2(475, 210, 470, 240), PANEL)
	surface.draw_rect(Rect2(475, 210, 470, 240), HAIRLINE, false, 1.0)
	_line(surface, Vector2(475, 210), Vector2(945, 210), accent, 3.0)
	_text(surface, "行动胜利" if _result_victory else "行动结算", Vector2(503, 246), 13, accent)
	_text(surface, "最后的幸存者" if _result_victory else "本次行动结束", Vector2(502, 292), 32, WHITE)
	_line(surface, Vector2(503, 312), Vector2(917, 312))
	_text(surface, "淘汰敌人", Vector2(503, 340), 12, MUTED)
	_text(surface, "%02d" % _result_kills, Vector2(503, 377), 29, accent)
	_text(surface, "生存时间", Vector2(648, 340), 12, MUTED)
	_text(surface, _time_text(_result_time), Vector2(648, 377), 29, WHITE)
	_text(surface, "生存排名", Vector2(802, 340), 12, MUTED)
	_text(surface, "#%d" % _result_rank if _result_rank > 0 else "—", Vector2(802, 377), 29, WHITE)
	_text(surface, "整备装备，再次出发。", Vector2(503, 423), 13, MUTED)


func _menu_key(surface: Control, key: String, label: String, position: Vector2) -> void:
	_text(surface, key, position, 12, CYAN)
	_text(surface, label, position + Vector2(75, 0), 12, MUTED)

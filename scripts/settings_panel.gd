extends Control

const CONFIG_PATH: String = "user://preferences.cfg"
const CONFIG_SECTION: String = "settings"
const DEFAULTS: Dictionary = {
	"sensitivity": 1.0,
	"fov": 78.0,
	"volume": 80.0,
	"sfx": 100.0,
	"ambient": 70.0,
	"interface": 90.0,
	"motion": true,
}
const WHITE: Color = Color("ecf2f2")
const MUTED: Color = Color("a1b2b5")
const CYAN: Color = Color("65dedc")

var sensitivity_slider: HSlider
var fov_slider: HSlider
var volume_slider: HSlider
var sfx_slider: HSlider
var ambient_slider: HSlider
var interface_slider: HSlider
var motion_toggle: CheckButton

var _player: Node3D
var _config: ConfigFile = ConfigFile.new()
var _panel_style: StyleBoxFlat
var _sensitivity_value: Label
var _fov_value: Label
var _volume_value: Label
var _sfx_value: Label
var _ambient_value: Label
var _interface_value: Label
var _configured: bool = false


func _init() -> void:
	position = Vector2(475.0, 132.0)
	size = Vector2(360.0, 470.0)
	custom_minimum_size = size
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(player: Node3D) -> void:
	if _configured:
		return
	_player = player
	_build_ui()
	var error: Error = _config.load(CONFIG_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load preferences: %s" % error_string(error))
	var motion: Variant = _config.get_value(CONFIG_SECTION, "motion", DEFAULTS["motion"])
	_set_values({
		"sensitivity": _load_number("sensitivity", 0.25, 2.5),
		"fov": _load_number("fov", 65.0, 100.0),
		"volume": _load_number("volume", 0.0, 100.0),
		"sfx": _load_number("sfx", 0.0, 100.0),
		"ambient": _load_number("ambient", 0.0, 100.0),
		"interface": _load_number("interface", 0.0, 100.0),
		"motion": motion if motion is bool else DEFAULTS["motion"],
	})
	_apply_values()
	# Connect only after loading; initialization must never write preferences.
	sensitivity_slider.value_changed.connect(_on_slider_changed)
	fov_slider.value_changed.connect(_on_slider_changed)
	volume_slider.value_changed.connect(_on_slider_changed)
	sfx_slider.value_changed.connect(_on_slider_changed)
	ambient_slider.value_changed.connect(_on_slider_changed)
	interface_slider.value_changed.connect(_on_slider_changed)
	motion_toggle.toggled.connect(_on_motion_changed)
	_configured = true


func get_values() -> Dictionary:
	if not is_instance_valid(sensitivity_slider):
		return DEFAULTS.duplicate()
	return {
		"sensitivity": sensitivity_slider.value,
		"fov": fov_slider.value,
		"volume": volume_slider.value,
		"sfx": sfx_slider.value,
		"ambient": ambient_slider.value,
		"interface": interface_slider.value,
		"motion": motion_toggle.button_pressed,
	}


func reset_defaults() -> void:
	if not _configured:
		return
	_set_values(DEFAULTS)
	_apply_values()
	_save_values()


func _build_ui() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	font.allow_system_fallback = true
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.025, 0.047, 0.056, 0.96)
	_panel_style.border_color = Color(0.8, 0.93, 0.94, 0.21)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(2)

	var title: Label = _label("操作与音效", Rect2(20, 13, 320, 28))
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", WHITE)

	_label("鼠标灵敏度", Rect2(20, 51, 220, 22))
	_sensitivity_value = _value_label(51.0)
	sensitivity_slider = _slider(77.0, 0.25, 2.5, 0.05)
	sensitivity_slider.name = "SensitivitySlider"

	_label("视野 FOV", Rect2(20, 105, 220, 22))
	_fov_value = _value_label(105.0)
	fov_slider = _slider(131.0, 65.0, 100.0, 1.0)
	fov_slider.name = "FOVSlider"

	_label("主音量", Rect2(20, 159, 220, 22))
	_volume_value = _value_label(159.0)
	volume_slider = _slider(185.0, 0.0, 100.0, 1.0)
	volume_slider.name = "VolumeSlider"

	_label("枪声与脚步", Rect2(20, 213, 220, 22))
	_sfx_value = _value_label(213.0)
	sfx_slider = _slider(239.0, 0.0, 100.0, 1.0)
	sfx_slider.name = "SFXSlider"

	_label("海浪与环境", Rect2(20, 267, 220, 22))
	_ambient_value = _value_label(267.0)
	ambient_slider = _slider(293.0, 0.0, 100.0, 1.0)
	ambient_slider.name = "AmbientSlider"

	_label("界面提示音", Rect2(20, 321, 220, 22))
	_interface_value = _value_label(321.0)
	interface_slider = _slider(347.0, 0.0, 100.0, 1.0)
	interface_slider.name = "UISlider"

	motion_toggle = CheckButton.new()
	motion_toggle.name = "MotionToggle"
	motion_toggle.text = "视角动态"
	motion_toggle.position = Vector2(16, 380)
	motion_toggle.size = Vector2(328, 32)
	motion_toggle.focus_mode = Control.FOCUS_NONE
	motion_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	motion_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	motion_toggle.add_theme_color_override("font_color", WHITE)
	motion_toggle.add_theme_color_override("font_hover_color", CYAN)
	motion_toggle.add_theme_color_override("font_pressed_color", CYAN)
	add_child(motion_toggle)

	var reset_button: Button = Button.new()
	reset_button.name = "ResetDefaults"
	reset_button.text = "恢复默认"
	reset_button.position = Vector2(236, 420)
	reset_button.size = Vector2(104, 30)
	reset_button.flat = true
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.mouse_filter = Control.MOUSE_FILTER_STOP
	reset_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset_button.add_theme_color_override("font_color", CYAN)
	reset_button.add_theme_color_override("font_hover_color", WHITE)
	reset_button.add_theme_color_override("font_pressed_color", MUTED)
	reset_button.pressed.connect(reset_defaults)
	add_child(reset_button)
	queue_redraw()


func _draw() -> void:
	if _panel_style != null:
		draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))
		draw_line(Vector2(20, 44), Vector2(340, 44), Color(CYAN, 0.3), 1.0)


func _label(text: String, rect: Rect2) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", MUTED)
	add_child(label)
	return label


func _value_label(y: float) -> Label:
	var label: Label = _label("", Rect2(252, y, 88, 22))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", CYAN)
	return label


func _slider(y: float, minimum: float, maximum: float, increment: float) -> HSlider:
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.position = Vector2(20, y)
	slider.size = Vector2(320, 22)
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.self_modulate = CYAN
	add_child(slider)
	return slider


func _load_number(key: String, minimum: float, maximum: float) -> float:
	var value: Variant = _config.get_value(CONFIG_SECTION, key, DEFAULTS[key])
	if value is float or value is int:
		var number: float = float(value)
		if is_finite(number):
			return clampf(number, minimum, maximum)
	return float(DEFAULTS[key])


func _set_values(values: Dictionary) -> void:
	# Silent setters also keep resetting all four controls to one save operation.
	sensitivity_slider.set_value_no_signal(float(values["sensitivity"]))
	fov_slider.set_value_no_signal(float(values["fov"]))
	volume_slider.set_value_no_signal(float(values["volume"]))
	sfx_slider.set_value_no_signal(float(values["sfx"]))
	ambient_slider.set_value_no_signal(float(values["ambient"]))
	interface_slider.set_value_no_signal(float(values["interface"]))
	motion_toggle.set_pressed_no_signal(bool(values["motion"]))


func _apply_values() -> void:
	_sensitivity_value.text = "%.2f" % sensitivity_slider.value
	_fov_value.text = "%d°" % int(fov_slider.value)
	_volume_value.text = "%d%%" % int(volume_slider.value)
	_sfx_value.text = "%d%%" % int(sfx_slider.value)
	_ambient_value.text = "%d%%" % int(ambient_slider.value)
	_interface_value.text = "%d%%" % int(interface_slider.value)
	if is_instance_valid(_player):
		_player.set("mouse_sensitivity", sensitivity_slider.value)
		_player.set("base_fov", fov_slider.value)
		_player.set("view_motion", motion_toggle.button_pressed)
	var master: int = AudioServer.get_bus_index("Master")
	if master >= 0:
		var volume: float = volume_slider.value / 100.0
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(0.001, volume)))
		AudioServer.set_bus_mute(master, volume_slider.value <= 0.0)
	Audio.set_bus_level("SFX", sfx_slider.value / 100.0)
	Audio.set_bus_level("Ambient", ambient_slider.value / 100.0)
	Audio.set_bus_level("UI", interface_slider.value / 100.0)


func _save_values() -> void:
	var values: Dictionary = get_values()
	for key: String in values:
		_config.set_value(CONFIG_SECTION, key, values[key])
	var error: Error = _config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Could not save preferences: %s" % error_string(error))


func _on_slider_changed(_value: float) -> void:
	_apply_values()
	_save_values()


func _on_motion_changed(_pressed: bool) -> void:
	_apply_values()
	_save_values()

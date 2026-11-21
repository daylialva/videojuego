extends Control

signal closed

const SETTINGS_PATH: String = "user://audio_settings.cfg"

@onready var music_slider: HSlider = $Window/Content/MusicRow/Slider
@onready var music_value: Label = $Window/Content/MusicRow/Value
@onready var effects_slider: HSlider = $Window/Content/EffectsRow/Slider
@onready var effects_value: Label = $Window/Content/EffectsRow/Value

static func apply_saved_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_apply_bus_volume(&"Music", float(config.get_value("audio", "music", 100.0)))
	_apply_bus_volume(&"SFX", float(config.get_value("audio", "effects", 100.0)))

static func _apply_bus_volume(bus_name: StringName, percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var amount := clampf(percent / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, is_zero_approx(amount))
	if amount > 0.0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(amount))

func _ready() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	music_slider.set_value_no_signal(clampf(float(config.get_value("audio", "music", 100.0)), 0.0, 100.0))
	effects_slider.set_value_no_signal(clampf(float(config.get_value("audio", "effects", 100.0)), 0.0, 100.0))
	_update_labels()
	music_slider.value_changed.connect(_on_volume_changed.bind(&"Music", "music"))
	effects_slider.value_changed.connect(_on_volume_changed.bind(&"SFX", "effects"))
	$Window/Content/Close.pressed.connect(_close)
	music_slider.grab_focus()

func _on_volume_changed(value: float, bus_name: StringName, setting_name: String) -> void:
	_apply_bus_volume(bus_name, value)
	_update_labels()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", setting_name, value)
	config.save(SETTINGS_PATH)

func _update_labels() -> void:
	music_value.text = "%d%%" % int(music_slider.value)
	effects_value.text = "%d%%" % int(effects_slider.value)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
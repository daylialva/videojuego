extends Control

signal back_pressed
signal session_ready

@onready var address_input: LineEdit = $Window/Content/Address
@onready var status_label: Label = $Window/Content/Status

func _ready() -> void:
	$Window/Content/Host.pressed.connect(_host)
	$Window/Content/Join.pressed.connect(_join)
	$Window/Content/Back.pressed.connect(_back)
	LanSession.status_changed.connect(_show_status)
	LanSession.session_started.connect(_session_started)
	address_input.text = "127.0.0.1"
	$Window/Content/Host.grab_focus()

func _host() -> void:
	LanSession.host_game()

func _join() -> void:
	LanSession.join_game(address_input.text)

func _back() -> void:
	if LanSession.connecting:
		LanSession.close_session()
	back_pressed.emit()

func _show_status(message: String) -> void:
	status_label.text = message

func _session_started() -> void:
	session_ready.emit()

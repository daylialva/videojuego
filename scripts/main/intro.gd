extends Control

signal intro_finished

@onready var video_player: VideoStreamPlayer = $VideoPlayer

var finished: bool = false

func _ready() -> void:
	video_player.finished.connect(_finish_intro)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish_intro()
	elif event is InputEventMouseButton and event.pressed:
		_finish_intro()

func _finish_intro() -> void:
	if finished:
		return
	finished = true
	set_process_unhandled_input(false)
	video_player.stop()
	if LanSession.active:
		$Label.text = "Esperando al otro jugador..."
	intro_finished.emit()

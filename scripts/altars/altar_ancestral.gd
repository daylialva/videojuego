extends Node2D

signal restored

@export var prompt_text: String = "Presiona E para interactuar"
@export var confirmation_text: String = "¿Deseas entregar el fragmento de Illapa y la escama de serpiente?"
@export var completion_text: String = "El equilibrio ancestral ha sido restaurado."

@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $AltarUI/PromptLabel
@onready var confirmation_panel: Panel = $AltarUI/ConfirmationPanel
@onready var question_label: Label = $AltarUI/ConfirmationPanel/QuestionLabel
@onready var yes_button: Button = $AltarUI/ConfirmationPanel/YesButton
@onready var no_button: Button = $AltarUI/ConfirmationPanel/NoButton
@onready var message_panel: Panel = $AltarUI/MessagePanel
@onready var message_label: Label = $AltarUI/MessagePanel/MessageLabel
@onready var close_button: Button = $AltarUI/MessagePanel/CloseButton
@onready var rune_glow: Sprite2D = $RuneGlow
@onready var rune_light: PointLight2D = $RuneLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var nearby_player: CharacterBody2D
var ui_open: bool = false
var ceremony_running: bool = false

func _ready() -> void:
	add_to_group("lan_altar")
	prompt_label.text = prompt_text
	question_label.text = confirmation_text
	prompt_label.hide()
	confirmation_panel.hide()
	message_panel.hide()
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	yes_button.pressed.connect(_on_yes_pressed)
	no_button.pressed.connect(_close_confirmation)
	close_button.pressed.connect(_close_message)
	animation_player.animation_finished.connect(_on_animation_finished)
	if PlayerData.altar_restored:
		rune_glow.modulate.a = 0.75
		rune_light.energy = 0.85
		animation_player.play(&"pulso")
	else:
		rune_glow.modulate.a = 0.0
		rune_light.energy = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(nearby_player) or ui_open or PlayerData.altar_restored:
		return
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed(&"interact"):
		return
	if (nearby_player.get("dialogue_active") == true) or (nearby_player.get("inventory_active") == true):
		return
	if nearby_player.has_method("is_dead") and (nearby_player.call("is_dead") == true):
		return
	ui_open = true
	nearby_player.set_dialogue_active(true)
	prompt_label.hide()
	question_label.text = confirmation_text
	confirmation_panel.show()
	yes_button.grab_focus()
	get_viewport().set_input_as_handled()

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("player"):
		nearby_player = body
		if not PlayerData.altar_restored and not ui_open:
			prompt_label.show()

func _on_body_exited(body: Node2D) -> void:
	if body != nearby_player:
		return
	if ui_open and not ceremony_running:
		_close_confirmation()
		_close_message()
	prompt_label.hide()
	nearby_player = null

func _on_yes_pressed() -> void:
	confirmation_panel.hide()
	if LanSession.active and not multiplayer.is_server():
		if PlayerData.can_restore_altar():
			LanSession.request_altar_restore.rpc_id(1)
			_show_message(completion_text)
		else:
			_show_message("Necesitas el fragmento de Illapa y la escama de serpiente.")
		return
	if not PlayerData.restore_altar():
		_show_message("Necesitas el fragmento de Illapa y la escama de serpiente.")
		return
	ceremony_running = true
	animation_player.play(&"activar")

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"activar":
		return
	ceremony_running = false
	animation_player.play(&"pulso")
	_show_message(completion_text)
	restored.emit()

func _show_message(value: String) -> void:
	message_label.text = value
	message_panel.show()
	close_button.grab_focus()

func _close_confirmation() -> void:
	confirmation_panel.hide()
	_release_player()

func _close_message() -> void:
	message_panel.hide()
	_release_player()

func _release_player() -> void:
	if confirmation_panel.visible or message_panel.visible or ceremony_running:
		return
	ui_open = false
	if is_instance_valid(nearby_player):
		nearby_player.set_dialogue_active(false)
		if not PlayerData.altar_restored:
			prompt_label.show()

func _exit_tree() -> void:
	if ui_open and is_instance_valid(nearby_player):
		nearby_player.set_dialogue_active(false)

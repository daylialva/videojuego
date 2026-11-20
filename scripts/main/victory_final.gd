extends Control

const RESULT_SCENE: PackedScene = preload("res://scenes/main/escena_final.tscn")
const MENU_PATH := "res://scenes/main/gestor_escena.tscn"

func _ready() -> void:
	var panel: Control = RESULT_SCENE.instantiate()
	panel.victoria = true
	panel.menu.connect(_return_to_menu)
	add_child(panel)
	panel.get_node("VB/Botones/Replay").hide()

func _return_to_menu(_origin: String) -> void:
	if LanSession.active:
		LanSession.close_session()
	get_tree().change_scene_to_file(MENU_PATH)

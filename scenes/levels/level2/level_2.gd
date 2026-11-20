extends Node2D

@export var escena_final_packed: PackedScene = preload("res://scenes/main/escena_final.tscn")

@export_file("*.tscn") var next_level_path: String = "res://scenes/levels/level_2.tscn"
@export var next_level_title: String = "Nivel II: Dominios de Illapa"
@export var transition_video: VideoStream # Opcional: arrastra aquí un archivo .ogv si tienes uno
@export var is_final_level: bool = false

@export_group("Final Level Ending")
@export_file("*.tscn") var main_menu_path: String = "res://scenes/main/gestor_escena.tscn"
@export_file("*.tscn") var victory_scene_path: String = "res://scenes/main/victory_final.tscn"
@export var final_chapter_title: String = "FIN - APU: LA IRA DE LOS ANDES"

@onready var exit_portal: Area2D = $ExitPortal

var enemies_remaining: int = 0
var portal_unlocked: bool = false
var entering_portal: bool = false

func _ready() -> void:
	$Player.game_over.connect(_on_player_game_over)
	$AltarAncestral.restored.connect(_on_altar_restored)
	SaveManager.set_checkpoint(SaveManager.LEVEL_TWO)
	exit_portal.visible = false
	exit_portal.set_deferred("monitoring", false)
	if exit_portal.has_node("PillarCollisions/LeftPillarShape"):
		$ExitPortal/PillarCollisions/LeftPillarShape.set_deferred("disabled", true)
		$ExitPortal/PillarCollisions/RightPillarShape.set_deferred("disabled", true)

	exit_portal.body_entered.connect(_on_exit_portal_body_entered)
	exit_portal.area_entered.connect(_on_exit_portal_area_entered)

	if LanSession.active and not multiplayer.is_server():
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies_remaining = enemies.size()
	print("Enemigos detectados en el nivel: ", enemies_remaining)
	for enemy in enemies:
		enemy.tree_exited.connect(_on_enemy_defeated)
	if PlayerData.altar_restored:
		_unlock_portal()
		for enemy in enemies:
			enemy.queue_free()

func _on_enemy_defeated() -> void:
	if not is_inside_tree():
		return
	enemies_remaining -= 1
	print("Enemigos restantes: ", enemies_remaining)
	if enemies_remaining <= 0 and not PlayerData.altar_restored:
		print("Los objetos sagrados deben entregarse al altar.")

func _on_altar_restored() -> void:
	if PlayerData.altar_restored:
		_unlock_portal()

func _unlock_portal() -> void:
	if portal_unlocked:
		return
	portal_unlocked = true
	exit_portal.visible = true
	exit_portal.set_deferred("monitoring", true)
	if exit_portal.has_node("PillarCollisions/LeftPillarShape"):
		$ExitPortal/PillarCollisions/LeftPillarShape.set_deferred("disabled", false)
		$ExitPortal/PillarCollisions/RightPillarShape.set_deferred("disabled", false)

	# Animación de aparición y brillo pulsante
	exit_portal.scale = Vector2(0.5, 0.5)
	exit_portal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var intro := create_tween().set_parallel(true)
	intro.tween_property(exit_portal, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(exit_portal, "modulate:a", 1.0, 0.35)

	var pulse := create_tween().set_loops()
	pulse.tween_property(exit_portal, "modulate", Color(1.3, 1.45, 1.6, 1.0), 0.8)
	pulse.tween_property(exit_portal, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)

func _on_exit_portal_area_entered(area: Area2D) -> void:
	if area.owner != null:
		_on_exit_portal_body_entered(area.owner)

func _on_exit_portal_body_entered(body: Node2D) -> void:
	if LanSession.active and not multiplayer.is_server():
		return
	if not portal_unlocked or not PlayerData.altar_restored or entering_portal:
		return
	if body.is_in_group("player") or body.name == "Player":
		entering_portal = true

		# Inmoviliza a Kuya para que no siga caminando durante la animación
		body.set_physics_process(false)
		body.set_process_unhandled_input(false)

		# Efecto de succión hacia el centro del vórtice
		var vortex_center := exit_portal.global_position + Vector2(0, -16)
		var suck_tween := create_tween().set_parallel(true)
		suck_tween.tween_property(body, "global_position", vortex_center, 0.65).set_ease(Tween.EASE_IN)
		suck_tween.tween_property(body, "scale", Vector2(0.1, 0.1), 0.65).set_ease(Tween.EASE_IN)
		suck_tween.tween_property(body, "rotation", TAU, 0.65)
		suck_tween.tween_property(body, "modulate", Color(0.4, 0.9, 1.5, 0.0), 0.65)
		await suck_tween.finished

		if is_final_level:
			if not ResourceLoader.exists(victory_scene_path):
				push_error("No se encontró la escena de victoria: " + victory_scene_path)
				_on_player_game_over(true)
				return
			if LanSession.active:
				LanSession.finish_cooperative_run()
			else:
				SaveManager.finish_run()
				SceneTransition.change_level(victory_scene_path, final_chapter_title, transition_video)
		elif ResourceLoader.exists(next_level_path):
			SceneTransition.change_level(next_level_path, next_level_title, transition_video)
		else:
			push_error("Ruta de Nivel 2 inválida: " + next_level_path)

func _on_player_game_over(victoria: bool) -> void:
	if get_node_or_null("HealthCanvas/EscenaFinal") != null:
		return
	var result_panel: Control = escena_final_packed.instantiate()
	result_panel.victoria = victoria
	if LanSession.active:
		result_panel.repeat_level.connect(func(_origin: String) -> void: LanSession.request_replay())
		result_panel.menu.connect(func(_origin: String) -> void: LanSession.exit_to_menu())
	else:
		result_panel.repeat_level.connect(_replay_level)
		result_panel.menu.connect(_return_to_menu)
	$HealthCanvas.add_child(result_panel)
	$Player.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

func _replay_level(_origin: String) -> void:
	if SaveManager.restore_checkpoint():
		get_tree().reload_current_scene()

func _return_to_menu(_origin: String) -> void:
	get_tree().change_scene_to_file(main_menu_path)

extends Node

signal status_changed(message: String)
signal session_started
signal peer_ready(peer_id: int, level_number: int)
signal peer_left(peer_id: int)

const PORT: int = 27771
const LEVEL_TWO: String = "res://scenes/levels/level2/level_2.tscn"
const VICTORY: String = "res://scenes/main/victory_final.tscn"

var active: bool = false
var hosting: bool = false
var connecting: bool = false

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)

func host_game() -> bool:
	close_session()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		status_changed.emit("No se pudo crear la partida LAN: " + error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	status_changed.emit("Partida creada. Puerto %d. Esperando otro jugador." % PORT)
	session_started.emit()
	return true

func join_game(address: String) -> bool:
	close_session()
	address = address.strip_edges()
	if address.is_empty():
		status_changed.emit("Escribe la IP del anfitrión.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		status_changed.emit("No se pudo conectar: " + error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	connecting = true
	status_changed.emit("Conectando a %s:%d…" % [address, PORT])
	return true

func close_session() -> void:
	active = false
	hosting = false
	connecting = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _connected() -> void:
	connecting = false
	active = true
	status_changed.emit("Conectado al anfitrión.")
	session_started.emit()

func _connection_failed() -> void:
	close_session()
	status_changed.emit("No se pudo conectar. Comprueba la IP y la red local.")

func _server_disconnected() -> void:
	close_session()
	status_changed.emit("El anfitrión se desconectó.")
	get_tree().change_scene_to_file("res://scenes/main/gestor_escena.tscn")

func _peer_disconnected(id: int) -> void:
	peer_left.emit(id)
	status_changed.emit("El otro jugador se desconectó.")

@rpc("any_peer", "call_remote", "reliable")
func announce_level_ready(level_number: int) -> void:
	if active and multiplayer.is_server():
		peer_ready.emit(multiplayer.get_remote_sender_id(), level_number)

func advance_to_level_two() -> void:
	if active and multiplayer.is_server():
		await _despawn_players_before_transition()
		_change_to_level_two.rpc()

@rpc("authority", "call_local", "reliable")
func _change_to_level_two() -> void:
	SceneTransition.change_level(LEVEL_TWO, "Nivel II: Dominios de Illapa")

func finish_cooperative_run() -> void:
	if active and multiplayer.is_server():
		await _despawn_players_before_transition()
		_finish_run.rpc()

@rpc("authority", "call_local", "reliable")
func _finish_run() -> void:
	if multiplayer.is_server():
		SaveManager.finish_run()
	SceneTransition.change_level(VICTORY, "FIN - APU: LA IRA DE LOS ANDES")

@rpc("any_peer", "call_remote", "reliable")
func request_item_use(item_name: String) -> void:
	if active and multiplayer.is_server() and item_name in ["COCA", "CHICHA_DE_JORA", "QUIPU", "ILLA"]:
		PlayerData.consume_item(item_name)

@rpc("any_peer", "call_remote", "reliable")
func request_altar_restore() -> void:
	if not active or not multiplayer.is_server() or not PlayerData.can_restore_altar():
		return
	var altar := get_tree().get_first_node_in_group("lan_altar")
	if altar != null and PlayerData.restore_altar():
		altar.ceremony_running = true
		altar.animation_player.play(&"activar")

func _despawn_players_before_transition() -> void:
	var coordinator := get_tree().get_first_node_in_group("lan_coordinator")
	if multiplayer.is_server() and coordinator != null:
		for player in coordinator.players.get_children():
			player.queue_free()
	await get_tree().create_timer(0.2).timeout

func report_defeat() -> void:
	if not active:
		return
	if multiplayer.is_server():
		_show_shared_defeat.rpc()
	else:
		_request_defeat.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_defeat() -> void:
	if active and multiplayer.is_server():
		_show_shared_defeat.rpc()

@rpc("authority", "call_local", "reliable")
func _show_shared_defeat() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.name == "Level2" and scene.has_method("_on_player_game_over"):
		scene._on_player_game_over(false)
	elif scene.name == "GestorEscena":
		var game := scene.get_node_or_null("GameScene")
		if game != null:
			game.display_escena_final(false)
	elif scene.name == "GameScene":
		scene.display_escena_final(false)

func request_replay() -> void:
	if not active:
		return
	if multiplayer.is_server():
		_replay_together.rpc()
	else:
		_request_replay.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_replay() -> void:
	if active and multiplayer.is_server():
		_replay_together.rpc()

@rpc("authority", "call_local", "reliable")
func _replay_together() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if multiplayer.is_server():
		SaveManager.restore_checkpoint()
	else:
		PlayerData.reset_run()
	await _despawn_players_before_transition()
	if scene.name == "GestorEscena":
		var old_game := scene.get_node_or_null("GameScene")
		if old_game != null:
			old_game.queue_free()
		await get_tree().process_frame
		scene._start_level()
	else:
		get_tree().reload_current_scene()

func exit_to_menu() -> void:
	if not active:
		return
	if multiplayer.is_server():
		_exit_to_menu.rpc()
	else:
		_request_exit.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_exit() -> void:
	if active and multiplayer.is_server():
		_exit_to_menu.rpc()

@rpc("authority", "call_local", "reliable")
func _exit_to_menu() -> void:
	await get_tree().create_timer(0.1).timeout
	close_session()
	get_tree().change_scene_to_file("res://scenes/main/gestor_escena.tscn")

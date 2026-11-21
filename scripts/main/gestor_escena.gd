extends Node

@export var menu_packed: PackedScene
@export var intro_packed: PackedScene
@export var level_packed: PackedScene

func _ready() -> void:
	load_menu("game_start")

func load_menu(origin: String) -> void:
	if origin == "escena_final":
		get_node("GameScene").queue_free()
	var menu: Control = menu_packed.instantiate()
	menu.nuevo_juego_pressed.connect(nuevo_juego)
	menu.continuar_pressed.connect(continuar_juego)
	menu.opciones_pressed.connect(about_open)
	menu.salir_pressed.connect(exit_game)
	menu.lan_pressed.connect(open_lan_menu)
	add_child(menu)

func nuevo_juego(origin: String) -> void:
	if LanSession.active:
		LanSession.close_session()
	if origin == "menu":
		SaveManager.begin_new_game()
		get_node("Menu").queue_free()
		_start_intro()
		return
	if origin == "escena_final":
		SaveManager.begin_new_game()
		get_node("GameScene").queue_free()
		await get_tree().process_frame
	_start_level()

func _start_intro() -> void:
	var intro: Control = intro_packed.instantiate()
	intro.intro_finished.connect(_on_intro_finished.bind(intro))
	add_child(intro)

func _on_intro_finished(intro_node: Control) -> void:
	if LanSession.active:
		LanSession.report_intro_finished()
		return
	if is_instance_valid(intro_node):
		intro_node.queue_free()
	await get_tree().process_frame
	_start_level()

func _on_lan_intro_all_ready() -> void:
	var intro := get_node_or_null("Intro")
	if intro != null:
		intro.queue_free()
	await get_tree().process_frame
	_start_level()

func _start_level() -> void:
	var level: Node2D = level_packed.instantiate()
	add_child(level)

func continuar_juego(_origin: String) -> void:
	if not SaveManager.load_game():
		return
	if SaveManager.checkpoint == SaveManager.LEVEL_TWO:
		get_tree().change_scene_to_file("res://scenes/levels/level2/level_2.tscn")
	else:
		get_node("Menu").queue_free()
		await get_tree().process_frame
		_start_level()

@warning_ignore("unused_parameter")
func about_open(origin: String) -> void:
	var options_panel: Control = preload("res://scenes/ui/options_panel.tscn").instantiate()
	add_child(options_panel)
	options_panel.closed.connect(options_panel.queue_free)

@warning_ignore("unused_parameter")
func exit_game(origin: String) -> void:
	get_tree().quit()

func open_lan_menu(_origin: String) -> void:
	var network_menu: Control = preload("res://scenes/network/network_menu.tscn").instantiate()
	add_child(network_menu)
	network_menu.back_pressed.connect(func() -> void:
		get_node("Menu").show()
		network_menu.queue_free()
	)
	network_menu.session_ready.connect(_start_lan_game)

func _start_lan_game() -> void:
	if LanSession.hosting:
		SaveManager.begin_new_game()
	else:
		PlayerData.reset_run()
	get_node("Menu").queue_free()
	get_node("NetworkMenu").queue_free()
	LanSession.intro_all_ready.connect(_on_lan_intro_all_ready)
	await get_tree().process_frame
	_start_intro()

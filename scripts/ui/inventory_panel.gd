extends Control

const ITEM_ICONS: Array[Texture2D] = [
	preload("res://Assets/items/coca_reference.png"),
	preload("res://Assets/items/cicha_reference.png"),
	preload("res://Assets/items/fragmento_reference.png"),
	preload("res://Assets/items/quipu_reference.png"),
	preload("res://Assets/items/illa_reference.png"),
	preload("res://Assets/items/semilla_reference.png"),
	preload("res://Assets/items/escama_reference.png")
]

const ITEM_NAMES: Array[String] = [
	"Coca", "Chicha de jora", "Fragmento de Illapa", "Quipu",
	"Illa", "Semilla de Pachamama", "Escama de Amaru"
]

const ITEM_DETAILS: Array[String] = [
	"Recupera vida y energía", "Aumenta la velocidad", "Objeto del altar",
	"Recupera energía", "Protección temporal", "Objeto de misión", "Objeto del altar"
]

@onready var grid: GridContainer = $Window/Margin/Content/Grid
@onready var close_button: Button = $Window/Margin/Content/CloseButton

var lan_player: CharacterBody2D

func _ready() -> void:
	close_button.pressed.connect(_close)
	PlayerData.inventory_changed.connect(_refresh)
	PlayerData.selected_slot_changed.connect(_refresh_selection)
	for i in range(PlayerData.ITEM_ORDER.size()):
		var slot := grid.get_child(i) as Panel
		(slot.get_node("Icon") as TextureRect).texture = ITEM_ICONS[i]
		(slot.get_node("NameLabel") as Label).text = ITEM_NAMES[i]
		(slot.get_node("DetailLabel") as Label).text = ITEM_DETAILS[i]
		(slot.get_node("KeyLabel") as Label).text = str(i + 1)
	_refresh(PlayerData.inventory)
	_refresh_selection(PlayerData.selected_slot)
	hide()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		if visible:
			_close()
		elif not get_tree().paused and not _dialogue_open():
			_open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _dialogue_open() -> bool:
	for dialogue in get_tree().get_nodes_in_group("dialogue_ui"):
		if dialogue.get("dialogue_open") == true:
			return true
	return false

func _open() -> void:
	_refresh(PlayerData.inventory)
	show()
	if LanSession.active:
		for candidate in get_tree().get_nodes_in_group("player"):
			if candidate is CharacterBody2D and candidate.is_multiplayer_authority():
				lan_player = candidate
				lan_player.set_physics_process(false)
				lan_player.set_process_unhandled_input(false)
				break
	else:
		get_tree().paused = true
	close_button.grab_focus()

func _close() -> void:
	hide()
	if is_instance_valid(lan_player):
		lan_player.set_physics_process(true)
		lan_player.set_process_unhandled_input(true)
		lan_player = null
	else:
		get_tree().paused = false

func _exit_tree() -> void:
	if is_instance_valid(lan_player):
		lan_player.set_physics_process(true)
		lan_player.set_process_unhandled_input(true)
	if visible and not LanSession.active:
		get_tree().paused = false

func _refresh(inventory: Dictionary) -> void:
	for i in range(PlayerData.ITEM_ORDER.size()):
		var slot := grid.get_child(i) as Panel
		var count: int = int(inventory.get(PlayerData.ITEM_ORDER[i], 0))
		(slot.get_node("CountLabel") as Label).text = "×%d" % count
		(slot.get_node("Icon") as TextureRect).modulate.a = 1.0 if count > 0 else 0.35

func _refresh_selection(index: int) -> void:
	for i in range(PlayerData.ITEM_ORDER.size()):
		var slot := grid.get_child(i) as Panel
		slot.modulate = Color(1.1, 1.05, 0.85) if i == index else Color.WHITE

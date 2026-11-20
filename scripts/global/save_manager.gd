extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const LEVEL_ONE := "level1"
const LEVEL_TWO := "level2"

var checkpoint: String = LEVEL_ONE
var checkpoint_state: Dictionary = {}
var autosave_enabled: bool = false

func _ready() -> void:
	PlayerData.inventory_changed.connect(_on_inventory_changed)

func _on_inventory_changed(_inventory: Dictionary) -> void:
	if autosave_enabled:
		save_game()

func begin_new_game() -> void:
	autosave_enabled = false
	clear_save()
	PlayerData.reset_run()
	checkpoint = LEVEL_ONE
	checkpoint_state = _capture_state()
	autosave_enabled = true

func set_checkpoint(level_id: String) -> void:
	if level_id != LEVEL_ONE and level_id != LEVEL_TWO:
		return
	if checkpoint != level_id or checkpoint_state.is_empty():
		checkpoint = level_id
		checkpoint_state = _capture_state()
	if autosave_enabled:
		save_game()

func save_game() -> bool:
	if not autosave_enabled:
		return false
	var data := _capture_state()
	data["version"] = SAVE_VERSION
	data["checkpoint"] = checkpoint
	data["checkpoint_state"] = checkpoint_state.duplicate(true)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo guardar la partida: " + error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func has_save() -> bool:
	return not _read_save().is_empty()

func load_game() -> bool:
	var data := _read_save()
	if data.is_empty():
		return false
	autosave_enabled = false
	checkpoint = str(data["checkpoint"])
	_apply_state(data)
	var saved_checkpoint: Variant = data.get("checkpoint_state", {})
	if saved_checkpoint is Dictionary and not saved_checkpoint.is_empty():
		checkpoint_state = saved_checkpoint.duplicate(true)
	else:
		checkpoint_state = _capture_state()
		if checkpoint == LEVEL_TWO:
			checkpoint_state["inventory"]["FRAGMENTO_DE_ILLAPA"] = 0
			checkpoint_state["inventory"]["ESCAMA_DE_AMARU"] = 0
			checkpoint_state["collected_pickups"].erase("boss_illapa_fragment")
			checkpoint_state["collected_pickups"].erase("boss_amaru_scale")
			checkpoint_state["altar_restored"] = false
	autosave_enabled = true
	return true

func restore_checkpoint() -> bool:
	if checkpoint_state.is_empty():
		return false
	var was_autosaving := autosave_enabled
	autosave_enabled = false
	_apply_state(checkpoint_state)
	autosave_enabled = was_autosaving
	if autosave_enabled:
		save_game()
	return true

func finish_run() -> void:
	autosave_enabled = false
	clear_save()
	PlayerData.reset_run()
	checkpoint = LEVEL_ONE
	checkpoint_state.clear()

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if result != OK:
			push_error("No se pudo borrar la partida: " + error_string(result))

func _capture_state() -> Dictionary:
	return {
		"level": PlayerData.level,
		"experience": PlayerData.experience,
		"bonus_damage": PlayerData.bonus_damage,
		"bonus_speed": PlayerData.bonus_speed,
		"bonus_max_hp": PlayerData.bonus_max_hp,
		"bonus_max_energy": PlayerData.bonus_max_energy,
		"selected_slot": PlayerData.selected_slot,
		"inventory": PlayerData.inventory.duplicate(),
		"collected_pickups": PlayerData.collected_pickups.duplicate(),
		"altar_restored": PlayerData.altar_restored
	}

func _apply_state(data: Dictionary) -> void:
	PlayerData.reset_run()
	PlayerData.level = maxi(1, int(data.get("level", 1)))
	PlayerData.experience = maxi(0, int(data.get("experience", 0)))
	PlayerData.bonus_damage = int(data.get("bonus_damage", 0))
	PlayerData.bonus_speed = int(data.get("bonus_speed", 0))
	PlayerData.bonus_max_hp = int(data.get("bonus_max_hp", 0))
	PlayerData.bonus_max_energy = float(data.get("bonus_max_energy", 0.0))
	PlayerData.selected_slot = clampi(int(data.get("selected_slot", 0)), 0, PlayerData.ITEM_ORDER.size() - 1)
	var saved_inventory: Dictionary = data.get("inventory", {})
	for item_id in PlayerData.ITEM_ORDER:
		PlayerData.inventory[item_id] = maxi(0, int(saved_inventory.get(item_id, 0)))
	var saved_pickups: Dictionary = data.get("collected_pickups", {})
	PlayerData.collected_pickups = saved_pickups.duplicate()
	PlayerData.altar_restored = (data.get("altar_restored", false) == true)
	PlayerData.inventory_changed.emit(PlayerData.inventory)
	PlayerData.selected_slot_changed.emit(PlayerData.selected_slot)

func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	if int(parsed.get("version", -1)) != SAVE_VERSION:
		return {}
	if parsed.get("checkpoint", "") != LEVEL_ONE and parsed.get("checkpoint", "") != LEVEL_TWO:
		return {}
	if not parsed.get("inventory", null) is Dictionary:
		return {}
	return parsed

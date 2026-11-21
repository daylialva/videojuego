extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/player/power_up.tscn")

@export_range(1, 2) var level_number: int = 1
@onready var players: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

var snapshot_clock: float = 0.0
var local_player: CharacterBody2D

func _ready() -> void:
	add_to_group("lan_coordinator")
	if not LanSession.active:
		return
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	spawner.spawned.connect(_on_player_spawned)
	if multiplayer.is_server():
		LanSession.peer_ready.connect(_on_peer_ready)
		LanSession.peer_left.connect(_on_peer_left)
	else:
		call_deferred("_client_ready")
		call_deferred("_disable_client_enemies")

func _client_ready() -> void:
	while is_inside_tree() and LanSession.active and not is_instance_valid(local_player):
		LanSession.announce_level_ready.rpc_id(1, level_number)
		await get_tree().create_timer(0.5).timeout

func _spawn_player(peer_id: Variant) -> Node:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Peer_%d" % int(peer_id)
	player.position = get_parent().get_node("Player").position + Vector2(80, 0)
	player.set_multiplayer_authority(int(peer_id), true)
	return player

func _on_peer_ready(peer_id: int, ready_level: int) -> void:
	if ready_level != level_number or players.has_node("Peer_%d" % peer_id):
		return
	var player := spawner.spawn(peer_id) as CharacterBody2D
	_on_player_spawned(player)

func _on_peer_left(peer_id: int) -> void:
	var player := players.get_node_or_null("Peer_%d" % peer_id)
	if player != null:
		player.queue_free()

func _on_player_spawned(player: Node) -> void:
	if not player.is_multiplayer_authority():
		return
	local_player = player as CharacterBody2D
	call_deferred("_bind_local_player")

func _bind_local_player() -> void:
	if not is_instance_valid(local_player):
		return
	local_player.get_node("Camera2D").make_current()
	for hud in get_tree().get_nodes_in_group("lan_hud"):
		hud.bind_player(local_player)
	if level_number == 2:
		local_player.game_over.connect(get_parent()._on_player_game_over)
	else:
		var game_scene := get_parent().get_parent()
		if game_scene.has_method("display_escena_final"):
			local_player.game_over.connect(game_scene.display_escena_final)

func _disable_client_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if get_parent().is_ancestor_of(enemy):
			enemy.set_physics_process(false)
			var tree := enemy.get_node_or_null("AnimationTree") as AnimationTree
			if tree != null:
				tree.active = false
			var animator := enemy.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if animator != null:
				animator.active = false
			var hit_box := enemy.get_node_or_null("HitBox") as Area2D
			if hit_box != null:
				hit_box.set_deferred("monitoring", false)

func _process(delta: float) -> void:
	if not LanSession.active or not multiplayer.is_server():
		return
	snapshot_clock += delta
	if snapshot_clock < 0.1:
		return
	snapshot_clock = 0.0
	var enemy_state: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not get_parent().is_ancestor_of(enemy):
			continue
		var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		var bar := enemy.get_node_or_null("HealthBar") as Range
		enemy_state[str(get_parent().get_path_to(enemy))] = [enemy.global_position, sprite.frame if sprite != null else 0, sprite.flip_h if sprite != null else false, bar.value if bar != null else 0.0, bar.visible if bar != null else false]
	var pickup_state: Dictionary = {}
	for pickup in get_tree().get_nodes_in_group("lan_pickup"):
		if get_parent().is_ancestor_of(pickup):
			pickup_state[pickup._pickup_key()] = [pickup.power_type, pickup.global_position]
	var projectile_state: Dictionary = {}
	for projectile in get_tree().get_nodes_in_group("lan_projectile"):
		if get_parent().is_ancestor_of(projectile):
			var frame := 0
			var animated := projectile.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if animated != null:
				frame = animated.frame
			projectile_state[str(get_parent().get_path_to(projectile))] = [projectile.scene_file_path, projectile.global_position, projectile.rotation, frame]
	_sync_world.rpc(enemy_state, pickup_state, projectile_state, PlayerData.inventory, PlayerData.collected_pickups, PlayerData.altar_restored)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_world(enemy_state: Dictionary, pickup_state: Dictionary, projectile_state: Dictionary, inventory: Dictionary, collected: Dictionary, altar_restored: bool) -> void:
	if multiplayer.is_server():
		return
	if PlayerData.inventory != inventory:
		PlayerData.inventory = inventory.duplicate(true)
		PlayerData.inventory_changed.emit(PlayerData.inventory)
	PlayerData.collected_pickups = collected.duplicate(true)
	PlayerData.altar_restored = altar_restored
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not get_parent().is_ancestor_of(enemy):
			continue
		var key := str(get_parent().get_path_to(enemy))
		if not enemy_state.has(key):
			enemy.queue_free()
			continue
		var values: Array = enemy_state[key]
		enemy.global_position = values[0]
		var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			sprite.frame = int(values[1])
			sprite.flip_h = bool(values[2])
		var bar := enemy.get_node_or_null("HealthBar") as Range
		if bar != null:
			bar.value = values[3]
			bar.visible = bool(values[4])
	for pickup in get_tree().get_nodes_in_group("lan_pickup"):
		if get_parent().is_ancestor_of(pickup) and not pickup_state.has(pickup._pickup_key()):
			pickup.queue_free()
	for key in pickup_state:
		var found := false
		for pickup in get_tree().get_nodes_in_group("lan_pickup"):
			if get_parent().is_ancestor_of(pickup) and pickup._pickup_key() == key:
				found = true
				break
		if not found:
			var pickup := PICKUP_SCENE.instantiate()
			pickup.pickup_id = str(key)
			pickup.power_type = int(pickup_state[key][0])
			pickup.global_position = pickup_state[key][1]
			get_parent().add_child(pickup)
	for projectile in get_tree().get_nodes_in_group("lan_projectile"):
		if get_parent().is_ancestor_of(projectile) and not projectile_state.has(projectile.get_meta("lan_key", str(get_parent().get_path_to(projectile)))):
			projectile.queue_free()
	for key in projectile_state:
		var values: Array = projectile_state[key]
		var projectile := get_parent().get_node_or_null(NodePath(str(key))) as Area2D
		if projectile == null:
			for candidate in get_tree().get_nodes_in_group("lan_projectile"):
				if candidate.get_meta("lan_key", "") == key:
					projectile = candidate
					break
		if projectile == null and ResourceLoader.exists(str(values[0])):
			projectile = load(str(values[0])).instantiate() as Area2D
			projectile.set_meta("lan_key", key)
			get_parent().add_child(projectile)
		if projectile != null:
			projectile.global_position = values[1]
			projectile.rotation = values[2]
			var animated := projectile.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if animated != null:
				animated.frame = int(values[3])
	if level_number == 1 and enemy_state.is_empty() and not get_parent().portal_unlocked:
		get_parent()._unlock_portal()
	if level_number == 2 and altar_restored:
		var altar := get_tree().get_first_node_in_group("lan_altar")
		if altar != null and get_parent().is_ancestor_of(altar) and not altar.animation_player.is_playing():
			altar.rune_glow.modulate.a = 0.75
			altar.rune_light.energy = 0.85
			altar.animation_player.play(&"pulso")
		if not get_parent().portal_unlocked:
			get_parent()._unlock_portal()

@rpc("any_peer", "call_remote", "reliable")
func request_enemy_hit(enemy_path: String, damage: int) -> void:
	if not multiplayer.is_server() or damage <= 0 or damage > 500:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var attacker := players.get_node_or_null("Peer_%d" % peer_id) as CharacterBody2D
	var enemy := get_parent().get_node_or_null(NodePath(enemy_path)) as Node2D
	if attacker == null or enemy == null or not enemy.is_in_group("enemies"):
		return
	if attacker.global_position.distance_to(enemy.global_position) > 170.0:
		return
	enemy.take_damage(damage)

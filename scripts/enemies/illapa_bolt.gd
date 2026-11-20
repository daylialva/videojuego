extends Area2D

@export var speed: float = 560.0
@export var damage: int = 20
@export var lifetime: float = 1.2

var direction: Vector2 = Vector2.RIGHT
var age: float = 0.0

func _ready() -> void:
	add_to_group("lan_projectile")
	if LanSession.active and not multiplayer.is_server():
		set_physics_process(false)
		set_deferred("monitoring", false)
	area_entered.connect(_on_area_entered)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	age += delta
	if age >= lifetime:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if LanSession.active and not multiplayer.is_server():
		return
	var target := area.owner
	if target != null and target.is_in_group("player"):
		if target.has_method("take_damage") and (not target.has_method("is_dead") or not (target.call("is_dead") == true)):
			target.take_damage(damage)
		queue_free()

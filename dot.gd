extends CharacterBody2D

@export var stats: UnitStats
@export var is_selected: bool = false

@onready var sprite: Sprite2D = $Sprite

func _physics_process(delta: float) -> void:
	if not stats:
		return
	velocity.x = stats.speed
	sprite.modulate = Color.WHITE if is_selected else Color(1, 1, 1, 1)
	move_and_slide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var mouse_pos = get_global_mouse_position()
		if _is_mouse_over(mouse_pos):
			is_selected = !is_selected
		else:
			is_selected = false  # Deselect when clicking elsewhere

func _is_mouse_over(mouse_pos: Vector2) -> bool:
	var col = $Collision.shape
	if col is CircleShape2D:
		return mouse_pos.distance_to(global_position) <= col.radius
	return false

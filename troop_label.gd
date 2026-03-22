## Attach this as a child Label node named "TroopLabel" inside dot.tscn
## It floats below the unit sprite and shows the scale text.
extends Label

@export var troops_per_dot: int = 1000

func _ready() -> void:
	text = "1,000"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_override_font_sizes/font_size = 9
	# Position just below the sprite
	position = Vector2(-16, 14)
	# Dim so it doesn't clutter the battlefield
	modulate = Color(1, 1, 1, 0.55)

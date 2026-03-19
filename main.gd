extends Node2D

@export var dot_scene: PackedScene
@export var seed: int

func _ready() -> void:
	if dot_scene:
		var dot = dot_scene.instantiate()
		add_child(dot)
		dot.stats = preload("res://knight.tres")

func _process(delta: float) -> void:
	pass

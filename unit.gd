extends CharacterBody2D
class_name ShipkaUnit

@export var stats: UnitStats
@export var is_selected: bool = false

## Runtime state
var current_health: float = 0.0
var is_alive: bool = true
var move_points_left: int = 0
var attack_timer: float = 0.0
var current_target: ShipkaUnit = null
var move_target: Vector2 = Vector2.ZERO
var is_moving: bool = false
var charge_used: bool = false       # Cavalry charge — resets each turn

## Terrain
var terrain_speed_multiplier: float = 1.0

@onready var sprite: Sprite2D = $Sprite
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision_shape: CollisionShape2D = $Collision
@onready var selection_ring: Node2D = $SelectionRing
@onready var aura_ring: Node2D = $AuraRing

signal died(unit)
signal health_changed(unit, new_health)
signal fired_projectile(data)


func _ready() -> void:
	if stats:
		current_health = stats.max_health
		move_points_left = stats.move_points
		_apply_faction_color()
		_setup_visuals()
	if selection_ring:
		selection_ring.visible = false
	if aura_ring:
		aura_ring.visible = stats and stats.aura_radius > 0


func _physics_process(delta: float) -> void:
	if not stats or not is_alive:
		return
	_handle_movement(delta)
	_handle_passive_effects(delta)
	_update_health_bar()


func _handle_movement(delta: float) -> void:
	if not is_moving:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir = (move_target - global_position)
	if dir.length() < 6.0:
		is_moving = false
		velocity = Vector2.ZERO
	else:
		velocity = dir.normalized() * stats.speed * terrain_speed_multiplier
	move_and_slide()


func _handle_passive_effects(delta: float) -> void:
	# Medic heal
	if stats.heal_per_second > 0:
		_apply_heal(delta)

	# Commander aura
	if stats.aura_radius > 0:
		_apply_aura()

	# Auto-attack when target set
	if current_target and is_instance_valid(current_target) and current_target.is_alive:
		attack_timer -= delta
		if attack_timer <= 0:
			_fire_at(current_target)
			attack_timer = stats.attack_cooldown


func _apply_heal(delta: float) -> void:
	var nearby = _get_nearby_allies(stats.heal_radius)
	for ally in nearby:
		var healed = min(stats.heal_per_second * delta, ally.stats.max_health - ally.current_health)
		if healed > 0:
			ally.current_health += healed
			ally.emit_signal("health_changed", ally, ally.current_health)


func _apply_aura() -> void:
	## Aura bonuses are queried by units each frame — nothing to push here.
	## GameManager / units call get_aura_bonus() when computing damage/speed.
	pass


func get_aura_bonus_for(target: ShipkaUnit) -> Dictionary:
	## Returns the damage/speed/attack_speed bonus this commander gives to target.
	if not is_alive or stats.aura_radius <= 0:
		return {}
	if global_position.distance_to(target.global_position) > stats.aura_radius:
		return {}
	return {
		"damage": stats.aura_damage_bonus,
		"speed": stats.aura_speed_bonus,
		"attack_speed": stats.aura_attack_speed_bonus
	}


## ─── Combat ─────────────────────────────────────────────────────────────────

func attack(target: ShipkaUnit) -> void:
	if not is_alive or not target.is_alive:
		return
	current_target = target
	attack_timer = 0.0  # fire immediately this frame


func attack_position(pos: Vector2) -> void:
	## AoE attack at a world position (cannon)
	_fire_at_position(pos)


func _fire_at(target: ShipkaUnit) -> void:
	if not target or not is_instance_valid(target):
		current_target = null
		return

	var dmg = _compute_damage()

	if stats.aoe_radius > 0:
		_fire_at_position(target.global_position)
	else:
		# Ranged — emit projectile signal
		if stats.projectile_speed > 0:
			emit_signal("fired_projectile", {
				"from": global_position,
				"target": target,
				"damage": dmg,
				"speed": stats.projectile_speed,
				"size": stats.projectile_size,
				"aoe": 0.0,
				"faction": stats.faction
			})
		else:
			# Melee — instant
			_deal_damage_to(target, dmg)

	charge_used = true


func _fire_at_position(pos: Vector2) -> void:
	var dmg = _compute_damage()
	emit_signal("fired_projectile", {
		"from": global_position,
		"target_pos": pos,
		"damage": dmg,
		"speed": stats.projectile_speed,
		"size": stats.projectile_size,
		"aoe": stats.aoe_radius,
		"faction": stats.faction
	})


func _compute_damage() -> float:
	var dmg = stats.damage

	# Cavalry charge bonus (first strike)
	if stats.charge_damage_multiplier > 1.0 and not charge_used:
		dmg *= stats.charge_damage_multiplier

	# Nizam burst — handled by projectile spawner via burst_count / burst_interval
	# Commander aura bonus (self gets own aura? No — nearby allies only)

	return dmg


func _deal_damage_to(target: ShipkaUnit, dmg: float) -> void:
	var effective_dmg = dmg * (1.0 - target.stats.armor_pierce if "armor_pierce" in target.stats else 1.0)
	# Apply terrain defense bonus
	if target.stats.high_ground_defense_bonus > 0:
		# TerrainManager will set a flag on unit — simplified here
		effective_dmg *= (1.0 - target.stats.high_ground_defense_bonus)
	target.take_damage(effective_dmg)


func take_damage(amount: float) -> void:
	current_health -= amount
	current_health = max(current_health, 0.0)
	emit_signal("health_changed", self, current_health)
	if current_health <= 0:
		_die()


func _die() -> void:
	is_alive = false
	emit_signal("died", self)
	queue_free()


## ─── Movement ───────────────────────────────────────────────────────────────

func set_move_target(pos: Vector2) -> void:
	move_target = pos
	is_moving = true
	charge_used = false  # Reset charge on move (new engagement)


## ─── Visuals ─────────────────────────────────────────────────────────────────

func _setup_visuals() -> void:
	if sprite and stats:
		sprite.scale = Vector2.ONE * (stats.size / 24.0)

	if aura_ring and stats and stats.aura_radius > 0:
		aura_ring.scale = Vector2.ONE * (stats.aura_radius / 16.0)
		aura_ring.visible = true


func _update_health_bar() -> void:
	if health_bar and stats:
		health_bar.value = (current_health / stats.max_health) * 100.0
		health_bar.modulate = Color.GREEN if current_health > stats.max_health * 0.5 \
			else (Color.YELLOW if current_health > stats.max_health * 0.25 else Color.RED)


func _apply_faction_color() -> void:
	if sprite and stats:
		sprite.modulate = stats.unit_color


func select() -> void:
	is_selected = true
	if selection_ring:
		selection_ring.visible = true
	if sprite:
		sprite.modulate = stats.unit_color.lightened(0.4)


func deselect() -> void:
	is_selected = false
	if selection_ring:
		selection_ring.visible = false
	_apply_faction_color()


## ─── Input ──────────────────────────────────────────────────────────────────

func _input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		GameManager.select_unit(self)


## ─── Helpers ────────────────────────────────────────────────────────────────

func _get_nearby_allies(radius: float) -> Array[ShipkaUnit]:
	var result: Array[ShipkaUnit] = []
	for unit in GameManager.all_units:
		if unit == self or not unit.is_alive:
			continue
		if unit.stats.faction != stats.faction:
			continue
		if global_position.distance_to(unit.global_position) <= radius:
			result.append(unit)
	return result


func _is_mouse_over(mouse_pos: Vector2) -> bool:
	if collision_shape and collision_shape.shape is CircleShape2D:
		return mouse_pos.distance_to(global_position) <= collision_shape.shape.radius
	return false

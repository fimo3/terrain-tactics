extends CharacterBody2D

@export var stats: UnitStats

## ── Runtime state ─────────────────────────────────────────────────────────────
var current_health:   float   = 0.0
var stamina:          float   = 1.0   ## 0–1, multiplies damage output
var is_alive:         bool    = true
var is_selected:      bool    = false
var attack_timer:     float   = 0.0
var current_target            = null   ## forced target (player right-click or AI decision)
var _move_target:     Vector2 = Vector2.ZERO
var _has_move_order:  bool    = false
var _home_pos:        Vector2 = Vector2.ZERO

## Stamina constants
const S_DRAIN_COMBAT  := 0.035
const S_DRAIN_MOVE    := 0.006
const S_REGEN_REST    := 0.055
const S_REGEN_CMD     := 0.025
const S_FLEE_BELOW    := 0.18
const S_REJOIN_ABOVE  := 0.50

## Behaviour
enum B { IDLE, MOVE, ATTACK, FLEE }
var behaviour: B = B.IDLE

## Terrain (set by TerrainManager each frame)
var terrain_speed_mult:   float = 1.0
var terrain_defense_mult: float = 1.0  ## < 1.0 = less damage taken
var terrain_stamina_mult: float = 1.0  ## > 1.0 = stamina drains faster

## Draw geometry
const DOT_R := 11.0
const BAR_W := 40.0
const BAR_H := 5.0
const HP_Y  := 16.0
const ST_Y  := 23.0

## Flag palette
const C_BG_GREEN  := Color(0.00, 0.60, 0.20)
const C_BG_RED    := Color(0.85, 0.07, 0.07)
const C_RU_BLUE   := Color(0.10, 0.20, 0.75)
const C_RU_WHITE  := Color(0.92, 0.92, 0.92)
const C_OT_RED    := Color(0.78, 0.05, 0.05)
const C_GOLD      := Color(1.00, 0.85, 0.15)
const C_WHITE     := Color(0.92, 0.92, 0.92)
const C_RU_RING   := Color(0.85, 0.07, 0.07)

@onready var sprite:          Sprite2D         = $Sprite
@onready var collision_shape: CollisionShape2D = $Collision

signal died(unit)
signal fired_projectile(data)

## ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if stats:
		current_health = stats.max_health
	_home_pos = global_position
	if sprite: sprite.visible = false


func _physics_process(delta: float) -> void:
	if not stats or not is_alive:
		return
	TerrainManager.apply_terrain(self)
	_update_stamina(delta)
	_commander_aura_regen(delta)
	_update_behaviour(delta)
	_update_attack(delta)
	queue_redraw()


## ── Stamina ───────────────────────────────────────────────────────────────────

func _update_stamina(delta: float) -> void:
	var fighting = current_target != null and is_instance_valid(current_target)
	var moving   = velocity.length() > 5.0
	if fighting:
		stamina -= S_DRAIN_COMBAT * terrain_stamina_mult * delta
	elif moving:
		stamina -= S_DRAIN_MOVE * terrain_stamina_mult * delta
	else:
		stamina += S_REGEN_REST * delta
	stamina = clamp(stamina, 0.0, 1.0)


func _commander_aura_regen(delta: float) -> void:
	for ally in GameManager.allies_of(stats.faction):
		if not is_instance_valid(ally) or not ally.is_alive: continue
		if ally.stats.unit_type != UnitStats.UnitType.COMMANDER: continue
		if global_position.distance_to(ally.global_position) <= ally.stats.aura_radius:
			stamina = min(1.0, stamina + S_REGEN_CMD * delta)
			break


## ── Behaviour ─────────────────────────────────────────────────────────────────

func _update_behaviour(delta: float) -> void:
	## Low stamina → always flee regardless of orders
	if stamina < S_FLEE_BELOW and behaviour != B.FLEE:
		behaviour = B.FLEE
		_has_move_order = false
		current_target  = null

	match behaviour:
		B.FLEE:
			_move_toward(_home_pos, delta)
			if stamina >= S_REJOIN_ABOVE:
				behaviour = B.IDLE

		B.MOVE:
			_move_toward(_move_target, delta)
			if global_position.distance_to(_move_target) < 10.0:
				behaviour = B.IDLE
				_has_move_order = false
			## Auto-attack if enemy steps into range while moving
			if not current_target:
				var e = _nearest_enemy_in_range()
				if e: current_target = e

		B.ATTACK:
			## Close gap for melee
			if current_target and is_instance_valid(current_target):
				if stats.range < 80 and _dist_to(current_target) > stats.range * 0.85:
					_move_toward(current_target.global_position, delta)
			else:
				current_target = null
				behaviour = B.IDLE

		B.IDLE:
			velocity = Vector2.ZERO
			move_and_slide()
			## Auto-seek nearest enemy
			var e = _nearest_enemy_in_range()
			if e:
				current_target = e
				behaviour = B.ATTACK


## ── Player commands ───────────────────────────────────────────────────────────

## Called by main.gd right-click on empty ground
func order_move(pos: Vector2) -> void:
	_move_target    = pos
	_has_move_order = true
	current_target  = null
	behaviour       = B.MOVE


## Called by main.gd right-click on enemy unit
func order_attack(target) -> void:
	current_target = target
	behaviour      = B.ATTACK


## ── Movement ──────────────────────────────────────────────────────────────────

func _move_toward(target: Vector2, _delta: float) -> void:
	var dir = target - global_position
	if dir.length() < 5.0:
		velocity = Vector2.ZERO
	else:
		velocity = dir.normalized() * stats.speed * terrain_speed_mult
	move_and_slide()


## ── Combat ────────────────────────────────────────────────────────────────────

func _update_attack(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target) or not current_target.is_alive:
		current_target = null
		if behaviour == B.ATTACK: behaviour = B.IDLE
		return
	if _dist_to(current_target) > stats.range * 1.15:
		return
	attack_timer -= delta
	if attack_timer <= 0.0:
		_fire()
		attack_timer = stats.attack_cooldown


func _fire() -> void:
	var dmg = stats.damage * stamina   ## STAMINA = DAMAGE MULTIPLIER

	if stats.heal_per_second > 0:
		_do_heal()
		return

	if stats.aoe_radius > 0:
		emit_signal("fired_projectile", {
			"from": global_position, "target_pos": current_target.global_position,
			"damage": dmg, "speed": stats.projectile_speed,
			"size": stats.projectile_size, "aoe": stats.aoe_radius, "faction": stats.faction
		})
	elif stats.projectile_speed > 0:
		emit_signal("fired_projectile", {
			"from": global_position, "target": current_target,
			"damage": dmg, "speed": stats.projectile_speed,
			"size": stats.projectile_size, "aoe": 0.0, "faction": stats.faction
		})
	else:
		current_target.take_damage(dmg)


func _do_heal() -> void:
	for ally in GameManager.allies_of(stats.faction):
		if not is_instance_valid(ally) or ally == self: continue
		if global_position.distance_to(ally.global_position) <= stats.heal_radius:
			ally.current_health = min(ally.current_health + stats.heal_per_second * stats.attack_cooldown,
				ally.stats.max_health)


func take_damage(amount: float) -> void:
	## terrain_defense_mult < 1.0 means terrain absorbs some damage
	var eff = amount * terrain_defense_mult
	eff = max(eff, 0.0)
	current_health -= eff
	current_health  = max(current_health, 0.0)
	if current_health <= 0.0:
		_die()


func _die() -> void:
	is_alive = false
	emit_signal("died", self)
	queue_free()


## ── Selection visuals ─────────────────────────────────────────────────────────

func select() -> void:
	is_selected = true
	queue_redraw()


func deselect() -> void:
	is_selected = false
	queue_redraw()


## ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not stats: return
	var fc       = _faction_colors()
	var hp_ratio = current_health / stats.max_health if stats.max_health > 0 else 0.0
	var alpha    = lerp(0.38, 1.0, stamina)

	var body = Color(fc.body.r, fc.body.g, fc.body.b, alpha)
	var ring = Color(fc.ring.r, fc.ring.g, fc.ring.b, alpha)

	draw_circle(Vector2(1,1), DOT_R, Color(0,0,0,0.22*alpha))
	draw_circle(Vector2.ZERO, DOT_R, body)
	draw_arc(Vector2.ZERO, DOT_R+1.5, 0, TAU, 48, ring, 2.2)

	if stats.faction == 1:              _draw_crescent(alpha)
	elif stats.unit_type != UnitStats.UnitType.COMMANDER:  _draw_cross(alpha)

	if stats.unit_type == UnitStats.UnitType.COMMANDER:
		_draw_star(Vector2.ZERO, 6.5, Color(1.0, 0.88, 0.20, 0.95*alpha))

	if behaviour == B.FLEE:
		var pulse = abs(sin(Time.get_ticks_msec() * 0.005))
		draw_arc(Vector2.ZERO, DOT_R+5, 0, TAU, 32, Color(1,1,1,0.6*pulse), 1.5)

	if is_selected:
		draw_arc(Vector2.ZERO, 17.0, 0, TAU, 64, Color(1.0,0.92,0.2,0.95), 2.8)
		for i in 6:
			var a = i*TAU/6.0
			draw_arc(Vector2.ZERO, 22.5, a, a+0.35, 8, Color(1,1,1,0.35), 1.2)
		if stats.aura_radius > 0:
			draw_arc(Vector2.ZERO, stats.aura_radius, 0, TAU, 80, Color(1.0,0.88,0.20,0.14), 1.2)

	_draw_bar(HP_Y, hp_ratio,
		Color(0.18,0.82,0.22) if hp_ratio>0.6 else
		(Color(0.95,0.76,0.06) if hp_ratio>0.3 else Color(0.92,0.15,0.10)))
	_draw_bar(ST_Y, stamina, Color(0.15,0.65,0.95))

	draw_string(ThemeDB.fallback_font,
		Vector2(-18, ST_Y+BAR_H+10), "1,000",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1,1,1,0.40*alpha))


func _draw_bar(y: float, ratio: float, col: Color) -> void:
	var bx = -BAR_W*0.5
	draw_rect(Rect2(bx-1, y-1, BAR_W+2, BAR_H+2), Color(0,0,0,0.62))
	draw_rect(Rect2(bx,   y,   BAR_W,   BAR_H  ), Color(0.08,0.08,0.08,0.85))
	if ratio > 0:
		draw_rect(Rect2(bx, y, BAR_W*ratio, BAR_H), col)
	draw_rect(Rect2(bx-1, y-1, BAR_W+2, BAR_H+2), Color(0,0,0,0.40), false, 0.7)


func _draw_crescent(alpha: float) -> void:
	draw_arc(Vector2(-1.5,-1.0), 6.0, deg_to_rad(200), deg_to_rad(360), 20, Color(1,1,1,0.90*alpha), 2.0)
	draw_arc(Vector2( 1.5,-1.0), 4.5, deg_to_rad(200), deg_to_rad(360), 20, _faction_colors().body, 2.5)
	_draw_star(Vector2(7,-4), 2.2, Color(1,1,1,0.80*alpha))


func _draw_cross(alpha: float) -> void:
	var col: Color
	if stats.unit_type == UnitStats.UnitType.CAVALRY or stats.unit_type == UnitStats.UnitType.MEDIC:
		col = Color(0.85,0.07,0.07, 0.85*alpha)
	else:
		col = Color(1.0,1.0,1.0,   0.75*alpha)
	draw_line(Vector2(-5,0), Vector2(5,0), col, 1.5)
	draw_line(Vector2(0,-5), Vector2(0,5), col, 1.5)


func _draw_star(center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var angle = i*TAU/10.0 - TAU/4.0
		var rad   = r if i%2==0 else r*0.42
		pts.append(center + Vector2(cos(angle), sin(angle))*rad)
	draw_colored_polygon(pts, color)


func _faction_colors() -> Dictionary:
	if stats.faction == 1:
		var b = C_OT_RED
		if stats.unit_type == UnitStats.UnitType.COMMANDER: b = Color(0.82,0.05,0.05)
		return {"body": b, "ring": C_WHITE}
	match stats.unit_type:
		UnitStats.UnitType.RIFLEMAN:  return {"body": C_BG_GREEN,  "ring": C_WHITE}
		UnitStats.UnitType.CANNON:    return {"body": C_BG_RED,    "ring": C_WHITE}
		UnitStats.UnitType.COMMANDER: return {"body": C_BG_RED,    "ring": C_GOLD}
		UnitStats.UnitType.CAVALRY:   return {"body": C_RU_BLUE,   "ring": C_RU_RING}
		UnitStats.UnitType.MEDIC:     return {"body": C_RU_WHITE,  "ring": C_RU_RING}
	return {"body": Color(0.6,0.6,0.6), "ring": Color(1,1,1)}


## ── Helpers ───────────────────────────────────────────────────────────────────

func _nearest_enemy_in_range():
	var enemies = GameManager.enemies_of(stats.faction)
	var best = null
	var best_dist = stats.range * 2.5   ## lookahead radius
	for e in enemies:
		if not e.is_alive: continue
		var d = global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _dist_to(other) -> float:
	return global_position.distance_to(other.global_position)

extends CharacterBody2D

@export var stats: UnitStats

## ── Runtime state ─────────────────────────────────────────────────────────────
var current_health:   float   = 0.0
var stamina:          float   = 1.0
var is_alive:         bool    = true
var is_selected:      bool    = false
var attack_timer:     float   = 0.0
var current_target            = null
var _move_target:     Vector2 = Vector2.ZERO
var _has_move_order:  bool    = false
var _home_pos:        Vector2 = Vector2.ZERO

## Burst fire state
var _burst_remaining: int   = 0
var _burst_timer:     float = 0.0

## Stamina constants
const S_DRAIN_COMBAT  := 0.030
const S_DRAIN_MOVE    := 0.005
const S_REGEN_REST    := 0.050
const S_REGEN_CMD     := 0.022
const S_FLEE_BELOW    := 0.18
const S_REJOIN_ABOVE  := 0.50

## Behaviour
enum B { IDLE, MOVE, ATTACK, FLEE }
var behaviour: B = B.IDLE

## Terrain (set by TerrainManager each frame)
var terrain_speed_mult:   float = 1.0
var terrain_damage_mult:  float = 1.0  ## > 1.0 = more damage on high ground
var terrain_attack_speed: float = 1.0  ## < 1.0 = fires faster on high ground

## Draw geometry
const DOT_R := 11.0
const BAR_W := 40.0
const BAR_H := 5.0
const HP_Y  := 16.0
const ST_Y  := 23.0

## Colour palette
const C_BG_GREEN  := Color(0.00, 0.60, 0.20)
const C_BG_RED    := Color(0.85, 0.07, 0.07)
const C_RU_BLUE   := Color(0.10, 0.20, 0.75)
const C_RU_WHITE  := Color(0.92, 0.92, 0.92)
const C_OT_RED    := Color(0.78, 0.05, 0.05)
const C_GOLD      := Color(1.00, 0.85, 0.15)
const C_WHITE     := Color(0.92, 0.92, 0.92)
const C_RU_RING   := Color(0.85, 0.07, 0.07)

## Hit flash
var _hit_flash:   float = 0.0
const FLASH_DUR := 0.18

## Floating damage popup
var _dmg_popup:       float = 0.0
var _dmg_popup_value: float = 0.0
const POPUP_DUR := 0.85

## Reinforcement banner
var _banner_text:  String = ""
var _banner_timer: float  = 0.0
const BANNER_DUR := 4.5

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


func show_banner(text: String) -> void:
	_banner_text  = text
	_banner_timer = BANNER_DUR


func _physics_process(delta: float) -> void:
	if not stats or not is_alive:
		return
	TerrainManager.apply_terrain(self)
	_update_stamina(delta)
	_commander_aura_regen(delta)
	_update_behaviour(delta)
	_update_attack(delta)
	_update_burst(delta)

	if _hit_flash > 0.0:    _hit_flash    = max(0.0, _hit_flash - delta)
	if _dmg_popup > 0.0:    _dmg_popup    = max(0.0, _dmg_popup - delta)
	if _banner_timer > 0.0: _banner_timer = max(0.0, _banner_timer - delta)

	queue_redraw()


## ── Stamina ───────────────────────────────────────────────────────────────────

func _update_stamina(delta: float) -> void:
	var fighting = current_target != null and is_instance_valid(current_target)
	var moving   = velocity.length() > 5.0
	if fighting:
		stamina -= S_DRAIN_COMBAT * delta
	elif moving:
		stamina -= S_DRAIN_MOVE * delta
	else:
		stamina += S_REGEN_REST * delta
	stamina = clamp(stamina, 0.0, 1.0)


func _commander_aura_regen(delta: float) -> void:
	for ally in GameManager.allies_of(stats.faction):
		if not is_instance_valid(ally) or not ally.is_alive: continue
		if ally == self: continue
		if ally.stats.unit_type != UnitStats.UnitType.COMMANDER: continue
		if global_position.distance_to(ally.global_position) <= ally.stats.aura_radius:
			stamina = min(1.0, stamina + S_REGEN_CMD * delta)
			break


## ── Behaviour ─────────────────────────────────────────────────────────────────

func _update_behaviour(delta: float) -> void:
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
			if not current_target:
				var e = _nearest_enemy_in_range()
				if e: current_target = e

		B.ATTACK:
			if current_target and is_instance_valid(current_target):
				if stats.range < 80 and _dist_to(current_target) > stats.range * 0.85:
					_move_toward(current_target.global_position, delta)
			else:
				current_target = null
				behaviour = B.IDLE

		B.IDLE:
			velocity = Vector2.ZERO
			move_and_slide()
			var e = _nearest_enemy_in_range()
			if e:
				current_target = e
				behaviour = B.ATTACK


## ── Player / AI commands ──────────────────────────────────────────────────────

func order_move(pos: Vector2) -> void:
	_move_target    = pos
	_has_move_order = true
	current_target  = null
	behaviour       = B.MOVE

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

func _compute_damage() -> float:
	## High ground: terrain_damage_mult > 1.0. Stamina also scales.
	return stats.damage * terrain_damage_mult * stamina


func _update_attack(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target) or not current_target.is_alive:
		current_target = null
		if behaviour == B.ATTACK: behaviour = B.IDLE
		return
	if _dist_to(current_target) > stats.range * 1.15:
		return
	attack_timer -= delta
	## terrain_attack_speed < 1.0 means faster fire on high ground
	if attack_timer <= 0.0:
		_fire()
		attack_timer = stats.attack_cooldown * terrain_attack_speed


func _update_burst(delta: float) -> void:
	if _burst_remaining <= 0: return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		if current_target and is_instance_valid(current_target) and current_target.is_alive:
			_emit_single_shot(current_target, _compute_damage())
		_burst_remaining -= 1
		_burst_timer = stats.burst_interval if _burst_remaining > 0 else 0.0


func _fire() -> void:
	if stats.heal_per_second > 0:
		_do_heal()
		return

	var dmg = _compute_damage()

	if stats.burst_count > 1:
		_emit_single_shot(current_target, dmg)
		_burst_remaining = stats.burst_count - 1
		_burst_timer     = stats.burst_interval
		return

	if stats.aoe_radius > 0:
		emit_signal("fired_projectile", {
			"from": global_position,
			"target_pos": current_target.global_position,
			"damage": dmg, "speed": stats.projectile_speed,
			"size": stats.projectile_size, "aoe": stats.aoe_radius,
			"faction": stats.faction
		})
	elif stats.projectile_speed > 0:
		_emit_single_shot(current_target, dmg)
	else:
		current_target.take_damage(dmg)


func _emit_single_shot(target, dmg: float) -> void:
	emit_signal("fired_projectile", {
		"from": global_position, "target": target,
		"damage": dmg, "speed": stats.projectile_speed,
		"size": stats.projectile_size, "aoe": 0.0,
		"faction": stats.faction
	})


func _do_heal() -> void:
	for ally in GameManager.allies_of(stats.faction):
		if not is_instance_valid(ally) or ally == self: continue
		if global_position.distance_to(ally.global_position) <= stats.heal_radius:
			ally.current_health = min(
				ally.current_health + stats.heal_per_second * stats.attack_cooldown,
				ally.stats.max_health)


func take_damage(amount: float) -> void:
	current_health -= max(amount, 0.0)
	current_health  = max(current_health, 0.0)
	_hit_flash       = FLASH_DUR
	_dmg_popup_value = amount
	_dmg_popup       = POPUP_DUR
	if current_health <= 0.0:
		_die()


func _die() -> void:
	is_alive = false
	emit_signal("died", self)
	queue_free()


## ── Selection ─────────────────────────────────────────────────────────────────

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
	var alpha    = lerp(0.40, 1.0, stamina)
	var font     = ThemeDB.fallback_font

	## Hit-flash blend
	var body: Color
	var ring: Color
	if _hit_flash > 0.0:
		var f = _hit_flash / FLASH_DUR
		body = fc.body.lerp(Color(1, 1, 1), f * 0.80)
		ring = fc.ring.lerp(Color(1, 1, 1), f * 0.55)
	else:
		body = Color(fc.body.r, fc.body.g, fc.body.b, alpha)
		ring = Color(fc.ring.r, fc.ring.g, fc.ring.b, alpha)

	draw_circle(Vector2(1,1), DOT_R, Color(0,0,0,0.24*alpha))
	draw_circle(Vector2.ZERO, DOT_R, body)
	draw_arc(Vector2.ZERO, DOT_R+1.5, 0, TAU, 48, ring, 2.2)

	## High-ground shimmer
	if terrain_damage_mult > 1.05:
		var t    = Time.get_ticks_msec() * 0.002
		var sh_a = (sin(t) * 0.5 + 0.5) * 0.50 * alpha
		draw_arc(Vector2.ZERO, DOT_R + 3.5, -PI * 0.72, -PI * 0.28, 16,
			Color(1.0, 0.88, 0.20, sh_a), 2.5)

	## Symbol
	if stats.faction == 1:
		_draw_crescent(alpha)
	elif stats.unit_type != UnitStats.UnitType.COMMANDER:
		_draw_cross(alpha)

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
		if stats.heal_radius > 0:
			draw_arc(Vector2.ZERO, stats.heal_radius, 0, TAU, 64, Color(0.15,0.95,0.55,0.20), 1.2)
		_draw_dashed_range(stats.range, Color(1,1,1,0.10), 32)

	_draw_bar(HP_Y, hp_ratio,
		Color(0.18,0.82,0.22) if hp_ratio>0.6 else (Color(0.95,0.76,0.06) if hp_ratio>0.3 else Color(0.92,0.15,0.10)))
	_draw_bar(ST_Y, stamina, Color(0.15,0.65,0.95))

	## ── Unit name above the dot ────────────────────────────────────────────────
	var name_str = _short_name()
	var tw       = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var name_y   = -(DOT_R + 11.0)
	## Dark backing for readability
	draw_rect(Rect2(-tw*0.5 - 3, name_y - 10, tw + 6, 12),
		Color(0, 0, 0, 0.45 * alpha))
	var name_col = Color(1.0, 1.0, 1.0, 0.90 * alpha) if stats.faction == 0 \
		else Color(1.0, 0.76, 0.76, 0.90 * alpha)
	draw_string(font, Vector2(-tw * 0.5, name_y),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, name_col)

	## Troop scale
	draw_string(font, Vector2(-18, ST_Y+BAR_H+10), "1,000",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1,1,1,0.35*alpha))

	## Floating damage
	if _dmg_popup > 0.0 and _dmg_popup_value > 0.0:
		var prog  = 1.0 - (_dmg_popup / POPUP_DUR)
		var pop_y = -(DOT_R + 26.0 + prog * 18.0)
		var pop_a = clamp(_dmg_popup / POPUP_DUR, 0.0, 1.0)
		draw_string(font, Vector2(-10, pop_y), "-%d" % int(_dmg_popup_value),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.28, 0.08, pop_a))

	## Reinforcement banner
	if _banner_timer > 0.0:
		var ba  = clamp(_banner_timer / 1.5, 0.0, 1.0)
		var btw = font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_rect(Rect2(-btw*0.5 - 5, -(DOT_R + 52), btw + 10, 16),
			Color(0.04, 0.04, 0.10, 0.88 * ba))
		draw_string(font, Vector2(-btw * 0.5, -(DOT_R + 39)),
			_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.92, 0.25, ba))


## ── Helpers ───────────────────────────────────────────────────────────────────

func _short_name() -> String:
	if not stats: return "?"
	var n = stats.display_name
	## Strip parenthetical suffix for brevity
	var paren = n.find("(")
	if paren > 2:
		n = n.substr(0, paren).strip_edges()
	if n.length() > 18:
		n = n.substr(0, 17) + "…"
	return n


func _draw_dashed_range(radius: float, col: Color, segments: int) -> void:
	for i in segments:
		if i % 2 == 0: continue
		var a0 = i * TAU / segments
		var a1 = (i+1) * TAU / segments
		draw_arc(Vector2.ZERO, radius, a0, a1, 4, col, 1.0)


func _draw_bar(y: float, ratio: float, col: Color) -> void:
	var bx = -BAR_W*0.5
	draw_rect(Rect2(bx-1, y-1, BAR_W+2, BAR_H+2), Color(0,0,0,0.62))
	draw_rect(Rect2(bx,   y,   BAR_W,   BAR_H  ), Color(0.08,0.08,0.08,0.85))
	if ratio > 0:
		draw_rect(Rect2(bx, y, BAR_W*ratio, BAR_H), col)
	draw_rect(Rect2(bx-1, y-1, BAR_W+2, BAR_H+2), Color(0,0,0,0.40), false, 0.7)


func _draw_crescent(alpha: float) -> void:
	draw_arc(Vector2(-1.5,-1.0), 6.0, deg_to_rad(200), deg_to_rad(360), 20,
		Color(1,1,1,0.90*alpha), 2.0)
	draw_arc(Vector2( 1.5,-1.0), 4.5, deg_to_rad(200), deg_to_rad(360), 20,
		_faction_colors().body, 2.5)
	_draw_star(Vector2(7,-4), 2.2, Color(1,1,1,0.80*alpha))


func _draw_cross(alpha: float) -> void:
	var col: Color
	if stats.unit_type == UnitStats.UnitType.CAVALRY or stats.unit_type == UnitStats.UnitType.MEDIC:
		col = Color(0.85,0.07,0.07, 0.85*alpha)
	else:
		col = Color(1.0,1.0,1.0, 0.75*alpha)
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


func _nearest_enemy_in_range():
	var enemies    = GameManager.enemies_of(stats.faction)
	var best       = null
	var best_score = -INF
	var lookahead  = stats.range * 2.5
	for e in enemies:
		if not e.is_alive: continue
		var d = global_position.distance_to(e.global_position)
		if d > lookahead: continue
		var hp_ratio = e.current_health / e.stats.max_health if e.stats.max_health > 0 else 1.0
		var score    = -d + (1.0 - hp_ratio) * stats.range * 0.5
		if score > best_score:
			best_score = score
			best = e
	return best


func _dist_to(other) -> float:
	return global_position.distance_to(other.global_position)

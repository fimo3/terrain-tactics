extends Node2D

var target              = null       ## enemy unit (tracks position)
var target_pos: Vector2 = Vector2.ZERO
var damage:     float   = 0.0
var speed:      float   = 300.0
var aoe_radius: float   = 0.0
var faction:    int     = 0          ## 0 = BG/RU, 1 = Ottoman

## Visual state
var _arrived:        bool    = false
var _explode_timer:  float   = 0.0
var _exploding:      bool    = false
const EXPLODE_DURATION := 0.35

## Tail trail — last N positions
var _trail: Array[Vector2] = []
const TRAIL_LEN := 8

## Rotation angle (computed from velocity)
var _angle: float = 0.0


func _ready() -> void:
	z_index = 10   ## draw above units


func _process(delta: float) -> void:
	if _exploding:
		_explode_timer -= delta
		queue_redraw()
		if _explode_timer <= 0.0:
			queue_free()
		return

	if _arrived:
		return

	var dest: Vector2
	if target and is_instance_valid(target) and target.is_alive:
		dest = target.global_position
	else:
		dest = target_pos

	var dir = dest - global_position
	var step = speed * delta

	if dir.length() < step + 4.0:
		global_position = dest
		_on_arrive()
	else:
		var move = dir.normalized() * step
		_angle = move.angle()
		_trail.append(global_position)
		if _trail.size() > TRAIL_LEN:
			_trail.pop_front()
		global_position += move

	queue_redraw()


func _on_arrive() -> void:
	_arrived = true
	if aoe_radius > 0:
		_apply_aoe()
		_exploding      = true
		_explode_timer  = EXPLODE_DURATION
		queue_redraw()
	else:
		if target and is_instance_valid(target) and target.is_alive:
			target.take_damage(damage)
		## Small impact flash then free
		_exploding     = true
		_explode_timer = 0.12
		aoe_radius     = 12.0   ## tiny flash radius for visual only


func _apply_aoe() -> void:
	for unit in GameManager.all_units:
		if not unit.is_alive: continue
		if unit.stats.faction == faction: continue
		if global_position.distance_to(unit.global_position) <= aoe_radius:
			unit.take_damage(damage)


## ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _exploding:
		_draw_explosion()
		return
	if aoe_radius > 0:
		_draw_cannonball()
	else:
		_draw_bullet()


func _draw_bullet() -> void:
	## Trail
	var trail_count = _trail.size()
	for i in trail_count:
		var tp   = to_local(_trail[i])
		var frac = float(i) / float(TRAIL_LEN)
		var col  = _bullet_color().darkened(0.3)
		col.a    = frac * 0.5
		draw_circle(tp, lerp(1.0, 3.0, frac), col)

	## Bullet body — elongated oval along travel direction
	var col = _bullet_color()
	## Draw as a short line to look like a fast-moving round
	var back = Vector2(-cos(_angle), -sin(_angle)) * 6.0
	draw_line(Vector2.ZERO, back, Color(col.r, col.g, col.b, 0.5), 2.5, true)
	draw_circle(Vector2.ZERO, 3.0, col)

	## Faction mark — tiny crescent or cross
	if faction == 1:
		## Ottoman: white dot centre
		draw_circle(Vector2.ZERO, 1.2, Color(1,1,1,0.8))
	else:
		## BG/RU: slightly lighter core
		draw_circle(Vector2.ZERO, 1.5, col.lightened(0.5))


func _draw_cannonball() -> void:
	## Trail — wide smoky trail
	var trail_count = _trail.size()
	for i in trail_count:
		var tp   = to_local(_trail[i])
		var frac = float(i) / float(TRAIL_LEN)
		draw_circle(tp, lerp(2.0, 6.0, frac), Color(0.3, 0.3, 0.3, frac * 0.35))

	## Shadow
	draw_circle(Vector2(2, 2), 7.0, Color(0, 0, 0, 0.25))
	## Iron ball
	draw_circle(Vector2.ZERO, 7.0, Color(0.18, 0.18, 0.20))
	## Highlight
	draw_circle(Vector2(-2, -2), 2.5, Color(0.45, 0.45, 0.50, 0.8))


func _draw_explosion() -> void:
	var progress = 1.0 - (_explode_timer / EXPLODE_DURATION)
	var radius   = aoe_radius * progress
	var alpha    = (1.0 - progress) * 0.9

	if aoe_radius > 20:
		## Full cannon explosion
		## Outer shockwave ring
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64,
			Color(1.0, 0.6, 0.1, alpha * 0.5), 3.0)
		## Inner fire fill
		draw_circle(Vector2.ZERO, radius * 0.65,
			Color(1.0, 0.35, 0.05, alpha * 0.75))
		## Bright core
		draw_circle(Vector2.ZERO, radius * 0.30,
			Color(1.0, 0.9,  0.6,  alpha))
		## Debris dots
		for i in 8:
			var angle  = i * TAU / 8.0 + progress * 3.0
			var dist   = radius * 0.8
			var dp     = Vector2(cos(angle), sin(angle)) * dist
			draw_circle(dp, 3.0, Color(0.9, 0.4, 0.1, alpha * 0.7))
	else:
		## Small bullet impact flash
		draw_circle(Vector2.ZERO, radius,
			Color(1.0, 0.85, 0.3, alpha * 0.8))
		draw_circle(Vector2.ZERO, radius * 0.5,
			Color(1.0, 1.0,  0.8, alpha))


## ── Helpers ───────────────────────────────────────────────────────────────────

func _bullet_color() -> Color:
	if faction == 1:
		return Color(1.0, 0.75, 0.20)   ## Ottoman — gold/brass cartridge
	return Color(0.75, 0.85, 1.00)      ## BG/RU   — steel blue

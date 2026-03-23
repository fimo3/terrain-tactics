extends Node2D

var target              = null
var target_pos: Vector2 = Vector2.ZERO
var damage:     float   = 0.0
var speed:      float   = 300.0
var aoe_radius: float   = 0.0
var faction:    int     = 0

var _arrived:        bool    = false
var _explode_timer:  float   = 0.0
var _exploding:      bool    = false
const EXPLODE_DURATION := 0.38

## Tail trail
var _trail: Array[Vector2] = []
const TRAIL_LEN := 10

var _angle: float = 0.0

## Wobble for cannonballs (slight arc simulation)
var _wobble_phase: float = 0.0


func _ready() -> void:
	z_index = 10
	_wobble_phase = randf() * TAU


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

	var dir  = dest - global_position
	var step = speed * delta

	_wobble_phase += delta * 5.0

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
		_exploding     = true
		_explode_timer = EXPLODE_DURATION
	else:
		if target and is_instance_valid(target) and target.is_alive:
			target.take_damage(damage)
		_exploding     = true
		_explode_timer = 0.14
		aoe_radius     = 14.0   ## visual-only flash radius
	queue_redraw()


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
	var col      = _bullet_color()
	var trail_n  = _trail.size()
	for i in trail_n:
		var tp   = to_local(_trail[i])
		var frac = float(i) / float(TRAIL_LEN)
		var tc   = Color(col.r, col.g, col.b, frac * 0.45)
		draw_circle(tp, lerp(0.8, 2.5, frac), tc)

	## Elongated bullet along travel direction
	var back = Vector2(-cos(_angle), -sin(_angle)) * 7.0
	draw_line(Vector2.ZERO, back, Color(col.r, col.g, col.b, 0.45), 2.2, true)
	draw_circle(Vector2.ZERO, 3.2, col)

	if faction == 1:
		draw_circle(Vector2.ZERO, 1.2, Color(1,1,1,0.8))
	else:
		draw_circle(Vector2.ZERO, 1.5, col.lightened(0.45))


func _draw_cannonball() -> void:
	var trail_n = _trail.size()
	## Smoke trail — blobs that fade and expand
	for i in trail_n:
		var tp   = to_local(_trail[i])
		var frac = float(i) / float(TRAIL_LEN)
		var r    = lerp(3.0, 9.0, frac)
		var a    = frac * 0.28
		draw_circle(tp, r, Color(0.25, 0.25, 0.28, a))

	## Slight wobble (cannonball arc illusion)
	var wobble = Vector2(0, sin(_wobble_phase) * 1.5)

	## Drop shadow
	draw_circle(wobble + Vector2(2.5, 3.0), 7.5, Color(0, 0, 0, 0.22))
	## Iron ball
	draw_circle(wobble, 7.5, Color(0.16, 0.16, 0.18))
	## Specular highlight
	draw_circle(wobble + Vector2(-2.2, -2.2), 2.8, Color(0.42, 0.42, 0.48, 0.80))
	draw_circle(wobble + Vector2(-3.0, -3.0), 1.0, Color(0.65, 0.65, 0.70, 0.55))


func _draw_explosion() -> void:
	var progress = 1.0 - (_explode_timer / EXPLODE_DURATION)
	var radius   = aoe_radius * progress
	var alpha    = (1.0 - progress) * 0.95

	if aoe_radius > 20:
		## Cannon explosion
		## Shockwave ring
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64,
			Color(1.0, 0.6, 0.1, alpha * 0.45), 3.5)
		## Outer fire fill
		draw_circle(Vector2.ZERO, radius * 0.70,
			Color(1.0, 0.30, 0.04, alpha * 0.70))
		## Inner bright core
		draw_circle(Vector2.ZERO, radius * 0.38,
			Color(1.0, 0.85, 0.55, alpha * 0.90))
		## Hot white centre
		draw_circle(Vector2.ZERO, radius * 0.15,
			Color(1.0, 1.0, 0.9, alpha))
		## Flying debris
		for i in 10:
			var angle = i * TAU / 10.0 + progress * 4.2
			var dist  = radius * lerp(0.5, 0.95, float(i) / 10.0)
			var dp    = Vector2(cos(angle), sin(angle)) * dist
			var dr    = lerp(4.0, 1.5, progress)
			draw_circle(dp, dr, Color(0.85, 0.35, 0.08, alpha * 0.65))
		## Ground scorch ring
		if progress > 0.5:
			draw_arc(Vector2.ZERO, aoe_radius * 0.55, 0, TAU, 48,
				Color(0.2, 0.1, 0.05, (progress - 0.5) * 0.3), 2.0)
	else:
		## Small bullet impact flash
		draw_circle(Vector2.ZERO, radius,
			Color(1.0, 0.88, 0.35, alpha * 0.85))
		draw_circle(Vector2.ZERO, radius * 0.45,
			Color(1.0, 1.0, 0.85, alpha))


func _bullet_color() -> Color:
	if faction == 1:
		return Color(1.0, 0.75, 0.20)   ## Ottoman — brass/gold
	return Color(0.75, 0.88, 1.00)      ## BG/RU   — steel blue

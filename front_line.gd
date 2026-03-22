extends Node2D
## FrontLine — draws a live boundary between the two forces.
## Add as a child of main (same level as units), below the Ground sprite in draw order.
##
## Algorithm:
##   1. Sample a grid of columns across the battlefield
##   2. For each column, find the midpoint between the nearest BG unit and nearest OT unit
##   3. Smooth the midpoints with a moving average
##   4. Draw a filled poly for each side + a glowing border line
##   5. Animate the border with a subtle wave

## How wide/tall the battlefield is — match your map bounds
@export var map_left:   float = -700.0
@export var map_right:  float =  700.0
@export var map_top:    float = -600.0
@export var map_bottom: float =  600.0

## Number of sample columns — more = smoother line, more CPU
@export var columns:    int   = 40

## How much to smooth the line (0 = none, 1 = fully flat)
@export var smoothing:  float = 0.65

## Colors
const C_BG_FILL  := Color(0.10, 0.20, 0.75, 0.10)   ## Russian blue tint
const C_OT_FILL  := Color(0.78, 0.05, 0.05, 0.10)   ## Ottoman red tint
const C_LINE     := Color(1.00, 1.00, 1.00, 0.55)   ## white border
const C_GLOW     := Color(1.00, 1.00, 1.00, 0.12)   ## soft glow halo

## Smoothed midpoint y-values for each column
var _mids: PackedFloat32Array

## Animated wave offset
var _wave_offset: float = 0.0


func _ready() -> void:
	_mids.resize(columns)
	_mids.fill((map_top + map_bottom) * 0.5)
	## Sit just above the ground, below the units
	z_index = -1


func _process(delta: float) -> void:
	_wave_offset += delta * 0.8
	_compute_front_line()
	queue_redraw()


## ── Compute ───────────────────────────────────────────────────────────────────

func _compute_front_line() -> void:
	var bg_units = GameManager.bulgarian_units
	var ot_units = GameManager.ottoman_units

	if bg_units.is_empty() or ot_units.is_empty():
		return

	var col_w = (map_right - map_left) / float(columns)
	var raw   = PackedFloat32Array()
	raw.resize(columns)

	for c in columns:
		var cx = map_left + (c + 0.5) * col_w

		## Find nearest BG and OT unit to this column's x position
		var nearest_bg_y = map_top
		var nearest_ot_y = map_bottom
		var best_bg_dist = INF
		var best_ot_dist = INF

		for u in bg_units:
			if not u.is_alive: continue
			var dx = abs(u.global_position.x - cx)
			if dx < best_bg_dist:
				best_bg_dist = dx
				nearest_bg_y = u.global_position.y

		for u in ot_units:
			if not u.is_alive: continue
			var dx = abs(u.global_position.x - cx)
			if dx < best_ot_dist:
				best_ot_dist = dx
				nearest_ot_y = u.global_position.y

		raw[c] = (nearest_bg_y + nearest_ot_y) * 0.5

	## Smooth across columns
	for c in columns:
		var prev = raw[c - 1] if c > 0           else raw[c]
		var next = raw[c + 1] if c < columns - 1 else raw[c]
		var smooth_val = prev * 0.25 + raw[c] * 0.5 + next * 0.25
		_mids[c] = lerp(_mids[c], smooth_val, 1.0 - smoothing)


## ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _mids.is_empty():
		return

	var col_w = (map_right - map_left) / float(columns)

	## Build the front-line polyline with a subtle sine wave
	var line_pts = PackedVector2Array()
	line_pts.resize(columns)
	for c in columns:
		var x    = map_left + (c + 0.5) * col_w
		var wave = sin(_wave_offset + c * 0.4) * 4.0
		line_pts[c] = Vector2(x, _mids[c] + wave)

	## ── BG territory fill (above the line = defenders' territory) ──
	var bg_poly = PackedVector2Array()
	bg_poly.append(Vector2(map_left,  map_top))
	bg_poly.append(Vector2(map_right, map_top))
	for c in range(columns - 1, -1, -1):
		bg_poly.append(line_pts[c])
	draw_colored_polygon(bg_poly, C_BG_FILL)

	## ── OT territory fill (below the line = Ottoman territory) ──
	var ot_poly = PackedVector2Array()
	for c in columns:
		ot_poly.append(line_pts[c])
	ot_poly.append(Vector2(map_right, map_bottom))
	ot_poly.append(Vector2(map_left,  map_bottom))
	draw_colored_polygon(ot_poly, C_OT_FILL)

	## ── Glow halo (thicker, more transparent) ──
	draw_polyline(line_pts, C_GLOW, 7.0, true)

	## ── Main border line ──
	draw_polyline(line_pts, C_LINE, 2.0, true)

	## ── Side labels ──
	if not GameManager.bulgarian_units.is_empty():
		var label_y = line_pts[0].y - 40.0
		label_y = clamp(label_y, map_top + 20, map_bottom - 20)
		draw_string(ThemeDB.fallback_font,
			Vector2(map_left + 12, label_y),
			"Russia & Opalchentsi",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.55, 0.75, 1.0, 0.70))

	if not GameManager.ottoman_units.is_empty():
		var label_y = line_pts[columns - 1].y + 22.0
		label_y = clamp(label_y, map_top + 20, map_bottom - 20)
		draw_string(ThemeDB.fallback_font,
			Vector2(map_right - 12, label_y),
			"Ottoman Empire",
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 13,
			Color(1.0, 0.55, 0.55, 0.70))

extends Node2D
## FrontLine — draws a live boundary between the two forces.
## Add as a child of main (same level as units), below units in draw order.
##
## Algorithm:
##   1. Sample a grid of columns across the battlefield
##   2. For each column, find the southernmost BG unit and northernmost OT unit
##      (accounts for the N/S orientation of the battle)
##   3. Compute midpoint between the two, clamp to map bounds
##   4. Smooth with exponential moving average
##   5. Draw filled territory polys + glowing animated border

@export var map_left:   float = -700.0
@export var map_right:  float =  700.0
@export var map_top:    float = -600.0
@export var map_bottom: float =  600.0
@export var columns:    int   = 44
@export var smoothing:  float = 0.70

const C_BG_FILL  := Color(0.10, 0.20, 0.75, 0.08)
const C_OT_FILL  := Color(0.78, 0.05, 0.05, 0.08)
const C_LINE     := Color(1.00, 1.00, 1.00, 0.50)
const C_GLOW     := Color(1.00, 1.00, 1.00, 0.10)
const C_GLOW2    := Color(1.00, 0.80, 0.40, 0.06)  ## warm secondary glow

var _mids: PackedFloat32Array
var _wave_offset: float = 0.0

## Cache last valid midpoint per column to handle empty-side gracefully
var _last_valid_mids: PackedFloat32Array


func _ready() -> void:
	var mid = (map_top + map_bottom) * 0.5
	_mids.resize(columns)
	_mids.fill(mid)
	_last_valid_mids.resize(columns)
	_last_valid_mids.fill(mid)
	z_index = -1


func _process(delta: float) -> void:
	_wave_offset += delta * 0.7
	_compute_front_line()
	queue_redraw()


## ── Compute ───────────────────────────────────────────────────────────────────

func _compute_front_line() -> void:
	var bg_units = GameManager.bulgarian_units
	var ot_units = GameManager.ottoman_units

	## If one side is gone, freeze the line
	if bg_units.is_empty() or ot_units.is_empty():
		return

	var col_w = (map_right - map_left) / float(columns)
	var raw   = PackedFloat32Array()
	raw.resize(columns)

	for c in columns:
		var cx = map_left + (c + 0.5) * col_w

		## Find the southernmost (highest Y) BG unit and northernmost (lowest Y) OT unit
		## near this column — these represent the front edge of each side.
		var frontier_bg_y = map_top      ## BG pushes south, so we want their southernmost
		var frontier_ot_y = map_bottom   ## OT pushes north, so we want their northernmost

		var col_half = col_w * 2.5   ## search radius in X for this column

		var found_bg := false
		var found_ot := false

		for u in bg_units:
			if not u.is_alive: continue
			var dx = abs(u.global_position.x - cx)
			if dx > col_half: continue
			if u.global_position.y > frontier_bg_y or not found_bg:
				frontier_bg_y = u.global_position.y
				found_bg = true

		for u in ot_units:
			if not u.is_alive: continue
			var dx = abs(u.global_position.x - cx)
			if dx > col_half: continue
			if u.global_position.y < frontier_ot_y or not found_ot:
				frontier_ot_y = u.global_position.y
				found_ot = true

		if found_bg and found_ot:
			raw[c] = (frontier_bg_y + frontier_ot_y) * 0.5
			_last_valid_mids[c] = raw[c]
		else:
			## Fall back to last known value for this column
			raw[c] = _last_valid_mids[c]

	## Three-point smooth
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

	## Build the animated front-line polyline
	var line_pts = PackedVector2Array()
	line_pts.resize(columns)
	for c in columns:
		var x    = map_left + (c + 0.5) * col_w
		var wave = sin(_wave_offset + c * 0.38) * 3.5 + sin(_wave_offset * 1.7 + c * 0.8) * 1.5
		line_pts[c] = Vector2(x, clamp(_mids[c] + wave, map_top, map_bottom))

	## BG territory fill (above the line)
	var bg_poly = PackedVector2Array()
	bg_poly.append(Vector2(map_left,  map_top))
	bg_poly.append(Vector2(map_right, map_top))
	for c in range(columns - 1, -1, -1):
		bg_poly.append(line_pts[c])
	draw_colored_polygon(bg_poly, C_BG_FILL)

	## OT territory fill (below the line)
	var ot_poly = PackedVector2Array()
	for c in columns:
		ot_poly.append(line_pts[c])
	ot_poly.append(Vector2(map_right, map_bottom))
	ot_poly.append(Vector2(map_left,  map_bottom))
	draw_colored_polygon(ot_poly, C_OT_FILL)

	## Warm secondary glow (slightly offset)
	var glow2_pts = PackedVector2Array()
	glow2_pts.resize(columns)
	for c in columns:
		glow2_pts[c] = line_pts[c] + Vector2(0, 4)
	draw_polyline(glow2_pts, C_GLOW2, 9.0, true)

	## White glow halo
	draw_polyline(line_pts, C_GLOW, 7.0, true)

	## Main border line
	draw_polyline(line_pts, C_LINE, 1.8, true)

	## Side labels (positioned relative to line, clamped to map)
	_draw_side_label(line_pts, true)
	_draw_side_label(line_pts, false)


func _draw_side_label(line_pts: PackedVector2Array, bg_side: bool) -> void:
	if line_pts.is_empty(): return

	if bg_side:
		if GameManager.bulgarian_units.is_empty(): return
		var y = clamp(line_pts[0].y - 38.0, map_top + 16, map_bottom - 16)
		draw_string(ThemeDB.fallback_font,
			Vector2(map_left + 10, y),
			"Russia & Opalchentsi",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.55, 0.78, 1.0, 0.65))
	else:
		if GameManager.ottoman_units.is_empty(): return
		var y = clamp(line_pts[columns - 1].y + 20.0, map_top + 16, map_bottom - 16)
		draw_string(ThemeDB.fallback_font,
			Vector2(map_right - 10, y),
			"Ottoman Empire",
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 12,
			Color(1.0, 0.60, 0.55, 0.65))

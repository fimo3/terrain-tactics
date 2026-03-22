extends Node
## TerrainManager — autoload singleton ("TerrainManager")
## Colors mapped directly from the gradient in main.tscn.

enum TerrainType {
	OPEN_SLOPE,    ## mid greens H 0.22–0.36 — neutral
	FOREST,        ## pure green H 0.32–0.45 — cover, slow
	DEEP_COVER,    ## dark teal  H 0.45–0.60 — heavy cover, very slow
	HIGH_RIDGE,    ## blue/purple H 0.60–0.68 — defenders' advantage
	SNOW_PEAK,     ## bright yellow H 0.14–0.19 S>0.85 — Eagle's Nest summit
	PASS_ROAD,     ## yellow-gold H 0.10–0.22 — fast but exposed
	DANGER_ZONE,   ## orange-red H 0.05–0.10 — Ottoman assault axis, very exposed
}

## speed:   movement multiplier (1.0 = normal)
## defense: incoming damage multiplier (< 1.0 = less damage taken)
## stamina: stamina drain multiplier (< 1.0 = drains slower)
const EFFECTS := {
	TerrainType.OPEN_SLOPE:  { "speed": 1.00, "defense": 1.00, "stamina": 1.00,
		"label": "Open slope",    "tip": "No advantage or penalty" },
	TerrainType.FOREST:      { "speed": 0.72, "defense": 0.88, "stamina": 0.88,
		"label": "Forest",        "tip": "+12% def, -28% speed, less tiring" },
	TerrainType.DEEP_COVER:  { "speed": 0.55, "defense": 0.80, "stamina": 0.82,
		"label": "Dense forest",  "tip": "+20% def, -45% speed, hides units" },
	TerrainType.HIGH_RIDGE:  { "speed": 0.60, "defense": 0.74, "stamina": 0.78,
		"label": "High ridge",    "tip": "+26% def, -40% speed — Opalchentsi stronghold" },
	TerrainType.SNOW_PEAK:   { "speed": 0.45, "defense": 0.60, "stamina": 0.70,
		"label": "Eagle's Nest",  "tip": "+40% def, -55% speed — summit fortress" },
	TerrainType.PASS_ROAD:   { "speed": 1.20, "defense": 1.18, "stamina": 1.22,
		"label": "Pass road",     "tip": "+20% speed, -18% def, tires faster — exposed" },
	TerrainType.DANGER_ZONE: { "speed": 1.15, "defense": 1.25, "stamina": 1.32,
		"label": "Exposed flank", "tip": "+15% speed, -25% def, drains stamina fast" },
}

var ground_sprite = null
var _img:    Image   = null
var _tex_sz: Vector2 = Vector2.ZERO
var _scale:  Vector2 = Vector2.ONE
var _origin: Vector2 = Vector2.ZERO


func initialize(sprite) -> void:
	if not sprite or not is_instance_valid(sprite):
		push_warning("TerrainManager: sprite is null — terrain disabled")
		return
	ground_sprite = sprite
	if not sprite.texture:
		return
	var tex = sprite.texture
	if tex is NoiseTexture2D:
		if not tex.changed.is_connected(_on_tex_ready):
			tex.changed.connect(_on_tex_ready)
		var img = tex.get_image()
		if img:
			_cache(img)
	else:
		var img = tex.get_image()
		if img:
			_cache(img)


func _on_tex_ready() -> void:
	if ground_sprite and ground_sprite.texture:
		var img = ground_sprite.texture.get_image()
		if img:
			_cache(img)


func _cache(img: Image) -> void:
	_img    = img
	_tex_sz = Vector2(img.get_width(), img.get_height())
	if ground_sprite:
		_scale  = ground_sprite.scale
		_origin = ground_sprite.global_position


func apply_terrain(unit) -> void:
	if not _img:
		return
	var t  = sample(unit.global_position)
	var fx = EFFECTS[t]
	unit.terrain_speed_mult   = fx["speed"]
	unit.terrain_defense_mult = fx["defense"]
	## stamina drain is read by dot.gd via terrain_stamina_mult
	unit.terrain_stamina_mult = fx["stamina"]


func sample(world_pos: Vector2) -> TerrainType:
	if not _img:
		return TerrainType.OPEN_SLOPE
	var local = world_pos - _origin + (_tex_sz * _scale * 0.5)
	var uv    = (local / (_tex_sz * _scale)).clamp(Vector2.ZERO, Vector2.ONE)
	var px    = int(uv.x * (_tex_sz.x - 1))
	var py    = int(uv.y * (_tex_sz.y - 1))
	return _classify(_img.get_pixel(px, py))


func _classify(c: Color) -> TerrainType:
	var h = c.h
	var s = c.s
	var v = c.v

	## Very dark pixel → deep forest cover
	if v < 0.30:
		return TerrainType.DEEP_COVER

	## Blue / purple (H 0.60–0.68) → high rocky ridge
	if h >= 0.60 and h <= 0.70:
		return TerrainType.HIGH_RIDGE

	## Bright yellow with high saturation (H 0.14–0.19, S > 0.85) → snow peak / Eagle's Nest
	if h >= 0.14 and h <= 0.20 and s >= 0.85 and v >= 0.90:
		return TerrainType.SNOW_PEAK

	## Teal (H 0.45–0.60) → dense forest cover
	if h >= 0.45 and h < 0.60:
		return TerrainType.DEEP_COVER

	## Pure / dark green (H 0.32–0.45) → forest
	if h >= 0.32 and h < 0.45:
		return TerrainType.FOREST

	## Mid yellow-green (H 0.22–0.32) → open slope
	if h >= 0.22 and h < 0.32:
		return TerrainType.OPEN_SLOPE

	## Yellow-gold (H 0.10–0.22) → pass road, exposed
	if h >= 0.10 and h < 0.22:
		return TerrainType.PASS_ROAD

	## Orange-red (H 0.05–0.10) → danger zone, Ottoman assault axis
	if h >= 0.05 and h < 0.10:
		return TerrainType.DANGER_ZONE

	## Deep red / near-zero hue → also danger zone
	if h < 0.05 or h > 0.95:
		return TerrainType.DANGER_ZONE

	return TerrainType.OPEN_SLOPE


func get_label(world_pos: Vector2) -> String:
	return EFFECTS[sample(world_pos)]["label"]


func get_tip(world_pos: Vector2) -> String:
	return EFFECTS[sample(world_pos)]["tip"]


func is_high_ground(world_pos: Vector2) -> bool:
	var t = sample(world_pos)
	return t == TerrainType.HIGH_RIDGE or t == TerrainType.SNOW_PEAK

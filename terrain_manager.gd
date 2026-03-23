extends Node
## TerrainManager — autoload singleton ("TerrainManager")
## Design: higher altitude = more damage output + faster fire rate (+ slight speed penalty).
## Low ground / exposed = less damage, slower fire rate, slightly faster movement.

enum TerrainType {
	DANGER_ZONE,   ## orange-red  — Ottoman staging, lowest ground
	PASS_ROAD,     ## yellow-gold — open road, exposed
	OPEN_SLOPE,    ## mid green   — neutral mid-ground
	FOREST,        ## green       — light altitude cover
	DEEP_COVER,    ## dark teal   — mid-ridge, dense tree line
	HIGH_RIDGE,    ## blue/purple — defenders' ridge
	SNOW_PEAK,     ## bright yellow H 0.14–0.20, S>0.85 — Eagle's Nest summit
}

## speed_mult:      movement speed multiplier
## damage_mult:     outgoing damage multiplier (higher = hits harder)
## attack_speed:    attack cooldown multiplier (lower = fires faster)
## label / tip:     HUD display strings
const EFFECTS := {
	TerrainType.DANGER_ZONE: {
		"speed_mult": 1.10, "damage_mult": 0.78, "attack_speed": 1.25,
		"label": "Exposed flank",
		"tip": "+10% spd  •  -22% dmg  •  -25% fire rate (low ground)"
	},
	TerrainType.PASS_ROAD: {
		"speed_mult": 1.15, "damage_mult": 0.88, "attack_speed": 1.12,
		"label": "Pass road",
		"tip": "+15% spd  •  -12% dmg  •  -12% fire rate (open road)"
	},
	TerrainType.OPEN_SLOPE: {
		"speed_mult": 1.00, "damage_mult": 1.00, "attack_speed": 1.00,
		"label": "Open slope",
		"tip": "No terrain bonus or penalty"
	},
	TerrainType.FOREST: {
		"speed_mult": 0.82, "damage_mult": 1.10, "attack_speed": 0.94,
		"label": "Forest",
		"tip": "-18% spd  •  +10% dmg  •  +6% fire rate (light altitude)"
	},
	TerrainType.DEEP_COVER: {
		"speed_mult": 0.68, "damage_mult": 1.18, "attack_speed": 0.88,
		"label": "Dense forest",
		"tip": "-32% spd  •  +18% dmg  •  +12% fire rate (mid ridge)"
	},
	TerrainType.HIGH_RIDGE: {
		"speed_mult": 0.72, "damage_mult": 1.28, "attack_speed": 0.82,
		"label": "High ridge",
		"tip": "-28% spd  •  +28% dmg  •  +18% fire rate — Opalchentsi stronghold"
	},
	TerrainType.SNOW_PEAK: {
		"speed_mult": 0.55, "damage_mult": 1.45, "attack_speed": 0.72,
		"label": "Eagle's Nest",
		"tip": "-45% spd  •  +45% dmg  •  +28% fire rate — summit fortress"
	},
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
	if not sprite.texture: return
	var tex = sprite.texture
	if tex is NoiseTexture2D:
		if not tex.changed.is_connected(_on_tex_ready):
			tex.changed.connect(_on_tex_ready)
		var img = tex.get_image()
		if img: _cache(img)
	else:
		var img = tex.get_image()
		if img: _cache(img)


func _on_tex_ready() -> void:
	if ground_sprite and ground_sprite.texture:
		var img = ground_sprite.texture.get_image()
		if img: _cache(img)


func _cache(img: Image) -> void:
	_img    = img
	_tex_sz = Vector2(img.get_width(), img.get_height())
	if ground_sprite:
		_scale  = ground_sprite.scale
		_origin = ground_sprite.global_position


func apply_terrain(unit) -> void:
	if not _img: return
	var fx = EFFECTS[sample(unit.global_position)]
	unit.terrain_speed_mult   = fx["speed_mult"]
	unit.terrain_damage_mult  = fx["damage_mult"]
	unit.terrain_attack_speed = fx["attack_speed"]


func sample(world_pos: Vector2) -> TerrainType:
	if not _img: return TerrainType.OPEN_SLOPE
	var local = world_pos - _origin + (_tex_sz * _scale * 0.5)
	var uv    = (local / (_tex_sz * _scale)).clamp(Vector2.ZERO, Vector2.ONE)
	var px    = int(uv.x * (_tex_sz.x - 1))
	var py    = int(uv.y * (_tex_sz.y - 1))
	return _classify(_img.get_pixel(px, py))


func _classify(c: Color) -> TerrainType:
	var h = c.h
	var s = c.s
	var v = c.v

	if v < 0.30:                                              return TerrainType.DEEP_COVER
	if h >= 0.60 and h <= 0.70:                              return TerrainType.HIGH_RIDGE
	if h >= 0.14 and h <= 0.20 and s >= 0.85 and v >= 0.90: return TerrainType.SNOW_PEAK
	if h >= 0.45 and h < 0.60:                               return TerrainType.DEEP_COVER
	if h >= 0.32 and h < 0.45:                               return TerrainType.FOREST
	if h >= 0.22 and h < 0.32:                               return TerrainType.OPEN_SLOPE
	if h >= 0.10 and h < 0.22:                               return TerrainType.PASS_ROAD
	if h >= 0.05 and h < 0.10:                               return TerrainType.DANGER_ZONE
	if h < 0.05 or h > 0.95:                                 return TerrainType.DANGER_ZONE
	return TerrainType.OPEN_SLOPE


func get_label(world_pos: Vector2) -> String: return EFFECTS[sample(world_pos)]["label"]
func get_tip(world_pos: Vector2) -> String:   return EFFECTS[sample(world_pos)]["tip"]
func is_high_ground(world_pos: Vector2) -> bool:
	var t = sample(world_pos)
	return t == TerrainType.HIGH_RIDGE or t == TerrainType.SNOW_PEAK

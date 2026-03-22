extends Resource
class_name UnitStats

enum UnitType { RIFLEMAN, CAVALRY, CANNON, MEDIC, COMMANDER }
enum Faction { BULGARIAN_RUSSIAN, OTTOMAN }

@export var unit_type: UnitType = UnitType.RIFLEMAN
@export var faction: Faction = Faction.BULGARIAN_RUSSIAN
@export var display_name: String = "Unit"
@export var description: String = ""

## Movement
@export var speed: float = 60.0
@export var move_points: int = 3

## Combat
@export var max_health: float = 100.0
@export var damage: float = 12.0
@export var range: float = 180.0
@export var attack_cooldown: float = 1.5
@export var projectile_speed: float = 300.0
@export var projectile_size: float = 5.0
@export var aoe_radius: float = 0.0

## Special — Medic
@export var heal_per_second: float = 0.0
@export var heal_radius: float = 0.0

## Special — Commander aura
@export var aura_radius: float = 0.0
@export var aura_damage_bonus: float = 0.0    # additive multiplier e.g. 0.25 = +25%
@export var aura_speed_bonus: float = 0.0     # additive multiplier e.g. 0.15 = +15%
@export var aura_attack_speed_bonus: float = 0.0

## Special — Cavalry charge
@export var charge_damage_multiplier: float = 1.0  # 1.5 = +50% on first hit
@export var armor_pierce: float = 0.0              # flat damage ignored by target armor

## Special — Terrain
@export var high_ground_defense_bonus: float = 0.0  # e.g. 0.2 = +20% effective HP on hills
@export var burst_count: int = 1                     # shots per attack (Nizam volley = 3)
@export var burst_interval: float = 0.0             # seconds between burst shots

## Visuals
@export var unit_color: Color = Color.WHITE
@export var size: float = 12.0

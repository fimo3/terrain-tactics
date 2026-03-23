extends Node
## GameManager — autoload singleton ("GameManager")

signal game_over(winner_faction)
signal units_changed()

enum GameState { RUNNING, GAME_OVER }

var state: GameState = GameState.RUNNING

var all_units:       Array = []
var bulgarian_units: Array = []
var ottoman_units:   Array = []
var selected_unit          = null

var shipka_zone: Rect2 = Rect2()
var hold_seconds_needed: float = 60.0
var hold_seconds: float = 0.0

## Track starting strengths for the UI and AI
var starting_bg_count: int = 0
var starting_ot_count: int = 0


func _process(delta: float) -> void:
	if state != GameState.RUNNING: return
	_check_hold(delta)


func _check_hold(delta: float) -> void:
	if shipka_zone == Rect2(): return

	## Check without allocating a lambda every frame
	var ot_in_zone := false
	for u in ottoman_units:
		if u.is_alive and shipka_zone.has_point(u.global_position):
			ot_in_zone = true
			break

	if ot_in_zone:
		hold_seconds = 0.0
	else:
		hold_seconds += delta

	if hold_seconds >= hold_seconds_needed:
		_declare_winner(0)


func register_unit(unit) -> void:
	all_units.append(unit)
	if unit.stats.faction == 0:
		bulgarian_units.append(unit)
		starting_bg_count = bulgarian_units.size()
	else:
		ottoman_units.append(unit)
		starting_ot_count = ottoman_units.size()
	unit.died.connect(_on_unit_died)
	emit_signal("units_changed")


func _on_unit_died(unit) -> void:
	all_units.erase(unit)
	bulgarian_units.erase(unit)
	ottoman_units.erase(unit)
	if selected_unit == unit:
		selected_unit = null
	emit_signal("units_changed")

	if ottoman_units.is_empty():
		_declare_winner(0)
	elif bulgarian_units.is_empty():
		_declare_winner(1)


func _declare_winner(faction: int) -> void:
	if state == GameState.GAME_OVER: return
	state = GameState.GAME_OVER
	emit_signal("game_over", faction)


func select_unit(unit) -> void:
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.deselect()
	selected_unit = unit
	if unit: unit.select()


func deselect_all() -> void:
	select_unit(null)


func enemies_of(faction: int) -> Array:
	return ottoman_units if faction == 0 else bulgarian_units


func allies_of(faction: int) -> Array:
	return bulgarian_units if faction == 0 else ottoman_units


## Returns 0.0–1.0 for how depleted each side is
func bg_strength_ratio() -> float:
	if starting_bg_count == 0: return 0.0
	return float(bulgarian_units.size()) / float(starting_bg_count)


func ot_strength_ratio() -> float:
	if starting_ot_count == 0: return 0.0
	return float(ottoman_units.size()) / float(starting_ot_count)

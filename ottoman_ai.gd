extends Node
## OttomanAI — autoload singleton (add as "OttomanAI")
##
## Historically models Süleyman Hüsnü Pasha's assault doctrine:
##  Phase 1 — Artillery preparation: cannons bombard Eagle's Nest before infantry moves
##  Phase 2 — Frontal wave assault up the pass road
##  Phase 3 — Simultaneous flank probes on left and right ridges
##  Phase 4 — If wavering, regroup at base and re-launch with reinforced stamina
##
## Each unit gets a role and target_pos; the unit's own FSM handles movement/combat.

enum Phase { ARTILLERY_PREP, WAVE_ASSAULT, FLANK, REGROUP }
var phase: Phase = Phase.ARTILLERY_PREP

## Key strategic positions (set by main.gd after load)
var eagles_nest_pos:  Vector2 = Vector2.ZERO
var pass_road_pos:    Vector2 = Vector2.ZERO
var left_ridge_pos:   Vector2 = Vector2.ZERO
var right_ridge_pos:  Vector2 = Vector2.ZERO
var rally_pos:        Vector2 = Vector2.ZERO

var _phase_timer:   float = 0.0

const ARTILLERY_PREP_DURATION := 12.0
const WAVE_DURATION           := 30.0
const FLANK_DURATION          := 25.0
const REGROUP_DURATION        := 15.0

## Thresholds
const REGROUP_FORCE_RATIO := 0.40
var _peak_force: int = 0      ## Highest unit count observed — used as regroup baseline
var _regrouped_once: bool = false   ## Prevent regroup spam


func _ready() -> void:
	set_process(false)


func start(start_pos: Vector2, nest_pos: Vector2, road_pos: Vector2,
		   left_pos: Vector2, right_pos: Vector2) -> void:
	rally_pos       = start_pos
	eagles_nest_pos = nest_pos
	pass_road_pos   = road_pos
	left_ridge_pos  = left_pos
	right_ridge_pos = right_pos
	_peak_force     = GameManager.ottoman_units.size()
	phase           = Phase.ARTILLERY_PREP
	_phase_timer    = 0.0
	_regrouped_once = false
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.RUNNING:
		set_process(false)
		return

	_phase_timer += delta

	## Track peak force so regroup threshold is stable
	var cur = GameManager.ottoman_units.size()
	if cur > _peak_force:
		_peak_force = cur

	_issue_orders()
	_check_phase_transition()


## ── Order dispatch ────────────────────────────────────────────────────────────

func _issue_orders() -> void:
	var units = GameManager.ottoman_units
	if units.is_empty(): return

	match phase:
		Phase.ARTILLERY_PREP: _order_artillery_prep(units)
		Phase.WAVE_ASSAULT:   _order_wave_assault(units)
		Phase.FLANK:          _order_flank(units)
		Phase.REGROUP:        _order_regroup(units)


func _order_artillery_prep(units: Array) -> void:
	## Cannons bombard Eagle's Nest. Infantry holds at staging area.
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive: continue
		match unit.stats.unit_type:
			UnitStats.UnitType.CANNON:
				var target = _nearest_enemy_near(eagles_nest_pos, 800.0)
				if target:
					unit.order_attack(target)
				else:
					## Advance into range if no target found
					unit.order_move(eagles_nest_pos + Vector2(0, 200))
			UnitStats.UnitType.COMMANDER:
				unit.order_move(rally_pos + Vector2(0, 120))
			UnitStats.UnitType.MEDIC:
				_move_to_most_wounded(unit)
			_:
				## Infantry assembles at staging area
				unit.order_move(rally_pos + Vector2(randf_range(-80,80), randf_range(-40,40)))


func _order_wave_assault(units: Array) -> void:
	var wave_offset := 0
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive: continue
		if unit.behaviour == unit.B.FLEE: continue

		match unit.stats.unit_type:
			UnitStats.UnitType.RIFLEMAN:
				var spread = Vector2(randf_range(-60, 60), randf_range(-20, 20))
				var target = _nearest_enemy_near(pass_road_pos + spread, 9999.0)
				if target:
					unit.order_attack(target)
				else:
					unit.order_move(pass_road_pos + spread)
				wave_offset += 1

			UnitStats.UnitType.CAVALRY:
				var flank_pos = left_ridge_pos if wave_offset % 2 == 0 else right_ridge_pos
				var target = _nearest_enemy_near(flank_pos, 500.0)
				if target:
					unit.order_attack(target)
				else:
					unit.order_move(flank_pos)
				wave_offset += 1

			UnitStats.UnitType.CANNON:
				var cluster_target = _find_cluster_target()
				if cluster_target:
					unit.order_attack(cluster_target)
				else:
					unit.order_move(pass_road_pos + Vector2(0, 120))

			UnitStats.UnitType.MEDIC:
				_move_to_most_wounded(unit)

			UnitStats.UnitType.COMMANDER:
				unit.order_move(pass_road_pos + Vector2(0, 80))


func _order_flank(units: Array) -> void:
	var left_count  := 0
	var right_count := 0

	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive: continue
		if unit.behaviour == unit.B.FLEE: continue

		match unit.stats.unit_type:
			UnitStats.UnitType.CANNON:
				var target = _find_cluster_target()
				if target:
					unit.order_attack(target)
				else:
					unit.order_move(pass_road_pos + Vector2(0, 100))

			UnitStats.UnitType.COMMANDER:
				unit.order_move(pass_road_pos)

			UnitStats.UnitType.MEDIC:
				_move_to_most_wounded(unit)

			_:
				if left_count <= right_count:
					var target = _nearest_enemy_near(left_ridge_pos, 9999.0)
					if target: unit.order_attack(target)
					else: unit.order_move(left_ridge_pos)
					left_count += 1
				else:
					var target = _nearest_enemy_near(right_ridge_pos, 9999.0)
					if target: unit.order_attack(target)
					else: unit.order_move(right_ridge_pos)
					right_count += 1


func _order_regroup(units: Array) -> void:
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive: continue
		unit.order_move(rally_pos + Vector2(randf_range(-100,100), randf_range(-60,60)))


## ── Phase transitions ─────────────────────────────────────────────────────────

func _check_phase_transition() -> void:
	var ot_units    = GameManager.ottoman_units
	var force_ratio = float(ot_units.size()) / float(max(_peak_force, 1))

	## Force regroup if losing badly — but only once (prevents infinite regroup loop)
	if force_ratio < REGROUP_FORCE_RATIO and phase != Phase.REGROUP and not _regrouped_once:
		_regrouped_once = true
		_enter_phase(Phase.REGROUP)
		return

	if phase == Phase.REGROUP and _phase_timer >= REGROUP_DURATION:
		_enter_phase(Phase.WAVE_ASSAULT)
		return

	match phase:
		Phase.ARTILLERY_PREP:
			if _phase_timer >= ARTILLERY_PREP_DURATION:
				_enter_phase(Phase.WAVE_ASSAULT)
		Phase.WAVE_ASSAULT:
			if _phase_timer >= WAVE_DURATION:
				_enter_phase(Phase.FLANK)
		Phase.FLANK:
			if _phase_timer >= FLANK_DURATION:
				_enter_phase(Phase.WAVE_ASSAULT)


func _enter_phase(new_phase: Phase) -> void:
	phase        = new_phase
	_phase_timer = 0.0


## ── Helpers ───────────────────────────────────────────────────────────────────

func _nearest_enemy_near(pos: Vector2, max_dist: float):
	var best      = null
	var best_dist = max_dist
	for u in GameManager.bulgarian_units:
		if not u.is_alive: continue
		var d = pos.distance_to(u.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best


func _find_cluster_target():
	## Target the Bulgarian unit with the most allies nearby — maximise AoE damage
	var best       = null
	var best_score = 0
	for u in GameManager.bulgarian_units:
		if not u.is_alive: continue
		var score = 0
		for other in GameManager.bulgarian_units:
			if other.is_alive and u.global_position.distance_to(other.global_position) < 100:
				score += 1
		if score > best_score:
			best_score = score
			best = u
	return best


func _move_to_most_wounded(unit) -> void:
	var worst       = null
	var worst_ratio = 1.0
	for ally in GameManager.ottoman_units:
		if not is_instance_valid(ally) or not ally.is_alive or ally == unit: continue
		if ally.stats.unit_type == UnitStats.UnitType.MEDIC: continue
		var r = ally.current_health / ally.stats.max_health
		if r < worst_ratio:
			worst_ratio = r
			worst = ally
	if worst:
		unit.order_move(worst.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
	else:
		## No wounded — stay near commander
		for ally in GameManager.ottoman_units:
			if not is_instance_valid(ally) or not ally.is_alive: continue
			if ally.stats.unit_type == UnitStats.UnitType.COMMANDER:
				unit.order_move(ally.global_position + Vector2(30, 0))
				break

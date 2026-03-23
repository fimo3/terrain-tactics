extends Node
## BattleStageManager — autoload singleton ("BattleStageManager")
##
## Drives the four historical stages of the Battle of Shipka Pass (1877–1878).
## Each stage transitions after its real-world duration (compressed to gameplay seconds),
## spawns the historically accurate reinforcements, and updates the AI phase.
##
## REAL TIMELINE (compressed):
##   Stage 1 — First Battle:  17–19 July 1877    (Gurko captures pass; 4,000 OT garrison)
##   Stage 2 — Second Battle: 21–26 August 1877  (30,000 OT vs 7,500 BG/RU; worst fighting)
##   Stage 3 — Third Battle:  13–17 September 1877 (18,000 OT probe; Radetsky holds)
##   Stage 4 — Fourth Battle: 5–9 January 1878   (66,000 RU offensive; OT surrender)

signal stage_changed(new_stage: int, info: Dictionary)
signal reinforcements_arrived(faction: int, units_spawned: Array)

## Stage indices
const STAGE_1 := 0   ## First Battle  — July 1877
const STAGE_2 := 1   ## Second Battle — August 1877
const STAGE_3 := 2   ## Third Battle  — September 1877
const STAGE_4 := 3   ## Fourth Battle — January 1878

var current_stage: int = STAGE_1
var stage_timer:   float = 0.0
var _active:       bool  = false

## References set by main.gd
var dot_scene:       PackedScene = null
var main_node:       Node        = null

## Stage durations in gameplay seconds
## Roughly: 1 day of real battle ≈ 20 gameplay seconds
## Stage 1: 3 days  → 60s
## Stage 2: 6 days  → 120s (most intense)
## Stage 3: 5 days  → 100s
## Stage 4: 5 days  → 100s
const STAGE_DURATIONS := [60.0, 120.0, 100.0, 100.0]

## Historical data per stage
const STAGE_INFO := [
	{
		"name": "First Battle — July 17–19, 1877",
		"date": "July 1877",
		"desc": "Gurko's 11,000-man vanguard seizes Shipka Pass from the 4,000-strong Ottoman garrison. The Ottoman commanders slip away west on the morning of July 19.",
		"ot_strength": "4,000",
		"bg_strength": "11,000 (Gurko's vanguard)",
	},
	{
		"name": "Second Battle — August 21–26, 1877",
		"date": "August 1877",
		"desc": "Süleyman's 30,000 Ottomans launch massive assaults. Defenders dwindle to 7,500. Near the end, having run out of ammunition, they throw rocks and bodies of fallen comrades.",
		"ot_strength": "30,000",
		"bg_strength": "7,500 (5,000 Bulgarians + 2,500 Russians)",
	},
	{
		"name": "Third Battle — September 13–17, 1877",
		"date": "September 1877",
		"desc": "Süleyman shells St. Nicholas from September 13. A frontal assault on the 17th captures the first trench line, but Radetsky's reinforcements drive them back.",
		"ot_strength": "20,000+",
		"bg_strength": "18,000 (reinforced, limited by Siege of Pleven)",
	},
	{
		"name": "Fourth Battle — January 5–9, 1878",
		"date": "January 1878",
		"desc": "Pleven has fallen. Gourko has 65,000 troops. Skobelev and Mirsky encircle Veysel Pasha's garrison. On January 9, the surrounded Ottoman forces surrender — 36,000 captured.",
		"ot_strength": "36,000",
		"bg_strength": "66,000 (Radetsky + Gourko + Skobelev + Mirsky)",
	},
]

## Reinforcement events: [stage, delay_from_stage_start, faction, stats_key, position, label]
## faction 0 = BG/RU, faction 1 = Ottoman
## Positions are approximate world-space coords matching the battlefield
var _reinforcement_events: Array = [

	## ── STAGE 1 ─ First Battle (Gurko captures pass) ──────────────────────────
	## Historical: Mirsky attacks July 17 with 2,000 infantry + Cossacks from north
	## Gurko arrives July 18 with infantry and Cossacks from south
	## Day 2 — Gurko's southern force arrives
	{ "stage": 0, "delay": 25.0, "faction": 0, "type": "kazak",
	  "pos": Vector2(-400, -100), "label": "Gurko's Cossacks arrive" },
	## Day 3 — Ottoman garrison slips away; Gurko consolidates
	{ "stage": 0, "delay": 50.0, "faction": 0, "type": "opalchenets",
	  "pos": Vector2(50, -310), "label": "Bulgarian volunteers reinforce summit" },

	## ── STAGE 2 ─ Second Battle (August 21–26) ────────────────────────────────
	## Aug 21: OT bombard + first assault. Regiment from Sevlievo boosts defenders to 7,500
	{ "stage": 1, "delay": 10.0, "faction": 0, "type": "opalchenets",
	  "pos": Vector2(-120, -290), "label": "Regiment from Sevlievo (+2,500 men)" },
	## Aug 21: Süleyman's first infantry wave (Rauf Pasha's 15 battalions join)
	{ "stage": 1, "delay": 5.0, "faction": 1, "type": "nizam",
	  "pos": Vector2(80, 380), "label": "Rauf Pasha's 15 battalions" },
	## Aug 22: OT move artillery up mountainside; flanking infantry
	{ "stage": 1, "delay": 30.0, "faction": 1, "type": "top",
	  "pos": Vector2(250, 200), "label": "Ottoman artillery advances up slope" },
	{ "stage": 1, "delay": 35.0, "faction": 1, "type": "suvari",
	  "pos": Vector2(-380, 300), "label": "Ottoman flanking cavalry" },
	## Aug 23: All positions attacked; 4th Rifle Brigade (Radetsky) saves Central Hill
	{ "stage": 1, "delay": 55.0, "faction": 0, "type": "orudie",
	  "pos": Vector2(20, -260), "label": "4th Rifle Brigade — Radetsky saves Central Hill!" },
	## Aug 26: Bulgarian bayonet charge repulses attack on Eagle's Nest; more Russian reinforcements
	{ "stage": 1, "delay": 90.0, "faction": 0, "type": "kazak",
	  "pos": Vector2(-280, -200), "label": "Russian reinforcements (Aug 26)" },

	## ── STAGE 3 ─ Third Battle (September 13–17) ──────────────────────────────
	## Sep 13: Süleyman begins shelling
	{ "stage": 2, "delay": 5.0, "faction": 1, "type": "top",
	  "pos": Vector2(150, 350), "label": "Ottoman artillery bombardment (Sep 13)" },
	## Sep 17: Frontal assault; Ottoman troops capture first trench line
	{ "stage": 2, "delay": 40.0, "faction": 1, "type": "nizam",
	  "pos": Vector2(-60, 320), "label": "Ottoman frontal assault (Sep 17)" },
	## Radetsky brings reinforcements — Russian counterattack
	{ "stage": 2, "delay": 60.0, "faction": 0, "type": "sanitar",
	  "pos": Vector2(120, -280), "label": "Radetsky's reinforcements — counterattack!" },
	{ "stage": 2, "delay": 65.0, "faction": 0, "type": "opalchenets",
	  "pos": Vector2(-80, -300), "label": "Bulgarian reserve (secondary northern assault repulsed)" },

	## ── STAGE 4 ─ Fourth Battle (January 5–9, 1878) ───────────────────────────
	## Pleven has fallen Dec 10 — Gourko has 65,000 troops
	## Jan 5: Radetsky attacks from pass; Skobelev + Mirsky columns encircle
	{ "stage": 3, "delay": 5.0, "faction": 0, "type": "kazak",
	  "pos": Vector2(-500, -50), "label": "Mirsky's column attacks from west (Jan 5)" },
	{ "stage": 3, "delay": 8.0, "faction": 0, "type": "sanitar",
	  "pos": Vector2(350, 50), "label": "Skobelev's column pushes from east" },
	{ "stage": 3, "delay": 12.0, "faction": 0, "type": "orudie",
	  "pos": Vector2(0, -200), "label": "Radetsky attacks from the pass" },
	## Jan 8: Mirsky attacks unsupported; heavy resistance
	{ "stage": 3, "delay": 50.0, "faction": 0, "type": "gurko",
	  "pos": Vector2(-200, -100), "label": "Gourko's main force — overwhelming advance!" },
	## Jan 9: Skobelev breaks through; Veysel Pasha surrenders
	{ "stage": 3, "delay": 80.0, "faction": 0, "type": "opalchenets",
	  "pos": Vector2(100, -320), "label": "Final encirclement — Veysel Pasha surrounded!" },
]

var _fired_events: Array[int] = []   ## indices of already-fired events
var _stats_cache: Dictionary = {}    ## populated by main.gd


func _ready() -> void:
	set_process(false)


func start(stats: Dictionary, scene: PackedScene, node: Node) -> void:
	_stats_cache = stats
	dot_scene    = scene
	main_node    = node
	current_stage = STAGE_1
	stage_timer   = 0.0
	_fired_events.clear()
	_active = true
	set_process(true)
	emit_signal("stage_changed", current_stage, STAGE_INFO[current_stage])


func _process(delta: float) -> void:
	if not _active: return
	if GameManager.state != GameManager.GameState.RUNNING: return

	stage_timer += delta

	## Fire any pending reinforcement events
	for i in _reinforcement_events.size():
		if i in _fired_events: continue
		var ev = _reinforcement_events[i]
		if ev["stage"] == current_stage and stage_timer >= ev["delay"]:
			_fire_reinforcement(ev)
			_fired_events.append(i)

	## Check stage transition
	if current_stage < STAGE_4 and stage_timer >= STAGE_DURATIONS[current_stage]:
		_advance_stage()


func _advance_stage() -> void:
	current_stage += 1
	stage_timer    = 0.0
	emit_signal("stage_changed", current_stage, STAGE_INFO[current_stage])

	## Reset the Ottoman AI for the new assault pattern
	if is_instance_valid(OttomanAI):
		OttomanAI._starting_count = GameManager.ottoman_units.size()
		OttomanAI._regrouped_once = false
		OttomanAI._enter_phase(OttomanAI.Phase.ARTILLERY_PREP if current_stage < 3
			else OttomanAI.Phase.WAVE_ASSAULT)

	## Stage 4: Pleven has fallen — Ottoman morale collapses, regroup disabled
	if current_stage == STAGE_4:
		OttomanAI._regrouped_once = true   ## No more regrouping for OT in Stage 4


func _fire_reinforcement(ev: Dictionary) -> void:
	var key: String = ev["type"]
	if not _stats_cache.has(key): return
	var stats_res = _stats_cache[key]
	if not stats_res or not dot_scene: return

	var unit = dot_scene.instantiate()
	unit.stats           = stats_res
	unit.global_position = ev["pos"]
	main_node.add_child(unit)
	unit.fired_projectile.connect(main_node._on_fired_projectile)
	GameManager.register_unit(unit)

	emit_signal("reinforcements_arrived", ev["faction"],
		[{"label": ev["label"], "faction": ev["faction"]}])


## Returns 0.0–1.0 progress through the current stage
func stage_progress() -> float:
	return clamp(stage_timer / STAGE_DURATIONS[current_stage], 0.0, 1.0)


func time_to_next_stage() -> float:
	if current_stage >= STAGE_4: return 0.0
	return max(0.0, STAGE_DURATIONS[current_stage] - stage_timer)

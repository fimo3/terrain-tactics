extends CanvasLayer

@onready var bg_units:    Label       = $Top/M/Row/BGBox/Units
@onready var bg_troops:   Label       = $Top/M/Row/BGBox/Troops
@onready var ot_units:    Label       = $Top/M/Row/OTBox/Units
@onready var ot_troops:   Label       = $Top/M/Row/OTBox/Troops
@onready var hold_lbl:    Label       = $Top/M/Row/PassBox/HoldLbl
@onready var hold_bar:    ProgressBar = $Top/M/Row/PassBox/HoldBar
@onready var ai_phase:    Label       = $Top/M/Row/AIBox/PhaseLbl
@onready var stage_lbl:   Label       = $Top/M/Row/StageBox/StageLbl
@onready var stage_bar:   ProgressBar = $Top/M/Row/StageBox/StageBar

@onready var unit_panel:  PanelContainer = $UnitPanel
@onready var u_name:      Label          = $UnitPanel/M/Col/Name
@onready var u_role:      Label          = $UnitPanel/M/Col/Role
@onready var u_behaviour: Label          = $UnitPanel/M/Col/BehaviourLbl
@onready var u_terrain:   Label          = $UnitPanel/M/Col/TerrainLbl
@onready var u_hp_bar:    ProgressBar    = $UnitPanel/M/Col/HPRow/HPBar
@onready var u_hp_lbl:    Label          = $UnitPanel/M/Col/HPRow/HPLbl
@onready var u_st_bar:    ProgressBar    = $UnitPanel/M/Col/StRow/StBar
@onready var u_st_lbl:    Label          = $UnitPanel/M/Col/StRow/StLbl
@onready var u_special:   Label          = $UnitPanel/M/Col/SpecialLbl
@onready var u_desc:      Label          = $UnitPanel/M/Col/DescLbl
@onready var u_troops:    Label          = $UnitPanel/M/Col/TroopsLbl

@onready var go_panel:    PanelContainer = $GameOver
@onready var go_result:   Label          = $GameOver/M/Col/Result
@onready var go_sub:      Label          = $GameOver/M/Col/Sub
@onready var go_hist:     Label          = $GameOver/M/Col/Hist
@onready var go_restart:  Button         = $GameOver/M/Col/Restart

@onready var stage_banner:     PanelContainer = $StageBanner
@onready var banner_title:     Label          = $StageBanner/M/Col/Title
@onready var banner_date:      Label          = $StageBanner/M/Col/Date
@onready var banner_desc:      Label          = $StageBanner/M/Col/Desc
@onready var banner_strengths: Label          = $StageBanner/M/Col/Strengths

@onready var toast_lbl:   Label = $ToastLbl

@onready var scale_lbl:   Label = $ScaleLbl
@onready var hint_lbl:    Label = $HintLbl

const AI_PHASE_NAMES  := ["Artillery prep", "Wave assault", "Flank attack", "Regrouping"]
const AI_PHASE_COLORS := [
	Color(0.95, 0.76, 0.06),
	Color(0.92, 0.15, 0.10),
	Color(0.90, 0.40, 0.40),
	Color(0.55, 0.55, 0.62),
]

var _banner_timer:  float = 0.0
const BANNER_DUR := 7.0

var _toast_timer:   float = 0.0
var _toast_queue:   Array[String] = []
const TOAST_DUR  := 3.5

var _bg_losses := 0
var _ot_losses := 0
var _prev_bg   := 0
var _prev_ot   := 0


func _ready() -> void:
	unit_panel.visible   = false
	go_panel.visible     = false
	stage_banner.visible = false
	toast_lbl.visible    = false

	scale_lbl.text = "1 dot  =  ~1,000 soldiers"
	hint_lbl.text  = "Left-click: select unit   Right-click: move/attack   Tab: cycle   Space: focus   Scroll: zoom   MMB: pan"

	go_restart.pressed.connect(func(): get_tree().reload_current_scene())
	GameManager.units_changed.connect(_refresh_counts)
	set_process(true)

	_prev_bg = GameManager.bulgarian_units.size()
	_prev_ot = GameManager.ottoman_units.size()


func _process(delta: float) -> void:
	_refresh_selected()
	_refresh_hold()
	_refresh_ai_phase()
	_refresh_stage()
	_tick_banner(delta)
	_tick_toast(delta)


## ── Stage banner ──────────────────────────────────────────────────────────────

func show_stage_banner(stage: int, info: Dictionary) -> void:
	banner_title.text = "⚔  " + info.get("name", "Battle")
	banner_date.text  = info.get("date", "")
	banner_desc.text  = info.get("desc", "")
	var strengths = "Defenders: %s\nAttackers: %s" % [
		info.get("bg_strength", "?"),
		info.get("ot_strength", "?"),
	]
	banner_strengths.text = strengths
	stage_banner.visible = true
	_banner_timer = BANNER_DUR


func _tick_banner(delta: float) -> void:
	if _banner_timer <= 0.0: return
	_banner_timer -= delta
	var alpha = clamp(_banner_timer / 1.2, 0.0, 1.0)
	stage_banner.modulate = Color(1, 1, 1, alpha)
	if _banner_timer <= 0.0:
		stage_banner.visible = false


## ── Reinforcement toast ───────────────────────────────────────────────────────

func show_reinforcement_toast(text: String) -> void:
	_toast_queue.append(text)


func _tick_toast(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		var a = clamp(_toast_timer / 0.6, 0.0, 1.0)
		toast_lbl.modulate = Color(1, 1, 1, a)
		if _toast_timer <= 0.0:
			toast_lbl.visible = false
	elif not _toast_queue.is_empty():
		toast_lbl.text    = "★ " + _toast_queue.pop_front()
		toast_lbl.visible = true
		toast_lbl.modulate = Color(1, 1, 1, 1)
		_toast_timer = TOAST_DUR


## ── Counts ────────────────────────────────────────────────────────────────────

func _refresh_counts() -> void:
	var cur_bg = GameManager.bulgarian_units.size()
	var cur_ot = GameManager.ottoman_units.size()
	if cur_bg < _prev_bg: _bg_losses += _prev_bg - cur_bg
	if cur_ot < _prev_ot: _ot_losses += _prev_ot - cur_ot
	_prev_bg = cur_bg
	_prev_ot = cur_ot
	update_counts(cur_bg, cur_ot)


func update_counts(bg: int, ot: int) -> void:
	var bg_pct = int(GameManager.bg_strength_ratio() * 100.0)
	var ot_pct = int(GameManager.ot_strength_ratio() * 100.0)
	bg_units.text  = "%d units  (%d%% strength)" % [bg, bg_pct]
	bg_troops.text = "≈ %d,000 troops  |  lost: %d" % [bg, _bg_losses]
	ot_units.text  = "%d units  (%d%% strength)" % [ot, ot_pct]
	ot_troops.text = "≈ %d,000 troops  |  lost: %d" % [ot, _ot_losses]


## ── Hold bar ──────────────────────────────────────────────────────────────────

func _refresh_hold() -> void:
	var pct       = clamp(GameManager.hold_seconds / GameManager.hold_seconds_needed, 0.0, 1.0)
	var remaining = max(0.0, GameManager.hold_seconds_needed - GameManager.hold_seconds)
	hold_bar.value = pct * 100.0
	hold_lbl.text  = "Eagle's Nest  %.0fs  (%.0fs to win)" % [GameManager.hold_seconds, remaining]
	hold_bar.modulate = Color(0.35,0.85,0.45) if pct>0.6 else (Color(0.95,0.76,0.06) if pct>0.3 else Color(0.55,0.75,1.0))


## ── AI phase ──────────────────────────────────────────────────────────────────

func _refresh_ai_phase() -> void:
	var p = OttomanAI.phase as int
	ai_phase.text = "Ottoman: " + AI_PHASE_NAMES[p]
	ai_phase.add_theme_color_override("font_color", AI_PHASE_COLORS[p])


## ── Stage progress ────────────────────────────────────────────────────────────

func _refresh_stage() -> void:
	var s     = BattleStageManager.current_stage
	var names = ["1st Battle", "2nd Battle", "3rd Battle", "4th Battle"]
	var dates = ["Jul 1877", "Aug 1877", "Sep 1877", "Jan 1878"]
	stage_lbl.text = "Stage %d: %s  •  %s  (next in %.0fs)" % [
		s + 1, names[s], dates[s],
		BattleStageManager.time_to_next_stage()
	]
	stage_bar.value = BattleStageManager.stage_progress() * 100.0


## ── Unit panel ────────────────────────────────────────────────────────────────

func _refresh_selected() -> void:
	var sel = GameManager.selected_unit
	if not sel or not is_instance_valid(sel) or not sel.is_alive:
		unit_panel.visible = false
		return
	unit_panel.visible = true
	var s = sel.stats

	u_name.text = s.display_name
	u_role.text = _role(s)
	if u_desc: u_desc.text = s.description

	## Behaviour
	var b_names  = ["Idle", "Moving", "Fighting", "Retreating"]
	var b_colors = [Color(0.6,0.6,0.6), Color(0.4,0.8,1.0), Color(0.95,0.35,0.35), Color(1.0,0.85,0.3)]
	var bi = sel.behaviour as int
	u_behaviour.text = b_names[bi]
	u_behaviour.add_theme_color_override("font_color", b_colors[bi])

	## Terrain — show actual current bonuses from unit's cached terrain multipliers
	var t_label = TerrainManager.get_label(sel.global_position)
	var dmg_pct = int((sel.terrain_damage_mult - 1.0) * 100.0)
	var spd_pct = int((sel.terrain_speed_mult  - 1.0) * 100.0)
	var asp_pct = int((1.0 - sel.terrain_attack_speed) * 100.0)
	var dmg_str = ("+%d%%" if dmg_pct >= 0 else "%d%%") % dmg_pct
	var spd_str = ("+%d%%" if spd_pct >= 0 else "%d%%") % spd_pct
	var asp_str = ("+%d%%" if asp_pct >= 0 else "%d%%") % asp_pct
	u_terrain.text = "%s  •  dmg %s  spd %s  fire %s" % [t_label, dmg_str, spd_str, asp_str]

	var on_high = TerrainManager.is_high_ground(sel.global_position)
	u_terrain.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.45) if on_high else Color(0.65, 0.80, 0.55))

	## HP
	var hp = sel.current_health / s.max_health
	u_hp_bar.value = hp * 100.0
	u_hp_bar.modulate = Color(0.2,0.85,0.25) if hp>0.6 else (Color(0.95,0.76,0.06) if hp>0.3 else Color(0.92,0.15,0.10))
	u_hp_lbl.text = "%d / %d hp" % [int(sel.current_health), int(s.max_health)]

	## Stamina
	u_st_bar.value = sel.stamina * 100.0
	u_st_bar.modulate = Color(0.15,0.65,0.95) if sel.stamina > 0.4 else Color(0.95,0.76,0.06)
	u_st_lbl.text  = "%.0f%%" % (sel.stamina * 100.0)

	## Specials
	var sp: Array[String] = []
	if s.heal_per_second > 0:            sp.append("⚕ Heals allies in %gpx" % s.heal_radius)
	if s.aura_radius > 0:                sp.append("★ Aura %gpx  +%.0f%% dmg" % [s.aura_radius, s.aura_damage_bonus*100])
	if s.charge_damage_multiplier > 1.0: sp.append("⚡ Charge ×%.1f" % s.charge_damage_multiplier)
	if s.armor_pierce > 0:               sp.append("⚔ Armor pierce %d%%" % int(s.armor_pierce*100))
	if s.burst_count > 1:                sp.append("🔫 Volley %d shots" % s.burst_count)
	if s.aoe_radius > 0:                 sp.append("💥 AoE r=%g" % s.aoe_radius)
	u_special.text = "\n".join(sp)
	u_troops.text  = "Represents ≈ 1,000 soldiers"


func show_game_over(winner: int) -> void:
	go_panel.visible = true
	if winner == 0:
		go_result.text = "Russia & Opalchentsi Hold the Pass!"
		go_result.add_theme_color_override("font_color", Color(0.35,0.85,0.45))
		go_sub.text  = "The Eagle's Nest stands.\nBulgaria's freedom is secured."
		go_hist.text = (
			"Historical outcome: Defenders held Shipka across all four battles "
			"(Jul 1877 – Jan 1878). Süleyman lost ~10,000 men in August alone. "
			"He was later court-martialed and exiled to Baghdad by Sultan Abdulhamid II. "
			"The pass became the central symbol of the Liberation of Bulgaria."
		)
	else:
		go_result.text = "Ottoman Empire Breaks Through!"
		go_result.add_theme_color_override("font_color", Color(1.0,0.35,0.35))
		go_sub.text  = "Süleyman forces the pass.\nThe road to Pleven's supply lines is open."
		go_hist.text = (
			"In reality, Süleyman's forces never broke through despite 30,000 men against 7,500 "
			"defenders. 'There is no Shipka!' became a Bulgarian phrase — ironic shorthand for "
			"an impossible but achieved defence. The pass held across all four battles."
		)


func _role(s: UnitStats) -> String:
	var f = "Ottoman" if s.faction==1 else ("Russian" if s.unit_type==UnitStats.UnitType.CAVALRY or s.unit_type==UnitStats.UnitType.MEDIC else "Bulgarian")
	match s.unit_type:
		UnitStats.UnitType.RIFLEMAN:  return f+" infantry"
		UnitStats.UnitType.CAVALRY:   return f+" cavalry"
		UnitStats.UnitType.CANNON:    return f+" artillery"
		UnitStats.UnitType.MEDIC:     return f+" support"
		UnitStats.UnitType.COMMANDER: return f+" commander"
	return ""

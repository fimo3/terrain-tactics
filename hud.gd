extends CanvasLayer

@onready var bg_units:    Label       = $Top/M/Row/BGBox/Units
@onready var bg_troops:   Label       = $Top/M/Row/BGBox/Troops
@onready var ot_units:    Label       = $Top/M/Row/OTBox/Units
@onready var ot_troops:   Label       = $Top/M/Row/OTBox/Troops
@onready var hold_lbl:    Label       = $Top/M/Row/PassBox/HoldLbl
@onready var hold_bar:    ProgressBar = $Top/M/Row/PassBox/HoldBar
@onready var ai_phase:    Label       = $Top/M/Row/AIBox/PhaseLbl

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
@onready var u_troops:    Label          = $UnitPanel/M/Col/TroopsLbl

@onready var go_panel:    PanelContainer = $GameOver
@onready var go_result:   Label          = $GameOver/M/Col/Result
@onready var go_sub:      Label          = $GameOver/M/Col/Sub
@onready var go_hist:     Label          = $GameOver/M/Col/Hist
@onready var go_restart:  Button         = $GameOver/M/Col/Restart

@onready var scale_lbl:   Label = $ScaleLbl
@onready var hint_lbl:    Label = $HintLbl

const AI_PHASE_NAMES := ["Artillery prep", "Wave assault", "Flank attack", "Regrouping"]
const AI_PHASE_COLORS := [
	Color(0.95, 0.76, 0.06),
	Color(0.92, 0.15, 0.10),
	Color(0.90, 0.40, 0.40),
	Color(0.55, 0.55, 0.62),
]


func _ready() -> void:
	unit_panel.visible = false
	go_panel.visible   = false
	scale_lbl.text = "1 dot  =  1,000 soldiers"
	hint_lbl.text  = "Left-click: select your unit   Right-click: move / attack   Tab: cycle units   Scroll: zoom"
	go_restart.pressed.connect(func(): get_tree().reload_current_scene())
	GameManager.units_changed.connect(_refresh_counts)
	set_process(true)


func _process(_delta: float) -> void:
	_refresh_selected()
	_refresh_hold()
	_refresh_ai_phase()


func _refresh_counts() -> void:
	update_counts(GameManager.bulgarian_units.size(), GameManager.ottoman_units.size())


func update_counts(bg: int, ot: int) -> void:
	bg_units.text  = "%d units" % bg
	bg_troops.text = "≈ %d,000 troops" % bg
	ot_units.text  = "%d units" % ot
	ot_troops.text = "≈ %d,000 troops" % ot


func _refresh_hold() -> void:
	var pct = clamp(GameManager.hold_seconds / GameManager.hold_seconds_needed, 0.0, 1.0)
	hold_bar.value = pct * 100.0
	hold_lbl.text  = "Eagle's Nest  %.0fs / %.0fs" % [
		GameManager.hold_seconds, GameManager.hold_seconds_needed]


func _refresh_ai_phase() -> void:
	var p = OttomanAI.phase as int
	ai_phase.text = "Ottoman: " + AI_PHASE_NAMES[p]
	ai_phase.add_theme_color_override("font_color", AI_PHASE_COLORS[p])


func _refresh_selected() -> void:
	var sel = GameManager.selected_unit
	if not sel or not is_instance_valid(sel) or not sel.is_alive:
		unit_panel.visible = false
		return
	unit_panel.visible = true
	var s = sel.stats

	u_name.text = s.display_name
	u_role.text = _role(s)

	## Behaviour
	var b_names  = ["Idle", "Moving", "Fighting", "Retreating"]
	var b_colors = [Color(0.6,0.6,0.6), Color(0.4,0.8,1.0), Color(0.95,0.35,0.35), Color(1.0,0.85,0.3)]
	var bi = sel.behaviour as int
	u_behaviour.text = b_names[bi]
	u_behaviour.add_theme_color_override("font_color", b_colors[bi])

	## Terrain
	u_terrain.text = "%s  —  %s" % [
		TerrainManager.get_label(sel.global_position),
		TerrainManager.get_tip(sel.global_position)
	]

	## HP
	var hp = sel.current_health / s.max_health
	u_hp_bar.value = hp * 100.0
	u_hp_bar.modulate = Color(0.2,0.85,0.25) if hp>0.6 else (Color(0.95,0.76,0.06) if hp>0.3 else Color(0.92,0.15,0.10))
	u_hp_lbl.text = "%d / %d hp" % [int(sel.current_health), int(s.max_health)]

	## Stamina
	u_st_bar.value = sel.stamina * 100.0
	u_st_lbl.text  = "%.0f%%" % (sel.stamina * 100.0)

	## Specials
	var sp: Array[String] = []
	if s.heal_per_second > 0:   sp.append("Heals allies in %gpx" % s.heal_radius)
	if s.aura_radius > 0:       sp.append("Aura: ally stamina regen in %gpx" % s.aura_radius)
	if s.charge_damage_multiplier > 1.0: sp.append("Charge bonus: ×%.1f" % s.charge_damage_multiplier)
	if s.armor_pierce > 0:      sp.append("Pierces %d%% armor" % int(s.armor_pierce*100))
	if s.burst_count > 1:       sp.append("Volley: %d shots" % s.burst_count)
	if s.aoe_radius > 0:        sp.append("AoE blast r=%g" % s.aoe_radius)
	u_special.text = "\n".join(sp)
	u_troops.text  = "Represents ≈ 1,000 soldiers"


func show_game_over(winner: int) -> void:
	go_panel.visible = true
	if winner == 0:
		go_result.text = "Russia & Opalchentsi Win!"
		go_result.add_theme_color_override("font_color", Color(0.35,0.85,0.45))
		go_sub.text  = "The Eagle's Nest holds.\nBulgaria wins its freedom."
		go_hist.text = "\"The Bulgarian volunteers played a decisive role in defending the Shipka Pass, thus denying the Ottomans a major breakthrough.\"\n— Battle of Shipka Pass, Wikipedia"
	else:
		go_result.text = "Ottoman Empire Wins!"
		go_result.add_theme_color_override("font_color", Color(1.0,0.35,0.35))
		go_sub.text  = "Süleyman breaks through.\nThe road to Pleven's supply lines is open."
		go_hist.text = "Suleiman Pasha was later court-martialed and exiled to Baghdad by Sultan Abdulhamid II."


func _role(s: UnitStats) -> String:
	var f = "Ottoman" if s.faction==1 else ("Russian" if s.unit_type==UnitStats.UnitType.CAVALRY or s.unit_type==UnitStats.UnitType.MEDIC else "Bulgarian")
	match s.unit_type:
		UnitStats.UnitType.RIFLEMAN:  return f+" infantry"
		UnitStats.UnitType.CAVALRY:   return f+" cavalry"
		UnitStats.UnitType.CANNON:    return f+" artillery"
		UnitStats.UnitType.MEDIC:     return f+" support"
		UnitStats.UnitType.COMMANDER: return f+" commander"
	return ""

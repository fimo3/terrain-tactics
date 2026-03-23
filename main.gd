extends Node2D

@export var dot_scene:        PackedScene
@export var projectile_scene: PackedScene
@export var front_line_scene: PackedScene
@export var hud_scene:        PackedScene

@export var bg_spawn_points: Array[Vector2] = [
	Vector2(-180,  -320),
	Vector2(-380,  -180),
	Vector2( 0,    -340),
	Vector2( 200,  -280),
	Vector2(-80,   -300),
]
@export var ot_spawn_points: Array[Vector2] = [
	Vector2(-120,   400),
	Vector2(-320,   350),
	Vector2( 200,   380),
	Vector2( 80,    420),
	Vector2( 0,     450),
]

@export var eagles_nest_pos:  Vector2 = Vector2(-80,  -320)
@export var pass_road_pos:    Vector2 = Vector2(-20,    80)
@export var left_ridge_pos:   Vector2 = Vector2(-350, -150)
@export var right_ridge_pos:  Vector2 = Vector2( 280, -150)
@export var ot_rally_pos:     Vector2 = Vector2(  0,   440)
@export var shipka_zone_pos:  Vector2 = Vector2(-160, -380)
@export var shipka_zone_size: Vector2 = Vector2( 320,  180)

@export var res_opalchenets: UnitStats
@export var res_kazak:       UnitStats
@export var res_orudie:      UnitStats
@export var res_sanitar:     UnitStats
@export var res_gurko:       UnitStats
@export var res_nizam:       UnitStats
@export var res_suvari:      UnitStats
@export var res_top:         UnitStats
@export var res_hakim:       UnitStats
@export var res_suleiman:    UnitStats

@onready var camera: Camera2D = $Camera
var _hud = null

const CLICK_RADIUS := 30.0
const CAM_LIMIT    := 850.0
var _pan_last: Vector2 = Vector2.ZERO
var _panning:  bool    = false


func _ready() -> void:
	## ── Terrain ──────────────────────────────────────────────────────────────
	var ground: Sprite2D = _find_node_by_name(self, "Ground") as Sprite2D
	if ground:
		TerrainManager.initialize(ground)
	else:
		push_warning("main: Ground sprite not found")

	## ── Win zone ─────────────────────────────────────────────────────────────
	GameManager.shipka_zone = Rect2(shipka_zone_pos, shipka_zone_size)

	## ── HUD ──────────────────────────────────────────────────────────────────
	_hud = _find_node_by_name(self, "UI")
	if not _hud and hud_scene:
		_hud = hud_scene.instantiate()
		_hud.name = "UI"
		add_child(_hud)

	## ── Camera limits ────────────────────────────────────────────────────────
	camera.limit_left   = -CAM_LIMIT
	camera.limit_right  =  CAM_LIMIT
	camera.limit_top    = -CAM_LIMIT
	camera.limit_bottom =  CAM_LIMIT

	## ── Signals ──────────────────────────────────────────────────────────────
	GameManager.game_over.connect(_on_game_over)
	GameManager.units_changed.connect(_on_units_changed)
	BattleStageManager.stage_changed.connect(_on_stage_changed)
	BattleStageManager.reinforcements_arrived.connect(_on_reinforcements_arrived)

	## ── Spawn ────────────────────────────────────────────────────────────────
	_spawn_all()
	_spawn_front_line()

	call_deferred("_start_systems")


func _start_systems() -> void:
	## AI
	if is_instance_valid(OttomanAI):
		OttomanAI.start(ot_rally_pos, eagles_nest_pos, pass_road_pos,
			left_ridge_pos, right_ridge_pos)

	## Stage manager — pass all stats resources so it can spawn reinforcements
	var stats_dict = {
		"opalchenets": res_opalchenets,
		"kazak":       res_kazak,
		"orudie":      res_orudie,
		"sanitar":     res_sanitar,
		"gurko":       res_gurko,
		"nizam":       res_nizam,
		"suvari":      res_suvari,
		"top":         res_top,
		"hakim":       res_hakim,
		"suleiman":    res_suleiman,
	}
	BattleStageManager.start(stats_dict, dot_scene, self)


func _find_node_by_name(node: Node, target: String) -> Node:
	if node.name == target: return node
	for child in node.get_children():
		var r = _find_node_by_name(child, target)
		if r: return r
	return null


func _spawn_front_line() -> void:
	if front_line_scene:
		var fl = front_line_scene.instantiate()
		fl.name = "FrontLine"
		add_child(fl)
	else:
		var fl = Node2D.new()
		fl.set_script(load("res://front_line.gd"))
		fl.name = "FrontLine"
		add_child(fl)


func _spawn_all() -> void:
	## Stage 1 historically: Gurko's 5,000 defenders on the summit
	var bg = [res_opalchenets, res_kazak, res_orudie, res_sanitar, res_gurko]
	## Stage 1 Ottoman: 4,000-strong garrison
	var ot = [res_nizam, res_suvari, res_top, res_hakim, res_suleiman]

	for i in bg.size():
		if bg[i]:
			_spawn(bg[i], bg_spawn_points[i] if i < bg_spawn_points.size() else Vector2(-300+i*60, -200))
	for i in ot.size():
		if ot[i]:
			_spawn(ot[i], ot_spawn_points[i] if i < ot_spawn_points.size() else Vector2(-200+i*60, 400))


func _spawn(res: UnitStats, pos: Vector2) -> void:
	if not dot_scene: return
	var unit = dot_scene.instantiate()
	unit.stats           = res
	unit.global_position = pos
	add_child(unit)
	unit.fired_projectile.connect(_on_fired_projectile)
	GameManager.register_unit(unit)


## ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning  = event.pressed
		_pan_last = event.position
	if event is InputEventMouseMotion and _panning:
		camera.position -= (event.position - _pan_last) / camera.zoom
		camera.position.x = clamp(camera.position.x, -CAM_LIMIT, CAM_LIMIT)
		camera.position.y = clamp(camera.position.y, -CAM_LIMIT, CAM_LIMIT)
		_pan_last = event.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var world = get_global_mouse_position()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var clicked = _unit_at(world)
				if clicked and clicked.stats.faction == 0:
					GameManager.select_unit(clicked)
				else:
					GameManager.deselect_all()
			MOUSE_BUTTON_RIGHT:
				var sel = GameManager.selected_unit
				if not sel or not is_instance_valid(sel): return
				var enemy = _unit_at(world)
				if enemy and enemy.stats.faction == 1:
					sel.order_attack(enemy)
				else:
					sel.order_move(world)
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom * 1.12).clamp(Vector2(0.25,0.25), Vector2(5.0,5.0))
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom * 0.88).clamp(Vector2(0.25,0.25), Vector2(5.0,5.0))

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE: GameManager.deselect_all()
			KEY_TAB:    _cycle_selection()
			KEY_SPACE:  _focus_selected()


func _unit_at(world_pos: Vector2):
	var best = null
	var best_dist = CLICK_RADIUS
	for unit in GameManager.all_units:
		if not unit.is_alive: continue
		var d = world_pos.distance_to(unit.global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best


func _cycle_selection() -> void:
	var my_units = GameManager.bulgarian_units
	if my_units.is_empty(): return
	var cur  = GameManager.selected_unit
	var idx  = my_units.find(cur)
	GameManager.select_unit(my_units[(idx + 1) % my_units.size()])
	_focus_selected()


func _focus_selected() -> void:
	var sel = GameManager.selected_unit
	if sel and is_instance_valid(sel):
		camera.position = sel.global_position


## ── Projectiles ───────────────────────────────────────────────────────────────

func _on_fired_projectile(data: Dictionary) -> void:
	if not projectile_scene:
		if data.has("target") and is_instance_valid(data["target"]):
			data["target"].take_damage(data["damage"])
		return
	var proj = projectile_scene.instantiate()
	proj.global_position = data["from"]
	proj.damage          = data["damage"]
	proj.speed           = data.get("speed", 300.0)
	proj.aoe_radius      = data.get("aoe", 0.0)
	proj.faction         = data.get("faction", 0)
	if data.has("target") and is_instance_valid(data["target"]):
		proj.target     = data["target"]
		proj.target_pos = data["target"].global_position
	elif data.has("target_pos"):
		proj.target_pos = data["target_pos"]
	add_child(proj)


## ── Stage / reinforcement callbacks ──────────────────────────────────────────

func _on_stage_changed(new_stage: int, info: Dictionary) -> void:
	if _hud and _hud.has_method("show_stage_banner"):
		_hud.show_stage_banner(new_stage, info)


func _on_reinforcements_arrived(_faction: int, units_data: Array) -> void:
	## The unit was already spawned by BattleStageManager._fire_reinforcement.
	## Find the most recently added living unit and show its banner.
	if units_data.is_empty(): return
	var label = units_data[0].get("label", "Reinforcements arrived!")
	## Show banner on the most recently registered unit
	var all = GameManager.all_units
	if all.is_empty(): return
	var newest = all[all.size() - 1]
	if newest and is_instance_valid(newest) and newest.has_method("show_banner"):
		newest.show_banner(label)
	if _hud and _hud.has_method("show_reinforcement_toast"):
		_hud.show_reinforcement_toast(label)


## ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_game_over(winner: int) -> void:
	if _hud and _hud.has_method("show_game_over"):
		_hud.show_game_over(winner)


func _on_units_changed() -> void:
	if _hud and _hud.has_method("update_counts"):
		_hud.update_counts(GameManager.bulgarian_units.size(), GameManager.ottoman_units.size())

extends Node2D

@export var dot_scene:        PackedScene
@export var projectile_scene: PackedScene
@export var front_line_scene: PackedScene

## Spawn positions — Bulgarian/Russian defend the north (top), Ottomans attack from south
@export var bg_spawn_points: Array[Vector2] = [
	Vector2(-180,  -320),   ## Opalchentsi — Eagle's Nest ridge
	Vector2(-380,  -180),   ## Cossacks    — left flank
	Vector2( 0,    -340),   ## Radetsky    — central summit
	Vector2( 200,  -280),   ## Skobelev    — right approach
	Vector2(-80,   -300),   ## Gurko        — command position
]
@export var ot_spawn_points: Array[Vector2] = [
	Vector2(-120,   400),   ## Nizam       — main road axis
	Vector2(-320,   350),   ## Süvari      — left flanking cavalry
	Vector2( 200,   380),   ## Top         — artillery south
	Vector2( 80,    420),   ## Veysel/Hakim — support
	Vector2( 0,     450),   ## Süleyman    — command rear
]

## Strategic positions fed to the AI
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

@onready var camera:       Camera2D   = $Camera

@onready var ui:           CanvasLayer = $UI

const CLICK_RADIUS := 30.0
var _pan_last:  Vector2 = Vector2.ZERO
var _panning:   bool    = false


func _ready() -> void:
	## Terrain — find Ground sprite safely regardless of scene tree depth
	var ground: Sprite2D = null
	for node in get_tree().get_nodes_in_group("ground"):
		ground = node
		break
	if not ground:
		ground = _find_node_by_name(self, "Ground") as Sprite2D
	if ground:
		TerrainManager.initialize(ground)
	else:
		push_warning("TerrainManager: Ground sprite not found — terrain effects disabled")

	## Win zone
	GameManager.shipka_zone = Rect2(shipka_zone_pos, shipka_zone_size)

	## Signals
	GameManager.game_over.connect(_on_game_over)
	GameManager.units_changed.connect(_on_units_changed)

	## Spawn
	_spawn_all()

	## Front line
	_spawn_front_line()

	## Start AI — deferred so scene tree is fully ready
	call_deferred("_start_ai")



## Recursively finds a node by name anywhere in the tree
func _find_node_by_name(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var result = _find_node_by_name(child, target)
		if result:
			return result
	return null



func _spawn_front_line() -> void:
	if not front_line_scene:
		## No scene assigned — create it programmatically
		var fl = Node2D.new()
		fl.set_script(load("res://front_line.gd"))
		fl.name = "FrontLine"
		add_child(fl)
		return
	var fl = front_line_scene.instantiate()
	fl.name = "FrontLine"
	add_child(fl)

func _start_ai() -> void:
	if not is_instance_valid(OttomanAI):
		push_error("OttomanAI autoload not found. Add ottoman_ai.gd as autoload named 'OttomanAI'.")
		return
	OttomanAI.start(ot_rally_pos, eagles_nest_pos, pass_road_pos,
		left_ridge_pos, right_ridge_pos)

func _spawn_all() -> void:
	var bg = [res_opalchenets, res_kazak, res_orudie, res_sanitar, res_gurko]
	var ot = [res_nizam,       res_suvari, res_top,  res_hakim,   res_suleiman]
	for i in bg.size():
		if bg[i]: _spawn(bg[i], bg_spawn_points[i] if i < bg_spawn_points.size() else Vector2(-300+i*60, -200))
	for i in ot.size():
		if ot[i]: _spawn(ot[i], ot_spawn_points[i]  if i < ot_spawn_points.size() else Vector2(-200+i*60,  400))


func _spawn(res: UnitStats, pos: Vector2) -> void:
	if not dot_scene: return
	var unit = dot_scene.instantiate()
	unit.stats = res
	unit.global_position = pos
	add_child(unit)
	unit.fired_projectile.connect(_on_fired_projectile)
	GameManager.register_unit(unit)


## ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	## Middle-mouse pan
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_pan_last = event.position
	if event is InputEventMouseMotion and _panning:
		camera.position -= (event.position - _pan_last) / camera.zoom
		_pan_last = event.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var world = get_global_mouse_position()

		match event.button_index:
			MOUSE_BUTTON_LEFT:
				## Select only YOUR units (Bulgarian/Russian = faction 0)
				var clicked = _unit_at(world)
				if clicked and clicked.stats.faction == 0:
					GameManager.select_unit(clicked)
				else:
					GameManager.deselect_all()

			MOUSE_BUTTON_RIGHT:
				var sel = GameManager.selected_unit
				if not sel or not is_instance_valid(sel): return
				## Right-click enemy → attack order
				var enemy = _unit_at(world)
				if enemy and enemy.stats.faction == 1:
					sel.order_attack(enemy)
				else:
					## Right-click ground → move order
					sel.order_move(world)

			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom * 1.12).clamp(Vector2(0.2,0.2), Vector2(5.0,5.0))
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom * 0.88).clamp(Vector2(0.2,0.2), Vector2(5.0,5.0))

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			GameManager.deselect_all()
		## Tab cycles through your units
		if event.keycode == KEY_TAB:
			_cycle_selection()


func _unit_at(world_pos: Vector2):
	var best      = null
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
	var cur = GameManager.selected_unit
	var idx = my_units.find(cur)
	var next_idx = (idx + 1) % my_units.size()
	GameManager.select_unit(my_units[next_idx])


## ── Projectiles ───────────────────────────────────────────────────────────────

func _on_fired_projectile(data: Dictionary) -> void:
	if not projectile_scene:
		if data.has("target") and is_instance_valid(data["target"]):
			data["target"].take_damage(data["damage"])
		return
	var proj = projectile_scene.instantiate()
	proj.global_position = data["from"]
	proj.damage     = data["damage"]
	proj.speed      = data.get("speed", 300.0)
	proj.aoe_radius = data.get("aoe", 0.0)
	proj.faction    = data.get("faction", 0)
	if data.has("target") and is_instance_valid(data["target"]):
		proj.target     = data["target"]
		proj.target_pos = data["target"].global_position
	elif data.has("target_pos"):
		proj.target_pos = data["target_pos"]
	add_child(proj)


## ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_game_over(winner: int) -> void:
	if ui and ui.has_method("show_game_over"):
		ui.show_game_over(winner)


func _on_units_changed() -> void:
	if ui and ui.has_method("update_counts"):
		ui.update_counts(GameManager.bulgarian_units.size(), GameManager.ottoman_units.size())

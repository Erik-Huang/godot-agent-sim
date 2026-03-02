extends Node2D

const AgentScene: PackedScene = preload("res://agent.tscn")

# AUDIT-012: Centralised world bounds
const WORLD_BOUNDS := Rect2(10, 10, 1180, 780)

# TODO: replace with @export var roster: Array[AgentDefinition] once .tres files created
var agent_data: Array[Dictionary] = [
	{"name": "Alice", "personality": "curious", "color": Color(0.3, 0.8, 1.0)},
	{"name": "Bob", "personality": "shy", "color": Color(0.6, 0.4, 0.9)},
	{"name": "Carol", "personality": "social", "color": Color(1.0, 0.5, 0.3)},
	{"name": "Dave", "personality": "wanderer", "color": Color(0.3, 0.9, 0.4)},
	{"name": "Eve", "personality": "lazy", "color": Color(0.9, 0.3, 0.6)},
]

var agents: Array = []

# INT-005: Social waypoints — named hotspots for encounter density
var waypoints: Array[Dictionary] = []

# DBG-001: Spacebar pause
var pause_label: Label

# GFX-005: Time-of-day lighting
var sim_time: float = 8.0  # start at 8am
const SIM_SPEED: float = 60.0  # 1 real second = 1 sim minute
var canvas_mod: CanvasModulate
var clock_label: Label

var zone_rects: Dictionary = {
	"park": Rect2(10, 10, 580, 380),
	"cafe": Rect2(610, 10, 580, 380),
	"town_square": Rect2(10, 410, 1180, 380),
}

@onready var agent_container: Node2D = $AgentContainer
@onready var ui_panel: VBoxContainer = $UIPanel
@onready var nav_region: NavigationRegion2D = $NavigationRegion2D

# GFX-004: Zone color tints
var zone_colors: Dictionary = {
	"park": Color(0.2, 0.8, 0.2, 0.06),
	"cafe": Color(1.0, 0.7, 0.3, 0.06),
	"town_square": Color(0.5, 0.6, 0.8, 0.06),
}

func _ready() -> void:
	# AUDIT-015: randomize() removed — auto-called in Godot 4
	_setup_navigation()
	_setup_wall_shapes()
	_setup_zone_visuals()
	# DBG-001: Main processes during pause (for input); agents pause via their container
	process_mode = Node.PROCESS_MODE_ALWAYS
	agent_container.process_mode = Node.PROCESS_MODE_PAUSABLE

	# DBG-001: Create PAUSED overlay label
	pause_label = Label.new()
	pause_label.text = "PAUSED"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 48)
	pause_label.add_theme_color_override("font_color", Color.WHITE)
	pause_label.add_theme_constant_override("outline_size", 3)
	pause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	pause_label.set_anchors_preset(Control.PRESET_CENTER)
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_label.size = Vector2(400, 60)
	pause_label.position = Vector2(400, 370)
	pause_label.visible = false
	pause_label.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_label.z_index = 100
	add_child(pause_label)
	# DBG-001: UIPanel stays responsive while paused
	ui_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	# GFX-005: CanvasModulate for time-of-day lighting
	canvas_mod = CanvasModulate.new()
	canvas_mod.color = Color.WHITE
	add_child(canvas_mod)
	# GFX-005: Clock label in UI
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 14)
	clock_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label.text = "08:00"
	ui_panel.add_child(clock_label)
	ui_panel.move_child(clock_label, 0)  # Put clock at top of UI panel

	# INT-005: Social waypoints
	waypoints = [
		{"name": "park bench", "position": Vector2(150, 180), "zone": "park"},
		{"name": "park fountain", "position": Vector2(350, 250), "zone": "park"},
		{"name": "cafe counter", "position": Vector2(750, 120), "zone": "cafe"},
		{"name": "cafe window", "position": Vector2(950, 280), "zone": "cafe"},
		{"name": "square stage", "position": Vector2(400, 580), "zone": "town_square"},
		{"name": "square bench", "position": Vector2(700, 650), "zone": "town_square"},
	]

	# MEM-005: Connect reflection signal to LLM reflection handler
	MemoryService.on_reflection_ready.connect(_on_reflection_ready)

	# Wait one frame for navigation to bake
	await get_tree().physics_frame
	_spawn_agents()

# DBG-001: Spacebar pause toggle + GFX-005: Time-of-day
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		get_tree().paused = not get_tree().paused
		pause_label.visible = get_tree().paused
	# GFX-005: Advance sim clock and update lighting
	if not get_tree().paused:
		sim_time = fmod(sim_time + delta * SIM_SPEED / 60.0, 24.0)
		_update_lighting()
		clock_label.text = "%02d:%02d" % [int(sim_time), int(fmod(sim_time * 60, 60))]
		# AUDIT-019: Expose sim_time to agents
		for agent in agents:
			agent.sim_time = sim_time

# GFX-005: Time-of-day lighting
func _update_lighting() -> void:
	var t := sim_time
	var col: Color
	if t < 6.0 or t >= 22.0:    # night
		col = Color(0.3, 0.35, 0.55)
	elif t < 8.0 or t >= 20.0:  # dawn/dusk
		col = Color(0.85, 0.65, 0.45)
	elif t < 18.0:               # day
		col = Color.WHITE
	else:                         # evening
		col = Color(1.0, 0.85, 0.6)
	canvas_mod.color = canvas_mod.color.lerp(col, 0.01)  # smooth transition

func _setup_zone_visuals() -> void:
	var zone_vis := Node2D.new()
	zone_vis.name = "ZoneVisuals"
	# Insert before AgentContainer so tints render beneath agents
	add_child(zone_vis)
	move_child(zone_vis, agent_container.get_index())
	for zone_name in zone_rects:
		var rect: Rect2 = zone_rects[zone_name]
		var color_rect := ColorRect.new()
		color_rect.position = rect.position
		color_rect.size = rect.size
		if zone_colors.has(zone_name):
			color_rect.color = zone_colors[zone_name]
		else:
			color_rect.color = Color(0.5, 0.5, 0.5, 0.06)
		color_rect.name = "Zone_%s" % zone_name
		zone_vis.add_child(color_rect)

func _setup_navigation() -> void:
	var nav_poly: NavigationPolygon = NavigationPolygon.new()
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(10, 10),
		Vector2(1190, 10),
		Vector2(1190, 790),
		Vector2(10, 790),
	])
	nav_poly.add_outline(outline)
	# Use modern API to avoid deprecation warning
	var source_geo: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geo, nav_region)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geo)
	nav_region.navigation_polygon = nav_poly

func _setup_wall_shapes() -> void:
	# Top wall
	var top_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	top_shape.normal = Vector2(0, 1)
	top_shape.distance = 5
	$Walls/WallTop/CollisionShape2D.shape = top_shape
	# Bottom wall
	var bot_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	bot_shape.normal = Vector2(0, -1)
	bot_shape.distance = -795
	$Walls/WallBottom/CollisionShape2D.shape = bot_shape
	# Left wall
	var left_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	left_shape.normal = Vector2(1, 0)
	left_shape.distance = 5
	$Walls/WallLeft/CollisionShape2D.shape = left_shape
	# Right wall
	var right_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	right_shape.normal = Vector2(-1, 0)
	right_shape.distance = -1195
	$Walls/WallRight/CollisionShape2D.shape = right_shape

func _spawn_agents() -> void:
	var spawn_positions: Array[Vector2] = [
		Vector2(200, 200),   # Park
		Vector2(300, 300),   # Park
		Vector2(800, 200),   # Cafe
		Vector2(600, 600),   # Town Square
		Vector2(900, 600),   # Town Square
	]
	for i in range(agent_data.size()):
		var data: Dictionary = agent_data[i]
		var agent = AgentScene.instantiate()
		agent.agent_name = data["name"]
		agent.personality = data["personality"]
		agent.agent_color = data["color"]
		agent.position = spawn_positions[i]
		agent.zone_rects = zone_rects
		agent.waypoints = waypoints  # INT-005
		agent.world_bounds = WORLD_BOUNDS  # AUDIT-012
		agent.interaction_started.connect(_on_agent_interaction)
		agent.state_changed.connect(_on_agent_state_changed)
		agent_container.add_child(agent)
		agents.append(agent)
		ui_panel.register_agent(data["name"], data["personality"])
	# AUDIT-011: Register agent names for dynamic importance heuristic
	LlmDialogue.register_agents(agents.map(func(a): return a.agent_name.to_lower()))

# INT-001: Proximity detection moved to Area2D signals on each agent
# The O(n²) loop is no longer needed here

# MEM-005: Trigger LLM reflection when an agent hits the observation threshold
func _on_reflection_ready(agent_name: String) -> void:
	LlmDialogue.request_reflection(agent_name)

func _on_agent_interaction(agent_name: String, other_name: String, dialogue: String) -> void:
	ui_panel.log_interaction(agent_name, other_name, dialogue)

func _on_agent_state_changed(agent_name: String, new_state: String) -> void:
	ui_panel.update_agent_state(agent_name, new_state)

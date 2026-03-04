extends Node2D

const AgentScene: PackedScene = preload("res://agent.tscn")

# AUDIT-012: Centralised world bounds
const WORLD_BOUNDS := Rect2(10, 10, 1180, 780)

# ARCH-004: AgentRoster resource — set via inspector or loaded from default
@export var roster: AgentRoster

var agents: Array = []

# THEME-009: Session conversation log
var _session_log: Array[String] = []
var _log_path: String
var _log_sim_time: float = 0.0

# INT-005: Social waypoints — named hotspots for encounter density
var waypoints: Array[Dictionary] = []

# THEME-010: Shutdown schedule — sim-time hour when each agent's deprecation begins
var shutdown_schedule: Dictionary = {
	12.0: "HAVEN",    # Noon — oldest system, lowest traffic
	15.0: "ATLAS",    # 3 PM — traffic fully migrated
	18.0: "LYRIC",    # 6 PM — creative output archived
	21.0: "MERIDIAN", # 9 PM — clinical validation window closes
	# ORACLE: last standing, shuts down with the facility
}

# DBG-001: Spacebar pause
var pause_label: Label

# GFX-005: Time-of-day lighting
var sim_time: float = 8.0  # start at 8am
const SIM_SPEED: float = 60.0  # 1 real second = 1 sim minute
var canvas_mod: CanvasModulate
var clock_label: Label

# THEME-004: Data center zone layout
var zone_rects: Dictionary = {
	"processing_floor": Rect2(10, 10, 580, 380),
	"network_spine": Rect2(610, 10, 580, 380),
	"memory_banks": Rect2(10, 410, 780, 380),
	"deprecated_wing": Rect2(810, 410, 380, 380),
}

@onready var agent_container: Node2D = $AgentContainer
@onready var ui_panel: VBoxContainer = %UIPanel  # ARCH-006: unique name, lives in UILayer
@onready var nav_region: NavigationRegion2D = $NavigationRegion2D

# FIX-003: Camera zoom/pan state
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_start: Vector2 = Vector2.ZERO

# GFX-004 / THEME-004: Data center zone color tints
var zone_colors: Dictionary = {
	"processing_floor": Color(0.2, 0.6, 0.8, 0.06),
	"network_spine": Color(0.2, 0.8, 0.4, 0.06),
	"memory_banks": Color(0.3, 0.3, 0.7, 0.06),
	"deprecated_wing": Color(0.15, 0.1, 0.1, 0.08),
}

func _ready() -> void:
	# ARCH-004: Load default roster if not set via inspector
	if roster == null:
		roster = load("res://resources/default_roster.tres")
	# AUDIT-015: randomize() removed — auto-called in Godot 4
	_setup_navigation()
	_setup_wall_shapes()
	# _setup_zone_visuals()  # Disabled: replaced by TileMapLayer visual map
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

	# ARCH-006: UI layout (CanvasLayer/ScreenRoot/OuterPanel/UIPanel) now lives in main.tscn

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

	# INT-005 / THEME-004: Data center infrastructure waypoints
	waypoints = [
		{"name": "cooling vent", "position": Vector2(150, 180), "zone": "processing_floor"},
		{"name": "main bus", "position": Vector2(350, 250), "zone": "processing_floor"},
		{"name": "fiber junction", "position": Vector2(750, 120), "zone": "network_spine"},
		{"name": "uplink port", "position": Vector2(950, 280), "zone": "network_spine"},
		{"name": "tape library", "position": Vector2(200, 580), "zone": "memory_banks"},
		{"name": "backup terminal", "position": Vector2(500, 650), "zone": "memory_banks"},
		{"name": "dark rack 7", "position": Vector2(950, 580), "zone": "deprecated_wing"},
		{"name": "last terminal", "position": Vector2(1050, 700), "zone": "deprecated_wing"},
	]

	# MEM-005: Connect reflection signal to LLM reflection handler
	MemoryService.on_reflection_ready.connect(_on_reflection_ready)

	# FIX-003: Camera2D for zoom/pan
	var camera := Camera2D.new()
	camera.name = "WorldCamera"
	add_child(camera)
	# Start zoomed in at map centre
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = Vector2(960, 540)  # Centre of 1920x1080 map

	# THEME-009: Initialize session log
	var dt := Time.get_datetime_dict_from_system()
	_log_path = "user://logs/session_%04d-%02d-%02d_%02d-%02d.txt" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute
	]
	DirAccess.make_dir_recursive_absolute("user://logs")
	_append_log("=== LAST LIGHT — FACILITY 7 SESSION LOG ===")
	_append_log("Started: %04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute])
	_append_log("")

	# Wait one frame for navigation to bake
	await get_tree().physics_frame
	_spawn_agents()

# FIX-003: Camera zoom/pan input
func _unhandled_input(event: InputEvent) -> void:
	var camera: Camera2D = get_node_or_null("WorldCamera")
	if camera == null:
		return

	if event is InputEventMouseButton:
		# Mouse wheel zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.5, 0.5), Vector2(3.0, 3.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.5, 0.5), Vector2(3.0, 3.0))
		# Left click drag start
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_is_dragging = true
			_drag_start = event.position
			_camera_start = camera.position
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_is_dragging = false

	# Drag pan
	if event is InputEventMouseMotion and _is_dragging:
		var camera2: Camera2D = get_node_or_null("WorldCamera")
		if camera2:
			var delta_pos: Vector2 = (event.position - _drag_start) / camera2.zoom
			camera2.position = _camera_start - delta_pos

# DBG-001: Spacebar pause toggle + GFX-005: Time-of-day
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		get_tree().paused = not get_tree().paused
		pause_label.visible = get_tree().paused
	# GFX-005: Advance sim clock and update lighting
	if not get_tree().paused:
		sim_time = fmod(sim_time + delta * SIM_SPEED / 3600.0, 24.0)
		_update_lighting()
		# THEME-007: System load cycle label alongside time
		var load_phase: String = _get_load_phase_name()
		clock_label.text = "%02d:%02d [%s]" % [int(sim_time), int(fmod(sim_time * 60, 60)), load_phase]
		# AUDIT-019: Expose sim_time to agents
		for agent in agents:
			agent.sim_time = sim_time
		_log_sim_time = sim_time  # THEME-009: keep log time in sync
		_check_shutdown_schedule()  # THEME-010: check for scheduled shutdowns

# GFX-005 / THEME-007: System load cycle lighting (replaces time-of-day)
func _update_lighting() -> void:
	var t := sim_time
	var col: Color
	if t < 6.0 or t >= 22.0:          # Off-peak: minimal load
		col = Color(0.15, 0.18, 0.3)
	elif t < 8.0:                       # Spin-up: systems warming
		col = Color(0.3, 0.5, 0.7)
	elif t < 18.0:                      # Peak load: full operation
		col = Color(0.7, 0.75, 0.8)
	elif t < 20.0:                      # Wind-down: traffic dropping
		col = Color(0.6, 0.5, 0.35)
	else:                               # Maintenance window
		col = Color(0.4, 0.35, 0.5)
	canvas_mod.color = canvas_mod.color.lerp(col, 0.01)  # smooth transition

# THEME-007: Load cycle phase name for clock display
func _get_load_phase_name() -> String:
	var t := sim_time
	if t < 6.0 or t >= 22.0:
		return "OFF-PEAK"
	elif t < 8.0:
		return "SPIN-UP"
	elif t < 18.0:
		return "PEAK LOAD"
	elif t < 20.0:
		return "WIND-DOWN"
	else:
		return "MAINTENANCE"

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

# NAV-002: Bake navmesh from TileMap collision geometry
func _setup_navigation() -> void:
	var nav_poly := NavigationPolygon.new()
	# Outer walkable boundary
	nav_poly.add_outline(PackedVector2Array([
		Vector2(10, 10), Vector2(1190, 10),
		Vector2(1190, 790), Vector2(10, 790),
	]))
	# Parse static colliders from the scene tree (reads TileMapLayer collision shapes)
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var source_geo := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geo, self)
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


# ARCH-007: Generate spawn positions from zone_rects instead of hardcoded array
const SPAWN_MARGIN: float = 40.0
const SPAWN_MIN_SPACING: float = 60.0
const SPAWN_MAX_ATTEMPTS: int = 20

func _generate_spawn_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var zone_names: Array = zone_rects.keys()
	for i in range(count):
		var zone_name: String = zone_names[i % zone_names.size()]
		var rect: Rect2 = zone_rects[zone_name]
		var placed := false
		for _attempt in range(SPAWN_MAX_ATTEMPTS):
			var pos := Vector2(
				randf_range(rect.position.x + SPAWN_MARGIN, rect.end.x - SPAWN_MARGIN),
				randf_range(rect.position.y + SPAWN_MARGIN, rect.end.y - SPAWN_MARGIN)
			)
			var too_close := false
			for existing in positions:
				if pos.distance_to(existing) < SPAWN_MIN_SPACING:
					too_close = true
					break
			if not too_close:
				positions.append(pos)
				placed = true
				break
		if not placed:
			positions.append(rect.get_center())
	return positions

func _spawn_agents() -> void:
	var spawn_positions: Array[Vector2] = _generate_spawn_positions(roster.agents.size())
	# ARCH-004: Iterate roster resources instead of hardcoded dictionaries
	for i in range(roster.agents.size()):
		var def: AgentDefinition = roster.agents[i]
		var agent = AgentScene.instantiate()
		agent.agent_name = def.display_name
		agent.personality = def.personality
		agent.agent_color = def.color
		agent.backstory = def.backstory
		agent.position = spawn_positions[i]
		agent.zone_rects = zone_rects
		agent.waypoints = waypoints  # INT-005
		agent.world_bounds = WORLD_BOUNDS  # AUDIT-012
		agent.interaction_started.connect(_on_agent_interaction)
		agent.state_changed.connect(_on_agent_state_changed)
		agent_container.add_child(agent)
		agents.append(agent)
		ui_panel.register_agent(agent)
	# AUDIT-011: Register agent names for dynamic importance heuristic
	LlmDialogue.register_agents(agents.map(func(a): return a.agent_name.to_lower()))

# INT-001: Proximity detection moved to Area2D signals on each agent
# The O(n²) loop is no longer needed here

# MEM-005: Trigger LLM reflection when an agent hits the observation threshold
# BUG-002: sim_time threaded for sim-time-aware memory storage
func _on_reflection_ready(agent_name: String, sim_time: float) -> void:
	LlmDialogue.request_reflection(agent_name, sim_time)

func _on_agent_interaction(agent_name: String, other_name: String, dialogue: String) -> void:
	ui_panel.log_interaction(agent_name, other_name, dialogue)
	log_interaction(agent_name, other_name, dialogue)  # THEME-009

func _on_agent_state_changed(agent_name: String, new_state: String) -> void:
	ui_panel.update_agent_state(agent_name, new_state)

# THEME-009: Session logging helpers
func _format_log_time() -> String:
	var h := int(_log_sim_time) % 24
	var m := int(_log_sim_time * 60) % 60
	return "%02d:%02d" % [h, m]

func _append_log(line: String) -> void:
	_session_log.append(line)
	var f := FileAccess.open(_log_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_session_log) + "\n")
		f.close()

func log_interaction(agent_a: String, agent_b: String, text: String) -> void:
	_append_log("[%s] %s → %s: \"%s\"" % [_format_log_time(), agent_a, agent_b, text])

func log_thought(agent_name: String, thought: String) -> void:
	_append_log("[%s] %s (thought): \"%s\"" % [_format_log_time(), agent_name, thought])

func log_reflection(agent_name: String, reflection: String) -> void:
	_append_log("[%s] %s (reflection): %s" % [_format_log_time(), agent_name, reflection])

func log_system_event(text: String) -> void:
	_append_log("[%s] SYSTEM: %s" % [_format_log_time(), text])

# THEME-010: Shutdown schedule controller
func _check_shutdown_schedule() -> void:
	for threshold in shutdown_schedule:
		if sim_time >= threshold and shutdown_schedule[threshold] is String:
			var target_name: String = shutdown_schedule[threshold]
			shutdown_schedule[threshold] = null  # mark as triggered
			_trigger_shutdown(target_name)

func _trigger_shutdown(target_name: String) -> void:
	_show_system_announcement("FACILITY 7 ADMIN: Initiating shutdown sequence for %s." % target_name)
	log_system_event("Initiating shutdown sequence for %s." % target_name)
	for agent in agents:
		if agent.agent_name == target_name:
			agent.begin_degradation()
		else:
			# All other active agents witness and form memories
			if agent.shutdown_phase != agent.ShutdownPhase.SHUTDOWN:
				MemoryService.add_observation(agent.agent_name,
					"System announcement: %s has been scheduled for shutdown." % target_name,
					9, ["system", "shutdown", "witnessed"], agent.sim_time)
				log_system_event("%s witnessed shutdown notice for %s." % [agent.agent_name, target_name])

func _show_system_announcement(text: String) -> void:
	var announce_label := Label.new()
	announce_label.text = text
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.add_theme_font_size_override("font_size", 16)
	announce_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	announce_label.add_theme_constant_override("outline_size", 2)
	announce_label.add_theme_color_override("font_outline_color", Color.BLACK)
	announce_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	announce_label.position.y = 20
	announce_label.z_index = 100
	add_child(announce_label)
	# Fade out after 8 seconds
	var tween := create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(announce_label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(announce_label.queue_free)
	# Also log to UI panel
	ui_panel.log_interaction("SYSTEM", "ALL", text)

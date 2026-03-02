extends CharacterBody2D

signal interaction_started(agent_name: String, other_name: String, dialogue: String)
signal state_changed(agent_name: String, state: String)

enum State { IDLE, WANDER, SEEK, INTERACT, MOVING_TO_ZONE }

@export var agent_name: String = "Agent"
@export var personality: String = "curious"
@export var agent_color: Color = Color.WHITE

var state: State = State.IDLE
var speed: float = 60.0
var idle_timer: float = 0.0
var interact_timer: float = 0.0
var interaction_cooldown: float = 0.0
var seek_target: CharacterBody2D = null
var speech_timer: float = 0.0
var current_zone: String = ""
var interact_partner: CharacterBody2D = null
var detection_area: Area2D = null
var seek_chance: float = 0.3
var approach_tendency: float = 0.0
var _rolled_for: Dictionary = {}  # AUDIT-002: track per-encounter rolls

# Zone definitions (set by main.gd)
var zone_rects: Dictionary = {}

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var speech_bubble: PanelContainer = $SpeechBubble
@onready var speech_label: Label = $SpeechBubble/SpeechLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# Create programmatic sprite texture
	var img: Image = Image.create(20, 28, false, Image.FORMAT_RGBA8)
	img.fill(agent_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex

	# Set collision shape
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(18, 26)
	collision_shape.shape = shape

	name_label.text = agent_name
	speech_bubble.visible = false

	# Apply speed modifier based on personality
	match personality:
		"lazy":
			speed = 30.0
		"wanderer":
			speed = 85.0
		"shy":
			speed = 50.0
		"curious":
			speed = 60.0
		"social":
			speed = 65.0

	# INT-006: Personality-driven approach/flee tendencies
	match personality:
		"social":
			seek_chance = 0.7
			approach_tendency = 0.8
		"shy":
			seek_chance = 0.1
			approach_tendency = -0.5
		"curious":
			seek_chance = 0.5
			approach_tendency = 0.2
		"wanderer":
			seek_chance = 0.2
			approach_tendency = 0.0
		"lazy":
			seek_chance = 0.15
			approach_tendency = -0.1
		_:
			seek_chance = 0.3
			approach_tendency = 0.0

	# Start in IDLE
	_enter_idle()

	# INT-001: Area2D proximity detection
	var detection_area := Area2D.new()
	var cshape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 80.0
	cshape.shape = circle
	detection_area.add_child(cshape)
	detection_area.monitoring = true
	detection_area.monitorable = true
	add_child(detection_area)
	detection_area.area_entered.connect(_on_area_entered)
	detection_area.area_exited.connect(_on_area_exited)
	self.detection_area = detection_area

func get_state_name() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.WANDER:
			return "wander"
		State.SEEK:
			return "seek"
		State.INTERACT:
			return "interact"
		State.MOVING_TO_ZONE:
			return "moving_to_zone"
	return "unknown"

func _physics_process(delta: float) -> void:
	# Speech bubble timer
	if speech_timer > 0.0:
		speech_timer -= delta
		if speech_timer <= 0.0:
			speech_bubble.visible = false

	# Interaction cooldown
	if interaction_cooldown > 0.0:
		interaction_cooldown -= delta

	# Update current zone
	_update_current_zone()

	match state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.SEEK:
			_process_seek(delta)
		State.INTERACT:
			_process_interact(delta)
		State.MOVING_TO_ZONE:
			_process_moving_to_zone(delta)

func _update_current_zone() -> void:
	for zone_name in zone_rects:
		var rect: Rect2 = zone_rects[zone_name]
		if rect.has_point(position):
			current_zone = zone_name
			return
	current_zone = ""

# --- IDLE ---
func _enter_idle() -> void:
	state = State.IDLE
	idle_timer = randf_range(2.0, 3.0)
	velocity = Vector2.ZERO
	interact_partner = null
	queue_redraw()
	state_changed.emit(agent_name, "idle")

func _process_idle(delta: float) -> void:
	_poll_nearby_agents()
	idle_timer -= delta
	# AUDIT-010: Occasionally surface an idle thought via Thoughts autoload
	if idle_timer > 0.0 and speech_timer <= 0.0 and randf() < 0.01:
		show_speech(Thoughts.get_thought(personality))
	if idle_timer <= 0.0:
		# Decide next action
		var roll: float = randf()
		if roll < 0.15:
			_enter_moving_to_zone()
		else:
			_enter_wander()

# --- WANDER ---
func _enter_wander() -> void:
	state = State.WANDER
	_pick_wander_target()
	state_changed.emit(agent_name, "wander")

func _pick_wander_target() -> void:
	# Pick a random point within current zone (or nearby)
	var target_pos: Vector2
	if current_zone != "" and zone_rects.has(current_zone):
		var rect: Rect2 = zone_rects[current_zone]
		target_pos = Vector2(
			randf_range(rect.position.x + 20, rect.end.x - 20),
			randf_range(rect.position.y + 20, rect.end.y - 20)
		)
	else:
		target_pos = position + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		target_pos.x = clampf(target_pos.x, 30, 1170)
		target_pos.y = clampf(target_pos.y, 30, 770)
	nav_agent.target_position = target_pos

func _process_wander(_delta: float) -> void:
	_poll_nearby_agents()
	if nav_agent.is_navigation_finished():
		_enter_idle()
		return
	_move_toward_nav_target()

# --- SEEK ---
func _enter_seek(target: CharacterBody2D) -> void:
	state = State.SEEK
	seek_target = target
	nav_agent.target_position = target.position
	state_changed.emit(agent_name, "seek")

func _process_seek(_delta: float) -> void:
	if seek_target == null or not is_instance_valid(seek_target):
		_enter_wander()
		return
	nav_agent.target_position = seek_target.position
	var dist: float = position.distance_to(seek_target.position)
	if dist < 35.0:
		_enter_interact(seek_target)
		return
	if dist > 200.0:
		_enter_wander()
		return
	_move_toward_nav_target()

# --- INTERACT ---
func _enter_interact(other: CharacterBody2D) -> void:
	state = State.INTERACT
	interact_timer = 5.0
	interaction_cooldown = 5.0
	velocity = Vector2.ZERO
	interact_partner = other
	show_action_text("Chatting...")
	state_changed.emit(agent_name, "interact")
	# AUDIT-001: Notify partner so both agents enter INTERACT state
	if other.has_method("receive_interaction"):
		other.receive_interaction(self)
	# Request dialogue from LLM system
	if LlmDialogue:
		LlmDialogue.request_dialogue(self, other)

# AUDIT-001: Allow another agent to pull us into an interaction
func receive_interaction(initiator: CharacterBody2D) -> void:
	if state == State.INTERACT or state == State.SEEK:
		return
	interact_partner = initiator
	interact_timer = 5.0
	interaction_cooldown = 5.0
	velocity = Vector2.ZERO
	state = State.INTERACT
	queue_redraw()
	state_changed.emit(agent_name, "interact")

func _process_interact(delta: float) -> void:
	velocity = Vector2.ZERO
	interact_timer -= delta
	# AUDIT-001: Face toward interaction partner
	if interact_partner and is_instance_valid(interact_partner):
		var face_dir: Vector2 = (interact_partner.global_position - global_position).normalized()
		if face_dir.length() > 0.01:
			sprite.flip_h = face_dir.x < 0.0
		queue_redraw()
	if interact_timer <= 0.0:
		_enter_idle()

func show_speech(text: String) -> void:
	speech_label.text = text
	speech_bubble.visible = true
	speech_timer = 4.0

# --- MOVING_TO_ZONE ---
func _enter_moving_to_zone() -> void:
	state = State.MOVING_TO_ZONE
	# Pick a random different zone
	var zone_names: Array = zone_rects.keys()
	if zone_names.size() == 0:
		_enter_wander()
		return
	var candidates: Array = []
	for z in zone_names:
		if z != current_zone:
			candidates.append(z)
	if candidates.size() == 0:
		candidates = zone_names
	var target_zone: String = candidates[randi() % candidates.size()]
	var rect: Rect2 = zone_rects[target_zone]
	var target_pos: Vector2 = Vector2(
		randf_range(rect.position.x + 30, rect.end.x - 30),
		randf_range(rect.position.y + 30, rect.end.y - 30)
	)
	nav_agent.target_position = target_pos
	show_action_text("→ %s" % target_zone)
	state_changed.emit(agent_name, "moving_to_zone")

func _process_moving_to_zone(_delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_enter_idle()
		return
	_move_toward_nav_target()

# --- GFX-002: Interaction indicator ---
func _draw() -> void:
	if state == State.INTERACT and interact_partner and is_instance_valid(interact_partner):
		var target_local: Vector2 = interact_partner.global_position - global_position
		draw_line(Vector2.ZERO, target_local, Color(1.0, 1.0, 1.0, 0.4), 1.5)

# --- GFX-001: Floating action text ---
func show_action_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.position = Vector2(-20, -45)
	label.z_index = 10
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30.0, 1.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(label.queue_free)

# --- Movement helper ---
func _move_toward_nav_target() -> void:
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_pos - global_position).normalized()
	velocity = direction * speed
	move_and_slide()


# INT-001 fix: re-check overlapping agents each frame while idle/wander
# area_entered fires once; this ensures missed rolls get retried
func _poll_nearby_agents() -> void:
	if detection_area == null:
		return
	for area in detection_area.get_overlapping_areas():
		var other = area.get_parent()
		if other != self and other is CharacterBody2D:
			# AUDIT-002: Only roll once per encounter
			if _rolled_for.has(other.agent_name):
				continue
			check_nearby(other)
			if state == State.SEEK or state == State.INTERACT:
				return

# --- Area2D proximity signal handler (INT-001) ---
func _on_area_entered(area: Area2D) -> void:
	var other = area.get_parent()
	if other != self and other is CharacterBody2D:
		# AUDIT-002: Only roll once per encounter
		if _rolled_for.has(other.agent_name):
			return
		check_nearby(other)

# AUDIT-002: Clear roll tracking when agent leaves detection zone
func _on_area_exited(area: Area2D) -> void:
	var other = area.get_parent()
	if other != self and other is CharacterBody2D and other.has_method("get_state_name"):
		_rolled_for.erase(other.agent_name)

# --- Called to check for nearby agents ---
func check_nearby(other: CharacterBody2D) -> void:
	if state == State.INTERACT or state == State.SEEK:
		return
	if interaction_cooldown > 0.0:
		return
	var dist: float = position.distance_to(other.position)
	if dist < 80.0 and other.interaction_cooldown <= 0.0 and other.state != State.INTERACT:
		# AUDIT-002: Record that we rolled for this agent (pass or fail)
		_rolled_for[other.agent_name] = true
		if randf() < seek_chance:
			# INT-006: Negative approach_tendency = flee instead of seek
			if approach_tendency < 0.0 and randf() < absf(approach_tendency):
				_enter_flee(other)
			else:
				_enter_seek(other)

# --- FLEE (INT-006: personality-driven avoidance) ---
func _enter_flee(other: CharacterBody2D) -> void:
	state = State.WANDER
	# Pick a point opposite to other agent's position
	var away_dir: Vector2 = (position - other.position).normalized()
	var flee_target: Vector2 = position + away_dir * 120.0
	flee_target.x = clampf(flee_target.x, 30, 1170)
	flee_target.y = clampf(flee_target.y, 30, 770)
	nav_agent.target_position = flee_target
	interaction_cooldown = 3.0
	state_changed.emit(agent_name, "flee")

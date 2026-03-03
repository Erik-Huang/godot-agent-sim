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

# GFX-006: AnimatedSprite2D for Ninja Adventure sprites
var anim_sprite: AnimatedSprite2D = null

# AUDIT-018: Direction tracking during movement
var last_move_dir: Vector2 = Vector2.RIGHT

# AUDIT-019: Sim time synced from main.gd each frame
var sim_time: float = 8.0

# INT-004: Daily agenda
var agenda: Array = []  # [{activity: String, zone: String, done: bool}]
var agenda_generated: bool = false
var backstory: String = ""  # Set by main.gd for LLM agenda generation

# INT-005: Social waypoints
var waypoints: Array = []

# AUDIT-012: Centralised world bounds
var world_bounds: Rect2 = Rect2(10, 10, 1180, 780)

# Zone definitions (set by main.gd)
var zone_rects: Dictionary = {}

# UI-001: Tracking for side panel
var last_action_text: String = ""
var last_speech_text: String = ""

# UI-002: Emote icon system
var emote_icon: TextureRect = null
var emote_textures: Dictionary = {}

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
	# GFX-006: Hide Sprite2D — _draw() handles visuals now
	sprite.visible = false

	# Set collision shape
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(18, 26)
	collision_shape.shape = shape

	name_label.text = agent_name
	# DBG-002: Readable name labels
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	# UI-001: Pixel art speech bubble with NinePatch styling
	speech_bubble.visible = false
	speech_bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	speech_bubble.custom_minimum_size = Vector2(80, 0)
	speech_bubble.position = Vector2(-40, -60)
	speech_bubble.z_index = 10
	speech_bubble.z_as_relative = false
	if ResourceLoader.exists("res://assets/ui/theme/nine_path_panel.png"):
		var stylebox := StyleBoxTexture.new()
		stylebox.texture = load("res://assets/ui/theme/nine_path_panel.png") as Texture2D
		stylebox.texture_margin_left = 3.0
		stylebox.texture_margin_top = 3.0
		stylebox.texture_margin_right = 3.0
		stylebox.texture_margin_bottom = 3.0
		stylebox.expand_margin_left = 2.0
		stylebox.expand_margin_top = 2.0
		stylebox.expand_margin_right = 2.0
		stylebox.expand_margin_bottom = 2.0
		speech_bubble.add_theme_stylebox_override("panel", stylebox)
	if ResourceLoader.exists("res://assets/ui/fonts/NormalFont.ttf"):
		var font := load("res://assets/ui/fonts/NormalFont.ttf") as Font
		speech_label.add_theme_font_override("font", font)
		speech_label.add_theme_font_size_override("font_size", 6)
	else:
		speech_label.add_theme_font_size_override("font_size", 8)
	speech_label.add_theme_color_override("font_color", Color.WHITE)

	# Apply speed modifier based on personality
	# TODO (ARCH-003): replace match blocks with PersonalityProfile resource once .tres files created
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

	# GFX-006: Set up AnimatedSprite2D from generated SpriteFrames
	anim_sprite = AnimatedSprite2D.new()
	var frames_path: String = "res://assets/sprites/agents/%s_frames.tres" % agent_name.to_lower()
	if ResourceLoader.exists(frames_path):
		anim_sprite.sprite_frames = load(frames_path)
		anim_sprite.scale = Vector2(1.0, 1.0)  # 16px = 1 tile
		anim_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(anim_sprite)
		sprite.visible = false
	else:
		push_warning("No sprite frames found for %s at %s — using _draw() fallback" % [agent_name, frames_path])

	# UI-002: Emote icon above agent head
	_load_emote_textures()
	emote_icon = TextureRect.new()
	emote_icon.position = Vector2(-7, -78)
	emote_icon.size = Vector2(14, 13)
	emote_icon.scale = Vector2(2.0, 2.0)
	emote_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emote_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emote_icon.visible = false
	emote_icon.z_index = 15
	add_child(emote_icon)

func _load_emote_textures() -> void:
	var emote_map: Dictionary = {
		"happy": "res://assets/ui/emotes/emote7.png",
		"curious": "res://assets/ui/emotes/emote4.png",
		"alert": "res://assets/ui/emotes/emote3.png",
		"love": "res://assets/ui/emotes/emote1.png",
		"sleepy": "res://assets/ui/emotes/emote9.png",
		"nervous": "res://assets/ui/emotes/emote10.png",
		"angry": "res://assets/ui/emotes/emote12.png",
	}
	for key: String in emote_map:
		var path: String = emote_map[key]
		if ResourceLoader.exists(path):
			emote_textures[key] = load(path) as Texture2D

func show_emote(emote_name: String, duration: float = 2.0) -> void:
	if not emote_textures.has(emote_name) or emote_icon == null:
		return
	emote_icon.texture = emote_textures[emote_name]
	emote_icon.modulate.a = 1.0
	emote_icon.visible = true
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(emote_icon, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: emote_icon.visible = false; emote_icon.modulate.a = 1.0)

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
	# GFX-006: Redraw each frame for direction indicator (only needed for _draw() fallback)
	if anim_sprite == null or not anim_sprite.sprite_frames:
		queue_redraw()
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
	seek_target = null  # AUDIT-004: clear stale seek_target
	state_changed.emit(agent_name, "idle")
	_update_animation()

func _process_idle(delta: float) -> void:
	# INT-004: Generate agenda once at sim start (around 8am)
	if not agenda_generated and sim_time >= 8.0:
		_request_agenda()
		agenda_generated = true
	# INT-004: Follow agenda if idle long enough
	if idle_timer < 0.5 and agenda.size() > 0:
		var next_item: Dictionary = _get_next_agenda_item()
		if not next_item.is_empty():
			_follow_agenda_item(next_item)
			return
	_poll_nearby_agents()
	idle_timer -= delta
	# AUDIT-010: Occasionally surface an idle thought via Thoughts autoload
	if idle_timer > 0.0 and speech_timer <= 0.0 and randf() < 0.01:
		show_speech(Thoughts.get_thought(personality))
		if personality == "lazy":
			show_emote("sleepy")
		elif personality == "curious":
			show_emote("curious")
	if idle_timer <= 0.0:
		# Decide next action
		var roll: float = randf()
		if roll < 0.15:
			_enter_moving_to_zone()
		elif roll < 0.35:
			# INT-005: 20% chance to path toward a social waypoint
			_enter_waypoint()
		else:
			_enter_wander()

# --- INT-005: WAYPOINT ---
func _enter_waypoint() -> void:
	if waypoints.is_empty():
		_enter_wander()
		return
	var wp: Dictionary = waypoints[randi() % waypoints.size()]
	nav_agent.target_position = wp["position"]
	state = State.WANDER  # reuse wander state — just a targeted walk
	show_action_text("→ %s" % wp["name"])
	state_changed.emit(agent_name, "wander")
	_update_animation()

# --- WANDER ---
func _enter_wander() -> void:
	state = State.WANDER
	seek_target = null  # AUDIT-004: clear stale seek_target
	_pick_wander_target()
	state_changed.emit(agent_name, "wander")
	_update_animation()

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
		target_pos.x = clampf(target_pos.x, world_bounds.position.x + 20, world_bounds.end.x - 20)
		target_pos.y = clampf(target_pos.y, world_bounds.position.y + 20, world_bounds.end.y - 20)
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
	_update_animation()

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
	_update_animation()
	# AUDIT-001: Notify partner so both agents enter INTERACT state
	if other.has_method("receive_interaction"):
		other.receive_interaction(self)
	# Request dialogue from LLM system
	if LlmDialogue:
		LlmDialogue.request_dialogue(self, other)
	# UI-002: Emote based on sentiment toward partner
	var _sentiment: float = MemoryService.get_sentiment(agent_name, other.agent_name)
	if _sentiment > 0.3:
		show_emote("love")
	else:
		show_emote("alert")

# AUDIT-001: Allow another agent to pull us into an interaction
func receive_interaction(initiator: CharacterBody2D) -> void:
	if state == State.INTERACT or state == State.SEEK:
		return
	interact_partner = initiator
	interact_timer = 5.0
	interaction_cooldown = 5.0
	velocity = Vector2.ZERO
	state = State.INTERACT
	state_changed.emit(agent_name, "interact")
	_update_animation()

func _process_interact(delta: float) -> void:
	velocity = Vector2.ZERO
	interact_timer -= delta
	# AUDIT-001: Face toward interaction partner
	if interact_partner and is_instance_valid(interact_partner):
		var face_dir: Vector2 = (interact_partner.global_position - global_position).normalized()
		if face_dir.length() > 0.01:
			last_move_dir = face_dir  # GFX-006: Update direction indicator to face partner
			_update_animation()
	if interact_timer <= 0.0:
		_enter_idle()

func show_speech(text: String) -> void:
	last_speech_text = text
	# GFX-003: Enrich bubble with last memory snippet
	var display_text: String = text
	if MemoryService:
		var top_mems: Array = MemoryService.get_top_memories(agent_name, 1)
		if top_mems.size() > 0:
			var snippet: String = top_mems[0]["text"]
			if snippet.length() > 40:
				snippet = snippet.substr(0, 37) + "..."
			display_text += "\n" + snippet
	speech_label.text = display_text
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
	_update_animation()

func _process_moving_to_zone(_delta: float) -> void:
	# AUDIT-014: Allow interactions while traveling between zones
	_poll_nearby_agents()
	if nav_agent.is_navigation_finished():
		# INT-004: Mark current agenda item done on arrival
		for item in agenda:
			if not item["done"]:
				item["done"] = true
				break
		_enter_idle()
		return
	_move_toward_nav_target()

# --- INT-004: Daily agenda helpers ---
func _request_agenda() -> void:
	var api_key: String = OS.get_environment("OPENAI_API_KEY")
	if api_key != "" and LlmDialogue:
		LlmDialogue.request_agenda(agent_name, personality, backstory, _on_agenda_received)
	else:
		# Fallback: template agenda based on personality
		agenda = _get_template_agenda()

func _get_template_agenda() -> Array:
	match personality:
		"curious":
			return [
				{"activity": "morning coffee", "zone": "cafe", "done": false},
				{"activity": "explore the park", "zone": "park", "done": false},
				{"activity": "afternoon people-watching", "zone": "town_square", "done": false},
			]
		"shy":
			return [
				{"activity": "quiet spot in the park", "zone": "park", "done": false},
				{"activity": "wander around", "zone": "cafe", "done": false},
				{"activity": "park bench evening", "zone": "park", "done": false},
			]
		"social":
			return [
				{"activity": "morning chat in the square", "zone": "town_square", "done": false},
				{"activity": "lunch at the cafe", "zone": "cafe", "done": false},
				{"activity": "evening socializing", "zone": "town_square", "done": false},
			]
		"wanderer":
			return [
				{"activity": "park stroll", "zone": "park", "done": false},
				{"activity": "cafe visit", "zone": "cafe", "done": false},
				{"activity": "town square loop", "zone": "town_square", "done": false},
				{"activity": "back to the park", "zone": "park", "done": false},
			]
		"lazy":
			return [
				{"activity": "all day at the cafe", "zone": "cafe", "done": false},
			]
		_:
			return [
				{"activity": "visit the park", "zone": "park", "done": false},
				{"activity": "stop by the cafe", "zone": "cafe", "done": false},
			]

func _on_agenda_received(items: Array) -> void:
	if items.size() > 0:
		agenda = items
	else:
		agenda = _get_template_agenda()

func _get_next_agenda_item() -> Dictionary:
	for item in agenda:
		if not item["done"]:
			return item
	return {}

func _follow_agenda_item(item: Dictionary) -> void:
	if not zone_rects.has(item["zone"]):
		item["done"] = true
		return
	var rect: Rect2 = zone_rects[item["zone"]]
	var target_pos: Vector2 = Vector2(
		randf_range(rect.position.x + 30, rect.end.x - 30),
		randf_range(rect.position.y + 30, rect.end.y - 30)
	)
	nav_agent.target_position = target_pos
	show_action_text("→ %s" % item["activity"])
	state = State.MOVING_TO_ZONE
	state_changed.emit(agent_name, "moving_to_zone")
	_update_animation()

# --- GFX-006: Animation helpers ---
func _dir_to_suffix() -> String:
	var d := last_move_dir
	if abs(d.x) > abs(d.y):
		return "right" if d.x > 0 else "left"
	else:
		return "down" if d.y > 0 else "up"

func _update_animation() -> void:
	if anim_sprite == null or not anim_sprite.sprite_frames:
		queue_redraw()  # fall back to _draw() circle
		return
	
	var dir_suffix: String = _dir_to_suffix()
	
	match state:
		State.IDLE:
			anim_sprite.play("idle_" + dir_suffix)
		State.WANDER, State.MOVING_TO_ZONE:
			anim_sprite.play("walk_" + dir_suffix)
		State.SEEK:
			anim_sprite.play("walk_" + dir_suffix)
		State.INTERACT:
			anim_sprite.play("idle_" + dir_suffix)

# --- GFX-006: Direction-aware procedural sprites (fallback) ---
func _draw() -> void:
	# Skip if AnimatedSprite2D is handling visuals
	if anim_sprite != null and anim_sprite.sprite_frames != null:
		# Still draw the interact line if needed
		if state == State.INTERACT and interact_partner and is_instance_valid(interact_partner):
			var target_local: Vector2 = interact_partner.global_position - global_position
			draw_line(Vector2.ZERO, target_local, Color(1.0, 1.0, 1.0, 0.4), 1.5)
		return
	# Body circle
	draw_circle(Vector2.ZERO, 10.0, agent_color)
	# Direction indicator (nose)
	var nose_tip: Vector2 = last_move_dir.normalized() * 14.0
	var perp: Vector2 = Vector2(-last_move_dir.y, last_move_dir.x).normalized() * 4.0
	var pts: PackedVector2Array = PackedVector2Array([
		nose_tip,
		-last_move_dir.normalized() * 2.0 + perp,
		-last_move_dir.normalized() * 2.0 - perp,
	])
	draw_colored_polygon(pts, agent_color.lightened(0.4))
	# GFX-002: INTERACT indicator line
	if state == State.INTERACT and interact_partner and is_instance_valid(interact_partner):
		var target_local: Vector2 = interact_partner.global_position - global_position
		draw_line(Vector2.ZERO, target_local, Color(1.0, 1.0, 1.0, 0.4), 1.5)

# --- GFX-001: Floating action text ---
func show_action_text(text: String) -> void:
	last_action_text = text
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 7)
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
	# AUDIT-018: Store direction and flip sprite while walking
	if direction.length() > 0.1:
		var old_suffix: String = _dir_to_suffix()
		last_move_dir = direction
		sprite.flip_h = direction.x < 0.0
		# GFX-006: Update walk animation when direction changes
		if _dir_to_suffix() != old_suffix:
			_update_animation()
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
		# MEM-004: Adjust seek chance by social sentiment
		var sentiment: float = MemoryService.get_sentiment(agent_name, other.agent_name)
		var adjusted_chance: float = seek_chance * (1.0 + sentiment * 0.5)
		if randf() < adjusted_chance:
			# INT-006: Negative approach_tendency = flee instead of seek
			if approach_tendency < 0.0 and randf() < absf(approach_tendency):
				_enter_flee(other)
			else:
				_enter_seek(other)

# --- FLEE (INT-006: personality-driven avoidance) ---
func _enter_flee(other: CharacterBody2D) -> void:
	show_emote("nervous")
	state = State.WANDER
	# Pick a point opposite to other agent's position
	var away_dir: Vector2 = (position - other.position).normalized()
	var flee_target: Vector2 = position + away_dir * 120.0
	flee_target.x = clampf(flee_target.x, world_bounds.position.x + 20, world_bounds.end.x - 20)
	flee_target.y = clampf(flee_target.y, world_bounds.position.y + 20, world_bounds.end.y - 20)
	nav_agent.target_position = flee_target
	interaction_cooldown = 3.0
	state_changed.emit(agent_name, "flee")
	_update_animation()

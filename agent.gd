extends Node2D

signal interaction_started(agent_name: String, other_name: String)
signal state_changed(agent_name: String, state: String)

@export var agent_name: String = "Agent"
@export var personality: String = "curious"
@export var agent_color: Color = Color.WHITE

var velocity: Vector2 = Vector2.ZERO
var speed: float = 60.0
var wander_timer: float = 0.0
var wander_interval: float = 2.0
var state: String = "wandering"
var interaction_cooldown: float = 0.0
var flash_timer: float = 0.0
var base_color: Color
var thought_timer: float = 0.0
var detection_radius: float = 100.0

var bounds_min: Vector2 = Vector2(20, 20)
var bounds_max: Vector2 = Vector2(780, 580)

@onready var name_label: Label = $NameLabel
@onready var thought_label: Label = $ThoughtLabel

func _ready() -> void:
	base_color = agent_color
	name_label.text = agent_name
	thought_label.text = ""
	thought_label.visible = false
	_pick_new_direction()

func _draw() -> void:
	var draw_color: Color = agent_color
	if flash_timer > 0.0:
		draw_color = Color.YELLOW
	draw_circle(Vector2.ZERO, 12, draw_color)
	draw_arc(Vector2.ZERO, detection_radius, 0, TAU, 32, Color(agent_color, 0.1), 1.0)

func _physics_process(delta: float) -> void:
	# Wander logic
	wander_timer -= delta
	if wander_timer <= 0.0:
		_pick_new_direction()

	# Apply personality-based speed modifier
	var speed_mod: float = _get_speed_modifier()
	position += velocity * speed_mod * delta

	# Keep in bounds with steering
	_steer_in_bounds()

	# Interaction cooldown
	if interaction_cooldown > 0.0:
		interaction_cooldown -= delta
		if interaction_cooldown <= 0.0 and state == "interacting":
			state = "wandering"
			state_changed.emit(agent_name, state)

	# Flash timer
	if flash_timer > 0.0:
		flash_timer -= delta
		queue_redraw()

	# Thought fade
	if thought_timer > 0.0:
		thought_timer -= delta
		var alpha: float = clampf(thought_timer / 0.5, 0.0, 1.0) if thought_timer < 0.5 else 1.0
		thought_label.modulate.a = alpha
		if thought_timer <= 0.0:
			thought_label.visible = false

func _pick_new_direction() -> void:
	var angle: float = randf() * TAU
	velocity = Vector2(cos(angle), sin(angle)) * speed
	wander_interval = randf_range(1.5, 3.5)
	wander_timer = wander_interval

func _get_speed_modifier() -> float:
	match personality:
		"lazy":
			return 0.4
		"wanderer":
			return 1.4
		"shy":
			return 0.8
		"curious":
			return 1.0
		"social":
			return 1.1
	return 1.0

func _steer_in_bounds() -> void:
	var margin: float = 30.0
	var steer: Vector2 = Vector2.ZERO

	if position.x < bounds_min.x + margin:
		steer.x += 1.0
	elif position.x > bounds_max.x - margin:
		steer.x -= 1.0

	if position.y < bounds_min.y + margin:
		steer.y += 1.0
	elif position.y > bounds_max.y - margin:
		steer.y -= 1.0

	if steer != Vector2.ZERO:
		velocity = velocity.lerp(steer.normalized() * speed, 0.1)

	position.x = clampf(position.x, bounds_min.x, bounds_max.x)
	position.y = clampf(position.y, bounds_min.y, bounds_max.y)

func check_nearby(other: Node2D) -> void:
	if other == self:
		return
	if interaction_cooldown > 0.0:
		return
	var dist: float = position.distance_to(other.position)
	if dist < detection_radius:
		_interact_with(other)

func _interact_with(other: Node2D) -> void:
	state = "interacting"
	interaction_cooldown = 4.0
	flash_timer = 0.6

	var thought: String = Thoughts.get_thought(personality)
	thought_label.text = thought
	thought_label.visible = true
	thought_timer = 2.5

	queue_redraw()
	interaction_started.emit(agent_name, other.agent_name)
	state_changed.emit(agent_name, state)

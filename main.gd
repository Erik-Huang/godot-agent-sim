extends Node2D

const AgentScene: PackedScene = preload("res://agent.tscn")

var agent_data: Array[Dictionary] = [
	{"name": "Alice", "personality": "curious", "color": Color(0.3, 0.8, 1.0)},
	{"name": "Bob", "personality": "shy", "color": Color(0.6, 0.4, 0.9)},
	{"name": "Carol", "personality": "social", "color": Color(1.0, 0.5, 0.3)},
	{"name": "Dave", "personality": "wanderer", "color": Color(0.3, 0.9, 0.4)},
	{"name": "Eve", "personality": "lazy", "color": Color(0.9, 0.3, 0.6)},
]

var agents: Array[Node2D] = []

@onready var agent_container: Node2D = $AgentContainer
@onready var ui_panel: VBoxContainer = $UIPanel

func _ready() -> void:
	randomize()
	_spawn_agents()

func _spawn_agents() -> void:
	for data in agent_data:
		var agent: Node2D = AgentScene.instantiate()
		agent.agent_name = data["name"]
		agent.personality = data["personality"]
		agent.agent_color = data["color"]
		agent.position = Vector2(
			randf_range(80, 720),
			randf_range(80, 520)
		)
		agent.interaction_started.connect(_on_agent_interaction)
		agent.state_changed.connect(_on_agent_state_changed)
		agent_container.add_child(agent)
		agents.append(agent)
		ui_panel.register_agent(data["name"], data["personality"])

func _physics_process(_delta: float) -> void:
	for agent in agents:
		for other in agents:
			if agent != other:
				agent.check_nearby(other)

func _on_agent_interaction(agent_name: String, other_name: String) -> void:
	ui_panel.log_interaction(agent_name, other_name)

func _on_agent_state_changed(agent_name: String, state: String) -> void:
	ui_panel.update_agent_state(agent_name, state)

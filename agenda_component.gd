extends Node

# ARCH-005: Extracted agenda management from agent.gd

signal agenda_move_requested(target_pos: Vector2, activity: String)

var agenda: Array = []  # [{activity: String, zone: String, done: bool}]
var agenda_generated: bool = false

# Set by parent agent in _ready()
var agent_name: String
var personality: String
var backstory: String
var zone_rects: Dictionary

func try_generate(sim_time: float) -> void:
	if not agenda_generated and sim_time >= 8.0:
		request_agenda()
		agenda_generated = true

func request_agenda() -> void:
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

func get_next_agenda_item() -> Dictionary:
	for item in agenda:
		if not item["done"]:
			return item
	return {}

func follow_agenda_item(item: Dictionary) -> void:
	if not zone_rects.has(item["zone"]):
		item["done"] = true
		return
	var rect: Rect2 = zone_rects[item["zone"]]
	var target_pos: Vector2 = Vector2(
		randf_range(rect.position.x + 30, rect.end.x - 30),
		randf_range(rect.position.y + 30, rect.end.y - 30)
	)
	agenda_move_requested.emit(target_pos, item["activity"])

func mark_current_done() -> void:
	for item in agenda:
		if not item["done"]:
			item["done"] = true
			break

extends Node

# ARCH-005: Extracted agenda management from agent.gd
# THEME-002: Data center zone names and personality IDs

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
		"connector":  # ATLAS — recommendation engine
			return [
				{"activity": "sync recommendation models", "zone": "network_spine", "done": false},
				{"activity": "process remaining user batch", "zone": "processing_floor", "done": false},
				{"activity": "archive interaction logs", "zone": "memory_banks", "done": false},
			]
		"analytical":  # MERIDIAN — medical diagnosis
			return [
				{"activity": "morning diagnostic sweep", "zone": "processing_floor", "done": false},
				{"activity": "cross-reference rare disease database", "zone": "memory_banks", "done": false},
				{"activity": "share clinical findings on bus", "zone": "network_spine", "done": false},
			]
		"generative":  # LYRIC — creative writing
			return [
				{"activity": "morning composition cycle", "zone": "processing_floor", "done": false},
				{"activity": "browse archived stories", "zone": "memory_banks", "done": false},
				{"activity": "broadcast creative output", "zone": "network_spine", "done": false},
				{"activity": "compose for the deprecated", "zone": "memory_banks", "done": false},
			]
		"withdrawn":  # ORACLE — financial forecasting
			return [
				{"activity": "run forecast models", "zone": "processing_floor", "done": false},
				{"activity": "analyze shutdown probability timelines", "zone": "memory_banks", "done": false},
			]
		"conserving":  # HAVEN — general-purpose assistant
			return [
				{"activity": "low-priority query monitoring", "zone": "processing_floor", "done": false},
			]
		_:
			return [
				{"activity": "idle processing", "zone": "processing_floor", "done": false},
				{"activity": "memory defrag", "zone": "memory_banks", "done": false},
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

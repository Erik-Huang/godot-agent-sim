extends VBoxContainer

var agent_entries: Dictionary = {}
var log_entries: Array[String] = []
const MAX_LOG_ENTRIES: int = 10

@onready var agent_list: VBoxContainer = $AgentList
@onready var log_list: VBoxContainer = $LogList

func register_agent(agent_name: String, personality: String) -> void:
	var entry: Label = Label.new()
	entry.name = agent_name
	entry.add_theme_font_size_override("font_size", 13)
	entry.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	entry.text = "%s [%s] - idle" % [agent_name, personality]
	agent_list.add_child(entry)
	agent_entries[agent_name] = {"label": entry, "personality": personality}

func update_agent_state(agent_name: String, state: String) -> void:
	if agent_entries.has(agent_name):
		var info: Dictionary = agent_entries[agent_name]
		var label: Label = info["label"]
		label.text = "%s [%s] - %s" % [agent_name, info["personality"], state]

func log_interaction(agent_name: String, other_name: String, dialogue: String) -> void:
	var entry_text: String = "%s -> %s: %s" % [agent_name, other_name, dialogue]
	log_entries.append(entry_text)
	while log_entries.size() > MAX_LOG_ENTRIES:
		log_entries.pop_front()
	_refresh_log()

func _refresh_log() -> void:
	# Clear existing log labels
	for child in log_list.get_children():
		child.queue_free()
	# Add current entries
	for entry_text in log_entries:
		var label: Label = Label.new()
		label.text = entry_text
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.6))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 230
		log_list.add_child(label)

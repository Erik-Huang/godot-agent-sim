extends VBoxContainer

var tick_count: int = 0
var agent_entries: Dictionary = {}

@onready var tick_label: Label = $TickLabel
@onready var agent_list: VBoxContainer = $AgentList

func _ready() -> void:
	tick_label.text = "Tick: 0"

func _physics_process(_delta: float) -> void:
	tick_count += 1
	tick_label.text = "Tick: %d" % tick_count

func register_agent(agent_name: String, personality: String) -> void:
	var entry: Label = Label.new()
	entry.name = agent_name
	entry.add_theme_font_size_override("font_size", 12)
	entry.text = "%s [%s]\nState: wandering" % [agent_name, personality]
	agent_list.add_child(entry)
	agent_entries[agent_name] = entry

func update_agent_state(agent_name: String, state: String) -> void:
	if agent_entries.has(agent_name):
		var entry: Label = agent_entries[agent_name]
		var lines: PackedStringArray = entry.text.split("\n")
		if lines.size() > 0:
			entry.text = "%s\nState: %s" % [lines[0], state]

func log_interaction(agent_name: String, other_name: String) -> void:
	update_agent_state(agent_name, "interacting")

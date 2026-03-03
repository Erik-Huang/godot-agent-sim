extends VBoxContainer

# UI-003: Rich per-agent card panel with live state updates

const PANEL_TEXTURE_PATH := "res://assets/ui/theme/nine_path_panel.png"
const BG_TEXTURE_PATH := "res://assets/ui/theme/nine_path_bg.png"
const FONT_PATH := "res://assets/ui/fonts/NormalFont.ttf"

var agent_cards: Dictionary = {}  # agent_name → Dictionary of UI nodes
var agent_refs: Array = []  # CharacterBody2D references for live polling
var pixel_font: Font = null
var panel_texture: Texture2D = null
var bg_texture: Texture2D = null

var log_entries: Array[String] = []
const MAX_LOG_ENTRIES: int = 8
var _log_labels: Array[Label] = []

@onready var agent_list: VBoxContainer = $AgentScroll/AgentList
@onready var log_list: VBoxContainer = $LogList

func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		pixel_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(PANEL_TEXTURE_PATH):
		panel_texture = load(PANEL_TEXTURE_PATH) as Texture2D
	if ResourceLoader.exists(BG_TEXTURE_PATH):
		bg_texture = load(BG_TEXTURE_PATH) as Texture2D
	_setup_panel_background()

func _setup_panel_background() -> void:
	# Apply background style directly on this panel node
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 1.0)
	add_theme_stylebox_override("panel", sb)
	# Style title and headers with pixel font
	var title: Label = get_node_or_null("Title")
	if title and pixel_font:
		title.add_theme_font_override("font", pixel_font)
	var agents_header: Label = get_node_or_null("AgentsHeader")
	if agents_header and pixel_font:
		agents_header.add_theme_font_override("font", pixel_font)
	var log_header: Label = get_node_or_null("LogHeader")
	if log_header and pixel_font:
		log_header.add_theme_font_override("font", pixel_font)

func register_agent(agent: CharacterBody2D) -> void:
	agent_refs.append(agent)
	var card: Dictionary = _create_agent_card(agent.agent_name, agent.personality, agent.agent_color)
	agent_cards[agent.agent_name] = card

func _create_agent_card(agent_name: String, personality_tag: String, agent_color: Color) -> Dictionary:
	# Card container — PanelContainer with texture or flat fallback
	var card := PanelContainer.new()
	card.name = "Card_%s" % agent_name
	if panel_texture:
		var sb := StyleBoxTexture.new()
		sb.texture = panel_texture
		sb.texture_margin_left = 4
		sb.texture_margin_right = 4
		sb.texture_margin_top = 4
		sb.texture_margin_bottom = 4
		card.add_theme_stylebox_override("panel", sb)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.12, 0.15, 0.9)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.3, 0.35, 0.4, 0.5)
		card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Margin inside card
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	# Header row: color dot + name [personality]
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	var color_dot := ColorRect.new()
	color_dot.custom_minimum_size = Vector2(8, 8)
	color_dot.size = Vector2(8, 8)
	color_dot.color = agent_color
	header_row.add_child(color_dot)
	var header_label := Label.new()
	header_label.text = "%s [%s]" % [agent_name, personality_tag]
	_apply_font(header_label, 12)
	header_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	header_row.add_child(header_label)
	vbox.add_child(header_row)

	# State + zone row
	var state_label := Label.new()
	state_label.text = "idle | —"
	_apply_font(state_label, 11)
	_apply_muted_color(state_label)
	vbox.add_child(state_label)

	# Agenda
	var agenda_label := Label.new()
	agenda_label.text = "agenda: —"
	_apply_font(agenda_label, 11)
	_apply_muted_color(agenda_label)
	vbox.add_child(agenda_label)

	# Mood bar row
	var mood_row := HBoxContainer.new()
	mood_row.add_theme_constant_override("separation", 4)
	var mood_text := Label.new()
	mood_text.text = "mood:"
	_apply_font(mood_text, 11)
	_apply_muted_color(mood_text)
	mood_row.add_child(mood_text)
	var mood_bar_bg := ColorRect.new()
	mood_bar_bg.custom_minimum_size = Vector2(60, 6)
	mood_bar_bg.size = Vector2(60, 6)
	mood_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	mood_row.add_child(mood_bar_bg)
	var mood_bar_fill := ColorRect.new()
	mood_bar_fill.custom_minimum_size = Vector2(30, 6)
	mood_bar_fill.size = Vector2(30, 6)
	mood_bar_fill.color = Color(0.5, 0.5, 0.5)
	mood_bar_fill.position = Vector2.ZERO
	mood_bar_bg.add_child(mood_bar_fill)
	mood_row.add_child(Control.new())  # spacer
	vbox.add_child(mood_row)

	# Last memory
	var memory_label := Label.new()
	memory_label.text = "mem: —"
	_apply_font(memory_label, 10)
	memory_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	memory_label.custom_minimum_size.x = 0
	vbox.add_child(memory_label)

	# Last speech
	var speech_label := Label.new()
	speech_label.text = ""
	_apply_font(speech_label, 10)
	speech_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.7))
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_label.custom_minimum_size.x = 0
	vbox.add_child(speech_label)

	margin.add_child(vbox)
	card.add_child(margin)
	agent_list.add_child(card)

	return {
		"state_label": state_label,
		"agenda_label": agenda_label,
		"mood_bar_fill": mood_bar_fill,
		"memory_label": memory_label,
		"speech_label": speech_label,
	}

func _apply_font(label: Label, size: int) -> void:
	if pixel_font:
		label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", size)

func _apply_muted_color(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))

func _process(_delta: float) -> void:
	# Pull live data from all registered agents each frame
	for agent in agent_refs:
		if not is_instance_valid(agent):
			continue
		var aname: String = agent.agent_name
		if not agent_cards.has(aname):
			continue
		var card: Dictionary = agent_cards[aname]

		# State + zone
		var state_text: String = agent.get_state_name()
		var zone_text: String = agent.current_zone if agent.current_zone != "" else "—"
		card["state_label"].text = "%s | %s" % [state_text, zone_text]

		# Agenda — first incomplete item
		var agenda_text: String = "—"
		if agent.agenda.size() > 0:
			var next_item: Dictionary = agent._get_next_agenda_item()
			if not next_item.is_empty():
				agenda_text = next_item.get("activity", "—")
		card["agenda_label"].text = "agenda: %s" % agenda_text

		# Mood — average sentiment across relationships
		var avg_sentiment: float = 0.0
		if MemoryService.relationships.has(aname):
			var rels: Dictionary = MemoryService.relationships[aname]
			if rels.size() > 0:
				var total: float = 0.0
				for other: String in rels:
					total += rels[other].get("sentiment", 0.0)
				avg_sentiment = total / float(rels.size())
		_update_mood_bar(card["mood_bar_fill"], avg_sentiment)

		# Last memory
		var top_mems: Array = MemoryService.get_top_memories(aname, 1)
		if top_mems.size() > 0:
			var snippet: String = top_mems[0].get("text", "")
			if snippet.length() > 40:
				snippet = snippet.substr(0, 37) + "..."
			card["memory_label"].text = "mem: %s" % snippet
		else:
			card["memory_label"].text = "mem: —"

		# Last speech
		if agent.last_speech_text != "":
			var speech_snip: String = agent.last_speech_text
			if speech_snip.length() > 50:
				speech_snip = speech_snip.substr(0, 47) + "..."
			card["speech_label"].text = "\"%s\"" % speech_snip
		else:
			card["speech_label"].text = ""

func _update_mood_bar(bar: ColorRect, sentiment: float) -> void:
	# Width: 0-60px proportional to abs sentiment, minimum 4px
	var width: float = lerpf(4.0, 60.0, absf(sentiment))
	bar.custom_minimum_size.x = width
	bar.size.x = width
	# Color: green (+1) → gray (0) → red (-1)
	var color: Color
	if sentiment >= 0.0:
		color = Color(0.5, 0.5, 0.5).lerp(Color(0.2, 0.8, 0.2), sentiment)
	else:
		color = Color(0.5, 0.5, 0.5).lerp(Color(0.8, 0.2, 0.2), absf(sentiment))
	bar.color = color

# Legacy compatibility — still callable from signals but _process handles updates
func update_agent_state(_agent_name: String, _state: String) -> void:
	pass

func log_interaction(agent_name: String, other_name: String, dialogue: String) -> void:
	var entry_text: String = "%s → %s: %s" % [agent_name, other_name, dialogue]
	log_entries.append(entry_text)
	while log_entries.size() > MAX_LOG_ENTRIES:
		log_entries.pop_front()
	_refresh_log()

func _refresh_log() -> void:
	while _log_labels.size() < log_entries.size():
		var label: Label = Label.new()
		_apply_font(label, 10)
		label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.6))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 230
		log_list.add_child(label)
		_log_labels.append(label)
	for i: int in range(_log_labels.size()):
		if i < log_entries.size():
			_log_labels[i].text = log_entries[i]
			_log_labels[i].visible = true
		else:
			_log_labels[i].visible = false

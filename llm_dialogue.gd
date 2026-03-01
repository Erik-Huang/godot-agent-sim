extends Node

# Cache: key = "AgentA:AgentB" (sorted), value = {"text": String, "time": float}
var dialogue_cache: Dictionary = {}
const CACHE_TTL: float = 60.0

var fallback_templates: Dictionary = {
	"curious": ["What are you doing?", "Tell me more!", "Interesting...", "Ooh, what's that?"],
	"shy": ["Oh... hi.", "I feel crowded...", "Maybe later.", "Um..."],
	"social": ["Hey! Great to see you!", "Love this place!", "Let's hang out!", "You're awesome!"],
	"wanderer": ["Just passing through.", "Always moving.", "The road calls.", "Places to be."],
	"lazy": ["Ugh, more walking.", "Can we stop?", "Five more minutes...", "So tired."],
}

func _get_cache_key(name_a: String, name_b: String) -> String:
	var names: Array = [name_a, name_b]
	names.sort()
	return "%s:%s" % [names[0], names[1]]

func _get_fallback(personality: String) -> String:
	if fallback_templates.has(personality):
		var options: Array = fallback_templates[personality]
		return options[randi() % options.size()]
	return "..."

func request_dialogue(agent: CharacterBody2D, other: CharacterBody2D) -> void:
	var cache_key: String = _get_cache_key(agent.agent_name, other.agent_name)

	# Check cache
	if dialogue_cache.has(cache_key):
		var cached: Dictionary = dialogue_cache[cache_key]
		var elapsed: float = (Time.get_ticks_msec() / 1000.0) - cached["time"]
		if elapsed < CACHE_TTL:
			agent.show_speech(cached["text"])
			agent.interaction_started.emit(agent.agent_name, other.agent_name, cached["text"])
			return

	# Try API call
	var api_key: String = OS.get_environment("OPENAI_API_KEY")
	if api_key == "":
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		return

	# Create HTTP request
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	var prompt_text: String = "You are %s, a %s person. You just met %s, who is %s. Write ONE short sentence (max 12 words) you'd say to them. Reply with ONLY the sentence." % [
		agent.agent_name, agent.personality, other.agent_name, other.personality
	]

	var body: Dictionary = {
		"model": "gpt-4o-mini",
		"messages": [{"role": "user", "content": prompt_text}],
		"max_tokens": 50,
		"temperature": 0.8,
	}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])

	var json_body: String = JSON.stringify(body)

	# Connect callback with agent references
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			_on_request_completed(result, response_code, body_bytes, agent, other, cache_key)
			http.queue_free()
	)

	var err: int = http.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		http.queue_free()

func _on_request_completed(result: int, response_code: int, body_bytes: PackedByteArray, agent: CharacterBody2D, other: CharacterBody2D, cache_key: String) -> void:
	if not is_instance_valid(agent):
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		return

	var json: JSON = JSON.new()
	var parse_err: int = json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		return

	var data: Dictionary = json.data
	if data.has("choices") and data["choices"].size() > 0:
		var text: String = data["choices"][0]["message"]["content"].strip_edges()
		# Cache it
		dialogue_cache[cache_key] = {"text": text, "time": Time.get_ticks_msec() / 1000.0}
		agent.show_speech(text)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, text)
	else:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)

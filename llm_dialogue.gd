extends Node

# Cache: key = "AgentA:AgentB" (sorted), value = {"text": String, "time": float}
var dialogue_cache: Dictionary = {}
const CACHE_TTL: float = 60.0

# AUDIT-007: LLM request queue for rate limiting
var _active_requests: int = 0
var _request_queue: Array = []  # Array of Callable
const MAX_CONCURRENT: int = 3

# ARCH-001: Fallback templates now sourced from ContentData.PERSONALITY_LINES

func _get_cache_key(name_a: String, name_b: String) -> String:
	var names: Array = [name_a, name_b]
	names.sort()
	return "%s:%s" % [names[0], names[1]]

func _get_fallback(personality: String) -> String:
	if ContentData.PERSONALITY_LINES.has(personality):
		var options: Array = ContentData.PERSONALITY_LINES[personality]
		return options[randi() % options.size()]
	return "..."

# AUDIT-007: Queue-based rate limiting for LLM requests
func _dispatch_or_queue(callable: Callable) -> void:
	if _active_requests < MAX_CONCURRENT:
		_active_requests += 1
		callable.call()
	else:
		_request_queue.append(callable)

func _dispatch_next() -> void:
	_active_requests -= 1
	if _request_queue.size() > 0 and _active_requests < MAX_CONCURRENT:
		var next: Callable = _request_queue.pop_front()
		_active_requests += 1
		next.call()

# MEM-002: Importance scoring
# Returns an importance rating 1-10 for an observation text.
# Uses heuristics if no API key; async LLM call otherwise (fire-and-forget update).
func rate_importance(agent_name: String, text: String) -> int:
	var api_key: String = OS.get_environment("OPENAI_API_KEY")
	if api_key == "":
		return _heuristic_importance(text)

	# Fire async LLM call to rate importance; return heuristic for now
	var initial: int = _heuristic_importance(text)
	_async_rate_importance(agent_name, text, api_key)
	return initial

func _heuristic_importance(text: String) -> int:
	var lower: String = text.to_lower()
	# Check for agent names (interaction-related)
	var agent_names: Array = ["alice", "bob", "carol", "dave", "eve"]
	for aname in agent_names:
		if lower.find(aname.to_lower()) != -1:
			return 7
	if lower.find("interact") != -1 or lower.find("talked") != -1 or lower.find("said") != -1:
		return 7
	if lower.find("park") != -1 or lower.find("cafe") != -1 or lower.find("town") != -1 or lower.find("zone") != -1:
		return 3
	return 4

func _async_rate_importance(agent_name: String, text: String, api_key: String) -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	var prompt_text: String = "Rate 1-10 how significant this event is for %s: '%s'. Reply with only a number." % [agent_name, text]

	var body: Dictionary = {
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": "You are roleplaying a character in a small-town life simulation. Stay in character. Be concise."},
			{"role": "user", "content": prompt_text}
		],
		"max_tokens": 5,
		"temperature": 0.0,
	}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])

	var json_body: String = JSON.stringify(body)

	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				var json := JSON.new()
				if json.parse(body_bytes.get_string_from_utf8()) == OK:
					var data: Dictionary = json.data
					if data.has("choices") and data["choices"].size() > 0:
						var rating_text: String = data["choices"][0]["message"]["content"].strip_edges()
						var rating: int = clampi(rating_text.to_int(), 1, 10)
						# Update the observation in MemoryService if it exists
						if MemoryService and MemoryService.observations.has(agent_name):
							for obs in MemoryService.observations[agent_name]:
								if obs["text"] == text:
									obs["importance"] = rating
									break
			http.queue_free()
	)

	var err: int = http.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()

# MEM-003: Format top memories as a text block for prompt injection
func _format_memories_block(agent_name: String, n: int = 3) -> String:
	if not MemoryService:
		return ""
	var memories: Array = MemoryService.get_top_memories(agent_name, n)
	if memories.size() == 0:
		return ""
	var lines: String = "Recent memories:\n"
	for mem in memories:
		lines += "- %s\n" % mem["text"]
	return lines

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

	# AUDIT-007: Queue the HTTP dispatch for rate limiting
	_dispatch_or_queue(func() -> void:
		_do_dialogue_request(agent, other, cache_key, api_key)
	)

func _do_dialogue_request(agent: CharacterBody2D, other: CharacterBody2D, cache_key: String, api_key: String) -> void:
	# Create HTTP request
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	# MEM-003 + INT-002: Richer prompt with memory context
	var memories_block: String = _format_memories_block(agent.agent_name, 3)
	# AUDIT-009: Default to "between areas" when zone string is empty
	var zone_name: String = agent.current_zone if agent.current_zone != "" else "between areas"
	var prompt_text: String = "You are %s, a %s person currently in the %s area.\n%sYou just encountered %s, who is %s.\nWrite ONE sentence (max 12 words) you would say to them. Reply with ONLY the sentence." % [
		agent.agent_name, agent.personality, zone_name, memories_block, other.agent_name, other.personality
	]

	var body: Dictionary = {
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": "You are roleplaying a character in a small-town life simulation. Stay in character. Be concise."},
			{"role": "user", "content": prompt_text}
		],
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
			# AUDIT-007: Dispatch next queued request
			_dispatch_next()
			http.queue_free()
	)

	var err: int = http.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		_dispatch_next()
		http.queue_free()

func _on_request_completed(result: int, response_code: int, body_bytes: PackedByteArray, agent: CharacterBody2D, other: CharacterBody2D, cache_key: String) -> void:
	if not is_instance_valid(agent):
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		# INT-003: Fallback observation on HTTP failure
		if MemoryService and is_instance_valid(other):
			var zone_name: String = agent.current_zone if agent.current_zone != "" else "somewhere"
			MemoryService.add_observation(agent.agent_name, "I tried talking to %s near the %s but couldn't find words" % [other.agent_name, zone_name], 4, ["social"])
		return

	var json: JSON = JSON.new()
	var parse_err: int = json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		# INT-003: Fallback observation on parse failure
		if MemoryService and is_instance_valid(other):
			var zone_name: String = agent.current_zone if agent.current_zone != "" else "somewhere"
			MemoryService.add_observation(agent.agent_name, "I tried talking to %s near the %s but couldn't find words" % [other.agent_name, zone_name], 4, ["social"])
		return

	var data: Dictionary = json.data
	if data.has("choices") and data["choices"].size() > 0:
		var text: String = data["choices"][0]["message"]["content"].strip_edges()
		# Cache it
		dialogue_cache[cache_key] = {"text": text, "time": Time.get_ticks_msec() / 1000.0}
		agent.show_speech(text)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, text)
		# AUDIT-003: Partner response — show fallback immediately, replace with LLM if available
		if is_instance_valid(other):
			_generate_partner_response(agent, other, text)
		# INT-003: Information propagation — store interaction memories
		if MemoryService and is_instance_valid(other):
			var zone_name: String = agent.current_zone if agent.current_zone != "" else "somewhere"
			var obs_text: String = "I talked to %s near the %s. They said: '%s'" % [other.agent_name, zone_name, text]
			MemoryService.add_observation(agent.agent_name, obs_text, 6, ["social", "interaction"])
			MemoryService.add_observation(other.agent_name, "I was approached by %s in the %s" % [agent.agent_name, zone_name], 5, ["social"])
	else:
		var fallback: String = _get_fallback(agent.personality)
		agent.show_speech(fallback)
		agent.interaction_started.emit(agent.agent_name, other.agent_name, fallback)
		# INT-003: Fallback observation when LLM returns no choices
		if MemoryService and is_instance_valid(other):
			var zone_name: String = agent.current_zone if agent.current_zone != "" else "somewhere"
			MemoryService.add_observation(agent.agent_name, "I tried talking to %s near the %s but couldn't find words" % [other.agent_name, zone_name], 4, ["social"])


# AUDIT-003: Generate a response for the interaction partner
func _generate_partner_response(agent: CharacterBody2D, other: CharacterBody2D, initiator_text: String) -> void:
	if not is_instance_valid(other):
		return
	# Show fallback reaction immediately after a 1.5s delay
	var fallback: String = _get_fallback(other.personality)
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(1.5).timeout
	if not is_instance_valid(other):
		return
	other.show_speech(fallback)

	# If API key present, make a short LLM call to replace fallback
	var api_key: String = OS.get_environment("OPENAI_API_KEY")
	if api_key == "":
		return

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	var memories_block: String = _format_memories_block(other.agent_name, 2)
	var prompt_text: String = "You are %s, a %s person.\n%s%s just said to you: \"%s\"\nWrite a SHORT reply (max 8 words). Reply with ONLY the sentence." % [
		other.agent_name, other.personality, memories_block, agent.agent_name, initiator_text
	]

	var body: Dictionary = {
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": "You are roleplaying a character in a small-town life simulation. Stay in character. Be concise."},
			{"role": "user", "content": prompt_text}
		],
		"max_tokens": 30,
		"temperature": 0.8,
	}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])

	var json_body: String = JSON.stringify(body)

	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				var json := JSON.new()
				if json.parse(body_bytes.get_string_from_utf8()) == OK:
					var data: Dictionary = json.data
					if data.has("choices") and data["choices"].size() > 0:
						var reply_text: String = data["choices"][0]["message"]["content"].strip_edges()
						if is_instance_valid(other):
							other.show_speech(reply_text)
			http.queue_free()
	)

	var err: int = http.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()

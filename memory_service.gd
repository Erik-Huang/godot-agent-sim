extends Node

# Per-agent memory storage
# observations[agent_name] = Array of {text: String, timestamp_sec: float, importance: int, tags: Array[String]}
var observations: Dictionary = {}

# MEM-004: Social relationship tracking
# Structure: {agent_name: {other_name: {count: int, last_seen: float, sentiment: float}}}
var relationships: Dictionary = {}

# MEM-005: Reflection synthesis — tracks observations since last reflection per agent
var reflection_counters: Dictionary = {}
const REFLECTION_THRESHOLD: int = 15
signal on_reflection_ready(agent_name: String)

const MAX_OBSERVATIONS_PER_AGENT: int = 200
const MEMORY_DIR: String = "user://memory/"

func _ready() -> void:
	load_memories()
	# AUDIT-005: Auto-save timer to prevent memory loss on editor stop / crash
	var auto_save_timer := Timer.new()
	auto_save_timer.name = "AutoSaveTimer"
	auto_save_timer.wait_time = 60.0
	auto_save_timer.autostart = true
	add_child(auto_save_timer)
	auto_save_timer.timeout.connect(save_memories)

# AUDIT-005: Save on tree exit (editor stop, scene change, etc.)
func _exit_tree() -> void:
	save_memories()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_memories()

func add_observation(agent_name: String, text: String, importance: int = 5, tags: Array = []) -> void:
	if not observations.has(agent_name):
		observations[agent_name] = []

	var entry: Dictionary = {
		"text": text,
		"timestamp_sec": Time.get_unix_time_from_system(),
		"importance": clampi(importance, 1, 10),
		"tags": tags,
	}
	observations[agent_name].append(entry)

	# MEM-005: Track observations for reflection synthesis
	if not reflection_counters.has(agent_name):
		reflection_counters[agent_name] = 0
	reflection_counters[agent_name] += 1
	if reflection_counters[agent_name] >= REFLECTION_THRESHOLD:
		on_reflection_ready.emit(agent_name)
		reflection_counters[agent_name] = 0

	# Evict lowest-score entry if over cap
	if observations[agent_name].size() > MAX_OBSERVATIONS_PER_AGENT:
		_evict_lowest(agent_name)

func get_top_memories(agent_name: String, n: int = 5) -> Array:
	if not observations.has(agent_name):
		return []

	var now_sec: float = Time.get_unix_time_from_system()
	var scored: Array = []

	for obs in observations[agent_name]:
		var age_sec: float = now_sec - obs["timestamp_sec"]
		var score: float = 0.3 * exp(-age_sec / 3600.0) + 0.7 * obs["importance"]
		scored.append({"obs": obs, "score": score})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])

	var result: Array = []
	for i in range(mini(n, scored.size())):
		result.append(scored[i]["obs"])
	return result

# MEM-004: Update relationship between two agents
func update_relationship(agent_name: String, other_name: String, sentiment_delta: float) -> void:
	if not relationships.has(agent_name):
		relationships[agent_name] = {}
	if not relationships[agent_name].has(other_name):
		relationships[agent_name][other_name] = {"count": 0, "last_seen": 0.0, "sentiment": 0.0}
	var rel: Dictionary = relationships[agent_name][other_name]
	rel["count"] += 1
	rel["last_seen"] = Time.get_unix_time_from_system()
	rel["sentiment"] = clampf(rel["sentiment"] + sentiment_delta, -1.0, 1.0)

# MEM-004: Get sentiment toward another agent (0.0 if unknown)
func get_sentiment(agent_name: String, other_name: String) -> float:
	if relationships.has(agent_name) and relationships[agent_name].has(other_name):
		return relationships[agent_name][other_name]["sentiment"]
	return 0.0

# MEM-005: Get most recent N observations for reflection context
func get_observations_for_reflection(agent_name: String, n: int = 10) -> Array:
	if not observations.has(agent_name):
		return []
	var obs_list: Array = observations[agent_name]
	var start_idx: int = maxi(0, obs_list.size() - n)
	return obs_list.slice(start_idx)

func save_memories() -> void:
	DirAccess.make_dir_recursive_absolute(MEMORY_DIR)
	for agent_name in observations:
		var path: String = MEMORY_DIR + agent_name + ".json"
		var save_data: Dictionary = {"observations": observations[agent_name]}
		if relationships.has(agent_name):
			save_data["relationships"] = relationships[agent_name]
		if reflection_counters.has(agent_name):
			save_data["reflection_counter"] = reflection_counters[agent_name]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data, "\t"))
			file.close()

func load_memories() -> void:
	if not DirAccess.dir_exists_absolute(MEMORY_DIR):
		return
	var dir := DirAccess.open(MEMORY_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var agent_name: String = file_name.get_basename()
			var path: String = MEMORY_DIR + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				var err: int = json.parse(file.get_as_text())
				if err == OK:
					if json.data is Array:
						# Legacy format: bare array of observations
						observations[agent_name] = json.data
					elif json.data is Dictionary:
						# MEM-004: New format with relationships
						observations[agent_name] = json.data.get("observations", [])
						if json.data.has("relationships"):
							relationships[agent_name] = json.data["relationships"]
						if json.data.has("reflection_counter"):
							reflection_counters[agent_name] = json.data["reflection_counter"]
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

func _evict_lowest(agent_name: String) -> void:
	var now_sec: float = Time.get_unix_time_from_system()
	var lowest_score: float = INF
	var lowest_idx: int = 0

	for i in range(observations[agent_name].size()):
		var obs: Dictionary = observations[agent_name][i]
		var age_sec: float = now_sec - obs["timestamp_sec"]
		var score: float = 0.3 * exp(-age_sec / 3600.0) + 0.7 * obs["importance"]
		if score < lowest_score:
			lowest_score = score
			lowest_idx = i

	observations[agent_name].remove_at(lowest_idx)

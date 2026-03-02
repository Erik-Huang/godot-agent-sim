extends Node

# Per-agent memory storage
# observations[agent_name] = Array of {text: String, timestamp_sec: float, importance: int, tags: Array[String]}
var observations: Dictionary = {}

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
		var score: float = 0.3 * (1.0 / maxf(age_sec, 1.0)) + 0.7 * obs["importance"]
		scored.append({"obs": obs, "score": score})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])

	var result: Array = []
	for i in range(mini(n, scored.size())):
		result.append(scored[i]["obs"])
	return result

func save_memories() -> void:
	DirAccess.make_dir_recursive_absolute(MEMORY_DIR)
	for agent_name in observations:
		var path: String = MEMORY_DIR + agent_name + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(observations[agent_name], "\t"))
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
				if err == OK and json.data is Array:
					observations[agent_name] = json.data
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
		var score: float = 0.3 * (1.0 / maxf(age_sec, 1.0)) + 0.7 * obs["importance"]
		if score < lowest_score:
			lowest_score = score
			lowest_idx = i

	observations[agent_name].remove_at(lowest_idx)

extends Node

# ARCH-001: Templates now sourced from ContentData.PERSONALITY_LINES

func get_thought(personality: String) -> String:
	if ContentData.PERSONALITY_LINES.has(personality):
		var options: Array = ContentData.PERSONALITY_LINES[personality]
		return options[randi() % options.size()]
	return "..."

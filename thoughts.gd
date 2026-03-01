extends Node

var templates: Dictionary = {
	"curious": ["What are you doing?", "Tell me more!", "Interesting...", "Ooh, what's that?", "I wonder why..."],
	"shy": ["Oh... hi.", "I feel crowded...", "Maybe later.", "Um...", "I'll just be over here."],
	"social": ["Hey! Great to meet you!", "Love this place!", "Let us hang!", "Party time!", "You're awesome!"],
	"wanderer": ["Just passing through.", "Always moving.", "The road calls.", "Places to be.", "Never stop."],
	"lazy": ["Ugh, more walking.", "Can we stop?", "Five more minutes...", "So tired.", "Wake me later."],
}

func get_thought(personality: String) -> String:
	if templates.has(personality):
		var options: Array = templates[personality]
		return options[randi() % options.size()]
	return "..."

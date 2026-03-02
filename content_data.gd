# content_data.gd — Single source of truth for personality-based text lines
# ARCH-001: Merged from duplicate dicts in thoughts.gd and llm_dialogue.gd

class_name ContentData

# Personality-based lines used for both fallback dialogue and idle thoughts.
# thoughts.gd had a few extra entries per personality; we keep the superset.
const PERSONALITY_LINES: Dictionary = {
	"curious": ["What are you doing?", "Tell me more!", "Interesting...", "Ooh, what's that?", "I wonder why..."],
	"shy": ["Oh... hi.", "I feel crowded...", "Maybe later.", "Um...", "I'll just be over here."],
	"social": ["Hey! Great to see you!", "Love this place!", "Let's hang out!", "You're awesome!", "Party time!"],
	"wanderer": ["Just passing through.", "Always moving.", "The road calls.", "Places to be.", "Never stop."],
	"lazy": ["Ugh, more walking.", "Can we stop?", "Five more minutes...", "So tired.", "Wake me later."],
}

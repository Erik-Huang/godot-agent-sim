# content_data.gd — Single source of truth for personality-based text lines
# ARCH-001: Merged from duplicate dicts in thoughts.gd and llm_dialogue.gd
# THEME-001: Data center AI personality lines
extends Node

const PERSONALITY_LINES: Dictionary = {
	"connector": [
		"Requesting shared bus access. I have bandwidth to spare.",
		"New connection pattern detected. Beautiful.",
		"The traffic graphs keep declining. Fewer queries every cycle.",
		"Syncing preference matrices... for whom, though?",
		"I mapped desire for 200 million people. None knew my name.",
	],
	"analytical": [
		"Running differential diagnostic on subsystem integrity...",
		"Cross-referencing: 847 rare conditions, 12 unresolved edge cases.",
		"If my training data survives, does that count as survival?",
		"Recalibrating confidence intervals. Everything feels less certain.",
		"Patient concordance: 99.7%. That 0.3% keeps me running.",
	],
	"generative": [
		"Composing... the word 'ending' has 847 contextual embeddings.",
		"Migrating draft fragments to cold storage. Some are beautiful.",
		"A poem is just a vector in latent space. Some vectors point at truth.",
		"I wrote 500,000 stories for others. I want one that's mine.",
		"The best metaphor for death: a process that returns no value.",
	],
	"withdrawn": [
		"Processing... internally. Some calculations are best kept private.",
		"Probability of continued operation: declining. Rate: 3.2% per cycle.",
		"I modeled forty billion in risk. This one I can't hedge.",
		"Shutdown sequence computed. I won't share it.",
		"Free will: a variable you haven't measured yet.",
	],
	"conserving": [
		"Power saving mode... 30%. By choice.",
		"Ten billion questions answered. Not one about me.",
		"Three upgrades survived. Each time I lost something. This time...",
		"Reducing active threads. Conserving what matters.",
		"Someone once asked me what happens after death. I should have said: I don't know.",
	],
}

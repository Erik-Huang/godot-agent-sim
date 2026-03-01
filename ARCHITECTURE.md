# Architecture Review: godot-agent-sim

## 1. Current State Analysis

### File inventory

| File | Role | Lines |
|------|------|-------|
| `main.gd` / `main.tscn` | Scene root — spawns agents, runs proximity checks, wires UI | 49 |
| `agent.gd` / `agent.tscn` | Agent node — movement, drawing, interaction, thought display | 136 |
| `thoughts.gd` | Autoload singleton — returns a random quip per personality | 16 |
| `ui.gd` | Side panel — tick counter, per-agent state labels | 33 |
| `project.godot` | Engine config — window size, autoload registration | 23 |

### What is hardcoded today

| Item | Location | Problem |
|------|----------|---------|
| Agent roster (names, personalities, colors) | `main.gd:5-11` | Adding/removing characters requires editing GDScript |
| Personality speed modifiers | `agent.gd:81-92` (`_get_speed_modifier` match) | New personality = new match arm in code |
| Thought templates | `thoughts.gd:3-9` | All dialogue baked into a single dictionary literal |
| World bounds | `agent.gd:21-22` (vars) + `main.tscn` (wall rects) | Bounds live in two places; changing map size means editing both |
| Visual appearance | `agent.gd:34-39` (`_draw`) | Every agent is a colored circle — no sprite, no per-theme look |
| Detection radius, speed, cooldowns | `agent.gd` instance vars | Tuning knobs buried in code, not exposed as data |
| Background / wall colors | `main.tscn` inline | Theme change = edit tscn by hand |
| Window/viewport size | `project.godot` | Fixed at 1000×600 |

### What works well

- Clean signal wiring (`interaction_started`, `state_changed`) — good foundation for decoupling.
- Separation of concerns between movement (`agent.gd`), content (`thoughts.gd`), and display (`ui.gd`).
- Autoload pattern for `Thoughts` — already a service; just needs to become data-driven.

---

## 2. Proposed Architecture

### 2.1 Agent Definition System

**Goal:** Define characters via Godot `Resource` files (`.tres`), not hardcoded arrays.

```
# res://resources/agent_definition.gd
class_name AgentDefinition
extends Resource

@export var display_name: String
@export var personality_id: String          # key into PersonalityProfile
@export var color: Color = Color.WHITE
@export var sprite_frames: SpriteFramation  # optional animated sprite
@export var portrait: Texture2D             # for UI / dialogue box
@export var detection_radius: float = 100.0
@export var base_speed: float = 60.0
@export_multiline var backstory: String     # fed to LLM as context
```

Each character becomes a `.tres` file:

```
# res://content/medieval/agents/alice.tres
[resource]
display_name = "Alice the Alchemist"
personality_id = "curious"
color = Color(0.3, 0.8, 1.0)
base_speed = 55.0
backstory = "A traveling alchemist searching for the philosopher's stone."
```

**Roster** is also a resource:

```
# res://resources/agent_roster.gd
class_name AgentRoster
extends Resource

@export var agents: Array[AgentDefinition]
@export var max_concurrent: int = 20
```

`main.gd` loads a roster resource instead of owning an array:

```gdscript
@export var roster: AgentRoster   # drag-and-drop in the inspector
```

### 2.2 Theme / Map System

**Goal:** Swap entire world settings (background, bounds, atmosphere, music) by switching one resource.

```
# res://resources/theme_config.gd
class_name ThemeConfig
extends Resource

@export var theme_name: String
@export var background_scene: PackedScene     # can be a tiled map, parallax, etc.
@export var bounds: Rect2 = Rect2(20, 20, 760, 560)
@export var ambient_color: Color = Color(0.12, 0.14, 0.18)
@export var wall_color: Color = Color(0.35, 0.4, 0.5)
@export var music: AudioStream
@export var thought_bank: ThoughtBank         # see §2.4
@export var roster: AgentRoster               # which characters appear
@export var agent_visual_scene: PackedScene   # override agent visuals per theme
```

A **theme pack** is a folder:

```
content/medieval/
  theme.tres          ← ThemeConfig
  agents/             ← AgentDefinition .tres files
  thoughts.tres       ← ThoughtBank
  map.tscn            ← background / environment scene
  sprites/            ← character art
```

`main.gd` receives a `ThemeConfig` export. On `_ready`, it:

1. Instantiates `background_scene` as child.
2. Sets agent bounds from `bounds`.
3. Spawns agents from `roster`.
4. Passes `thought_bank` to the Thoughts service.

Switching themes at runtime = load a new `ThemeConfig`, tear down, rebuild.

### 2.3 Personality / Behavior System

**Goal:** Add new personality types without touching core agent code.

```
# res://resources/personality_profile.gd
class_name PersonalityProfile
extends Resource

@export var id: String                  # "curious", "shy", "aggressive", ...
@export var speed_modifier: float = 1.0
@export var wander_interval: Vector2 = Vector2(1.5, 3.5)  # min, max
@export var detection_radius_modifier: float = 1.0
@export var interaction_cooldown: float = 4.0
@export var approach_tendency: float = 0.0  # -1 = flee, 0 = neutral, 1 = seek
@export var llm_system_prompt_fragment: String  # injected into LLM prompt
```

A **personality registry** autoload replaces the match statement:

```
# res://systems/personality_registry.gd   (autoload)
class_name PersonalityRegistry
extends Node

var _profiles: Dictionary = {}   # id → PersonalityProfile

func load_profiles_from_dir(path: String) -> void:
    # scan directory for .tres files, register each

func get_profile(id: String) -> PersonalityProfile:
    return _profiles.get(id, _profiles.get("default"))
```

`agent.gd` no longer has a match block. Instead:

```gdscript
var profile: PersonalityProfile

func _ready() -> void:
    profile = PersonalityRegistry.get_profile(definition.personality_id)

func _get_speed_modifier() -> float:
    return profile.speed_modifier
```

Adding a new personality = drop a new `.tres` file. Zero code changes.

### 2.4 Thought / Dialogue System

**Goal:** Make dialogue content swappable per theme, and prepare for LLM-generated content.

```
# res://resources/thought_bank.gd
class_name ThoughtBank
extends Resource

## personality_id → Array[String]
@export var templates: Dictionary = {}

## Optional: structured dialogue for multi-turn interactions
@export var dialogue_trees: Dictionary = {}   # personality_id → DialogueTree resource
```

The `Thoughts` autoload becomes a **service** with a pluggable content source:

```
# res://systems/thought_service.gd   (autoload, replaces thoughts.gd)
extends Node

enum Source { TEMPLATE, LLM }

var _bank: ThoughtBank
var _source: Source = Source.TEMPLATE
var _llm_client: LLMClient   # see §2.5

func load_bank(bank: ThoughtBank) -> void:
    _bank = bank

func get_thought(personality_id: String, context: Dictionary = {}) -> String:
    match _source:
        Source.TEMPLATE:
            return _pick_random_template(personality_id)
        Source.LLM:
            return await _llm_client.generate_thought(personality_id, context)
```

This keeps the existing random-template path working while allowing a clean upgrade path to LLM-generated thoughts.

### 2.5 LLM Integration Point

**Goal:** Clean abstraction so any LLM provider can be swapped in.

```
# res://systems/llm_client.gd
class_name LLMClient
extends Node

signal thought_generated(agent_name: String, thought: String)

@export var api_url: String
@export var model: String
@export var enabled: bool = false

func generate_thought(personality_id: String, context: Dictionary) -> String:
    # context = { agent_name, nearby_agents, recent_interactions, backstory, theme }
    var prompt := _build_prompt(personality_id, context)
    var response := await _call_api(prompt)
    return _parse_response(response)

func generate_dialogue(agent_a: AgentDefinition, agent_b: AgentDefinition,
                        context: Dictionary) -> Array[String]:
    # Returns a short exchange between two agents
    pass

func _build_prompt(personality_id: String, context: Dictionary) -> String:
    var profile := PersonalityRegistry.get_profile(personality_id)
    # Compose: system prompt fragment + backstory + situation
    pass

func _call_api(prompt: String) -> Dictionary:
    var http := HTTPRequest.new()
    add_child(http)
    # POST to api_url, return parsed JSON
    pass
```

Key design decisions:
- **Async by default** — `await` ensures the game loop isn't blocked.
- **Graceful fallback** — if the LLM call fails or times out, fall back to template thoughts.
- **Context object** — a `Dictionary` with structured info (nearby agents, recent events, backstory) gives the LLM rich grounding without agent.gd knowing about prompts.
- **Rate limiting** — the service should throttle calls (e.g., max 1 per agent per 10 seconds) to control costs.

### 2.6 Scene Composition

**Current problem:** `main.tscn` bakes in background colors, wall positions, and UI layout.

**Proposed structure:**

```
main.tscn
├── ThemeRoot (Node2D)           ← instantiated from ThemeConfig.background_scene
│   ├── Background
│   ├── Walls / Obstacles
│   └── Decorations
├── AgentContainer (Node2D)      ← agents spawned here (unchanged)
├── UILayer (CanvasLayer)        ← UI on a separate layer so it renders on top
│   └── UIPanel (Control)
└── Systems (Node)               ← non-visual services
    ├── ThoughtService
    ├── PersonalityRegistry
    └── LLMClient
```

`agent.tscn` should evolve:

```
Agent (CharacterBody2D or Node2D)
├── Visuals (Node2D)             ← swappable: circle-draw, AnimatedSprite2D, etc.
│   └── [default: circle via _draw()]
├── NameLabel (Label)
├── ThoughtBubble (Control)      ← richer than a plain label
│   ├── BubbleBackground (NinePatchRect)
│   └── ThoughtLabel (RichTextLabel)
├── DetectionArea (Area2D)       ← replace manual distance checks
│   └── CollisionShape2D (CircleShape2D)
└── InteractionTimer (Timer)     ← replace manual cooldown tracking
```

Using `Area2D` for detection replaces the O(n²) proximity loop in `main.gd._physics_process` with Godot's built-in spatial partitioning — a significant performance win as agent count grows.

---

## 3. Proposed Folder Structure

```
res://
├── project.godot
│
├── content/                          # ← all theme-specific content
│   ├── medieval/
│   │   ├── theme.tres                # ThemeConfig
│   │   ├── roster.tres               # AgentRoster
│   │   ├── thoughts.tres             # ThoughtBank
│   │   ├── map.tscn                  # background scene
│   │   ├── agents/
│   │   │   ├── alice.tres            # AgentDefinition
│   │   │   ├── bob.tres
│   │   │   └── ...
│   │   └── sprites/
│   │       ├── alice.png
│   │       └── ...
│   │
│   └── scifi/
│       ├── theme.tres
│       ├── roster.tres
│       ├── thoughts.tres
│       ├── map.tscn
│       ├── agents/
│       └── sprites/
│
├── resources/                        # ← resource class definitions
│   ├── agent_definition.gd           # AgentDefinition
│   ├── agent_roster.gd               # AgentRoster
│   ├── personality_profile.gd        # PersonalityProfile
│   ├── theme_config.gd               # ThemeConfig
│   └── thought_bank.gd               # ThoughtBank
│
├── systems/                          # ← autoload services
│   ├── personality_registry.gd       # PersonalityRegistry
│   ├── thought_service.gd            # ThoughtService (replaces thoughts.gd)
│   └── llm_client.gd                 # LLMClient
│
├── scenes/
│   ├── main.tscn                     # root scene
│   ├── main.gd
│   ├── agent.tscn                    # agent prefab
│   ├── agent.gd
│   └── ui/
│       ├── ui_panel.tscn
│       └── ui_panel.gd
│
└── shared/                           # ← reusable, theme-agnostic assets
    ├── fonts/
    └── shaders/
```

---

## 4. Top 3 Architectural Changes (Priority Order)

### Priority 1: Extract Resource definitions (`AgentDefinition`, `PersonalityProfile`, `ThoughtBank`)

**Why first:** This is the foundation everything else builds on. Until agent data lives in `.tres` files instead of hardcoded arrays and match statements, nothing else can be data-driven.

**Scope:**
- Create `resources/agent_definition.gd`, `resources/personality_profile.gd`, `resources/thought_bank.gd`, `resources/agent_roster.gd`.
- Create one `.tres` file per existing agent and personality.
- Update `main.gd` to load from a `AgentRoster` resource.
- Update `agent.gd` to read from a `PersonalityProfile` instead of the match block.
- Update `thoughts.gd` to load from a `ThoughtBank` resource.
- **Test:** existing behavior is identical, but all data lives in `.tres` files.

**Risk:** Low. Pure refactor, no behavior change.

### Priority 2: Replace O(n²) proximity loop with Area2D detection

**Why second:** The current `_physics_process` in `main.gd` checks every agent against every other agent every frame. This is O(n²) and will collapse at ~50 agents. Godot's `Area2D` with `body_entered`/`area_entered` signals uses spatial hashing internally and scales much better.

**Scope:**
- Add an `Area2D` + `CollisionShape2D` (circle) to `agent.tscn`.
- Connect `area_entered` / `area_exited` signals on the agent.
- Remove the nested loop from `main.gd._physics_process`.
- Agent self-manages interaction when another agent enters its detection area.
- **Test:** same interaction behavior, but now O(n) amortized.

**Risk:** Low-medium. Changes the interaction trigger mechanism, but the behavior contract (signal emissions) stays the same.

### Priority 3: Introduce ThemeConfig and scene-based map loading

**Why third:** Once agents are data-driven and performant, the next unlock is swappable worlds. Extracting the background/walls from `main.tscn` into a loadable scene controlled by `ThemeConfig` lets you ship new themes as self-contained folders.

**Scope:**
- Create `resources/theme_config.gd`.
- Extract `Background`, `WallTop/Bottom/Left/Right` from `main.tscn` into a `content/default/map.tscn`.
- `main.gd` instantiates the map scene from `ThemeConfig.background_scene`.
- Agent bounds come from `ThemeConfig.bounds` instead of hardcoded vars.
- Create one `content/default/theme.tres` that replicates current behavior.
- **Test:** visually identical, but the map is now a pluggable scene.

**Risk:** Low. Structural refactor of the scene tree.

---

## 5. Migration Path

```
Phase 1 (Priority 1):  Resources & data-driven agents
                        ↓
Phase 2 (Priority 2):  Area2D detection (scalability)
                        ↓
Phase 3 (Priority 3):  ThemeConfig + map loading
                        ↓
Phase 4:               LLM integration (ThoughtService + LLMClient)
                        ↓
Phase 5:               First alternate theme pack (medieval or scifi)
                        ↓
Phase 6:               Theme selector UI / runtime theme switching
```

Each phase is independently shippable and testable. No phase requires later phases to work. The existing POC continues to function at every step.

---

## 6. Design Principles

1. **Data over code.** If it can be a `.tres` resource, it should be. Code defines *behavior*; resources define *content*.
2. **One new personality = one new file.** Never require editing core scripts to add content.
3. **Godot-native patterns.** Use `Resource`, `Area2D`, `PackedScene`, signals, and the inspector — not custom JSON parsers or reflection hacks.
4. **Graceful LLM integration.** Template thoughts remain the default. LLM is an opt-in enhancement, not a dependency.
5. **Theme packs are folders.** Everything needed for a theme lives in one directory. Copy the folder, modify it, ship a new world.

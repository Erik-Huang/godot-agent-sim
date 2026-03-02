# godot-agent-sim — Improvement TODO

*Plan by Claudia · Audited 2026-03-02*
*Based on: Stanford Generative Agents (Park et al. 2023), OpenClaw-bot-review pixel office, codebase audit*

---

## Audit Notes

Key findings from codebase review before this plan was finalised:

1. **Duplicate templates** — `thoughts.gd` and `llm_dialogue.gd` both define the same per-personality fallback strings. These are unified under MEM-001 (single source of truth in MemoryService).

2. **Reordering** — Original draft put architecture refactors (AgentDefinition resources) first. For a POC the memory system and interaction fixes are higher leverage. Architecture cleanup moved to Phase 2 where it unblocks theming work.

3. **LlmDialogue is already a clean service** — `llm_dialogue.gd` handles HTTP, caching, and fallback correctly. ARCH-005 (LLMClient abstraction) is now an incremental addition, not a rewrite. The new `rate_importance()` and `generate_thought()` methods slot in alongside `request_dialogue()`.

4. **Area2D compatibility confirmed** — `agent.gd` uses `CharacterBody2D`. Adding an `Area2D` child with `CollisionShape2D` and connecting `area_entered` is idiomatic Godot 4. The `check_nearby()` call in `main.gd._physics_process` can be removed entirely.

5. **Scope trimmed** — INT-007 (group interactions), INT-003 (reactive replanning), ARCH-006 (folder restructure), and GFX-001 (animated sprites) deferred to Phase 3/4. They're good ideas but not POC-phase work.

6. **GDScript 4 validation** — `class_name` + `Resource` + `@export var agents: Array[AgentDefinition]` is valid. `CanvasModulate` for time-of-day lighting confirmed. `Area2D.area_entered` signal works with `CharacterBody2D` agents that have `Area2D` children.

---

## Section 1: Memory System

> Agents currently forget everything between interactions. This is the single highest-leverage improvement.

### MEM-001 — MemoryService autoload + per-agent observation log
- New autoload: `memory_service.gd`
- Each agent gets an `observations: Array[Dictionary]` with keys: `text`, `timestamp_sec`, `importance` (1–10), `tags: Array[String]`
- API: `MemoryService.add_observation(agent_name, text, importance, tags)`  
  `MemoryService.get_top_memories(agent_name, n) -> Array[Dictionary]`
- Persist to `user://memory/<agent_name>.json` on scene exit, load on scene enter
- Cap at 200 entries; evict lowest-importance when full
- **Unifies** `thoughts.gd` templates into `MemoryService` as the content authority — `thoughts.gd` becomes a thin shim or is removed
- **Effort:** Medium | **Impact:** Very High | **Blocks:** MEM-002, MEM-003, INT-002, INT-004

### MEM-002 — Importance scoring
- When an observation is stored, call LLM: `"Rate 1-10: how significant is this event for {agent_name}? Event: {text}. Reply with only the number."`
- Parse integer from response; fall back to heuristic if LLM unavailable:
  - Interaction event = 7, zone arrival = 3, idle wander = 1
- Add `rate_importance(agent_name, text) -> int` to `llm_dialogue.gd`
- **Effort:** Low | **Impact:** High | **Requires:** MEM-001

### MEM-003 — Weighted memory retrieval for LLM context
- `MemoryService.get_top_memories()` ranks by: `score = 0.3 * (1.0 / age_sec.clamp(1, 3600)) + 0.7 * importance`
- `llm_dialogue.request_dialogue()` injects top-5 as a "Recent memories:" block in the prompt
- Zero new HTTP calls — just enriches the existing prompt string
- **Effort:** Low | **Impact:** High | **Requires:** MEM-001, MEM-002

### MEM-004 — Social relationship tracking
- `MemoryService` maintains per-agent relationship dict: `{other_name: {interaction_count, last_seen_sec, sentiment: float}}`
- Sentiment ∈ [-1.0, 1.0]; updated +0.2 per positive interaction, −0.3 per negative (currently all interactions are neutral → default +0.1)
- `agent.gd.check_nearby()` reads sentiment to bias seek_chance: social * (1 + sentiment * 0.5)
- **Effort:** Medium | **Impact:** High | **Requires:** MEM-001

### MEM-005 — Reflection synthesis
- Trigger after agent accumulates 15+ new observations since last reflection
- Prompt: `"Summarise these {n} observations about {agent_name}'s day into 1-2 sentences of personal insight."`
- Store result as observation with importance=8, tag `reflection`
- Max 2 levels of reflection nesting (reflections can be reflected on once)
- **Effort:** High | **Impact:** High | **Requires:** MEM-001, MEM-002, MEM-003 | **Phase:** 3

---

## Section 2: Interaction & Behavior

### INT-001 — Area2D proximity detection (replaces O(n²) loop)
- Add `Area2D` + `CollisionShape2D(CircleShape2D, radius=80)` to `agent.tscn`
- Connect `area_entered(area: Area2D)` signal; get parent `CharacterBody2D` via `area.get_parent()`
- `agent.gd` handles its own proximity — calls `check_nearby(other)` on signal
- Remove the nested agent loop from `main.gd._physics_process` entirely
- **Effort:** Low | **Impact:** High (correctness + scalability) | **No dependencies**

### INT-002 — Richer dialogue context (prompt upgrade)
- Expand `llm_dialogue.request_dialogue()` prompt from 1 line to structured context:
  ```
  You are {name}, a {personality} person in {zone}.
  Recent memories: {top_3_memories}
  You just encountered {other_name} ({other_personality}).
  Write ONE sentence (max 12 words) you'd say. Reply with ONLY the sentence.
  ```
- Wire `MemoryService.get_top_memories(agent.agent_name, 3)` into the prompt builder
- **Effort:** Low | **Impact:** High | **Requires:** MEM-001, MEM-003

### INT-003 — Information propagation during interactions
- After each interaction, both agents call `MemoryService.add_observation()` with a shared-memory entry:
  `"I talked to {other} near the {zone}. They said: '{dialogue_snippet}'"`
- Creates emergent information spread — what Carol tells Bob, Bob can reference later
- **Effort:** Low | **Impact:** High | **Requires:** MEM-001

### INT-004 — Daily plan / agenda per agent
- On `_ready`, each agent generates a loose agenda: 3–5 `{activity, zone}` pairs
- Generated by LLM from backstory + personality, or from a simple template if LLM unavailable
- Agent checks agenda on `_enter_idle()` and prioritises the next agenda item if idle > 10s
- Agenda items are consumed (removed) when completed
- **Effort:** High | **Impact:** Very High | **Requires:** MEM-001 | **Phase:** 3

### INT-005 — Social waypoints
- Define 2–3 named points per zone in `main.gd` zone data: `{name, position, zone}`
- On `_enter_idle()`, 20% chance agent paths to a waypoint instead of random wander
- Waypoints are hotspots — increased encounter probability
- **Effort:** Medium | **Impact:** Medium | **Phase:** 2

### INT-006 — Personality-driven approach / flee
- `check_nearby()` currently has a personality match block with seek_chance. Extract to a `seek_chance` var on the agent set from personality string at `_ready()`
- Also add `approach_tendency` (float, -1 flee to +1 seek) — shy agents move away from approaching others
- **Effort:** Low | **Impact:** Medium | **No dependencies**

---

## Section 3: Graphics & Visual Polish

### GFX-001 — Floating action text
- On state change, float a short label above the agent head: "→ Cafe", "Chatting…", "Thinking"
- `Label` node, tweened: `position.y - 20` over 1.5s, `modulate.a` fades to 0
- Remove when tween completes
- **Effort:** Low | **Impact:** Medium | **No dependencies**

### GFX-002 — Interaction visual indicator
- When two agents enter `INTERACT` state, draw a dashed line or small "💬" icon between them
- Use `draw_line()` in `_draw()` on the agent, or a separate `Line2D` node spawned by `main.gd`
- Line removed when interaction ends
- **Effort:** Low | **Impact:** Medium | **No dependencies**

### GFX-003 — Upgraded thought bubble
- Replace flat `PanelContainer + Label` with a 9-patch bubble + tail pointing at agent
- Show 1–2 lines: current dialogue + last stored observation (from MEM-001)
- Tween in/out with `ease_in_out`
- **Effort:** Medium | **Impact:** High | **Requires:** MEM-001 for second line | **Phase:** 2

### GFX-004 — Zone floor tinting
- Add a `ColorRect` per zone behind agents, semi-transparent (alpha 0.08)
- Park = green tint, Cafe = warm amber, Town Square = neutral grey-blue
- Defined alongside zone_rects in `main.gd`, no separate system needed
- **Effort:** Low | **Impact:** Medium | **No dependencies**

### GFX-005 — Time-of-day lighting
- Add `CanvasModulate` node to `main.tscn`
- Sim time advances at 60x real speed (1 sim-hour = 1 real-minute)
- Tween modulate color: day=white, evening=warm amber `Color(1.0, 0.85, 0.6)`, night=cool blue `Color(0.55, 0.6, 0.8)`
- Agents shift zones at certain hours (come to cafe in morning, town square at noon etc.)
- **Effort:** Medium | **Impact:** High | **Phase:** 2

### GFX-006 — Animated sprite characters
- Replace `Image.create()` colored rectangles with `AnimatedSprite2D`
- Use a shared top-down character sprite sheet (RPG Maker-style, free assets exist)
- Colorize per agent using `modulate` — preserves hue-shift approach from pixel office
- Animations: `walk_down`, `walk_up`, `walk_left`, `walk_right`, `idle`, `interact`
- **Effort:** High | **Impact:** Very High | **Phase:** 3

---

## Section 4: Architecture

### ARCH-001 — Merge duplicate templates
- `thoughts.gd` and `llm_dialogue.gd` both define personality fallback template dicts
- Move the single authoritative dict into `MemoryService` (or a new `content_data.gd` const file)
- Both `LlmDialogue` and `Thoughts` read from it
- **Effort:** Low | **Impact:** Medium (code quality) | **Requires:** MEM-001

### ARCH-002 — AgentDefinition resource class
- Create `resources/agent_definition.gd` with `class_name AgentDefinition extends Resource`
- `@export` fields: `display_name`, `personality`, `color`, `base_speed`, `detection_radius`, `backstory`
- Convert the 5 hardcoded dicts in `main.gd` to `.tres` files in `content/default/agents/`
- `main.gd` loads an exported `Array[AgentDefinition]` — drag-and-drop in inspector
- **Effort:** Low | **Impact:** High (unblocks all content features) | **Phase:** 2

### ARCH-003 — PersonalityProfile resource class
- `resources/personality_profile.gd`: `@export` seek_chance, speed_modifier, wander_interval, approach_tendency, llm_prompt_fragment
- Replace match blocks in `agent.gd` and `check_nearby()` with profile property reads
- Registry autoload or simple dict in `main.gd` maps personality id → profile resource
- **Effort:** Low | **Impact:** Medium
---

## Priority Matrix

| ID | Section | Effort | Impact | Phase |
|---|---|---|---|---|
| INT-001 | Interaction | Low | High | 1 |
| MEM-001 | Memory | Medium | Very High | 1 |
| MEM-002 | Memory | Low | High | 1 |
| MEM-003 | Memory | Low | High | 1 |
| INT-002 | Interaction | Low | High | 1 |
| INT-003 | Interaction | Low | High | 1 |
| INT-006 | Interaction | Low | Medium | 1 |
| GFX-001 | Graphics | Low | Medium | 1 |
| GFX-002 | Graphics | Low | Medium | 1 |
| GFX-004 | Graphics | Low | Medium | 1 |
| ARCH-001 | Architecture | Low | Medium | 1 |
| MEM-004 | Memory | Medium | High | 2 |
| INT-005 | Interaction | Medium | Medium | 2 |
| GFX-003 | Graphics | Medium | High | 2 |
| GFX-005 | Graphics | Medium | High | 2 |
| ARCH-002 | Architecture | Low | High | 2 |
| ARCH-003 | Architecture | Low | Medium | 2 |
| INT-004 | Interaction | High | Very High | 3 |
| MEM-005 | Memory | High | High | 3 |
| GFX-006 | Graphics | High | Very High | 3 |

---

## Phase 1 Implementation Order

Pick these up in order — each is a clean, shippable unit:

1. **INT-001** — Area2D detection. Independent. Fixes scalability, cleans up main.gd.
2. **MEM-001** — MemoryService autoload. Foundation everything else builds on.
3. **MEM-002** — Importance scoring. Slots into llm_dialogue.gd alongside existing request_dialogue().
4. **MEM-003** — Weighted retrieval. Pure function on top of MEM-001 data.
5. **INT-002** — Richer prompt. Immediately uses MEM-003. One function edit in llm_dialogue.gd.
6. **INT-003** — Info propagation. Add 2 lines to _enter_interact() callback. Uses MEM-001.
7. **INT-006** — Personality approach/flee. Replaces match block, no new dependencies.
8. **GFX-001** — Floating action text. Independent visual polish.
9. **GFX-002** — Interaction indicator. Independent visual polish.
10. **GFX-004** — Zone tinting. 5 ColorRect nodes. Independent.
11. **ARCH-001** — Merge duplicate templates. Cleanup after MEM-001 is in place.

---

*Ready for implementation. Start with INT-001 then MEM-001.*

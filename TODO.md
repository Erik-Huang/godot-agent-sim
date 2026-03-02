# godot-agent-sim — TODO

*Last updated: 2026-03-02 | Branch: phase-1-implementation*

---

## ✅ Phase 1 — Complete

All shipped. Key wins:
- **Memory system** (MEM-001/002/003): MemoryService autoload, importance scoring, weighted retrieval injected into LLM prompts
- **Interaction fixes** (AUDIT-001/002/003): Both agents enter INTERACT state, seek_chance rolled once per encounter, partner now responds
- **Behavior** (INT-002/003/006): Richer prompts with zone + memory context, info propagation, personality-driven approach/flee
- **Visual** (GFX-001/002/004): Floating action text, interaction line indicator, zone floor tints
- **Stability** (AUDIT-004–010/015): Memory auto-save, LLM queue (max 3 concurrent), system prompt, stale refs cleared, cache cleanup, idle thoughts wired up, `randomize()` removed
- **Architecture** (INT-001, ARCH-001): Area2D signal detection, ContentData unified template source

---

## Phase 2 — Next Up

### Memory
- **MEM-004** — Social relationship tracking: per-agent `{other: {count, last_seen, sentiment}}` dict in MemoryService; sentiment biases seek_chance. *Effort: Medium | Impact: High*
- **AUDIT-013** — Memory recency decay is broken: `1/age` drops below noise after 5s. Replace with `exp(-age_sec / 3600.0)` for meaningful hourly decay. *Effort: Low | Impact: Medium*

### Interaction & Behavior
- **INT-005** — Social waypoints: 2–3 named hotspots per zone (bench, fountain); 20% idle chance to path there, increases encounter density. *Effort: Medium | Impact: Medium*
- **AUDIT-014** — Agents don't interact while traveling: add `_poll_nearby_agents()` to `_process_moving_to_zone()`. *Effort: Trivial | Impact: Low*

### Graphics
- **GFX-003** — Upgraded thought bubble: 9-patch bubble with tail, show dialogue + last memory line, tween in/out. *Requires MEM-001 ✅ | Effort: Medium | Impact: High*
- **GFX-005** — Time-of-day lighting: `CanvasModulate` tweening day→evening→night at 60x sim speed; agents zone-shift by hour. *Effort: Medium | Impact: High*

### Architecture
- **ARCH-002** — AgentDefinition resource: move hardcoded agent dicts in `main.gd` to `.tres` files; drag-and-drop roster in inspector. *Effort: Low | Impact: High*
- **ARCH-003** — PersonalityProfile resource: replace personality match blocks with `@export` resource files. *Effort: Low | Impact: Medium*
- **AUDIT-011** — Hardcoded agent names in importance heuristic (`llm_dialogue.gd`): query dynamically. *Effort: Low | Impact: Low*
- **AUDIT-012** — World bounds defined in 3 places with different values: centralise in `main.gd`, pass to agents. *Effort: Low | Impact: Low*
- **AUDIT-016** — UI label refresh destroys/recreates all nodes every tick: reuse Labels or switch to RichTextLabel. *Effort: Low | Impact: Low*

---

## Phase 3 — Later

- **MEM-005** — Reflection synthesis: after 15 observations, LLM synthesises 1–2 insight sentences stored as high-importance memories. *Effort: High | Impact: High*
- **INT-004** — Daily agenda per agent: LLM-generated plan at sim start; agent follows steps, deviates on events. *Effort: High | Impact: Very High*
- **GFX-006** — Animated sprite characters: replace colored rects with `AnimatedSprite2D` + shared sprite sheet, colorised per agent. *Effort: High | Impact: Very High*

---

## Known Gotchas

- **ContentData autoload order**: must be first in `project.godot` autoload list — `class_name` resolution not guaranteed at parse time
- **area_entered one-shot**: signal fires once on entry; poll `get_overlapping_areas()` in idle/wander to retry missed rolls

# godot-agent-sim — TODO

*Last updated: 2026-03-02 | Branch: main*

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

## ✅ Phase 2 — Complete

All shipped. Key wins:
- **Debug** (DBG-001/002): Spacebar pause + PAUSED overlay; all labels white, sized, outlined
- **Memory depth** (MEM-004, AUDIT-013): Social relationship sentiment, exponential recency decay
- **Behavior** (INT-005, AUDIT-014): 6 named social waypoints, interactions during travel
- **Visual** (GFX-003/005): Time-of-day lighting (60x sim speed, dawn/dusk/night), upgraded thought bubble with last-memory line
- **Architecture** (ARCH-002/003, AUDIT-011/012/016): AgentDefinition + PersonalityProfile resource stubs, centralised world bounds, dynamic agent names, UI label pool

---

## Phase 3 — Later

- **MEM-005** — Reflection synthesis: after 15 observations, LLM synthesises 1–2 insight sentences stored as high-importance memories. *Effort: High | Impact: High*
- **INT-004** — Daily agenda per agent: LLM-generated plan at sim start; agent follows steps, deviates on events. *Effort: High | Impact: Very High*
- **GFX-006** — Animated sprite characters: replace colored rects with `AnimatedSprite2D` + shared sprite sheet, colorised per agent. *Effort: High | Impact: Very High*

---

## Known Gotchas

- **ContentData autoload order**: must be first in `project.godot` autoload list — `class_name` resolution not guaranteed at parse time
- **area_entered one-shot**: signal fires once on entry; poll `get_overlapping_areas()` in idle/wander to retry missed rolls

---

## Section 6: Pre-Phase 3 Fixes

*Identified during pre-Phase 3 audit (2026-03-02)*

### Blockers for Phase 3

- **AUDIT-019** — `sim_time` not accessible from agents: required for INT-004 (daily agenda). Either pass as property and update each frame from `main.gd`, or extract to a TimeManager autoload. *Effort: Low | Impact: High (blocks INT-004)*

- **AUDIT-018** — No direction tracking during movement: `_move_toward_nav_target()` computes direction but doesn't store it or flip sprite. Prerequisite for GFX-006 animated sprites. Also a visual bug now (agents always face right while walking). Fix: add `last_move_dir` var, set `sprite.flip_h` in `_move_toward_nav_target()`. *Effort: Trivial | Impact: Medium (blocks GFX-006, fixes visual bug)*

### Bugs / Tech Debt

- **AUDIT-017** — Partner response bypasses rate limiter: `_generate_partner_response()` creates its own `HTTPRequest` without going through `_dispatch_or_queue()`. Under high interaction density, concurrent requests can exceed `MAX_CONCURRENT = 3`. Fix: route through the queue. *Effort: Low | Impact: Low*

- **AUDIT-020** — TODO.md stale Phase 2 section: "Phase 2 — Next Up" still lists implemented items (MEM-004, AUDIT-013, INT-005, AUDIT-014, GFX-003, GFX-005, etc.) as pending. Clean up or collapse into the ✅ summary. *Effort: Trivial | Impact: Trivial (docs hygiene)*

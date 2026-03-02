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

## ✅ Phase 3 — Complete

All shipped. Key wins:
- **Pre-flight fixes** (AUDIT-017/018/019/020): Partner response routed through rate limiter, direction tracking during movement, sim_time exposed to agents, TODO cleanup
- **Memory** (MEM-005): Reflection synthesis — after 15 observations, LLM generates 1–2 insight sentences stored as high-importance memories; counter persists across saves
- **Behavior** (INT-004): Daily agenda per agent — LLM-generated or personality-template plan at sim start; agents follow steps via MOVING_TO_ZONE; items marked done on arrival
- **Visual** (GFX-006): Direction-aware procedural sprites — circle body + nose triangle indicator, interact partner line; replaces colored rect; ready for real sprite swap

---

## Known Gotchas

- **ContentData autoload order**: must be first in `project.godot` autoload list — `class_name` resolution not guaranteed at parse time
- **area_entered one-shot**: signal fires once on entry; poll `get_overlapping_areas()` in idle/wander to retry missed rolls

# godot-agent-sim — TODO

*Last updated: 2026-03-02 | Branch: main*

---

## ✅ Phase 1 — Complete

- **Memory system** (MEM-001/002/003): MemoryService autoload, importance scoring, weighted retrieval injected into LLM prompts
- **Interaction fixes** (AUDIT-001/002/003): Both agents enter INTERACT state, seek_chance rolled once per encounter, partner now responds
- **Behavior** (INT-002/003/006): Richer prompts with zone + memory context, info propagation, personality-driven approach/flee
- **Visual** (GFX-001/002/004): Floating action text, interaction line indicator, zone floor tints
- **Stability** (AUDIT-004–010/015): Memory auto-save, LLM queue (max 3 concurrent), system prompt, stale refs cleared, cache cleanup, idle thoughts, `randomize()` removed
- **Architecture** (INT-001, ARCH-001): Area2D signal detection, ContentData unified template source

---

## ✅ Phase 2 — Complete

- **Debug** (DBG-001/002): Spacebar pause + PAUSED overlay; all labels white, sized, outlined
- **Memory depth** (MEM-004, AUDIT-013): Social relationship sentiment, exponential recency decay
- **Behavior** (INT-005, AUDIT-014): 6 named social waypoints, interactions during travel
- **Visual** (GFX-003/005): Time-of-day lighting (60x sim speed, dawn/dusk/night), upgraded thought bubble with last-memory line
- **Architecture** (ARCH-002/003, AUDIT-011/012/016): AgentDefinition + PersonalityProfile resource stubs, centralised world bounds, dynamic agent names, UI label pool

---

## 🚧 Phase 3 — In Progress

### ✅ Done
- **Pre-flight fixes** (AUDIT-017/018/019/020): Partner response through rate limiter, direction tracking during movement, sim_time exposed to agents, TODO cleanup
- **MEM-005** — Reflection synthesis: after 15 observations, LLM generates 1–2 insight sentences stored as importance-8 memories; counter persists
- **INT-004** — Daily agenda: LLM-generated or personality-template plan at 8am sim-time; agents follow steps via MOVING_TO_ZONE, mark done on arrival
- **GFX-006 (placeholder)** — Direction-aware procedural sprites: circle body + nose triangle, replaces colored rect, direction tracks `last_move_dir`

### 🔄 In Progress
- **GFX-006 (real sprites)** — Ninja Adventure asset integration: 5 distinct CC0 pixel art characters, 4-direction walk + idle animations, AnimatedSprite2D, pixel art rendering. Subagent running now.

### ⬜ Remaining
- **GFX-006 (polish)** — Once sprites land: tune scale (16px → 32px), verify walk animation timing at 8fps, add interact idle-facing-partner animation, test all 5 agent characters in-sim

---

## Known Gotchas

- **ContentData autoload order**: must be first in `project.godot` autoload list — `class_name` resolution not guaranteed at parse time
- **area_entered one-shot**: signal fires once on entry; poll `get_overlapping_areas()` in idle/wander to retry missed rolls
- **Ninja Adventure sprite layout**: 64×64 sheet, 4×4 grid, 16×16 per frame. Row 0=walk_down, 1=walk_up, 2=walk_left, 3=walk_right. Verify with `sips` before generating SpriteFrames .tres files.

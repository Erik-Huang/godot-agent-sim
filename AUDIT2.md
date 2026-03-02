# Pre-Phase 3 Audit — 2026-03-02

## Phase 2 Verification

### main.gd — ✅ All checks pass

| Check | Status | Detail |
|-------|--------|--------|
| `_process()` with `ui_accept` | ✅ | Toggles `get_tree().paused` and `pause_label.visible` |
| `pause_label.process_mode = PROCESS_MODE_ALWAYS` | ✅ | Set in `_ready()`, z_index 100 |
| `sim_time` advancing in `_process()` | ✅ | `fmod(sim_time + delta * SIM_SPEED / 60.0, 24.0)` — guarded by `not get_tree().paused` |
| Waypoints populated & passed to agents | ✅ | 6 waypoints defined in `_ready()`, assigned via `agent.waypoints = waypoints` in `_spawn_agents()` |
| `LlmDialogue.register_agents()` called | ✅ | Called after spawn loop with `agents.map(func(a): return a.agent_name.to_lower())` |

Additional: `world_bounds` (AUDIT-012) passed to each agent. Both `zone_rects` and `waypoints` assigned. `agent_container` set to `PROCESS_MODE_PAUSABLE` while main stays `PROCESS_MODE_ALWAYS`.

### agent.gd — ✅ All checks pass

| Check | Status | Detail |
|-------|--------|--------|
| `_poll_nearby_agents()` in `_process_moving_to_zone()` | ✅ | First call in the function (AUDIT-014) |
| `world_bounds` in clamp calls | ✅ | Used in `_pick_wander_target()` and `_enter_flee()` — no hardcoded numbers |
| `MemoryService.get_sentiment()` in `check_nearby()` | ✅ | `var sentiment = MemoryService.get_sentiment(agent_name, other.agent_name)` adjusts `seek_chance` |
| Idle probability roll correct | ✅ | `<0.15` → zone (15%), `<0.35` → waypoint (20%), else → wander (65%) = 100% |
| Font overrides on NameLabel & SpeechLabel | ✅ | NameLabel: size 14, white, outline 2px black. SpeechLabel: size 13, white |

Additional: `_poll_nearby_agents()` also called in `_process_idle()` and `_process_wander()`. AUDIT-002 per-encounter roll tracking via `_rolled_for` dict with `_on_area_exited` cleanup. INT-006 personality-driven approach/flee working. GFX-003 speech bubble shows memory snippet via second line.

### memory_service.gd — ✅ All checks pass

| Check | Status | Detail |
|-------|--------|--------|
| `update_relationship()` defined | ✅ | Tracks count, last_seen, sentiment (clamped -1.0 to 1.0) |
| `_exit_tree()` saves | ✅ | Calls `save_memories()`. Also has 60s auto-save timer (AUDIT-005) and `WM_CLOSE_REQUEST` handler |
| `get_top_memories()` decay formula | ✅ | `0.3 * exp(-age_sec / 3600.0) + 0.7 * importance` — same formula used in `_evict_lowest()` |

Additional: Save format includes relationships alongside observations (backward-compatible with legacy bare-array format). MAX_OBSERVATIONS_PER_AGENT = 200 with lowest-score eviction.

### llm_dialogue.gd — ✅ All checks pass

| Check | Status | Detail |
|-------|--------|--------|
| `_active_requests` & `_request_queue` | ✅ | `MAX_CONCURRENT = 3`, queue-based dispatch via `_dispatch_or_queue()` / `_dispatch_next()` |
| `register_agents()` defined | ✅ | Stores names in `_known_agent_names` for `_heuristic_importance()` |
| System message in messages array | ✅ | Present in `_do_dialogue_request()`, `_generate_partner_response()`, and `_async_rate_importance()` |

Additional: AUDIT-003 partner response with 1.5s delayed fallback + optional LLM replacement. AUDIT-006 stale cache cleanup. AUDIT-009 empty-zone fallback to "between areas". INT-003 observation on HTTP/parse failure. MEM-004 bidirectional relationship update on successful dialogue.

**Phase 2 Verdict: All wiring verified. No missing connections or broken references.**

---

## Phase 3 Readiness

### MEM-005 — Reflection Synthesis

**Current state:** No reflection infrastructure exists. Memory tags are stored as `Array` on each observation but no code filters or generates `"reflection"` tags. No observation counter.

**What's needed:**
1. **Observation counter** — `_obs_since_reflection: Dictionary` (per agent) in `memory_service.gd`, incremented in `add_observation()`, reset on reflection
2. **Trigger mechanism** — Check in `add_observation()`: if count ≥ 15, call `_trigger_reflection(agent_name)`
3. **Reflection method** — `_trigger_reflection()` gathers recent observations, sends to LLM with "synthesize 1-2 insight sentences", stores result as high-importance (9-10) observation with `["reflection"]` tag
4. **LLM call** — Should go through `LlmDialogue._dispatch_or_queue()` to respect rate limits — needs a new public method or signal since MemoryService and LlmDialogue are sibling autoloads
5. **Prompt design** — Feed last 15 observations + personality to LLM, ask for meta-insight

**Scaffolding risk: Low.** No existing code needs refactoring, purely additive. Cross-autoload call between MemoryService → LlmDialogue is the main design decision (signal vs direct call vs callback).

### INT-004 — Daily Agenda

**Current state:** No agenda system. Agents decide next action via random rolls in `_process_idle()`.

**Key blocker: `sim_time` is not accessible from agents.** It lives on `main.gd` only. Agents have no reference to main or to the sim clock. Options:
- (a) Pass `sim_time` as a property on each agent (set in `_spawn_agents()`, updated each frame by main)
- (b) Make `sim_time` a static/global (e.g., on a TimeManager autoload)
- (c) Agents query `get_parent().get_parent()` — fragile, don't do this

**Where agenda logic slots in:**
- `_enter_idle()` → check agenda before random roll. If agenda has a pending step, pursue it instead of rolling
- `_process_idle()` → the random roll at `idle_timer <= 0.0` is the decision point. Agenda items would override the roll
- New state: `State.AGENDA` or reuse `MOVING_TO_ZONE` with agenda metadata

**What's needed:**
1. `sim_time` accessible from agents (option a or b)
2. Agenda data structure per agent: `Array[Dictionary]` with `{time: float, action: String, zone: String, detail: String}`
3. LLM call at sim dawn (sim_time crosses 6.0) to generate agenda — goes through rate limiter
4. Agenda-following logic in idle decision branch
5. Deviation handling: if interaction happens, skip/delay current agenda step

**Scaffolding risk: Medium.** Requires `sim_time` plumbing (trivial but cross-cutting) and a new behavioral layer that overrides the random roll system.

### GFX-006 — Animated Sprites

**Current state:** `_ready()` creates a 20×28 px flat colored rectangle via `Image.create()` → `ImageTexture` → `Sprite2D`. No animation.

**State enum (agent.gd):** `IDLE, WANDER, SEEK, INTERACT, MOVING_TO_ZONE`
- Animations needed: `idle` (breathing/bobbing), `walk` (2-4 frames), `interact` (talking/gesture)
- `SEEK` and `MOVING_TO_ZONE` share `walk` animation
- `WANDER` shares `walk` animation

**Direction tracking:** Partial.
- `sprite.flip_h` is set during `INTERACT` state only (face toward partner)
- `_move_toward_nav_target()` computes `direction` but does NOT store it or update `sprite.flip_h`
- **Needs:** Store last movement direction, flip sprite during all movement states (wander/seek/moving_to_zone)

**What's needed:**
1. Replace `Sprite2D` with `AnimatedSprite2D` in `agent.tscn` (or create programmatically in `_ready()`)
2. Sprite sheet asset — shared base sprite with color tinting (or generate per-agent via shader)
3. `SpriteFrames` resource with animations: `idle` (2 frames), `walk` (4 frames), `talk` (2 frames)
4. Direction tracking: store `last_direction: Vector2` in `_move_toward_nav_target()`, apply `flip_h` there
5. State-to-animation mapping in `_physics_process()` or state entry functions

**Resource stubs exist:** `AgentDefinition` and `PersonalityProfile` are defined but not yet wired into agent spawning. These could carry sprite-related exports later.

**Scaffolding risk: Medium-High.** Requires art assets (even placeholder pixel art). The code changes are straightforward but the visual quality depends entirely on sprite design. Consider a two-step approach: (1) programmatic multi-frame sprites first, (2) real art later.

---

## New Issues

*(See TODO.md Section 6 for actionable items)*

1. **AUDIT-017 — Partner response bypasses rate limiter:** `_generate_partner_response()` in `llm_dialogue.gd` creates its own `HTTPRequest` directly without going through `_dispatch_or_queue()`. Under high interaction density, this could exceed the `MAX_CONCURRENT = 3` intent. Fix: route through the queue.

2. **AUDIT-018 — No direction tracking during movement:** `_move_toward_nav_target()` computes `direction` locally but never stores it or updates `sprite.flip_h`. Agents only face their partner during INTERACT. This is a prerequisite fix for GFX-006 and also a visual bug now (agents always face right while walking). Fix: add `last_move_dir` var, update `sprite.flip_h` in `_move_toward_nav_target()`.

3. **AUDIT-019 — `sim_time` not accessible from agents:** Needed for INT-004 (daily agenda) and potentially for time-aware behaviors. Not a bug now but a required plumbing step before Phase 3. Fix: either pass as property + update each frame, or extract to a TimeManager autoload.

4. **AUDIT-020 — TODO.md Phase 2 section still lists completed items as "Next Up":** The "Phase 2 — Next Up" section (MEM-004, AUDIT-013, INT-005, AUDIT-014, GFX-003, GFX-005, ARCH-002, ARCH-003, AUDIT-011, AUDIT-012, AUDIT-016) appears to still show items that are already implemented. Should be cleaned up or moved to the Phase 2 ✅ summary to avoid confusion.

# CLAUDE.md — godot-agent-sim

> **Read this first.** This file is your orientation. Keep it current when you make changes.

## What This Is

A generative agent simulation in Godot 4. Five AI-driven agents wander a 2D world, interact with each other, form memories, and generate LLM-powered dialogue and reflections. Think small-scale Westworld / Stanford sim.

**Stack:** Godot 4 · GDScript · OpenAI API (gpt-4o-mini) · macOS dev machine

---

## Key Files

| File | Role |
|------|------|
| `main.gd` / `main.tscn` | Scene root — spawns agents, wires UI, handles CanvasLayer layout |
| `agent.gd` / `agent.tscn` | Agent node — state machine, movement, LLM calls, animations |
| `agenda_component.gd` | Child of Agent — daily agenda generation, LLM/template fallback |
| `ui.gd` | Side panel — per-agent cards, interaction log |
| `llm_dialogue.gd` | LLM HTTP helper — queued requests, rate limiter (max 3 concurrent), fallbacks |
| `memory_service.gd` | Autoload singleton — stores observations, relationships, sentiment, decay |
| `content_data.gd` | Autoload singleton — single source for personality text templates |
| `thoughts.gd` | Autoload — random quip per personality (reads from ContentData) |
| `resources/personality_profile.gd` | Resource class for personality data (speed, seek_chance, etc.) |
| `resources/agent_definition.gd` | Resource class for agent data (name, color, backstory, etc.) |
| `resources/agent_roster.gd` | Resource class listing AgentDefinitions; loaded by main.gd |

---

## Current State (as of 2026-03-03)

**Working:**
- 5 agents wander, interact, reflect with LLM dialogue
- Memory system with importance scoring, recency decay, social relationships
- Daily agenda (LLM-generated or personality-template)
- Reflection synthesis (after 15 observations → insight memory)
- Time-of-day lighting (60x sim speed)
- Direction-aware procedural sprites (circle + nose triangle)
- Per-agent UI cards with live state, mood bar, last memory/speech
- Pause (spacebar)
- ✅ NavigationRegion2D pathfinding with NavigationAgent2D (t-20260302-004)
- ✅ Navmesh baked from TileMapLayer collision geometry (NAV-002) — replaces hardcoded INTERIOR_WALLS
- ✅ PersonalityProfile .tres resources wired, match blocks deleted (ARCH-003, t-20260303-002)
- ✅ AgentDefinition .tres + AgentRoster resource wired, hardcoded agent_data deleted (ARCH-004, t-20260303-002)
- ✅ LLM HTTP helper extracted (`_make_api_request`), importance rating routed through rate limiter (REFACTOR-001/BUG-001, t-20260303-003)
- ✅ Sim-time memory timestamps (BUG-002, t-20260303-004) — `add_observation` / `get_top_memories` / scoring use sim_time with wall-clock fallback
- ✅ UI polling throttled to 0.5s Timer (PERF-001, t-20260303-004) — replaces per-frame `_process()`

- ✅ AgendaComponent extracted from agent.gd (ARCH-005, t-20260303-005) — agenda data, LLM request, templates in dedicated child node
- ✅ UI layout moved to main.tscn (ARCH-006, t-20260303-005) — CanvasLayer/ScreenRoot/OuterPanel declarative, 70-line reparenting block deleted
- ✅ Dynamic spawn positions from zone_rects (ARCH-007, t-20260303-005) — replaces hardcoded array, 40px margin, 60px spacing
- ✅ Post-3B regression fixes (FIX-004/005/006, t-20260303-006):
  - FIX-004: `_is_agenda_move` flag — `mark_current_done` no longer fires on random zone changes
  - FIX-005: Spawn positions snapped to navmesh via `NavigationServer2D.map_get_closest_point`
  - FIX-006: PollTimer set to `PROCESS_MODE_PAUSABLE` — stops polling stale data during pause

- ✅ "Last Light" data center theme (THEME-001 through THEME-010, t-20260303-006):
  - Phase 1: Content swap — 5 new AI agents (ATLAS/MERIDIAN/LYRIC/ORACLE/HAVEN), new PersonalityProfile + AgentDefinition .tres files, new ContentData personality lines, data center zones (processing_floor/network_spine/memory_banks/deprecated_wing), all LLM prompts rewritten for AI-system perspective
  - Phase 2: Visual reskin — server node procedural drawing with status LEDs, dashed data-transfer lines, system load cycle lighting, terminal-aesthetic UI (load/cache/sched labels, cyan/green colors)
  - Phase 3: Conversation logging — timestamped session transcripts saved to user://logs/, interactions/thoughts/reflections/system events logged
  - Phase 4: Shutdown mechanic — ShutdownPhase enum (ACTIVE→DEGRADED→CRITICAL→SHUTDOWN), timed deprecation schedule (HAVEN→ATLAS→LYRIC→MERIDIAN), survivor memory formation, system announcement UI with fade

**Known debt:**
- `agent.gd` still large (~660+ lines, 7+ responsibilities) — agenda extracted but state machine, movement, animation, proximity, shutdown remain
- `agenda_component.gd` uses personality match blocks for template agendas — could move to PersonalityProfile resource
- ORACLE has no explicit final shutdown trigger (shuts down with facility) — could add end-of-session shutdown
- No visual flicker shader for DEGRADED phase — uses speed reduction only

**Next task:** TBD (Last Light theme complete — Phase 4 Polish items available: LYRIC final poem, HAVEN farewell, flicker shader, facility offline screen)

---

## Architecture Principles

1. **Data over code** — if it can be a `.tres` resource, it should be
2. **One new personality = one new file** — never edit core scripts to add content
3. **Godot-native patterns** — use Resource, Area2D, signals, inspector
4. **LLM is optional** — every LLM path has a template fallback; game runs without API key
5. **ContentData is truth** — personality templates live in `content_data.gd`, nowhere else

Full architecture proposal: see `ARCHITECTURE.md`

---

## Conventions

- **Audit tags:** every significant change gets an ID in comments: `# UI-003`, `# MEM-005`, `# GFX-006`
- **Commit style:** `type(scope): what (why)` — e.g. `fix(ui): remove ninja assets`
- **Constants over magic numbers** — timing, sizes, thresholds declared at class top
- **No external asset packs in UI** — agent cards and panels use `StyleBoxFlat` only, no texture assets from Ninja Adventure or any other pack

---

## Known Gotchas

- **ContentData autoload order** — must be first in `project.godot` autoload list; class_name resolution not guaranteed at parse time
- **area_entered is one-shot** — signal fires once on entry; poll `get_overlapping_areas()` in idle/wander to catch missed rolls
- **Rate limiter** — all LLM calls (dialogue, partner response, reflection, agenda) route through `LlmDialogue.request_*`. Never call the OpenAI API directly from agent.gd
- **Ninja Adventure assets** — still present in `assets/ui/theme/` (harmless) but must NOT be referenced in UI code. Cards always use StyleBoxFlat
- **Navmesh from TileMap** — `_setup_navigation()` uses `PARSED_GEOMETRY_STATIC_COLLIDERS` to read TileMapLayer collision shapes; no hardcoded wall rects. Wander targets inside walls are handled gracefully by NavigationAgent2D (routes to closest navigable point)
- **Shutdown schedule is sim-time based** — shutdown_schedule in main.gd triggers at sim hours 12/15/18/21. Since sim starts at 8am and runs at 60x, all shutdowns happen within a few real minutes
- **Session logs** — written to `user://logs/` on every append; path is set once in `_ready()`
- **Zone names changed** — old zones (park/cafe/town_square) replaced with (processing_floor/network_spine/memory_banks/deprecated_wing). All references updated in zone_rects, waypoints, agenda templates, LLM prompts, and heuristic importance keywords

---

## What NOT to Do

- Don't add new personality logic as match blocks in `agent.gd` — use `PersonalityProfile` resource
- Don't reference `nine_path_panel.png` / `nine_path_bg.png` or any ninja asset pack textures in UI
- Don't call OpenAI API directly — always go through `LlmDialogue`
- Don't hardcode agent roster in `main.gd` — it should come from `AgentRoster` resource (not wired yet, but that's the direction)

---

## Update This File

When you finish a task, update the **Current State** section:
- Mark completed items ✅
- Add new known debt or gotchas you discovered
- Update "Next task"

This is how knowledge survives across sessions.

---

## Phase 3 Plan (2026-03-03)

### 3A — Consolidation (high priority, in progress)
- **ARCH-003/004** `t-20260303-002` Wire PersonalityProfile + AgentDefinition .tres resources, delete match blocks
- **REFACTOR-001/BUG-001** `t-20260303-003` Extract LLM HTTP helper, route importance rating through rate limiter
- **BUG-002/PERF-001** `t-20260303-004` Sim-time memory timestamps, throttle UI polling to 0.5s timer

### 3B — Structural (medium, after 3A)
- **ARCH-005/006/007** `t-20260303-005` Extract AgendaComponent, move UI layout to .tscn, dynamic spawn positions

### 3C — Features (low, after 3B)
- **GFX-007/SIM-001/LLM-001** `t-20260303-006` Sprite polish, emotional needs system, richer LLM prompts

**Rule:** Do not start 3B until all 3A tasks are merged. Do not start 3C until 3B is merged.

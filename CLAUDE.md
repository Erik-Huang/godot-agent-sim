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
| `ui.gd` | Side panel — per-agent cards, interaction log |
| `llm_dialogue.gd` | LLM HTTP helper — queued requests, rate limiter (max 3 concurrent), fallbacks |
| `memory_service.gd` | Autoload singleton — stores observations, relationships, sentiment, decay |
| `content_data.gd` | Autoload singleton — single source for personality text templates |
| `thoughts.gd` | Autoload — random quip per personality (reads from ContentData) |
| `resources/personality_profile.gd` | Resource class for personality data (speed, seek_chance, etc.) |
| `resources/agent_definition.gd` | Resource class for agent data (name, color, backstory, etc.) |

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

**Known debt:**
- `agent.gd` is a God Object (677 lines, 7+ responsibilities) — see REVIEW-2026-03-03.md
- `PersonalityProfile` and `AgentDefinition` resources exist but are NOT wired — personality still uses match blocks in agent.gd
- `main.gd` has 70 lines of manual UI reparenting in `_ready()`

**Next task:** TBD

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

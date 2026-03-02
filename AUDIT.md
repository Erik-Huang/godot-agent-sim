# Audit Report — godot-agent-sim

*Audited 2026-03-02 · Evidence-first methodology (Zeno)*
*Every claim cites `file:Lx-Ly`. No evidence, no claim.*

---

## Critical Issues (will crash or break core behavior)

### C-1: One-Sided Interactions — Partner Never Enters INTERACT State

**Evidence:** `agent.gd:L218-L228` — `_enter_interact(other)` sets `self.state = State.INTERACT`, `self.velocity = Vector2.ZERO`, and `self.interact_partner = other`. But it **never modifies `other`** in any way.

**Evidence:** `agent.gd:L197-L215` — `_enter_seek` → when distance < 35 → `_enter_interact(seek_target)` is called only on self.

**Impact:** Agent A stands still for 5 seconds "chatting" while Agent B wanders away obliviously. The interaction line (`_draw`, L276) stretches across the screen chasing a walking agent. Visually absurd — it looks like A is talking to B's back as B walks away. This single bug makes every interaction look broken.

**Fix:** When Agent A enters INTERACT with Agent B, call `other._enter_interact(self)` (or a `receive_interaction(initiator)` method) so both agents stop, face each other, and both show speech. Both need `interaction_cooldown` set.

---

### C-2: seek_chance Rolled Every Physics Frame — Probability Math is Fundamentally Broken

**Evidence:** `agent.gd:L308-L316` — `_poll_nearby_agents()` iterates `get_overlapping_areas()` and calls `check_nearby(other)` for each. This runs every `_physics_process` frame during IDLE (L158) and WANDER (L190).

**Evidence:** `agent.gd:L332` — `if randf() < seek_chance:` — this roll happens ~60 times per second.

**Impact:** Even the "shy" personality (`seek_chance=0.1`, L69) has a 99.8% chance of seeking within 1 second of proximity (P = 1 - 0.9^60). After 3 seconds, every personality is at 100%. The `seek_chance` values (0.1 to 0.7) are meaningless — all agents behave identically as "always interact." The personality system is an illusion.

**Fix:** Either:
- Roll once per encounter (set a `has_rolled_for: Dictionary` that tracks which agents you've already rolled for this proximity window, reset when they leave range)
- Or use a per-second timer: only roll once per second, not per frame

---

### C-3: Only Initiator Shows Speech — Other Agent is Silent

**Evidence:** `llm_dialogue.gd:L108,L116,L154,L164,L176,L189,L199` — every code path calls `agent.show_speech(text)` but **never** `other.show_speech()`.

**Impact:** In every interaction, only one agent shows a speech bubble. The "conversation" is a monologue. The other agent shows nothing — no acknowledgment, no response. This makes interactions feel hollow and broken.

**Fix:** Generate dialogue for both agents. At minimum, show a reactive line on `other` (e.g., from fallback templates or a second LLM call). Ideally, generate a back-and-forth: A says → B responds.

---

### C-4: Stale `seek_target` Reference Never Cleared

**Evidence:** `agent.gd:L149-L155` — `_enter_idle()` sets `interact_partner = null` but does **not** clear `seek_target`.

**Evidence:** `agent.gd:L17` — `var seek_target: CharacterBody2D = null` — only set in `_enter_seek` (L199).

**Impact:** `seek_target` retains a reference to a potentially freed node. While `_process_seek` does check `is_instance_valid(seek_target)` at L204, this is fragile — if the node is freed and memory reallocated, `is_instance_valid` may return true on a different object. More practically, this prevents garbage collection of the referenced node.

**Fix:** Set `seek_target = null` in `_enter_idle()` and `_enter_wander()`.

---

### C-5: Memory Persistence Only on WM_CLOSE_REQUEST — Data Loss on Any Abnormal Exit

**Evidence:** `memory_service.gd:L13-L15` — `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` is the only save trigger.

**Impact:** Clicking "Stop" in the Godot editor, force-quitting, crashes, or power loss all lose ALL accumulated memories. For a sim that runs for extended periods, this is devastating. All observations gone.

**Fix:** Add periodic auto-save (every 60s via timer) and also save on `NOTIFICATION_PREDELETE` or `_exit_tree`. Consider using `NOTIFICATION_APPLICATION_FOCUS_OUT` as well.

---

### C-6: Dialogue Cache Never Cleaned — Unbounded Memory Growth

**Evidence:** `llm_dialogue.gd:L4` — `var dialogue_cache: Dictionary = {}`
**Evidence:** `llm_dialogue.gd:L188` — entries are added: `dialogue_cache[cache_key] = {...}`
**Evidence:** `llm_dialogue.gd:L104-L110` — stale entries are skipped via TTL check but **never deleted**.

**Impact:** Every unique agent pair creates a permanent cache entry. With N agents, that's O(N²) entries that grow every 60 seconds (CACHE_TTL). With 20 agents, 190 pairs × many interactions = significant unbounded growth over a long session.

**Fix:** Either prune stale entries when checked, or run a periodic cleanup timer. Simple fix at L107: add `dialogue_cache.erase(cache_key)` when TTL expired, then continue to fetch fresh.

---

## Behavioral Issues (why it feels lifeless)

### B-1: No Agent Goals, Plans, or Schedules — Pure Random Walk

**Evidence:** `agent.gd:L157-L166` — when idle timer expires, the only decision is: 15% chance move to random zone, 85% chance wander randomly. There is no concept of goals, plans, routines, or preferences.

**Impact:** Agents are Brownian motion particles. They don't prefer zones, don't have routines, don't seek out specific agents. A "curious" agent and a "lazy" agent both just drift randomly. Without intentionality, the sim feels like a screensaver, not a world.

---

### B-2: Personality Affects Only Speed and Seek Chance — Invisible in Behavior

**Evidence:** `agent.gd:L51-L82` — personality maps to `speed` and `seek_chance`/`approach_tendency` via match blocks.

**Impact:** A viewer can't distinguish personalities by watching the sim. "Curious" (speed=60) and "social" (speed=65) are nearly identical visually. The personality has no effect on:
- Which zones they prefer
- What they talk about
- How long they interact
- Whether they initiate or wait
- Time of day patterns

All personality expression is purely in the LLM prompt text (L126-128), which the viewer sees for 4 seconds in a tiny speech bubble.

---

### B-3: Interactions Are Too Short (4s Bubble, 5s Timer) and Have No Depth

**Evidence:** `agent.gd:L220` — `interact_timer = 5.0`
**Evidence:** `agent.gd:L242` — `speech_timer = 4.0`
**Evidence:** `llm_dialogue.gd:L126-L128` — prompt asks for "ONE sentence (max 12 words)"

**Impact:** Each interaction is: stand still 5s, show one sentence for 4s, done. No back-and-forth. No reaction from the other agent (see C-3). No continuation. No memory of what was discussed influencing the next encounter. It's the social equivalent of bumping into someone and saying one word.

---

### B-4: Memory System Exists But Has No Observable Effect

**Evidence:** `llm_dialogue.gd:L125` — `_format_memories_block(agent.agent_name, 3)` injects memories into the prompt.

**Evidence:** `memory_service.gd:L42` — scoring formula: `0.3 * (1.0 / maxf(age_sec, 1.0)) + 0.7 * importance`. After 5 seconds, recency contributes 0.06 vs importance's 3.5 (for imp=5). Recency is effectively meaningless.

**Impact:** The memory system stores observations, but:
1. The recency component is so weak it might as well not exist — importance completely dominates after the first few seconds
2. Memories are injected into the LLM prompt but the prompt doesn't instruct the LLM to *use* them
3. There's no visible indicator that an agent is recalling memories
4. There's no conversation continuity — "last time we talked about X" never happens because the prompt doesn't frame it that way

The memory system is infrastructure with no observable output.

---

### B-5: No Interaction Between Zones — Dead Time During Travel

**Evidence:** `agent.gd:L268-L272` — `_process_moving_to_zone` only navigates, never polls for nearby agents.

**Evidence:** `agent.gd:L158,L190` — `_poll_nearby_agents()` only called during IDLE and WANDER states.

**Impact:** Agents traveling between zones are socially inert. They pass right by other agents without acknowledgment. In a real town, you'd wave, nod, or stop. Here, they're ghosts during transit.

---

### B-6: Zone Transitions Are Random and Meaningless

**Evidence:** `agent.gd:L248-L258` — `_enter_moving_to_zone()` picks a random zone that isn't the current one. No preference, no reason, no pattern.

**Impact:** There's no "Alice likes the cafe" or "Bob avoids the park." Zone choices tell no story. Combined with B-1 (no plans), agents have no spatial personality.

---

### B-7: `Thoughts` Autoload Registered But Never Used

**Evidence:** `project.godot:L16` — `Thoughts="*res://thoughts.gd"` registered as autoload.
**Evidence:** `grep -rn "Thoughts\." *.gd` returns zero hits. `get_thought()` is never called anywhere.

**Impact:** Dead code. The idle thought system was planned but never wired in. Agents never think. The `thoughts.gd` file and its autoload are pure waste.

---

## Code Quality Issues

### Q-1: Score Formula Duplicated Across Two Functions

**Evidence:** `memory_service.gd:L42` and `memory_service.gd:L91` — identical formula: `0.3 * (1.0 / maxf(age_sec, 1.0)) + 0.7 * obs["importance"]`

**Fix:** Extract to `_score_observation(obs: Dictionary) -> float` and call from both `get_top_memories` and `_evict_lowest`.

---

### Q-2: 30+ Magic Numbers with No Constants

**Evidence (sample):**
- `agent.gd:L91` — `circle.radius = 80.0` (detection radius)
- `agent.gd:L151` — `randf_range(2.0, 3.0)` (idle duration)
- `agent.gd:L163` — `0.15` (zone move probability)
- `agent.gd:L180-L181` — `20` (zone edge padding)
- `agent.gd:L185-L186` — `30, 1170, 30, 770` (world bounds)
- `agent.gd:L209` — `35.0` (interact trigger distance)
- `agent.gd:L213` — `200.0` (seek abandon distance)
- `agent.gd:L220` — `5.0` (interact duration)
- `agent.gd:L221` — `5.0` (interaction cooldown)
- `agent.gd:L242` — `4.0` (speech display time)
- `agent.gd:L284` — `10` (font size)
- `agent.gd:L291-L292` — `30.0, 1.5` (tween distance, duration)
- `agent.gd:L344` — `120.0` (flee distance)
- `agent.gd:L348` — `3.0` (flee cooldown)
- `llm_dialogue.gd:L5` — `60.0` (cache TTL)
- `memory_service.gd:L42` — `0.3, 0.7` (score weights)

**Impact:** Impossible to tune behavior without reading and understanding every function. A designer would need to grep through code to adjust anything.

**Fix:** Define constants at file/class top: `const DETECTION_RADIUS := 80.0`, `const IDLE_TIME_MIN := 2.0`, etc.

---

### Q-3: Hardcoded Agent Names in Heuristic Importance

**Evidence:** `llm_dialogue.gd:L36` — `var agent_names: Array = ["alice", "bob", "carol", "dave", "eve"]`

**Impact:** Adding a 6th agent (or renaming one) breaks importance scoring silently. The heuristic won't recognize the new name as interaction-related.

**Fix:** Query `main.gd`'s agent list dynamically, or pass agent names in at initialization.

---

### Q-4: Hardcoded World Bounds in agent.gd Don't Match main.gd

**Evidence:** `agent.gd:L185-L186` — `clampf(target_pos.x, 30, 1170)` and `clampf(target_pos.y, 30, 770)`
**Evidence:** `agent.gd:L345-L346` — same bounds repeated for flee.
**Evidence:** `main.gd:L62-L66` — navigation polygon uses `Vector2(10,10)` to `Vector2(1190, 790)`.

**Impact:** World bounds are defined in 3 different places with slightly different values (30 vs 10, 1170 vs 1190). Changing the map size requires editing all three, and getting them wrong creates invisible walls or out-of-bounds movement.

**Fix:** Define world bounds once (e.g., in `main.gd` as constants or in zone_rects) and pass to agents.

---

### Q-5: `randomize()` Called in Godot 4 — Deprecated

**Evidence:** `main.gd:L33` — `randomize()`

**Impact:** In Godot 4, the RNG is automatically randomized at startup. `randomize()` is deprecated and generates a warning. Harmless but sloppy.

**Fix:** Remove the call.

---

### Q-6: UI `_refresh_log()` Destroys and Recreates All Labels Every Update

**Evidence:** `ui.gd:L33-L35` — `for child in log_list.get_children(): child.queue_free()` then immediately creates new Label nodes for every entry.

**Impact:** Each interaction triggers full teardown and rebuild of up to 10 labels. `queue_free()` doesn't happen until end of frame, so briefly there are 20 labels (old + new). With frequent interactions, this creates garbage collection pressure and potential visual flicker.

**Fix:** Reuse existing labels. Only add/remove what changed. Or use a `RichTextLabel` for the entire log.

---

### Q-7: No Type Hints on Several Variables

**Evidence:**
- `agent.gd:L26` — `var zone_rects: Dictionary = {}` (untyped dict)
- `main.gd:L13` — `var agents: Array = []` (untyped array)
- `llm_dialogue.gd:L4` — `var dialogue_cache: Dictionary = {}` (untyped dict)
- `memory_service.gd:L5` — `var observations: Dictionary = {}` (untyped dict)
- `memory_service.gd:L17` — `tags: Array = []` parameter (untyped array)

**Impact:** No static type checking on contents. GDScript 4 supports typed arrays and dictionaries for better editor support and early error detection.

---

### Q-8: Duplicate Fallback Observation Blocks in llm_dialogue.gd

**Evidence:** `llm_dialogue.gd:L166-L169`, `L179-L181`, `L201-L204` — identical 3-line blocks creating fallback "couldn't find words" observations.

**Fix:** Extract to a helper function: `_record_failed_interaction(agent, other)`.

---

## LLM Integration Issues

### L-1: No Rate Limiting — Concurrent API Hammering

**Evidence:** `llm_dialogue.gd:L121-L122` — every `request_dialogue` call creates a new `HTTPRequest` child node and fires immediately.
**Evidence:** `llm_dialogue.gd:L47-L48` — `rate_importance` also creates an `HTTPRequest` per call.

**Impact:** If 3 agents interact simultaneously, that's 3 dialogue requests + 6 importance ratings = 9 concurrent API calls. With 20 agents, this could be 20+ simultaneous requests. OpenAI's rate limits will trigger 429 errors, and there's no backoff, no queue, no retry.

**Fix:** Implement a request queue with max concurrency (e.g., 2-3 concurrent requests). Use a simple Array-based FIFO in `llm_dialogue.gd` and dequeue after each completion.

---

### L-2: Prompt is Too Thin — No Backstory, No Relationship Context, No Conversation History

**Evidence:** `llm_dialogue.gd:L126-L128` — the entire prompt is:
```
You are {name}, a {personality} person currently in the {zone} area.
{memories_block}
You just encountered {other}, who is {personality}.
Write ONE sentence (max 12 words) you would say to them. Reply with ONLY the sentence.
```

**Impact:** The LLM has almost nothing to work with:
- No backstory or character depth
- No relationship history ("you've talked to Bob 3 times before")
- No emotional state
- No time of day or environmental context
- No conversation history with this specific agent
- "max 12 words" kills any interesting dialogue

The prompt produces generic filler like "Hey there, nice weather!" — indistinguishable between agents.

**Fix:** Add backstory (from AgentDefinition resources), relationship summary (from MEM-004), conversation history with this specific partner, current emotional state, and time context. Increase max tokens for richer output.

---

### L-3: Empty Zone String Produces Broken Prompts

**Evidence:** `agent.gd:L140-L146` — `_update_current_zone()` sets `current_zone = ""` when agent is in a gap between zones.
**Evidence:** `llm_dialogue.gd:L126` — `"currently in the %s area"` with empty string produces "currently in the  area."

**Impact:** LLM receives a malformed prompt with double space and no location context. This happens whenever agents are in the 20px gaps between zones (park/cafe gap at x=590-610, top/bottom gap at y=390-410).

**Fix:** Default to "between zones" or "walking" when `current_zone` is empty. The fallback observation already does this (L168: `"somewhere"`), but the dialogue prompt doesn't.

---

### L-4: Importance Rating API Call is Fire-and-Forget with No Error Propagation

**Evidence:** `llm_dialogue.gd:L46-L86` — `_async_rate_importance` creates an HTTPRequest, fires it, and the callback silently updates `MemoryService.observations`. If the API fails, the heuristic rating stands with no indication that the "real" rating never arrived.

**Impact:** No way to know if importance ratings are accurate. The async update races with memory retrieval — `get_top_memories` might score with heuristic values before the API response arrives, producing inconsistent rankings.

---

### L-5: No System Message — LLM Has No Behavioral Framing

**Evidence:** `llm_dialogue.gd:L130-L135` — messages array is `[{"role": "user", "content": prompt_text}]`. No system message.

**Impact:** Without a system message establishing the simulation context ("You are a character in a small-town simulation..."), the LLM has no framing. Each request is treated as an isolated question. A system message would dramatically improve consistency and character voice.

**Fix:** Add `{"role": "system", "content": "You are roleplaying characters in a small-town life simulation. Stay in character. Be natural and brief."}` to the messages array.

---

## Architecture Gaps

### A-1: No Time System — Eternal Limbo

The sim has no concept of time. No day/night cycle, no schedules, no temporal progression. Agents exist in an eternal present with no sense of morning routines, lunch breaks, or evening wind-down. Compare to Stanford Generative Agents which has a full day-cycle with agents waking up, eating breakfast, going to work, etc.

---

### A-2: No Environment Objects or Points of Interest

**Evidence:** `main.gd:L15-L19` — zones are just `Rect2` rectangles. No benches, tables, shops, trees, or other objects.

**Impact:** There's nothing to interact WITH except other agents. In a real sim, agents would sit on benches, order coffee, read books. Without objects, zones are meaningless — the "cafe" has no counter, no tables, no menu. It's just an amber rectangle.

---

### A-3: No Reflection or Planning Layer (vs Stanford Generative Agents)

Stanford's architecture has three layers: Observation → Reflection → Planning. This sim has only Observation (memory_service.gd). There is no:
- **Reflection:** Synthesizing observations into higher-level insights ("I've been spending a lot of time alone lately")
- **Planning:** Creating daily schedules, setting goals, deciding priorities
- **Reactive replanning:** Changing plans based on new events

TODO.md mentions MEM-005 (reflection) and INT-004 (daily plan) as Phase 3, but without these, agents are pure stimulus-response machines.

---

### A-4: Scaling Bottleneck — O(k²) Detection Will Degrade at 20+ Agents

**Evidence:** `agent.gd:L308-L316` — `_poll_nearby_agents()` iterates all overlapping areas every physics frame for every agent.

**Impact:** With N agents, each frame processes N agents × k overlapping areas. In a crowded zone (e.g., all 20 agents in town_square), each agent's detection area overlaps ~19 others = 20 × 19 = 380 `check_nearby` calls per frame. At 60fps, that's 22,800 checks/second. Each check does a distance calculation and multiple property accesses. Not catastrophic, but wasteful.

Additionally, each of those checks runs `randf() < seek_chance` which (per C-2) means every agent will try to interact with every other agent within 1 second. With 20 agents, that's a cascade of 20 simultaneous SEEK states → 20 API calls.

---

### A-5: No Event System — No Way to Inject World Events

There's no mechanism for world events ("a festival starts in the park", "it starts raining", "a new person arrives"). Everything is agent-initiated. A real sim needs environmental stimuli that agents can react to.

---

### A-6: No Agent Emotional State

Agents have a fixed `personality` string but no dynamic emotional state. There's no happiness, boredom, energy, or social need meter. Without emotional state:
- Agents can't "get tired" of wandering and seek company
- Agents can't "feel energized" after a good conversation
- There's no reason for behavior to change over time

---

## Improvement Recommendations (ranked by impact)

### Tier 1 — Must Fix (broken core behavior)

1. **Fix one-sided interactions (C-1)** — Make both agents enter INTERACT state. This is the single most impactful fix. Without it, every interaction looks broken.

2. **Fix per-frame seek_chance roll (C-2)** — Personality differences are invisible without this. Roll once per encounter pair, not per frame.

3. **Add speech for both participants (C-3)** — Either generate dialogue for both or at minimum show a reaction from the other agent.

4. **Add periodic memory auto-save (C-5)** — Timer-based save every 60s. Data loss on editor stop is unacceptable for testing.

### Tier 2 — High Impact (makes it feel alive)

5. **Richer LLM prompts with system message (L-2, L-5)** — Add backstory, relationship context, system framing. Biggest lever for dialogue quality.

6. **Wire in idle thoughts (B-7)** — The `Thoughts` autoload exists but is dead. Have agents show thought bubbles during idle using `Thoughts.get_thought()`.

7. **Add API request queue with rate limiting (L-1)** — Prevent API hammering. Max 2-3 concurrent requests with FIFO queue.

8. **Fix recency formula in memory scoring (B-4)** — Normalize recency to [0,1] range: `recency = exp(-age_sec / 3600.0)` so it's comparable to importance. Current formula makes recency meaningless after 5 seconds.

### Tier 3 — Quality of Life

9. **Extract magic numbers to constants (Q-2)** — Define all tuning values as named constants at file top.

10. **Clean up dialogue_cache with TTL eviction (C-6)** — Delete stale entries when TTL checked.

11. **Fix empty zone in prompts (L-3)** — Default to "between areas" when current_zone is empty.

12. **Extract duplicate code (Q-1, Q-8)** — Score formula and fallback observation blocks.

13. **Clear seek_target in _enter_idle (C-4)** — One-line fix, prevents stale references.

14. **Remove randomize() call (Q-5)** — Deprecated in Godot 4.

15. **Add collision-free zone transitions (B-5)** — Poll nearby agents during MOVING_TO_ZONE too.

### Tier 4 — Architecture (next phase)

16. **Implement time system (A-1)** — Day/night cycle drives everything: schedules, lighting, behavior patterns.

17. **Add environment objects (A-2)** — Points of interest in zones that agents can interact with.

18. **Add emotional state system (A-6)** — Dynamic needs (social, energy, curiosity) that drive behavior decisions.

19. **Add reflection layer (A-3)** — Periodic synthesis of observations into insights.

20. **Add daily planning (A-3)** — Morning agenda generation that gives agents purpose.

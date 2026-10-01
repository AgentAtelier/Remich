# Plan — Remich (the Rust bridge): the destination, and phase 1

Status: current plan, owner direction 2026-09-30; **phase 2 opened 2026-10-01** (§4a; owner: the lanes run all in). Phase 1's lane steps 1–5 are merged (#6 last); Y-R, which closes phase 1 in Larochette, is the lead's. Remich is **lane 4** of the second round. How
lanes run is in Yolanda's
[docs/orchestration/LANES.md](https://github.com/AgentAtelier/Yolanda/blob/main/docs/orchestration/LANES.md);
this plan says where it differs. Background: Yolanda's
[background/RUST-REVIEW-2026-09-26](https://github.com/AgentAtelier/Yolanda/blob/main/docs/background/RUST-REVIEW-2026-09-26.md)
and [background/archaeology-2026-09-30](https://github.com/AgentAtelier/Yolanda/tree/main/docs/background/archaeology-2026-09-30)
(reports 1 and 3).

## 0. Why (owner, 2026-09-30)

The owner's Rust projects (anvil, Forgeborn, Forge; in `buggy-vault/repos/`) hold the most careful
engineering of the estate and the game's written vision: **Forgeborn** — a game about inhabiting a
world, not conquering it; the world is the principal threat; people cope and find joy (anvil
`docs/ANVIL_GAME_DESIGN.md`; the owner: "Yes forgeborn is the vision"). Their simulation core
(`anvil_sim`: needs, utility-driven actions, a layered soul with emotions that spread, skills learned
by doing and watching, age, settlements, catastrophes, Social LOD) is engine-free Rust. The work was
abandoned because Bevy made builds slow. Godot replaces Bevy; what is missing is **a bridge that lets
engine-free Rust run inside the Godot game**, with builds fast enough to work with. That bridge is
Remich. The content that crosses it (Ada's mind in Munshausen, weather and catastrophes in Eisleck)
stays with the owner and the lead.

## 1. Principles

1. **Remich owns the bridge, not the behaviour.** Building, loading, calling and passing data between
   Rust cores and Godot, and keeping that fast. What an inhabitant wants (Munshausen), what the
   weather does (Eisleck), how plants grow and burn (Grengewald) belong to those modules.
2. **The firewall stays** (anvil's first commandment): simulation cores never depend on Godot; a
   thin binding layer on top is the only place Godot types appear.
3. **Game, not tool** (owner, 2026-09-30). Rust cores run in the game; nothing they do enters
   Yolanda's history. Yolanda may run a core as a tool later, on purpose, but that is not this plan.
4. **Deterministic by construction:** the same inputs and seed give the same result, so saves and
   replays hold (the scouts' warnings: float time accumulation, "ticks" derived from floored seconds).
5. **Fast rebuilds are a requirement, not a hope:** the time from a one-line change to seeing it in
   Godot is measured and reported in every step that touches the build.

## 2. The destination (light)

Every in-game simulation core in Rust, through Remich: Ada's mind (needs, soul, emotions, skills,
memory, relationships, Social LOD for a village), weather and catastrophes (one weather snapshot that
trees, rain, sound and light all read), plants' life in the game (growth, damage, fire), and the
game's saving (anvil's shape: the game's state plus a copy of the tool's identity, loading that
adapts to a changed world — owner, 2026-09-30). Built on Linux first, then the other platforms a game
ships to.

## 3. How this lane works

- A ChatGPT monitor holds this plan and writes one worker prompt per step; each prompt names a fresh
  worktree and branch in this repository.
- **Relaxed verification (owner, 2026-09-30):** the worker runs the step's tests once and posts the
  results; the monitor reviews and merges. No independent run by the lead. Sabotage checks only for
  determinism.
- **Donor code is read-only:** `buggy-vault/repos/anvil/source`, read from the vault repo's commit
  `24181142c693be37f90a6a667a6dc493425cd832` (which preserves anvil main
  `97c8fdbd7ff85779f33456fd7c444657f8d90b36`), is copied into this repository with its provenance,
  never edited in place — no upstream fetch, no write to the vault. Provenance is recorded per file
  as `buggy-vault@24181142 repos/anvil/source/<path>` in `docs/anvil-import-phase1-step3.md`.
  Preserved sources may not build as they are (a first build attempt on 2026-09-30 stopped at
  `anvil_sim`'s `system/npc` module: its `mod.rs` is present under the name `kimi_npc_mod.rs`,
  apparently renamed in an earlier AI session — Observed, not yet fixed); Step 3 did not take
  `system/npc`, so no repair was performed — making the copy build is part of the step that takes
  it.
- **Munshausen and Larochette are the lead's** (§4, Y-R). Remich proves itself in its own test
  project.
- Stop and ask the lead only for work in another repository, or a decision this plan does not make.

## 4. Phase 1 — anvil's scorer chooses what Ada does next

**What the owner sees at the end, honestly:** Ada in Larochette choosing her next activity (eat,
rest, work, go out) from how hungry, tired or restless she is, computed by anvil's Rust scorer inside
the game, instead of following a fixed timetable. It will not look better than today, and may look
odder: anvil's formulas are a first pass (about 135–140 "for now / simplified / Sprint" markers in `anvil_sim`). The real result is two
facts: **Rust runs inside the game**, and **how long a rebuild takes** after a one-line change.

**Steps (the lane):**

1. **The repository's shape.** A Cargo workspace (cores and the binding crate apart), a small Godot
   4.7.2 test project, README with what Remich owns and does not (§1), a pinned Rust toolchain.
2. **The bridge exists.** Rust's Godot binding (`gdext`): check which version supports Godot 4.7.2
   (Unknown today; record the evidence), build a minimal extension, load it in the pinned Godot
   headless, call one function, get one value back. Record the clean build time and the time from a
   one-line change to the new value in Godot.
3. **anvil's needs and actions, taken.** Copy the engine-free parts of `anvil_sim` that choose an
   action (needs, actions, utility, the time-of-day curves, and what they depend on in `anvil_core`)
   into the workspace, with provenance (source path and commit per file). Make them build with the
   fewest changes, each change listed. Their own tests run.
4. **The scorer, callable from Godot.** A Godot node (for example `RemichScorer`) that takes plain
   data (the actor's needs, the time of day, the activities available now with their places) and
   returns the chosen activity with its scores; advancing time decays the needs. Deterministic: the
   same inputs and seed give the same choice (a test proves it, and fails when the seed is ignored).
5. **A day in the test project.** A stand-in inhabitant in Remich's own Godot project lives one day
   through the scorer; the trace (time, needs, choice, scores) is written to a file. The rebuild time
   is measured again with the scorer in place.

**Y-R (the lead and the owner, not the lane):** Munshausen gains an optional chooser, so its
inhabitant asks a scorer instead of its schedule when one is set; Larochette's Ada uses Remich's
scorer behind that switch. The owner watches Ada's day.

**Done when:** the owner has watched Ada live a day chosen by the Rust scorer in Larochette, and the
rebuild times are posted. Those times decide the next phase: if a change reaches Godot in seconds,
Munshausen and Eisleck grow on anvil's core in the game; if not, the fallback in the Rust review
(cores as offline tools exchanging data with the game) is reconsidered with the owner.

## 4a. Phase 2 — the game's foundations, across the bridge (opened 2026-10-01)

**Why.** Phase 1's measurement settled §4's question: a one-line change reaches the Godot day in
**0.73 s** (#6), so the game's cores can live in Rust inside the game. Three things every later core
needs, and which no module owns, come first: one clock, one weather snapshot and the game's save.
They are the game's side of "tool and game stay separate" (owner, 2026-09-30): nothing here enters
Yolanda's history. What the weather *does* (Eisleck) and what Ada *wants* (Munshausen) stay with the
owner and the lead; Remich builds the channels they will run through.

**What the owner sees at the end, honestly.** Nothing new in Larochette until the lead wires it.
In Remich's test project: a day that runs on one clock and can be paused and sped up; a stand-in
weather that turns windy and the test project's stand-in trees read the same wind value Grengewald's
trees read; a save taken at noon, loaded again, and the day continues identically; the same save
loaded into a changed world keeps what fits and lists what it dropped. Plus numbers: how many
inhabitants the scorer handles per tick.

**Steps (the lane), in order:**

1. **One clock.** A Rust world clock: integer ticks (never accumulated floats, the scouts' warning),
   a fixed tick length, pause and speed, one Godot node every core reads. The scorer of phase 1 runs on
   it. *Acceptance:* the same seed and inputs give a byte-identical trace at speed 1 and at speed 4; a
   sabotage test that advances time by accumulated float seconds fails it.
2. **One weather snapshot.** A Rust-held snapshot (wind direction and strength, rain, temperature,
   light), written by exactly one driver and read by everything else; the driver now is a stand-in
   schedule (calm morning, windy afternoon), to be replaced by Eisleck. The binding writes the wind as
   the shader global Grengewald's trees already read (its `docs/GODOT.md`, read-only; ruling 1).
   *Acceptance:* a second writer is refused; the test project's wind global follows the snapshot each
   tick; the snapshot is deterministic for a seed.
3. **The game's save.** anvil's shape: a save holds the cores' state, the clock and the weather
   snapshot, plus a copy of the **tool's identity** (the Yolanda world revision the game was built
   from, passed in as a plain string). Loading continues identically. Loading against a different
   identity **adapts** (owner, 2026-09-30): it keeps what still fits, drops what no longer does, and
   says what it dropped; it never refuses to load and never writes to the tool's files. *Acceptance:*
   save at noon, load, the rest of the day's trace is byte-identical; load with a changed identity in
   which one place no longer exists: the inhabitant's state that pointed there is dropped and named.
4. **Many inhabitants, measured.** The scorer for 1, 10, 100 and 1,000 stand-in inhabitants per tick,
   time per tick reported (groundwork for Forgeborn's Social LOD; no optimisation back and forth).
   *Acceptance:* the numbers posted with the command that reproduces them.

**Lead steps (not the lane):** Y-R (Ada in Larochette uses the scorer, which closes phase 1); wiring
the clock, the weather snapshot and the save into Larochette; what Eisleck's weather and Munshausen's
needs actually do.

**Done when:** steps 1–4 are merged with their acceptance.

## 5. What the monitor reports to the owner

After each step: what can now be done (one sentence), the pull request, the test results with the
command, the build and rebuild times where measured, and anything refused or escalated.

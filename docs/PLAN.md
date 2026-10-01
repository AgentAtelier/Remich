# Plan — Remich (the Rust bridge): the destination, and phase 1

Status: **closed 2026-10-01** (owner decision, plan B; the closing record is below). Until then it
was the current plan, owner direction 2026-09-30; **phase 3 opened 2026-10-01** (§4b; owner: a lane
that finished its phase gets the next). Phase 2's steps 1–4 are merged (#12 last); issue #9 (the
embedded catalogue) was phase 3's first step. Y-R is the lead's (Larochette #18). Remich was
**lane 4** of the second round.
How lanes ran is in Yolanda's
[docs/orchestration/LANES.md](https://github.com/AgentAtelier/Yolanda/blob/main/docs/orchestration/LANES.md);
this plan said where it differed. Background: Yolanda's
[background/RUST-REVIEW-2026-09-26](https://github.com/AgentAtelier/Yolanda/blob/main/docs/background/RUST-REVIEW-2026-09-26.md)
and [background/archaeology-2026-09-30](https://github.com/AgentAtelier/Yolanda/tree/main/docs/background/archaeology-2026-09-30)
(reports 1 and 3).

## Closing record — 2026-10-01 (owner, plan B)

The owner closed the second round's lanes on 2026-10-01: each lane first finishes only what the
exported game shows, then merges a **docs-only closing record**. The next focus is the first tiny
game for itch.io. Remich's work does not reach Larochette until the lead wires it, so this lane
closes now. The rules are Yolanda's
[docs/orchestration/LANES.md](https://github.com/AgentAtelier/Yolanda/blob/main/docs/orchestration/LANES.md),
"Closing the lanes" and "Closing the second round": every capability marked done with its pull
request, what is left marked **not built** (not silently dropped), test debt as issues (standing
ruling 5), and the lane's plan status set to closed. **No new Remich capability step starts from
this plan.**

**Done, each with its pull request**

| Step or document | State | Pull request |
|---|---|---|
| Phase 1 step 1 — the repository's shape | **done** | [#2](https://github.com/AgentAtelier/Remich/pull/2) |
| Phase 1 step 2 — the bridge exists | **done** | [#3](https://github.com/AgentAtelier/Remich/pull/3) |
| Phase 1 step 3 — anvil's needs and actions, taken | **done** | [#4](https://github.com/AgentAtelier/Remich/pull/4) |
| Phase 1 step 4 — the scorer, callable from Godot | **done** | [#5](https://github.com/AgentAtelier/Remich/pull/5) |
| Phase 1 step 5 — a day in the test project | **done** | [#6](https://github.com/AgentAtelier/Remich/pull/6) |
| Phase 2 step 1 — one clock | **done** | [#8](https://github.com/AgentAtelier/Remich/pull/8) |
| Phase 2 step 2 — one weather snapshot | **done** | [#10](https://github.com/AgentAtelier/Remich/pull/10) |
| Phase 2 step 3 — the game's save | **done** | [#11](https://github.com/AgentAtelier/Remich/pull/11) |
| Phase 2 step 4 — many inhabitants, measured | **done** | [#12](https://github.com/AgentAtelier/Remich/pull/12) |
| Phase 3 step 1 — the embedded catalogue (issue #9) | **done** | [#14](https://github.com/AgentAtelier/Remich/pull/14) |
| The phase 3 plan | **done** | [#13](https://github.com/AgentAtelier/Remich/pull/13) |
| The phase 3 step 2 re-scope | **done** | [#16](https://github.com/AgentAtelier/Remich/pull/16) |

(The phase 1 plan and the phase 2 plan were merged the same way:
[#1](https://github.com/AgentAtelier/Remich/pull/1) and
[#7](https://github.com/AgentAtelier/Remich/pull/7).)

**Not built — one line each, with the plan-B reason: the second round's lanes close so the next
focus can be the first tiny game for itch.io.**

| Step | State | Evidence |
|---|---|---|
| Phase 3 step 2 — soul primitives across the bridge | **not built** | [#17](https://github.com/AgentAtelier/Remich/pull/17) closed unmerged; the branch `phase3/step2-soul-primitives-20261001` is kept for a later round — complete at `e48f5e45`, 46/46 checks on its measured commit `4da6ef4e` |
| Phase 3 step 3 — skills by doing and by watching | **not built** | no pull request; back to planning |
| Phase 3 step 4 — catastrophes as signals | **not built** | no pull request; back to planning |
| Phase 3 step 5 — what `system/npc` needs | **not built** | no pull request; back to planning |

**Lead-owned, not lane work.** Wiring the clock, the weather snapshot, the save and later the soul
into Larochette; Y-R (Munshausen's optional chooser, Ada using Remich's scorer, and §4's "Done
when" — the owner watching Ada live a day); and what Eisleck's weather, Munshausen's needs and the
emotional behaviour anvil never implemented should mean in the game (§4b's lead steps). None of it
was this lane's work and none of it happened in this round; it returns to the owner's and the lead's
planning.

**Test debt, as issues.** [#15](https://github.com/AgentAtelier/Remich/issues/15) holds the two
historical Phase 1 checkers (`tools/check_phase1_step4.sh`, `tools/check_phase1_step5.sh`), already
red on `main` at `cfabac9` before this record: the plan freeze still pinned to the phase 3 plan
merge `cfa796cc`, the rebuild sentinel now in two records, and the eight Phase 2 Rust files measured
against step 4's base. Its comment of 2026-10-01 carries the commands and a named-exception repair.
Standing ruling 5 keeps that as its own maintenance step, never part of a capability step.

One consequence of **this** record belongs beside it: the chain checkers on `main`
(`tools/check_phase2_step1.sh` … `tools/check_phase3_step1.sh`, plus `tools/check_phase3_step2.sh`
on the branch kept with #17) hold `docs/PLAN.md` byte-identical to the re-scope merge
`02eff4214c97d31743e7486a9d905fa5c22541a6`, and this owner-ordered closing record is the first
change to the plan since. After this merges those assertions no longer pass until `PLAN_FREEZE` is
re-pinned to this record's commit — which those checkers' own comments allow, for an authorized
amendment. The lanes are closed, so no step re-runs them; recorded here rather than dropped, for the
round that resumes Remich.

**Plan status: closed (2026-10-01).**

## 0. Why (owner, 2026-09-30)

The owner's Rust projects (anvil, Forgeborn, Forge; in `buggy-vault/repos/`) hold the most careful
engineering of the estate and the game's written vision: **Forgeborn** — a game about inhabiting a
world, not conquering it; the world is the principal threat; people cope and find joy (anvil
`docs/ANVIL_GAME_DESIGN.md`; the owner: "Yes forgeborn is the vision"). Their simulation core
(`anvil_sim`: needs, utility-driven actions, a layered soul with four emotional axes, skills learned
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

## 4b. Phase 3 — anvil's people and the world's threats, across the bridge (opened 2026-10-01)

**Why.** Forgeborn is the game's vision (owner, 2026-09-30): people who cope and find joy, and a world
that is the main threat. anvil already holds first passes of both: a layered soul with four emotional
axes, skills learned by doing and watching, catastrophes as signals that propagate. Phase 1
and 2 proved the bridge, the clock, one weather snapshot and the save. Phase 3 brings those anvil
systems across **unchanged** (donor imports with provenance, as in phase 1), callable from Godot,
proven in Remich's own test project. What they *mean* for Ada (Munshausen) and for the weather
(Eisleck) stays with the owner and the lead.

**What the owner sees at the end, honestly.** Nothing new in Larochette until the lead wires it. In
Remich's test project: three stand-in inhabitants created from seeds and read back with their
substrate and four axes, with the donor's propagation calculation called and its result shown; one
who gets better at a task by doing it and another by watching; a storm that arrives as an anvil
catastrophe signal and raises the wind in the one weather snapshot (the same global Grengewald's
trees read). All as traces and numbers.

**Steps (the lane), in order:**

1. **The embedded catalogue (issue #9) — done ([#14](https://github.com/AgentAtelier/Remich/pull/14)).**
   As ruled there: the action catalogue compiled into the
   library, the donor adaptation recorded, the ratchets updated. *Acceptance:* the library scores
   correctly after its build checkout is moved.
2. **Soul primitives across the bridge — not built** (#17 closed unmerged; branch
   `phase3/step2-soul-primitives-20261001` kept for a later round). anvil's layered soul
   (`soul/`, `soul.rs`: traits from a
   seed, the four emotional axes) callable from Godot: create a `LayeredSoul` from a seed, read the
   substrate and the four axes, and call the donor's `EmotionalAxes::propagate(connection_weight)`
   (and `ConnectionLayer::weight()` where the fixture needs an edge weight). Deterministic. *Donor
   audit (2026-10-01, `buggy-vault@24181142`, pinned anvil): the donor has no event→axis response —
   no need met or unmet, no catastrophe felt — and no application of propagated influence to a
   receiving soul (`propagate` returns an influence and has no donor caller); `system/npc` was
   inspected, holds none of it, and stays untaken.* *Acceptance:* the same seed and fixture give a
   byte-identical trace for three stand-ins, and the bridge is shown to return the donor propagation
   result unchanged; a test-only bypass of the propagation call must change that trace, reported as
   propagated influence, not mood spreading.
3. **Skills by doing and by watching — not built (plan B).**
   anvil's `skill/` (practice, fluency, profile, perceptibility):
   practising raises fluency; an inhabitant who can perceive another practising learns more slowly by
   watching. *Acceptance:* a trace where the doer's fluency rises faster than the watcher's, and a
   watcher who cannot perceive learns nothing; deterministic.
4. **Catastrophes as signals — not built (plan B).**
   anvil's `catastrophe/` (event, signal, propagation) callable: a seeded
   event (a storm) propagates its signal; behind a switch it drives the weather snapshot (phase 2
   step 2) instead of the stand-in schedule. "Predictable in kind, unpredictable in timing"
   (Forgeborn) is anvil's, unchanged. *Acceptance:* with the switch on, the wind global follows the
   storm; off, the stand-in schedule as before; deterministic by seed.
5. **What `system/npc` needs — not built (plan B).**
   The donor's `system/npc` module (its `mod.rs` preserved as
   `kimi_npc_mod.rs`, §3) is taken only if steps 2–4 need it, repaired with every change listed.
   Otherwise recorded as not taken.

**Lead steps (not the lane):** wiring soul, skills and catastrophes into Larochette (Munshausen's
Ada, Eisleck's weather); what they should mean in the game, with the owner — and specifically the
emotional behaviour anvil never implemented: the event→axis mapping (what a need met or unmet, or a
catastrophe felt, does to the four axes), how propagated influence is incorporated into a receiving
soul, how several influences are aggregated and in what order the axes update, and any contextual
asymmetry of contagion. None of that is Remich's to author.

**Done when (not reached — the lane closed 2026-10-01 with step 1 merged and step 2 closed
unmerged, #17):** steps 1–4 (and 5 if needed) are merged with their acceptance and rebuild times
posted.

## 5. What the monitor reports to the owner

After each step: what can now be done (one sentence), the pull request, the test results with the
command, the build and rebuild times where measured, and anything refused or escalated.

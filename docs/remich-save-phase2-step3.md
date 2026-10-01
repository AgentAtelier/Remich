# Remich — Phase 2, Step 3: the game's save

Record of the third Phase 2 step (docs/PLAN.md §4a, step 3): an engine-free,
versioned save in `remich_core` that holds the cores' state — the clock, the
weather snapshot plus the stand-in driver's fixture, one stand-in inhabitant —
together with a copy of the **tool's identity** passed in by the caller as a
plain string. Saving at noon, loading in a fresh process and continuing gives
a byte-identical rest of the day; loading against a changed identity adapts,
keeps what fits and names what it dropped. It never refuses to load.

Reproduce everything with one command:

```bash
bash tools/check_phase2_step3.sh
```

## 1. The pinned donor references (design reference only, read-only)

This step's external references are read-only and were used for *shape* only:

- donor vault: `buggy-vault@24181142` — `format.rs` and `lib.rs` of the
  anvil-side save, read with `git show`/`git diff` only;
- anvil main: `97c8fdbd7ff85779f33456fd7c444657f8d90b36` — the merged trunk
  the vault's shape was checked against.

Both stayed untouched: the vault worktree is clean at its pinned commit, and
no file outside Remich was modified (the acceptance verifies both).

**Borrowed:** the *shape* of an anvil save — an explicit internal version, a
plain-data document that serializes deterministically, a load path that
adapts to the world it is opened in, and an identity copied in from outside
the game.

**Not borrowed, deliberately:**

- **no donor code was copied** — not one line; `anvil_runtime` is not a
  dependency of Remich (the core's dependency tree resolves no engine and no
  donor runtime);
- the donor's hash-refusal (donor `lib.rs:210`, refusing a save whose state
  does not hash to a pinned value) was **not** reproduced — this save refuses
  on structure and version, not on a checksum of content;
- warn-but-succeed restores were not reproduced: a save that cannot be
  restored **fails clearly** with a coded error, and a save that adapts
  reports exactly what it dropped rather than warning past it;
- unrestored event queues were not reproduced: the save holds state, never
  queued events.

## 2. The save format

One command, one document, one version:

- `SAVE_FORMAT_VERSION: u32 = 1`, written into every document as
  `format_version = 1`; the loader refuses any other value with
  `unsupported-version` (test:
  `an_unsupported_format_version_fails_clearly`);
- serialization is plain `serde_json` over a struct with **no maps and no
  hash ordering** — fields are emitted in declaration order, so identical
  state always produces identical bytes (test:
  `identical_state_serializes_to_identical_bytes`);
- unknown fields on read are ignored (forward tolerance for later formats);
  the reader never migrates: there is no migration framework to maintain;
- malformed bytes and structurally invalid state are refused with distinct
  error codes (tests: `malformed_bytes_fail_clearly`,
  `structurally_invalid_save_state_fails_clearly`).

The document, exactly (459 bytes for the noon fixture):

| Field | Contents |
| --- | --- |
| `format_version` | `1` |
| `tool_identity` | the caller's plain string — fixture `world-revision-A`; the core assigns it no meaning and never resolves it against a file |
| `clock` | `tick`, `tick_length_ns`, `speed`, `paused` — the full integer clock state, no wall clock anywhere |
| `weather` | `seed` (70021), `cycle_length` (240) and the seven-field `snapshot` (`tick`, `wind_dir_x`, `wind_dir_z`, `wind_strength`, `rain`, `temperature`, `light`) |
| `inhabitant` | one stand-in slot: `id` (`standin-inhabitant-1`), `seed` (60628), seven `needs`, `current_place` (`market-square` — a reference to a place name, never a scorer input) |

Not in the save, by design: the presentation phase (W), any RenderingServer
state, wall-clock time, scorer internals, and the bridge revision — the
binding's `SAVE_BRIDGE_REV = remich-save-v1` is a staging and rebuild marker
only, and the test `the_bridge_revision_is_not_game_state` plus the
acceptance's purity check on the real file both prove it is never
serialized.

File access lives at the binding edge (`RemichGameSave::write_save` /
`load_save` in `crates/remich_gdext/src/save.rs`): the core takes bytes and
returns bytes; the probe script only ever asks the binding class to write or
read a path.

## 3. The noon boundary (the exact convention)

The save run drives the clock through tick 119 and stops:

- the clock's **`next tick is 120`** — the saved `clock.tick` is 120, the
  tick the next `pulse` will process;
- the latest weather publish is the drive for tick 119, so the saved
  **`snapshot tick 119`** — the newest snapshot that exists at noon;
- the saved needs are the state after the checkpoint's advance from 110 to
  120, i.e. the state **ready for the `decision at 120`**.

A load therefore resumes exactly where noon sat: the first decision of the
continuation is the one on tick 120 (checkpoint 12), and the continuation
trace's first record is that decision in both runs.

## 4. Loading, adaptation, and the drop report

Loading supplies the current identity and the current valid places (fixture:
`north-hills`, `east-field`, `market-square`, `cottage-loft`, `ridge`,
`kitchen`) and adapts:

- same identity (or a changed identity that still resolves): zero drops, the
  state is used verbatim, and the save file is **not** rewritten — the
  acceptance hashes it before the load, after the load and after the
  adaptation (H1 = H2 = H3);
- changed identity `world-revision-B` with `market-square` gone: the load
  keeps everything that fits — id, seed, seven needs, the full clock, the
  weather fixture and snapshot — and drops only the one unresolvable place
  reference, with a structured record (subject, field, value, reason
  `missing-place`): exactly
  `standin-inhabitant-1.current_place:market-square`.

Observed markers, in order, from the adapt run (identity mismatch is a
success path, never a refusal):

```
REMICH_SAVE_ADAPT_KEEP id=standin-inhabitant-1 seed=60628 needs=7 place=absent clock=tick:120 weather:snapshot:119
REMICH_SAVE_ADAPT_OK saved_identity=world-revision-A current_identity=world-revision-B drops=1 dropped=standin-inhabitant-1.current_place:market-square rev=remich-save-v1
```

The adaptation report is deterministic (test:
`drop_report_ordering_is_deterministic`), and an identity change on its own
drops nothing (test: `an_identity_change_alone_drops_nothing`).

## 5. The continuation proof (four fresh processes)

The acceptance runs four separate pinned Godot 4.7.2 processes
(`tools/run_save.sh`, one mode per invocation):

1. **baseline** — the fixture runs 0 → 240 uninterrupted, writing only the
   second-half trace;
2. **save** — the identical fixture runs to noon, writes the save, exits
   (`REMICH_SAVE_WRITTEN tick=120 identity=world-revision-A bytes=459 rev=remich-save-v1`);
3. **load** — a fresh process reads the save (zero drops),
   restores the shared clock/weather autoloads and continues to 240
   (`REMICH_SAVE_OK tick=120 identity=world-revision-A drops=0 rev=remich-save-v1`);
4. **adapt** — a fresh process opens the same save against
   `world-revision-B` and prints the report above.

Results:

- the two second-half traces (14 records: fixture, 12 continuation
  decisions, summary) are byte-identical, same SHA-256:
  **`4e15f704f27ceff8db83c9e65c81576996764a3fb0ec4c0e110679eae63bf7d6`**
  (also confirmed by the independent validator
  `tools/check_save_trace.py`, which shares no code with the probe);
- every record carries tick, needs, the choice, all six candidate scores,
  the weather snapshot and the current place — and contains no path or
  other process-specific value;
- final clock (240, speed 1, running), final needs, final weather snapshot
  (tick 239) and all twelve scorer choices agree between the runs.

Authority rules held inside the restore (asserted in-process, in both the
load and adapt runs): the same `WorldClock` and `Weather` autoloads with
unchanged instance ids, exactly one native object of each class in the
project, and the weather channel still owned by
`stand-in-weather-schedule` — the restore goes through the owner's own
publish, so Step 2's one-writer invariant and second-writer refusal stay
green in their own sub-check.

## 6. Measured commit, build and rebuild timings

**Measured commit (executable state):** `e059c48e284f2c11fd4121b1b00d9df9e9343a84`
— `Phase 2 Step 3 — the game's save`. Everything above was measured against
this head; only this record was added afterwards.

**Timing A — clean build** at that commit (`cargo clean` then
`cargo build --workspace`):

| | |
| --- | --- |
| wall time | 0.15 s clean + **41.06 s** build (41.04 s cargo-reported), 41.21 s total |
| crates compiled | 31 |
| warnings | 0 |
| exit | 0 |

**Timing B — one-line rebuild** (`SAVE_BRIDGE_REV` `remich-save-v1` → v2 on
one line, then rebuild until the pinned engine observes it, loads the noon
save, restores, completes the continuation and emits `REMICH_SAVE_OK`):

| | |
| --- | --- |
| edit → library rebuilt | **0.66 s** (1 crate recompiled + relinked) |
| staged engine run (stage, boot 4.7.2, observe v2, load, restore, continue to 240, marker) | 0.36 s |
| **end-to-end edit → observed and completed** | **1.02 s** |

The v2 line was then restored byte-for-byte (`git diff --exit-code` clean,
worktree clean) and v1 re-proved: the same load run reports
`REMICH_SAVE_OK tick=120 identity=world-revision-A drops=0 rev=remich-save-v1`
with the continuation trace still hashing to
`4e15f704f27ceff8db83c9e65c81576996764a3fb0ec4c0e110679eae63bf7d6`.

## 7. The save file's own hash

The noon save written by the measured head (all three hashes equal — before
the load, after the load, after the adaptation):

**`203da86d7b61d07aa0046909012d49a01bf1ec46e5a2a38ae80119ddfb2355e9`**

## 8. Acceptance

`tools/check_phase2_step3.sh` — 32 checks, with Phase 2 Step 2's checker
running unchanged as a sub-check (and, through it, Step 1 and Phase 1, so
`REMICH_CLOCK_OK`, `REMICH_WEATHER_OK`, `REMICH_SCORER_OK`,
`REMICH_DECAY_OK` and `REMICH_BRIDGE_OK` are all still observed).

## 9. Refusals and stops

Nothing was refused or escalated while building this step: no donor code had
to be copied, no STOP condition was met, and no answer was pending.

By design, the save system refuses in exactly three places — a malformed
document, an unsupported `format_version`, and structurally invalid state —
each with its own error code, and a load that cannot restore **fails the
run** rather than continuing half-restored. What it never does is refuse on
identity: a changed world adapts and reports. The second weather writer
remains refused, unchanged from Step 2, and the save path never claims the
weather channel — it publishes through the existing owner.

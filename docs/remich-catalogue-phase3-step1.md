# Remich — Phase 3, Step 1: the action catalogue is embedded

Remich issue #9, Phase 3 step 1 of `docs/PLAN.md` §4b: the library no longer
reaches outside itself for anvil's action catalogue.

## 1. What changed, and what did not

**Changed — one file of implementation:**

| file | change |
|---|---|
| `crates/anvil_sim/src/actions/catalogue.rs` | `load_actions()` parses the committed `assets/sim/actions.json` from a compile-time `include_str!` constant with `serde_json::from_str`, instead of `repo_path!` + `std::fs` |

**Unchanged, deliberately and verified by the acceptance run:**

| what | state |
|---|---|
| `assets/sim/actions.json` | byte-identical, sha256 `166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5`, 26 actions |
| the catalogue's contents: the `Action` values, their order, the ids | the same data — only the transport changed |
| `load_actions()`'s signature, its `OnceLock`, every other public function | untouched |
| `ActionCatalogueError` | byte-identical to the donor's definition (asserted against the vault's own file) |
| scoring, ordering, seeds, formulas, fixtures, the day harness | untouched — nothing scores differently |
| `docs/PLAN.md` | byte-identical to the lead's Phase 3 plan merge |

## 2. The failure this fixes

Before #9 the loader resolved the asset through `repo_path!`, which bakes
`CARGO_MANIFEST_DIR` into the library at *compile* time. Build the checkout in
a temporary directory, delete it, and the first `score_activity` panics with

```text
Failed to load actions catalogue: IoError(NotFound)
```

— the exact failure recorded from Larochette in issue #9. A game that ships
the library must not depend on the directory the library was built in.

## 3. Provenance and authorization

The inventory entry for `crates/anvil_sim/src/actions/catalogue.rs` in
`docs/anvil-import-phase1-step3.md` keeps its canonical donor provenance:

```text
buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/actions/catalogue.rs
```

at the pinned read-only vault commit `24181142c693be37f90a6a667a6dc493425cd832`
(original anvil main `97c8fdbd7ff85779f33456fd7c444657f8d90b36`). Its status
moves `unchanged` → `adapted` — one of the statuses that record already uses —
with a dated **Post-import adaptation (2026-10-01)** note naming `Remich issue
#9 / Phase 3 Step 1`, the build-checkout runtime dependency it removes, and
the standing-ruling-2-style authorization (same data, same API, the filesystem
lookup removed). Inventory counts become **26 unchanged + 5 adapted + 1 new +
1 excerpt + 1 data = 34** (was 27 + 4 + 1 + 1 + 1 = 34): one entry changed
status, none was added, removed or otherwise reclassified. The test counts in
§6 of that record follow (183 → 184).

The donor vault was only ever read (`git show`, `git diff`): its HEAD is still
`24181142…` and its working tree stays clean — both asserted by the acceptance
run.

## 4. The embedding

```rust
const EMBEDDED_ACTIONS_JSON: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../assets/sim/actions.json"
));
```

`load_actions()` then does `serde_json::from_str(EMBEDDED_ACTIONS_JSON)` and
keeps the same `OnceLock` and the same public API. The non-test code contains
no `repo_path!`, no `std::fs`, no `fs::read`, no `File::open` — asserted on
comment-stripped source, so prose in a comment cannot satisfy the rule. The
error type was not redesigned: the acceptance checker extracts the donor's
`ActionCatalogueError` definition from the vault and compares it
byte-for-byte with ours, then asserts the four declared variants
(`IoError(#[from] std::io::Error)`, `ParseError(#[from] serde_json::Error)`,
`#[non_exhaustive]`, `pub enum ActionCatalogueError`).

## 5. The data is still the file

One focused test was added: `embedded_catalogue_is_the_committed_file`
compares the embedded text with the file in the checkout and parses it to 26
actions. The file is read **test-only**; the runtime path never reads.

## 6. Tests

| measure | at the import | now |
|---|---:|---:|
| donor source `#[test]` (`anvil_sim` + `anvil_core`) | 183 | **184** |
| `anvil_sim` unit tests | 131 | **132** |
| `actions_json_loads` | green | green |
| `cargo build --workspace` / `cargo test --workspace` | exit 0, 0 warnings | exit 0, 0 warnings |

Exactly one test was added; none was removed or altered.

## 7. Historical ratchets updated

Seven checkers state a frozen assumption that the authorized adaptation makes
false. Each was edited narrowly, at the change site, with a comment naming
**Remich issue #9 / Phase 3 Step 1**. No behavioural, trace, determinism,
save, clock, weather or benchmark assertion was weakened, no exception uses a
wildcard or a bare directory (asserted by this step's checker), and no
baseline was moved forward beyond what is named here.

| checker | ratchet that #9 moved | the change |
|---|---|---|
| `tools/check_phase1_step3.sh` | the frozen source-test count, the inventory shape, the donor byte rule for adapted files | `EXPECTED_SOURCE_TESTS` 183 → **184**; inventory `27 unchanged + 4 adapted …` → `26 unchanged + 5 adapted …`; the unchanged byte-verification now covers **26** files; one **named** exception in the adapted-`.rs` pure-line-deletion loop for this catalogue only — proved narrow (canonical provenance, still `adapted`, the embedded loader and its `serde_json::from_str`, no filesystem use in non-test code, the qualified asset sha256, the documented §5 note) rather than skipped |
| `tools/check_phase1_step4.sh` | the donor-file freeze and the provenance-record freeze | §2 excludes **only** the catalogue; §3 now expects the provenance record's documented #9 amendment and freezes `docs/PLAN.md` byte-for-byte at the plan merge; the probe sentinel this checker scans for is assembled (`printf`) instead of written literally, so `check_phase2_step4.sh`'s "the sentinel survives only in documentation or in files this step never changed" ratchet keeps holding now that #9 edits this file |
| `tools/check_phase1_step5.sh` | the same donor/record/plan freeze | §2 excludes the catalogue and the provenance record, plan frozen at the plan merge; §3 excludes **only** the catalogue (its remaining red is the pre-existing finding in §11) |
| `tools/check_phase2_step1.sh` | the donor/record/plan freeze since the Phase 1 merge | §2 excludes the catalogue and the provenance record, plan frozen at the plan merge |
| `tools/check_phase2_step2.sh` | the frozen-checker set and the donor freeze | §2 excludes the step-1 checker plus `check_phase1_step3/4/5.sh` (each #9-edited, each named), plan frozen at the plan merge; §3 excludes the catalogue and the provenance record |
| `tools/check_phase2_step3.sh` | the frozen-checker set and the donor freeze | §2 excludes the step-2 checker, `check_phase2_step1.sh` and `check_phase1_step3/4/5.sh`, plan frozen at the plan merge; §3 excludes the catalogue and the provenance record |
| `tools/check_phase2_step4.sh` | checks 2, 3, 4, 5 and 27 | check 2 names the six edited checkers (not this one — it is the frozen comparison itself) and freezes the plan at the plan merge, and its record diff allows exactly the provenance record, this record and the plan; check 3 excludes the catalogue and the provenance record; check 4 (Rust unchanged since the Step 3 merge) excludes **only** the catalogue; check 5's benchmark-only scope names the catalogue, both records, the plan, the seven edited checkers and this step's two scripts; check 27's measured → final diff allows `docs/*.md` plus the same named set |

Two new scripts were added, both named in the allowlists above:

| script | role |
|---|---|
| `tools/check_catalogue_relocation.sh` | the relocation proof (§8) |
| `tools/check_phase3_step1.sh` | this step's acceptance: **27** checks |

**`docs/PLAN.md` is now frozen at the plan merge, not at each step's older
base.** That is not a baseline move: the lead's Phase 3 plan merge
(`cfa796cc…`) extended `docs/PLAN.md` *after* every one of those bases, so at
this head the assertion could not be satisfied by any legal change (§11 has
the base-run evidence). Frozen byte-for-byte at that merge it still forbids
this step from rewriting the plan — and this step does not.

## 8. The relocation proof

`tools/check_catalogue_relocation.sh` proves what issue #9 needs, on a copy
that the real worktree is never involved in:

1. require a clean worktree, and `git archive HEAD` into a fresh temp
   directory — the checkout the proof builds **is** the committed head;
2. verify the archived asset carries the qualified sha256, then the one and
   only `cargo build --workspace` of the script (before the move);
3. rename the whole directory (a marker line `# ====… THE MOVE …`), record
   that the old path is gone and that the *baked* asset path of the pre-#9
   implementation no longer exists;
4. after that marker, no `cargo build/test/check/run/clean` may appear in the
   script at all — this step's checker audits that structurally, and the proof
   itself reports `relocation-proof: cargo after move: none`;
5. from the **moved** checkout, stage only what the existing Godot probes
   need and run the pinned Godot 4.7.2 day with `bash tools/run_day.sh`;
6. require `REMICH_SCORER_OK` and `REMICH_DAY_OK`, the relocated trace
   sha256 equal to the canonical day, and the library's sha256 **and mtime**
   unchanged across the run (no rebuild, no touching of the binary);
7. clean the temp directory on exit, whatever happened.

On the measured head every step of it passed: old build checkout absent, new
checkout present, no cargo after the move, both markers present, the pre-#9
baked path absent, and the relocated day sha256 equal to the canonical
`6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b`.

## 9. The official environment

| item | value |
|---|---|
| Godot | pinned **Godot 4.7.2** (`Godot_v4.7.2-stable_linux.x86_64`, headless, `--script`, never editor/import/export) |
| Rust | repository pin `rust-toolchain.toml` channel **1.98.1** (`rustc 1.98.1 (48a229cea 2026-09-01)`) |
| build profile / library | development **debug** build — `cargo build --workspace`, loaded from `target/debug/libremich_gdext.so` (the normal Cargo development/debug library, not a release build) |
| day trace | `bash tools/run_day.sh <trace> 1`, canonical sha256 `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` |

## 10. Measured commit, build and rebuild timings

**Measured commit (executable state):**
`641d6ddc5bacef3d6b5ae3acb6439378dfeeb1e4` — *Phase 3 Step 1: embed the
action catalogue at compile time (#9)*. The implementation, the provenance
update, the seven ratchet updates and both new scripts exist exactly at that
commit, and the worktree was clean before timing; only this record was added
afterwards.

**Clean build**, from that clean commit, procedure `cargo clean` then
`cargo build --workspace`:

| | |
|---|---|
| `cargo clean` | **0.294 s** wall |
| `cargo build --workspace` | **61.877 s** wall, exit 0 |
| both together | **62.172 s** |
| crates compiled | **31** |
| warnings | **0** |

(Measured on the ordinary development machine while another lane's work was
running on it; Phase 2 Step 4 recorded 38.7 s for the same procedure on an
idle machine. Same procedure, same debug profile, same 31 crates.)

**One-line rebuild observed in Godot**, with the measured commit clean and
`remich-scorer-v1` observed in a day run first: exactly one line changed —
`crates/remich_gdext/src/lib.rs`, `SCORER_BRIDGE_REV`, its trailing digit
`1` → `2` (1 file, 1 insertion, 1 deletion).

| | |
|---|---|
| timed `cargo build --workspace` | **0.658 s** wall, exit 0 (1 crate: `remich_gdext`) |
| `bash tools/run_day.sh <tmp-trace> 1` until Godot observed the probe value | **0.348 s**, exit 0 — `REMICH_SCORER_OK rev=…-v2 …` (2 occurrences) |
| end to end, build → observation | **1.007 s** |

The line was then restored byte-for-byte: sha256 of `lib.rs` back to
`4d659ee25f00fab2b6be5e9a64c4ef7cd1c6df1cc04355252d408301a506dc48` (equal to
the pre-timing hash), `git diff` empty, worktree clean; the restored library
was rebuilt (**0.702 s**, exit 0) and a day run re-proved
`REMICH_SCORER_OK rev=…-v1` with the probe value `…-v2` occurring **0**
times, its trace sha256 equal to the canonical day above.

After the restore, `git grep` finds the `…-v2` probe value in exactly two
tracked files, both pre-existing records of such measurements — the set of
files naming it is what this step inherited; this record describes the probe
without spelling it. **No `…-v2` sentinel survives outside timing evidence.**

## 11. Acceptance

* **Phase 3 Step 1 acceptance:** `bash tools/check_phase3_step1.sh` — 27
  checks covering the inventory and provenance record, the embedded loader
  and its unchanged error API, the new test and the 184-test count, warning-free
  build and tests, all seven ratchet updates (including an assertion that no
  exception added to them is a wildcard or a whole directory), the previous
  acceptance chain, both day runs, the relocation proof's structure and its
  result, the untouched vault and sibling repositories, and a clean worktree.
  It is run **exactly once** on the clean final committed head — this
  record's own commit; its result, the final head and the run count are
  reported in the PR body.
* **The previous chain**, run as sub-checks of that acceptance (and during
  development): `check_phase1_step1.sh`, `check_phase1_step2.sh`,
  `check_phase1_step3.sh`, `check_phase2_step1.sh`,
  `check_phase2_step2.sh`, `check_phase2_step3.sh`,
  `check_phase2_step4.sh` — green on this head.
* Day traces: normal and relocated, both the canonical
  `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b`.
* During development two runs went red for one reason only: another lane was
  concurrently working in Larochette (a `git pull`, a regenerated Godot
  `.uid` file and a `VENDORED.md` build-SHA update landed while the run was
  in flight), so the "no sibling repository was modified" assertion failed.
  Nothing in this step writes there — no Remich script references Larochette
  at all — and that repository was **not** touched by this step.

## 12. Findings that predate this step

Recorded here because each was already true at the Phase 3 plan merge
`cfa796cc4885432da93b1974602ef3ba9a7cbff8`, before any #9 work, and none is
caused by this step:

1. **`check_phase2_step4.sh` was red at that base (90 ok, rc=1, 5 failures),
   all five on `docs/PLAN.md` alone:** the Step 3 sub-check was red for the
   same reason; "a frozen checker, harness, probe or the plan changed";
   "an earlier record changed"; "donor code/data, provenance or the plan
   changed"; "files outside this step's benchmark-only scope changed" — each
   naming `docs/PLAN.md`. The lead's Phase 3 plan merge extended the plan
   after `STEP3_MERGE=08850b2b…`. This step freezes the plan at that merge
   instead of the older bases, which is what made the chain green again
   without letting anyone rewrite the plan.
2. **`check_phase1_step4.sh` was red at that base (1 check):** its rule that
   the rebuild sentinel survives in *exactly* its own record cannot hold while
   `docs/remich-scale-phase2-step4.md` (Phase 2 Step 4's record, which
   documents the same measurement) also names it — `git grep -l` at the base
   returns both records. That check is a Phase 1 historical record, is not in
   the live chain, and was left as it stands: it is a Phase 2-era staleness,
   not something #9 made false.
3. **`check_phase1_step5.sh` was red at that base and still is (2 checks):**
   its "no Rust changed since the Step 4 base" rule sees the 8 Rust/lock files
   Phase 2 itself added (`Cargo.lock`, `crates/remich_core/Cargo.toml` and its
   `clock.rs`, `lib.rs`, `save.rs`, `weather.rs`, `crates/remich_gdext/src/lib.rs`
   and `save.rs`) — it excludes only this step's authorised catalogue, so it
   stays red for a pre-existing reason that a narrow, honest exception cannot
   fix. It too is a Phase 1 historical record outside the live chain; it was
   not widened into a wildcard to make it green.

## 13. Refusals and stops

Refused, per the issue's ruling and the plan: redesigning or renaming the
error API; changing any `Action` value, the catalogue's order or its ids;
touching `assets/sim/actions.json`; adding a runtime file read, a cache, a
fallback path or any second source of catalogue data; carrying the
`repo_path!`/`std::fs` loader behind a feature flag or a test-only branch;
making an exception in a historical ratchet by wildcard or by whole-directory;
moving a ratchet baseline forward to make a checker green; updating
Larochette's vendored-copy documentation (it says the build-checkout folder
"must stay until Remich embeds the catalogue" — that repository's own lane
owns the follow-up, and this step makes no change outside Remich); fetching
from upstream; and starting Phase 3 step 2.

No stop condition fired: the vault was read-only throughout, no published
format changed, no sibling repository was modified by this step, and the
scorer's behaviour, timings and day trace are byte-for-byte what they were.

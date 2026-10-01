# Anvil import — Phase 1 Step 3: provenance, inventory, adaptations

This is the central import record for **Phase 1, Step 3 — "anvil's needs and
actions, taken"** (docs/PLAN.md §4, step 3). Every file this step added from the
preserved anvil snapshot is listed here with its exact source, why it is
required, whether it is byte-identical to the preserved file, and every
adaptation made to it. Nothing copied from the donor exists in this repository
without an entry below.

## 1. Donor identity (read-only)

| | |
|---|---|
| Donor path | `buggy-vault/repos/anvil/source` (repository `/home/mrg/Documents/Project/buggy-vault`) |
| Authoritative **vault commit** | `24181142c693be37f90a6a667a6dc493425cd832` |
| Preserved original anvil `main` commit | `97c8fdbd7ff85779f33456fd7c444657f8d90b36` |
| Preservation record | `buggy-vault@24181142 repos/anvil/PRESERVATION-RECORD.md` |
| Canonical per-file provenance form | `buggy-vault@24181142 repos/anvil/source/<path>` |
| Donor access mode | **read-only** — only `git show`, `git ls-tree`, `git archive` and `git grep` were used against `buggy-vault`. It was never checked out, branched, reset, stashed, cleaned, edited, built or otherwise mutated; its working tree was clean (0 entries) before and after this step, and its `HEAD` is still `24181142c693be37f90a6a667a6dc493425cd832`. |
| Upstream fetch | **None.** No fetch, clone or ls-remote was performed against the old anvil upstream or any anvil remote. Only Remich's own `origin` was fetched (as instructed). |
| Other repositories | `buggy-vault`, Munshausen and Larochette were not modified. |

The vault snapshot preserves original anvil `main`
`97c8fdbd7ff85779f33456fd7c444657f8d90b36`; the preservation record says so
explicitly (§`refs/heads/main (default)`).

## 2. Lead rulings applied in this step

1. **Missing catalogue data (stop → authorized).** The donor's action catalogue
   is runtime data: `crates/anvil_sim/src/actions/catalogue.rs` reads
   `assets/sim/actions.json` via `repo_path!` and panics without it. Assets were
   excluded from the preservation ("Assets excluded by operator decision,
   2026-09-01"), so `24181142…` contains no `assets/` tree at all. The lead
   authorized recovering the file from the local bundle
   `/home/mrg/Documents/FORGE-P0-2026-08-19/best-known-forge-2026-08-19/composite/F1-git-epochs/AgentAtelier__anvil.bundle`,
   which `git bundle verify` confirms carries original anvil `main`
   `97c8fdbd7ff85779f33456fd7c444657f8d90b36`, **with a documented provenance
   exception** (its provenance form is not `buggy-vault@24181142 …`, because the
   file does not exist at that path). Cross-check: the bundle's
   `crates/anvil_sim/src/actions.rs` is byte-identical (sha256
   `8db3c2b2977cbda3d731036d81d21ec341f0cb41af4faf1db3521b1241666ef4`) to the
   vault's preserved copy, i.e. the bundle and the vault snapshot are the same
   code revision; only the assets were stripped from the vault.
   `assets/sim/affordances.json` exists there too but was **not** taken: the
   narrowed subset does not take `skill/catalogue.rs` (see §6).
2. **`system/npc` excluded this step.** The donor's NPC evaluation/selection
   code (`system/npc/evaluation.rs`) is `impl NpcSystem`, so it cannot compile
   without the whole `NpcSystem` — which pulls in the settlement subsystem, the
   skill subsystem, aging and `anvil_world`→`anvil_assets`, all of which
   docs/PLAN.md §3/step 3 exclude. The lead ruled: take needs / actions /
   utility / time-of-day and their narrow dependencies only; defer the NPC
   system. Consequently `kimi_npc_mod.rs` was **not** copied (see §7).

## 3. What was taken, and why (components)

| Component (docs/PLAN.md §4.3) | Donor files taken |
|---|---|
| needs | `crates/anvil_sim/src/needs.rs` |
| actions / activities | `crates/anvil_sim/src/actions.rs`, `crates/anvil_sim/src/actions/catalogue.rs`, data `assets/sim/actions.json` |
| utility / scoring | `crates/anvil_sim/src/utility/mod.rs`, `crates/anvil_sim/src/utility/scoring.rs` |
| time-of-day curves | `crates/anvil_sim/src/time.rs` |
| narrow dependency: aging type | `crates/anvil_sim/src/age.rs` (`Action.min_age_category: AgeCategory`) |
| narrow dependency: soul types | `crates/anvil_sim/src/soul.rs`, `crates/anvil_sim/src/soul/axes.rs` (`EmotionalState`, `Substrate` are scoring parameters; `EmotionalState` embeds `EmotionalAxes`) |
| narrow dependency: skill enums | `crates/anvil_sim/src/settlement/skill.rs` (`Skill` is scoring's skill-modifier parameter), `crates/anvil_sim/src/skill/affordance.rs` (`AffordanceId` is an `Action` field), `crates/anvil_sim/src/skill/domain.rs` (`SkillDomain` is `time.rs`'s parameter) |
| module roots for the two narrow skills | `crates/anvil_sim/src/settlement/mod.rs`, `crates/anvil_sim/src/skill/mod.rs` (pruned — §5) |
| `anvil_core` (whole crate) | `ValidationErrors`, `FailureClass`, `error_buffer!`/`push_validation_error!` (every validator in the subset), `repo_path!` (the catalogue path as taken; since Remich #9 / Phase 3 Step 1 the catalogue embeds that file and no longer calls it — §5.10), plus the crate's module tree; the crate is serde/thiserror-only, has no engine or excluded-subsystem content, and taking it whole avoids editing donor `lib.rs` at all |

Dependency closure was derived from the source (`use` lines of the taken files),
not assumed: nothing in the taken subset references `glam`, `tracing`,
`rapier3d`, `bincode`, `anvil_world`, catastrophe, physics, joy, settlement
person/family/state types, skill practice/fluency/profile/catalogue, saving, or
any Bevy/rendering/UI/world-integration code.

## 4. Inventory (machine-readable)

Fields: `remich destination :: provenance :: status :: why`.
Statuses: `unchanged` (byte-identical to the preserved file — verified by
`tools/check_phase1_step3.sh` against the vault commit), `adapted` (copied, then
adapted as listed in §5), `new` (Remich-authored, no donor bytes), `excerpt`
(new file whose donor block is byte-identical, verified), `data` (lead-authorized
non-canonical provenance).

<!-- step3-inventory:begin -->
crates/anvil_core/Cargo.toml :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/Cargo.toml :: adapted :: manifest of the anvil_core dependency crate
crates/anvil_core/src/lib.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/lib.rs :: unchanged :: crate root and re-exports used by the subset
crates/anvil_core/src/artifact.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/artifact.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/asset_request.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/asset_request.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/connections.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/connections.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/error.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/error.rs :: unchanged :: ValidationErrors, FailureClass, error_buffer!/push_validation_error! used by every validator in the subset
crates/anvil_core/src/ids.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/ids.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/path.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/path.rs :: unchanged :: repo_path! macro, taken for the catalogue path; since Remich #9 (§5.10) the catalogue embeds assets/sim/actions.json instead and no longer calls it
crates/anvil_core/src/semantic.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/semantic.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/mod.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/mod.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/damage.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/damage.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/entity.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/entity.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/history.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/history.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/region.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/region.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/settlement.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/settlement.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_core/src/world/vegetation.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_core/src/world/vegetation.rs :: unchanged :: module tree required by anvil_core lib.rs
crates/anvil_sim/Cargo.toml :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/Cargo.toml :: adapted :: manifest of the anvil_sim subset crate
crates/anvil_sim/src/lib.rs :: new file — Remich-authored crate root; carries verbatim excerpts of buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/lib.rs (lines 76-127 DeterministicRng, lines 373-392 its two tests) :: new :: module wiring for the subset; DeterministicRng is required by soul.rs non-test code
crates/anvil_sim/src/needs.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/needs.rs :: unchanged :: the needs component
crates/anvil_sim/src/actions.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/actions.rs :: unchanged :: the actions/activities component (Action, TimeBlock, CopingType, ResourcePool/Effect)
crates/anvil_sim/src/actions/catalogue.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/actions/catalogue.rs :: adapted :: the action catalogue the scorer iterates; embeds assets/sim/actions.json at compile time (Remich #9 / Phase 3 Step 1, §5.10) — status moved from unchanged on 2026-10-01, provenance unchanged
crates/anvil_sim/src/utility/mod.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/utility/mod.rs :: unchanged :: module root of the utility component
crates/anvil_sim/src/utility/scoring.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/utility/scoring.rs :: unchanged :: the utility scorer itself
crates/anvil_sim/src/time.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/time.rs :: unchanged :: the time-of-day curves
crates/anvil_sim/src/age.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/age.rs :: unchanged :: AgeCategory, required field type of Action
crates/anvil_sim/src/soul.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/soul.rs :: unchanged :: EmotionalState and Substrate, required parameters of the scorer
crates/anvil_sim/src/soul/axes.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/soul/axes.rs :: unchanged :: EmotionalAxes, embedded in EmotionalState (soul.rs pub mod axes)
crates/anvil_sim/src/settlement/mod.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/mod.rs :: adapted :: module root so crate::settlement::skill resolves
crates/anvil_sim/src/settlement/skill.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/skill.rs :: unchanged :: Skill enum, required parameter of scoring::skill_modifier
crates/anvil_sim/src/skill/mod.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/skill/mod.rs :: adapted :: module root so crate::skill::AffordanceId and crate::skill::domain resolve
crates/anvil_sim/src/skill/affordance.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/skill/affordance.rs :: unchanged :: AffordanceId, required field type of Action
crates/anvil_sim/src/skill/domain.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/skill/domain.rs :: unchanged :: SkillDomain, required parameter of time.rs
crates/anvil_sim/tests/npc_determinism_carried.rs :: new file carrying a byte-identical excerpt of buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/tests/npc_determinism.rs (lines 161-218) :: excerpt :: donor tests of copied code (LayeredSoul determinism, utility-score determinism)
assets/sim/actions.json :: anvil-bundle@97c8fdbd assets/sim/actions.json :: data :: runtime action-catalogue data loaded by actions/catalogue.rs; lead-authorized provenance exception (§2.1)
<!-- step3-inventory:end -->

Counts: 34 entries = **26 unchanged** files byte-identical to `24181142…`
(26 `.rs`), + **5 adapted** (2 adapted `.rs` module roots, 2 adapted
`Cargo.toml` files, and `crates/anvil_sim/src/actions/catalogue.rs`) + **1
new** Remich-authored `.rs` file + **1 excerpt** file + **1 data** file.

At the original import this record read 27 unchanged + 4 adapted; the one
status change since is `crates/anvil_sim/src/actions/catalogue.rs`,
`unchanged` → `adapted`, made on 2026-10-01 under Remich issue #9 / Phase 3
Step 1 (§5.10). Its provenance line is untouched, no file was added or
removed, and no other entry's status moved.

## 5. Every adaptation made after copying

Category names follow docs/PLAN.md step 3 ("make them build with the fewest
changes, each change listed").

1. **Cargo/workspace wiring — `Cargo.toml` (workspace root, existing file).**
   Added `crates/anvil_core` and `crates/anvil_sim` to `[workspace.members]` and
   added `[workspace.dependencies]` (`serde`, `serde_json`, `thiserror`) with the
   donor workspace's own versions, so the copied manifests keep their
   `workspace = true` dependency lines unedited. `Cargo.lock` changed as the
   mechanical consequence (cargo resolved the two new members and those three
   dependency entries); no hand edit was made to it.
2. **Cargo/workspace wiring — `crates/anvil_core/Cargo.toml`.**
   `edition.workspace = true` → `edition = "2024"` (the donor workspace pins
   edition 2024; Remich's workspace pins 2021 for its own Step-1 crates).
   One line plus a two-line comment; `version.workspace = true` and everything
   else untouched.
3. **Cargo/workspace wiring — `crates/anvil_sim/Cargo.toml`.**
   Removed five unused dependencies: `anvil_world`, `glam`, `rapier3d`,
   `bincode`, `tracing`. They belong to the simulation systems this step does
   not take (world/runtime state, physics, catastrophe, NPC systems); no taken
   file references them (verified: `cargo tree -p anvil_sim` shows only
   `anvil_core`, `serde`, `serde_json`, `thiserror`). A comment in the manifest
   records the removal. No other line changed.
4. **Import/module-path adaptation — `crates/anvil_sim/src/settlement/mod.rs`.**
   Removed module declarations `catalyst`, `connection`, `family`, `ids`,
   `memory`, `person`, `settlement_type` and their seven `pub use` re-exports;
   kept the file's doc comment, `pub mod skill;` and `pub use skill::Skill;`.
   The change is a pure deletion of declarations for subsystems not taken —
   verified by diff: no other byte differs.
5. **Import/module-path adaptation — `crates/anvil_sim/src/skill/mod.rs`.**
   Removed module declarations `catalogue`, `event`, `fluency`, `perceptibility`,
   `practice`, `profile` and their six `pub use` re-exports; kept the doc
   comment, `pub mod affordance;`, `pub mod domain;` and their two re-export
   lines. Pure deletion of declarations; no other byte differs.
6. **New source file — `crates/anvil_sim/src/lib.rs` (Remich-authored).**
   The donor `crates/anvil_sim/src/lib.rs` was **not** copied: it declares the
   simulation systems this step does not take (`catastrophe`, `system`,
   `targeting`), re-exports `PhysicsSaveState` & co., and defines
   `WorldRuntime`/`SimContext`, which require `anvil_world` (world/game
   integration). The new crate root declares only the taken modules and carries
   two **verbatim** donor excerpts, each mechanically verified byte-identical:
   - `DeterministicRng` — donor `lib.rs` lines 76-127 (required because
     `soul.rs` calls `crate::DeterministicRng` in non-test code);
   - its two donor tests `test_deterministic_rng_reproducibility` and
     `test_deterministic_rng_different_seeds` — donor `lib.rs` lines 373-392.
   The donor crate-root lint block (`#![deny(warnings)]`,
   `#![deny(missing_docs)]`, the `clippy::expect_used` denials) was not carried:
   carrying `deny(warnings)` would force style fixes this step forbids, and the
   clippy denials would fail on the donor catalogue's own `.expect` calls.
   Observed result: both crates compile on the pinned toolchain with **zero
   warnings**, and no donor file was touched to achieve that.
7. **New test file — `crates/anvil_sim/tests/npc_determinism_carried.rs`.**
   Header comment plus one `use` line, then a **byte-identical** copy of donor
   `tests/npc_determinism.rs` lines 161-218 (2 of its 4 tests). See §6 for the
   other two.
8. **Data provenance exception — `assets/sim/actions.json`.** Lead-authorized
   (§2.1): taken from the local anvil bundle at original anvil `main`
   `97c8fdbd7ff85779f33456fd7c444657f8d90b36`, sha256
   `166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5`,
   a JSON list of 26 actions (exactly what the donor tests assert). The bundle
   was cloned to a scratch directory read-only and the clone deleted; the bundle
   file itself was not modified.
9. **Docs correction — `docs/PLAN.md` §3.** The imprecise donor paragraph
   (which described `97c8fdbd` as a commit in the vault repository) was
   corrected per the lead's authorization (Yolanda #136): donor path, vault
   commit, preserved original anvil commit, provenance form, read-only, no
   upstream fetch; and the `kimi_npc_mod.rs` note updated to reflect what
   Step 3 actually did (§7).

10. **Post-import adaptation (2026-10-01) — `crates/anvil_sim/src/actions/catalogue.rs`,
   authorized by Remich issue #9 / Phase 3 Step 1.** This item was **not** part
   of the Phase 1 Step 3 import; it is recorded here because this document is
   the inventory of record for that file. The imported file loaded
   `assets/sim/actions.json` at run time through `repo_path!`, which resolves
   from `CARGO_MANIFEST_DIR` **at compile time**, so the built
   `libremich_gdext.so` kept reading its catalogue from the checkout it was
   built in — observed when Y-R built Remich in a temporary checkout, deleted
   it, and the first `score_activity` in Larochette panicked with
   `Failed to load actions catalogue: IoError(NotFound)`. The lead ruled this
   one donor adaptation allowed (standing-ruling-2 spirit, recorded in issue
   #9): the committed catalogue is now embedded at compile time with
   `include_str!(concat!(env!("CARGO_MANIFEST_DIR"),
   "/../../assets/sim/actions.json"))` and parsed with
   `serde_json::from_str`. **Exactly what changed:** the delivery of the bytes
   — the runtime loader no longer invokes `repo_path!`, opens a file, calls
   `std::fs::read` or otherwise touches the build checkout. **Exactly what did
   not:** the catalogue data (`assets/sim/actions.json` is byte-identical,
   sha256 `166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5`,
   26 actions), the `Action` values and their order, the public functions, the
   `OnceLock` behaviour, and the `ActionCatalogueError` type — the error API
   was deliberately not redesigned for an I/O-less loader. One test was added
   (`embedded_catalogue_is_the_committed_file`, test-only file comparison),
   which is why the frozen donor source-test count moved 183 → 184 (§6). The
   file's status moved `unchanged` → `adapted`; its provenance line did not.

No other post-copy change was made during the import: items 1-9 are the whole
of the Phase 1 Step 3 adaptation list, and for them no formula was tuned, no
concept renamed, no algorithm simplified, no donor API reshaped for the Godot
bridge (that is Step 4), no visibility changed, no warning or style cleanup, and
no engine-facing code had to be removed — the donor sim code was already
engine-free. Item 10 is the single later, dated, lead-authorized adaptation
described above.

## 6. Donor tests: what runs, what was not carried (and exactly why)

### Carried — executed and green

Command: `cargo test -p anvil_core -p anvil_sim` (and via
`cargo test --workspace`). On the pinned toolchain (Rust 1.98.1):

| Test target | Result |
|---|---|
| `anvil_sim` unit tests (inline in the copied sources + the 2 carried RNG tests) | **132 passed, 0 failed, 0 ignored** (131 at the import + the post-import Remich #9 test, §5.10) |
| `anvil_sim` integration `tests/npc_determinism_carried.rs` (carried excerpt) | **2 passed, 0 failed** |
| `anvil_core` unit tests (inline in the copied sources) | **50 passed, 0 failed, 0 ignored** |
| `anvil_core` doc-tests | 3 passed, 1 ignored, in the two batches rustdoc emits: `2 passed; 0 failed; 1 ignored` (the ignore is the donor's own ` ```ignore ` example in `error.rs`, copied byte-identically — not ours), then `1 passed; 0 failed; 0 ignored` (the donor's compile-fail doctest in `ids.rs`) |
| `anvil_sim` doc-tests | 0 tests (no doc examples in the taken subset) |

Per-file unit-test counts (mechanically cross-checked by
`tools/check_phase1_step3.sh` against `#[test]` occurrences in the tracked
sources — executed count must equal source count):

`needs.rs` 5 · `actions.rs` 12 · `actions/catalogue.rs` 10 (9 at the import +
the Remich #9 test, §5.10) ·
`utility/scoring.rs` 17 · `time.rs` 9 · `age.rs` 17 · `soul.rs` 23 ·
`soul/axes.rs` 24 · `settlement/skill.rs` 1 · `skill/affordance.rs` 9 ·
`skill/domain.rs` 3 · `anvil_sim/src/lib.rs` (carried RNG tests) 2 → **132** ·
`anvil_core`: `lib.rs` 5 · `asset_request.rs` 12 · `connections.rs` 16 ·
`error.rs` 8 · `semantic.rs` 9 → **50**.

So the source `#[test]` count of the two donor crates is **184** since
2026-10-01 (132 + 50 + 2 carried integration), against the 183 this step
recorded at the import; `tools/check_phase1_step3.sh` freezes 184 because
Remich #9 added exactly one catalogue test and no other.

These cover every copied component: needs, actions + catalogue (including the
real `actions.json` load and every catalogue-content assertion), utility
scoring (urgency, time multiplier, skill/perception/substrate/coping/
cooperation modifiers, the full `compute_utility_score`), time-of-day curves,
age, soul/axes, Skill, AffordanceId, SkillDomain, and `anvil_core`.

### Not carried — exact dependency diagnosis (not silently omitted)

| Donor test file / tests | Why they cannot run in this step's closure |
|---|---|
| `tests/npc_determinism.rs` → `test_npc_system_deterministic_action_selection`, `test_npc_system_deterministic_need_decay` | need `NpcSystem` (`system/npc`, excluded by the lead's scope ruling §2.2) and `WorldRuntime` → `anvil_world`. The file's other two tests were carried (§4, §5.7). |
| `tests/integration_skill_emotion.rs` | `anvil_sim::system::NpcSystem` + settlement `Family`/`Person` + `anvil_world` |
| `tests/skill_determinism.rs` | `NpcSystem` + `skill::SkillEvent` (skill subsystem) + `anvil_world` |
| `tests/drought_to_harvest.rs` | `JoySystem` + settlement `Family`/`Person` + `skill::SkillProfile` + `anvil_world` |
| `tests/determinism.rs` | `CatastropheSystem` + `anvil_world` |
| `tests/determinism_fuzz.rs` | `CatastropheSystem`, `JoySystem`, `PhysicsSystem`, `NpcSystem` + `anvil_world` + `glam` |
| `tests/phase3_determinism.rs` | `CatastropheSystem`, `JoySystem`, `PhysicsSystem`, `NpcSystem` + `anvil_world` + `glam` |
| `tests/phase3_snapshot_roundtrip.rs` | same four systems + snapshot/restore (saving) + `anvil_world` |
| `tests/physics_determinism.rs`, `tests/snapshot_physics.rs` | `PhysicsSystem` / `PhysicsSaveState` + `rapier3d` + `anvil_world` |
| `tests/perceptibility_test.rs` | `skill::perceptibility` and `skill::catalogue` (skill subsystem, not taken) |
| donor `anvil_sim/src/lib.rs` tests → `test_sim_context_creation`, `test_world_runtime_defaults` | `SimContext`/`WorldRuntime` → `anvil_world` (world/game integration) |
| donor `anvil_sim/src/lib.rs` tests → `test_system_trait_object_safety`, `test_sim_error_display` | `SimSystem`/`SimError` — crate-root infrastructure of the systems this step does not take; not required by any taken file (the RNG pair they sit next to **was** carried) |

None of these were deleted, ignored, weakened, rewritten or skipped; each is
simply outside this step's closure, as decided in §2.2.

## 7. The known preservation defect: `kimi_npc_mod.rs`

The preserved snapshot has `repos/anvil/source/crates/anvil_sim/src/system/npc/kimi_npc_mod.rs`
where Rust expects `system/npc/mod.rs`.

**Step 3 did not copy that module** (lead scope ruling §2.2: the NPC system's
evaluation/selection code is `impl NpcSystem` and cannot be taken without the
settlement + skill + `anvil_world` closure). Therefore **no filename
restoration was performed and none was needed**; the defect remains untouched
in the vault (`buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/system/npc/kimi_npc_mod.rs`,
Observed, unfixed). If a later step takes `system/npc`, the planned adaptation
is: copy donor bytes `…/system/npc/kimi_npc_mod.rs` → `…/system/npc/mod.rs`,
content unchanged, adaptation = "restored Rust module filename", recorded as
such. No other preservation defect was encountered in this step's subset.

## 8. Engine-free firewall (docs/PLAN.md §1.2)

`crates/anvil_sim` and `crates/anvil_core` contain no engine dependency, no
binding API and no engine types: `cargo tree -p anvil_sim --edges normal,build`
resolves only `anvil_core`, `serde`, `serde_json`, `thiserror`; the same holds
for `anvil_core`. `grep -riE 'godot|gdext'` over both crates (sources and
manifests) returns nothing. The binding dependency appears only in
`crates/remich_gdext`. Nothing here is exposed to the engine — that is Step 4.

## 9. Reproducing

```bash
bash tools/check_phase1_step3.sh
```

## 10. Build timings (measured 2026-09-30, this worktree, pinned toolchain)

Both figures are wall-clock on this machine, taken on this step's final Rust
state (only this record changed after the measurement — no Rust byte differs).
The probe was exactly one added comment line carrying the sentinel
`remich-timing-probe`, in `crates/anvil_sim/src/lib.rs`; it was reverted
byte-exact immediately after the measurement. The sentinel survives nowhere
except this sentence, which `tools/check_phase1_step3.sh` proves by grepping
every tracked file.

| Measurement | Command | Result |
|---|---|---|
| Clean build | `cargo clean` then `cargo build --workspace` | 44.28 s wall, 31 crates compiled, 0 warnings, exit 0 |
| One-line probe rebuild | add one comment line (`remich-timing-probe`) to `crates/anvil_sim/src/lib.rs`, then `cargo build --workspace` | 0.27 s wall, only `anvil_sim` recompiled (1 crate — no crate depends on it yet; the bridge wiring is Step 4), exit 0 |

The revert was itself observed as a rebuild: after removing the line, `cargo
build --workspace` recompiled `anvil_sim` again (0.21 s), proving the file was
byte-different from the probe state — i.e. the probe did not linger.

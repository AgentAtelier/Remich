# Remich — Phase 3, Step 2: soul primitives across the bridge

Remich issue #9, Phase 3 step 2 of `docs/PLAN.md` §4b: the donor's own soul
primitives are reachable from the engine, and a pinned Godot run proves the
result is deterministic, equal to the donor, and never applied to a soul.

## 1. What changed, and what did not

**Changed — implementation:**

| file | change |
|---|---|
| `crates/anvil_sim/src/settlement/connection.rs` | imported from the donor, **byte-identical** (107 lines): `Connection`, `ConnectionLayer` and `ConnectionLayer::weight()` — the edge strength per layer, the only weight this step uses |
| `crates/anvil_sim/src/settlement/ids.rs` | imported from the donor, **byte-identical** (178 lines): the newtype ids `connection.rs` is parameterised by |
| `crates/anvil_sim/src/settlement/mod.rs` | adapted: the donor's own first five doc lines kept verbatim, plus exactly three donor-spelled lines — `pub mod connection;`, `pub mod ids;`, `pub use connection::{Connection, ConnectionLayer};` — each spelled identically in the donor's file and each documented in the provenance record (§5.11) |
| `crates/remich_core/src/soul.rs` | new **engine-free facade** (362 lines) and its 7 tests |
| `crates/remich_core/src/lib.rs` | declares and documents `pub mod soul;` (+6) |
| `crates/remich_gdext/src/lib.rs` | `SOUL_BRIDGE_REV`, the single `RemichSoul` class and its marker test (+197) |
| `godot/soul_probe.gd` | new standalone `SceneTree` probe (309 lines) — invoked with `--script`, **not** an autoload |
| `tools/stage_soul.sh` | staging: derives the probe's expectation from the Rust source, chains `stage_bridge.sh` |
| `tools/run_soul.sh` | the runner: pinned Godot, headless, `--script`, normal/bypass |
| `tools/check_phase3_step2.sh` | this step's acceptance: **46 checks** |
| `.gitignore` | `/godot/soul_probe_expectation.txt` and `soul_trace*.txt` (derived state, never committed) |
| `docs/anvil-import-phase1-step3.md` | provenance: §4 +2 inventory entries, §5.11, §6 counts, new dated §11 (+129/−18) |
| six ratchet checkers | named, narrow edits (§7) |

**Unchanged, deliberately and asserted by the acceptance run:**

| what | state |
|---|---|
| `crates/anvil_sim/src/soul.rs` | byte-identical to the donor, sha256 `72b6d1ed66aec8dfc55b7cf768804ad99e9efa869426c3b68b3577d7b3d284cd` |
| `crates/anvil_sim/src/soul/axes.rs` | byte-identical to the donor, sha256 `f038823f43ea9560c8d6e0abc659307b99dd5cb5b2d35a26d9ab47e9d3c66c20` |
| `settlement/connection.rs` / `settlement/ids.rs` | byte-identical, `252c99e2b0608156…` and `a315bf7fa6e6e0d8…` |
| `crates/anvil_sim/src/system/npc` | **untaken** — nothing under `system/` is tracked or changed |
| `docs/PLAN.md` | byte-identical to the re-scope freeze `02eff4214c97d31743e7486a9d905fa5c22541a6` |
| `tools/check_phase1_step4.sh`, `tools/check_phase1_step5.sh` | untouched (issue #15's scripts, outside this step's allowed edit set — see §12) |
| the donor vault | read-only at `24181142c693be37f90a6a667a6dc493425cd832`, working tree clean |
| the sibling repositories | clean; none touched |
| the canonical day trace | `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` (chain green) |

## 2. What did not exist

The donor computes a propagated influence for a named connection layer and
returns it: `ConnectionLayer::weight()` picks the edge strength, and
`EmotionalAxes::propagate(weight)` returns the per-axis influence values as an
`EmotionalAxes`. None of that was reachable from the engine: `remich_core` had
no soul module, the extension had no soul class, and `godot/` had no probe
that could ask a question of a soul — so a Godot run could not read a soul,
could not read a layer weight, and could not observe the donor's propagation
at all.

This step closes exactly that gap: one engine-free facade, one binding class,
one standalone probe. What the influence *means* for an inhabitant — writing
it into a receiver, reacting to it, remembering who caused it — belongs to the
lead's Munshausen wiring (`docs/PLAN.md` §4b, "Lead steps") and is not
attempted here.

## 3. Provenance and authorization

Both new donor files carry canonical inventory entries with status
**`unchanged`**:

```text
crates/anvil_sim/src/settlement/connection.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/connection.rs :: unchanged
crates/anvil_sim/src/settlement/ids.rs :: buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/ids.rs :: unchanged
```

at the pinned read-only vault commit `24181142c693be37f90a6a667a6dc493425cd832`
(original anvil main `97c8fdbd7ff85779f33456fd7c444657f8d90b36`). Inventory
counts become **28 unchanged + 5 adapted + 1 new + 1 excerpt + 1 data = 36**
(unchanged 26 → 28: two files added, nothing reclassified).

The provenance record gained a dated **§11 Phase 3 Step 2 — soul primitives
across the bridge (2026-10-01)** with the four sha256 values, the statement
that `system/npc` remains untaken, and the distinction this step keeps intact:
propagated influence is a value the donor returns, **not** a receiver state
update. §6 of that record carries the donor test arithmetic (§6 below).

## 4. The bridge

```rust
// crates/remich_core/src/soul.rs — the facade, engine-free by construction
pub fn propagate(&self, layer: ConnectionLayer) -> PropagatedInfluence {
    let connection_weight = layer.weight();          // the donor's own table
    PropagatedInfluence {
        layer,
        connection_weight,
        axes: axes_snapshot(&self.soul.emotional_state.axes.propagate(connection_weight)),
    }                                                // the donor's own formula
}
```

Two donor calls and nothing else. Nothing else exists in that path: no literal
weight, no layer-name → number map (the name lookup maps `"family"` →
`ConnectionLayer::Family` and holds no numeric value), no `fn apply`, no
`target +=`, no ordering of souls, no aggregation over neighbours. Each
assertion runs on comment-stripped source, so prose in a comment cannot
satisfy it. The result is `PropagatedInfluence { layer, connection_weight,
axes }` — the influence *value*, never a soul.

The binding is one class with six explicit methods — `initialize`,
`is_initialized`, `soul_snapshot`, `connection_weight`, `propagate`,
`soul_bridge_rev` — holding only `Option<SoulFacade>`, and

```rust
pub const SOUL_BRIDGE_REV: &str = "remich-soul-v1";
```

whose line is compared byte-for-byte by acceptance check 20 and by the
`fn soul_bridge_rev_is_the_committed_marker` unit test. The staging
script derives the probe's expectation **from that Rust source**, so a
revision change cannot be staged against a stale constant.

## 5. The fixture

`godot/soul_probe.gd` creates exactly three stand-in souls from the committed
fixture seeds **1000003, 2000003, 3000003**, one donor layer each —
**family (1.0), proximity (0.5), village (0.1)**, the donor's own
`ConnectionLayer::weight()` table — reads them back, records the donor's
propagated influence, and asserts:

* the soul snapshot taken *after* the call equals the one taken before
  (`JSON.stringify` equality) — nothing was written into a soul;
* an unknown layer name is refused rather than defaulted;
* no clock, pid, random or path value may enter the trace.

The trace is plain text, fixed order, 24 lines (3 records × 7 lines + 3 blank
separators), 1595 bytes: `actor`, `substrate`, `source_axes`, `connection`,
`propagated_influence`, `influence_kind`, `bridge_rev`. The final four values
are explicitly labelled:

```text
influence_kind=propagated-influence (not a receiver state update)
```

Neither trace contains the word `bypass` or any mode label — acceptance check
45 greps for both.

## 6. Tests

| measure | at the import | now |
|---|---:|---:|
| donor source `#[test]` (`anvil_sim` + `anvil_core`) | 184 | **187** |
| … contributed by `settlement/ids.rs` | — | **+0** |
| … contributed by `settlement/connection.rs` | — | **+3** |
| `remich_core` `soul::tests` | 0 (module absent) | **7** |
| `cargo build --workspace` / `cargo test --workspace` | exit 0, 0 warnings | exit 0, 0 warnings |

Exactly three tests arrived with `settlement/connection.rs` and none with
`settlement/ids.rs`; none was removed, weakened or altered by hand:
`anvil_sim` reaches **135** and `anvil_core` **50**, so the source `#[test]`
count of the two donor crates is **135 + 50 + 2 carried integration = 187**,
and `tools/check_phase1_step3.sh` freezes 187 as `EXPECTED_SOURCE_TESTS`.

## 7. Historical ratchets updated

Six checkers state a frozen assumption this step makes false. Each was edited
narrowly, at the change site, with a comment naming **Phase 3 Step 2 — soul
primitives across the bridge**, no wildcard, no bare directory and no
baseline advanced beyond what is named here.

| checker | ratchet that moved | the change |
|---|---|---|
| `tools/check_phase1_step3.sh` | the frozen source-test count, the inventory shape, the donor byte rule | `EXPECTED_SOURCE_TESTS` 184 → **187**; inventory `unchanged=28`, 36 entries, `unchanged_ok -eq 28`; one **named** exception (`P3S2_SETTLEMENT_MOD` with `P3S2_ADDED_LINES`) in the pure-line-deletion loop for `settlement/mod.rs` only — proved narrow (the donor's own doc lines, exactly three donor-spelled lines once each and documented, file-minus-those-lines still a pure line-deletion of the donor, Phase 1's `skill` keeps intact) |
| `tools/check_phase2_step1.sh` | the donor freeze | the donor delta names `P3S2_CONNECTION`, `P3S2_IDS`, `P3S2_SETTLEMENT_MOD` |
| `tools/check_phase2_step2.sh` | the donor freeze | the same three exact paths |
| `tools/check_phase2_step3.sh` | the donor freeze | the same three exact paths |
| `tools/check_phase2_step4.sh` | checks 2, 3, 4, 5 and 27 | the three donor paths; `P3S2_RUST_FILES` and `rust_filters` in check 4; allowlists in checks 5 and 27; four messages updated |
| `tools/check_phase3_step1.sh` | the frozen source-test count and the changed-file allowlist | `EXPECTED_SOURCE_TESTS` 184 → **187**; check 2 becomes an **exact** allowlist — the authorized catalogue plus `P3S2_BEHAVIOUR_FILES` (7 paths) — with the catalogue still required to be among the changed files |

Three scripts were added, all named in the allowlists above:

| script | role |
|---|---|
| `tools/stage_soul.sh` | staging: derives the expectation from the Rust source, chains `stage_bridge.sh` (§4) |
| `tools/run_soul.sh` | the runner: pinned Godot, headless, `--script`, normal/bypass (§5, §8) |
| `tools/check_phase3_step2.sh` | this step's acceptance: **46 checks** (§11) |

## 8. The determinism and bypass proof

Two runs of the same fixture, written to a temp directory outside the
repository:

| run | trace sha256 |
|---|---|
| normal, first | `410aab053bcb79891e8cf3f7ac3c538f9f3973ebde05624b88e18b0dfbb2717f` |
| normal, second | `410aab053bcb79891e8cf3f7ac3c538f9f3973ebde05624b88e18b0dfbb2717f` — **byte-identical** |
| bypass | `0e9795e795d9a72daf90e4a9829df25cf45e46460ce2e07cebdfe87c80f7a055` |

`diff` of the normal and bypass traces, with `propagated_influence` lines
stripped, is **empty**: seed, substrate, source axes, layer name, donor weight
and bridge revision are identical, and the bypass changes only the influence
values. Those values are all zero (0 of 12 components non-zero), while the
normal trace has **12** non-zero components — so a zero-output implementation
cannot pass check 44. `normal_sha != bypass_sha` (check 41).

The bypass is described only as bypassing the propagation calculation — a
test-only bypass of *that calculation*, as `tools/run_soul.sh`'s header states.
It is never phrased as "disabling contagion" or "stopping mood spreading":
neither exists in Remich.

## 9. The official environment

| item | value |
|---|---|
| Godot | pinned **Godot 4.7.2** (`Godot_v4.7.2-stable_linux.x86_64`, headless, `--script res://soul_probe.gd`, never editor/import/export) |
| Rust | repository pin `rust-toolchain.toml` channel **1.98.1** (`rustc 1.98.1 (48a229cea 2026-09-01)`) |
| build profile / library | development **debug** build — `cargo build --workspace`, loaded from `target/debug/libremich_gdext.so` |
| day trace | `bash tools/run_day.sh <trace> 1`, canonical sha256 `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` |
| soul trace | `bash tools/run_soul.sh <trace> normal`, sha256 `410aab053bcb79891e8cf3f7ac3c538f9f3973ebde05624b88e18b0dfbb2717f` |

## 10. Measured commit, build and rebuild timings

**Measured commit (executable state):**
`4da6ef4ef1c1ad9057831d6006d2ac3f5a334d0f` — *test(soul): add the Phase 3
Step 2 acceptance check*. Every implementation file, ratchet edit, provenance
update and script exists exactly at that commit, and the worktree was clean
before timing; only this record was added afterwards.

**Clean build**, from that clean commit, procedure `cargo clean` then
`cargo build --workspace`:

| | |
|---|---|
| `cargo clean` | **0.253 s** wall, exit 0 |
| `cargo build --workspace` | **44.66 s** wall, exit 0 |
| both together | **44.91 s** |
| crates compiled | **31** |
| warnings | **0** |

(A first cold build of the same procedure measured **54.81 s** earlier the
same evening, while another lane was working on the machine. Same procedure,
same debug profile, same 31 crates.)

**One-line rebuild observed in Godot**, with the measured commit clean and
`remich-soul-v1` observed in a normal run first: exactly one line changed —
`crates/remich_gdext/src/lib.rs` line 101, `SOUL_BRIDGE_REV`, its trailing
digit `1` → `2` (1 file, 1 insertion, 1 deletion).

| | |
|---|---|
| timed `cargo build --workspace` | **1.356 s** wall, exit 0 |
| `bash tools/run_soul.sh <tmp-trace> normal` until Godot observed the new value | **0.571 s**, exit 0 — `REMICH_SOUL_OK actors=3 rev=remich-soul-v2` and `REMICH_SOUL_PROPAGATION_OK layers=family,proximity,village rev=remich-soul-v2` |
| end to end, build → observation | **1.931 s** |

The line was then restored byte-for-byte: sha256 of `lib.rs` back to
`46d338e8c70a28fea2f32a0df706edcece5b671353f60121b01b17af475c0752` (equal to
the pre-timing hash), `git diff` empty, worktree clean; the restored library
was rebuilt (**13.25 s** wall, exit 0) and a normal run re-proved
`REMICH_SOUL_OK actors=3 rev=remich-soul-v1` with its trace sha256 equal to
the committed `410aab05…` above.

## 11. Acceptance

* **Phase 3 Step 2 acceptance:** `bash tools/check_phase3_step2.sh` — **46
  checks, 46 ok, 0 failed, rc=0**, run **exactly once**, on 2026-10-01 from
  23:47:56 to 23:49:23 (87 s) on the clean measured commit `4da6ef4e…`. It
  covers the live chain, the plan freeze, the pinned vault, all four donor
  files byte-for-byte, the module-root wiring, the provenance record, the
  engine-free facade, the single binding class, the standalone probe, the
  staging and runner, both normal runs and their SHA, the bypass run and its
  SHA, and the boundary (no mutation construct, `system/npc` untouched, no
  sibling repository modified, clean worktree).
* **The previous chain**, run as sub-checks of that acceptance:
  `check_phase3_step1.sh` (which transitively runs `check_phase2_step4.sh` →
  step 3 → step 2 → step 1 → `check_phase1_step3.sh` → step 2 → step 1) and
  `check_phase1_step3.sh` run directly — green on this head.
* **The three markers.** The first two are printed by `godot/soul_probe.gd`
  on a successful run (the second only when the propagation calculation
  really ran) and asserted by acceptance checks 34–36 and 39:

  ```text
  REMICH_SOUL_OK actors=3 rev=remich-soul-v1
  REMICH_SOUL_PROPAGATION_OK layers=family,proximity,village rev=remich-soul-v1
  ```

  The third names both fingerprints, so it can only exist once both runs are
  over; its substance is acceptance check 41 (`normal_sha != bypass_sha`) and
  it is recorded here:

  ```text
  REMICH_SOUL_BYPASS_OK normal_sha=410aab053bcb79891e8cf3f7ac3c538f9f3973ebde05624b88e18b0dfbb2717f bypass_sha=0e9795e795d9a72daf90e4a9829df25cf45e46460ce2e07cebdfe87c80f7a055
  ```

* This record's commit follows the measured commit: the final head differs
  from `4da6ef4e…` by this document alone — one `docs/*.md` file. No checker
  reads its contents; `tools/check_phase2_step4.sh`'s measured → final
  allowlist already names this exact path, and the other gates' record
  allowlists cover `docs/*.md`, so no assertion moves between the acceptance
  run and the pushed head.
* During development the fixture was proven with separate `run_soul.sh`
  invocations (never with a second acceptance run); the acceptance itself
  ran once.

## 12. Findings that predate this step

Two Phase 1 checkers — `tools/check_phase1_step4.sh` and
`tools/check_phase1_step5.sh` (issue #15's scripts) — are outside the live
chain and outside this step's allowed edit set, so they were **not**
touched: `git diff cfabac9 HEAD -- tools/check_phase1_step4.sh
tools/check_phase1_step5.sh` is empty. Both were run during development and
both exited 1; both were already red at the base
`cfabac9f136f6b7b12b3380b5faffa0ab734781d`, before any of this step's work;
evaluating each failing assertion's own `git diff` at that ref gives:

1. **`check_phase1_step4.sh` at the base — 2 of its checks already red:**
   * `docs/PLAN.md` "rewritten since the Phase 3 plan merge `cfa796cc`":
     `git diff --quiet cfa796cc cfabac9 -- docs/PLAN.md` is **not** quiet —
     the lead's Phase 3 re-scope (PR #16) amended the plan after that merge;
   * the rebuild sentinel — the value that checker assembles with
     `printf 'remich-scorer-v%s' '2'`, which this record deliberately does not
     spell, because its whole-worktree scan wants that value in exactly one
     file: `git grep -lF` of it at `cfabac9` returns **two** files,
     `docs/remich-scale-phase2-step4.md` and `docs/remich-scorer-step4.md`,
     while the rule wants only its own record. This record spells no such
     value, so it adds no file to that list.
   Its donor-file check **passed** at the base (`git diff --name-only
   35276c0 cfabac9 -- crates/anvil_sim crates/anvil_core assets` minus the
   authorized catalogue is empty) and is the one check this step moves: it now
   lists `settlement/connection.rs`, `settlement/ids.rs` and
   `settlement/mod.rs`.
2. **`check_phase1_step5.sh` at the base — 2 of its checks already red:**
   the same `docs/PLAN.md` assertion, and "Rust file changed since `a599a55`
   beyond the catalogue", which at the base already lists **8** files
   (`Cargo.lock`, `crates/remich_core/Cargo.toml` and its `clock.rs`,
   `lib.rs`, `save.rs`, `weather.rs`, `crates/remich_gdext/src/lib.rs` and
   `save.rs`) — all Phase 2's. Its donor check was empty at the base and this
   step adds the same three settlement files to it.

So both scripts were red before this step existed, for reasons Phase 2 and the
plan re-scope created; this step adds the three named settlement files to
checks that were already failing (and moves one previously-green `p1s4`
check). They are not in the live chain, they are not in this step's allowed
edit set, and they were left byte-identical rather than widened into a
wildcard.

## 13. Refusals and stops

Refused, per the issue's ruling and the plan: authoring any event → axis
mutation, `target += influence`, blending, receiver clamping, neighbour
aggregation, update ordering or contextual-contagion asymmetry; introducing
`EmotionalEvent` or a persistent social graph; owning a weight table or a
propagation formula in Remich; taking `system/npc`; altering `soul.rs` or
`soul/axes.rs` in any way; importing anything beyond
`settlement/connection.rs` and `settlement/ids.rs` (and the three documented
lines in `settlement/mod.rs`); making the probe an autoload; adding a second
binding class; writing timestamps, pids, paths or machine values into the
trace; phrasing the bypass as anything other than bypassing the propagation
calculation; fetching from upstream; touching Yolanda or any sibling
repository; rewriting `docs/PLAN.md`; editing issue #15's two scripts;
adding a wildcard or whole-directory exception to a ratchet or advancing a
baseline; starting Phase 3 step 3; and merging the pull request.

No stop condition fired: the vault was read-only throughout, no published
format changed, no sibling repository was modified by this step, and the
donor's soul code, the canonical day trace and the scorer's behaviour are
byte-for-byte what they were.

# Remich

**The Rust bridge** of Schmelz: engine-free Rust simulation cores running inside the Godot game,
through Rust's Godot binding (`gdext`), with rebuilds fast enough to work with.

Named after the Moselle town whose bridge crosses from Luxembourg to Germany.

The plan — the destination and phase 1 (anvil's scorer chooses what Ada does next) — is
[docs/PLAN.md](docs/PLAN.md).

## What Remich owns, and what it does not

Remich's boundary is [docs/PLAN.md §1](docs/PLAN.md). In short:

1. **Remich owns the bridge, not the behaviour.** Remich owns building, loading, calling and data
   transfer between engine-free Rust cores and Godot — not game behaviour. What an inhabitant wants
   belongs to [Munshausen](https://github.com/AgentAtelier/Munshausen), what the weather does to
   [Eisleck](https://github.com/AgentAtelier/Eisleck), how plants grow and burn to
   [Grengewald](https://github.com/AgentAtelier/Grengewald). Remich carries that behaviour across
   the bridge; it does not write it.
2. **Godot types belong only in the thin binding layer.** The firewall: simulation cores never
   depend on the engine. [`crates/remich_core`](crates/remich_core) is engine-free — no engine
   dependency, no engine types — and [`crates/remich_gdext`](crates/remich_gdext), the thin binding
   layer on top of it, is the only place Godot types appear.
3. **Game, not tool.** Rust cores run in the game: runtime simulation is game state, not Yolanda
   history. Nothing a core computes at runtime enters Yolanda's history. Yolanda may run a core as
   a tool later, on purpose, but that is not this plan.
4. **Determinism is a requirement, not a hope.** The same inputs and seed give the same result, so
   saves and replays hold.
5. **Rebuild speed is a requirement, not a hope.** The time from a one-line change to seeing it in
   Godot is measured and reported in every step that touches the build.

## The repository's shape

| Path | What it is |
| --- | --- |
| [`Cargo.toml`](Cargo.toml) | The workspace: engine-free core and thin binding as separate crates. |
| [`crates/remich_core`](crates/remich_core) | The engine-free core. Plain Rust; no engine dependency, no engine types. |
| [`crates/remich_gdext`](crates/remich_gdext) | The binding side — a real, loadable GDExtension and the only place Godot types appear. |
| [`godot/`](godot) | Remich's own small Godot test project, including `remich.gdextension`. The bridge is proved here, in Remich's project, before it goes anywhere else. |
| [`rust-toolchain.toml`](rust-toolchain.toml) | The exact pinned Rust toolchain. |
| [`docs/binding-compatibility.md`](docs/binding-compatibility.md) | Which binding supports the pinned engine, with dated upstream evidence. |
| [`tools/check_phase1_step1.sh`](tools/check_phase1_step1.sh) | The acceptance check for step 1. |
| [`tools/check_phase1_step2.sh`](tools/check_phase1_step2.sh) | The acceptance check for step 2; runs the step 1 check first. |
| [`docs/PLAN.md`](docs/PLAN.md) | The plan. |

Generated state is never committed: Cargo's `target/`, Godot's `.godot/`, the extension binary and
the derived bridge expectation are all ignored.

**Not in this step** (later steps of [docs/PLAN.md](docs/PLAN.md)): scoring, needs, actions,
utilities, engine-facing nodes of our own, and a simulated day. Step 1 was the shape, the pinned
toolchain, the test project and the measured rebuild; step 2 added the bridge itself — one Rust
callable and one value, observed and verified in Godot.

## The binding (phase 1, step 2)

Remich binds to Godot through [godot-rust/gdext](https://github.com/godot-rust/gdext) — the `godot`
crate — pinned exactly at `=0.5.5` **with the `api-4-7` feature**, so the bridge compiles against
the Godot 4.7 API rather than whatever the crate happens to default to.

Which binding version supports the pinned engine was an open question in the plan, so it is
answered with recorded evidence in [`docs/binding-compatibility.md`](docs/binding-compatibility.md):
the upstream release notes, the documented `runtime >= API` compatibility rule, the runtime guard in
the binding's own source, and two dated build observations — all checked 2026-09-30.

The bridge itself is deliberately trivial. Godot instantiates `RemichBridge`, calls
`bridge_probe()`, and gets `BRIDGE_PROBE_VALUE` back. Proving that call happens — not building
behaviour — is what this step is for.

## Pinned Rust toolchain

[`rust-toolchain.toml`](rust-toolchain.toml) pins an exact channel — `1.98.1`, never `stable` — so
the build and its timings are reproducible. The exact `rustc -Vv` used:

```text
rustc 1.98.1 (48a229cea 2026-09-01)
binary: rustc
commit-hash: 48a229ceaefd4985c50990b14116b6d856af0985
commit-date: 2026-09-01
host: x86_64-unknown-linux-gnu
release: 1.98.1
LLVM version: 22.1.8
```

## Pinned Godot

The test project is opened with the pinned Godot executable, unchanged:

```text
/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64
--version -> 4.7.2.stable.official.ed1daf0bf
```

## Acceptance

One command per step:

```bash
bash tools/check_phase1_step1.sh   # the repository's shape
bash tools/check_phase1_step2.sh   # the bridge exists (runs the step 1 check first)
```

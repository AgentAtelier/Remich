# Binding compatibility with the pinned Godot 4.7.2

**Recorded 2026-09-30** for phase 1, step 2 of [docs/PLAN.md](PLAN.md), which asks to
"check which version supports Godot 4.7.2 (Unknown today; record the evidence)".

## Answer

| | |
| --- | --- |
| Binding project | [godot-rust/gdext](https://github.com/godot-rust/gdext) |
| Crate | `godot` (crates.io) |
| Exact version pinned | `=0.5.5`, declared in [`crates/remich_gdext/Cargo.toml`](../crates/remich_gdext/Cargo.toml) |
| API-level feature pinned | `api-4-7` |
| Qualified against | Godot `4.7.2.stable.official.ed1daf0bf` (the pinned binary) |
| Sources checked | 2026-09-30 |

## The evidence

### 1. gdext's own release notes announce Godot 4.7 support

> Godot 4.7: add `api-4-7` level ([#1641](https://github.com/godot-rust/gdext/pull/1641))

— gdext `Changelog.md`, entry **v0.5.4**, dated **23 June 2026**.
Source: <https://github.com/godot-rust/gdext/blob/master/Changelog.md> (checked 2026-09-30).

`v0.5.5` — the current release, **9 August 2026** — still ships that level: `cargo info godot`
lists `api-4-7` among its features, and the published crate's own
`godot-bindings-0.5.5/src/import.rs` contains
`#[cfg(feature = "api-4-7")] pub use gdextension_api::version_4_7 as prebuilt;`.

### 2. The documented compatibility rule covers a 4.7 extension running in 4.7.2

> Starting from that version's official release, extensions can be loaded by any Godot version,
> as long as _runtime version **>=** API version_.
> - You **can** run a `4.2` extension in Godot `4.2.1` or `4.3`.
> - You **cannot** run a `4.3` extension in Godot `4.2.1`.

— "Compatibility and stability", <https://godot-rust.github.io/book/toolchain/compatibility.html>
(checked 2026-09-30).

Remich compiles against API **4.7.0** and runs in **4.7.2**, so `runtime >= API` holds.

### 3. gdext enforces exactly this rule at load time, and does not refuse here

```rust
// From here we can assume Godot 4.2+. We need to make sure that the runtime version is >= static version.
let static_version = crate::GdextBuild::godot_static_version_triple();
...
if runtime_version < static_version {
    panic!("godot-rust compiled against newer Godot version: ... \
           but loaded by older Godot binary: ...")
}
```

— `godot-ffi 0.5.5`, `src/interface_init.rs`, in the source of the pinned crate
(checked 2026-09-30).

For this repository: static `(4, 7, 0)` versus runtime `(4, 7, 2)` → the guard does not fire.
The reverse (a 4.8-built extension in 4.7.2) *would* panic, which is why the API level is pinned
rather than left to float.

### 4. API levels are minor-version scoped, so 4.7.2 sits inside `api-4-7`

> By default, godot-rust uses the **current minor release** of Godot 4, with patch 0. This ensures
> that it can be run with all Godot patch versions for that minor release.
> Example: if the current release is Godot 4.3.5, then godot-rust will use API version 4.3.0.

— "Selecting a Godot version", <https://godot-rust.github.io/book/toolchain/godot-version.html>
(checked 2026-09-30).

Corroborated by the payload itself: `gdextension-api 0.5.1` ships
`src/4.7/extension_api.json` with `GODOT_VERSION_STRING = "4.7"`. The API level is per **minor**
version; 4.7.2 is a patch of 4.7, and patch releases do not change the GDExtension interface.

### 5. `api-4-7` is **not** the default in the pinned version — the part that is easy to get wrong

`godot 0.5.5` declares `default = ["__codegen-full"]` (no API level) and `godot-core 0.5.5`
declares `default = []`. With no `api-4-*` feature, `godot-bindings 0.5.5` falls back to a
hand-maintained default in `src/import.rs`:

```rust
// [include] default.minor
#[rustfmt::skip]
pub use gdextension_api::version_4_6 as prebuilt;   // <-- 4.6, not 4.7
...
pub const LATEST_API_VERSION: (u8, u8, u8) = (4, 7, 0);
```

Observed rather than inferred — two builds on 2026-09-30 on this machine, same pinned toolchain,
read from `target/debug/build/godot-core-*/output`:

| build | `Parsed extension_api.json for version …` |
| --- | --- |
| `godot = "=0.5.5"` (default features only) | `version_major: 4, version_minor: 6, version_patch: 0, … "Godot Engine v4.6.stable.official"` |
| `godot = "=0.5.5"`, `features = ["api-4-7"]` | `version_major: 4, version_minor: 7, version_patch: 0, … "Godot Engine v4.7.stable.official"` |

**This is why `api-4-7` is written explicitly in `crates/remich_gdext/Cargo.toml`.** Without it the
bridge would compile against Godot 4.6's API: it would still *load* in 4.7.2 by rule 2, but this
step would not have qualified the 4.7 binding at all, and nothing would ever have exercised the 4.7
API.

### 6. Confirmed by this repository's own acceptance

`bash tools/check_phase1_step2.sh` runs the pinned engine headlessly against Remich's own project.
The log opens with gdext reporting both versions, and ends with Godot's own verdict on the value:

```text
Initialize godot-rust (API v4.7.stable.official, runtime v4.7.2.stable.official, safeguards strict)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

REMICH_TEST_PROJECT_OPENED
REMICH_BRIDGE_OK value=remich-bridge-v1
```

## Caveats relevant to this repository

1. **Never rely on the default API level.** The book's "Default version" section describes the
   default as the current minor release, but the pinned `0.5.5` resolves it to **4.6** (observed
   above). `api-4-7` must stay written out in the manifest.
2. **`api-4-7` is minor-version scoped.** It qualifies 4.7.x, including 4.7.2 — not 4.6 and not 4.8.
   Moving the pinned engine to another minor version reopens this question; this document must then
   be re-recorded with fresh upstream evidence.
3. **The pin is exact on purpose.** `=0.5.5` plus the committed `Cargo.lock` also freeze the
   transitive `gdextension-api` (0.5.1), `godot-bindings`, `godot-core`, `godot-ffi`,
   `godot-codegen` and `godot-macros`. A dependency update cannot silently change which binding
   version this step qualified; changing it is a deliberate edit to
   `crates/remich_gdext/Cargo.toml` and `Cargo.lock`, and a re-run of this evidence.
4. **Rust toolchain.** `godot 0.5.5` declares `rust-version = "1.94"`; Remich's pin is `1.98.1`,
   which satisfies it.
5. **This is a runtime qualification, not an editor one.** The acceptance never passes `--editor`,
   `--import` or `--export`, because the pinned binary is portable-mode and an editor run rewrites
   `editor_data/` inside Yolanda's directory.

## Sources

All checked **2026-09-30**:

- gdext release notes (Changelog): <https://github.com/godot-rust/gdext/blob/master/Changelog.md>
- Compatibility and stability: <https://godot-rust.github.io/book/toolchain/compatibility.html>
- Selecting a Godot version: <https://godot-rust.github.io/book/toolchain/godot-version.html>
- Setup / Hello World (`.gdextension`, `extension_list.cfg`): <https://godot-rust.github.io/book/intro/hello-world.html>
- crates.io metadata for `godot` (`cargo info godot`), and the published sources of
  `godot 0.5.5`, `godot-bindings 0.5.5`, `godot-ffi 0.5.5`, `gdextension-api 0.5.1`
  under `~/.cargo/registry/src/`.

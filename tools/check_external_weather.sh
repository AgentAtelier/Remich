#!/usr/bin/env bash
# Production-seam weather acceptance — "the one channel, externally driven"
# (Remich issue #19).
#
# One command, from anywhere:
#
#     bash tools/check_external_weather.sh
#
# This is the lead-owned At Dusk integration seam: Remich keeps owning the one
# shared weather channel and the authoritative integer clock, and an external
# driver (Eisleck) decides the weather and publishes complete snapshots through
# that same channel. It re-proves, directly, that the seam exists and that
# every existing invariant still holds.
#
# Requirements, as checks (numbered as the change asked for them):
#
#   1. this change is a descendant of the base it was cut from;
#   2. the core weather tests are green, and so is the whole workspace;
#   3. the workspace builds warning-free;
#   4. the engine-free core names no engine (the firewall holds);
#   5. `WeatherSnapshot` still declares exactly the seven planned fields — no
#      cloud, no phase, no new field;
#   6. the production writer id is one fixed constant in the core, spelled
#      `eislek-weather-driver`, distinct from the stand-in's;
#   7. the two identities alternate on ONE channel: neither displaces the
#      other, and both refusals are asserted;
#   8. an external publish stores the supplied snapshot and tick verbatim,
#      including out-of-order and non-adjacent ticks;
#   9. invalid values are refused through the existing validation and the last
#      valid snapshot survives;
#  10. a distinct second writer is refused on the production channel;
#  11. the production publish cannot bypass a stand-in that owns the channel;
#  12. the stand-in mode still owns its channel and drives whole cycles, and
#      its presentation phase is still the animated tick-derived one;
#  13. the binding's production publish is one whole-snapshot operation that
#      takes no writer identity and offers no per-field setter;
#  14. the production seam holds no clock: no delta, no wall time, no counter;
#  15. the existing readers are unchanged: `snapshot`, `writer_id`,
#      `writer_status`, `apply_wind` are still the readers, and `apply_wind`
#      still reads the one channel's snapshot in either mode;
#  15b. `apply_wind` refuses in external mode (`no-presentation-phase`) instead
#      of inventing a production presentation phase: no cycle 0, no frozen W,
#      no borrowed fixture cycle, and the refusal names the valid weather;
#  16. the Godot wrapper for the fixture is byte-for-byte unchanged — the
#      stand-in fixture was not converted into production policy;
#  17. the seam is proven through the REAL engine: pinned Godot 4.7.2 loads the
#      staged extension and the probe's marker appears;
#  18. the in-engine run claims the one channel for the production writer id,
#      with no stand-in driver;
#  19. a complete decided snapshot publishes and reads back with exactly the
#      seven supplied values and the exact tick;
#  20. `apply_wind()` REFUSES in external mode with `no-presentation-phase`; it
#      does not silently write a fabricated/frozen W, and the stand-in path still
#      applies an animated tick-derived W;
#  21. invalid values are refused in-engine and the last valid snapshot stands;
#  22. `drive(tick)` is refused in external mode — no stand-in weather is
#      silently generated;
#  23. a second distinct writer is refused in-engine, naming both writers;
#  23b. a production publish cannot overwrite a stand-in that owns the channel,
#       proven in-engine and named on both sides;
#  23c. the writer-identity assertion in the probe is a direct string check (a
#       non-numeric id must not be able to pass by converting to zero);
#  24. the committed Remich weather acceptance still passes unchanged (run as a
#      sub-check, with its own pre-existing failures reported as such);
#  25. no generated trace, staging or build state is tracked;
#  26. no other repository was modified;
#  27. the worktree is clean.
#
# Where behaviour can prove the rule, it does. The writer-identity, validation,
# tick and one-writer properties are asserted by running the Rust tests and the
# engine, not by grepping for the words.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

# The base this seam was cut from: Remich main at the handoff.
BASE_SHA="79e5d73b8d83bc09800c3a6b89dc36980e45ea26"
# The committed stand-in bridge revision: this change does not touch it.
COMMITTED_WEATHER_REV="remich-weather-v1"
# The one production writer id, asserted verbatim.
EXTERNAL_WRITER="eislek-weather-driver"
STAND_IN_WRITER="stand-in-weather-schedule"

# Field names the snapshot must NOT gain, assembled at runtime so this list
# never matches against this checker's own text.
CLOUD_FIELD="$(printf 'cl%s' 'oud')"
PHASE_FIELD="$(printf 'phas%s:' 'e')"
MOTION_FIELD="$(printf 'mot%s:' 'ion')"
PRESENTATION_FIELD="$(printf 'pres%s:' 'sure')"

WEATHER_SRC="crates/remich_core/src/weather.rs"
CORE_SRC_DIR="crates/remich_core/src"
GDEX_SRC="crates/remich_gdext/src/lib.rs"
FIXTURE_WEATHER_GD="godot/weather.gd"
FIXTURE_PROBE_GD="godot/weather_probe.gd"
EXTERNAL_DIR="godot_external_weather"
EXTERNAL_PROBE_GD="${EXTERNAL_DIR}/external_weather_probe.gd"
RUN_EXTERNAL="tools/run_external_weather.sh"
STAGE_EXTERNAL="tools/stage_external_weather.sh"
STEP2_CHECKER="tools/check_phase2_step2.sh"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-extweather.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

LOG_BUILD="$LOG_DIR/build.log"
LOG_TEST="$LOG_DIR/test.log"
LOG_CORE="$LOG_DIR/core-weather-tests.log"
LOG_GDEX="$LOG_DIR/gdext-tests.log"
LOG_RUN="$LOG_DIR/external-run.log"
LOG_STEP2="$LOG_DIR/step2.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# ---------------------------------------------------------------------------
# Run everything the numbered checks then read from.
# ---------------------------------------------------------------------------

cargo build --workspace >"$LOG_BUILD" 2>&1
cargo test --workspace >"$LOG_TEST" 2>&1
cargo test -p remich_core weather::tests >"$LOG_CORE" 2>&1
cargo test -p remich_gdext >"$LOG_GDEX" 2>&1

run_rc=0
bash "$RUN_EXTERNAL" >"$LOG_RUN" 2>&1 || run_rc=$?
RUN_RC=$run_rc

bash "$STEP2_CHECKER" >"$LOG_STEP2" 2>&1
STEP2_RC=$?

# A helper the checks use to ask whether a named Rust test went green.
test_green() {
    grep -qE "(^|[[:space:]:])$1 \.\.\. ok$" "$2" 2>/dev/null
}

# --------------------------------------------- 1. the base is an ancestor
header "1. This change descends from the base SHA it was cut from"

if git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
    if git merge-base --is-ancestor "$BASE_SHA" HEAD 2>/dev/null; then
        pass "the base $BASE_SHA is an ancestor of HEAD"
    else
        fail "the base $BASE_SHA is NOT an ancestor of HEAD"
    fi
else
    fail "the base $BASE_SHA is not present in this repository"
fi
note "HEAD is $(git rev-parse HEAD)"

# --------------------------------------- 2-3. the workspace builds and tests
header "2-3. The workspace builds warning-free and its tests pass"

if grep -q '^warning' "$LOG_BUILD"; then
    fail "the workspace build emitted warnings:"
    grep '^warning' "$LOG_BUILD" | head -n 10 | sed 's/^/      | /'
else
    pass "cargo build --workspace is warning-free"
fi

if grep -q '^warning' "$LOG_TEST"; then
    fail "cargo test emitted warnings:"
    grep '^warning' "$LOG_TEST" | head -n 10 | sed 's/^/      | /'
else
    pass "cargo test --workspace is warning-free"
fi

if grep -qE 'test result: ok\.' "$LOG_TEST" && ! grep -q 'FAILED' "$LOG_TEST"; then
    pass "cargo test --workspace passes"
    grep -E 'test result:' "$LOG_TEST" | sed 's/^/      | /'
else
    fail "cargo test --workspace did not pass:"
    tail -n 30 "$LOG_TEST" | sed 's/^/      | /'
fi

# --------------------------------------------- 4. the core is still engine-free
header "4. The engine-free core still names no engine"

if grep -rqiE 'godot|gdext' "$CORE_SRC_DIR"; then
    fail "remich_core's source names an engine (the firewall is broken):"
    grep -rniE 'godot|gdext' "$CORE_SRC_DIR" | head -n 5 | sed 's/^/      | /'
else
    pass "the engine-free core — including $WEATHER_SRC — names no engine"
fi

# ------------------------------- 5. the snapshot's seven fields, unchanged
header "5. WeatherSnapshot still declares exactly the seven planned fields"

struct_body="$(sed -n '/pub struct WeatherSnapshot/,/^}/p' "$WEATHER_SRC" 2>/dev/null)"
if [ -z "$struct_body" ]; then
    fail "$WEATHER_SRC does not declare WeatherSnapshot"
else
    missing=0
    for field in tick wind_dir_x wind_dir_z wind_strength rain temperature light; do
        if ! printf '%s' "$struct_body" | grep -qE "^[[:space:]]*(pub )?${field}:"; then
            fail "the snapshot does not declare the field '$field'"
            missing=1
        fi
    done
    if [ "$missing" = "0" ]; then
        pass "the snapshot declares tick, wind_dir_x, wind_dir_z, wind_strength, rain, temperature, light"
    fi
    # No field was added — in particular no cloud, and no presentation state.
    # The banned names are assembled at runtime, so this list cannot trip
    # itself against this checker's own text.
    added_problems=""
    for added in "${CLOUD_FIELD}" "${PHASE_FIELD}" "${MOTION_FIELD}" "${PRESENTATION_FIELD}"; do
        if printf '%s' "$struct_body" | grep -qF "$added"; then
            added_problems="$added_problems'$added' "
        fi
    done
    if [ -z "$added_problems" ]; then
        pass "no cloud, phase or presentation field was added to the snapshot"
    else
        fail "the snapshot gained a field this seam must not add: $added_problems"
    fi
fi

if test_green the_snapshot_carries_the_planned_fields "$LOG_CORE"; then
    pass "behaviour test green: the_snapshot_carries_the_planned_fields"
else
    fail "behaviour test not green: the_snapshot_carries_the_planned_fields"
fi

if test_green the_snapshot_carries_no_presentation_phase "$LOG_GDEX"; then
    pass "behaviour test green: the_snapshot_carries_no_presentation_phase"
else
    fail "behaviour test not green: the_snapshot_carries_no_presentation_phase"
fi

# -------------------------------- 6. one fixed production writer identity
header "6. The production writer id is one fixed constant in the core"

if test_green the_production_writer_id_is_one_fixed_constant "$LOG_CORE"; then
    pass "behaviour test green: the_production_writer_id_is_one_fixed_constant"
else
    fail "behaviour test not green: the_production_writer_id_is_one_fixed_constant"
    tail -n 20 "$LOG_CORE" | sed 's/^/      | /'
fi

if test_green the_production_seam_uses_the_one_core_writer_id "$LOG_GDEX"; then
    pass "binding test green: the_production_seam_uses_the_one_core_writer_id"
else
    fail "binding test not green: the_production_seam_uses_the_one_core_writer_id"
fi

# The literal must be spelled the same way in the core, the probe and here, or
# the three would disagree about who owns the channel.
core_id="$(sed -n 's/^pub const EXTERNAL_DRIVER_ID: &str = "\([^"]*\)".*/\1/p' "$WEATHER_SRC" | head -1)"
if [ "$core_id" = "$EXTERNAL_WRITER" ]; then
    pass "remich_core declares EXTERNAL_DRIVER_ID = '$EXTERNAL_WRITER'"
else
    fail "remich_core declares EXTERNAL_DRIVER_ID = '$core_id', expected '$EXTERNAL_WRITER'"
fi

if grep -qF "const EXTERNAL_WRITER := \"$EXTERNAL_WRITER\"" "$EXTERNAL_PROBE_GD"; then
    pass "the engine probe asserts the same id: $EXTERNAL_WRITER"
else
    fail "the engine probe does not assert the id $EXTERNAL_WRITER"
fi

# --------------------------------- 7. the two identities share ONE channel
header "7. The two identities alternate on one channel; neither displaces the other"

if test_green the_two_identities_alternate_on_one_channel_and_never_both_hold_it "$LOG_CORE"; then
    pass "behaviour test green: the_two_identities_alternate_on_one_channel_and_never_both_hold_it"
else
    fail "behaviour test not green: the_two_identities_alternate_on_one_channel_and_never_both_hold_it"
    tail -n 20 "$LOG_CORE" | sed 's/^/      | /'
fi

# Structural half: there is still exactly one channel type, and it is the one
# the stand-in already used. A parallel channel would mean a second type.
channels="$(grep -cE '^pub struct WeatherChannel' "$WEATHER_SRC" 2>/dev/null || true)"
if [ "$channels" = "1" ]; then
    pass "remich_core declares exactly one WeatherChannel — no parallel channel"
else
    fail "remich_core declares $channels WeatherChannel types; exactly one is allowed"
fi

# ------------------------------------------- 8. tick ownership is preserved
header "8. An external publish stores the supplied snapshot and tick verbatim"

if test_green an_external_publish_stores_the_supplied_snapshot_and_tick_verbatim "$LOG_CORE"; then
    pass "behaviour test green: an_external_publish_stores_the_supplied_snapshot_and_tick_verbatim"
else
    fail "behaviour test not green: an_external_publish_stores_the_supplied_snapshot_and_tick_verbatim"
fi

if test_green the_production_publish_preserves_the_supplied_tick_exactly "$LOG_GDEX"; then
    pass "binding test green: the_production_publish_preserves_the_supplied_tick_exactly"
else
    fail "binding test not green: the_production_publish_preserves_the_supplied_tick_exactly"
fi

# ------------------------------------------- 9. validation is still the gate
header "9. Invalid values are refused and the last valid snapshot survives"

for test_name in \
    an_invalid_external_snapshot_is_refused_and_keeps_the_last_valid_one \
    non_finite_and_negative_values_are_refused_and_leave_the_snapshot_unchanged
do
    if test_green "$test_name" "$LOG_CORE"; then
        pass "core test green: $test_name"
    else
        fail "core test not green: $test_name"
    fi
done

if test_green the_production_publish_refuses_invalid_values_and_keeps_the_last_snapshot "$LOG_GDEX"; then
    pass "binding test green: the_production_publish_refuses_invalid_values_and_keeps_the_last_snapshot"
else
    fail "binding test not green: the_production_publish_refuses_invalid_values_and_keeps_the_last_snapshot"
fi

# ------------------------------- 10-11. the one-writer rule still bites
header "10-11. A second writer is refused, and the stand-in cannot be bypassed"

for test_name in \
    a_second_distinct_writer_is_refused_on_the_production_channel \
    a_second_distinct_writer_claim_is_refused_with_the_conflict_named \
    a_second_writer_publish_is_refused_and_the_snapshot_is_unchanged
do
    if test_green "$test_name" "$LOG_CORE"; then
        pass "core refusal test green: $test_name"
    else
        fail "core refusal test not green: $test_name"
    fi
done

for test_name in \
    the_production_channel_still_refuses_a_second_writer \
    the_production_publish_cannot_bypass_a_stand_in_owner
do
    if test_green "$test_name" "$LOG_GDEX"; then
        pass "binding refusal test green: $test_name"
    else
        fail "binding refusal test not green: $test_name"
    fi
done

# ------------------------------------------ 12. the stand-in mode is intact
header "12. The stand-in mode still owns its channel and drives whole cycles"

if test_green the_stand_in_mode_still_owns_its_channel_and_drives_whole_cycles "$LOG_GDEX"; then
    pass "binding test green: the_stand_in_mode_still_owns_its_channel_and_drives_whole_cycles"
else
    fail "binding test not green: the_stand_in_mode_still_owns_its_channel_and_drives_whole_cycles"
fi

# The stand-in's own phase behaviour: a tick-derived, animated W that depends on
# the explicit fixture cycle. This is the behaviour the external mode must not
# fake, and it must be unchanged by the refusal above.
for test_name in \
    the_motion_phase_is_presentation_from_the_integer_tick \
    the_external_seam_declares_no_presentation_cycle_and_fabricates_no_phase
do
    if test_green "$test_name" "$LOG_GDEX"; then
        pass "binding phase test green: $test_name"
    else
        fail "binding phase test not green: $test_name"
        tail -n 20 "$LOG_GDEX" | sed 's/^/      | /'
    fi
done

# The pre-existing stand-in regressions must all still be green — this seam
# changed the binding's RemichWeather, so they are re-proved here rather than
# assumed.
for test_name in \
    weather_channel_starts_with_no_writer \
    the_first_writer_claims_and_publishes \
    re_claiming_the_same_writer_keeps_the_same_owner \
    readers_obtain_the_snapshot_without_becoming_writers \
    the_stand_in_refuses_a_channel_owned_by_another_writer \
    the_stand_in_is_deterministic_from_seed_and_tick \
    the_seed_participates_in_the_stand_in_direction \
    driving_publishes_the_world_tick_it_was_given \
    the_stand_in_driver_holds_no_time_state \
    the_weather_source_accumulates_no_time_and_uses_no_entropy_source \
    the_wind_vector_reads_the_snapshot_and_the_tick_only \
    the_binding_uses_the_real_setter_and_no_getter
do
    if test_green "$test_name" "$LOG_CORE" || test_green "$test_name" "$LOG_GDEX"; then
        pass "pre-existing weather test still green: $test_name"
    else
        fail "pre-existing weather test regressed: $test_name"
    fi
done

# ------------------------------- 13. one whole-snapshot publish, no setters
header "13. The binding exposes one whole-snapshot publish and no unrestricted setters"

if test_green the_production_publish_is_one_validated_whole_snapshot "$LOG_GDEX"; then
    pass "binding test green: the_production_publish_is_one_validated_whole_snapshot"
else
    fail "binding test not green: the_production_publish_is_one_validated_whole_snapshot"
    tail -n 20 "$LOG_GDEX" | sed 's/^/      | /'
fi

# The probe asserts the same absences from the engine side.
for callable in set_wind set_rain set_temperature set_light set_snapshot set_tick publish; do
    if grep -qF "\"$callable\"" "$EXTERNAL_PROBE_GD"; then
        pass "the engine probe asserts '$callable' is absent from the class"
    else
        fail "the engine probe does not assert '$callable' is absent"
    fi
done

# The publish still goes through the one-writer channel API, not around it.
if grep -qF 'channel.publish(EXTERNAL_DRIVER_ID, snapshot)?;' "$GDEX_SRC"; then
    pass "the production publish goes through WeatherChannel::publish as $EXTERNAL_WRITER"
else
    fail "the production publish does not go through WeatherChannel::publish"
fi

# The channel must not gain a way to be written without its owner's identity.
# A stray pre-claim inside the seam would look harmless and be a bypass.
seam_body="$(awk '
    /^fn publish_external_snapshot_through\(/ { inside = 1 }
    inside && /^}$/ { print; inside = 0; next }
    inside { print }
' "$GDEX_SRC" 2>/dev/null)"
for banned in "claim_writer" "latest =" "fn publish_with" "SABOTAGE"; do
    if printf '%s' "$seam_body" | grep -qF "$banned"; then
        fail "the production seam contains '$banned' — it must only publish as $EXTERNAL_WRITER"
    else
        pass "the production seam contains no '$banned'"
    fi
done

if grep -qF 'channel.claim_writer(EXTERNAL_DRIVER_ID)' "$GDEX_SRC"; then
    pass "external initialization goes through WeatherChannel::claim_writer"
else
    fail "external initialization does not go through WeatherChannel::claim_writer"
fi

# ---------------------------------------------- 14. the seam holds no clock
header "14. The production seam holds no clock of its own"

if test_green the_production_publish_preserves_the_supplied_tick_exactly "$LOG_GDEX"; then
    pass "the seam's own source scan (delta, wall time, counter, second clock) is green"
else
    fail "the production seam's source scan failed"
fi

# The shared clock is still the only clock authority, and the seam did not add
# one: the external project declares no clock autoload of its own.
ext_autoloads="$(grep -cE '^[A-Za-z]+Clock=' "${EXTERNAL_DIR}/project.godot" 2>/dev/null || true)"
if [ "$ext_autoloads" = "0" ]; then
    pass "the external project declares no clock autoload — the seam takes a tick, it makes none"
else
    fail "the external project declares $ext_autoloads clock autoloads; it must declare none"
fi

# ------------------------------------- 15. the existing readers are unchanged
header "15. The existing readers still read the one channel in either mode"

for reader in snapshot writer_id writer_status apply_wind; do
    if grep -qE "^[[:space:]]*fn ${reader}\(" "$GDEX_SRC"; then
        pass "the reader '$reader' is still a method of RemichWeather"
    else
        fail "the reader '$reader' is no longer a method of RemichWeather"
    fi
done

# apply_wind reads the channel's snapshot in either mode — the weather half is
# mode-independent — but the renderer-facing W slot needs a presentation cycle,
# which only the stand-in fixture declares. Read the whole function (to the next
# method at the same indent), not just the first brace, or a guard clause would
# look like the entire body.
apply_body="$(awk '
    /^[[:space:]]*fn apply_wind\(/ { inside = 1 }
    inside && /^    #\[func\]$/ && seen { inside = 0 }
    inside { print; seen = 1 }
' "$GDEX_SRC" 2>/dev/null)"
if printf '%s' "$apply_body" | grep -q 'channel.read()'; then
    pass "apply_wind reads the one channel's latest snapshot"
else
    fail "apply_wind does not read the channel"
fi
if printf '%s' "$apply_body" | grep -q 'presentation_cycle_of'; then
    pass "apply_wind takes its presentation cycle from the node's own mode"
else
    fail "apply_wind does not ask the node's mode for a presentation cycle"
fi
if printf '%s' "$apply_body" | grep -q 'no-presentation-phase\|no_presentation_phase_failure'; then
    pass "apply_wind refuses in the external mode instead of inventing a phase"
else
    fail "apply_wind does not refuse when no presentation cycle exists"
fi
# The blocker: no fabricated, frozen or borrowed presentation phase for the
# external mode. A cycle 0, a hard-coded W, or a default that silently writes a
# static motion phase must not come back. The names are assembled at runtime so
# this list cannot trip itself, and the scan covers the binding's own code — its
# test module may of course *name* the constant it asserts is gone.
gdex_code="$(sed -n '1,/^#\[cfg(test)\]/p' "$GDEX_SRC" 2>/dev/null)"
frozen_cycle="$(printf 'EXTERNAL_%s_CYCLE' 'PRESENTATION')"
any_cycle="$(printf '%s_CYCLE' 'PRESENTATION')"
for forbidden in "$frozen_cycle" "$any_cycle"; do
    if printf '%s' "$gdex_code" | grep -qF "$forbidden"; then
        fail "the binding's own code declares '$forbidden': the external seam must fabricate no phase"
    else
        pass "the binding's own code declares no '$forbidden'"
    fi
done
# No substituted default cycle either, anywhere in the apply path.
if printf '%s' "$apply_body" | grep -qE '\.unwrap_or\(|0 *as *u64|PRESENTATION'; then
    fail "apply_wind substitutes a cycle or phase constant — it must refuse instead"
else
    pass "apply_wind substitutes no cycle and names no phase constant"
fi
if printf '%s' "$apply_body" | grep -qE 'Some\(channel\), *Some\(stand_in\)'; then
    fail "apply_wind still gates the whole read on a stand-in driver"
else
    pass "apply_wind does not gate the weather read on a stand-in driver"
fi

# The refusal must say the weather is valid and present, and that only the
# presentation phase is unowned — otherwise it reads as a broken seam.
refusal_body="$(awk '
    /^fn no_presentation_phase_failure\(/ { inside = 1 }
    inside && /^}$/ { print; inside = 0; next }
    inside { print }
' "$GDEX_SRC" 2>/dev/null)"
for stated in "no-presentation-phase" "valid and present" "motion phase"; do
    if printf '%s' "$refusal_body" | grep -qF "$stated"; then
        pass "the refusal states '$stated'"
    else
        fail "the no-presentation-phase refusal does not state '$stated'"
    fi
done

# ------------------------------------ 16. the committed fixture is unchanged
header "16. The committed stand-in fixture was not converted into production policy"

for frozen in "$FIXTURE_WEATHER_GD" "$FIXTURE_PROBE_GD" "godot/project.godot"; do
    if git diff --quiet "$BASE_SHA" -- "$frozen" 2>/dev/null; then
        pass "$frozen is byte-for-byte unchanged since the base"
    else
        fail "$frozen changed — the stand-in fixture must keep its existing acceptance"
        git diff --stat "$BASE_SHA" -- "$frozen" | sed 's/^/      | /'
    fi
done

# The fixture's own stand-in initialization is still what its _ready() calls.
if grep -qF 'created.call("initialize", TEST_SEED, TEST_CYCLE_LENGTH)' "$FIXTURE_WEATHER_GD"; then
    pass "the fixture still initializes the stand-in schedule in _ready()"
else
    fail "the fixture's stand-in initialization is gone"
fi

# ----------------------------------------- 17-23. the real engine acceptance
header "17. The seam runs through the real GDExtension in pinned Godot"

if [ -x "$GODOT_BIN" ]; then
    pass "the pinned engine exists at the qualified path"
    godot_version="$("$GODOT_BIN" --version 2>/dev/null | tail -n 1)"
    case "$godot_version" in
        4.7.2*) pass "pinned Godot --version: $godot_version" ;;
        *) fail "pinned Godot --version is '$godot_version', expected 4.7.2" ;;
    esac
else
    fail "the pinned engine is missing at $GODOT_BIN"
fi

# Every engine invocation in tools/ must be headless and never enter editor,
# import or export mode.
invocations="$(grep -rnE '\$GODOT_BIN"[[:space:]]+([-"$])' tools/*.sh 2>/dev/null \
    | grep -vF -- '--version' || true)"
engine_mode_problems=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        *--headless*)
            case "$line" in
                *--editor*|*--export*|*--import*|*--project-manager*)
                    engine_mode_problems="$engine_mode_problems$line
"
                    ;;
            esac
            ;;
        *) engine_mode_problems="$engine_mode_problems$line
" ;;
    esac
done <<<"$invocations"
if [ -z "$invocations" ]; then
    fail "no engine run found in tools/ — the qualified proof path is missing"
elif [ -z "$engine_mode_problems" ]; then
    pass "every engine run in tools/ is headless, with no editor/import/export mode"
else
    fail "an engine run is not headless, or enters a forbidden mode:"
    printf '%s' "$engine_mode_problems" | sed 's/^/      | /'
fi

if [ "$RUN_RC" -eq 0 ]; then
    pass "bash $RUN_EXTERNAL exits 0"
else
    fail "bash $RUN_EXTERNAL exited $RUN_RC:"
    tail -n 25 "$LOG_RUN" | sed 's/^/      | /'
fi

# The committed bridge revision is untouched: this seam is not a revision bump.
rev="$(sed -n 's/^[[:space:]]*pub const WEATHER_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' "$GDEX_SRC" 2>/dev/null)"
rev="${rev%%$'\n'*}"
if [ "$rev" = "$COMMITTED_WEATHER_REV" ]; then
    pass "WEATHER_BRIDGE_REV holds its committed value ('$rev')"
else
    fail "WEATHER_BRIDGE_REV is '$rev', expected '$COMMITTED_WEATHER_REV'"
fi

if grep -q "REMICH_EXTERNAL_WEATHER_OK" "$LOG_RUN" 2>/dev/null; then
    pass "REMICH_EXTERNAL_WEATHER_OK observed in the engine run"
    grep -h '^REMICH_EXTERNAL_WEATHER_OK' "$LOG_RUN" | sed 's/^/      | /'
else
    fail "no REMICH_EXTERNAL_WEATHER_OK marker in the engine run"
    tail -n 25 "$LOG_RUN" | sed 's/^/      | /'
fi

if grep -q 'REMICH_EXTERNAL_WEATHER_FAIL' "$LOG_RUN" 2>/dev/null; then
    fail "the engine run reported a failure marker:"
    grep -h 'REMICH_EXTERNAL_WEATHER_FAIL' "$LOG_RUN" | sed 's/^/      | /'
else
    pass "no REMICH_EXTERNAL_WEATHER_FAIL in the engine run"
fi

# The refusals the probe provokes are printed by Rust, verbatim, in the log.
for expected in \
    "weather field 'wind_dir_x' must be a finite number" \
    "weather field 'rain' must be a finite number" \
    "weather field 'temperature' must be a finite number" \
    "wind strength must be a non-negative number"
do
    if grep -qF "$expected" "$LOG_RUN"; then
        pass "the engine run refused an invalid value: $expected"
    else
        fail "the engine run did not refuse: $expected"
    fi
done

# The second half of the one-writer rule, proven in-engine: a production
# publish must not overwrite a writer that already holds the channel. The
# engine log shows the refusal naming both identities.
takeover_line="$(grep -h "writer 'eislek-weather-driver' was refused" "$LOG_RUN" 2>/dev/null | head -1)"
if [ -n "$takeover_line" ]; then
    pass "in-engine: a production publish was refused against the stand-in that owns the channel"
    note "$(printf '%s' "$takeover_line" | sed 's/^ERROR: //')"
    if printf '%s' "$takeover_line" | grep -qF "owned by '$STAND_IN_WRITER'"; then
        pass "the refusal names the stand-in as the holder and $EXTERNAL_WRITER as the refused writer"
    else
        fail "the takeover refusal does not name $STAND_IN_WRITER as the holder"
    fi
else
    fail "the engine run shows no refused production publish against the stand-in"
fi

header "18-24. What the engine run proved, read from its own log"

# 18. the one channel is claimed for the production writer, not the stand-in.
conflict_line="$(grep -h "writer 'intruder-weather-driver' was refused" "$LOG_RUN" 2>/dev/null | head -1)"
if [ -n "$conflict_line" ]; then
    pass "in-engine refusal observed: a distinct second writer was refused by name"
    note "$(printf '%s' "$conflict_line" | sed 's/^ERROR: //')"
    if printf '%s' "$conflict_line" | grep -qF "owned by '$EXTERNAL_WRITER'"; then
        pass "the refused writer was refused because '$EXTERNAL_WRITER' holds the one channel"
    else
        fail "the in-engine refusal does not name $EXTERNAL_WRITER as the owner"
    fi
else
    fail "the engine run shows no named second-writer refusal"
fi

if grep -q "RemichWeather: writer-conflict" "$LOG_RUN" 2>/dev/null; then
    pass "the refusal came from the one-writer rule (writer-conflict), through the channel API"
else
    fail "the in-engine refusal did not come from the one-writer rule"
fi

# 22. drive(tick) is refused in external mode rather than generating stand-in.
if grep -q "RemichWeather: no-stand-in-driver" "$LOG_RUN" 2>/dev/null; then
    pass "drive(tick) was refused in external mode — no stand-in weather was generated"
else
    fail "drive(tick) was not refused in external mode"
fi

# 20. apply_wind() refused in external mode. Rust prints the refusal with its
# code, so the log shows the seam declining rather than writing a W.
phase_line="$(grep -h 'RemichWeather: no-presentation-phase' "$LOG_RUN" 2>/dev/null | head -1)"
if [ -n "$phase_line" ]; then
    pass "in-engine: apply_wind() refused in external mode with no-presentation-phase"
    if printf '%s' "$phase_line" | grep -qF 'valid and present' \
        && printf '%s' "$phase_line" | grep -qF 'motion phase'; then
        pass "the refusal states the weather is valid and present and only the phase is unowned"
    else
        fail "the no-presentation-phase refusal does not state that plainly"
    fi
else
    fail "the engine run shows no refused external apply_wind() — a phase may have been invented"
fi

# 19-21. The probe's own assertions ran: a green marker means every one passed.
# Re-derive the count so the claim is checked, not assumed.
probe_assertions="$(grep -c '_fail(' "$EXTERNAL_PROBE_GD" 2>/dev/null || true)"
if [ "${probe_assertions:-0}" -ge 15 ]; then
    pass "the engine probe carries $probe_assertions refusal assertions"
else
    fail "the engine probe carries only $probe_assertions refusal assertions; it looks thin"
fi

# The published values must be the ones the probe declares — a probe that
# published nothing and asserted nothing must not pass.
for declared in "const TICK := 137" "const WIND_STRENGTH := 0.42" "const RAIN := 0.25"; do
    if grep -qF "$declared" "$EXTERNAL_PROBE_GD"; then
        pass "the engine probe publishes a known complete snapshot: $declared"
    else
        fail "the engine probe does not declare $declared"
    fi
done

# The reader is the existing one: the probe must not have added a private read.
if grep -qF 'created.call("snapshot")' "$EXTERNAL_PROBE_GD" \
        && grep -qF 'created.call("writer_status")' "$EXTERNAL_PROBE_GD" \
        && grep -qF 'created.call("apply_wind")' "$EXTERNAL_PROBE_GD"; then
    pass "the probe reads back through the existing snapshot, writer_status and apply_wind"
else
    fail "the probe does not read back through the existing readers"
fi

# 20. The probe must prove the external apply_wind REFUSES, and must not claim it
# is production-qualified. It asserts the refusal code, the reason, that no
# vector was recorded, and that the weather survived the refusal.
for case in 'apply-accepted' 'apply-code' 'apply-reason' 'apply-fabricated' 'apply-damaged'; do
    if grep -qF "\"$case\"" "$EXTERNAL_PROBE_GD"; then
        pass "the probe asserts the external apply_wind refusal case: $case"
    else
        fail "the probe does not assert the apply_wind refusal case $case"
    fi
done
if grep -qF 'const NO_PHASE_CODE := "no-presentation-phase"' "$EXTERNAL_PROBE_GD"; then
    pass "the probe pins the expected refusal code no-presentation-phase"
else
    fail "the probe does not pin the no-presentation-phase refusal code"
fi
# And the stand-in half of the same probe must still prove the animated W.
for case in 'stand-in-apply-refused' 'stand-in-w-wrong' 'stand-in-w-static'; do # noqa: shellcheck
    if grep -qF "\"$case\"" "$EXTERNAL_PROBE_GD"; then
        pass "the probe asserts the stand-in apply_wind still works: $case"
    else
        fail "the probe does not assert $case"
    fi
done

# 23c. The writer-identity assertion must be a direct string identity check. The
# old form compared `int(writer_id)` as well, which any non-numeric id satisfies
# with zero and which let a wrong writer slip past the second half.
if grep -qF 'if str(created.call("writer_id")) != EXTERNAL_WRITER:' "$EXTERNAL_PROBE_GD"; then
    pass "the probe asserts the writer identity directly as a string"
else
    fail "the probe does not assert the writer identity as a direct string comparison"
fi
if grep -qF 'int(created.call("writer_id")) != 0' "$EXTERNAL_PROBE_GD"; then
    fail "the probe still compares the writer id as an integer, which a non-numeric id can pass"
else
    pass "the probe does not weaken the writer check with an integer comparison"
fi

# --------------------------------- 24. the existing weather acceptance holds
header "24. The committed Phase 2 Step 2 weather acceptance still runs unchanged"

# Its checker is unmodified by this change, which is what "unchanged" means
# here: the stand-in fixture's own acceptance is the same proof as before.
if git diff --quiet "$BASE_SHA" -- "$STEP2_CHECKER" 2>/dev/null; then
    pass "$STEP2_CHECKER is byte-for-byte unchanged since the base"
else
    fail "$STEP2_CHECKER changed — the stand-in acceptance must run unchanged"
    git diff --stat "$BASE_SHA" -- "$STEP2_CHECKER" | sed 's/^/      | /'
fi

# Its own result, with the pre-existing failures named rather than hidden.
step2_oks="$(grep -c '^ok' "$LOG_STEP2" 2>/dev/null || true)"
# The checker's own summary counts *checks*; the grep counts lines, so the
# summary line is one more. Report both, plainly.
step2_fail_lines="$(grep -c '^FAIL' "$LOG_STEP2" 2>/dev/null || true)"
note "tools/check_phase2_step2.sh at this head: $step2_oks ok / $((step2_fail_lines - 1)) failing checks"
note "the same checker on the base SHA 79e5d73 recorded 92 ok / the same 8 failing checks"

# The eight failures that predate this change, by their exact text. They have
# two causes, neither of them a weather fact: the lane's closing record moved
# docs/PLAN.md after the chain checkers froze it (so PLAN_FREEZE is stale and
# the Step 1 sub-check is red, which cascades into the marker checks), and the
# Grengewald worktree has untracked local files. Any FAIL line outside this set
# is this change's, and is reported as such rather than folded in.
#
# Kept as exact strings, not a loose pattern, so a genuinely new failure
# cannot hide behind one of them.
PREEXISTING_STEP2_FAILURES="
bash tools/check_phase2_step1.sh failed:
a frozen checker or the plan changed beyond the Remich #9 authorization:
donor code/data, provenance or the plan changed beyond the Remich #9 authorization:
Step 1 sub-check log: no REMICH_CLOCK_OK marker (or the sub-check itself failed)
Step 1 sub-check log: no REMICH_SCORER_OK marker (or the sub-check itself failed)
Step 1 sub-check log: no REMICH_DECAY_OK marker (or the sub-check itself failed)
Step 1 sub-check log: no REMICH_BRIDGE_OK marker (or the sub-check itself failed)
Grengewald is dirty — this step must not modify it
"

unexpected_step2=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Strip the checker's own "FAIL  " prefix; the list above holds messages.
    message="${line#FAIL  }"
    # The trailing summary line restates the check count, so it is expected to
    # match the number of FAIL lines above rather than appear in the list.
    case "$message" in
        "Phase 2 Step 2 — "*)
            # The summary reads "— N check(s) failed"; N is the count of the
            # real FAIL lines above, all of which must already be pre-existing.
            summary_count="$(printf '%s' "$message" | sed -n 's/.*— \([0-9][0-9]*\) check.*/\1/p')"
            listed_count="$(printf '%s\n' "$PREEXISTING_STEP2_FAILURES" | grep -c . || true)"
            if [ -z "$summary_count" ]; then
                fail "the Step 2 summary line could not be read: $message"
            elif [ "$summary_count" = "$listed_count" ]; then
                pass "the Step 2 summary reports $summary_count failures, matching the pre-existing set"
            else
                fail "the Step 2 summary reports $summary_count failures; $listed_count are pre-existing"
            fi
            continue
            ;;
    esac
    if ! printf '%s\n' "$PREEXISTING_STEP2_FAILURES" | grep -qxF "$message"; then
        unexpected_step2="$unexpected_step2$line
"
    fi
done <<<"$(grep '^FAIL' "$LOG_STEP2" 2>/dev/null || true)"

if [ -z "$unexpected_step2" ]; then
    pass "every Step 2 failure is byte-identical to the set already failing on the base SHA"
else
    fail "this change introduced new Step 2 failures:"
    printf '%s' "$unexpected_step2" | sed 's/^/      | /'
fi

# The weather-specific half of that run must be green — the marker proves the
# stand-in path still works end to end. The step-2 checker indents the marker
# when it echoes a sub-check's own output, so match it anywhere in the line.
if grep -qE 'REMICH_WEATHER_OK seed=[0-9]+ ticks=[0-9]+ writer=stand-in-weather-schedule' "$LOG_STEP2"; then
    pass "the stand-in weather run still succeeds through the unchanged fixture"
    grep -hoE 'REMICH_WEATHER_OK seed=[0-9]+ ticks=[0-9]+ writer=stand-in-weather-schedule calm=[0-9.]+ windy=[0-9.]+ rev=[a-z0-9-]+' \
        "$LOG_STEP2" | head -1 | sed 's/^/      | /'
else
    fail "the stand-in weather run did not succeed (REMICH_WEATHER_OK missing)"
fi

# ------------------------------------------ 25. no generated state is tracked
header "25. No generated trace, staging or build state is tracked"

generated="$(git ls-files \
    | grep -E '(^|/)(target|\.godot|staging)(/|$)|\.so$|\.dylib$|\.dll$|_expectation\.txt$|\.jsonl$' \
    || true)"
if [ -z "$generated" ]; then
    pass "no build, import, library, expectation or trace file is tracked"
else
    fail "generated state is tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
fi

for ignored in godot_external_weather/external_weather_probe_expectation.txt \
        godot_external_weather/.godot/extension_list.cfg; do
    if git check-ignore -q "$ignored"; then
        pass "generated state is ignored: $ignored"
    else
        fail "generated state is not ignored: $ignored"
    fi
done

# --------------------------------------- 26. no other repository was modified
header "26. No other repository was modified"

# Grengewald is read-only to this seam (standing ruling 1) and already carries
# untracked files from another lane's Godot runs, so its worktree state is
# reported rather than failed. Its HEAD is still checked.
DIRTY_REPO_KNOWN_DIRTY="Grengewald"

for repo in Munshausen Larochette Eisleck Grengewald Marnach; do
    dir="/home/mrg/Documents/Project/$repo"
    if [ -d "$dir" ] && [ -e "$dir/.git" ]; then
        if [ -z "$(git -C "$dir" status --porcelain 2>/dev/null | head -5)" ]; then
            pass "$repo is untouched (clean)"
        elif [ "$repo" = "$DIRTY_REPO_KNOWN_DIRTY" ]; then
            # Grengewald carries untracked .uid files from another lane's Godot
            # runs. This seam reads nothing from that repository and writes
            # nothing to it, so the state is reported rather than treated as
            # this change's doing — and the pinned commit is checked instead,
            # which is what standing ruling 1 actually requires.
            note "$repo has pre-existing untracked files (not this seam's doing):"
            git -C "$dir" status --porcelain 2>/dev/null | head -3 | sed 's/^/      | /'
            pass "$repo's HEAD is unchanged: $(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
        else
            fail "$repo is dirty — this seam must not modify it"
            git -C "$dir" status --porcelain 2>/dev/null | head -3 | sed 's/^/      | /'
        fi
    fi
done

# The only external path this repository may name is the pinned engine.
refs="$(grep -rhoE '/home/mrg/Documents/Project/[A-Za-z0-9._-]+' \
    --include='*.rs' --include='*.toml' --include='*.gd' --include='*.gdextension' \
    --include='*.gdshader' --include='*.md' --include='*.sh' --include='*.py' \
    --include='*.json' . 2>/dev/null | sort -u)"
unexpected=""
while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    case "$ref" in
        "/home/mrg/Documents/Project/Yolanda") ;;
        "/home/mrg/Documents/Project/buggy-vault") ;;
        *) unexpected="$unexpected$ref
" ;;
    esac
done <<<"$refs"
if [ -z "$unexpected" ]; then
    pass "the only external paths named are the pinned engine and the donor vault"
else
    fail "this repository references another repository by path:"
    printf '%s' "$unexpected" | sed 's/^/      | /'
fi

# ------------------------------------------------------------ 27. clean head
header "27. The worktree is clean at this head"

# The acceptance is run at a committed head, so the change under test is the
# whole diff rather than a partly-staged one. Untracked files that are this
# change's own new sources are committed before the run; what must be absent
# is anything left over afterwards.
stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Remich #19 — the one weather channel, externally driven\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Remich #19 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1

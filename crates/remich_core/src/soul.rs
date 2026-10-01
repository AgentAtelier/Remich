//! Soul primitives across the bridge (Phase 3, Step 2).
//!
//! This is an adapter, exactly like [`crate::scorer`]: it holds the donor's own
//! state and forwards to the donor's own functions. It never re-implements
//! them. Nothing here contains a weight table, a propagation formula, or any
//! rule about how an event changes an emotion — those do not exist in the
//! pinned donor and this step does not author them
//! (`docs/PLAN.md` §4b, step 2, donor audit 2026-10-01).
//!
//! ## What crosses the bridge
//!
//! 1. create a donor [`LayeredSoul`] from a seed — [`SoulFacade::from_seed`];
//! 2. read the three substrate traits and the four emotional axes —
//!    [`SoulFacade::snapshot`];
//! 3. ask the donor for a named edge strength — [`ConnectionLayer::weight`];
//! 4. call the donor's propagation — [`EmotionalAxes::propagate`].
//!
//! ## Propagated influence is not a receiver state
//!
//! [`SoulFacade::propagate`] returns [`PropagatedInfluence`]: the donor's
//! *influence values* for a connection. It takes `&self`, writes nothing back,
//! and the facade's own snapshot is unchanged afterwards. There is no
//! `target += influence`, no blending, no clamping of a receiver, no
//! aggregation over neighbours and no update ordering here — the amended plan
//! assigns all of that to the lead's Munshausen wiring, not to Remich.
//!
//! Donor references (byte-identical in this repository, `buggy-vault@24181142`):
//!
//! * `repos/anvil/source/crates/anvil_sim/src/soul.rs`
//! * `repos/anvil/source/crates/anvil_sim/src/soul/axes.rs`
//! * `repos/anvil/source/crates/anvil_sim/src/settlement/connection.rs`
//! * `repos/anvil/source/crates/anvil_sim/src/settlement/ids.rs`

use anvil_sim::settlement::connection::ConnectionLayer;
use anvil_sim::soul::axes::EmotionalAxes;
use anvil_sim::soul::LayeredSoul;

/// The three substrate traits as the donor stores them: plain `f32` fields of
/// the donor's [`anvil_sim::soul::Substrate`], read out and copied.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SubstrateSnapshot {
    /// Donor `Substrate::courage_fear`.
    pub courage_fear: f32,
    /// Donor `Substrate::generosity_selfishness`.
    pub generosity_selfishness: f32,
    /// Donor `Substrate::stability_anxiety`.
    pub stability_anxiety: f32,
}

/// The four emotional axes as the donor stores them: plain `f32` fields of the
/// donor's [`EmotionalAxes`], read out and copied.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AxesSnapshot {
    /// Donor `EmotionalAxes::security_threat`.
    pub security_threat: f32,
    /// Donor `EmotionalAxes::belonging_isolation`.
    pub belonging_isolation: f32,
    /// Donor `EmotionalAxes::agency_helplessness`.
    pub agency_helplessness: f32,
    /// Donor `EmotionalAxes::satiation_desperation`.
    pub satiation_desperation: f32,
}

/// A full read of the soul state: identity plus every donor field.
///
/// Read-only by construction: this is a copy of what the donor holds, and
/// nothing in Remich writes it back into the donor state.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SoulSnapshot {
    /// The seed this soul was created from.
    pub seed: u64,
    /// The three substrate traits.
    pub substrate: SubstrateSnapshot,
    /// The four emotional axes.
    pub axes: AxesSnapshot,
}

/// The donor's propagated influence for one connection — **not** a receiver
/// state update.
///
/// Every field is read from or computed by the donor:
/// `connection_weight` comes from [`ConnectionLayer::weight`] and `axes` from
/// [`EmotionalAxes::propagate`] called with that weight. Remich adds no
/// arithmetic of its own, and nothing ever applies these values to a soul.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PropagatedInfluence {
    /// Which donor connection layer produced this influence.
    pub layer: ConnectionLayer,
    /// The donor's edge strength for that layer (`ConnectionLayer::weight`).
    pub connection_weight: f32,
    /// The donor's per-axis influence values (`EmotionalAxes::propagate`).
    pub axes: AxesSnapshot,
}

/// Resolves a connection-layer name to the donor's enum.
///
/// A name lookup only — it maps `"family"`, `"proximity"` and `"village"` to
/// the donor's variants and holds no numeric value. The strength of a layer is
/// asked of the donor, never of this mapping.
pub fn connection_layer_from_name(name: &str) -> Option<ConnectionLayer> {
    match name {
        "family" => Some(ConnectionLayer::Family),
        "proximity" => Some(ConnectionLayer::Proximity),
        "village" => Some(ConnectionLayer::Village),
        _ => None,
    }
}

/// The donor's own display name for a connection layer.
///
/// Forwarded to the donor's `Display` impl so the string the trace records is
/// the donor's, not a Remich-owned copy of it.
pub fn connection_layer_name(layer: ConnectionLayer) -> String {
    layer.to_string()
}

/// The engine-free soul facade: one donor [`LayeredSoul`], held and forwarded.
///
/// The state lives here (plain Rust, no engine types); the behaviour lives in
/// the donor. Every method either reads the donor's fields or calls the
/// donor's functions.
pub struct SoulFacade {
    seed: u64,
    soul: LayeredSoul,
}

impl SoulFacade {
    /// Creates a soul with the donor's own seeded constructor.
    ///
    /// This is a direct call to `LayeredSoul::from_seed`; the substrate and
    /// the mood that seed produces are the donor's, unchanged.
    pub fn from_seed(seed: u64) -> Self {
        Self {
            seed,
            soul: LayeredSoul::from_seed(seed),
        }
    }

    /// The seed this soul was created from.
    pub fn seed(&self) -> u64 {
        self.seed
    }

    /// Reads back every donor field of this soul.
    pub fn snapshot(&self) -> SoulSnapshot {
        SoulSnapshot {
            seed: self.seed,
            substrate: SubstrateSnapshot {
                courage_fear: self.soul.substrate.courage_fear,
                generosity_selfishness: self.soul.substrate.generosity_selfishness,
                stability_anxiety: self.soul.substrate.stability_anxiety,
            },
            axes: axes_snapshot(&self.soul.emotional_state.axes),
        }
    }

    /// Asks the donor for this layer's edge strength.
    ///
    /// The number comes from `ConnectionLayer::weight()` — there is no
    /// Remich-owned weight table anywhere in this crate.
    pub fn connection_weight(&self, layer: ConnectionLayer) -> f32 {
        layer.weight()
    }

    /// Computes the donor's propagated influence for a named connection layer.
    ///
    /// Two donor calls and nothing else: `ConnectionLayer::weight()` for the
    /// edge strength, then `EmotionalAxes::propagate(weight)` for the four
    /// influence values. Takes `&self` and writes nothing back — the soul's
    /// own snapshot is unchanged after this call.
    pub fn propagate(&self, layer: ConnectionLayer) -> PropagatedInfluence {
        let connection_weight = layer.weight();
        PropagatedInfluence {
            layer,
            connection_weight,
            axes: axes_snapshot(&self.soul.emotional_state.axes.propagate(connection_weight)),
        }
    }

    /// The donor's propagation through an explicit edge strength.
    ///
    /// A test path: the weight is validated and then handed straight to
    /// `EmotionalAxes::propagate`. `Err` on a non-finite or out-of-range
    /// weight rather than silently substituting one.
    pub fn propagate_with_weight(&self, connection_weight: f32) -> Result<AxesSnapshot, SoulError> {
        if !connection_weight.is_finite() || !(0.0..=1.0).contains(&connection_weight) {
            return Err(SoulError::InvalidWeight(connection_weight));
        }
        Ok(axes_snapshot(
            &self.soul.emotional_state.axes.propagate(connection_weight),
        ))
    }
}

/// Why a facade request was refused. Nothing is ever substituted for it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SoulError {
    /// An explicit edge strength outside `[0.0, 1.0]`, or not finite.
    InvalidWeight(f32),
}

impl std::fmt::Display for SoulError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SoulError::InvalidWeight(weight) => {
                write!(f, "connection weight {weight} is outside [0.0, 1.0]")
            }
        }
    }
}

impl std::error::Error for SoulError {}

/// Copies the donor's four axis fields into plain data.
fn axes_snapshot(axes: &EmotionalAxes) -> AxesSnapshot {
    AxesSnapshot {
        security_threat: axes.security_threat,
        belonging_isolation: axes.belonging_isolation,
        agency_helplessness: axes.agency_helplessness,
        satiation_desperation: axes.satiation_desperation,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anvil_sim::soul::LayeredSoul;

    /// The three committed fixture seeds, identical to the ones in the
    /// standalone soul probe fixture (`soul_probe.gd`, invoked by
    /// `tools/run_soul.sh`); tools/check_phase3_step2.sh compares them.
    const FIXTURE_SEEDS: [u64; 3] = [1_000_003, 2_000_003, 3_000_003];

    /// The three donor connection layers the fixture exercises, in trace order.
    const FIXTURE_LAYERS: [ConnectionLayer; 3] = [
        ConnectionLayer::Family,
        ConnectionLayer::Proximity,
        ConnectionLayer::Village,
    ];

    fn direct_snapshot(seed: u64) -> SoulSnapshot {
        let donor = LayeredSoul::from_seed(seed);
        SoulSnapshot {
            seed,
            substrate: SubstrateSnapshot {
                courage_fear: donor.substrate.courage_fear,
                generosity_selfishness: donor.substrate.generosity_selfishness,
                stability_anxiety: donor.substrate.stability_anxiety,
            },
            axes: AxesSnapshot {
                security_threat: donor.emotional_state.axes.security_threat,
                belonging_isolation: donor.emotional_state.axes.belonging_isolation,
                agency_helplessness: donor.emotional_state.axes.agency_helplessness,
                satiation_desperation: donor.emotional_state.axes.satiation_desperation,
            },
        }
    }

    /// The facade creates exactly the soul the donor creates, field for field.
    #[test]
    fn facade_seed_matches_donor_from_seed() {
        for seed in FIXTURE_SEEDS {
            let facade = SoulFacade::from_seed(seed);
            assert_eq!(facade.seed(), seed);
            assert_eq!(facade.snapshot(), direct_snapshot(seed));
        }
    }

    /// For every fixture seed and layer: the facade's weight is the donor's
    /// weight and the facade's influence is the donor's `propagate` result —
    /// exact `f32` equality, same computation, same process.
    ///
    /// If a Remich-owned weight table or propagation formula were substituted,
    /// this fails.
    #[test]
    fn facade_propagation_is_the_donor_result_exactly() {
        for seed in FIXTURE_SEEDS {
            let facade = SoulFacade::from_seed(seed);
            let donor = LayeredSoul::from_seed(seed);
            for layer in FIXTURE_LAYERS {
                let influence = facade.propagate(layer);
                assert_eq!(
                    influence.connection_weight,
                    layer.weight(),
                    "facade weight must be ConnectionLayer::weight()"
                );
                let direct = donor.emotional_state.axes.propagate(layer.weight());
                assert_eq!(influence.axes.security_threat, direct.security_threat);
                assert_eq!(influence.axes.belonging_isolation, direct.belonging_isolation);
                assert_eq!(influence.axes.agency_helplessness, direct.agency_helplessness);
                assert_eq!(influence.axes.satiation_desperation, direct.satiation_desperation);
            }
        }
    }

    /// The explicit-weight path forwards to the donor unchanged as well.
    #[test]
    fn facade_explicit_weight_is_the_donor_result_exactly() {
        let facade = SoulFacade::from_seed(FIXTURE_SEEDS[0]);
        let donor = LayeredSoul::from_seed(FIXTURE_SEEDS[0]);
        for weight in [0.0_f32, 0.1, 0.37, 0.5, 1.0] {
            let influence = facade.propagate_with_weight(weight).expect("valid weight");
            let direct = donor.emotional_state.axes.propagate(weight);
            assert_eq!(influence.security_threat, direct.security_threat);
            assert_eq!(influence.belonging_isolation, direct.belonging_isolation);
            assert_eq!(influence.agency_helplessness, direct.agency_helplessness);
            assert_eq!(influence.satiation_desperation, direct.satiation_desperation);
        }
    }

    /// An invalid explicit weight is refused, never substituted.
    #[test]
    fn facade_refuses_an_invalid_explicit_weight() {
        let facade = SoulFacade::from_seed(FIXTURE_SEEDS[0]);
        for weight in [-0.5_f32, 1.5, f32::NAN, f32::INFINITY] {
            assert!(facade.propagate_with_weight(weight).is_err());
        }
    }

    /// The name lookup returns the donor's variants and refuses anything else.
    #[test]
    fn connection_layer_names_resolve_to_the_donor_enum() {
        assert_eq!(connection_layer_from_name("family"), Some(ConnectionLayer::Family));
        assert_eq!(connection_layer_from_name("proximity"), Some(ConnectionLayer::Proximity));
        assert_eq!(connection_layer_from_name("village"), Some(ConnectionLayer::Village));
        assert_eq!(connection_layer_from_name("stranger"), None);
        assert_eq!(connection_layer_from_name(""), None);
        for layer in FIXTURE_LAYERS {
            let name = connection_layer_name(layer);
            assert_eq!(connection_layer_from_name(&name), Some(layer));
        }
    }

    /// Propagation reads and returns; it never writes. The facade's snapshot
    /// is bit-for-bit unchanged afterwards — no receiver application exists.
    #[test]
    fn propagation_does_not_change_the_soul() {
        for seed in FIXTURE_SEEDS {
            let facade = SoulFacade::from_seed(seed);
            let before = facade.snapshot();
            for layer in FIXTURE_LAYERS {
                let _ = facade.propagate(layer);
            }
            assert_eq!(facade.snapshot(), before);
        }
    }

    /// The donor's influence for these seeds is not all zeros, so a facade
    /// that silently returned neutral values would fail here rather than pass.
    #[test]
    fn donor_influence_is_not_neutral() {
        let facade = SoulFacade::from_seed(FIXTURE_SEEDS[0]);
        let influence = facade.propagate(ConnectionLayer::Family);
        let axes = [
            influence.axes.security_threat,
            influence.axes.belonging_isolation,
            influence.axes.agency_helplessness,
            influence.axes.satiation_desperation,
        ];
        assert!(axes.iter().any(|value| *value != 0.0));
    }
}

// The stand-in tree consumer (docs/remich-weather-phase2-step2.md).
//
// This tiny shader exists ONLY to prove that Remich writes the same
// game-owned global that Grengewald's trees read: it declares
//
//     global uniform vec4 grengewald_wind
//
// exactly the name, type and component meaning of the pinned Grengewald
// contract (AgentAtelier/Grengewald@95fa08e45c919e93d62d3940f2dea032f1b724e3,
// docs/GODOT.md): X/Y = world X/Z direction, Z = gentle displacement in
// metres, W = motion phase in radians.
//
// It is NOT Grengewald rendering, not a forest addon, and not a visual
// verdict — nothing in the test project even renders it. Acceptance proves
// the write path statically (this declaration + the project's
// `shader_globals` entry) and behaviourally (the binding's real
// `RenderingServer` setter, recorded per tick by godot/weather_probe.gd).

shader_type spatial;

global uniform vec4 grengewald_wind;

void vertex() {
	// The smallest honest consumer: lean along the wind direction, scaled by
	// the displacement strength the game supplied.
	VERTEX.x += grengewald_wind.x * grengewald_wind.z;
	VERTEX.z += grengewald_wind.y * grengewald_wind.z;
}

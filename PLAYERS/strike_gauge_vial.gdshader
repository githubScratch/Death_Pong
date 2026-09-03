shader_type canvas_item;

// Fills the SAME circular footprint the old bead sprite used to occupy -
// no separate vial/glass shape, just a soft-edged disc matching the shield
// core's own silhouette (see radius/edge_softness below, tuned to match the
// old Gradient_sgauge texture's own falloff: solid to ~85% radius, fading
// to 0 by the edge). What's different from before is HOW it fills: instead
// of the whole disc scaling up from a point, a liquid level rises inside a
// fixed-size disc, and that level can slosh - see strike_gauge.gd.

// 0.0 = empty, 1.0 = full - see StrikeGauge.set_fill_ratio().
uniform float fill_level : hint_range(0.0, 1.0) = 0.0;

// Current slosh displacement, in UV units - see StrikeGauge._process()'s
// damped-spring integration, kicked by StrikeGauge.slosh() on every deflect.
uniform float wobble_amount : hint_range(-0.5, 0.5) = 0.0;

// How many wave crests cross the disc - purely a look/feel tuning knob,
// higher reads "thinner/sloppier" liquid, lower reads "thicker/calmer".
uniform float wobble_frequency : hint_range(0.0, 30.0) = 7.0;

// Static rest-state curve on the surface, independent of the slosh wave -
// a real meniscus, not a transient. Positive curves it concave (the center
// dips slightly below the edges, like liquid climbing a glass wall);
// negative curves it convex (the center domes slightly above the edges,
// like mercury). 0 is perfectly flat. See strike_gauge.gd's meniscus_amount.
uniform float meniscus_amount : hint_range(-0.15, 0.15) = 0.05;

uniform vec4 liquid_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);

// Matches the old bead texture's solid zone (~85% of the disc) and its
// fade band (~15%) - see the doc comment above.
uniform float radius : hint_range(0.0, 0.5) = 0.425;
uniform float edge_softness : hint_range(0.0, 0.3) = 0.075;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float dist_from_center = length(p);
	float radial_alpha = 1.0 - smoothstep(radius - edge_softness, radius, dist_from_center);
	if (radial_alpha <= 0.0) {
		discard;
	}

	// UV.y runs 0 (top) -> 1 (bottom), so the surface line starts at the
	// disc's bottom edge (empty) and rises toward its top edge (full). The
	// meniscus term is a fixed parabola - full strength at the center
	// (p.x = 0), fading to 0 right at the disc's edges - layered under the
	// transient slosh wave rather than replacing it. Its sign flips once the
	// gauge crosses half full (eased across a small band around 0.5 rather
	// than snapping, so the tween pouring fill_level through that midpoint
	// doesn't pop the curve inside-out in a single frame) - shallow liquid
	// climbs the walls (concave), a fuller gauge reads as domed/pressured
	// (convex) instead.
	float meniscus_sign = mix(1.0, -1.0, smoothstep(0.45, 0.55, fill_level));
	float meniscus = meniscus_amount * meniscus_sign * (1.0 - (p.x * p.x) / (radius * radius + 0.0001));
	float wave = sin(p.x * wobble_frequency + TIME * 5.0) * wobble_amount;
	float surface_y = radius - fill_level * (2.0 * radius) + wave + meniscus;
	if (p.y <= surface_y) {
		discard;
	}

	float depth = clamp((p.y - surface_y) / (2.0 * radius), 0.0, 1.0);
	vec3 shaded = mix(liquid_color.rgb * 1.2, liquid_color.rgb * 0.7, depth);
	float surface_glow = smoothstep(0.03, 0.0, abs(p.y - surface_y));
	shaded += surface_glow * 0.35;

	COLOR = vec4(shaded, liquid_color.a * radial_alpha);
}

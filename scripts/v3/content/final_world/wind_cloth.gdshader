shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;
// A windsock/ribbon follows the supplied world wind and authority phase.
uniform float phase_seconds = 0.0;
uniform float wind_strength = 0.0;
uniform float industrial = 1.0;
uniform vec4 tone : source_color = vec4(0.69, 0.63, 0.42, 1.0);
uniform vec4 edge_tone : source_color = vec4(0.87, 0.82, 0.63, 1.0);

void vertex() {
	float free_end = UV.x;
	float flutter = sin(phase_seconds * (2.2 + wind_strength) + UV.x * 8.0);
	VERTEX.x *= mix(0.38, 1.0, wind_strength);
	VERTEX.y -= (1.0 - wind_strength) * free_end * 0.28;
	VERTEX.y += flutter * free_end * 0.055 * wind_strength;
	VERTEX.z += sin(phase_seconds * 3.1 + UV.x * 10.0) * free_end * 0.12 * wind_strength;
}

void fragment() {
	float stripe = industrial > 0.5 ? step(0.72, fract(UV.x * 3.0)) : step(0.92, abs(UV.y - 0.5) * 2.0);
	ALBEDO = mix(tone.rgb, edge_tone.rgb, stripe * 0.7);
	ROUGHNESS = 0.94;
}

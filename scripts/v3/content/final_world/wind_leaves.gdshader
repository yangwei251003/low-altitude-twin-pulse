shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled, world_vertex_coords;
// Sparse bank reeds / leaf fans. Vertex motion has no collisions or facts.
uniform float phase_seconds = 0.0;
uniform vec3 wind_velocity = vec3(0.0);
uniform vec4 tone : source_color = vec4(0.35, 0.49, 0.33, 1.0);
uniform vec4 tip_tone : source_color = vec4(0.60, 0.67, 0.44, 1.0);

void vertex() {
	float tip = UV.y * UV.y;
	float flutter = 0.8 + sin(phase_seconds * 1.5 + VERTEX.x * 0.7 + VERTEX.z * 0.4) * 0.2;
	VERTEX.xz += wind_velocity.xz * tip * flutter * 0.085;
	VERTEX.y += sin(phase_seconds * 1.4 + VERTEX.x * 0.8) * tip * 0.035 * min(1.0, length(wind_velocity) / 3.6);
}

void fragment() {
	ALBEDO = mix(tone.rgb, tip_tone.rgb, UV.y * 0.55);
	ROUGHNESS = 0.96;
}

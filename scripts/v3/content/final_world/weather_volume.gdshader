shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// Explicit authority phase only. No TIME, particles, wall clock or simulation.
uniform float phase_seconds = 0.0;
uniform vec3 wind_velocity = vec3(0.0);
uniform vec4 tone : source_color = vec4(0.66, 0.79, 0.81, 0.38);
uniform float volume_height = 26.0;
uniform float dust_mode = 0.0;
uniform float weather_weight = 0.0;
varying vec4 seed;

void vertex() {
	seed = INSTANCE_CUSTOM;
	if (dust_mode < 0.5) {
		float life = fract(phase_seconds * mix(0.23, 0.34, seed.b) + seed.r);
		VERTEX.y += (0.5 - life) * volume_height;
		VERTEX.xz += wind_velocity.xz * (life - 0.5) * 0.56;
		VERTEX.xz += VERTEX.y * wind_velocity.xz * 0.012;
	} else {
		float life = fract(phase_seconds * mix(0.025, 0.045, seed.b) + seed.r);
		VERTEX.y += (life - 0.5) * volume_height * 0.64;
		VERTEX.x += sin(phase_seconds * 0.48 + seed.g * 19.0) * 0.65;
		VERTEX.z += cos(phase_seconds * 0.37 + seed.r * 13.0) * 0.65;
		VERTEX.xz += wind_velocity.xz * sin(life * 6.2831853) * 0.20;
	}
}

void fragment() {
	ALBEDO = tone.rgb;
	float edge = dust_mode > 0.5 ? (0.65 + 0.35 * sin(phase_seconds * 0.9 + seed.r * 12.0)) : 1.0;
	ALPHA = tone.a * weather_weight * edge;
}

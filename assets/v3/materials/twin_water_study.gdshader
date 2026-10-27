shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://assets/v3/materials/twin_shore_profile.gdshaderinc"

// Opaque channel water: a surface study, not fluid simulation or final art.
// Phase is explicitly driven by the existing world's clock. No implicit TIME.
uniform float wind_phase = 0.0;
uniform vec2 wind_direction = vec2(0.85, 0.52);
uniform float ripple_strength : hint_range(0.0, 0.4) = 0.13;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 direction = normalize(wind_direction + vec2(0.0001));
	vec2 cross_direction = vec2(-direction.y, direction.x);
	float a = dot(p, direction) * 1.8 - wind_phase * 1.1;
	float b = dot(p, cross_direction) * 3.2 + wind_phase * 0.7 + sin(a * 0.27);
	float wide = sin(dot(p, direction) * 0.2 - wind_phase * 0.13);
	float wave = sin(a) * 0.6 + sin(b) * 0.23;
	vec2 banks = shore_edges(p.y);
	float bank_distance = min(abs(p.x - banks.x), abs(p.x - banks.y));
	float shore = 1.0 - smoothstep(0.1, 1.1, bank_distance);
	float foam = shore * smoothstep(0.1, 0.75, wave + 0.25 + sin(p.y * 1.1 + wind_phase * 0.09) * 0.2);
	vec3 deep = mix(vec3(0.045, 0.15, 0.19), vec3(0.09, 0.25, 0.265), wide * 0.5 + 0.5);
	vec3 surface = deep * (0.94 + wave * 0.07);
	surface = mix(surface, vec3(0.37, 0.53, 0.48), foam * 0.45);
	float top = smoothstep(0.65, 0.95, world_normal.y);
	ALBEDO = mix(vec3(0.045, 0.12, 0.15), surface, top);
	ROUGHNESS = mix(0.6, 0.38 + shore * 0.15, top);
	SPECULAR = 0.38;
	vec2 slope = (direction * cos(a) * 0.6 + cross_direction * cos(b) * 0.42) * ripple_strength;
	vec3 ripple_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(world_normal, ripple_normal, top)), 0.0)).xyz);
}

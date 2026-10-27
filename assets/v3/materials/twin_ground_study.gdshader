shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://assets/v3/materials/twin_shore_profile.gdshaderinc"

// F1 development surface from a single generated basecolor reference.
// This material is not final terrain art; industrial expression is preserved.
// Real shore profile and curved functional path remain world-meter based.
uniform bool fantasy_world = false;
uniform float shore_side = 0.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.8;
uniform sampler2D forest_basecolor : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float forest_tile_metres : hint_range(2.0, 16.0) = 14.0;
uniform float forest_texture_blend : hint_range(0.0, 1.0) = 0.90;
uniform float forest_saturation : hint_range(0.0, 1.0) = 0.62;
uniform float forest_contrast : hint_range(0.0, 1.0) = 0.72;
uniform float forest_gain : hint_range(0.5, 2.0) = 1.35;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float band(float distance_to_line, float half_width, float aa) {
	return 1.0 - smoothstep(half_width, half_width + aa, abs(distance_to_line));
}

float rectangle(vec2 p, vec2 half_size, float aa) {
	vec2 d = abs(p) - half_size;
	return 1.0 - smoothstep(0.0, aa, max(d.x, d.y));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = world_position.xz;
	float bank = shore_side == 0.0 ? (p.x < 0.0 ? -1.0 : 1.0) : shore_side;
	float bank_x = p.x * bank;
	float aa = max(0.025, max(fwidth(p.x), fwidth(p.y)) * 0.8);
	float top = smoothstep(0.65, 0.95, world_normal.y);
	float broad = value_noise(p * 0.17);
	vec2 banks = shore_edges(p.y);
	float dry_distance = bank < 0.0 ? banks.x - p.x : p.x - banks.y;
	float shoreline = 1.0 - smoothstep(0.25, 3.5, dry_distance + (broad - 0.5) * 1.1);
	vec3 color = vec3(0.3);
	float rough = 0.9;
	float crevice = 0.0;

	if (!fantasy_world) {
		float wear = value_noise(p * 1.7 + vec2(17.0, 4.0));
		// Large work slabs, staggered across rows. Pattern is structural, not noise.
		vec2 slab_p = p;
		slab_p.x += mod(floor(p.y / 3.5), 2.0) * 1.7;
		vec2 slab_cell = floor(slab_p / vec2(4.2, 3.5));
		vec2 slab_local = (fract(slab_p / vec2(4.2, 3.5)) - 0.5) * vec2(4.2, 3.5);
		vec2 edge = vec2(2.1, 1.75) - abs(slab_local);
		float joint = band(min(edge.x, edge.y), 0.018, aa);
		float slab_variation = hash21(slab_cell + bank * 9.0);
		color = mix(vec3(0.30, 0.365, 0.38), vec3(0.365, 0.405, 0.415), slab_variation * 0.28 + 0.35);
		color *= 0.92 + broad * 0.16;
		color = mix(color, vec3(0.245, 0.29, 0.30), joint * 0.35);
		crevice = joint * 0.25;
		// Occasional repaired concrete inset, rather than evenly mottled ground.
		float repair_zone = smoothstep(0.57, 0.76, value_noise(p * 0.075 + vec2(13.0, -8.0)));
		float repair = rectangle(slab_local - vec2(0.35, -0.2), vec2(0.68, 0.42), aa) * step(0.89, slab_variation) * repair_zone;
		color = mix(color, vec3(0.27, 0.32, 0.33), repair * 0.45);
		// Salt and aggregate settle in broad irregular fields. These remain
		// low contrast, so a surface patch never resembles a pickup or hazard.
		float aggregate = smoothstep(0.47, 0.79, wear) * smoothstep(0.43, 0.7, broad);
		color = mix(color, color * vec3(0.84, 0.88, 0.9), aggregate * 0.38);
		// Narrow quay walk / service margin next to the water.
		float quay = 1.0 - smoothstep(12.2, 12.5, bank_x);
		color = mix(color, vec3(0.4, 0.43, 0.4) * (0.94 + broad * 0.08), quay * 0.4);
		// Authored use zones match this harbor's actual structures: the west
		// service lane ends at the work terrace; the east freight lane runs
		// outside the warehouse footprint. Neither is mirrored across the canal.
		float west = 1.0 - step(0.0, bank);
		float road_center = mix(44.0, 18.0 + smoothstep(6.0, 22.0, p.y) * 4.0, west);
		float road_x = bank_x - road_center;
		float road_extent = mix(1.0, smoothstep(3.5, 6.0, p.y), west);
		float road = (1.0 - smoothstep(2.9, 3.08, abs(road_x))) * road_extent;
		// A single delivery apron joins the eastern access lane at the beacon.
		float delivery = rectangle(p - vec2(35.0, 27.0), vec2(9.0, 5.0), aa) * (1.0 - west);
		float west_service = rectangle(p - vec2(-16.0, 14.0), vec2(4.8, 4.8), aa) * west;
		vec3 service_concrete = vec3(0.265, 0.32, 0.32) * (0.96 + broad * 0.08);
		color = mix(color, service_concrete, max(delivery, west_service) * 0.72);
		vec3 asphalt = vec3(0.105, 0.145, 0.16) * (0.95 + wear * 0.12);
		float tire_track = band(abs(road_x) - 1.35, 0.3, 0.32);
		asphalt *= 1.0 - tire_track * 0.08;
		color = mix(color, asphalt, road);
		float edge_paint = band(abs(road_x) - 2.65, 0.06, aa) * road_extent * (1.0 - delivery);
		float dash = (1.0 - smoothstep(2.2, 2.2 + aa, mod(p.y + 1.0, 6.0))) * band(road_x, 0.055, aa) * road_extent;
		float paint_wear = 0.65 + wear * 0.3;
		color = mix(color, vec3(0.68, 0.49, 0.18), max(edge_paint, dash) * paint_wear);
		// Only two marked cargo bays, beneath the two actual southern stacks.
		vec2 bay = p - vec2(31.0, p.y < 8.5 ? 5.0 : 12.0);
		float bay_border = (rectangle(bay, vec2(5.3, 3.1), aa) - rectangle(bay, vec2(5.18, 2.98), aa)) * (1.0 - west);
		color = mix(color, vec3(0.55, 0.48, 0.28), max(0.0, bay_border) * paint_wear * 0.65);
		// Recess/grate illusion is color only; real collisions remain the flat floor.
		float drain = band(road_x - 3.6, 0.16, aa) * road_extent;
		float grate = band(mod(p.y, 0.38) - 0.19, 0.045, aa);
		color = mix(color, mix(vec3(0.065, 0.105, 0.115), vec3(0.28, 0.34, 0.34), grate), drain);
		crevice = max(crevice * (1.0 - road), drain * 0.35);
		// Intermittent safety hatch at the dock edge, with a readable kept-clear band.
		float dock_work = max(rectangle(p - vec2(-10.0, 14.0), vec2(3.0, 6.0), aa), rectangle(p - vec2(10.0, 27.0), vec2(3.0, 5.0), aa));
		float edge_strip = band(bank_x - 9.1, 0.20, aa) * dock_work;
		float hatch = step(0.5, fract((p.y + bank_x) * 0.65));
		color = mix(color, mix(vec3(0.14, 0.18, 0.17), vec3(0.65, 0.49, 0.21), hatch), edge_strip * 0.65);
		float gravel_margin = smoothstep(47.0, 49.0, bank_x);
		vec2 gravel_cell = floor(p * 3.8);
		vec2 gravel_local = fract(p * 3.8) - 0.5;
		float pebble = 1.0 - smoothstep(0.19, 0.35, length(gravel_local * vec2(1.0, 1.4)));
		vec3 gravel = mix(vec3(0.2, 0.245, 0.24), vec3(0.38, 0.4, 0.35), pebble * hash21(gravel_cell));
		color = mix(color, gravel, gravel_margin * 0.75);
		color = mix(color, color * vec3(0.64, 0.77, 0.78), shoreline * 0.75);
		rough = mix(0.9 - road * 0.06, 0.43, shoreline * 0.8);
	} else {
		// Surface color only: no displacement, depth occlusion or implied collision.
		// One dominant sample retains clump-scale readability. The small secondary
		// contribution only softens repetition; seamlessness remains unproven.
		vec2 uv = p / max(2.0, forest_tile_metres);
		vec3 tex_a = texture(forest_basecolor, uv).rgb;
		vec3 tex_b = texture(forest_basecolor, vec2(-uv.y, uv.x) * 0.73 + vec2(0.317, 0.761)).rgb;
		float secondary = mix(0.04, 0.08, value_noise(p * 0.045 + vec2(7.4, -3.2)));
		vec3 tex = mix(tex_a, tex_b, secondary);
		float luminance = dot(tex, vec3(0.2126, 0.7152, 0.0722));
		tex = mix(vec3(luminance), tex, forest_saturation) * vec3(0.95, 1.0, 1.18);
		tex = mix(vec3(0.12, 0.14, 0.095), tex, forest_contrast) * forest_gain;
		// Meter-scale density changes are independent of the repeated image. Quiet
		// areas keep broad soil/moss color and a light material trace, while dense
		// areas retain the original image's middle-scale clumps. This is spatial
		// allocation, not a uniformly lowered opacity over the whole bank.
		float density_field = value_noise(p * 0.052 + vec2(1.7, -3.4));
		density_field = density_field * 0.8 + value_noise(p * 0.021 + vec2(-2.1, 4.8)) * 0.2;
		float density = smoothstep(0.32, 0.67, density_field);
		float soil_field = smoothstep(0.3, 0.7, value_noise(p * 0.075 + vec2(4.1, -2.7)));
		vec3 quiet_surface = mix(vec3(0.225, 0.235, 0.17), vec3(0.20, 0.27, 0.18), soil_field);
		quiet_surface *= 0.94 + broad * 0.12;
		float texture_weight = forest_texture_blend * mix(0.24, 1.0, density);
		color = mix(quiet_surface, tex, texture_weight);
		color *= 0.96 + value_noise(p * 0.035 + vec2(-4.0, 2.0)) * 0.08;
		// Preserve the original curving used route and its transition widths.
		float path_center = 22.0 + sin(p.y * 0.065) * 3.8 + sin(p.y * 0.19) * 0.65;
		float path_distance = abs(bank_x - path_center);
		float path = 1.0 - smoothstep(2.0, 3.2, path_distance + (broad - 0.5) * 1.3);
		float soil_variation = mix(0.84, 1.14, smoothstep(0.02, 0.28, luminance));
		vec3 mud = mix(vec3(0.245, 0.215, 0.16), vec3(0.31, 0.265, 0.19), broad) * soil_variation;
		color = mix(color, mud, path * 0.92);
		// Damp shoreline still follows the actual shared shoreline coordinates.
		color = mix(color, color * vec3(0.72, 0.82, 0.82), shoreline * 0.72);
		rough = clamp(0.95 - path * 0.06 - shoreline * 0.16 + (luminance - 0.12) * 0.06, 0.72, 0.99);
		crevice = 0.0;
	}

	// Cliff faces receive strata, not road/leaf patterns projected down their walls.
	float layers = sin(world_position.y * 3.2 + broad * 1.1) * 0.5 + 0.5;
	vec3 side_color = fantasy_world ? mix(vec3(0.18, 0.225, 0.16), vec3(0.29, 0.31, 0.22), layers) : mix(vec3(0.19, 0.24, 0.25), vec3(0.3, 0.34, 0.34), layers);
	ALBEDO = mix(side_color, color, top);
	ROUGHNESS = mix(0.94, rough, top);
	SPECULAR = mix(0.18, 0.34, shoreline * top);
	AO = 1.0 - crevice * top;
	// Small world-space surface response, faded once it becomes subpixel.
	float bump = detail_strength * (1.0 - smoothstep(0.08, 0.28, aa)) * 0.025;
	if (fantasy_world) { bump *= 0.55; }
	vec3 top_normal = normalize(vec3(sin(p.x * 7.0 + p.y) * bump, 1.0, cos(p.y * 8.0 - p.x) * bump));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(world_normal, top_normal, top)), 0.0)).xyz);
}

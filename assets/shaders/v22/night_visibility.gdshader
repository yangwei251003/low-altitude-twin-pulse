shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 pilot_position = vec3(0.0);
uniform vec3 beam_origin = vec3(0.0);
uniform vec3 beam_direction = vec3(0.0, -0.37, -0.93);
uniform float beam_range = 20.0;
uniform float beam_cos_outer = 0.78801075;
uniform float beam_cos_inner = 0.8746197;
uniform float self_radius = 4.5;
uniform float local_inner = 24.0;
uniform float local_outer = 30.0;
uniform vec4 light_pools[6];
uniform float pool_gains[6];
uniform int pool_count = 0;
uniform vec4 combat_flashes[3];
uniform float flash_gains[3];
uniform int flash_count = 0;
uniform vec3 darkness_color : source_color = vec3(0.012, 0.022, 0.038);
uniform float environment_veil = 0.22;

// Keep this rule identical to NightVisibilityV22.visibility_strength().
float visibility_at(vec3 point) {
    vec2 planar_offset = point.xz - pilot_position.xz;
    // The shared locality rule is exactly zero here, regardless of light pools.
    if (dot(planar_offset, planar_offset) >= local_outer * local_outer) return 0.0;
    float near_light = 1.0 - smoothstep(self_radius * 0.65, self_radius, distance(point, pilot_position));
    vec3 offset = point - beam_origin;
    float length_m = length(offset);
    float facing = dot(offset / max(length_m, 0.0001), beam_direction);
    float beam = smoothstep(beam_cos_outer, beam_cos_inner, facing);
    beam *= 1.0 - smoothstep(beam_range * 0.68, beam_range, length_m);
    float visible = max(near_light, beam);
    for (int i = 0; i < 6; i++) {
        if (i >= pool_count) break;
        float radius = light_pools[i].w;
        float pool = 1.0 - smoothstep(radius * 0.65, radius, distance(point, light_pools[i].xyz));
        visible = max(visible, pool * pool_gains[i]);
    }
    for (int i = 0; i < 3; i++) {
        if (i >= flash_count) break;
        float radius = combat_flashes[i].w;
        float flash = 1.0 - smoothstep(radius * 0.4, radius, distance(point, combat_flashes[i].xyz));
        visible = max(visible, flash * flash_gains[i]);
    }
    float locality = 1.0 - smoothstep(local_inner, local_outer, distance(point.xz, pilot_position.xz));
    return clamp(visible * locality, 0.0, 1.0);
}

void vertex() {
    // Godot 4.3+ reverse-Z near plane. Camera parenting prevents CPU culling.
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    float depth = texture(depth_texture, SCREEN_UV).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #endif
    // The far plane/sky has no locally illuminated geometry to reveal.
    float visible = 0.0;
    if (depth >= 0.000001) {
        vec4 reconstructed = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
        vec3 world_position = reconstructed.xyz / reconstructed.w;
        visible = visibility_at(world_position);
    }
    ALBEDO = darkness_color;
    ALPHA = (1.0 - visible) * environment_veil;
}

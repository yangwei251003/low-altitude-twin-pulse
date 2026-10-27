shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// An extra pass on the already visible opaque Body only. No vertex expansion,
// depth-test bypass, light source, shared-material mutation or nighttime guess.
// Priority 0 is below the existing nighttime veil (126), which still masks it.
uniform vec3 rim_color : source_color = vec3(0.40, 0.58, 0.62);
uniform float rim_strength : hint_range(0.0, 0.25) = 0.20;

void fragment() {
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float rim = pow(1.0 - facing, 2.2);
    ALBEDO = rim_color;
    ALPHA = 0.025 + rim_strength * rim;
}

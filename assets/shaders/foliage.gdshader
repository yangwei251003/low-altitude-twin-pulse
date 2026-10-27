shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_alpha : filter_linear_mipmap_anisotropic;
void fragment(){
	vec4 c=texture(leaf_color,UV);
	ALBEDO=c.rgb*vec3(1.0,1.1,.94);
	ALPHA=texture(leaf_alpha,UV).r;
	ALPHA_SCISSOR_THRESHOLD=.42;
	ROUGHNESS=.9;
	SPECULAR=.15;
	BACKLIGHT=ALBEDO*.25;
}

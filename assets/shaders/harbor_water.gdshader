shader_type spatial;
render_mode cull_disabled;
uniform vec4 water_color : source_color = vec4(.10,.32,.38,1.0);
varying vec3 world_pos;
void vertex(){
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	vec2 p=world_pos.xz;
	float a=sin(p.x*1.7+p.y*.6+TIME*.60);
	float b=sin(p.y*2.2-p.x*.35-TIME*.42);
	float c=sin(p.x*3.1+p.y*2.2+TIME*.75);
	float crest=pow(max(0.0,a*.40+b*.38+c*.22),14.0);
	ALBEDO=water_color.rgb*(.55+(a+b)*.025)+vec3(.16,.25,.26)*crest*.18;
	ROUGHNESS=.52;
	METALLIC=.05;
	SPECULAR=.18;
	NORMAL=normalize(NORMAL+vec3(a*.010,b*.008,0.0));
}

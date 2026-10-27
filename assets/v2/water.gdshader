shader_type spatial;
render_mode diffuse_burley;
uniform vec4 water_color : source_color = vec4(0.12,0.38,0.43,1.0);
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float waves=sin(wp.x*2.8+wp.z*1.8+TIME*0.75)*sin(wp.z*3.3-wp.x*0.5-TIME*0.55);
 float glint=pow(max(0.0,waves),8.0);
 ALBEDO=water_color.rgb*(0.94+waves*0.08)+vec3(0.12,0.20,0.18)*glint;
 ROUGHNESS=0.32; METALLIC=0.25;
}

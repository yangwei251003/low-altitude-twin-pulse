shader_type spatial;
render_mode diffuse_burley;
uniform vec3 wind_velocity = vec3(1.0,0.0,0.0);
uniform float wind_time = 0.0;
uniform float base_height = 0.0;
uniform float sway_scale = 0.025;
varying vec4 vertex_tint;
void vertex(){
 vertex_tint=COLOR;
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float anchored=smoothstep(base_height+0.25,base_height+2.4,VERTEX.y);
 vec3 bend=wind_velocity*(sin(wind_time*1.8+world.x*0.29+world.z*0.21)*0.34+0.66)*anchored*sway_scale;
 VERTEX+=(inverse(mat3(MODEL_MATRIX))*bend);
}
void fragment(){ALBEDO=vertex_tint.rgb;ROUGHNESS=0.82;}

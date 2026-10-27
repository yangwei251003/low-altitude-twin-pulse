shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled,depth_draw_never;
uniform float airflow_strength = 1.0;
uniform float weather_time = 0.0;
void vertex(){
 float travel=mod(weather_time*3.2+INSTANCE_CUSTOM.x*12.0,12.0);
 VERTEX.z+=travel;
 VERTEX.y+=sin(travel*1.4+INSTANCE_CUSTOM.y*6.0)*0.12;
}
void fragment(){ALBEDO=vec3(0.78,0.84,0.65);ALPHA=0.22*airflow_strength;}

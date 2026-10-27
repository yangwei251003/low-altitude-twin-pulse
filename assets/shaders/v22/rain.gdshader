shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled,depth_draw_never;
uniform float rain_amount = 0.0;
uniform float weather_time = 0.0;
uniform vec3 wind_velocity = vec3(0.0);
void vertex(){
 float cycle=mod(weather_time*10.0+INSTANCE_CUSTOM.x*20.0,20.0);
 VERTEX.y+=10.0-cycle;
 VERTEX.xz+=wind_velocity.xz*(cycle/10.0-1.0);
}
void fragment(){ALBEDO=vec3(0.65,0.82,0.88);ALPHA=0.32*rain_amount;}

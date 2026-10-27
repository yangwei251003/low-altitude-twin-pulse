shader_type spatial;
render_mode diffuse_burley;
uniform vec4 water_color : source_color = vec4(0.16,0.44,0.49,1.0);
uniform vec3 wind_velocity = vec3(1.0,0.0,0.0);
uniform float weather_time = 0.0;
uniform float rain_amount = 0.0;
uniform vec3 downwash_position = vec3(0.0,-100.0,0.0);
uniform float downwash_strength = 0.0;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_position.xz;
 vec2 direction=normalize(wind_velocity.xz+vec2(0.0001));
 float w=sin(dot(p,direction)*3.8-weather_time*(0.8+length(wind_velocity)*0.3));
 float crosswave=sin(dot(p,vec2(-direction.y,direction.x))*4.6+weather_time*0.7);
 float d=distance(p,downwash_position.xz);
 float wake=sin(d*11.0-weather_time*10.0)*exp(-d*0.65)*downwash_strength;
 float drizzle=sin(p.x*37.0+weather_time*14.0)*sin(p.y*43.0-weather_time*12.0)*rain_amount;
 ALBEDO=water_color.rgb*(0.97+0.04*w*crosswave+0.06*drizzle)+vec3(0.09)*max(0.0,wake);
 ROUGHNESS=0.32+rain_amount*0.15;METALLIC=0.12;
}

shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.14,0.19,0.21,1.0);
uniform int surface_kind = 0;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_position.xz;
 float grain=mix(hash(floor(p*65.0)),0.5,clamp(length(fwidth(p))*24.0,0.0,1.0));
 float patch=noise(p*0.8);
 vec3 color=base_color.rgb*(0.94+grain*0.06+patch*0.06);
 if(surface_kind==1){
  vec2 tile=fract(p/0.85);
  float seam=step(tile.x,0.021)+step(tile.y,0.021);
  color*=1.0-clamp(seam,0.0,1.0)*0.23;
  color*=0.94+hash(floor(p/0.85))*0.12;
 }
 if(surface_kind==2){
  color*=0.88+noise(p*2.0)*0.16;
  color*=0.94+noise(p*0.25)*0.08;
 }
 if(surface_kind==3){
  float seam=step(fract(p.x/0.28),0.035);
  color*=1.0-seam*0.35;
  color*=0.92+sin(p.y*30.0+hash(vec2(floor(p.x/0.28),0.0))*20.0)*0.04;
 }
 ALBEDO=color; ROUGHNESS=0.92;
}

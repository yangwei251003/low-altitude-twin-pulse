shader_type spatial;
render_mode diffuse_burley;
uniform vec4 tint : source_color=vec4(.4,.45,.36,1);
uniform float industrial=0.0;
varying vec3 world_position;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float grain(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 float variation=grain(world_position.xz*.17)*.10+grain(world_position.xz*.75)*.025;
 vec2 tile=world_position.xz/vec2(8,6);
 vec2 edge=min(fract(tile),1.0-fract(tile));
 float line=1.0-smoothstep(0.0,.012+max(fwidth(tile.x),fwidth(tile.y)),min(edge.x,edge.y));
 ALBEDO=tint.rgb*(.87+variation-line*.09*industrial);
 ROUGHNESS=.96;SPECULAR=.15;
}

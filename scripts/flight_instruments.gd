extends Control

var world
var font: Font
const CYAN=Color("9de4dc")
const ORANGE=Color("f3b05c")
const WHITE=Color("e8f0e8")
const DARK=Color("112c38")

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=get_theme_default_font()

func _process(_delta: float) -> void:
	queue_redraw()

func _text(pos: Vector2,text: String,color: Color=WHITE,size: int=15) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _point(pos: Vector3) -> Vector2:
	return world.camera.unproject_position(pos)

func _diamond(p: Vector2,r: float,color: Color,filled: bool=false) -> void:
	var polygon=PackedVector2Array([p+Vector2(0,-r),p+Vector2(r,0),p+Vector2(0,r),p+Vector2(-r,0),p+Vector2(0,-r)])
	if filled:draw_colored_polygon(polygon,color)
	else:draw_polyline(polygon,color,1.6,true)

func _draw() -> void:
	if not is_instance_valid(world.player):return
	var p=world.player
	var view=get_viewport_rect().size
	# Miniature north-up survey map: data comes from this level, never decoration.
	var map_rect=Rect2(30,628,254,216)
	draw_style_box(_card(),map_rect)
	_text(Vector2(46,650),"空域雷达  /  N ↑",CYAN,15)
	var area=Rect2(44,662,224,166)
	var b: Rect2=world.flight_bounds
	var scale_map=minf(area.size.x/b.size.x,area.size.y/b.size.y)
	var center=area.get_center()
	for island in world.map_spec.islands:
		var ir=Rect2(center+Vector2(island[0]-island[2]*.5,island[1]-island[3]*.5)*scale_map,Vector2(island[2],island[3])*scale_map)
		draw_rect(ir,Color("3a5c5e"));draw_rect(ir,Color("637c72"),false,1)
	for item in world.objectives:
		_diamond(center+Vector2(item.position.x,item.position.z)*scale_map,4,Color("779c82") if item.done else ORANGE,true)
	for item in world.supplies:
		if not item.taken:
			var s=center+Vector2(item.position.x,item.position.z)*scale_map
			draw_line(s-Vector2(3,0),s+Vector2(3,0),CYAN,2);draw_line(s-Vector2(0,3),s+Vector2(0,3),CYAN,2)
	for enemy in world.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			draw_circle(center+Vector2(enemy.position.x,enemy.position.z)*scale_map,2.5,Color("e28362"))
	var rp=center+Vector2(p.position.x,p.position.z)*scale_map
	_diamond(rp,5,CYAN,true)
	var home=center+Vector2(world.launch_point.x,world.launch_point.z)*scale_map
	draw_rect(Rect2(home-Vector2(4,4),Vector2(8,8)),CYAN,false,1.5)
	# Aircraft-space target brackets and health. Occluded contacts are not locked.
	for enemy in world.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.position.distance_to(p.position)>24:continue
		if world.camera.is_position_behind(enemy.position):continue
		var s=_point(enemy.position+Vector3.UP*.9)
		if s.x<300 or s.x>view.x-80 or s.y<170 or s.y>view.y-180:continue
		var selected=is_instance_valid(p.target) and p.target==enemy
		var w=32.0 if enemy.kind=="boss" else 17.0
		var col=ORANGE if selected else Color("ed9272")
		if selected:
			for sign_x in [-1,1]:
				for sign_y in [-1,1]:
					var corner=s+Vector2(sign_x*w,sign_y*15)
					draw_line(corner,corner-Vector2(sign_x*7,0),col,2)
					draw_line(corner,corner-Vector2(0,sign_y*6),col,2)
			draw_rect(Rect2(s+Vector2(-22,22),Vector2(44,4)),DARK)
			draw_rect(Rect2(s+Vector2(-22,22),Vector2(44*enemy.health/enemy.maximum_health,4)),col)
			_text(s+Vector2(-18,-22),"%dm"%int(p.position.distance_to(enemy.position)),col,13)
	# Navigation markers clamp to screen edges and retain distance information.
	var targets=[]
	for item in world.objectives:
		if not item.done:targets.append({"pos":item.position,"label":"任务","color":ORANGE})
	if targets.is_empty() and world.selected_mission<2:targets.append({"pos":world.launch_point,"label":"返航","color":CYAN})
	if world.selected_mission==2 and world.stage==8:targets.append({"pos":world.map_spec.boss,"label":"蜂巢","color":ORANGE})
	for item in targets:
		var s=_point(item.pos+Vector3.UP*2)
		var edge=Vector2(clampf(s.x,330,view.x-190),clampf(s.y,190,view.y-250))
		_diamond(edge,9,item.color)
		_text(edge+Vector2(14,5),item.label+" %dm"%int(p.position.distance_to(item.pos)),item.color,14)
	# Ground tether makes height legible without camera tilting.
	var drone_screen=_point(p.position)
	var ground_screen=_point(Vector3(p.position.x,.18,p.position.z))
	draw_line(ground_screen,drone_screen,Color(.62,.90,.86,.48),1.2,true)
	draw_circle(ground_screen,3,CYAN,false,1.4,true)
	# Sparse compass and two flight tapes: a familiar flight HUD, kept peripheral.
	for i in range(-4,5):
		var x=view.x*.5+i*28
		draw_line(Vector2(x,33),Vector2(x,40 if i%2 else 46),Color(.8,.9,.86,.6),1)
	_text(Vector2(view.x*.5-32,67),"固定航向",CYAN,13)
	var meter_x=view.x-55
	for i in range(6):
		var y=390-i*19
		draw_line(Vector2(meter_x-12,y),Vector2(meter_x,y),WHITE,1)
		_text(Vector2(meter_x-36,y+5),str(i),WHITE,12)
	var alt_y=390-p.position.y*19
	draw_colored_polygon(PackedVector2Array([Vector2(meter_x+3,alt_y),Vector2(meter_x+14,alt_y-6),Vector2(meter_x+14,alt_y+6)]),CYAN)
	_text(Vector2(meter_x-37,416),"高度 m",CYAN,12)

func _card() -> StyleBoxFlat:
	var style=StyleBoxFlat.new();style.bg_color=Color(.04,.12,.16,.91)
	style.border_color=Color(.34,.62,.62,.5);style.set_border_width_all(1);style.set_corner_radius_all(8)
	return style

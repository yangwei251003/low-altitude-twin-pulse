extends Control
## Layered flight-deck illustration and ambient canvas lighting.
## This is presentation artwork, not a live level. The original airframe
## schematic API remains available to the equipment and hangar screens.
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const SCENE_ART := "res://assets/ui/front/dev94/twinpulse_flightdeck.png"
static var _scene_art: Texture2D
var _accent := Color("85dbc3")
var _reduce_motion := false
var _clock := 0.0
var _draw_clock := 0.0
var _hero := false
var _scene_card := false
var _parallax := Vector2.ZERO
var _frame_id := "tr01"
var _frame: Dictionary = {}
var _read_mask: GradientTexture2D
var _top_mask: GradientTexture2D
var _bottom_mask: GradientTexture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)

func _ready() -> void:
	if _scene_art == null and ResourceLoader.exists(SCENE_ART):
		_scene_art = load(SCENE_ART) as Texture2D
	_build_masks()
	set_process(not _reduce_motion)
	queue_redraw()

func set_reduce_motion(value: bool) -> void:
	_reduce_motion = value
	if value:
		_clock = 0.0
		_parallax = Vector2.ZERO
	set_process(not value)
	queue_redraw()

func set_accent(value: Color) -> void:
	_accent = value
	queue_redraw()

func set_scene_card(value: bool = true) -> void:
	_scene_card = value
	_hero = false
	custom_minimum_size = Vector2.ZERO
	_build_masks()
	queue_redraw()

func _build_masks() -> void:
	_read_mask=_mask(PackedFloat32Array([0.0,.20,.77,1.0]) if _scene_card else PackedFloat32Array([0.0,.03,.88,1.0]),PackedColorArray([Color(.018,.075,.096,.97),Color(.018,.075,.096,.97),Color(.018,.075,.096,.06),Color(.018,.075,.096,.06)]) if _scene_card else PackedColorArray([Color(.018,.075,.096,.91),Color(.018,.075,.096,.91),Color(.018,.075,.096,.48),Color(.018,.075,.096,.48)]),false)
	_top_mask=_mask(PackedFloat32Array([0.0,1.0]),PackedColorArray([Color(.012,.045,.06,.37),Color(.012,.045,.06,0)]),true)
	_bottom_mask=_mask(PackedFloat32Array([0.0,1.0]),PackedColorArray([Color(.015,.05,.065,0),Color(.015,.05,.065,.8)]),true)

static func _mask(offsets: PackedFloat32Array, colors: PackedColorArray, vertical: bool) -> GradientTexture2D:
	var gradient:=Gradient.new()
	gradient.offsets=offsets
	gradient.colors=colors
	var texture:=GradientTexture2D.new()
	texture.width=2 if vertical else 256
	texture.height=128 if vertical else 2
	texture.fill_from=Vector2.ZERO
	texture.fill_to=Vector2.DOWN if vertical else Vector2.RIGHT
	texture.gradient=gradient
	return texture

func set_airframe(frame_id: String, definition: Dictionary = {}) -> void:
	_hero = true
	_frame_id = frame_id
	_frame = definition.duplicate(true)
	custom_minimum_size = Vector2(0,300)
	queue_redraw()

func _process(delta: float) -> void:
	if _reduce_motion or not is_visible_in_tree(): return
	_clock += minf(delta,.1)
	var target := Vector2.ZERO
	var local_mouse := get_local_mouse_position()
	if Rect2(Vector2.ZERO,size).has_point(local_mouse) and size.x > 0 and size.y > 0:
		target = (local_mouse / size - Vector2(.5,.5)) * (5.0 if _scene_card else 9.0)
	_parallax = _parallax.lerp(target,minf(delta*2.0,1.0))
	_draw_clock += delta
	if _draw_clock >= 1.0/30.0:
		_draw_clock = 0.0
		queue_redraw()

func _draw() -> void:
	if size.x < 8 or size.y < 8: return
	if _hero: _airframe_illustration()
	else: _flightdeck_background()

func _flightdeck_background() -> void:
	if _scene_art == null:
		_chart_background()
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color("061923"))
	var texture_size := _scene_art.get_size()
	if texture_size.x <= 0 or texture_size.y <= 0: return
	# One imported texture, shared by the shell and hero. Overscan gives the
	# small cursor parallax room without exposing a stretched screen edge.
	var factor := maxf((size.x+24.0)/texture_size.x,(size.y+24.0)/texture_size.y)
	var image_size := texture_size*factor
	var image_origin := (size-image_size)*.5+_parallax
	if _scene_card: image_origin.y += (image_size.y-size.y)*.06
	draw_texture_rect(_scene_art,Rect2(image_origin,image_size),false,Color(1,1,1,.92 if _scene_card else .62))
	# The hero has a protected reading zone; the shell keeps navigation and
	# page data legible while the distant deck remains visible around them.
	if _read_mask!=null: draw_texture_rect(_read_mask,Rect2(Vector2.ZERO,size),false)
	if _top_mask!=null: draw_texture_rect(_top_mask,Rect2(Vector2.ZERO,Vector2(size.x,size.y*.21)),false)
	if _bottom_mask!=null: draw_texture_rect(_bottom_mask,Rect2(Vector2(0,size.y*.79),Vector2(size.x,size.y*.21)),false)
	_ambient_deck_marks()

func _ambient_deck_marks() -> void:
	var offset := _parallax*.3
	var right := size.x-22.0
	var baseline := size.y-22.0
	# A quiet, perspective-lit berth gives the image foreground a tactile
	# connection to the actual interactive 3D model displayed above it.
	var berth := Vector2(size.x*.77,size.y*.76)+offset
	var radius := Vector2(size.x*.2,size.y*.065)
	for ring in range(3):
		_ellipse(berth,radius*(1.0+float(ring)*.19),_color(_accent,.07-float(ring)*.017),1.0)
	var beam_start := Vector2(size.x*.59,baseline-3)+offset
	draw_line(beam_start,Vector2(right,baseline-3)+offset,_color(_accent,.11),6,true)
	draw_line(beam_start,Vector2(right,baseline-3)+offset,_color(_accent,.43),1,true)
	var spark := .54 if _reduce_motion else fposmod(_clock*.037,1.0)
	var head := beam_start.lerp(Vector2(right,baseline-3)+offset,spark)
	draw_line(head-Vector2(15,0),head+Vector2(15,0),_color(_accent,.7),1.6,true)
	for index in range(16 if _scene_card else 22):
		var phase := float(index)*1.718
		var x := size.x*.48+fposmod(float(index)*79.3,size.x*.49)
		var y := fposmod(float(index)*53.7-_clock*(2.4+float(index%3)),maxf(1.0,size.y-30))+15.0
		var alpha := .13+(.5+.5*sin(_clock*.6+phase))*.13
		var at := Vector2(x,y)+offset
		draw_circle(at,1.1+float(index%2)*.35,_color(Kit.GOLD if index%4==0 else _accent,alpha))
		if index%5==0: draw_line(at-Vector2(0,4),at+Vector2(0,4),_color(_accent,alpha*.6),1,true)
	_corner(Vector2(9,9),1,1)
	_corner(Vector2(size.x-9,9),-1,1)
	_corner(Vector2(9,size.y-9),1,-1)
	_corner(Vector2(size.x-9,size.y-9),-1,-1)
	if not _scene_card:
		var font := Kit.font()
		draw_string(font,Vector2(right-172,22),"TWIN PULSE / FLIGHT DECK",HORIZONTAL_ALIGNMENT_LEFT,-1,10,_color(_accent,.35))

func _chart_background() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("071c25"))
	# A soft horizontal wash keeps left navigation readable and gives the
	# illustration side its own quiet light, without a full-screen shader.
	for index in range(32):
		var weight := float(index)/31.0
		var color := Color("071b24").lerp(Color("12343b"),weight*.68)
		draw_rect(Rect2(Vector2(size.x*float(index)/32.0,0),Vector2(size.x/32.0+1,size.y)),color)
	var origin := Vector2(size.x*.72,size.y*.62)
	var gap := 62.0
	for index in range(int(size.x/gap)+2):
		var x := float(index)*gap
		draw_line(Vector2(x,0),Vector2(x,size.y),Color(.32,.56,.58,.055),1)
	for index in range(int(size.y/gap)+2):
		var y := float(index)*gap
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(.32,.56,.58,.055),1)
	for ring in range(5):
		var radius := 118.0+float(ring)*95.0
		draw_arc(origin,radius,-2.9,.35,68,_color(_accent,.08 if ring % 2 == 0 else .045),1,true)
	var ridge := PackedVector2Array()
	for index in range(17):
		var x := size.x*.4+float(index)*size.x*.047
		var y := size.y*.78-sin(float(index)*.7)*30.0-float(index % 3)*12.0
		ridge.append(Vector2(x,y))
	draw_polyline(ridge,Color(.38,.58,.57,.12),1,true)
	var route := PackedVector2Array([Vector2(size.x*.38,size.y*.72),Vector2(size.x*.56,size.y*.49),Vector2(size.x*.72,size.y*.61),Vector2(size.x*.91,size.y*.28)])
	draw_polyline(route,_color(_accent,.16),1.2,true)
	for index in range(route.size()):
		draw_circle(route[index],3.0,_color(_accent,.34))
		if index == 2:
			var pulse := 6.0+(sin(_clock*.8)+1.0)*3.0
			draw_arc(route[index],pulse,0,TAU,24,_color(_accent,.13),1,true)
	# Fixed specks are part of the drawing, rather than random particles.
	for index in range(34):
		var p := Vector2(fposmod(float(index)*137.7+21.0,size.x),fposmod(float(index)*79.3+17.0,size.y))
		draw_circle(p,.8,Color(.7,.84,.78,.12))
	draw_line(Vector2(size.x*.38,size.y-30),Vector2(size.x-36,size.y-30),Color(.4,.6,.6,.11),1)

func _airframe_illustration() -> void:
	var rect := Rect2(Vector2(5,5),size-Vector2(10,10))
	draw_style_box(Kit.box(Color("102b35"),Color("31515a"),14,0),rect)
	var center := Vector2(size.x*.5,size.y*.49)
	var unit := minf(size.x*.33,size.y*.36)
	var drift := 0.0 if _reduce_motion else sin(_clock*.7)*2.5
	center.y += drift
	var path_color := _color(_accent,.14)
	for ring in range(3):
		_ellipse(center+Vector2(0,20),Vector2(unit*(1.0+ring*.22),unit*(.5+ring*.11)),path_color,1.0)
	draw_line(Vector2(24,center.y),Vector2(size.x-24,center.y),_color(_accent,.08),1)
	draw_line(Vector2(center.x,24),Vector2(center.x,size.y-48),_color(_accent,.08),1)
	var silhouette := str(_frame.get("silhouette","guarded_quad"))
	var rotor_count := int(_frame.get("rotor_count",4))
	var positions: Array[Vector2] = []
	if rotor_count == 6:
		for index in range(6):
			var angle := float(index)*TAU/6.0+PI/6.0
			positions.append(Vector2(cos(angle)*.82,sin(angle)*.78))
	else:
		positions = [Vector2(-.65,-.6),Vector2(.65,-.6),Vector2(-.65,.6),Vector2(.65,.6)]
	var length_ratio := clampf(float(_frame.get("length_m",1.4))/maxf(.1,float(_frame.get("width_m",1.4))),.8,1.35)
	for index in range(positions.size()):
		var at: Vector2 = positions[index]
		at.y *= length_ratio
		positions[index] = at
		var p := _project(at,center,unit)
		draw_line(center+Vector2(0,10),p+Vector2(0,10),Color("0a1c23"),17,true)
		draw_line(center,p,Color("b6c9c2"),11,true)
		draw_line(center,p,_accent,2,true)
	var radius := unit*(.215 if silhouette == "compact_x" else .245)
	for at in positions:
		var p := _project(at,center,unit)
		var ellipse := Vector2(radius,radius*.55)
		_ellipse(p+Vector2(0,8),ellipse,Color("071a22"),9)
		_ellipse(p,ellipse,Color("a6beb8"),3.0)
		_ellipse(p,ellipse*.84,_color(_accent,.47),1.0)
		if rotor_count == 8: _ellipse(p+Vector2(0,5),ellipse*.92,Color("7c9898"),2.0)
		var blade_angle := .34 if at.x > 0 else -.34
		var blade := Vector2(cos(blade_angle)*radius*.76,sin(blade_angle)*radius*.4)
		draw_line(p-blade,p+blade,Color("728e91"),3,true)
		draw_circle(p,4.1,_accent)
	var body_shape := PackedVector2Array()
	var bottom_shape := PackedVector2Array()
	var shape: Array[Vector2] = [Vector2(-.22,-.38),Vector2(.22,-.38),Vector2(.31,.15),Vector2(.16,.4),Vector2(-.16,.4),Vector2(-.31,.15)]
	if silhouette == "wide_hex_cargo": shape = [Vector2(-.33,-.36),Vector2(.33,-.36),Vector2(.39,.29),Vector2(-.39,.29)]
	for point in shape:
		var p := _project(Vector2(point.x,point.y*length_ratio),center,unit)
		body_shape.append(p)
		bottom_shape.append(p+Vector2(0,11))
	draw_colored_polygon(bottom_shape,Color("536d73"))
	draw_colored_polygon(body_shape,Color("d9e4d7"))
	var outline := body_shape.duplicate()
	outline.append(body_shape[0])
	draw_polyline(outline,Color("76999b"),1.2,true)
	var panel := PackedVector2Array()
	for point in [Vector2(-.13,-.25),Vector2(.13,-.25),Vector2(.16,.17),Vector2(-.16,.17)]: panel.append(_project(point,center,unit))
	draw_colored_polygon(panel,Color("347e79"))
	draw_line(_project(Vector2(0,-.22),center,unit),_project(Vector2(0,.12),center,unit),_accent,2.0,true)
	if silhouette == "dual_pod_attack":
		for side in [-1.0,1.0]:
			var p := _project(Vector2(side*.3,.14),center,unit)+Vector2(0,11)
			draw_line(p-Vector2(0,10),p+Vector2(0,13),Color("425d66"),9,true)
	elif silhouette == "sensor_quad":
		var lens := _project(Vector2(0,.47),center,unit)+Vector2(0,10)
		draw_circle(lens,unit*.09,Color("273f49"))
		draw_circle(lens,unit*.05,_accent)
	elif silhouette == "wide_hex_cargo":
		var cargo := center+Vector2(0,unit*.29)
		draw_rect(Rect2(cargo-Vector2(unit*.21,0),Vector2(unit*.42,unit*.16)),Color("a5a38a"))
		draw_line(cargo+Vector2(0,unit*.16),cargo+Vector2(0,unit*.23),Kit.GOLD,2,true)
	var front := _project(Vector2(0,.32),center,unit)
	draw_circle(front,3.0,Kit.GOLD)
	# Annotation corners and dimensions distinguish an editable UI schematic
	# from a claim of a live in-engine aircraft screenshot.
	_corner(Vector2(21,21),1,1)
	_corner(Vector2(size.x-21,21),-1,1)
	_corner(Vector2(21,size.y-21),1,-1)
	_corner(Vector2(size.x-21,size.y-21),-1,-1)
	var font: Font = Kit.font()
	draw_string(font,Vector2(24,39),"AIRFRAME / "+_frame_id.to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,11,_color(_accent,.8))
	draw_string(font,Vector2(24,size.y-26),"当前机体线稿",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Kit.MUTED)
	var rotor_label := "%d 旋翼" % rotor_count
	var text_width := font.get_string_size(rotor_label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
	draw_string(font,Vector2(size.x-25-text_width,size.y-26),rotor_label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Kit.MUTED)

func _corner(at: Vector2, horizontal: float, vertical: float) -> void:
	draw_line(at,at+Vector2(horizontal*17,0),_color(_accent,.58),1.2,true)
	draw_line(at,at+Vector2(0,vertical*17),_color(_accent,.58),1.2,true)

func _ellipse(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in range(41):
		var angle := float(index)*TAU/40.0
		points.append(center+Vector2(cos(angle)*radius.x,sin(angle)*radius.y))
	draw_polyline(points,color,width,true)

static func _project(point: Vector2,center: Vector2,unit: float) -> Vector2:
	return center+Vector2(point.x*.91-point.y*.38,point.x*.13+point.y*.57)*unit

static func _color(color: Color,alpha: float) -> Color:
	return Color(color.r,color.g,color.b,alpha)

extends Control
## One short page-arrival accent. Never consumes input or changes layout.
var _phase := 1.0
var _accent := Color("9de4d3")
var _tween: Tween

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func play(reduced: bool, accent: Color) -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	_accent=accent
	_phase=1.0 if reduced else 0.0
	queue_redraw()
	if reduced: return
	_tween=create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_advance,0.0,1.0,.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _advance(value: float) -> void:
	_phase=value
	queue_redraw()

func _draw() -> void:
	if _phase>=1.0 or size.x<4: return
	var x:=size.x*_phase
	var alpha:=(1.0-_phase)*.45
	for index in range(8):
		var end:=maxf(0,x-float(index)*12.0)
		draw_line(Vector2(maxf(0,end-14),2),Vector2(end,2),Color(_accent.r,_accent.g,_accent.b,alpha*(1-float(index)/8.0)),2.0,true)
	for side in [-1.0,1.0]:
		var at:=Vector2(2 if side<0 else size.x-2,8)
		draw_line(at,at+Vector2(0,32*(1-_phase)),Color(_accent.r,_accent.g,_accent.b,alpha),1.2,true)

func _exit_tree() -> void:
	if _tween and _tween.is_valid(): _tween.kill()

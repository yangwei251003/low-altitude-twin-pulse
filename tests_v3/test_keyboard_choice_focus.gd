extends SceneTree
## Native Interface/Control dispatch only. No MAIN, aircraft, profile or Story.
const Interface = preload("res://scripts/v3/twin_interface.gd")
var interface: CanvasLayer
var checks: Array=[]
var actions: Array=[]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	interface=Interface.new()
	root.add_child(interface)
	interface.menu.hide()
	interface.hud.show()
	interface.controller_navigation=false
	interface.action_requested.connect(func(action: String,payload: Dictionary): actions.append({"action":action,"payload":payload.duplicate(true)}))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/choices.json"))
	var offer: Dictionary=data.choices["I2:chapter_choice"].duplicate(true)
	offer.target_id="I2:chapter_choice"
	interface.chapter_choice.show_offer(offer)
	await process_frame
	await process_frame
	var boxes: Array=interface.chapter_choice.find_children("*","CheckBox",true,false)
	_check(boxes.size()==2,"actual authored panel contains two explicit acknowledgements")
	for button: BaseButton in boxes:
		_check(button.focus_mode==Control.FOCUS_ALL,"keyboard modal retains native focus without joypad mode")
	for button: BaseButton in boxes:
		await _accept(button)
		_check(button.button_pressed,"native ui_accept really toggles its acknowledged CheckBox")
	var reads: Array=actions.filter(func(row: Dictionary): return row.action=="campaign_choice_read")
	_check(reads.size()==2,"only the two actual GUI toggles emit explicit read requests")
	var choose: Button=interface.chapter_choice._buttons[1]
	_check(not choose.disabled,"two acknowledged options enable the real proposal button")
	await _accept(choose)
	var proposals: Array=actions.filter(func(row: Dictionary): return row.action=="campaign_choice_propose")
	_check(proposals.size()==1 and proposals[0].payload.option=="balanced_service" and not interface.chapter_choice.visible,"native ui_accept activates the selected original GUI proposal signal once")
	await process_frame
	var hud_focus := false
	for button: BaseButton in interface.hud.find_children("*","BaseButton",true,false):
		if button.is_visible_in_tree() and button.focus_mode!=Control.FOCUS_NONE: hud_focus=true
	_check(not hud_focus,"closing the modal removes native focus from flight HUD buttons")
	interface.free()
	await process_frame
	var failed: Array=checks.filter(func(row: Dictionary): return not row.passed)
	print("KEYBOARD_CHOICE_FOCUS_RESULT "+JSON.stringify({"checks":checks,"failures":failed,"actions":actions,"scope":"Native Interface Controls and synthetic ui_accept press/release only. Actual authored I2 offer; no MAIN/Store/choice transaction, OS keyboard, real controller or human usability acceptance."}))
	quit(0 if failed.is_empty() else 1)

func _accept(button: BaseButton) -> void:
	# A just-enabled button gets modal focus eligibility on the next UI frame.
	await process_frame
	button.grab_focus()
	await process_frame
	_check(button.has_focus(),"focused native modal control keeps focus across an ordinary UI frame")
	var press:=InputEventAction.new()
	press.action=&"ui_accept"
	press.pressed=true
	press.strength=1.0
	Input.parse_input_event(press)
	await process_frame
	var release:=InputEventAction.new()
	release.action=&"ui_accept"
	release.pressed=false
	Input.parse_input_event(release)
	await process_frame

func _check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"label":label})

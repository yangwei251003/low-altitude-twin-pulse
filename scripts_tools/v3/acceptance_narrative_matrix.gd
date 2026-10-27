extends SceneTree
## Pure presentation matrix; copies never enter a Store or session.
const Final = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const Field = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
var output := ""
var rows: Array = []
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var chain_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source-chain="): chain_path=arg.trim_prefix("--source-chain=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		else: quit(2); return
	if not chain_path.is_absolute_path() or not "/normal-chain-20261022_" in chain_path.replace("\\","/") or not output.is_absolute_path() or FileAccess.file_exists(output): quit(2); return
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chain_path))
	if chain.get("state")!="complete" or chain.get("completed",[]).size()!=16 or chain.get("target",{}).get("app_version")!=ProjectSettings.get_setting("application/config/version"): quit(2); return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chain.completed[-1].report))
	var state: Dictionary = source.fresh_reader.world.actions.opening
	if state.completed.size()!=84 or not Final.ending_ready(state): quit(2); return
	for first: String in Final.CHOICES["I2:twin_pump_guardian:decision"]:
		for second: String in Final.CHOICES["F2:mirror_evidence:decision"]:
			for third: String in Final.CHOICES["I4:prism_array:decision"]:
				for last: String in Final.CHOICES["F4:twin_vein_core:decision"]:
					var view: Dictionary = state.duplicate(true)
					view.choices = {"I2:twin_pump_guardian:decision":first,"F2:mirror_evidence:decision":second,"I4:prism_array:decision":third,"F4:twin_vein_core:decision":last}
					var cards: Array = Final.ending_cards(view)
					var people: Array = Final.character_outcomes(view)
					var journals: Array = Final.journal_rows(view)
					var ending: Dictionary = Field.ending(view.choices)
					var ids: Array = []
					var ok: bool = cards.size()==18 and people.size()==13 and journals.size()==8 and ending.get("ending_id")==last
					for card: Dictionary in cards:
						ok = ok and not str(card.id).is_empty() and card.id not in ids and not str(card.title).is_empty() and not card.lines.is_empty()
						ids.append(card.id)
						for line: String in card.lines: ok = ok and not line.strip_edges().is_empty()
					for entry: Dictionary in journals: ok = ok and not entry.lines.is_empty() and entry.get("mode")=="archive"
					# Each earlier choice must render its own authored consequence card.
					var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Final.SOURCE))
					for key: String in ["I2:twin_pump_guardian:decision","F2:mirror_evidence:decision","I4:prism_array:decision"]:
						ok = ok and str(authored.choices[key][view.choices[key]].id) in ids
					rows.append({"choices":view.choices,"ok":ok,"ending":ending.get("ending_id"),"cards":cards.size(),"characters":people.size(),"regional_revisits":journals.size(),"card_ids":ids})
					if not ok: failures.append(rows[-1])
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"source_chain":chain_path,"passed":rows.size()==24 and failures.is_empty(),"rows":rows,"failures":failures,
		"scope":"Read-only 24-combination presentation matrix derived from the genuine natural84 report. Dictionary copies only: no world save, progress or choice commit. This is not 24 natural playthroughs, human experience, graphics or input evidence; actual nine GUI choice transactions are reported separately."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("NARRATIVE_MATRIX ",report.passed," rows=",rows.size()," output=",output)
	quit(0 if report.passed else 1)

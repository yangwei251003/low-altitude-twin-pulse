"""Produce editable, exact-subtitle Mandarin voice authoring manifests.

Authoring only: no game, tests, playback, profiles, checkpoints or networking.
All outputs stay in this content batch's exclusive data/assets directories.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
EXPECTED = Path(".").resolve()
DATA = ROOT / "data/v3/content/dev88_presentation"
ASSET_PREFIX = "res://assets/v3/content/dev88_presentation/voices/"
KEY_RE = re.compile(r"\{[^{}]+\}|\[[^\]]+\]|[A-Za-z0-9_+\-⌘]+|空格|回车|鼠标[左右中]键|方向键")


def read(relative):
    return json.loads((ROOT / relative.removeprefix("res://")).read_text(encoding="utf-8-sig"))


def normalize(text):
    return re.sub(r"\s+", "", KEY_RE.sub("", text.strip()))


def spoken(text):
    replacements = {"{contact}": "联络键", "{ability}": "能力键", "{brake}": "制动键"}
    for before, after in replacements.items():
        text = text.replace(before, after)
    return text.replace("2kg", "两公斤").replace("NPC", "联络员")


def collect():
    if ROOT != EXPECTED:
        raise RuntimeError("wrong real project root")
    characters = read("data/v3/content/dev88_presentation/presentation.json")["characters"]
    clips, routes, aliases, signatures, source_paths = [], {}, {}, {}, set()
    by_character, by_speaker, by_text = {}, {}, {}
    normal_by_character, normal_by_speaker, normal_by_text = {}, {}, {}
    old_summaries = {row["text"] for row in read("data/v3/content/presentation_next/radio_lines.json")["lines"]}

    def person(character_id, speaker_name):
        if character_id in characters:
            return characters[character_id]
        for row in characters.values():
            if row["name"] in speaker_name:
                return row
        if character_id.startswith("F"):
            return {"voice": "Microsoft Yaoyao", "rate": 0, "name": speaker_name or "地区联络"}
        return {"voice": "Microsoft Huihui Desktop", "rate": 0, "name": speaker_name or "无线电引导"}

    def normalized_insert(target, key, text, cue):
        value = normalize(text)
        if not value:
            return
        dest = target.setdefault(key, {}) if key is not None else target
        old = dest.get(value)
        # Numeric/input normalization is a fallback only. Different authored
        # lines collapsing to one key remain silent instead of guessing.
        if old is None:
            dest[value] = (text, cue)
        elif old[0] != text:
            dest[value] = ("", "")

    def add(character_id, speaker_name, text, source, route, requested_cue=""):
        text = str(text).strip()
        if not text or text in old_summaries:
            return ""
        profile = person(character_id, speaker_name)
        voice, rate = str(profile.get("voice", "Microsoft Huihui Desktop")), int(profile.get("rate", 0))
        speaker_name = speaker_name or str(profile.get("name", "无线电引导"))
        signature = (character_id, voice, rate, text)
        if signature in signatures:
            clip = signatures[signature]
        else:
            identity = json.dumps(signature, ensure_ascii=False, separators=(",", ":"))
            cue = "vo88_" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
            clip = {"cue_id": cue, "file": ASSET_PREFIX + cue + ".wav", "character_id": character_id,
                    "speaker_name": speaker_name, "text": text, "spoken_text": spoken(text),
                    "voice": voice, "rate": rate, "sources": []}
            clips.append(clip)
            signatures[signature] = clip
        cue = clip["cue_id"]
        if source not in clip["sources"]:
            clip["sources"].append(source)
        source_paths.add(source.split("#", 1)[0])
        if route:
            if cue not in routes.setdefault(route, []):
                routes[route].append(cue)
        if requested_cue:
            aliases[requested_cue] = cue
        if character_id:
            by_character.setdefault(character_id, {})[text] = cue
            normalized_insert(normal_by_character, character_id, text, cue)
        if speaker_name:
            by_speaker.setdefault(speaker_name, {})[text] = cue
            normalized_insert(normal_by_speaker, speaker_name, text, cue)
        by_text.setdefault(text, cue)
        normalized_insert(normal_by_text, None, text, cue)
        return cue

    def group(character_id, speaker_name, lines, source, route, cue_base=""):
        if isinstance(lines, str):
            lines = [lines]
        for index, line in enumerate(lines or []):
            requested = (cue_base if index == 0 else cue_base + "_%02d" % (index + 1)) if cue_base else ""
            add(character_id, speaker_name, line, source + "/" + str(index), route, requested)

    def dialogue_effects(value, source, route):
        if isinstance(value, dict):
            if value.get("type") == "dialogue" and isinstance(value.get("lines"), list):
                group(str(value.get("character_id", "")), str(value.get("speaker_name", "")), value["lines"], source, route)
                return
            for key, child in value.items():
                dialogue_effects(child, source + "/" + str(key), route)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                dialogue_effects(child, source + "/" + str(index), route)

    index = read("data/v3/campaign/index.json")
    main_paths = ["data/v3/actions/opening_actions.json"] + [p.removeprefix("res://") for p in index["base_extension_paths"] + index["extension_paths"]]
    for path in main_paths:
        document = read(path)
        for character in document.get("characters", []):
            group(character["id"], character["name"], character.get("greeting_lines", []), path + "#characters/" + character["id"], character["id"] + ":greeting")
        for action in document.get("actions", []):
            dialogue_effects(action, path + "#actions/" + str(action["id"]), str(action["id"]))

    field_path = "data/v3/content/npc_story_next/field_stories.json"
    fields = read(field_path)["regions"]
    for region, row in fields.items():
        for stage in ("entry", "boss_before", "boss_after", "transition"):
            group(row["main_character"], row["chapter_speaker"], row.get(stage, []), field_path + "#regions/" + region + "/" + stage, region + ":" + stage)
        for stage in ("offer", "complete"):
            group(region + ":field_contact_next", row["speaker_name"], row.get(stage, []), field_path + "#regions/" + region + "/" + stage, region + ":field_visit:" + stage)

    revisits_path = "data/v3/campaign/postboss_revisits.json"
    for reaction in read(revisits_path).get("reactions", []):
        for variant in reaction.get("variants", []):
            route = str(reaction["target_id"]) + ":revisit:" + str(variant.get("option", ""))
            group(str(reaction.get("character_id", "")), "", variant.get("lines", []), revisits_path + "#" + route, route)

    choices_path = "data/v3/campaign/choices.json"
    for target, offer in read(choices_path)["choices"].items():
        if offer.get("review_only"):
            continue
        character_id = {"I2": "npc:linlan", "F2": "npc:shuyao", "I4": "npc:wenxu", "F4": "npc:guanzhi"}.get(target[:2], "")
        for option in offer.get("options", []):
            route = "choice:" + target + ":" + option["id"]
            for field in ("benefit", "cost", "baseline", "consequence"):
                add(character_id, "", option[field], choices_path + "#" + route + "/" + field, route + ":" + field)
            # The chapter panel displays these fields together. Only the
            # player's explicit option-read action requests this whole-item
            # explanation; it is not a queued multi-caption radio exchange.
            full = "收益：" + option["benefit"] + "负担：" + option["cost"] + "保底：" + option["baseline"] + "后续：" + option["consequence"]
            add(character_id, "", full, choices_path + "#" + route + "/full_explicit_read", route + ":full")

    ending_path = "data/v3/content/npc_story_next/ending_stories.json"
    endings = read(ending_path)
    for ending_id, row in endings["endings"].items():
        group("npc:guanzhi", "冠枝", row["lines"], ending_path + "#endings/" + ending_id, "ending:" + ending_id)
        for still_index, still in enumerate(row.get("stills", [])):
            group("npc:guanzhi", "冠枝", still["lines"], ending_path + "#endings/" + ending_id + "/stills/" + str(still_index), "ending:" + ending_id + ":still:" + str(still_index))
    for objective, variants in endings.get("choice_consequences", {}).items():
        for option, lines in variants.items():
            group("npc:guanzhi", "冠枝", lines, ending_path + "#consequences/" + objective + "/" + option, "consequence:" + objective + ":" + option)
    group("npc:guanzhi", "冠枝", endings.get("shared_coda", []), ending_path + "#shared_coda", "ending:shared_coda")

    for filename in ("npc_sidejob_i1.json", "npc_sidejob_i2.json", "npc_sidejob_f2.json", "npc_sidejob_i3.json"):
        path = "data/v3/campaign/" + filename
        row = read(path)
        for stage in ("offer", "ready", "consequence"):
            add(str(row.get("npc_id", "")), "", row.get(stage, ""), path + "#" + stage, str(row["id"]) + ":" + stage)

    new_path = "data/v3/content/dev88_story/side_stories.json"
    for row in read(new_path).get("jobs", []):
        for source_field, suffix in (("offer", "offer"), ("accepted", "accept"), ("ready", "ready"), ("complete", "complete")):
            group(str(row["character_id"]), str(row["speaker_name"]), row.get(source_field, []),
                  new_path + "#" + str(row["id"]) + "/" + source_field,
                  str(row["id"]) + ":" + suffix, str(row["voice_base"]) + "_" + suffix)

    def flatten_normal(mapping, nested):
        if nested:
            return {key: {line: pair[1] for line, pair in rows.items() if pair[1]} for key, rows in mapping.items()}
        return {line: pair[1] for line, pair in mapping.items() if pair[1]}

    events = {}
    cue_index = {}
    for clip in clips:
        events[clip["cue_id"]] = {"files": [clip["file"]], "bus": "ui", "gain_db": -5.0, "range_m": 1.0,
                                   "priority": 8, "cooldown_ms": 100, "voice": True}
        cue_index[clip["cue_id"]] = {"text": clip["text"], "character_id": clip["character_id"], "speaker_name": clip["speaker_name"]}
    for alias, original in aliases.items():
        events[alias] = events[original].copy()
        cue_index[alias] = cue_index[original]
    manifest = {
        "schema": 1, "content_id": "dev88_temporary_mandarin_key_dialogue", "status": "developed_not_playtested",
        "voice_status": "explicitly_synthetic_local_key_dialogue_not_human_performances_not_all_dialogue",
        "source_documents": sorted(source_paths), "sample_rate": 22050, "clips": clips,
        "routes": routes, "cue_index": cue_index, "aliases": aliases,
        "by_character": by_character, "by_speaker": by_speaker, "by_text": by_text,
        "normalized_by_character": flatten_normal(normal_by_character, True),
        "normalized_by_speaker": flatten_normal(normal_by_speaker, True),
        "normalized_by_text": flatten_normal(normal_by_text, False),
        "normalization_pattern": KEY_RE.pattern,
        "notes": ["One WAV per actually displayed subtitle line. No whole-dialogue automatic playback.",
                  "All original primary campaign dialogue effects, eight contact greetings, post-Boss replies, chapter choices, ending cards, existing optional key exchanges and the new fifteen short side stories are covered.",
                  "Old Dev87 radio summary WAVs are not duplicated in this manifest.",
                  "Button names in speech use neutral action names; exact captions and input labels remain owned by the original interface.",
                  "No engine, game tests, playback, human listening or final mixing was performed by this production script."]
    }
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "voice_lines.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (DATA / "audio_events.json").write_text(json.dumps({"schema": 1, "events": events, "loops": {}, "status": "developed_not_playtested"}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"authored_lines": len(clips), "event_definitions_including_aliases": len(events), "sources": len(source_paths)}, ensure_ascii=False))


if __name__ == "__main__":
    collect()

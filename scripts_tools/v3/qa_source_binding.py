"""Strict read-only provenance for eight explicit exported MAIN QA entries.

This module never opens profile files, writes Store state, launches an engine,
changes goal arrays, or hashes a historical executable.
"""
from pathlib import Path
import hashlib
import json
import os
import re
from storage_policy import StoragePolicy, plain_path

BINDING_LIMIT = 16 * 1024
REPORT_LIMIT = 8 * 1024 * 1024
INPUTS_LIMIT = 1024 * 1024
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
HEX32 = re.compile(r"[0-9a-f]{32}\Z")
# entry: source count, final count, current receipt constant, predecessor flag/region
CONTRACTS = {
    "normal-f1": (9, 17, "SOURCE_RECEIPTS_SHA256", "first_segment_complete", "F1"),
    "normal-whale": (17, 19, "SEVENTEEN_DIGEST", "f1_segment_complete", "I1"),
    "normal-crown": (19, 23, "NINETEEN_DIGEST", "whale_segment_complete", "I1"),
    "normal-underdeck": (23, 27, "TWENTYTHREE_DIGEST", "crown_segment_complete", "F1"),
    "normal-clinic": (27, 31, "TWENTYSEVEN_DIGEST", "underdeck_segment_complete", "I1"),
    "normal-distribution": (31, 34, "THIRTYONE_DIGEST", "clinic_segment_complete", "I2"),
    "normal-canal": (34, 38, "THIRTYFOUR_DIGEST", "distribution_segment_complete", "I2"),
    "normal-i2-boss": (38, 42, "THIRTYEIGHT_DIGEST", "canal_segment_complete", "I2"),
    "normal-f2": (42, 46, "FORTYTWO_DIGEST", "i2_boss_segment_complete", "I2"),
    "normal-f2-boss": (46, 50, "FORTYSIX_DIGEST", "f2_segment_complete", "F2"),
    "normal-i3": (50, 58, "FIFTY_DIGEST", "f2_boss_segment_complete", "F2"),
    "normal-f3": (58, 66, "FIFTYEIGHT_DIGEST", "i3_segment_complete", "I3"),
    "normal-i4": (66, 75, "SIXTYSIX_DIGEST", "f3_segment_complete", "F3"),
    "normal-f4": (75, 84, "SEVENTYFIVE_DIGEST", "i4_segment_complete", "I4"),
}


PREFIX_COUNTS = {'SOURCE_RECEIPTS_SHA256': 9, 'FIRST_NINE_DIGEST': 9, 'SEVENTEEN_DIGEST': 17, 'NINETEEN_DIGEST': 19, 'TWENTYTHREE_DIGEST': 23, 'TWENTYSEVEN_DIGEST': 27, 'THIRTYONE_DIGEST': 31}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def receipt_digest(rows):
    return hashlib.sha256(canonical(rows)).hexdigest()


def _fail(message):
    raise RuntimeError("QA source binding: " + message)


def _keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        _fail(label + " keys must match exactly")


def _pairs(rows):
    result = {}
    for key, value in rows:
        if key in result:
            _fail("duplicate JSON key: " + key)
        result[key] = value
    return result


def _read(path, maximum, digest=None):
    path = plain_path(path, existing=True)
    if not path.is_file() or path.stat().st_size > maximum:
        _fail("bounded regular JSON required: " + str(path))
    data = path.read_bytes()
    if len(data) > maximum:
        _fail("JSON grew beyond limit")
    if digest is not None and (not isinstance(digest, str) or not HEX64.fullmatch(digest)
                               or hashlib.sha256(data).hexdigest() != digest):
        _fail("exact JSON SHA256 differs: " + str(path))
    try:
        return json.loads(data.decode("utf-8-sig"), object_pairs_hook=_pairs,
                          parse_constant=lambda text: _fail("non-finite JSON: " + text))
    except (ValueError, UnicodeError) as error:
        _fail("invalid JSON: " + str(error))


def add_binding_arguments(parser):
    parser.add_argument("--source-binding", type=Path, required=True,
                        help="Strict explicit QA source-binding JSON; never imports progress")
    parser.add_argument("--source-binding-sha256", required=True,
                        help="Exact SHA256 of that bounded binding JSON")


def _goal_array(text, name):
    match = re.search(r"^const " + re.escape(name) + r" := (\[.*\])$", text, re.M)
    if not match:
        _fail("compiled goal array absent: " + name)
    rows = json.loads(match.group(1))
    if not isinstance(rows, list) or any(not isinstance(v, str) for v in rows):
        _fail("compiled goal array invalid")
    return rows


def _evidence_path(value, project, state_root):
    if not isinstance(value, str) or not value:
        _fail("absolute source evidence path required")
    path = plain_path(value, existing=True)
    roots = (plain_path(project / "artifacts" / "v3", existing=True),
             plain_path(state_root / "evidence", existing=True))
    if path.suffix.lower() != ".json" or not any(path.is_relative_to(root) for root in roots):
        _fail("source JSON must remain in ordinary managed/project evidence")
    return path


def _integral(value):
    return type(value) in (int, float) and value >= 1 and int(value) == value


def _source(spec, *, project, state_root, profile, goals, success, region, target, segment=None):
    _keys(spec, ("report_path", "report_sha256", "inputs_path", "inputs_sha256",
                 "receipts_sha256"), "source")
    if any(not isinstance(spec[k], str) or not HEX64.fullmatch(spec[k])
           for k in ("report_sha256", "inputs_sha256", "receipts_sha256")):
        _fail("source digest format")
    path = _evidence_path(spec["report_path"], project, state_root)
    inputs_path = _evidence_path(spec["inputs_path"], project, state_root)
    if inputs_path.name != "inputs.json" or inputs_path.parent != path.parent:
        _fail("source report and inputs.json must share an evidence directory")
    report = _read(path, REPORT_LIMIT, spec["report_sha256"])
    inputs = _read(inputs_path, INPUTS_LIMIT, spec["inputs_sha256"])
    if not isinstance(report, dict) or not isinstance(inputs, dict):
        _fail("source report/inputs must be objects")
    terminal = "record" if success in ("whale_segment_complete", "crown_segment_complete") else "complete"
    preservation = report.get("preservation", {})
    native = report.get("native_exit", {})
    audio = native.get("audio", {})
    fresh = report.get("fresh_reader", {})
    world = fresh.get("world", {})
    story = world.get("actions", {}).get("opening", {})
    if (report.get("complete") is not True or report.get(success) is not True
            or report.get("requested_stage_stopped") is not False
            or report.get("requested_stage") != terminal
            or report.get("failures") != [] or report.get("engine_errors") != []
            or report.get("exported_application") is not True
            or report.get("profile") != profile["name"]
            or report.get("status", {}).get("completed") != goals
            or report.get("status", {}).get("region") != region
            or any(preservation.get(k) is not True for k in
                   ("original_prefix_preserved", "current_SaveGate_completed", "fresh_Story_matches_live"))
            or native.get("through") != "session._quit" or native.get("requested") is not True
            or native.get("observed_scene_exit") is not True or native.get("watchdog_failed") is not False
            or audio.get("ready") is not True or audio.get("started") is not True
            or audio.get("pending_references") != 0 or audio.get("pending") != []
            or fresh.get("profile_id") != profile["id"] or fresh.get("lineage_id") != profile["lineage"]
            or fresh.get("loaded", {}).get("ok") is not True
            or fresh.get("loaded", {}).get("recovered", False) is not False
            or fresh.get("prefix_validation", {}).get("ok") is not True
            or not _integral(fresh.get("generation"))
            or world.get("branch_id") != "main" or world.get("region_id") != region
            or story.get("completed") != goals or world.get("completed_objectives") != goals):
        _fail("complete natural source/save/identity/native-audio evidence rejected")
    if segment is not None and report.get("segment") != segment:
        _fail("independent predecessor segment differs")
    rows = report.get("story_receipts")
    if (not isinstance(rows, dict) or rows != story.get("receipts") or len(rows) != len(goals)
            or any(not isinstance(v, dict) or v.get("objective_id") not in goals for v in rows.values())
            or len({v["objective_id"] for v in rows.values()}) != len(goals)
            or receipt_digest(rows) != spec["receipts_sha256"]):
        _fail("exact source receipts differ from fresh Store report")
    before, after, process = inputs.get("before"), inputs.get("after"), inputs.get("process", {})
    if (inputs.get("unchanged") is not True or not isinstance(before, dict) or not before or before != after
            or any(not isinstance(v, str) or not HEX64.fullmatch(v) for v in before.values())
            or inputs.get("execution_failure") is not None
            or inputs.get("native_exit_leak_lines", []) != []
            or type(process.get("returncode")) is not int or process["returncode"] != 0
            or process.get("timed_out") is not False or process.get("orphan_cleanup") is not False
            or type(process.get("remaining_owned_processes")) is not int
            or process["remaining_owned_processes"] != 0 or process.get("passed") is not True):
        _fail("source requires natural Job zero, no cleanup, and unchanged tracked inputs")
    executable = report.get("executable")
    artifact = inputs.get("artifact_sha256")
    normalize = lambda value: os.path.normcase(os.path.normpath(value))
    if (not isinstance(executable, str) or not isinstance(artifact, str) or not HEX64.fullmatch(artifact)
            or normalize(executable) != normalize(target["exe_path"]) or artifact != target["exe_sha256"]
            or not any(normalize(str(k)) == normalize(executable) and value == artifact
                       for k, value in before.items())):
        _fail("source executable identity absent from stable inputs; no EXE rehash is attempted")
    return {"path": path, "inputs_path": inputs_path, "spec": spec,
            "report": report, "rows": rows, "generation": int(fresh["generation"])}


class Binding:
    def __init__(self, path, digest, data, values, primary, base50=None):
        self.path, self.sha256, self.data = path, digest, data
        self.values, self.primary, self.base50 = values, primary, base50
        self.report_path = primary["path"]
        self.metadata = {"source_binding_path": str(path), "source_binding_sha256": digest,
                         "source_goal_contract_sha256": data["goal_contract_sha256"],
                         "start_generation": data["start_generation"],
                         "source_binding_exe_sha256_verified_by": "cli_dev_file_sha256",
                         "source_binding_target_exe_sha256": data["target"]["exe_sha256"],
                         "source_binding_target_app_version": data["target"]["app_version"],
                         "source_binding_target_protocol": data["target"]["protocol"]}

    def evidence_files(self):
        rows = [Path(__file__).resolve(), self.path, self.primary["path"], self.primary["inputs_path"]]
        if self.base50:
            rows += [self.base50["path"], self.base50["inputs_path"]]
        return list(dict.fromkeys(rows))

    def cli_args(self):
        return ["--qa-source-binding=" + str(self.path),
                "--qa-source-binding-sha256=" + self.sha256]

    def verify_target(self, executable, file_sha256):
        target = self.data["target"]
        executable = plain_path(executable, existing=True)
        if (executable.suffix.lower() != ".exe" or "godot" in executable.name.lower()
                or plain_path(target["exe_path"], existing=True) != executable
                or file_sha256(executable) != target["exe_sha256"]):
            _fail("selected target EXE must match binding through existing dev.file_sha256")

    def validate_output(self, report):
        profile = self.data["profile"]
        fresh = report.get("fresh_reader", {})
        reported = report.get("source_binding_path")
        if (not isinstance(reported, str) or plain_path(reported, existing=True) != self.path
                or report.get("source_binding_sha256") != self.sha256
                or report.get("source_goal_contract_sha256") != self.data["goal_contract_sha256"]
                or report.get("source_profile_id") != profile["id"]
                or report.get("source_lineage_id") != profile["lineage"]
                or fresh.get("profile_id") != profile["id"] or fresh.get("lineage_id") != profile["lineage"]
                or report.get("source_generation") != self.data["start_generation"]
                or report.get("source_binding_target_exe_sha256") != self.data["target"]["exe_sha256"]
                or report.get("source_binding_target_sha256_verification") != "cli_inputs_required"):
            _fail("observer binding/initial generation/original identity differs")


def load_binding(path, digest, *, project, entry, segment=""):
    project = plain_path(project, existing=True)
    policy = StoragePolicy(project=project)
    path = plain_path(path, existing=True)
    if entry not in CONTRACTS or (segment not in ("tasks", "boss") if entry == "normal-i3" else segment != ""):
        _fail("unknown fixed entry/segment")
    data = _read(path, BINDING_LIMIT, digest)
    if path.read_bytes().strip() != canonical(data):
        _fail("binding must be canonical UTF-8 JSON without BOM or pretty formatting")
    _keys(data, ("version", "entry", "segment", "profile", "start_generation", "sources",
                 "goal_contract_sha256", "target"), "binding")
    if type(data["version"]) is not int or data["version"] != 1 or data["entry"] != entry or data["segment"] != segment:
        _fail("version/entry/segment mismatch")
    target = data["target"]
    _keys(target, ("exe_path", "exe_sha256", "app_version", "protocol"), "target")
    if (not isinstance(target["exe_path"], str) or not Path(target["exe_path"]).is_absolute()
            or not isinstance(target["exe_sha256"], str) or not HEX64.fullmatch(target["exe_sha256"])
            or not isinstance(target["app_version"], str) or not target["app_version"]
            or type(target["protocol"]) is not int or target["protocol"] < 1):
        _fail("explicit target EXE/SHA/app version/protocol required")
    profile = data["profile"]
    _keys(profile, ("name", "id", "lineage"), "profile")
    if (not isinstance(profile["name"], str) or not re.fullmatch(r"qa_[A-Za-z0-9_-]{1,88}", profile["name"])
            or any(not isinstance(profile[k], str) or not HEX32.fullmatch(profile[k]) for k in ("id", "lineage"))
            or type(data["start_generation"]) is not int or data["start_generation"] < 1):
        _fail("explicit QA profile identity/positive integral starting generation required")
    count, final_count, receipt_name, success, region = CONTRACTS[entry]
    node = project / "scripts" / "v3" / "qa" / ("twin_" + entry.replace("-", "_") + "_qa.gd")
    node = plain_path(node, existing=True)
    if node.stat().st_size > 256 * 1024:
        _fail("bounded original observer source required")
    text = node.read_text(encoding="utf-8-sig")
    original = _goal_array(text, "SOURCE_GOALS")
    expected = _goal_array(text, "EXPECTED")
    if len(original) != count or len(expected) != final_count or expected[:count] != original:
        _fail("compiled source/final goal counts or prefix changed")
    goals = original
    if entry == "normal-i3" and segment == "boss":
        goals = expected[:54]
        receipt_name, success, region = "FIFTYFOUR_DIGEST", "i3_segment_complete", "I3"
    contract = receipt_digest([entry, segment, goals, expected])
    if data["goal_contract_sha256"] != contract:
        _fail("compiled goal contract SHA differs")
    wanted_sources = ("primary", "base50") if entry == "normal-i3" and segment == "boss" else ("primary",)
    _keys(data["sources"], wanted_sources, "sources")
    predecessor_segment = "tasks" if entry == "normal-i3" and segment == "boss" else ("boss" if entry == "normal-f3" else None)
    primary = _source(data["sources"]["primary"], project=project, state_root=policy.root,
                      profile=profile, goals=goals, success=success, region=region, target=target, segment=predecessor_segment)
    values = {"SOURCE_PROFILE": profile["name"], "SOURCE_REPORT": str(primary["path"]),
              "SOURCE_REPORT_SHA256": primary["spec"]["report_sha256"],
              receipt_name: primary["spec"]["receipts_sha256"]}
    for name, count in PREFIX_COUNTS.items():
        if count <= len(goals):
            values[name] = receipt_digest({k: v for k, v in primary["rows"].items()
                                           if v["objective_id"] in goals[:count]})
    base50 = None
    if entry == "normal-i3" and segment == "boss":
        base50 = _source(data["sources"]["base50"], project=project, state_root=policy.root,
                         profile=profile, goals=original, success="f2_boss_segment_complete", region="F2", target=target)
        actual50 = {k: v for k, v in primary["rows"].items() if v["objective_id"] in original}
        if (primary["path"] == base50["path"] or actual50 != base50["rows"]
                or primary["report"].get("source_report_sha256") != base50["spec"]["report_sha256"]
                or primary["report"].get("source_receipts_sha256") != base50["spec"]["receipts_sha256"]
                or primary["generation"] < base50["generation"]):
            _fail("independent54 must preserve exactly the actual independent50 source")
        values.update({"SOURCE54_REPORT": str(primary["path"]),
                       "SOURCE54_REPORT_SHA256": primary["spec"]["report_sha256"],
                       "SOURCE_REPORT": str(base50["path"]),
                       "SOURCE_REPORT_SHA256": base50["spec"]["report_sha256"],
                       "FIFTY_DIGEST": base50["spec"]["receipts_sha256"]})
    if data["start_generation"] < primary["generation"]:
        _fail("starting generation cannot precede genuine source report")
    return Binding(path, digest, data, values, primary, base50)

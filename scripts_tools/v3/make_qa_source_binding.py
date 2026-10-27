"""Generate one bounded QA metadata binding; never launches or imports Store."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid
import dev
import qa_source_binding as sb
from storage_policy import plain_path


def digest(path, limit):
    path = plain_path(path, existing=True)
    if not path.is_file() or path.stat().st_size > limit:
        sb._fail("bounded regular input required")
    raw = path.read_bytes()
    if len(raw) > limit:
        sb._fail("input grew beyond limit")
    return hashlib.sha256(raw).hexdigest()


def source(path):
    path = plain_path(path, existing=True)
    report = sb._read(path, sb.REPORT_LIMIT)
    inputs = path.parent / "inputs.json"
    return {"report_path": str(path), "report_sha256": digest(path, sb.REPORT_LIMIT),
            "inputs_path": str(inputs), "inputs_sha256": digest(inputs, sb.INPUTS_LIMIT),
            "receipts_sha256": sb.receipt_digest(report.get("story_receipts"))}, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entry", required=True, choices=sorted(sb.CONTRACTS))
    parser.add_argument("--segment", choices=("", "tasks", "boss"), default="")
    parser.add_argument("--primary-report", "--report", dest="primary_report", type=Path, required=True)
    parser.add_argument("--base50-report", type=Path)
    parser.add_argument("--profile-file", type=Path, required=True)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    boss = args.entry == "normal-i3" and args.segment == "boss"
    if (args.entry == "normal-i3") != bool(args.segment) or boss != bool(args.base50_report):
        parser.error("I3 requires tasks|boss; only boss requires independent --base50-report")
    policy = dev.POLICY
    output = plain_path(args.output)
    if (output.suffix.lower() != ".json" or not output.is_relative_to(policy.path("evidence"))
            or output.exists()):
        sb._fail("new explicit managed evidence JSON output required")
    policy.preflight("evidence", sb.BINDING_LIMIT + 4096)
    exe = plain_path(args.exe, existing=True)
    current = policy._index().get("current")
    if not current or exe != policy.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"):
        sb._fail("only the actual managed current EXE is accepted")
    build = sb._read(exe.parent / "BUILD.json", 16 * 1024)
    if (not isinstance(build.get("version"), str) or not build["version"]
            or type(build.get("network_protocol")) is not int or build["network_protocol"] < 1):
        sb._fail("actual BUILD version/protocol missing")
    version = re.search(r'^config/version="([^"]+)"$', (dev.ROOT / "project.godot").read_text(encoding="utf-8-sig"), re.M)
    protocol = re.search(r'^const PROTOCOL = ([0-9]+)(?:[ \t]*#.*)?$', (dev.ROOT / "scripts/v3/twin_network.gd").read_text(encoding="utf-8-sig"), re.M)
    if not version or not protocol or build["version"] != version[1] or build["network_protocol"] != int(protocol[1]):
        sb._fail("BUILD version/protocol differ from current compiled source contract")
    target = {"exe_path": str(exe), "exe_sha256": dev.file_sha256(exe),
              "app_version": build["version"], "protocol": build["network_protocol"]}
    if target["exe_sha256"] != build.get("exe_sha256"):
        sb._fail("actual BUILD/target SHA differs")
    primary, report = source(args.primary_report)
    if not isinstance(report.get("user_dir"), str):
        sb._fail("actual source user_dir missing")
    user_root = plain_path(report["user_dir"], existing=True)
    if user_root.name != "LowAltitudeTwinPulseV3":
        sb._fail("actual source user_dir differs from V3 application")
    profile_path = plain_path(args.profile_file, existing=True)
    profile_root = plain_path(user_root / "profiles_v3", existing=True)
    match = re.fullmatch(r"profile_g([0-9]{1,15})\.json", profile_path.name)
    name = profile_path.parent.name
    if (profile_path.parent.parent != profile_root or not match
            or not re.fullmatch(r"qa_[A-Za-z0-9_-]{1,88}", name)):
        sb._fail("explicit actual QA generation file under profiles_v3 required")
    profile_sha = digest(profile_path, 16 * 1024 * 1024)
    envelope = sb._read(profile_path, 16 * 1024 * 1024)
    sb._keys(envelope, ("format", "schema_version", "payload_json", "payload_sha256"), "profile envelope")
    serialized = envelope["payload_json"]
    if (type(envelope["format"]) is not int or envelope["format"] != 1
            or not sb._integral(envelope["schema_version"]) or envelope["schema_version"] != 3
            or not isinstance(serialized, str)
            or hashlib.sha256(serialized.encode("utf-8")).hexdigest() != envelope["payload_sha256"]):
        sb._fail("profile payload_json SHA/schema rejected")
    payload = json.loads(serialized, object_pairs_hook=sb._pairs,
                         parse_constant=lambda value: sb._fail("non-finite profile JSON"))
    generation = payload.get("generation")
    if (not sb._integral(payload.get("schema_version")) or payload["schema_version"] != 3
            or not sb._integral(generation) or generation != int(match[1])
            or generation > 9007199254740991
            or any(not isinstance(payload.get(k), str) or not sb.HEX32.fullmatch(payload[k])
                   for k in ("profile_id", "lineage_id"))):
        sb._fail("profile generation/UUID/lineage rejected")
    node = dev.ROOT / "scripts/v3/qa" / ("twin_" + args.entry.replace("-", "_") + "_qa.gd")
    text = node.read_text(encoding="utf-8-sig")
    original, expected = (sb._goal_array(text, key) for key in ("SOURCE_GOALS", "EXPECTED"))
    goals = expected[:54] if boss else original
    world = payload.get("world", {})
    story = world.get("actions", {}).get("opening", {})
    completed = story.get("completed")
    allowed = [goals] + ([expected[:80]] if args.entry == "normal-f4" else [])
    rows = story.get("receipts", {})
    source_rows = report.get("story_receipts", {})
    if (world.get("branch_id") != "main" or payload.get("branches", {}).get("main", {}).get("world") != world
            or completed not in allowed or world.get("completed_objectives") != completed
            or not isinstance(rows, dict) or len(rows) != len(completed)
            or any(not isinstance(v, dict) or v.get("objective_id") not in completed for v in rows.values())
            or len({v["objective_id"] for v in rows.values()}) != len(completed)
            or {k: v for k, v in rows.items() if v["objective_id"] in goals} != source_rows):
        sb._fail("actual main profile/source receipt prefix rejected")
    sources = {"primary": primary}
    if boss:
        sources["base50"] = source(args.base50_report)[0]
    data = {"version": 1, "entry": args.entry, "segment": args.segment,
            "profile": {"name": name, "id": payload["profile_id"], "lineage": payload["lineage_id"]},
            "start_generation": int(generation), "sources": sources,
            "goal_contract_sha256": sb.receipt_digest([args.entry, args.segment, goals, expected]), "target": target}
    raw = sb.canonical(data)
    if len(raw) > sb.BINDING_LIMIT:
        sb._fail("binding exceeds16KiB")
    binding_sha = hashlib.sha256(raw).hexdigest()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("xb") as stream:
            stream.write(raw)
        binding = sb.load_binding(temporary, binding_sha, project=dev.ROOT, entry=args.entry, segment=args.segment)
        binding.verify_target(exe, dev.file_sha256)
        if digest(profile_path, 16 * 1024 * 1024) != profile_sha:
            sb._fail("explicit profile changed during metadata validation")
        temporary.rename(output)
    finally:
        if temporary.exists():
            temporary.unlink()
    print(json.dumps({"binding": str(output), "sha256": binding_sha, "bytes": len(raw),
                      "profile_file": str(profile_path), "profile_file_sha256": profile_sha,
                      "generation": int(generation), "target_sha256": target["exe_sha256"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

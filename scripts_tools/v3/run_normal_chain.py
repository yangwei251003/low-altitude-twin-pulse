"""One immutable graphical exported MAIN, one fresh natural profile, 16 boundaries."""
import argparse
import contextlib
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import uuid
sys.dont_write_bytecode = True
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# label, original entry, independent segment, final goals, original timeout, success, region
STEPS = [
    ("campaign", "normal-campaign", "", 9, 300, "first_segment_complete", "F1"),
    ("F1", "normal-f1", "", 17, 300, "f1_segment_complete", "I1"),
    ("Whale", "normal-whale", "", 19, 300, "whale_segment_complete", "I1"),
    ("Crown", "normal-crown", "", 23, 300, "crown_segment_complete", "F1"),
    ("Underdeck", "normal-underdeck", "", 27, 300, "underdeck_segment_complete", "I1"),
    ("Clinic", "normal-clinic", "", 31, 600, "clinic_segment_complete", "I2"),
    ("Distribution", "normal-distribution", "", 34, 600, "distribution_segment_complete", "I2"),
    ("Canal", "normal-canal", "", 38, 600, "canal_segment_complete", "I2"),
    ("I2Boss", "normal-i2-boss", "", 42, 600, "i2_boss_segment_complete", "I2"),
    ("F2", "normal-f2", "", 46, 600, "f2_segment_complete", "F2"),
    ("F2Boss", "normal-f2-boss", "", 50, 600, "f2_boss_segment_complete", "F2"),
    ("I3tasks", "normal-i3", "tasks", 54, 600, "i3_segment_complete", "I3"),
    ("I3boss", "normal-i3", "boss", 58, 600, "i3_segment_complete", "I3"),
    ("F3", "normal-f3", "", 66, 600, "f3_segment_complete", "F3"),
    ("I4", "normal-i4", "", 75, 900, "i4_segment_complete", "I4"),
    ("F4", "normal-f4", "", 84, 900, "f4_segment_complete", "F4"),
]


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def identity(path):
    s = path.stat()
    return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns]


def small_hash(path):
    path = plain_path(path, existing=True)
    require(path.is_file() and path.stat().st_size <= 1024 * 1024, "bounded small source required")
    before = identity(path)
    value = hashlib.sha256(path.read_bytes()).hexdigest()
    require(identity(path) == before, "small source changed while reading")
    return value


def tracked_files():
    names = ["project.godot", "scripts/v3/twin_app.gd", "scripts/v3/twin_session.gd",
             "scripts/v3/twin_network.gd", "scripts/v3/gameplay/twin_opening_story.gd",
             "scripts/v3/core/twin_world_store.gd", "scripts/v3/gameplay/actions/twin_action_director.gd",
             "scripts/v3/gameplay/twin_ability_rules.gd", "scripts/v3/qa/twin_source_binding.gd",
             "scripts/v3/qa/twin_normal_flight_pilot.gd",
             "scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd",
             "scripts_tools/v3/dev.py", "scripts_tools/v3/storage_policy.py",
             "scripts_tools/v3/qa_source_binding.py", "scripts_tools/v3/make_qa_source_binding.py",
             "data/v3/actions/opening_actions.json", "data/v3/regions.json"]
    names += ["scripts/v3/qa/twin_" + e.replace("-", "_") + "_qa.gd" for _, e, *_ in STEPS]
    paths = [project / n for n in names] + list((project / "data/v3/campaign").glob("*actions.json"))
    return sorted(set(paths + [Path(__file__).resolve()]), key=str)


def pinned_inputs(m):
    exe = plain_path(m["target"]["exe_path"], existing=True)
    require(policy._index().get("current") == m["candidate"], "managed current candidate changed")
    require(exe == policy.path("builds", m["candidate"], "LowAltitudeTwinPulse-Dev.exe"), "EXE path changed")
    require(identity(exe) == m["exe_identity"], "immutable EXE identity changed; stop without rehash")
    require(not exe.with_suffix(".pck").exists(), "this chain requires the current embedded-PCK export")
    build = sb._read(exe.parent / "BUILD.json", 16 * 1024)
    require((build.get("version"), build.get("network_protocol"), build.get("exe_sha256"), build.get("exe_bytes")) ==
            (m["target"]["app_version"], m["target"]["protocol"], m["target"]["exe_sha256"], exe.stat().st_size), "BUILD changed")
    values = {str(p): small_hash(p) for p in tracked_files()}
    values[str(exe.parent / "BUILD.json")] = small_hash(exe.parent / "BUILD.json")
    require(values == m["small_inputs"], "tracked source/BUILD/coordinator changed")
    require(dev.file_sha256(exe) == m["target"]["exe_sha256"], "cached current EXE proof differs")
    return {**values, str(exe): m["target"]["exe_sha256"]}


def profile_file(report, m, goals):
    root = plain_path(report["user_dir"], existing=True)
    require(root.name == "LowAltitudeTwinPulseV3", "actual V3 user_dir required")
    folder = plain_path(root / "profiles_v3" / m["profile"], existing=True)
    paths = [plain_path(p, existing=True) for p in folder.iterdir() if p.name.startswith("profile_g")]
    require(1 <= len(paths) <= 3, "require only actual retained 1..3 generations")
    observed, current = {}, None
    for path in paths:
        match = re.fullmatch(r"profile_g([0-9]{1,15})\.json", path.name)
        require(match and path.is_file(), "unexpected generation/temp file; no recovery fallback")
        observed[str(path)] = identity(path)
        row = sb._read(path, 16 * 1024 * 1024)
        sb._keys(row, ("format", "schema_version", "payload_json", "payload_sha256"), "retained envelope")
        text = row["payload_json"]
        require(type(row["format"]) is int and row["format"] == 1 and type(row["schema_version"]) in (int, float) and row["schema_version"] == 3 and isinstance(text, str), "profile envelope rejected")
        require(hashlib.sha256(text.encode("utf-8")).hexdigest() == row["payload_sha256"], "retained payload checksum failed")
        payload = json.loads(text, object_pairs_hook=sb._pairs, parse_constant=lambda v: sb._fail("nonfinite payload"))
        gen = payload.get("generation")
        require(sb._integral(gen) and gen == int(match[1]) and type(payload.get("schema_version")) in (int, float) and payload["schema_version"] == 3, "generation/schema mismatch")
        require((payload.get("profile_id"), payload.get("lineage_id")) == (m["identity"]["id"], m["identity"]["lineage"]), "retained identity changed")
        if current is None or gen > current[0]:
            current = (int(gen), path, payload)
    require(set(observed) == {str(plain_path(p, existing=True)) for p in folder.iterdir() if p.name.startswith("profile_g")}, "profile roster changed")
    require(all(identity(Path(p)) == v for p, v in observed.items()), "retained generation changed during read")
    gen, path, payload = current
    world = payload.get("world", {})
    story = world.get("actions", {}).get("opening", {})
    require(world.get("region_id") == report["status"]["region"] and world.get("branch_id") == "main" and payload.get("branches", {}).get("main", {}).get("world") == world, "actual main branch differs")
    require(story.get("completed") == goals and world.get("completed_objectives") == goals and
            story.get("receipts") == report["story_receipts"], "latest disk prefix/receipts differ from real report")
    require(gen >= report["fresh_reader"]["generation"], "latest disk precedes fresh reader")
    return path, gen


def audit(index, output, m, binding=None):
    label, entry, segment, count, seconds, success, region = STEPS[index]
    spec, report = maker.source(output)
    if m["identity"] is None:
        fresh = report.get("fresh_reader", {})
        m["identity"] = {"name": m["profile"], "id": fresh.get("profile_id"), "lineage": fresh.get("lineage_id")}
    require(all(isinstance(m["identity"].get(k), str) and sb.HEX32.fullmatch(m["identity"][k]) for k in ("id", "lineage")), "fresh UUID/lineage required")
    sb._source(spec, project=project, state_root=policy.root, profile=m["identity"], goals=goals84[:count],
               success=success, region=region, target=m["target"], segment=segment or None)
    require(os.path.normcase(os.path.realpath(report.get("runtime_cwd", ""))) ==
            os.path.normcase(os.path.realpath(Path(m["target"]["exe_path"]).parent)), "EXE must run in its own folder")
    if binding:
        binding.verify_target(m["target"]["exe_path"], dev.file_sha256)
        binding.validate_output(report)
    if index:
        previous = sb._read(m["completed"][index - 1]["report"], sb.REPORT_LIMIT)
        old = previous["story_receipts"]
        require({k: v for k, v in report["story_receipts"].items() if v["objective_id"] in goals84[:STEPS[index-1][3]]} == old,
                "actual previous receipts changed")
    path, gen = profile_file(report, m, goals84[:count])
    return report, {"name": label, "report": str(output), "report_sha256": spec["report_sha256"],
                    "inputs_sha256": spec["inputs_sha256"], "receipts_sha256": spec["receipts_sha256"],
                    "disk_generation": gen, "profile_file": str(path),
                    "binding": str(binding.path) if binding else None, "binding_sha256": binding.sha256 if binding else None}


def binding_for(index, directory, m, current_profile):
    _, entry, segment, *_ = STEPS[index]
    path = directory / "source-binding.json"
    argv = ["make_qa_source_binding", "--entry", entry, "--primary-report", m["completed"][-1]["report"],
            "--profile-file", str(current_profile), "--exe", m["target"]["exe_path"], "--output", str(path)]
    if segment:
        argv += ["--segment", segment]
    if segment == "boss":
        argv += ["--base50-report", m["completed"][10]["report"]]
    old = sys.argv
    try:
        sys.argv = argv
        with contextlib.redirect_stdout(io.StringIO()):
            require(maker.main() == 0, "binding generator failed")
    finally:
        sys.argv = old
    return sb.load_binding(path, maker.digest(path, sb.BINDING_LIMIT), project=project, entry=entry, segment=segment)


def execute(command, directory, seconds):
    previous = dev.ROOT, dev.EVIDENCE
    process, failure = None, None
    try:
        dev.ROOT, dev.EVIDENCE = Path(command[0]).parent, directory
        process = dev.execute_command(command, "exported-main", seconds + 15)
    except (SystemExit, Exception) as error:
        failure = str(error)[:512] or type(error).__name__
    finally:
        dev.ROOT, dev.EVIDENCE = previous
    log = directory / "exported-main.log"
    if process is None and log.is_file():
        with log.open("rb") as stream:
            stream.seek(max(0, log.stat().st_size - 16384))
            tail = stream.read(16384).decode("utf-8", errors="replace")
        for line in reversed(tail.splitlines()):
            if line.startswith("DEV_RUN_RESULT "):
                process = json.loads(line[len("DEV_RUN_RESULT "):]); break
    marks = set()
    if log.is_file():
        patterns = (b"ObjectDB instances leaked", b"resources still in use", b"RIDs were leaked", b"RID allocations of type")
        with log.open("rb") as stream:
            carry = b""
            while block := stream.read(65536):
                for marker in patterns:
                    if marker in carry + block: marks.add(marker.decode("ascii"))
                carry = block[-128:]
    return process, failure, sorted(marks)


def main():
    global project, policy, dev, sb, maker, plain_path, goals84
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path("."))
    parser.add_argument("--exe", type=Path)
    parser.add_argument("--until", choices=[s[0] for s in STEPS], default="F4")
    parser.add_argument("--resume", type=Path, help="Only a fully validated completed boundary manifest")
    args = parser.parse_args()
    sys.path.insert(0, str(args.project / "scripts_tools/v3"))
    import dev
    import qa_source_binding as sb
    import make_qa_source_binding as maker
    from storage_policy import plain_path, atomic_json
    project, policy = plain_path(args.project, existing=True), dev.POLICY
    os.environ["LOW_ALTITUDE_DEV_HOME"] = str(policy.root)  # Pass resolved MSIX-safe owner root to every native child.
    require(project == dev.ROOT, "real project/owner mismatch")
    policy.preflight_qa(64 * 1024 ** 2)
    require(all(e in sb.CONTRACTS for _, e, *_ in STEPS[1:]), "ONE_BUILD contracts not integrated")
    goals84 = sb._goal_array((project / "scripts/v3/qa/twin_normal_f4_qa.gd").read_text(encoding="utf-8-sig"), "EXPECTED")
    require(len(goals84) == 84, "exact current84 contract required")
    for _, entry, segment, count, *_ in STEPS[1:]:
        text = (project / ("scripts/v3/qa/twin_" + entry.replace("-", "_") + "_qa.gd")).read_text(encoding="utf-8-sig")
        require(sb._goal_array(text, "EXPECTED")[:count] == goals84[:count], "observer final prefix mismatch")
    require(sb._goal_array((project / "scripts/v3/qa/twin_normal_f1_qa.gd").read_text(encoding="utf-8-sig"), "SOURCE_GOALS") == goals84[:9], "first campaign exact9 mismatch")
    manifest, m, failure_owned = None, None, False
    try:
        if args.resume:
            manifest = plain_path(args.resume, existing=True)
            require(manifest.is_relative_to(policy.path("evidence")) and manifest.name == "chain.json" and manifest.parent.name.startswith("normal-chain-"), "managed chain manifest required")
            m = sb._read(manifest, 128 * 1024)
            require(m.get("version") == 1 and m.get("owner") == policy.owner["owner"] and m.get("state") in ("boundary", "complete"), "failed/running chain cannot auto-resume")
            require(re.fullmatch(r"qa_normal_campaign_[0-9]{8}_[0-9]{6}_[0-9a-f]{8}", m.get("profile", "")), "private chain profile rejected")
            require(args.exe is None or plain_path(args.exe, existing=True) == plain_path(m["target"]["exe_path"], existing=True), "resume EXE differs")
        else:
            stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:8]
            profile = "qa_normal_campaign_" + stamp
            for r in (Path(os.environ["APPDATA"]) / "LowAltitudeTwinPulseV3", Path(os.environ["APPDATA"]) / "Godot/app_userdata/LowAltitudeTwinPulseV3"):
                require(not (r / "profiles_v3" / profile).exists(), "fresh QA profile already exists; never delete/reuse")
            current = policy._index().get("current")
            require(current, "no managed current candidate")
            exe = plain_path(args.exe or policy.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"), existing=True)
            require(current and exe == policy.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"), "current managed EXE required")
            build = sb._read(exe.parent / "BUILD.json", 16 * 1024)
            version = re.search(r'^config/version="([^"]+)"$', (project / "project.godot").read_text(encoding="utf-8-sig"), re.M)
            protocol = re.search(r'^const PROTOCOL = ([0-9]+)(?:[ \t]*#.*)?$', (project / "scripts/v3/twin_network.gd").read_text(encoding="utf-8-sig"), re.M)
            require(version and protocol and build.get("version") == version[1] and build.get("network_protocol") == int(protocol[1]), "export/source version or protocol differs")
            small = {str(p): small_hash(p) for p in tracked_files()}
            small[str(exe.parent / "BUILD.json")] = small_hash(exe.parent / "BUILD.json")
            target = {"exe_path": str(exe), "exe_sha256": dev.file_sha256(exe), "app_version": build["version"], "protocol": build["network_protocol"]}
            m = {"version": 1, "owner": policy.owner["owner"], "candidate": current, "profile": profile, "identity": None,
                 "target": target, "exe_identity": identity(exe), "small_inputs": small, "state": "boundary", "completed": []}
            policy.preflight("evidence", 65536)
            folder = policy.path("evidence", "normal-chain-" + stamp)
            folder.mkdir(exist_ok=False)
            manifest = folder / "chain.json"
        pinned_inputs(m)
        if not args.resume: atomic_json(manifest, m)
        current_profile = None
        require(len(m["completed"]) <= len(STEPS), "chain exceeds fixed16 steps")
        if args.resume:
            require(m["completed"] and m["identity"]["name"] == m["profile"], "resume requires a completed private boundary")
            require((m["state"] == "complete") == (len(m["completed"]) == 16), "terminal boundary state mismatch")
        for index, row in enumerate(m["completed"]):
            require(row["name"] == STEPS[index][0] and plain_path(row["report"], existing=True).parent == manifest.parent / (f"{index+1:02d}-" + STEPS[index][0]), "non-prefix/foreign evidence boundary")
            require(maker.digest(Path(row["report"]), sb.REPORT_LIMIT) == row["report_sha256"] and
                    maker.digest(Path(row["report"]).parent / "inputs.json", sb.INPUTS_LIMIT) == row["inputs_sha256"], "stored evidence changed")
            binding = sb.load_binding(row["binding"], row["binding_sha256"], project=project, entry=STEPS[index][1], segment=STEPS[index][2]) if index else None
            # Revalidate historical reports, but only inspect CURRENT generations for the last one.
            spec, report = maker.source(Path(row["report"]))
            require(spec["receipts_sha256"] == row["receipts_sha256"], "boundary receipt digest differs")
            sb._source(spec, project=project, state_root=policy.root, profile=m["identity"], goals=goals84[:STEPS[index][3]], success=STEPS[index][5], region=STEPS[index][6], target=m["target"], segment=STEPS[index][2] or None)
            if binding: binding.validate_output(report)
            if index == len(m["completed"]) - 1: current_profile, _ = profile_file(report, m, goals84[:STEPS[index][3]])
        until = [s[0] for s in STEPS].index(args.until)
        for index in range(len(m["completed"]), until + 1):
            label, entry, segment, count, seconds, *_ = STEPS[index]
            before = pinned_inputs(m)
            policy.preflight("evidence", dev.LOG_LIMIT + sb.REPORT_LIMIT + sb.INPUTS_LIMIT + 65536)
            directory = manifest.parent / (f"{index+1:02d}-" + label)
            failure_owned = True
            directory.mkdir(exist_ok=False)
            output = directory / (entry + ("-" + segment if segment else "") + "-" + m["profile"][19:] + ".json")
            binding = binding_for(index, directory, m, current_profile) if index else None
            if binding: binding.verify_target(m["target"]["exe_path"], dev.file_sha256)
            command = [m["target"]["exe_path"], "--", "--qa-" + entry, "--qa-profile=" + m["profile"],
                       "--qa-normal-output=" + str(output), "--qa-normal-seconds=" + str(seconds)]
            if segment: command.append("--qa-i3-segment=" + segment)
            if binding: command += binding.cli_args()
            m.update(state="running", active=label)
            atomic_json(manifest, m)
            atomic_json(directory / "invocation.json", {"command": command, "cwd": str(Path(command[0]).parent), "timeout_seconds": seconds + 15})
            print(json.dumps({"stage_started": label, "manifest": str(manifest)}, ensure_ascii=False), flush=True)
            process, failure, leaks = execute(command, directory, seconds)
            try: after = pinned_inputs(m)
            except Exception as error: after, failure = {}, str(error)[:512]
            atomic_json(directory / "inputs.json", {**(binding.metadata if binding else {}), "before": before, "after": after,
                        "unchanged": before == after, "process": process, "execution_failure": failure,
                        "artifact_sha256": m["target"]["exe_sha256"], "native_exit_leak_lines": leaks})
            require(failure is None and before == after and process and process.get("passed") is True, "process/inputs failed; keep profile and stop")
            report, row = audit(index, output, m, binding)
            current_profile = Path(row["profile_file"])
            m["completed"].append(row)
            m.update(state="complete" if index == 15 else "boundary", active=None)
            atomic_json(manifest, m)
            print(json.dumps({"stage_complete": label, "goals": count, "manifest": str(manifest)}, ensure_ascii=False), flush=True)
        print(json.dumps({"complete84": len(m["completed"]) == 16, "boundary": m["completed"][-1]["name"] if m["completed"] else None, "manifest": str(manifest)}, ensure_ascii=False))
        return 0
    except (Exception, KeyboardInterrupt) as error:
        if failure_owned and m is not None and manifest and manifest.exists():
            m.update(state="failed", error=(type(error).__name__ + ": " + str(error))[:1024])
            atomic_json(manifest, m)
        print(json.dumps({"complete84": False, "error": str(error)[:1024], "manifest": str(manifest) if manifest else None}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

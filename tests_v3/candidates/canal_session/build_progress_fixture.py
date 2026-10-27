"""Pin an actual recorded ten-receipt scan; no synthesized gameplay state."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "evidence/20261020_210846_c423f4/result.json"
data = json.loads(SOURCE.read_text(encoding="utf-8"))
row = data["snapshots"]["original_scan"]
assert row["executor"]["receipt_count"] == 10
assert row["rules"]["jobs_completed"] == row["rules"]["service_credit"] == 0
target = HERE / "progress_fixture"
target.mkdir(exist_ok=True)
payload = (json.dumps(row, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
(target / "actual_scan_exchange.json").write_bytes(payload)
(target / "source.json").write_text(json.dumps({
    "source": str(SOURCE.relative_to(HERE)),
    "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "fixture_sha256": hashlib.sha256(payload).hexdigest(),
    "record": "snapshots.original_scan",
    "scope": "Actual original transport 10 receipts and partial scan. Source run 95 checks/1 failed bad-sample test: cold holder was set to the already existing same WORK value. Root fixed the negative test; this recorded real snapshot itself validated and restored. No synthetic completed work or service."}, ensure_ascii=False, indent=2), encoding="utf-8")
print(hashlib.sha256(payload).hexdigest())

departure_source = HERE / "evidence/departure_20261020_220204_b80a06/result.json"
departure = json.loads(departure_source.read_text(encoding="utf-8"))["snapshots"]["latest_roundtrip"]["saved"]
assert departure["workbench"]["version"] == 3
assert departure["rules"]["jobs_completed"] == 1
assert departure["rules"]["services_consumed"] == 0
assert departure["executor"]["fields"]["_action"]["kind"] == "pick"
departure_payload = (json.dumps(departure, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
(target / "actual_afterwork_route3.json").write_bytes(departure_payload)
(target / "afterwork_source.json").write_text(json.dumps({
    "source": str(departure_source.relative_to(HERE)),
    "source_sha256": hashlib.sha256(departure_source.read_bytes()).hexdigest(),
    "fixture_sha256": hashlib.sha256(departure_payload).hexdigest(),
    "record": "snapshots.latest_roundtrip.saved",
    "scope": "Actual commit, one work receipt, lift and all three departure routes already captured/Store/restored. Source run 179 checks/1 failed: real same-anchor carrier pickup could not descend from high work hold. This fixture retains the real blocked pending pickup and original momentum; no Safe terminal/claim is synthesized."}, ensure_ascii=False, indent=2), encoding="utf-8")
print(hashlib.sha256(departure_payload).hexdigest())

local_source = HERE / "evidence/20261020_210529_48e920/result.json"
local = json.loads(local_source.read_text(encoding="utf-8"))["snapshots"]["original_scan"]
assert local["executor"]["receipt_count"] == 0
assert local["rules"]["pending_action"]["serial"] == 1
assert local["rules"]["pending_action"]["cassette_id"] == "I2:canal_cassette_1"
assert local["rules"]["thermal_ledger"]["ability_removed"] == 25000000
local_payload = (json.dumps(local, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
(target / "actual_scan_local_cooling.json").write_bytes(local_payload)
(target / "local_cooling_source.json").write_text(json.dumps({
    "source": str(local_source.relative_to(HERE)),
    "source_sha256": hashlib.sha256(local_source.read_bytes()).hexdigest(),
    "fixture_sha256": hashlib.sha256(local_payload).hexdigest(),
    "record": "snapshots.original_scan",
    "scope": "Actual original Rules/LOS ability removed 25kJ from initial WORK cassette1, then original stationary first work #1 partial scan. Zero transport receipts; initial cassette0 remains on real PinJoint. Source96 checks/0 failures. No route exchange, completed work, claim, Story fact or reward synthesized."}, ensure_ascii=False, indent=2), encoding="utf-8")
print(hashlib.sha256(local_payload).hexdigest())

pickup_source = HERE / "evidence/service_20261020_225113_320296/result.json"
pickup = json.loads(pickup_source.read_text(encoding="utf-8"))["snapshots"]["latest_roundtrip"]["saved"]
assert pickup["executor"]["fields"]["_phase"] == "commit"
assert pickup["executor"]["fields"]["_action"]["kind"] == "pick"
assert pickup["executor"]["pickup_supported_history"] is True
assert pickup["custody"]["cargos"]["I2:canal_cassette_0"]["phase"] == "carried"
assert pickup["rules"]["cassettes"]["I2:canal_cassette_0"]["holder"] == "north_work"
pickup_payload = (json.dumps(pickup, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
(target / "actual_commit_pick.json").write_bytes(pickup_payload)
(target / "commit_pick_source.json").write_text(json.dumps({
    "source": str(pickup_source.relative_to(HERE)),
    "source_sha256": hashlib.sha256(pickup_source.read_bytes()).hexdigest(),
    "fixture_sha256": hashlib.sha256(pickup_payload).hexdigest(),
    "record": "snapshots.latest_roundtrip.saved",
    "scope": "Actual original same-anchor descent and alignment created the real PinJoint at original WORK support, before pick receipt. Source76 checks/1 failure: frozen generic clearance incorrectly treated legal pickup-source contact as an arbitrary obstacle. This is the unchanged actual original Store generation; no lift, Safe, claim, route receipt or reward manufactured."}, ensure_ascii=False, indent=2), encoding="utf-8")
print(hashlib.sha256(pickup_payload).hexdigest())

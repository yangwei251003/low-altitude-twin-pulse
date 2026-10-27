"""Add explicit discovery predicates to the editable world content source."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "docs/v2/data/world_content.json"
data = json.loads(path.read_text(encoding="utf-8"))
rules = {
    "R1-P04": (["interact"], "", False),
    "R1-P08": (["clearance_base"], "M05", False),
    "R1-P12": (["scan_base", "hook_base"], "", False),
    "R1-P16": (["interact"] * 3, "", False),
    "R1-P20": (["scan_base"] * 3, "", False),
    "R1-P24": (["searchlight_base"], "M06", True),
    "R2-P04": (["scan_base"] * 3, "", False),
    "R2-P08": (["scan_base"], "", False),
    "R2-P12": (["interact"] * 3, "", False),
    "R2-P16": (["scan_base"], "", False),
    "R2-P20": (["interact"], "M07", False),
    "R2-P24": (["hook_base"], "", False),
    "R3-P04": (["scan_base", "searchlight_base"], "", False),
    "R3-P08": (["scan_base"], "", False),
    "R3-P12": (["scan_base"] * 3, "", False),
    "R3-P16": (["scan_base"], "", False),
    "R3-P20": (["interact"], "M11", False),
    "R3-P24": (["scan_base"] * 2, "", False),
    "R4-P04": (["scan_base"] * 3, "", False),
    "R4-P08": (["scan_base"] * 2, "", False),
    "R4-P12": (["clearance_base"], "", False),
    "R4-P16": (["scan_base"], "M14", False),
    "R4-P20": (["scan_base", "hook_base"], "", False),
    "R4-P24": (["interact"], "M16", False),
}
for region in data["regions"]:
    for poi in region["pois"]:
        if not poi["hidden"]:
            continue
        tools, mission, night = rules[poi["id"]]
        poi["discovery_steps"] = [
            {"tool_id": tool, "duration_s": 2.0,
             "offset_xz_m": ([0, -4] if len(tools) == 1 else [[-4, 0], [0, -4], [4, 0]][i]),
             "radius_m": 2.5, "max_speed_mps": 1.0}
            for i, tool in enumerate(tools)
        ]
        poi["discovery_requires_mission"] = mission
        poi["discovery_night_only"] = night
        if poi["id"] == "R3-P08":
            poi["discovery_steps"][0]["bearing_deg"] = 90
            poi["discovery_steps"][0]["offset_xz_m"] = [4, 0]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Added 24 explicit secret discovery sequences")

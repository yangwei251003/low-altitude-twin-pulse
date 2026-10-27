"""Author compact greybox layouts/NPC graphs; no engine or asset processing."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data/v3/campaign"


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def graph(region, points):
    # A circuit plus a direct shelter chord allows an actual alternate path.
    return {"id": region, "nodes": [
        {"id": "supply", "position": points[0], "neighbors": ["hub", "shelter"]},
        {"id": "hub", "position": points[1], "neighbors": ["supply", "service", "upper"]},
        {"id": "service", "position": points[2], "neighbors": ["hub", "shelter"]},
        {"id": "upper", "position": points[3], "neighbors": ["hub", "shelter"]},
        {"id": "shelter", "position": points[4], "neighbors": ["supply", "service", "upper"]},
    ]}


def actor(region, suffix, name, role, purpose, jobs, loss="reserve", channel="maintenance_powered"):
    return {"id": region + ":" + suffix, "name": name, "region": region, "role": role,
            "purpose": purpose, "start_node": "supply", "shelter_node": "shelter", "speed": 2.5,
            "power_policy": {"channel": channel, "loss": loss, "reserve_seconds": 45 if loss == "reserve" else 0, "supply_node": "supply"},
            "shelter_weather": ["storm"], "jobs": [{"node": node, "kind": kind, "target_id": target, "work_seconds": work} for node, kind, target, work in jobs]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    regions = []
    descriptions = {
        "F2": ("镜湖悬庭", "湖檐读原件→西庭询问→上层转镜→北庭辨真身", "低湖檐、洞檐、上层镜台、北部巡守庭", "低檐运镜、上庭档案、灯机补光", ["找回被风吹歪的路镜", "护送灯机绕过巡守", "让瀑布洞檐的接收石重亮"], ["洞檐背光刻字", "上庭镜背校时", "西湖旧航标", "停机后展开的翼内图"]),
        "I3": ("热崖制造带", "换班台→中层账目→东换热台→高泊位→北轨道", "崖脚、厂房检修层、冷却高台、炉轨战区", "轮班休息、冷却维修、重载检修", ["恢复换班灯号", "给停工货梯接应急旁路", "清理工人休息台的热脉冲"], ["旧班组的维修刻记", "烟囱背后的低温航洞", "高台备用刹车靴", "炉车底盘原始铭牌"]),
        "F3": ("鸣菌幽谷", "样本低层→养护棚→双点隔离→育苗台→北声场", "根拱低谷、菌膜台、地下光网、静声台", "养分配送、授粉照料、信号隔离", ["接回西棚授粉环", "护送养分机穿过回声带", "听完三处不会同步的旧歌"], ["根拱里的空响孔", "菌膜背面的旧路", "地下光网的异色结", "静声后出现的幼菌群"]),
        "I4": ("离岸共振阵列", "值守台→协议匣→东见证器→低避风路→北阵列", "海面平台、挡风廊、转镜天线层、北防御台", "风暴值守、证据见证、平台维修", ["送回风窗观测器", "恢复值守台求援频闪", "护送巡检机绕过强风侧"], ["旧协议签署板", "挡风廊的手动限流杆", "未上报的维修短讯", "停机阵列内侧的海图"]),
        "F4": ("天脉冠峰", "接续台→工业接口→根冠接口→高负载台→北中枢", "裂谷边、根冠台、双界接口层、失落中枢", "两界会合、支脉照料、负载观测", ["接回伙伴的旧联络信标", "恢复峰南的幼根看护点", "让两界维护机走通同一条路线"], ["看护者的旧誓词", "裂谷侧翼的返航捷径", "中枢前的双界刻度", "结局后共同照料的留念台"]),
    }
    for rid, (name, path, levels, uses, sides, secrets) in descriptions.items():
        pack = json.loads((OUT / (rid.lower() + "_actions.json")).read_text(encoding="utf-8"))
        solids = [{"id": "Ground", "position": [0, -.5, 0], "size": [80, 1, 80], "tone": "ground", "purpose": "连续灰盒地表；非可游泳水面"}]
        # Marker pads end 0.8 m below the real interaction point. Pillars are
        # inside their pad footprint, keeping the side flight lanes open.
        for i, m in enumerate(pack["markers"]):
            if m["id"].endswith(("boss_briefing", "boss_record", "choice_terminal")):
                continue
            x, y, z = m["position"]
            top = y - .8
            solids.append({"id": f"Pad{i}", "position": [x, top - .4, z], "size": [6, .8, 6], "tone": "platform", "purpose": m["label"] + "的实际支撑台"})
            if top > 1.0:
                solids.append({"id": f"Support{i}", "position": [x, (top - .8) / 2, z], "size": [1, top - .8, 1], "tone": "edge", "purpose": "平台支撑，禁止在此虚构通道"})
        arena_y = {"F2": 8, "I3": 4, "F3": 6, "I4": 8, "F4": 10}[rid]
        solids.extend([
            {"id": "NorthArena", "position": [0, arena_y - 1.4, -26], "size": [32, 1.2, 24], "tone": "platform", "purpose": "Boss实体战区；入口在南缘，周边可飞行绕行"},
            {"id": "CoverWest", "position": [-12, arena_y + 1, -27], "size": [3, 4, 5], "tone": "cover", "purpose": "真实射线遮挡掩体，顶部可越过"},
            {"id": "CoverEast", "position": [12, arena_y + 2, -24], "size": [3, 6, 5], "tone": "cover", "purpose": "真实射线遮挡掩体，不挡中央通道"},
            {"id": "SouthLanding", "position": [-24, 1, 31], "size": [12, 2, 10], "tone": "platform", "purpose": "出生/返回安全落台"},
            {"id": "WestServiceDeck", "position": [-32, 2, 2], "size": [5, 1, 42], "tone": "edge", "purpose": "西侧低层旁路，前后留有垂直空域"},
            {"id": "EastLookout", "position": [32, 14, 10], "size": [6, 1, 12], "tone": "edge", "purpose": "东侧高层备用观察台"},
        ])
        # Native full-growth overlap evidence 20261020_234450: keep Pad3's
        # real corner clear of the complete nutrient bridge, with its column.
        if rid == "F3":
            for solid in solids:
                if solid["id"] in ("Pad3", "Support3"):
                    solid["position"][2] = -4
        fantasy = rid.startswith("F")
        regions.append({"id": rid, "name": name, "status": "greybox_layout_candidate",
            "spawn": [-24, 5, 31], "bounds": [-40, -1, -40, 40, 27, 40],
            "layers": levels, "use_areas": uses, "main_path_description": path,
            "main_route": [[-24, 6, 31], [-20, 10, 20], [-12, 10, 8], [18, 17, 5], [0, arena_y + 5, -16], [0, arena_y + 5, -28]],
            "bypass_route": [[-24, 6, 31], [-32, 7, 20], [-32, 7, -10], [-22, arena_y + 6, -26]],
            "high_route": [[-24, 6, 31], [32, 20, 22], [32, 20, -10], [20, 20, -26]],
            "minimum_flight_lane_width_m": 5, "minimum_vertical_opening_m": 4,
            "boss_arena": {"centre": [0, arena_y + 4, -28], "half_extents": [16, 9, 11], "entry_z": -21, "briefing_safe_z": -18, "retry_position": [0, arena_y + 4, -16], "actor_ground_y": arena_y - .8},
            "enemy_spawns": [{"id": rid + ":patrol_01", "position": [-4, 8, 8], "behavior": "short_patrol_then_warn", "route": [[-4, 8, 8], [6, 8, 4]], "purpose": "可绕行的单敌遭遇"}, {"id": rid + ":sentry_01", "position": [24, 12, -7], "behavior": "guard_cone_then_recover", "route": [[24, 12, -7], [26, 12, 2]], "purpose": "侧路上的观察与战斗"}],
            "palette": {"ground": "283e36" if fantasy else "35424a", "platform": "62775e" if fantasy else "6f8287", "edge": "8b825c" if fantasy else "54636b", "cover": "495e46" if fantasy else "7b7568"},
            "solids": solids,
            "optional_events": [{"id": rid + ":side:" + str(i+1), "title": title, "status": "authored_not_bound", "completion": "真实环境/战斗/NPC回执；不得接近即完成"} for i, title in enumerate(sides)],
            "secrets": [{"id": rid + ":secret:" + str(i+1), "title": title, "status": "authored_not_bound", "position": [[-35, 5, 14], [33, 16, 10], [-22, 12, -8], [15, arena_y+5, -35]][i], "completion": "近距显式检查且视线无遮挡；一次发现收据"} for i, title in enumerate(secrets)],
        })
    write("layouts.json", {"schema_version": 1, "status": "greybox_layouts_not_camera_or_collision_verified", "regions": regions})
    route_points = {
        "I2": [[-20, 7, 18], [-6, 9, 18], [16, 8, 13], [-2, 12, 5], [-20, 10, 22]],
        "F2": [[-25, 12, 24], [-8, 15, 17], [23, 14, 15], [12, 18, 0], [-28, 15, 26]],
        "I3": [[-25, 9, 24], [-6, 12, 17], [23, 12, 12], [12, 18, 0], [-28, 12, 26]],
        "F3": [[-25, 12, 24], [-8, 15, 17], [23, 14, 15], [12, 18, 0], [-28, 15, 26]],
        "I4": [[-25, 12, 24], [-8, 15, 17], [23, 16, 15], [12, 20, 0], [-28, 15, 26]],
        "F4": [[-25, 14, 24], [-8, 17, 17], [23, 18, 15], [12, 22, 0], [-28, 17, 26]],
    }
    actors = [
        actor("I2", "service_01", "南湾检修运送机", "service_transport", "在南湾服务恢复后运送检修用品，断供时回供应点，不介入病房水量。", [("supply", "pickup", "I2:service_supply", 3), ("service", "deliver", "I2:service_receiver", 4)], "return_supply", "supply_powered"),
        actor("F2", "lamp_01", "镜庭送灯机", "light_care", "维持低檐与上庭的路灯，风暴时绕回西庭避风。", [("service", "repair", "F2:path_lamp", 5), ("upper", "inspect", "F2:clock_stone", 3)], "ignore", "powered"),
        actor("I3", "coolant_01", "热崖冷却巡检机", "cooling_inspection", "巡查工人冷却与高台泊位；断供先用备用电完成一段再等待。", [("service", "repair", "I3:worker_cooling", 5), ("upper", "inspect", "I3:loaded_dock", 3)]),
        actor("F3", "nutrient_01", "菌谷养分运送机", "nutrient_transport", "取养分后向育苗台送达；只在保持养分线时工作。此真实到货可成为任务证据。", [("supply", "pickup", "F3:nutrient_supply", 3), ("service", "deliver", "F3:nutrient_receiver", 4)], "return_supply", "supply_powered"),
        actor("F3", "pollinator_01", "菌谷授粉飞虫", "pollination", "往返两处保留的花簇，危险时回棚，不自动消耗剧情角色。", [("service", "pollinate", "F3:east_bloom", 4), ("upper", "pollinate", "F3:upper_bloom", 4)], "ignore", "powered"),
        actor("I4", "watch_01", "阵列值守巡检机", "array_inspection", "巡查见证接收器和避风路，警示风暴的实际旁路。", [("service", "inspect", "I4:witness_receiver", 3), ("upper", "repair", "I4:shelter_lamp", 5)]),
        actor("F4", "care_01", "共脉接续看护机", "vein_care", "在两界接口间照料支脉，把故事修复转成可持续的地区服务。", [("service", "inspect", "F4:living_socket", 4), ("upper", "repair", "F4:shared_test", 5)]),
    ]
    write("npc_routes.json", {"schema_version": 1, "status": "authored_route_corridors_not_physics_verified", "regions": [graph(r, p) for r, p in route_points.items()], "actors": actors})
    print(f"Authored {len(regions)} compact layouts and {len(actors)} ecology actors; no engine verification.")


if __name__ == "__main__":
    main()

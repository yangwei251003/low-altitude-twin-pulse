"""Editable campaign authoring source. Only writes data/v3/campaign owned files.

Run from any directory using Python 3.12. Does not launch Godot or touch saves.
The JSON files are authored content candidates; scene integration is separate.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data/v3/campaign"
BASE = "opening_v1"


def flag(key):
    return {"type": "flag", "key": key, "value": True}


def say(who, *lines):
    return {"type": "dialogue", "character_id": who, "lines": list(lines)}


def memory(who, key):
    return {"type": "character_memory", "character_id": who, "memory": key}


def discover(key, title):
    return {"type": "discovery", "discovery_id": key, "title": title}


def objective(aid, key, text, hint, target, kind="fact", options=None, effects=None):
    return {"id": aid + ":" + key, "text": text, "hint": hint, "after": [],
            "events": [{"type": kind, "target_id": target, "options": options or [""]}],
            "effects": effects or []}


def action(aid, title, region, previous, objectives, completion, effects=None):
    for i, item in enumerate(objectives):
        item["after"] = [objectives[i - 1]["id"]] if i else []
    return {"id": aid, "title": title, "region_id": region, "prerequisites": [previous],
            "target_minutes": [5, 8], "completion_text": completion,
            "objectives": objectives, "effects": effects or []}


def marker(mid, region, point, label, kind="inspect", radius=3):
    return {"id": mid, "region": region, "position": point, "kind": kind,
            "label": label, "radius": radius}


def person(pid, name, role, region, greeting):
    return {"id": pid, "name": name, "role": role, "region_id": region,
            "greeting_lines": [greeting], "replies": []}


def binding(source, option, anchor, checks, **kw):
    return {"source": source, "options": option, "navigation_marker_id": anchor,
            "required_validation": checks, "requires_authority": True,
            "retain_before_objective": True, "commit_before_publish": True, **kw}


def extension(region, chars, markers, actions, bindings):
    return {"schema_version": 1, "content_id": "campaign_" + region.lower() + "_extension_v1",
            "extends_content_id": BASE, "status": "authored_candidate_not_scene_integrated",
            "scope_note": "行动数据与真实状态绑定契约。目标数量、5–8分钟均为制作预算；本文件不证明地区可玩、实体机制、趣味或体验时长。坐标需Root以默认镜头及真实碰撞核对。",
            "characters": chars, "markers": markers, "actions": actions,
            "character_reply_extensions": [], "host_bindings": bindings}


def boss_action(region, boss, previous, who, title, lesson, ending, choice=None):
    aid = region + ":" + boss
    objs = [
        objective(aid, "plan", "核对战区退路，确认停机方案", lesson, region + ":boss_briefing", "inspect", ["plan"],
                  [say(who, lesson)]),
        objective(aid, "engage", "进入战区，观察一次完整预警与恢复窗口", "离开安全台才会交战；先看形状、高度和可用掩体。倒地可救援，全灭可整场重试，不扣已有资产。", region + ":boss_observed", options=["observed"],
                  effects=[flag(region + ":boss_pattern_observed")]),
        objective(aid, "stop", "处理关键部件，停下失控核心", "按本区机制创造窗口；射击、能力和环境操作可组合。半血后重新观察节奏；结算保存成功才算停机。", region + ":boss_defeated", options=["committed"],
                  effects=[flag(region + ":boss_stopped"), say(who, "失控核心已停下，先保留它的运行记录。停机不能替我们决定接下来把支脉交给谁。")]),
    ]
    if choice:
        objs.append(objective(aid, "decision", choice["text"], choice["hint"], region + ":chapter_choice", options=choice["options"],
                              effects=[flag(region + ":chapter_decision_saved"), memory(who, region + ":informed_choice"), discover(region + ":operation_record", ending)]))
    else:
        objs.append(objective(aid, "record", "近距读取停机记录，核对下一段真实去向", "靠近核心侧记录台按 G；需看见目标。只有停机保存后才能读取；无需返回起点领奖。", region + ":boss_record", "inspect", ["record"],
                              [discover(region + ":operation_record", ending), memory(who, region + ":record_shared"), say(who, ending)]))
    return action(aid, title, region, previous, objs,
                  "行动完成 · " + ending, [flag(region + ":region_route_open")])


def create():
    OUT.mkdir(parents=True, exist_ok=True)
    packs = {}
    # I2 keeps the real canal executor, workbench, custody and original Store.
    a = "I2:canal_service"
    i2_prepare = action(a, "把服务真正送到南湾", "I2", "I2:distribution_audit", [
        objective(a, "brief", "在南湾联络台核对需要运送的检修匣", "病房供水和桥位已经保存，不必重做。读取南湾工位请求，分清运输、测量与维修各自的完成条件。", "I2:canal_briefing", "inspect", ["brief"],
                  [say("npc:linlan", "南湾不是再开一次水阀。热匣要退回，冷匣要落稳到工位，扫描标定后才可维修。病房支路保持原样。")]),
        objective(a, "exchange", "沿可通航路线换匣，让工位实际收到冷匣", "从泊位取冷匣、退回热匣并正确落架；高路和低路均可。载货时提早制动，让开岸柱，不用撞开设备。", "I2:canal_exchange_verified", options=["high_route", "low_route", "mixed_route"],
                  effects=[memory("npc:ruanheng", "I2:real_cassette_exchange"), say("npc:ruanheng", "两只匣的归属和落架都对上了。位置相近还不够，工位确认收到冷匣以后才能测量。")]),
        objective(a, "service", "在工位完成有效扫描、标定与维修", "依工位提示完成真实测量。扫描中可暂停和保存，恢复后继续余下扫描；重复读档不重复获得维修功劳。", "I2:canal_service_verified", options=["repaired"],
                  effects=[flag("I2:canal_service_ready"), discover("I2:canal_calibration", "南湾实际扫描与唯一维修工序信用"), say("npc:linlan", "维修服务到位了。运水和巡检有了稳定工位，南湾不用再挤占病房的检修时间。")]),
        objective(a, "order", "读取工位收到的双泵优先级指令", "完成服务后近距读取调度记录。把机器实际收到的指令和现场去向并列记录，先不指认发送者。", "I2:canal_dispatch", "inspect", ["record"],
                  [discover("I2:pump_priority_order", "双泵接受了重复的最高优先级指令"), say("npc:ruanheng", "两座泵都被写成最高优先级，互锁才会反复抢占。停下守卫，我们可以改调度，保住两条服务线。")]),
    ], "行动完成 · 南湾服务与双泵指令记录已保存。前往北部双泵检修台。")
    choice1 = {"text": "确认病房优先或均衡轮换的水城调度", "hint": "先阅读两方案：病房优先保留应急储水，南湾补给较慢；均衡轮换同时补给，病房回储较慢。两者均保底供水、保留绕路；不是牺牲居民。单人确认，合作双方同意，确认前建立独立分支。", "options": ["clinic_reserve", "balanced_service"]}
    packs["I2"] = extension("I2", [], [
        marker("I2:canal_briefing", "I2", [-18, 3, 18], "林岚 · 南湾服务联络"),
        marker("I2:canal_dispatch", "I2", [13, 3, 6], "南湾工位 · 双泵指令记录"),
        marker("I2:boss_briefing", "I2", [0, 5, -19], "双泵检修台"),
        marker("I2:choice_terminal", "I2", [0, 5, -19], "水城调度 · 知情确认"),
    ], [i2_prepare, boss_action("I2", "twin_pump_guardian", a, "npc:ruanheng", "让双泵学会轮换", "守卫的低泵和高泵交替开罩。低水位先处理低泵，高水位先处理高泵；控制水位或借旁路接近都可。水城民用泵与战区隔离。", "水城调度由现场双方确认，镜湖航路开放。", choice1)], {
        "I2:canal_exchange_verified": binding("original_canal_executor_completed_custody_exchange", ["high_route", "low_route", "mixed_route"], "I2:canal_dispatch", ["both_cassettes_actual_custody_and_rest_confirmed", "original_executor_receipts_match_serial_job_and_route", "not_only_distance_or_animation"], state_path="world.environment.I2_canal"),
        "I2:canal_service_verified": binding("original_canal_service_credit", ["repaired"], "I2:canal_dispatch", ["actual_completed_scan_and_calibration", "original_jobs_completed_and_unique_service_credit", "same_store_transaction_with_workbench"], state_path="world.environment.I2_canal"),
        "I2:chapter_choice": binding("host_consensus_after_boss_and_read_costs", choice1["options"], "I2:choice_terminal", ["boss_victory_committed", "both_cost_panels_inspected", "branch_created_before_commit", "party_consensus_if_two_players", "clinic_base_supply_unchanged"], consumes_major_choice_budget=1),
    })
    # F2 tests contradictory records, shadows, and proof before attribution.
    p = "npc:shuyao"
    a = "F2:mirror_evidence"
    f2_prepare = action(a, "镜面记录没有说完的话", "F2", "I2:twin_pump_guardian", [
        objective(a, "records", "从不同高度读取两份相反的镜面记录", "一份在低湖檐，一份在上层悬庭；分别靠近按 G。倒影只提示路径，不能替代读取真实记录。", "F2:paired_records", options=["both_read"],
                  effects=[discover("F2:contradictory_records", "停电与枯根的两份记录缺少同一段校时"), say(p, "两份记录都是真的，却没有记同一段时间。别急着拿其中一份指认另一边。")]),
        objective(a, "archive", "向疏谣核对缺失的校时与镜翼巡守", "档案守护者在西侧悬庭；靠近交谈。她能说明记录的来源，也会提醒你镜翼守卫的真身有固定投影。", p, "talk", ["clock_gap"],
                  [memory(p, "F2:evidence_before_blame"), say(p, "抽取开始前，校时曾被同一个中继延迟。巡守因此把两边都当成入侵者。把光路接回刻度石，缺失的时间会显出来。")]),
        objective(a, "light", "移动导光镜，让真实光路照亮校时刻度石", "可推拉转镜，或接管镜座调向；光束必须实际到达接收面且无遮挡。飞到倒影中、对接收石直接发光都不能替代这条路径。", "F2:clock_light_path", options=["manual_mirror", "takeover_mirror"],
                  effects=[flag("F2:clock_path_restored"), discover("F2:aligned_timeline", "两界失流与上游配额覆盖处于同一条时间线")]),
        objective(a, "decision", "决定立即公开原始证据，或附校时说明共同发布", "立即公开：两界居民马上看到原件，疏谣须处理未校时的争议；共同发布：阮衡与疏谣先补说明，延后本区公告。原件始终保留，不销毁、不封锁后续调查。联机双方确认，提交前建立分支。", "F2:chapter_choice", options=["publish_raw", "publish_context"],
                  effects=[flag("F2:chapter_decision_saved"), memory(p, "F2:publication_consent"), say(p, "原件会留下。我们记住怎样公开，也记住谁需要把遗漏的解释补上。现在去让巡守停下来，别让它继续攻击过路人。")]),
    ], "行动完成 · 校时与公开方案已留存。北庭可辨认真身的影子，前往停下镜翼巡守。")
    packs["F2"] = extension("F2", [person(p, "疏谣", "镜湖档案守护者", "F2", "湖上的倒影会换方向，记过的事不会自己变。先拿出原件，我们再说是谁伤了谁。")], [
        marker(p, "F2", [-22, 8, 20], "疏谣 · 镜湖档案庭", "npc"),
        marker("F2:record_low", "F2", [-12, 3, 10], "湖檐 · 原始记录"),
        marker("F2:record_high", "F2", [16, 13, -4], "悬庭 · 原始记录"),
        marker("F2:clock_stone", "F2", [21, 8, 15], "校时刻度石"),
        marker("F2:choice_terminal", "F2", [-22, 8, 18], "原件与校时 · 公开确认"),
        marker("F2:boss_briefing", "F2", [0, 10, -19], "镜翼战区 · 安全檐"),
        marker("F2:boss_record", "F2", [0, 10, -24], "巡守核心 · 中继记录"),
    ], [f2_prepare, boss_action("F2", "mirrorwing_warden", a, p, "只有真身会遮住光", "巡守会留下两个镜像。先看地面投影与光束遮挡，真身才会投出连续影子；用光照显形，或绕到背光侧射击。不要朝闪亮的镜像浪费火力。", "巡守记录把重复配额指向热崖冷却中继；疏谣愿随无线电继续核对。")], {
        "F2:paired_records": binding("two_host_manual_inspection_receipts", ["both_read"], "F2:record_low", ["both_markers_explicitly_read", "actual_range_and_los_each", "same_branch"], required_markers=["F2:record_low", "F2:record_high"]),
        "F2:clock_light_path": binding("actual_two_segment_reflection_and_receiver_hit", ["manual_mirror", "takeover_mirror"], "F2:clock_stone", ["mirror_actual_pose", "source_mirror_receiver_segments_unoccluded", "receiver_front_face_hit"], reject_as_proof=["direct_ability_target", "player_position_in_reflection"]),
        "F2:chapter_choice": binding("host_consensus_after_evidence_cost_panels", ["publish_raw", "publish_context"], "F2:choice_terminal", ["aligned_timeline_committed", "both_cost_panels_inspected", "branch_created_before_commit", "party_consensus_if_two_players"], consumes_major_choice_budget=1),
    })
    # I3 reuses heat, load and braking, but never requires burning a resident route.
    p = "npc:qiaoshu"
    a = "I3:cooling_route"
    packs["I3"] = extension("I3", [person(p, "乔述", "热崖轮班维修员", "I3", "停炉不难，难的是让这一班人的工作和下面的住区都能继续。先看隔离回路。")], [
        marker(p, "I3", [-22, 4, 20], "乔述 · 换班检修台", "npc"),
        marker("I3:cooling_ledger", "I3", [-15, 5, 8], "冷却配额记录"),
        marker("I3:cooling_test", "I3", [16, 8, 8], "隔离换热台"),
        marker("I3:brake_dock", "I3", [17, 12, -3], "热匣安全泊位", "reach"),
        marker("I3:boss_briefing", "I3", [0, 6, -18], "熔炉轨道 · 避让台"),
        marker("I3:boss_record", "I3", [0, 6, -25], "熔炉控制匣"),
    ], [action(a, "把热留在该去的地方", "I3", "F2:mirrorwing_warden", [
        objective(a, "brief", "听乔述说明生产与住区共用冷却线的风险", "先接通换班检修台；本次使用隔离回路，不切整条生产线。", p, "talk", ["cooling_plan"], [say(p, "有人把备用冷却配额当成可抽取余量。我们先用隔离台做一份真实热量记录，别拿工人的房间当散热器。")]),
        objective(a, "ledger", "读取热崖收到的配额与冷却账目", "记录在中层厂房；到侧面看清记录匣再按 G。核对发送端，保留工厂应急手动改接的记录。", "I3:cooling_ledger", "inspect", ["record"], [discover("I3:cooling_overdraft", "上游把冷却储备误计入可外送余量")]),
        objective(a, "exchange", "在隔离台把热匣热量导入有效冷却端", "先连通散热端，再调热。实际供受两端热量变化和散热记录必须相符；仅把温度数字降下去不能算修好。", "I3:thermal_transfer_verified", options=["manual_sink", "pumped_sink"], effects=[flag("I3:cooling_ready"), say(p, "这份记录有来源也有去处，才知道热没有被甩给别人。")]),
        objective(a, "dock", "带检修匣通过升流段，在高台稳稳制动落泊", "可借上升流，也可绕行外廊。承台周围留出减速距离；机速、载荷归属、落架稳定都正确才完成。", "I3:loaded_dock_verified", options=["updraft", "outer_corridor"], effects=[memory(p, "I3:kept_worker_cooling"), discover("I3:stoppable_route", "高差与载荷下仍可安全刹停的检修路线")]),
    ], "行动完成 · 工厂保留冷却线，履带兽的检修通道开放。"), boss_action("I3", "furnace_crawler", a, p, "在它冲过来前停住", "履带兽冲锋前会锁定直线。先横移让开，再把冷却端导向张开的散热片；冷却到位且履带刹停后核心才开放。借高度越过冲线也可，制动不能抵消正面撞击。", "履带兽的备用指令来自鸣菌地下光网，乔述留下轮班记录并接管本地冷却维护。")], {
        "I3:thermal_transfer_verified": binding("conserved_isolated_heat_exchange", ["manual_sink", "pumped_sink"], "I3:cooling_test", ["source_energy_loss_equals_sink_gain_plus_measured_dissipation", "real_connected_sink", "worker_loop_isolated", "stable_completion_receipt"]),
        "I3:loaded_dock_verified": binding("host_loaded_arrival_and_custody_receipt", ["updraft", "outer_corridor"], "I3:brake_dock", ["actual_routed_flight", "speed_below_dock_limit", "cassette_rest_and_custody_confirmed"]),
    })
    p = "npc:lingyin"
    a = "F3:separate_network"
    packs["F3"] = extension("F3", [person(p, "苓音", "菌谷养护人", "F3", "菌网把消息和养分一起送出去。割断所有根，看似安静，明天的花也不会开了。")], [
        marker(p, "F3", [-24, 5, 20], "苓音 · 养护棚", "npc"),
        marker("F3:root_sample", "F3", [-12, 4, 8], "带热痕的菌根样本"),
        marker("F3:network_junction", "F3", [12, 7, 6], "光网隔离接口"),
        marker("F3:nursery_exit", "F3", [20, 9, -2], "养分试送接收台"),
        marker("F3:boss_briefing", "F3", [0, 8, -18], "鸣菌战区 · 静声台"),
        marker("F3:boss_record", "F3", [0, 8, -25], "共生体 · 重复指令根结"),
    ], [action(a, "断开噪声，留下养分", "F3", "I3:furnace_crawler", [
        objective(a, "sample", "对照工厂热记录，检查仍在受伤的菌根", "在菌谷低层读样本；发热来自重复脉冲，不能只归咎于工厂冷却。", "F3:root_sample", "inspect", ["record"], [discover("F3:independent_feedback", "停止工业抽取后仍有重复脉冲，伤害还有另一来源")]),
        objective(a, "listen", "让苓音说明菌网维生与传信的两条路径", "先确认哪条根在送养分，哪条在放大脉冲；不要一并烧断。", p, "talk", ["network_paths"], [say(p, "旧中枢把求援当成配额不足，于是越求援越抽取。我们保留养分根，只隔离那条放大声。")]),
        objective(a, "isolate", "用协作分身维持一端，隔离重复信号根", "一个人可让协作分身维持已到位的接点，再到另一端隔离；双人可分头处理。连接须实际保持，不要求两人抢同一位置。", "F3:signal_isolation_verified", options=["echo_hold", "two_pilots", "latched_bypass"], effects=[flag("F3:signal_isolated"), memory(p, "F3:kept_nutrient_path")]),
        objective(a, "feed", "催生保留下来的养分桥，确认试送抵达育苗棚", "接回光路再催生。实际通路连通且养护机送达才算完成；种下就离开不会自动算到货。", "F3:nutrient_delivery_verified", options=["grown_path", "existing_bypass"], effects=[discover("F3:living_isolation", "重复信号已隔离，菌谷的养分服务仍可抵达")]),
    ], "行动完成 · 养分线保留，共生体的回声可以分离。"), boss_action("F3", "mycelial_choir", a, p, "让不同的声音分开", "三个声结轮流放大脉冲；找到正在发亮的一结，维持隔离再处理它。分身或另一名队友可维持接口，锁定旁路也能单人操作。把全部根烧掉会关闭窗口，不是捷径。", "共生体记录揭示旧中枢的自动补偿失控，离岸阵列仍可改写这条协议。")], {
        "F3:signal_isolation_verified": binding("actual_two_point_signal_separation", ["echo_hold", "two_pilots", "latched_bypass"], "F3:network_junction", ["both_real_interface_states_maintained", "signal_path_disconnected", "nutrient_path_still_connected", "no_required_second_human"]),
        "F3:nutrient_delivery_verified": binding("authored_npc_actual_delivery_event", ["grown_path", "existing_bypass"], "F3:nursery_exit", ["passable_supported_route", "named_carrier_completed_pickup_then_deliver", "event_from_authoritative_ecology_not_client"]),
    })
    p = "npc:wenxu"
    a = "I4:array_witness"
    packs["I4"] = extension("I4", [person(p, "闻序", "离岸阵列值守员", "I4", "这套系统最初是为了让任何一边都不断供。它一直在补偿，却没人再问补偿从哪里来。")], [
        marker(p, "I4", [-24, 6, 20], "闻序 · 风暴值守台", "npc"),
        marker("I4:protocol_archive", "I4", [-12, 8, 7], "原始补偿协议"),
        marker("I4:witness_receiver", "I4", [20, 12, 4], "公开见证接收器"),
        marker("I4:shelter_route", "I4", [14, 5, -3], "值守检修避风台", "reach"),
        marker("I4:boss_briefing", "I4", [0, 10, -18], "棱镜战区 · 遮光侧台"),
        marker("I4:choice_terminal", "I4", [0, 10, -25], "阵列协议 · 共同签署台"),
    ], [action(a, "把看不见的配额摊开", "I4", "F3:mycelial_choir", [
        objective(a, "brief", "询问闻序，核对自动补偿的原意与现状", "在值守台听取说明；已有两界原件不会被本区新解释覆盖。", p, "talk", ["protocol_origin"], [say(p, "最初写的是缺额补偿。后来中继把补偿又算成新缺额，形成自我抬高的配额。有人做过应急改接，却没能停掉它。")]),
        objective(a, "archive", "读取原始协议，核对中继修改的确切条目", "沿上层检修廊读取协议匣；原始设计、应急改接、失控结果分别记录。", "I4:protocol_archive", "inspect", ["record"], [discover("I4:protocol_chain", "自动补偿叠加中继回报形成重复需求，单一阵营抢能解释不足")]),
        objective(a, "witness", "把三处原始记录送到真实见证接收器", "接回输能光路和接收器后提交港口、镜湖、菌谷三份原件。传输需要实际通道，点亮外壳不代表数据已到达。", "I4:evidence_delivery_verified", options=["optical", "wired_bypass"], effects=[flag("I4:evidence_witnessed"), memory(p, "I4:shared_originals")]),
        objective(a, "shelter", "选择遮挡与高度穿过风暴检修段", "风暴前有可见风向和警示。可低飞借实体挡墙，或等侧向风窗绕高路；不设必须受伤的门槛。", "I4:storm_route_verified", options=["covered_low", "high_window"], effects=[discover("I4:storm_service_path", "值守机与玩家均可使用的阵列检修路径")]),
        objective(a, "isolate", "稳定检修平台，断开民用总线与棱镜防御的共用馈线", "力场固定平台或手动锁销都可；实际平台到位、馈线隔离和民用供能保留须同时成立。", "I4:defence_isolated", options=["field_lock", "mechanical_lock"], effects=[flag("I4:defence_isolated"), say(p, "居民线留住了，防御阵列现在可以单独停机。等它停下，再决定谁能改写补偿协议。")]),
    ], "行动完成 · 原始证据有了见证，防御与民用馈线已经分离。"), boss_action("I4", "prism_array", a, p, "穿过会移动的光路", "阵列发射前先标出反射路径。移动实体遮光板或绕到不受照的一侧；对齐接收端可反向开罩。平台风隙需要制动，玻璃倒影不是掩体。", "阵列控制权已按共同签署方案保存，前往冠峰汇合两界支脉。", {"text": "确认公开限流协议或地区双签协议", "hint": "公开限流：所有地区看见统一上限，闻序负责追踪异常；地区双签：地方可调整配额，跨界改动需两边签署，响应较慢。两案保留证据与民用底线；合作双方确认，提交前创建分支。", "options": ["public_caps", "regional_cosign"]})], {
        "I4:evidence_delivery_verified": binding("actual_receiver_three_original_hash_receipts", ["optical", "wired_bypass"], "I4:witness_receiver", ["port_mirror_fungi_originals_preserved", "actual_unoccluded_or_wired_channel", "receiver_receipts_match_original_hashes"]),
        "I4:storm_route_verified": binding("host_route_traversal_and_arrival", ["covered_low", "high_window"], "I4:shelter_route", ["actual_start_to_end_route", "no_teleport", "arrival_at_supported_shelter"]),
        "I4:defence_isolated": binding("actual_platform_lock_and_circuit_connectivity", ["field_lock", "mechanical_lock"], "I4:shelter_route", ["real_platform_supported_and_still", "defence_feed_open", "civilian_supply_connected"]),
        "I4:chapter_choice": binding("host_consensus_after_boss_and_cost_panels", ["public_caps", "regional_cosign"], "I4:choice_terminal", ["boss_victory_committed", "both_cost_panels_inspected", "branch_created_before_commit", "party_consensus_if_two_players"], consumes_major_choice_budget=1),
    })
    p = "npc:guanzhi"
    a = "F4:vein_reunion"
    packs["F4"] = extension("F4", [person(p, "冠枝", "冠峰脉络看护者", "F4", "两条支脉已经能说话。让我们把一路修好的东西接起来，不用再选一边失去声音。")], [
        marker(p, "F4", [-24, 8, 20], "冠枝 · 冠峰接续台", "npc"),
        marker("F4:industrial_socket", "F4", [-12, 9, 6], "工业支脉接口"),
        marker("F4:living_socket", "F4", [14, 12, 6], "活脉支路接口"),
        marker("F4:shared_test", "F4", [18, 16, -5], "两界负载试验台"),
        marker("F4:boss_briefing", "F4", [0, 12, -18], "共脉中枢 · 安全接近台"),
        marker("F4:choice_terminal", "F4", [0, 12, -25], "最终方案 · 双界签署台"),
    ], [action(a, "让一路的修复接在一起", "F4", "I4:prism_array", [
        objective(a, "council", "接通两界伙伴，核对每个地区已保住的服务", "短无线电汇合林岚、阮衡、阿苔及各地联络人；只回顾已提交事实，不要求重新跑八区。", p, "talk", ["reunion"], [say(p, "水城能供水，菌谷能送养分，港口和工厂保留应急线。我们现在要处理的，是让重复抽取停止，同时让这些修复继续工作。")]),
        objective(a, "industry", "接入有上限的工业支脉，保持应急供能", "连接后观察真实负载和电荷流向；不能通过直接设为通电跳过接线。", "F4:industrial_link_verified", options=["limited_bus"], effects=[flag("F4:industrial_link_ready"), memory("npc:ruanheng", "F4:lifeline_kept")]),
        objective(a, "living", "把活脉光路接回根冠，建立可承重路径", "按光照、生长、固定顺序组合；原有绕路仍可用。需要真实光路和完整支撑，不把装饰根当通路。", "F4:living_link_verified", options=["growth_support", "stable_bypass"], effects=[flag("F4:living_link_ready"), memory("npc:atai", "F4:living_link_kept")]),
        objective(a, "test", "在真实双端负载下试运行并测量回流", "一人可用协作分身维持一端，或锁定旁路；双人分头看读数。观察同一轮双端记录，不只读其中一边。", "F4:dual_load_verified", options=["echo_test", "two_pilots", "latched_test"], effects=[discover("F4:dual_load_record", "两界实际负载已可分别限流，共脉仍有重复补偿回路")]),
        objective(a, "plan", "阅读三种终局方案的收益、负担与伙伴职责", "方案均保底生存服务：共同照料更依赖持续协作；工业优先恢复较快、活脉扩展较慢；活脉优先生态恢复较快、工业扩产较慢。还没有作出选择。", "F4:plans_reviewed", options=["all_read"], effects=[flag("F4:final_plans_reviewed"), say(p, "代价要先讲清楚。我们可以保住底线，再决定谁先恢复，以及以后谁负责看护。停下中枢后，由你们共同签署。")]),
    ], "行动完成 · 两端真实负载与三种方案已准备，进入共脉中枢。"), boss_action("F4", "twin_vein_core", a, p, "把抽取改成彼此可承受的流动", "中枢依次启动电荷、热、活脉三种部件。读当前预警，分别断开重复馈线、接冷端或固定生长支点；三条单人替代路线都保留。半血后会轮换已启用部件，需要重新观察。", "终局方案已留存；可在机库继续探索已修复地区，伙伴按已选职责接续生活。", {"text": "共同签署最终支脉方案，确认两界未来的负担", "hint": "共同照料：均衡恢复、需要两界持续维护；工业优先：应急与生产较快，活脉扩展较慢；活脉优先：生态修复较快，工厂扩产较慢。三个方案均保持居民供水、幼根与撤离路线。不以隐藏计时杀死角色。读清职责后单人确认或双方同意，选择前独立分支。", "options": ["shared_stewardship", "industrial_lifeline", "living_vein"]})], {
        "F4:industrial_link_verified": binding("actual_bounded_bus_flow", ["limited_bus"], "F4:industrial_socket", ["physical_connection", "measured_draw_within_cap", "lifeline_connected"]),
        "F4:living_link_verified": binding("actual_light_and_supported_living_route", ["growth_support", "stable_bypass"], "F4:living_socket", ["receiver_illuminated", "continuous_supported_route", "root_nutrition_preserved"]),
        "F4:dual_load_verified": binding("matching_actual_dual_load_records", ["echo_test", "two_pilots", "latched_test"], "F4:shared_test", ["both_records_same_test_serial", "actual_load_each_side", "return_flow_measured", "no_required_second_human"]),
        "F4:plans_reviewed": binding("three_host_manual_plan_inspections", ["all_read"], "F4:choice_terminal", ["all_three_benefit_and_cost_panels_explicitly_read", "actual_range_and_los"]),
        "F4:chapter_choice": binding("host_consensus_after_boss_and_all_plans", ["shared_stewardship", "industrial_lifeline", "living_vein"], "F4:choice_terminal", ["boss_victory_committed", "all_three_cost_panels_inspected", "branch_created_before_commit", "party_consensus_if_two_players", "lifeline_invariants_revalidated"], consumes_major_choice_budget=1),
    })
    for region, pack in packs.items():
        boss = pack["actions"][1]["id"].split(":", 1)[1]
        pack["host_bindings"][region + ":boss_observed"] = binding("host_observed_full_telegraph_active_recovery_cycle", ["observed"], region + ":boss_briefing", ["real_arena_entry", "player_present_and_alive", "one_full_pattern_cycle"], boss_id=boss)
        pack["host_bindings"][region + ":boss_defeated"] = binding("durably_committed_campaign_boss_victory", ["committed"], region + ":boss_briefing", ["authoritative_encounter_completed", "same_store_victory_flag_and_receipt", "guest_reward_deduplicated"], boss_id=boss, campaign_receipt_id=f"boss:{region}:{boss}:{BASE}", reward_id=f"boss:{region}:{boss}", world_victory_flag=region + "_boss")
        for char in pack["characters"]:
            last = pack["actions"][1]["objectives"][-1]
            char["replies"].append({"after": last["id"], "lines": [pack["actions"][1]["completion_text"]]})
        (OUT / (region.lower() + "_actions.json")).write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    index = {"schema_version": 1, "content_id": "campaign_expansion_v1", "extends_content_id": BASE,
             "status": "authored_candidates_not_integrated",
             "base_extension_paths": ["res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json", "res://data/v3/actions/underdeck_action.json", "res://data/v3/actions/clinic_action.json", "res://data/v3/actions/distribution_action.json"],
             "extension_paths": ["res://data/v3/campaign/" + r.lower() + "_actions.json" for r in packs],
             "ordered_region_ids": list(packs),
             "region_unlocks": [{"from": "I2", "to": "F2", "requires_action": "I2:twin_pump_guardian"}, {"from": "F2", "to": "I3", "requires_action": "F2:mirrorwing_warden"}, {"from": "I3", "to": "F3", "requires_action": "I3:furnace_crawler"}, {"from": "F3", "to": "I4", "requires_action": "F3:mycelial_choir"}, {"from": "I4", "to": "F4", "requires_action": "I4:prism_array"}],
             "budget": {"existing_actions": 9, "existing_objectives": 34, "new_actions": 12, "new_objectives": 50, "total_authored_actions": 21, "total_objective_budget": 84, "runtime_complete_claim": False},
             "required_core_changes": ["TwinActionDirector.validate must permit all eight canonical region IDs in marker.region and action.region_id", "TwinOpeningStory setup appends extension_paths in index order", "Normal travel, physical bindings, input, Store and network integration remain Root-owned"],
             "play_order": [a["id"] for p in packs.values() for a in p["actions"]]}
    (OUT / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return packs


if __name__ == "__main__":
    result = create()
    print(f"Authored {sum(len(p['actions']) for p in result.values())} actions / "
          f"{sum(len(a['objectives']) for p in result.values() for a in p['actions'])} objectives; scene integration not claimed.")

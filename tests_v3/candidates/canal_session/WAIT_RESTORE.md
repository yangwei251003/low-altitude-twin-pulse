# 未下单 WAIT 挂匣恢复候选

本轮已在实际 Godot 4.7.2 / MAIN 通过 **78 checks、0 failures、0 engine errors**。旧 completed-safe v3 封套及其验证条件未修改；新 `canal_wait_checkpoint_v1` 仅接受真实 Bootstrap 已把冷匣挂到载机、热匣在 WORK、载机稳定驻 WAIT、未发动作/未有工序成果的阶段。允许该阶段真实温度、设备充能/轴速与序号变化，不把温度变化当完成。

## 宿主接口

- `CanalSession.capture_persistent_state()` 返回 `{ok,code,path,envelope}`，path 固定 `world.environment.I2_canal`。不可保存阶段明确失败；调用者只能将成功封套加入原 Store 同一事务。`persistent_state()` 兼容查询不代表成功回执。
- `prepare(world_data,destination,authority,discoveries=[])` 纯验证；I2 才创建 detached Assembly，其他区只验证旧数据。客户端仍拒绝。没有自动普通玩法注册。
- `adopt(prepared,world_data={})` 要求实际 current I2 World 已在树中，开始冻结的新现场构建；不能替换仍有效的旧实例。`ready=false`。
- `advance(delta)` 每个物理拍仅一次。完成全体身体/设备/账本/挂钩与空间检查后才解冻；重新观察真实接触至少350ms，当前拍重新核对后采用、注册六实体并 ready。恢复的接触历史不充当新世界证据。
- 通用 Session 暂停必须排除 `owns_body`。adapter 在停止控制器前捕获完整 WAIT 和原动量；暂停读缓存前重新核对身体/挂钩与 Rules/设备守卫。禁止把 stop 后归零的轴速/线速写成原值。

## 精确保存边界

物理服务器双方局部 PinJoint 锚点、节点初始 marker pose、bias/damping/impulse clamp、solver priority、成对免碰和实际碰撞过滤；两匣唯一占位/原 Custody revision/serial/grip；四个实际身体的姿态/线角速度/材料/阻尼/处理标志；两架原 Flight 伤损、电池、热量、计时与命令；WAIT 控制器序号/目标/稳定观察；原 Rules 水热账和微秒余量；Workbench 未提交状态/电量序号/实际受益机；Cooling 原状态/轴速度/防重放。没有拾货/work/service回执，没有新的钱包。

Workbench 原支持观察以历史数值保留，但新接触信用从0开始。恢复准备中的350ms物理观察不追补水网或工序墙钟；设备和飞行器正常受物理推进。首次原姿态/动量在全部冻结构造时可检查，采用后的自然推进不应逐位等于存档。

飞行中的任意路线、扫描、离架和任意多人载荷不在本封套范围。旧对象ID碰撞冷却只有已过0.7秒才允许省去；尚有活动碰撞冷却时拒绝捕获。未提供网络、玩家伤损保存或正式发布候选路径晋升。

## 实际专项与失败保留

`python tests_v3/candidates/canal_session/run_wait_test.py`：CPU2/private Job 外60秒、测试内55秒，实际 MAIN/四设施；old27与初始玩家位置明确仅QA前置。最终证据 `evidence/20261020_083741_5e5ceb/`：PID34280，29.203秒自然exit0，0残留，192项实际输入前后SHA一致。保存的原始log、result、inputs和源码快照不再修改。

已验证真实 Bootstrap到WAIT、实际 Rules/LOS充能与推轴、暂停前完整快照、原Session `_save_environment` / Store `failure_point=before_publish` 拒绝且原generation/现场不变、成功仅generation+1及Store重开、六实体不另存零散字段、三种非Dictionary rules安全拒绝、旧有效现场不被替换、真实MAIN新World冻结构建四身体及原关节、重新观察350ms真实支持后当拍采用、原序号/无新增信用和1.1秒续行。捕获载机速度并非被清零；回冷轴实际保存速度0.5803296602892035m/s，暂停缓存与原封套完全相同。

原关节局部A为 `(-.0021419525146484375,-.6499881148338318,-.003269195556640625)`，局部B为 `(.0037097930908203125,.43016499280929565,.0057697296142578125)`；恢复直接核对PhysicsServer双锚点，不重用默认attach锚。Custody原revision47 / serial4；Rules action_serial、jobs、credit仍0。此次两架均健康初态，不能替代带伤WAIT的专项；未测试客户端/任意在途或扫描恢复，也未在恢复点额外放置新障碍做负例。

|保留目录（均在本测试evidence下）|实际结果|定位|
|---|---|---|
|20261020_081916_62ff23|36/1，54.671s，PID23752|首次合并拒绝，未证明恢复|
|20261020_082532_906e07|36/1，53.687s，PID39600|明确Workbench序列化拒绝，真实支持/WAIT已稳定27秒|
|20261020_082820_37bc8b|36/1，26.906s，PID27032|原生受益机state拒绝、JSON往返却合法|
|20261020_083031_512021|36/1，26.891s，PID7240|定位严格keys；新增点键是StringName|
|20261020_083211_ddf863|36/1，53.109s，PID3372|字符串键修后暴露RigidBody原生质量表示差异|
|20261020_083510_d90e63|70/2，27.156s，PID41220|null早拒绝code断言与JSON整数规范化比较问题；保存/读回/冻结构建已过|
|20261020_083741_5e5ceb|78/0，29.203s，PID34280|完整候选链通过|

修复均未放宽物理门槛：新增 `row["wait"]` 保留严格String键；质量采用Catalog期望值的精确float32表示（真实3.200000047683716kg），不加质量误差范围；恢复首先用Rules既有 `_same` 验证保存值等价，然后采用该次restore后的原生baseline逐拍精确防变；非Dictionary rules在调用类型化restore之前拒绝。原生字段诊断另保留 `artifacts/v3/canal-wait-field-diagnostic-20261020-0830.log`、`canal-wait-native-key-20261020-0831.log`、`canal-wait-native-mass-20261020-0833.log`。它们是实际数值/类型诊断，不计入78项。

最终测试已改为实际arrived、支持≥.7s且接触冷却成熟后只捕获一次；永久schema拒绝立即失败，不以45秒重复等待掩盖错误。此为QA反馈加速，生产支持350ms及驻位门槛未变。

提交精选清单为同目录 `WAIT_SELECTED_FILES.json`：209个文件、3,548,532字节，逐文件原字节SHA；最终source完整保留，前六轮只选择log/result/inputs和与失败有关的改动源，其他原闭包仍留磁盘但不建议重复stage。三个原生短诊断log原字节复制到 `evidence/wait_native_diagnostics_20261020/`；其中源码副本对应最后一次mass诊断，前两次未另存完整源码，不能冒称三次各有全闭包证明。此次没有执行git add/commit。

[Godot PhysicsServer3D 官方接口](https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html)提供 `pin_joint_get/set_local_a/b`；本轮采用这些实际端点而非用 Joint 节点旧世界位置重算，也不调用默认0.65m的 attach_cargo。

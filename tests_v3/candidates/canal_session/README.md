# CanalSession 源码接线候选（短专项已通过）

唯一新增运行文件 `scripts/v3/gameplay/twin_canal_session.gd`。不注册全局类，不修改 MAIN / World / Registry / Store。原 Assembly / Rules / Custody / Workbench 全部复用，未复制演练场景或玩家控制器。

2026-10-20 实际 Godot 4.7.2 首轮 **82 checks / 0 failure / 0 engine error**；PID 22504（子进程 20852）自然 exit 0，28.094 秒，0 残留，187 个输入 SHA 前后相同。证据 `evidence/20261020_074012_b1888d/`：原始 engine.log、result.json、inputs.json、source/；运行期间及之后没有改 adapter/test。实际 Bootstrap 1065 拍，WAIT 距离 0.071774m、速度 0.048409m/s、稳定 0.35s；真实充能 35、轴接受一次 serial 2 并到 0.28m；有效通用事务被暂停设备拒绝时实体/能量/版本/冷却/原账均保持。不是完整工作单、保存、网络或真人玩法验收。

## Root 接口

- `setup(session)`；`prepare(world_data,destination,authority,discoveries=[])` 创建 detached、未配置 Assembly。
- `adopt(prepared,world_data={}) -> {ok,code,error}` 仅当前 live I2、authority、无旧 site 时安装。失败不释放旧有效模块。`ready` 必须等真实 Bootstrap 到 WAIT。
- 每一真实物理拍 `advance(delta)` 一次，放在 Session 现有 World/四设施更新后。不得拆拍补时；当前 `set_paused(bool)` 同时暂停原控制器/规则及本件所有 RigidBody（见下方新增 57 项证据）。
- `owns_target(id)`、`use_ability(peer,payload) -> {handled,ok,code,...}`。该分支必须放在 Session 原 `_use_ability` **任何 live actor 修改/通用 commit 之前**，返回后禁止调用 `_execute_physics` 或再次扣能量。成功由 adapter 更新 actor/target、0.35s cooldown 和 `stats.abilities`；失败仅增加 `stats.rejected_abilities`，原实体/能量/版本/冷却不动。Root 单独显示通知/beam，不需要重执行。
- `target_definitions/context/status`；`sync_roster` 不建立新玩家/轴租约。`clear/reset_connection` 仅移除身份仍匹配的本件目标与 owned Assembly，不删 World/玩家/四设施或同 ID 的新注册对象。
- 六目标按实际 body 出现逐一注册至 World objects/definitions/initial_transforms 和 Session.entities，并设置 `entity_id` 供原 LOS first-hit 判定。owner/revision 仅初建；以后只同步 position/temperature/charge/capacity/threshold/powered，保留 Rules 的归属和租约。

## 不能当作正式启用的边界

1. `persistence_supported=false / client_state_supported=false / ordinary_play_enabled=false`，`persistent_state()` 空字典**不代表保存成功**。现 Session `_persistent_environment()` 会遍历六目标并保存零散温度/电荷，却缺货物/工序账；接普通玩法前必须统一完整保存生命周期，禁止凭这些零散字段重建。已有 `environment.I2_canal` 或 `canal_candidate_checkpoint` 明确拒绝 fresh init。
2. 无 publish/receive/consume 网络假实现、无第五流 ready 假证据，不加入当前设施 Registry/codec。现 export preset 排除 candidates，依赖 Assembly 未晋升生产路径，不能称下一个独立包具备此功能。
3. Session `_apply_pause_state` 仍需接线：其通用冻结/解冻循环必须排除 `canal.owns_body(body)`，由本件统一处理包括未注册受益机在内的全部刚体。不能将 clear 用作离区后台待命；整体物理暂停不等于可保存任意中途状态。
4. 现直接候选 API 只接受真实主机鉴权后能力；没有新 RPC、任务/奖品或维修交易。普通 Session 接入尚未提交。

## 已执行的单次验证

Root 授权后执行了：`python tests_v3/candidates/canal_session/run_test.py`。没有追加重跑。

CPU2 / 原 dev.execute 私有 Job 外限 60s，内部 55s，保存原日志/小结果/输入前后 SHA。使用真实 MAIN solo、隔离 `qa_canal_session_*` 档；旧 27 目标仅为合法 I2 入口夹具。显式关闭 QA 的 `owns_world` 自动保存；不修改真实档、不联网。玩家仅一次摆位 `(8,3.2,27)` 并冻结作为射线夹具，不声称实际飞过该路线。

真实 Bootstrap/PinJoint 到 WAIT、六实体出现、原四设施不变；原 Rules/Session LOS 充能、真实阀推拉只执行一次；冷却/未知玩家/旧版本/错能力/远目标/真实遮挡/有效通用意图被实际暂停设备拒绝，检查拒绝前后实体/设备/原账/冷却完全不变；租约同步不覆盖；暂停/旧模块拒绝替换/同 ID 新注册清理边界。不开工作单，不复跑已验完整工序，不声称存档或 LAN 通过。

## 整体物理暂停补充：57/0，旧 82 输入与证据不改

2026-10-20 执行 `python tests_v3/candidates/canal_session/run_pause_test.py`，仅重用真实 MAIN/old27 启动帮助函数，不执行旧能力套件或完整工序。首轮 `evidence/20261020_075030_f7e9d7/` 保留 **36 项 / 2 失败 / 0 引擎错误**，PID 30784、8.657s：刚创建、尚未过物理拍的 carrier，Node 与 PhysicsServer 初始变换未同步，立即 resume 被严格位姿检查拒绝；该轮没有记录原始变换数值，不能声称已量出差值。

最小修复在捕获前调用 `force_update_transform()` 刷新已有 Node3D 变换通知（不赋位姿），随后要求 server/Node 一致。第二轮 `evidence/20261020_075138_43f7e8/` **57 项 / 0 失败 / 0 引擎错误**；PID 22128、27.922s、自然 exit 0、0 残留、188 输入 SHA 前后不变。

- 原 Bootstrap 固有 `freeze=true`、各体 sleeping/线角速度/process/physics_process 初值均可精确还原。
- 真实载货 WAIT 的四个 RigidBody（载机、两匣、未注册受益机）及一个真实 PinJoint；暂停 66 拍（1.1s），最大位置漂移 **0m**，两架 Flight 积分时钟和 Rules/水账不推进。暂停只是刚体模式切换，碰撞体与关节没有删除或重建。
- 重复 pause 保留首份快照；resume 原值只恢复一次；再正常 66 拍，两架 Flight 确实恢复积分，原身份/关节保持，无新碰撞、能力、工序、信用。
- 真调用旧 Session 通用 freeze 在前会得到 `external_body_mode_changed_before_pause:CandidateCarrier`。这是拒绝错误调用顺序，不是从丢失信息猜原动态状态。
- 正向验证完后，明确 QA 将被冻结匣横移 1mm；adapter 检出 Node/Physics/原姿态差，锁错并拒绝恢复，未传送纠正；仅销毁该损坏候选，外部四设施/玩家/World 保留。

接入顺序：在宿主真实暂停切换中显式调用 `canal.set_paused(value)`；通用 player/World 冻结循环始终跳过 `canal.owns_body(body)`。不要先冻结本件再捕获，也不要在本件恢复后通用解冻覆盖原 `freeze=true`。`advance` 遇宿主已暂停而本件尚未显式捕获，返回 `explicit_pause_transition_required`。暂停期间验证同一 owned body/RID/space/pose/Joint 和冻结处理开关；发现异常不偷偷重置现场。`status` 提供 `physics_paused / paused_body_count / pause_restores / pause_fault`。

依据：[Godot RigidBody3D freeze/睡眠文档](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html)说明冻结不再施加重力与力；[官方实现](https://raw.githubusercontent.com/godotengine/godot/master/scene/3d/physics/rigid_body_3d.cpp)的 freeze 切换改变 body mode。具体 4.7.2 的初始化通知、动量还原与实际无漂移结论来自以上本机专项，不由网页推定。

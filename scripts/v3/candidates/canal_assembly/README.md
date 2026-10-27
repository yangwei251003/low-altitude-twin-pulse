# Canal Assembly — 独立初建 / 安全点恢复候选

初建首轮及默认销毁路径已实际通过（对应各证据内原 source）；新增 saved-restore 已以独立52项实测通过；三轮对应各自源码，未把旧68项当作本次重跑。复用原 route `5e455d78-37b2-423b-b660-0cc3185eae49`。此文件是接线合同；不登记第十行动、MAIN、网络或存档成果。

## 宿主接口

1. 宿主已创建、入树并构建真实 I2 World。将 `Assembly.new()` 以 identity 直接加为该 World 子节点，调用 `configure(world, world.sample_environment, true)`。返回 `{ok,code,configured,ready,ordered,paused,closed,fatal}`；configure 只开始真实 Bootstrap，不能当作已经在 WAIT。
2. 宿主每物理拍调用 `advance(delta, authority, suspended=false)`。调用顺序固定：Bootstrap（内部唯一 Custody）→准备后唯一 Custody 或 Executor→Cooling→Rules 的实际有效微秒→Workbench。World 的 `clock_seconds` 仍由外部宿主推进。不会读墙钟补时；一次物理拍重复正 delta 拒绝。
3. `status(include_details=false)` 返回准备/订单/暂停/故障、最后拍/规则时钟、设备序号、严格8字段 place/cooling 交接计数。`true` 额外提供原模块只读报告，便于失败诊断。
4. `context()` 提供受信宿主 live 引用：`carrier/cargos/berths/custody/rules/environment_query/executor/cooling/workbench`。外层和两个注册表返回副本，实体仍为原对象；这不是可序列化保存数据。
5. `target_definitions()` 返回数组，每项 `{id,body,tags,abilities,state}`。state 只有实时物理 position/temperature/charge/capacity/threshold；宿主仅首次创建 neutral entity，此后只合并 state，**不得重置宿主自己的 owner/revision/takeover lease**。全部六目标就绪后包括两匣、运输机、回冷电点/滑阀、工位电点。Workbench 原描述标签 charge 正确适配为通用规则实际识别的 conductive/electrical。
6. `apply_authorized_ability(target_id,ability_id,mode="",physics_requests=[],authority=true)` 是宿主已完成真实权限/距离/首命中/能量验证后的**同步本域接受入口**；不是 RPC，也不是客户端自报授权证据。热量/充能/推拉/留工作单沿现 playable 调用原模块。不改玩家 energy/revision、通用冷却、临时租约或 Store。宿主应先把 `Ability.commit` 写入私有 candidate，再调用本入口，只有本域成功才采用 candidate，不能提前扣能量。推拉必须带唯一原 resolve 的 impulse 请求；没有该请求或错目标拒绝。
7. `set_paused(value,authority)` 停本件规则/轴/观察窗口及飞行指令；`advance(...,suspended=true)`同样停止。载机和受益机用原控制器正常制动/落架，**不宣称冻结刚体物理**；需要游戏整体暂停由宿主负责。非房主调用在改任何命令/时间/Custody之前拒绝；这版没有客户状态重建。
8. `close(authority)` 保留原账和 pending、停止本件控制并撤下 targets，不伪造完成、不清 pending。删除 Assembly 才删除其新子树；不会删除外部 World、玩家或原四设施。正常关闭须在 owner/子节点仍在树内调用；`_exit_tree` 只撤销 facade 的授权/可用性，绝不再调用已离树子模块的 report/tick/global transform。`close` 也不是离区后台待命接口。

## 所有权和已有事实

原 Bootstrap 接受任一 live 物理 host，本件把自己这个 identity Node3D 传给它；新增 site/机体/货物/四泊位从第一帧就在 Assembly 下，不在关节生成后 reparent。实际物理空间与收到的 I2 World 相同，查询仍绑定该 World。Cooling/Workbench/已审 RackArt 也是本件子节点。

未留工作单时，以原 Pilot 对真实 WAIT 持续驻位。接管能力成功仅把原 Executor 接上，不跳过实际初态门槛。工序中继续 tick Executor 的原锚点驻位；工序后由原回执驱动实际回收。冷却只在已松钩、同一个八字段 place pending、fall/commit、真实支撑成立的窄交接期断开该接头；其它物理/规则矛盾仍拒绝。

本件只有原低路 staggered 运输/原位冷却工序；未实现的 tray/buffer/high 路动作继续由原 Executor 返回 awaiting_external，不产生假回执。已消费服务后的新受益机、玩家维修事务、Repository、跨区留存/同步均由后续宿主接线；本次仅补下述既有安全点物理恢复，不扩大工序/奖励范围。

## 已执行的独立验证

`tests_v3/candidates/canal_assembly/test_canal_assembly.gd` 由外部创建真实生产 I2、四设施、一个 TR01 和 PilotInput。仅玩家初始观察位 `(2.5,3,8.5)` 是明示 QA 布置；之后玩家飞向接管点/返回使用原输入受力，载机和两匣全程复用真实 Bootstrap/Executor/Dock/Custody。

以真实首命中+原 Ability.resolve/commit 完成供电、原位降温、接管留单，验证原位工序、真实巡检机离架、六个真实回收回执与两匣南座落稳、后续5秒不重复服务。并检非房主/同拍拒绝、30拍暂停、World 四设施/RID/shape不变和关闭删除所有权。此专项不代替另一路完整十步换匣、不证明UI/真人/MAIN/保存/联机。

拟单次命令 `python tests_v3/candidates/canal_assembly/run_test.py`，CPU2/私有进程树，外240s/内225s。首次已获 Root 窗口并真实执行：`evidence/20261020_064511_ebb6fa/`，68 checks、0 failures、0 engine errors；PID 13808，145.937s 自然 exit0、0 owned residual，127 个 literal-resource 输入哈希前后不变。6 个真实 cleanup 回执、一个工序/25kJ、一次离架、服务 credit=1/consumed=0；最后有效 trace 的窄交接计数为2、回冷109816ml。此结果只覆盖显式 close 后删除，不能声称已覆盖默认父级销毁。原 source/result/log/inputs 原字节保留。


只读审查确认 `_exit_tree → close → Workbench.report → head.global_position` 在子节点已离树时不安全。现已静态改为退出时仅本地状态撤销，正常 live close 原调用顺序保持；离树 `status(true)` 也不读取子模块。独立 `test_canal_assembly_lifecycle.gd` 将真实 Bootstrap 到 WAIT、创建 actual head/载货关节后，**不调用 close 直接删除 owner**；检查旧四设施和原账不变/owned 子树释放/无引擎错误。命令 `python tests_v3/candidates/canal_assembly/run_test.py --lifecycle`，外60s/内50s；已获 Root 独占窗口实际运行：`evidence/20261020_065108_315e41/`，13 checks、0 failures、0 engine errors；PID 41444，21.703s 自然 exit0、0 owned residual，125 个 literal-resource 输入哈希前后不变。真实 Bootstrap 1065 拍到 WAIT 后无 close 删除 owner；载货 PinJoint/工具和新增子树释放，旧四设施/原账保留，离树数据报告不再访问 global transform。这项修复未改运输、工序或能力路径，没有为销毁覆盖重复完整链路。


## saved-restore 接口（独立52项实测）

- `prepare_saved(world, environment_query, site_envelope, device_serial, authority=true)`：空 identity Assembly 直接挂在已有真实 I2 World 下；只接受原 `canal_safe_checkpoint_v3`，仍限首工序/已离架、两匣原阈值 docked350ms/空挂载/无 pending/稳定 anchor。`device_serial` 为宿主保存的单一设备命令序号，必须是有限整数、不小于原 Cooling charge/axis 与 Workbench charge 序号。校验后原 `CheckpointRestore.prepare(self,...)` 直接建本件子树，**不会创建 Bootstrap 第二套货物/账本，也不 reparent 运行中的物理节点**。
- `advance` 准备期仅转交原 `Restore.tick`；不再同时推进 Executor/Cooling/Rules/Workbench。`status` 增 `restored_mode/restore_pending/restore_ready`，未采用前 `ready=false`、context/targets 空，能力拒绝。暂停调用原恢复器清 ready 观察信用，非 host 不写命令或物理。
- `adopt_saved(authority=true)`：只能采用**当前物理拍**原 ready，内部仍调用原 `Restore.adopt` 再次 capture 实际支撑/载机/工具。过拍 ready 不能采用，须继续真实 tick。成功直接接原 context/executor/workbench/cooling；设备序号、Rules 水/热时钟及余量从原数据延续。已消费首份服务由原恢复器进入 `wait_for_next_beneficiary`，不会补 credit、制造第二架受益机或再发工序回执。
- `discard_saved`：只删除未采用的本件候选；已采用拒绝。当前 World 任何现存 fresh/restored site 都在创建前拒绝，绝不为让路删除/冻结旧站。需要加载替换时，宿主自行建立隔离 staging World，保持旧站，待物理 ready/adopt 后才切换。该 Assembly 不创建 World，不负责存盘/玩家/相机，也不调用 Repository。
- 正常 `context` 可继续供现 `PlayerCheckpoint.capture` 使用；外部 PlayerCheckpoint/玩家创建/能力与 world.clock 恢复仍属于宿主，不复制封套或另建钱包/网络协议。

新增 `test_canal_assembly_restore.gd` 只用两份已有真实完整 JSON：原未消费玩家保存 `90fa185b…` 与已通过54项 UI 的已消费保存 `1831a081…`，取其原 site 子树/设备 serial。测试初建当前真实生产 I2，从旧封套实际重建并重新获取真实350ms支撑；覆盖非法版本/重放序号/非host、未采用目标锁闭、暂停与过拍采用拒绝、单一 ledger/模块/形体身份、两种额度状态各5秒正常 host、旧World保持、真实新增末端障碍失败销毁和主动取消。新障碍是明确 QA 负向夹具，没有修改货物位姿/阈值，也不重跑68项工序。

实际命令 `python tests_v3/candidates/canal_assembly/run_test.py --restore`，CPU2/private job 外60s/内50s。证据 `evidence/20261020_071616_5e04e4/`：52 checks、0 failures、0 engine errors，PID35128，18.640s 自然 exit0、0 owned residual，133个选定输入SHA前后不变。未消费与已消费两态各正常300拍/5秒，最大anchor误差分别0.0277095m/0.0277814m；同一模块/实体身份不变，jobs=1/action_serial=7，credit保持1或0、consumed保持0或1，未产生新回执。原device serial7保留，明确QA宿主下一次实际充能后到8。实际末端障碍触发 `restore_tick:workbench:beneficiary_initial_obstructed` 并清掉新候选，旧站继续有效。原始来源/输出/哈希见同目录 summary.json/result.json/inputs.json/source。

该专项载机/受益机fixture为满血，不能追加宣称新伤损矩阵；实际非满电量保持并正常继续消耗。它只重建两份历史安全点，不完成新工序、不创建玩家/Repository，不证明 MAIN、存储事务、任意中途恢复、客户端或跨区留存。

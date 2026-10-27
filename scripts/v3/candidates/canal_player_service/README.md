# 首份服务的玩家维修候选

独立候选；适配器本身不注册 MAIN、不接玩家按键、不增加任务或钱包。Root 已在独立 canal_playable 样板接入真实 G/F9；专项与实际三图结果见末尾，均不等于 MAIN/LAN 接入。

- `player_service.gd.configure(context, executor, workbench, cooling, player, repository)` 只绑定同一实际场景。Repository 使用原 `canal_candidate` 独立档或 `user://qa_v3/...`，禁止真实 default/V2 档。
- 正常宿主物理链结束后调用 `observe(ability_state, world_clock, authority, paused)`。它使用原 PlayerCheckpoint 的真实 350ms 安全观察；同拍多次不加时间。UI 只排队，在本拍 observe 后调用 `request(request_serial, expected_generation, ability_state, world_clock, authority, paused)`。
- 只需在 G 排队期间连续观察；取消、暂停或存在租约时调用公开 `reset_observation()`，不直接写私有成员，不清除世界或事务。
- 服务点是既有 `workbench.power_target` / `I2:canal_workbench_power`，当前实际中心 `(5.1,1.05,5.4)`；3D 距离≤4m，真实射线第一命中必须是该实体。`interaction()` 返回实时位置/距离/拒绝原因，不能以 HUD 锚点代替实际 LOS。
- 原有首工序及离架结果、两匣真实落稳、空挂载、工具 PARK、载机实际驻位，以及玩家正常 TR01/低速/无当前接触，均沿用原检查点门槛。宿主仍须事先排除无法保存的有效接管租约；不在本适配器复制租约账。

一次请求同步完成：本帧重新捕获 → 原 `Rules.prepare_service` → 完整封套中仅增加 `min(25, maximum-health)` 的玩家 hull health 并写入原 Rules 消费候选 → 原 Repository/Store 逐代事务及精确读回 → `Rules.adopt_service` → 执行器公开等待入口 → Flight 采用相同 damage 字典。除了 health，装甲、部件、伤损 serial、电池、热量、计时器、运动、碰撞历史及能力值均保留。没有 await、推进时间或伪造工序。

`service_committed` 带 `healed_hp/generation/service_serial/health`；同 serial 重复返回 `already_serviced` 且 healed=0，后续新 serial 返回 `awaiting_new_beneficiary`。满血 `hull_already_full` 不写盘、不扣额度。普通写盘失败 `save_failed:*` 不改现场。若磁盘可能已提交而现场/读回不一致，`reload_required:true` 要求停止新保存并读取原档，不能用未消费的旧现场覆盖；不承诺跨进程崩溃瞬间的内存原子性。

消费后 Rules 原有 `job_requested=true` 保留。新增 `Executor.wait_for_next_beneficiary(authority)` 仅接受已消费首份、空 pending、实际空载稳定 anchor 的宿主；之后每拍继续原 Pilot 完整扫掠和 Custody 观察，不再请求第二工序。没有解除等待/制造第二受益机接口。恢复器在采用已消费封套时接同一入口；暂停只是原实际制动，不声称冻结物理。现有 checkpoint v3/player v1 schema 已允许合法消费，不修改版本或放宽验证。

独立测试入口：`res://tests_v3/candidates/canal_player_service/test_player_service.gd`，内40s/建议外45s。使用真实57项 F5/F9通过结果的 site 子树（SHA c02925ec7c6c38c6d2cf3acf841d2b54e265547a5f4faac3f1668718e6d2490f）；公开 DamageModel 制造明确 QA 伤损，验证满血/遮挡/失败写盘/25HP上限/幂等/后续保存，以及消费后与重新加载后各5秒真实宿主继续。新玩家初始位与资源是明示 QA 夹具，不称真人探索或重做完整运输。

首轮 `artifacts/v3/canal-player-service-first-20261020_053919_d2796d.log`：43检查/1失败/0引擎错误，PID32272自然exit1，22.000s，0残留，215输入SHA不变。维修实际69.76→94.76，其他damage字段不变；两次5秒驻位最大anchor误差分别0.0235814m/0.0256053m，action_serial保持7，首工序1、消费1、credit0。原失败为“写盘失败保持不变”的合并断言，旧QA错误地对两份已JSON读回值再次编码一侧；修为读回值精确比较并分别记录4项布尔。保留原首败，不把42项通过当43项通过。同期核正helper的`matches_persisted_value(live,saved)`参数方向：实际历史在前、磁盘历史在后。修后复测记录如下；首轮失败保留。


修后专项 `artifacts/v3/canal-player-service-readback-20261020_054833_65379d.log`：43/43 PASS，0引擎错误，PID40588自然exit0，23.578s，0残留，215输入SHA不变。写盘失败后 generation/persisted_envelope/rules/player 四项分列全部为true。维修69.76→94.76、装甲2.24与动力部件29.408保留；原现场与重建后各5秒真实驻位最大误差0.02358136/0.02560532m，未产生第二工序。

首个UI探针 `artifacts/v3/art/canal-player-service-ui-20261020_055126_4029c2/state_checks.json`：51/51 PASS，0引擎错误，PID44272自然exit0，29.016s，0残留。唯一初始摆位后真实G修复95.68→100（4.32HP）、credit1→0、generation1→2；F9新树采用并继续5.3167秒，重复G拒领。电池未补满，wrapper224输入及实际Scene闭包331输入均不变。三图文字无截断，但中心标签盖住真正玩家；底栏处白机是巡检受益机，不能把它当玩家可见证据。

Root将工位提示避让真实玩家投影，并补G/已用信息。复测 `canal-player-service-label-20261020_055635_656dba` 54/54 PASS，PID43640、24.375s、0错误/残留、224 wrapper输入不变。Root逐看新三图，中心玩家清晰、标签在右侧；界面/一次维修保存范围通过，整区灰盒及MAIN/多人仍未完成。

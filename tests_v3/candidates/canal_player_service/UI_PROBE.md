# 短 G 维修 / F9 场景验证

实际首轮51项通过，Root发现中心目标提示遮玩家后返修；最新54项通过，三图玩家可见，新增实际投影与提示不重叠检查。入口 `res://tests_v3/candidates/canal_player_service/probe_player_service_ui.gd`，内限45s，建议 `dev.execute` 私有进程树外限60s。需要真实 Compatibility renderer，不能 `--headless`：

```python
dev.execute(['--rendering-method','gl_compatibility','--resolution','1280x720',
    '--script','res://tests_v3/candidates/canal_player_service/probe_player_service_ui.gd',
    '--','--capture-output=res://artifacts/v3/art/canal-player-service-<unique-time>'],
    'canal-player-service-ui-<unique-time>',60)
```

输出目录必须全新，位于 `artifacts/v3/art/` 下，以 `canal-player-service-` 开头；禁止覆盖。档案只使用唯一 `user://qa_v3/canal_service_ui_*`，由现 Repository/Store 导入原完整存档。`evidence/first_player_checkpoint_actual.json` 是此前57项完整玩家验证 `first_saved.json` 的原字节，SHA 90fa185b241fe2a8ce84c40bb2ad1ad047cbd53f62eb7f0ba70b4d6c3721e093。

真实场景恢复后，仅一次将玩家初始位置设为已测 `(3.5,2.8,5.4)` 并调整保持高度/相机跟随；不清速度、不改血量/部件/电池/能量或机关。随后通过正常 PilotInput QA 输入保持制动，发送真正 `Input.parse_input_event` 的 Tab/G/F9。此摆位不代表实际飞行路线。未重跑运输/工序，使用其已保存历史。

检查原95.68生命的实际 `min(25,缺量)` 维修、原账credit1→0/consumed1、generation1→2、部件/装甲/电池不补满；F9销毁旧 scene，实际新树ready/adopt，正常宿主至少5秒无新pending/重复工序/信用，重复G拒绝且generation不增。等待最多沿用生产20秒，失败保留现场状态，不临时摆正或清速。

生成三张1280×720原Framebuffer图：`01-before-service.png`、`02-after-service.png`、`03-restored-five-seconds.png`。不冻结宿主、不手调HUD文字/刷新，不隐藏碰撞或另造场景。`state_checks.json` 留真实状态、图SHA、相机、GPU、可见Label的rect/minsize/文字/祖先裁切；文字边界可机械判断，实际可读性留Root逐图审查。`inputs_before/after.json` 覆盖已有测试依赖路径及当前实际Scene的res引用闭包、导入remap缓存；输入变动、写图/写JSON失败或引擎错误均非零退出。


首轮 `canal-player-service-ui-20261020_055126_4029c2`：51/51，29.016s，0错误/残留，224 wrapper输入及331探针输入不变。18个Label边界通过但中心标签挡住真正玩家，底部白机是受益机；原图保留。修正后 `canal-player-service-label-20261020_055635_656dba`：54/54，PID43640、24.375s、0错误/残留，增加三次真实玩家投影避让检查。Root实看新三图，玩家清楚、标签靠右；G实际恢复4.32HP、F9后5.2667秒正常宿主继续且重复G不增消费/工序/代数。详见 `docs/v3/planning/I2_CANAL_PLAYER_SERVICE.md`。不代表MAIN、真人或整区美术通过。

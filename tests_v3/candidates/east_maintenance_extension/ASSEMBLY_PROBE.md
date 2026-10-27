# 东维护湾装配探针

当前结论（2026-10-20）：候选的三张真实 MAIN 图已由主线程逐张查看，单件分区、五孔和北缝可进入正式装配；外围整体地形仍未通过美术验收。修正 QA 的原始数组采样后，`20261020_031552_27f491` 无新图复测 **95/95**，PID31028 / 9.031 s / 自然 exit0，零引擎错误、警告与残留，299 项输入哈希不变。三张图来自保留的首轮 `030416`，不是本次 headless 结果。

**当前 World 已自动装配正式模型。以下 `capture_assembly.gd / run_assembly.py` 是历史候选安装探针，不能直接在新 World 重放，否则会重复安装。** 新生产检查另用 `capture_production.gd / run_production.py`，只读 World 自动装配结果。正式证据为首轮真实 MAIN **110/111 与两图**，加修正实例边界后的独立实际 World **8/8 身份复测**；不是一次完整重跑全过。唯一原失败已证为 QA 将作者嵌套同名根误当第二实例，不需改生产或模型。

正式入口：`python -B tests_v3/candidates/east_maintenance_extension/run_production.py --run`。默认无 `--run` 只校验路径/SHA，不启动引擎。一次导入最多 25 秒、两图捕获使用剩余时间，私有进程树合计硬上限 60 秒。新档为 `qa_visual_clinic_east_maintenance_production_*`，新证据为 `evidence/production-run-*` 与 `evidence/production-*`。它读取 `world.east_maintenance_art`，不调用安装函数、不生成替代物理；复用已冻结候选辅助函数的原始数组、孔缝、相机读回。历史候选 helper 的旧 Installer 仅是静态依赖，不加载其 GLB 作证明；正式资源路径、实际 live mesh 来源、PBR 和同 SHA 均独立核对。

生产基线来自当前东护岸实际保留的 `geometry.dry_surface`，因此面积比较不会重建/重装西岸。Ground 与 Clinic 原 fixed-body 身份、原 Terrain 精确 collision faces、全世界 PhysicsServer 位姿、四设施机制与历史均检查，两个冻结相机只推进显示。新图仅默认 26 m 与北接缝常规 zoom3。

正式首轮 `20261020_032556_ce4efd`：导入 PID39800 / 6.969 s / exit0，MAIN GPU PID34936 / 15.093 s / 自然 exit1，总 22.078 s、零残留；110/111、两张 720p 图、零错误/警告、301 输入 SHA 不变。实际导入和 PBR、97.544988 m² 扣面、五孔/北缝、628 体 PhysicsServer 位姿与 Ground 精确 collision faces 全通过。原始源副本与两图/日志索引保存在 `evidence/production-first-20261020_032556_ce4efd-source/manifest.json`（SHA256 `77d0b4c02ad6acb5529c8bb97daeaa52b5a6ba2b6d96173f3fd79e44fe5fbd12`），报告 SHA256 `4a980260875b0082a3d464facb79414011b0f3ae57007b7a5782a19f17a99217`。两图已实际查看，单件未见新孔缝问题；外围地形仍不代表整体美术通过。

原唯一失败将 parent/name/scene_file_path/model_path/递归同名数量/candidateabsence 混在一个布尔。现改为逐字段 actual.details，单次安装按 wrapper **直接子节点与 assembly.model 身份**核对；递归同名节点只作为作者层级元数据。短入口 `python -B tests_v3/candidates/east_maintenance_extension/run_production.py --identity-only --run` 使用既有导入、真实 `World.build(I2)`，上限 15 秒，无 Session/Store/网络/新图，不调用第二次 installer。

身份复测 `20261020_033136_234abe` 实际 **8/8**：PID29480 / 3.953 s / 自然 exit0，零错误、警告、超时、残留，驱动记录的 9 项相关源输入前后 SHA 相同。真实 wrapper 下仅 **1** 个直接正式 GLB 实例且就是 `assembly.model`；parent/name/scene_file_path/model_path/candidateabsence 均符合原意图。递归同名数为 **2**，路径分别为 `…/EastMaintenanceExtension` 与其子 `…/EastMaintenanceExtension/EastMaintenanceExtension`；后者 `scene_file_path` 为空，是 GLB 作者根。正式 scene_file_path 的实测值确实为 `res://assets/v3/i2_east_maintenance_extension/east_maintenance_extension.glb`，不是导入缓存路径。完整字段在 `evidence/production-identity-20261020_033136_234abe/identity.json`，SHA256 `eb52d2aa82a01cc3c932c4c61a63289b09b5f7c0fdafc6436cdd93f17c775a19`。首轮两张图和 301 项完整输入记录仍原字节保留，本次不重拍、不重写旧报告。

最小归档建议：完整保留 `asset_sources/v3/i2_east_maintenance_extension`，排除 `.blend1`、`__pycache__`、`.pyc`；本次新增归档属性文件之前的实数为 **209 文件 / 45,268,740 B**。包括 P1 原源、北接缝可见性失败与修正、delivery_p1 低密度失败、delivery_p2 全部清理/UV/checkpoint/PBR/GLB/同字节回导与日志，不再挑掉失败证据。另保留本探针目录的源码、UID、说明和完整 evidence（含首轮三图、两次诊断、已冻结源码副本与清单）。交付清单引用的 33 项外部作者输入保留现仓库原字节；若单独外发作者源，按 `delivery_p2/delivery_manifest.json` 的精确依赖复制，不整库复制模型。

正式 GLB、`.import` 描述、安装模块、World 接线和资产卡由主线程单独随集成提交保全；不必归档 `.godot` 缓存。源与 evidence 的 `.gitattributes` 均设 `* -text`，防止 Git 换行转换改变已冻结 SHA。全源保留不等于这些历史失败均通过。

入口：`python -B tests_v3/candidates/east_maintenance_extension/run_assembly.py --run`。
不带 `--run` 只验证路径、锁定 GLB SHA 和配置，不启动引擎。实际执行须由主线程分配独占窗口；导入最多 35 秒，随后捕获使用 120 秒总预算的余量。沿用 `scripts_tools/v3/dev.py` 的私有 Windows Job，合并原始 stdout/stderr，拒绝引擎 ERROR、非零退出和残留子进程。不启动网络。

探针继承现有 `capture_clinic_integrated.gd` 的 MAIN、原灯光、FlightCamera、HUD 和清理工具。全新 `qa_visual_clinic_east_maintenance_*` 档以明确的旧七行动 27 项 Director 事件夹具解锁 I2，再走真实地区切换。此历史夹具与三处冻结观察位置不代表真人通关或飞行路线。

安装前记录原 Waterfront 定义/几何/碰撞、全部现有物理体及 shape 数据、四设施机制/历史/目标、原北铺面及东西护岸。调用主线程候选 `Installer.install(world.waterfront_install)` 后检查：

- 当前可见东岸余面独立多边形面积扣除 97.545 m²；五孔从生产桥脚的实际 BoxShape 推导，合计 1.16 m²，孔内原地面保留。
- 非替换区域及原北铺面/两岸模型身份保持；Ground shape/RID/字节和全部设施 PhysicsServer 位姿保持；空输入及重复安装拒绝无部分安装。
- 实际 Godot 导入资源为 2 mesh、2 surface、2 PBR 材质、16,724 三角，地面 2K/检修件 1K，世界包络 X16.9..24.5、Y−0.18..0、Z2..15.6。
- 实际导入三角验证五个贯穿孔、北 Z2 接缝及蓝检修带、东岸顶条收边；3 m 净通路的物理射线仍首先命中原 Ground。
- 1280×720 的默认 26 m 视角、三档近景、北接缝共三图；捕获期间机制不推进，收尾后输入 SHA 不变，零引擎错误。

输出仅在本目录 `evidence/run-*` 与 `evidence/capture-*`。运行报告含各项真实测量、PNG SHA、镜头/摆位、资源来源、原始进程结果和完整输入前后哈希。三角点采样补充面积与身份检查，不是所有表面连续接触的穷尽证明；此候选也不代表性能、联机、人体舒适度或地区最终美术验收。

首轮实际批次 `20261020_030416_730ad8`：导入 PID44812 / 10.656 s / exit0；捕获 PID14740 / 15.313 s / exit1；总 25.985 s、0 残留，三张 720p 图均落盘，零引擎错误/警告。110/111 项通过，唯一失败为原复合的 finite / winding / metricUV 检查；不得称此轮全部通过。真实扣面 97.54499550978653 m²，五孔/原碰撞/四设施/接缝/实际导入检查通过，299 项输入前后 SHA 一致。三图已实际查看，新增东湾铺装可读，外围大面灰盒仍在。

原脚本、运行器、说明、UID、只读安装模块副本保存在 `evidence/first-run-20261020_030416_730ad8-source`；原始日志/JSON/图仍保持首轮目录原字节。该清单 SHA256 为 `a91548d2955986bfe9aef793c1af6fb3c43400a79a580d2ad4d93ca244dd5de8`。

后续仅诊断入口：`python -B tests_v3/candidates/east_maintenance_extension/run_assembly.py --diagnose-only --run`。它使用已导入资源、全新 QA 档和实际 MAIN，单 headless 进程树最多 40 秒，不重新导入、不拍新图。原复合断言拆成三个原阈值检查；同时记录**安装前原有两岸余面**和安装后余面的 face/vertex/index 对应关系、surface format、全部失败计数、最大 UV 误差、最小 cross²、最大 cross·normal、最多前 32 个失败明细及最大误差点。没有修改原判据或安装模块。

判据来源核对：有限性与 clockwise 的 `cross² > 1e-14`、`cross·normal < 0` 与生产 Partition 一致；理论 `UV = worldXZ × .25` 源于 Terrain 的 `_tri`。`1e-5` 是探针选择的读回误差界，不根据猜测放宽。

短诊断 `20261020_031103_5216ff` 已实际运行：PID304，9.359 s，自然 exit1，93/95 项通过；0 图、0 错误/警告、0 残留，299 项输入未变。原 `get_faces` 口径下 finite 前后均通过；winding 基线 4 项、安装后 5 项，最小 cross²=0；metricUV 前后相同两点，最大差均 `1.0967254638671875e-5`。原脚本及诊断证据索引另存 `evidence/diagnostic-20261020_031103_5216ff-source`，清单 SHA256 `3c648ce84dcc3853466b6cda70d1f616c047b1810a9d04fd1662b9c6c1806578`。

查明 QA 数据源问题：[确切 Godot 4.7.2 的 Mesh::get_faces](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/mesh.cpp) 调用三角缓存，而 [TriangleMesh::create](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/triangle_mesh.cpp#L127) 将位置 `snappedf(0.0001)` 后存入缓存。因此不能把这个取整位置与原 surface UV/normal 角点当成同一渲染属性配对。已按主线程授权**只修 QA**：从 `surface_get_arrays` 取真实 `ARRAY_VERTEX`，按同一 `ARRAY_INDEX`（空时依顺序）展开 position/normal/UV；几何面积与接缝采样也取实际 surface 顶点。原 finite / cross² / winding / `1e-5` UV 判据全部不变，不删除或移动任何实际面。`get_faces` 的差异与失败数量仍单独记为辅助缓存诊断，并列取整前后失败三角。

修正后实际复测 `20261020_031552_27f491`：扣面前/后最小 cross² 分别 `1.0513756532049001e-11` / `6.963318810448982e-13`，均高于原 `1e-14`；最大 UV 误差分别 0 / `1.7881393432617188e-7`，低于原 `1e-5`；finite/winding/metricUV 所有失败计数为 0。实际扣面 `97.54498803149909 m²`。此前缓存坍缩的三角 30，原始渲染面积为 `4.172325134277344e-7 m²`，真实面无需修改。报告位于 `evidence/diagnose-20261020_031552_27f491/state_checks.json`，SHA256 `1b73ade4ae8d3549820ffb7fe4457e39d662baa68476353e7ed4c3b45b58b406`；原失败保留。

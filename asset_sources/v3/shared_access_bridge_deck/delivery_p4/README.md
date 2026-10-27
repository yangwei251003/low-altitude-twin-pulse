# P4 原生 PBR / 12 件 GLB 交付准备

**实际更新（2026-10-19）：**原生三通道烘焙、12件显式GLB原始读回和同字节回导斜视已完成，源几何不变。[交付结果](REVIEW.md)记录两个懒加载检查失败、成功检查点与全部边界。GLB SHA `ea8aa0e10f35a637c7deef341471de771e364d9db938f502bd387cb41b9a7c28`，4,442,516B。仅本源目录交付，未自行写运行资产。最终美术、游戏镜头、运行物理/淡出仍未验收。原P4文件完全保留。下文保留准备合同；静态预期与真实raw报告有明确区分。

## 最小变化与复用

采用仓库 `clinic_pump_shell/delivery_v8` 已运行的原生流程：evaluated 三角→显式源 UV/角点属性副本→独占 DeliveryBakeUV→EMIT 底色/ORM 与 TANGENT Normal→按原组拆回→显式 GLB→二进制与同字节回导。没有光照/AO烘焙，没有下载或新增渲染器。

只有短端 UV 修补：BridgeDeck 与护板的 BlueSteel X 面从退化 X/Y 投影改为 Z/Y 投影，保留原图安静区与相同米制比例。原几何/角点法线指纹必须完全相同，记录逐面 UV 前后值；主体材质图不重建。新可编辑副本保留 12 件与原 modifiers，原 P4 `.blend` 不覆盖。

源 UV `SurfaceUV / SourceXZ / SourceY / PaintPanelUV` 与 `WeatherUse` CORNER 使用 `preserve_all_data_layers=True`，完整复制到实际三角，新增图集之后再次核对旧角点内容完全相同。源着色器全部按名读取显式 UV，不跟随活动 BakeUV 误采样。最终导出只留唯一 `SurfaceUV`，切线法线以该图集为基底。

## 导出合同与预算

精确静态合同在 [prepared_contract.json](prepared_contract.json)。其字段是预期，真实 GLB 后另以 `raw_glb_report.json` 记录节点 local/root 矩阵、accessor 局部 bounds、逐件三角、图像原字节 SHA，不能把预期冒充实际。

- 根 `SharedBridgeDeck` identity；子 `MovingDeck` 与 `LockPin` identity。
- MovingDeck：WestCarriage / EastCarriage 各1012tri；BridgeDeck 4524；NorthGuard / SouthGuard 各1284；BridgeHandle 308；PinBracketLeft / Right / Front / Back 各108。
- LockPin：LockRod 188tri、LockGrip 868tri。缩回位置 identity，实际插入沿 Godot -Y 0.3m。
- 12 Mesh、10,912tri，旋转 identity、scale1；**各 Mesh 的局部 center translation 保留，不能当成全部 identity。** 根原点 world(15,5,0)。完整精确 center / parent / local bounds 见 JSON。
- GroundOrigin 归总根；ManualHandleAnchor / WestTrackAnchor / EastTrackAnchor 归 MovingDeck；LockGripAnchor 归 LockPin。
- 单个 `SharedBridgeDeck_PBR`，12 个材质面。共同 2048² `SharedBridgeDeck_BaseColor.png`（sRGB）、`SharedBridgeDeck_ORM.png`（Non-Color，R=1/G=roughness/B=metallic）、`SharedBridgeDeck_Normal.png`（Non-Color，tangent +Y）。三张纹理均在 `textures/`，GLB 内嵌同字节 PNG。
- 未压缩 RGBA8 含完整 mip 三纹理约64MiB上界；实际导入压缩/驻留/性能未测。12surface不是实测帧drawcalls，不能假称只12次绘制。
- 无新碰撞导出。根保留原12body与隐藏Visual合同，能力靶/BridgeHandle/LockRod/Grip不淡出。局部装配为 `Transform(ORIGIN-layout spec.center)*authored`，authored 是模型根至该 mesh 的累计变换，不能再减已移动 body.position。

文件先只输出本目录 `shared_access_bridge_deck.glb`，不自行写 `assets/`。根未来复制确切同字节至运行路径；本脚本不推进生产集成。

## 授权运行入口

默认命令只显示准备项，不开引擎：

```powershell
python asset_sources/v3/shared_access_bridge_deck/delivery_p4/run_delivery.py
```

取得 root 窗口后：

```powershell
python asset_sources/v3/shared_access_bridge_deck/delivery_p4/run_delivery.py --run
```

顺序 bake→export→preview，CPU2、整个调用240秒，真实PID/完整stdout/stderr/退出信息在唯一run目录。可用 `--stage bake|export|preview` 单独执行已有前序的后续阶段；拒绝覆盖已有产物，失败必须保留再定位，不自动反复重跑。本次root只授权一张GLB回导斜视，沿P4相同01机位/光照/16samples/1400×1050，源三图已另行保留。

正式运行后必须实际看图确认2048图集没有把源细节压糊、无端面条纹/错误法线；当前准备不构成其通过证明。

# 普通临水作业铺装 V2：共享 GLB 交付

状态：**READY_FOR_ROOT_IMPORT**。2026-10-19，本轮 Blender 5.2.1 CPU2，PID 9836，自有进程树 180 秒上限，实际 3.11 秒自然退出 0；没有渲染、重新烘焙或启动 Godot。主线程已亲看并接受两张源接缝图，当前交付并不代表六块院落已完成实际游戏验收。

## 可直接导入的合同

交付 `clinic_ground_plain_v2.glb`，9,318,196 字节，SHA256：
`5356769cdcf540dc0b59f5f0ad94801df047eba4acf6945894a7833f4a80cc3f`。

根 `ClinicGroundPlainVariants` 的三个直接子树是互斥的变体，加载后必须只选用所需子树，不能把三件重合显示。整个 GLB、三个变体根及六个 mesh 的本地变换全部 identity，没有相机、灯、动画、水体或碰撞。

| 子树 | 子网格 | 三角数 |
|---|---|---:|
| PlainA | A_Concrete / A_Sealant | 596 + 84 = 680 |
| PlainB | B_Concrete / B_Sealant | 656 + 84 = 740 |
| PlainP2West | P2_W_Concrete / P2_W_Sealant | 596 + 84 = 680 |

每变体以 6×6m 地面的中心为原点，Godot 坐标边界 `[-3,-0.18000000715255737,-3]..[3,0,3]`。板顶 Y0，密封胶顶 Y−0.01199999917。每个变体的 15 个编辑件仅在导出临时副本中合为 2 mesh；编辑源 45 件完全保留。整个文件 2100 三角、6 surfaces、共享 1 个 `CGround_BakedPBR` 材质。

## PBR 和源数据

标准 OPAQUE Principled PBR，保留源双面设置，无自发光或 unlit。唯一 UV 层为 `SurfaceUV`，显式导出 `TEXCOORD_0`。四张既有 2048 图直接复用：BaseColor 为 sRGB，Roughness / Metallic / Normal 为 Non-Color；原生 glTF exporter 把粗糙度与金属度打包为 G/B，最终只有 3 张共享内嵌 PNG。BaseColor 和 Normal 的内嵌字节等于 P2 原文件，MR 字节也与 P2 冻结 GLB 的原生打包结果相同。没有增加源分辨率、改像素或重新烘焙。

编辑源：`../plain_v2/clinic_ground_plain_v2.blend`，SHA256 `02ce8caa0abf3e044d1a4e7681c84864acecc7fcb69bb54c90a6e5ad7d67e198`。贴图仍位于 `../p2/textures/`。源目录早期 README 的 PREPARED_NOT_RUN 是准备时记录，本轮不追改冻结旧文件；实际运行状态以其 `evidence/production_report.json`、`process.json` 和本目录读回报告为准。

`frozen_inputs_before.json` 记录 P2 / delivery_p2 / plain_v1 / plain_v2 的所有原有文件；导出结束及交付自检再次逐字节核对，未保存编辑源，未改旧脚本、贴图、图片或运行 assets。

## 六块院落的接缝

普通 A/B 四边各承担 10mm 密封胶。PlainP2West 只有 local −X 承担 20mm，因为冻结 P2 的外边没有半缝；其余三边仍 10mm。不要把这条 20mm 边接到普通半缝边，否则会产生 30mm。

拟摆位 X/Z：P2(−19,15)、PlainP2West(−13,15)、PlainB(−7,15)；第二行 PlainP2West(−19,21) 绕 Godot Y **−90°**、PlainB(−13,21)、PlainA(−7,21)。−90° 将 local −X 映到 world −Z，所以第二行西块的全缝恰好朝向 P2 的北边。原始 GLB Sealant 三角回读得出的 7 条内部边中，2 条是 0+20mm，5 条是 10+10mm；均在 float32 误差内为 20mm，没有 30mm。

完整数值见 `adjacency_report.json`。这项验证只包含真实导出几何及拟定刚性摆位，不代替 Godot 实际组合/飞行检查；院落外周如何接既有地面仍归主线程。原 4mm 倒角让近景的坡面加密封胶可见总宽约 28mm，内部缝也相同，不将其误报为纯胶体 20mm。

## 证据与局限

`delivery_report.json`：54/54 检查通过。六个 mesh 分别核对有向 float32 三角多重集、逐角 UV0（含 glTF V 翻转）、图元数、边界、身份变换、材质/内嵌图、禁止导出对象和原件字节。检查保留所有原三角，不以消重或容差放宽代替匹配。

源两张图亲看结果：普通相邻缝与内部缝的视觉权重一致；与 P2 相接的全缝也清楚，板面保持安静，无新增随机污点。尚未验证六块在实际默认镜头的整体重复感、外缘收口、远景密封胶与倒角可见性、真实 GPU/性能或全区美术。保持既有 Y0 保守 Ground 碰撞：细缝和排水槽不是可掉入的物理排水网，不能叠在未切除的旧地面可见面上。

导出日志如实保留了 glTF “multiple shader image nodes / first sampler” 提示，这是原生合并粗糙度与金属度时产生；实际 sampler/纹理角色由二进制自检记录。另有安装的 BlenderMCP 后台启动提示和 Blender 6.0 `Material.use_nodes` 弃用提示，未调用该 MCP、未安装或修改插件，进程实际退出 0。

复现入口为 `python run_export.py`，只允许在新的证据目录或明确归档旧输出后执行；当前 runner 拒绝覆盖原日志/GLB。本轮产物已冻结，后续不自行重导或重烘。

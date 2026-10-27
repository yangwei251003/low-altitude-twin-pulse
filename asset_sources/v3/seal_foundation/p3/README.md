# 南闸基座 P3：单岩上肩重雕首轮，失败证据

2026-10-18。**本轮自审退回，13/16 数值项通过不等于资产通过。没有 PBR、没有 GLB、没有运行集成。** 只写本目录；P1/P2、批准参考、CC0 原件、封印闸 P3、世界运行数据均保持只读。

## 坐标与有意改形

- 模型 Godot local 原点对应 world `(6,-3.2,26)`，Blender 坐标为 `(local.x,-local.z,local.y)`。底面 local Y0 = world Y−3.2，水位 local Y1 = world Y−2.2。
- 原生 Boulder01 LOD3 的长/中/薄主轴置于 Godot Z/Y/X，等比至 9m 长；初始最大厚度约 4.49755m。保留隐藏原生对象及来源哈希。
- 首先按真实截面对端部做单调 X 拓宽，随后局部细分上部边，实施竖向连续映射：梁下接触带目标 local Y5.69（与梁底交埋约4cm），向完整岩肩逐渐消退。**这是有意重雕，不是保持原始扫描比例。**
- 最大实际局部抬升 **3.02705m**，最大下移约0.25034m；细分后13,254顶点中9,623个移动超过1mm。虽然逐列映射的解析竖向导数最小为0.90718，真实离散三角仍出现自交，故不能用该导数替代最终几何验收。
- 独立神殿承梁整体 1.3×7.3×0.45m，顶 world Y2.9、底 Y2.45；中央1×7m保持平顶，侧面和端头有浅缺口/斜角。没有把梁加厚填补岩体空隙。
- 没有复制三块岩体，没有全体 voxel，没有改运行基座或水面。

## 原始结果与失败

`form_report.json` 未修改判定。共26,698三角，主体与承梁各为一个闭合正体积组件，0开边、0非流形边。**闭合并不代表没有自交。**

三项失败：

1. `SculptedNaturalBody_no_detected_self_intersections`：至少30对非相邻三角自交；检查在30对截断，因此不能写成仅30对。索引与候选审计保留于原始报告。
2. `beam_bottom_full_1_3x7_3_inside_solid_rock_section`：真实梁底高度的岩体截面不能完整包住梁底矩形，出现多条碎截面和边界穿越。
3. `beam_bottom_dense_support`：1,125点中78点支撑不足。点坐标和实际岩面高度完整保留，不能用梁顶的通过结果替代梁底结果。

其他已验证项包括：冻结门实际36个最低顶点接触、中央名义1×7m梁顶采样、闭合实际水位截面、床面接触、门升程禁入区、枝桥实体区，以及 HX02 原低飞完整保守包络外加0.1m的静态三角/箱体检查。后者**仅是静态前置检查，没有启动 Godot，也不是机体运动验收**。

- 实际 world bounds：X `[3.75122285,8.24877715]`，Y `[-3.200000015,2.899999905]`，Z `[21.5,30.5]`。底部微小负偏差是浮点精度。
- 床面实际接触面积约 **0.48393m²**，水下岩体体积约 **3.55305m³**。与上部宽体相比，基础偏窄；这也是视觉承重感弱的依据，而非仅检查“触床”即通过美术。
- 实际水线相对当前东岸水边最小间距约 **2.24614m**。水线从真实岩体切出，没有沿用旧八角或AABB。其环与世界坐标在 `actual_water_section.json`。

## 已实际看三图的美术判断

**这一轮连续顶点映射方法退回，不继续调权重强拉同一上肩。**

- 三柱重复已经消失，但抬升把原有凹陷和三角延长成明显竖向薄折片、锯齿与不自然裂口；这是几何失败，不用材质掩盖。
- 主体仍偏高窄岩墙，外侧宽斜岩腹和稳定低部承托没有达到新版参考；底部接触过窄，视觉有悬托感。
- 承梁/关闭门的方向和接合位置可读，但承梁仍是基础形，未做最终手绘石材与磨损。
- `basic.png` 的自动取景未处理不对称投影中心，远端出画；保留原始失败图，**不能当完整单件全轮廓证据**。装配图能读出主体/门关系，但不补足该取景缺口。
- 近岸图只用真实坐标构造简化岸坡、水面和枝桥位置参照。桥块穿过关闭门表示现有通路被关门阻断的位置关系；不是新建最终桥美术，也不是在 Godot 中验证过的画面。

本轮完成首次三图后已停止，没有自动开展第二次造型或重渲。后续方法由 root 看图决定。

## 文件

- `seal_foundation_p3.blend`：editable 主体/承梁、隐藏原始扫描副本、原位门和近岸参照集合。
- `seal_foundation_p3_basic.png`：首次单件基础色图，远端出画的问题明确保留。
- `seal_foundation_p3_gate_assembly.png`：冻结 P3 门的关闭装配图。
- `seal_foundation_p3_near_shore_context.png`：简化真实位置背景图。
- `build_foundation_p3.py`、`build_p3.log`：唯一构造/三图过程；Blender 5.2.1、Cycles CPU 2线程、16 samples。
- `form_report.json`、`actual_water_section.json`：原始检查与截面。
- `manifest.json`、`selfcheck.json`：逐文件哈希与只读输入校验。校验字节一致不代表失败资产通过。

进程 PID **27636**，2026-10-18 09:01:32启动，约09:03:52结束，exit0，脚本记录138.511秒。所有渲染已结束。

源 `.blend` SHA256：`1bab1677b48686ebf435595057bf1c47a17da1269e64997994f394ec3d7d99cc`。

## 只读来源

项目根 `.`。

- 新批准参考：`references/v3/production/seal_foundation/seal_foundation_reference_v2.png`，SHA256 `1d1c0fedc0bb9b412af8a8caef60c32c00972e01c94a871ca11816f90e3967ab`。只取厚腹、斜破面与嵌梁关系，不复制其远端高柱或摄影细噪。
- [Boulder 01](https://polyhaven.com/a/boulder_01)，Rico Cilliers，原生 `asset_sources/v3/growth_approach/resource_recovery/boulder_01/boulder_01_1k.blend`，SHA256 `8f8004fb52ebd00c4702a50873ac799e7bd7a0bea3415f2d8bc9986e1c58e371`。按 [Poly Haven CC0](https://polyhaven.com/license) 修改；本轮无新下载。
- 真实门为 `assets/v3/candidates/rising_seal_p3/rising_seal_p3.glb`，SHA256 `e3103cb59810b3703b298450f9047e32bd85fa4e7940cd0188c0660703e8989b`。
- `docs/v3/SEAL_FOUNDATION_SPACE_AUDIT.md` 提供空间合同；近岸来自读取时的 `f1_shore_layout.json`，快照哈希保留于报告，运行数据未改。
- 固定斜视方向取 `scripts/v2/flight_camera.gd` 的 `(32,39,32)`；当前是离线棚拍照明，不是 Godot 灯光。

# P11 — 三块粗砾源材质 / 着色法线对照（仅静态准备）

本轮不改变 P10 的 144 件、7,456 三角、土面沟网、混凝土断面、石块摆位/埋深/数量或碰撞。P10 原源/两图/失败证据均只读。当前没有启动 Blender，没有烘焙/GLB/生产导入。

## 一次有因果分离的对照

加载 `p10/repair_01/editable_source.blend`，保持灯光与视角方向；局部相机统一对准三块原位石头，正交宽 1.25 m，1440×860 / 24 samples。A/B/C 共用此一个相机，其他 141 件完全不改。该近景只诊断材质，不能证明默认 26 m 可读性。

- A：P10 原材质 + 原逐面平着色。
- B：两块天然岸石采用现有 Rocky Trail 的 Diffuse / Roughness / NormalGL；FallenConcreteFragment_00 保留真实 P10 混凝土主材质，仅 15% 颗粒色/粗糙度贡献与少量颗粒法线；三者仍逐面平着色。
- C：保持 B 材质，三块面 smooth，并按相邻面真实 50° 角标记 sharp_edge，保留强转折；不细分、不移动顶点。角度是这次固定起始设置，不是审美验收门槛。

选择：FallenConcreteFragment_00（22.16 cm）、SedimentBankStone_047（12.44 cm）、SedimentBankStone_020（6.82 cm），实际位置/埋深沿用 `selected_stones.json`。三者有不同面密度与可见侧面，足以区分颜色与面着色的收益，不先整件铺开。

## 映射与材料

已亲看原 2048² Rocky Trail Diffuse，选择其中三处较大棕灰岩表面内部作为 UV 取样中心，避免故意把颗粒间黑缝贴成整石深洞。位置在 `stone_material.py:PATCHES` 明确列出。每面按主法向采用有符号米制平面投射，新增 `StoneSurfaceUV`，源幅宽 2 m；各源 UV 不删改。此为面投射尺度，不假称无失真展开。UV 接缝在实际图上需检查。

Diffuse sRGB 保留实际石面色变，饱和度仅 0.90、value 0.96，避免再把扫描图混回均色；原 Roughness Non-Color 限于 0.60–0.95；NormalGL Non-Color 接显式同名 UV 的 tangent NormalMap，初始 strength 0.60。不把色图转 height，不创建 displacement、深坑或新 AO 黑边。若取样块混入不属于单石的地面颗粒，应据实际图退回，不以已有来源名直接通过。

FallenConcreteFragment_00 是断板落块，不是天然岩。其材质从 ConcreteResidual_00 实际主材质复制，85% 原混凝土色/粗糙度保持、15% 岩面信息只表达骨料；原混凝土法线占80%，源 NormalGL strength .35 后仅20% 混入，仍无位移。后续画面若仍失去混凝土身份就退回，不能因材料名字保留而算通过。

资源均复用 `p10/vendor/polyhaven_rocky_trail` 原图，Amal Kumar / Poly Haven / CC0，未编辑像素、未增加资源。来源与文件 SHA 在 input_contract.json 和既有 vendor provenance 中保留。

## 检查与执行入口

脚本逐件核对 P10 的原顶点/面签名、所有 world transform 与总三角；B/C 仅三块材料/UV/法线允许变化。实际运行再核查 tangent 非退化、corner normal 与 sharp edge 数、所有源图 abspath/SHA/真实 pixel buffer；不删除 has_data 检查。最终仅保存 C 的可编辑研究源和三张原始 PNG，失败即停、保留日志。

待 root 串行窗口：

`python -B asset_sources/v3/clinic_ground_transition/p11/run_comparison.py`

预计 CPU2 约 120–180 秒，硬上限 240 秒仅自身进程树。此时只通过 Python AST 静态检查，尚未实际运行，API/取样画面不假称验证。

## 官方依据与访问边界

root 已阅读官方 shading / 4.1 建模资料。本轮直接打开这两页返回 402；官方站搜索正文可读，确认 4.1 后不再使用旧 `use_auto_smooth` 开关，而由 sharp / smooth 元素决定 split normals；API 4.5 正文包含 `Mesh.set_sharp_from_angle(angle=...)`。脚本在实际 Blender 5.2 运行时仍核查方法存在，没有以网页结论替代本机执行。

- https://developer.blender.org/docs/release_notes/4.1/modeling/
- https://docs.blender.org/api/4.5/bpy.types.Mesh.html
- https://docs.blender.org/manual/en/latest/modeling/meshes/editing/face/shading.html

Smooth 只改变着色法线；不能把它称为改进了碰撞或真实沟深。P10 的大面积泥面/沟底低频辨识问题保留为未解决项，本轮不借此扩大为沟网重塑。

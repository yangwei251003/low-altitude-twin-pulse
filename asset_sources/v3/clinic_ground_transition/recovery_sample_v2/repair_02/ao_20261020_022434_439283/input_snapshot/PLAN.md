# 局部边界裁切与旧 AO 身份诊断：静态准备

状态：未运行 Blender，未制作新图，未烘焙。仅 0.9 m 方法样，不是全件 P14，也不是运行资产。

输入为已冻结的 repair_01/bake_20261020_010927_047833/baked_repair.blend。其 Normal 同组隔离修复、侧面源 UV、真实起伏和原 AO 全部保留。输入逐文件 SHA/字节在 input_contract.json；两个入口均会前后核对。

## 1. 左前双层外壁：只裁已证明的覆盖

已知低模土侧三角 8700–8703，与混凝土 9073/9075/9076 在 X=-0.44999998807907104 共面；10 对正面积重叠合计 0.0011702737642292106 m²（11.7027 cm²）。这不是整个模型的全局重叠结论。

保留混凝土原面，用这三个实际三角的 YZ 半平面，确定性减去被覆盖的土侧面。high/low 使用同一真实混凝土遮盖范围；high 原有微小坐标差不会强行压平。若低模发现超出已知四个土侧三角的新重叠，停止报告，不扩大修改范围。

新顶点保留原三角重心对应：位置、所有 UV 层、角点颜色、分裂法线都由该面插值，原材质/绕序/平滑标记和边标记保留。相邻共享边增加对应分点，几何表面不移位。新文件保留原物件作隐藏来源，增加 BoundaryHighFull/BoundaryLowFull；不覆盖现有投射工具、源文件或纹理。

验证：原面面积=保留+遮盖；所有剔除片均由未改混凝土覆盖；同组高低删除投影面积一致；实际 float32 输出的剩余重叠与缺口量化；原范围、未受影响面的坐标/UV严格匹配；新角点位置/法线/UV误差有报告。新旧拓扑计数均报告，不把被遮盖的开放土壳边冒称为独立闭体。外表面覆盖检查针对“土侧+混凝土”的组合，不等于全局自交/碰撞验收。

运行候选（待 root 窗口）：

`python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_02/run_stage.py boundary`

预计 35–65 秒，CPU 2，私有进程树硬限 90 秒。输出局部可编辑 candidate blend、原三角/角点对应、覆盖/拓扑/图片路径报告；不 bake/render/export。失败保留当时可保存的现场与脚本快照。

## 2. 落块底部：只读 32 个旧暗点

沿用已冻结 boundary inspection 中 32 个 ground_top 暗点和其实际四邻纹理像素。重建原 LowFull 顶点法线偏移 35 mm 的 cage 射线，分别向完整 HighFull 与匹配 ground_top 投射；记录首命中原三角/组件/正背面/距离。核对原 Full 几何和 BakeUV 与当前修复源相同，以及源 AO 的 only_local、35 mm distance 与法线输入。

这是对旧 bake 射线的几何重建，**不是 Cycles 历史随机 AO 采样重放**。如果先命中落块底面，证据只说明源身份错投风险；若仍命中地面，则保留该事实，不为预设结论改 AO。没有删 Normal/AO、加亮或重烘焙操作。

运行诊断（待 root 窗口）：

`python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_02/run_stage.py ao`

预计 8–18 秒，CPU 2，硬限 60 秒；只读现有 blend/JSON，不保存模型，不渲染。

## 已做的非引擎检查

5 个 Python 入口/模块 AST 可解析。纯 Python 凸多边形差集检查通过，原三角重心插值和共边接触不丢面积。用已记录的真实低模坐标演算，删除总面积与原 10 对重叠差 1.3e-18 m²；这仅验证静态算式，不能替代 Blender 实际副本/边界验收。详见 static_check.json。

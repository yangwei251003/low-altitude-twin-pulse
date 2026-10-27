# P1 源制作准备（尚未运行）

Root 已实际审阅 V1 并批准源准备。入口仅生成可编辑 .blend、几何报告、源重开读回与一张近景；没有 GLB 导出、运行灯、碰撞或规则修改。

## 实际视向

`scripts/v2/flight_camera.gd:4` 的 OFFSET=(32,39,32)。从 +X/+Z 上方看向对象，水平45°、俯角约40.75°；`scripts/v3/twin_session.gd` 的 target_size=26。
P1 源近景采用同一相对方向，聚焦单件，显式不是26m默认游戏画面。Root 要求控制离线成本，只有一图；26m辨识、实际世界遮挡与运行温度三态留给后续MAIN候选。
石体上肩坡面 y=1.55-.18x-.30z，外法线 normalize(.18,1,.30)，核心位于(.28,1.4306,.23)附近。朝 +X/+Z 的上肩能同时被相机看到，避免核心仅放竖直背面。

## 编辑结构

- 一件厚实主石体，加四块宽肩/脚石；所有几何受原 X±1.5/Y0..2/Z±1 包络检查。主体凹槽为真实浅 Boolean 裁切，底部仍完整，不留可飞穿孔。
- 三条连续根，用连续运输截面与沿弧长 PaintUV，末端收进原范围；不另添碎根杆。
- 四块低矮苔面，减少概念里密集的苔碎块。
- `TemperatureCore` + `HeatInlays_1/2` 为独立具名 Mesh；材质 `FT_TemperatureCore` / `FT_HeatInlays` 分开，源均显示20的冷青。后续由 Root 映射真实 temperature，不含真灯/状态计算。
- 温度核心不具备轴动画，本地变换在交付阶段实际记录；模型根 `F1ThermalStone` 为底心 identity。
- 源石/根/苔复用已批准 F-B 的9张纹理字节副本，记录于 ../inputs/material_inputs.json。旧源文件零修改；新源节点降低石材饱和/值与法线强度，避免密白边。UV显式采样 PaintUV；不将概念图当PBR。
- STUDIO_NOT_EXPORTED 中仅有源审图灯/地面/相机，不属于模型，没有任何运行资源写入。

## 有界入口（仅 Root 交付唯一窗口后）

```
python asset_sources/v3/f1_thermal_stone/p1/run_source.py --run
```

不带 --run 只打印准备信息。运行复用既有 scripts_tools/v3/dev.py 私有 JobObject，隐藏 CPU2，整树硬240s；预计单张源图连构建/重开约30–90s，实数以结果为准。
每次唯一 runs/<timestamp_uuid>/，不覆盖历史；source.log、inputs_before/after.json、summary.json 保存完整过程/进程退出/残留/输入变化。失败不自动重跑。
输出 output/f1_thermal_stone_editable.blend、geometry.json、readback.json、shots.json、01-game-direction-close.png。
输出只在本资产目录；必须读回几何/UV有限、闭边、各对象正三角面积、原包络、无模型LIGHT、源重开完全一致。结构统计来自实际构建，现不预填面数。
源近景使用 Blender 实际 camera.view_frame 校准画面高度，避免将 sensor_fit 假设作为游戏相机证明；仍非Godot截图。

当前仅 Python AST 解析完成；Blender API、实际闭边/UV/材质与图像均待获准首跑。不得将静态准备写成美术或运行通过。


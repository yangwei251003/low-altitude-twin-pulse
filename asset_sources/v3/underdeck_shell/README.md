# I1 检修仓体 — v2 开发集成候选

这是一个单件仓体资产，包括真实连通廊道、侧窗、转向室和三根实心屋顶塔的视觉。不是完整海港、游戏截图或最终美术合格声明。

## 当前交付

- `underdeck_shell.blend`：413 个可编辑网格，保留各构件；导出只合并副本。
- `textures/UDS_SharedAtlas_*.png`：四张外部 2048×2048 原创 UV PBR 图，BaseColor、Roughness、Metallic、Tangent Normal。三个原材质绑定共享同一图集，GLB 内嵌对应图片。没有声称进行了高低模烘焙。
- `../../../assets/v3/underdeck_shell/underdeck_shell.glb`：实际运行文件由项目根下 `assets/v3/underdeck_shell/` 提供；本段相对路径仅说明结构，不作为交付链接。
- `evidence/build_report.json`、`surface_partition.json`：原布局碰撞重放、每个基础原面与可见分割的映射。
- `evidence/glb_report.json`：直接解析原始 GLB；75 项通过，包含每个原矩形面积覆盖、逐对正面积重叠排除、98 条真实网格通道射线、三材质/PBR/UV/identity 层级。
- `evidence/reimport_report.json` 与 `underdeck_shell_glb_*.png`：从可编辑源取得评估几何后删除源对象，再导入同一个真实 GLB，进行双向顶点与三角数比较及离线渲染。渲染是否完成以报告字段为准。

## 几何接口

GLB 根 `UnderdeckShellArt`，所有本地变换 identity。Godot 模型原点置世界 `(-35,0,-27)`。主仓身 X/Z±8.5、Y0..6，三塔底 Y6、顶 Y11.6、实心截面3×3。浅饰面最多外浮6mm；实际最终边界见二进制报告。

```text
UnderdeckShellArt
  PermanentNavigation
    NavigationSurface       # 254 triangles / 2 surfaces
  OccludingCover
    CoverSurface            # 1030 triangles / 3 surfaces
    CoverDetails            # 6828 triangles / 2 surfaces
    RoofSupports            # 8760 triangles / 1 surface
```

共 16,872 三角、4 个 runtime meshes、8 surfaces、3 materials。`PermanentNavigation` 有导出 extras 提示 `terrain_visibility_keep=true`，根包装仍须显式设置 Godot metadata，不能只假设 glTF extras 自动等同该行为。

根已计划把两个基础表面移动到原 `PermanentNavigation/Surface`、`OccludingCover/Surface`；细节和三塔放到遮挡组。旧柱只隐藏视觉，保持其既有实体。源模型没有碰撞/灯光/相机导出，不会替换生产状态机、真实门或固定轨。

原碰撞 696 三角 SHA256 `8a9138bcf652ba71777aa89ec89bff8b790068b6e0c5b570c252560d51ee6473`。可见基础面由于低墙脚分界及米制 UV 细分为 1,284 三角；这不改变原碰撞。不能把本地射线检查称作完整机体扫掠。

## 有效性和已知差距

1. v1 两图已实际查看并退回：模型下缘裁切、青钢偏黑、整体过新、屋顶重复波浪裂纹。原源/纹理/GLB/报告/图保全在 `evidence/rejected_v1/`，不是有效验收结果。
2. 初始 v1 数值运行在 NumPy float32 JSON 序列化失败，exit17。修正为 Python float 后同构形完成；失败日志保留。v2 修改了相机取景、色阶/风化、屋顶边缘纹理，并错开框架/接板/紧固头的共面表面。
3. v2 正反图已实际查看；根允许进入 Godot 真实默认镜头检查。剩余差距：较批准参考干净；顶帽没有参考的抬高格栅；柱脚包板层次较薄。不能用通过项数量掩盖这些差别。
4. 参考图门洞偏宽、三塔偏矮，按已验证尺寸纠正；未照搬额外伸出基座/栏杆。外表百叶是实心塔的表面结构，不是玩家可穿过的孔。
5. `navigation_study` 图只是在 Blender 隐藏遮挡组，明确是离线拆分研究，不是游戏淡出结果。Godot 光照、真实滑门组合、淡出、飞行和性能均由根后续验证。

## 复现

使用现有 Blender 5.2.1 LTS，后台、factory startup、CPU 2 threads、Python exit code 17；运行 `build_underdeck_shell.py` 会重建本资产自身源/贴图/GLB及两张源图。运行 `inspect_glb.py` 只读当前 GLB，写本资产报告。`verify_and_render.py` 只读源/GLB，生成回导报告及三张离线图，不写运行资源。

不要为复现运行全项目 Godot 导入，也不要与根的实际 GPU/性能窗口并行。此交付不需要新软件。

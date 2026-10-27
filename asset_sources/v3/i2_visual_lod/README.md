# I2 装饰低模候选：一次有界生成

只处理现有护岸长/短件、护岸闭合段、东侧检修扩展、检修坑，共 5 个 GLB、4 类装饰。
冻结输入为 `manifest.json` 的源路径与 SHA256。5 份源共 74,810 tri；按现有场地实例数为 101,742 tri。
风格、纹理、材质槽、节点层级与局部变换沿用原件，不重绘、不烘焙、不渲染。

仅主 Agent 在独占 Blender 窗口执行，项目根下入口：

```powershell
& 'C:/Program Files/Python312/python.exe' asset_sources/v3/i2_visual_lod/run_candidates.py
```

预计 30–90 秒，整个 Blender 私有 Job 硬界 180 秒（可用 `--timeout`，最高 240）。
不自行启动 Godot；不枚举、终止或占用其他进程。单件可用 `--asset revetment_4m`、
`revetment_1p3`、`revetment_closure`、`east_maintenance` 或 `inspection_pit`。

## 几何策略与取消门

- 只进行一次 0.5° 共面简化，再按需要进行一次 Collapse，常规目标保留 35% tri。
- 不做仅按位置的全局焊点。glTF 导入只合并法线兼容的重合顶点，避免把检修板/格栅的相交部件焊为一体。
- 共面简化保留材质、UV、锐边、接缝与开放边界。闭合段含裁切开的边和端帽，必须保持各材质面边界。
- 检修坑的 Hardware 占 13,880/19,640 tri，目标保留 22%；坡道/地板和混凝土墙保留 75%，优先保住主要通行轮廓。
- 最终每件最多保留 40% tri；材质面数量或原材质槽变化即取消。每个原材质面的 min/max 偏差不超过 2 mm。
- 原/新顶点和三角形中心互查最近表面，样本距离不超过 2 cm。此为候选过滤，不能替代主要轮廓的固定镜头检查。
- 任一失败取消该件并记录具体原因；不循环调参、不改材质、不继续渲染。部分取消时 runner 退出码为 2，已通过件仍留存。

## 原 GLB 保留与产物

Blender 仅导出临时几何。脚本把它回填到原 GLB，原 nodes/scenes/变换、materials/textures/images/samplers
的 JSON 值及原贴图 BIN 字节不变。原几何字节暂留为未引用数据，因此候选文件大小可能增加；不能按文件大小判断减面收益。

- `runs/<tag>/result.json`：逐件接受/取消原因、mesh/surface/tri/material 精确 contract、完整源/新节点与变换、逐材质面 min/max 原值与偏差、距离采样。
- `runs/<tag>/*_editable.blend`：简化后的可编辑源，贴图打包；原 canonical GLB 和历史 blend 从未写入。
- `runs/<tag>/runner.json` 与 `blender.log`：硬界、原 GLB 前后 SHA、所属进程残留。
- `assets/v3/environment/i2_visual_lod/<tag>/*_lod.glb`：独立候选，未接生产。只以 result 中通过的产物为有效交付。

主 Agent 后续只为选中候选接入其**精确新 contract**，不放宽旧检查。
生产碰撞继续使用原 layout 与原 GLB-derived shape 的原值，不能改用低模生成碰撞。
需要默认固定镜头短图、原碰撞精确比较与同场景实际包性能对照后，才能决定是否采用。

当前仅完成静态准备，未运行 Blender、未验证候选画面或性能。

# 西短引桥 p2：基础色装配审查候选，暂冻

仅本目录新写。`west_p1`、生产 JSON、运行资产、核心和测试脚本均未改动。此版从 p1 可编辑 `.blend` 读取后定向修改；不是重新生成的孤立资产，也没有最终 UV/PBR 或运行接线。

## 观察与改动

已实际查看根代理的游戏装配图 `artifacts/v3/art/20261018_061744_west_p1_assembly/02-candidate-west-join.png`、`03-candidate-lower-rock-root.png`、`04-candidate-grown-join.png`，并重看批准的 v2 单件参考。p1 的问题是可见侧平行尖唇、横板式层叠，以及根被岩体遮成顶部碎段。

- 保留四块原可编辑厚岩。只对自由侧沿下雕、退让及斜切，各岩层采用不同切面；不把全部顶面锁死。保西接口五点、正式桥唇、下切鼻端、八锚点和中央承载带。为了避免三角插值降低 Z±0.85 通行带，保留其相邻原 Z±1 顶面顶点行。
- 正 Z 主根使用 p1 中留存的天然叉源重新摆位，三轴统一 1.10 尺度，sourceY 沿立面向下，sourceZ 保留分叉展开，sourceX 保留原截面厚度；逐 sourceY 截面的 Z 平移保留厚度。侧岩局部让出空间，避免再次只露几段树皮。
- p1 被替换的南根原几何副本仍在新 blend 的隐藏集合 `P1_EDITABLE_PART_COPY_NOT_EXPORTED` 中；天然原始源也仍保留。北根、基本材质和八锚点沿用 p1。

来源为冻结 p1 内的 Poly Haven Island Tree 01 树基/粗叉副本，CC0，原出处 <https://polyhaven.com/a/island_tree_01>；不能称作裸根扫描或无形变扫描。原始自然源及权属说明仍可追到 `shore_root/p9` 与 p1 卡。单图不可见背面、内部及精确尺寸不由图片推测恢复，尺寸只取现有 JSON。

## 装配接口

- `GrowthApproachWest` 单位根变换，Godot 本地原点 `(0,0,0)`，世界摆位 `(-14.5,0,25)`，不得额外旋转或缩放修缝。
- 本地实际包络 `(0,0,-1.5)..(3.75,5.25,1.5)`。底 Y0；正式桥唇 X3.5/Y5.25/宽3m；内鼻 X3.75/Y5.20/宽2.98m。
- `OuterJoin`、`OuterJoin_0..4`、`BridgeLip`、`InnerEnd` 八锚点与 p1 相同。西五点高度与 JSON 相同。
- 6 个独立网格，22,656 三角，13 绘制 primitive，4 种基础材质。材质名仍带 P1，表示原基本调色板未重做。静态；碰撞须直接用相同可见三角，不能用整盒或凸包填凹处。

## 本轮证据和冻结字节

Blender 5.2.1 LTS / Cycles CPU2 / 12 samples，实际构建及单图进程 exit 0。`geometry_report.json` 的 73 项检查全部通过：五点接口、42 条唇/鼻射线、93 个中央承载带采样、八锚点、包络、闭合边、非零面及主根 18 个正 Z 首命中截面。`inspect_review_glb.py` 对实际导出的二进制回读 13 项通过，验证源/GLB 网格数、三角、材质、包络和锚点一致。

- 输入 p1 blend SHA256：`a1d22875f043bcc2360d6b7b83a56f447e9d598e19f9b58e7e257790c1106168`，读前后不变。
- `growth_approach_west_p2.blend`：`0d56dd85793d7d3b5e92e8cc24015bc1399af182d028ec73516303abeb2c3dfc`。
- `west_p2_review.glb`：452,548 字节，`2f118763033c210b771c528769ea292cd437a58ee8fce883d9be3ebd96b71264`。
- `west_p2_default_direction.png` 为实际离线基础色图；相机方向与游戏一致，近裁图并非游戏截图。其哈希记在几何报告中。

制作方已实看离线图：**主根连续可见有改善，整体美术仍未通过**。上盖仍偏平板，右侧局部尖唇仍可读；天然叉部分端部埋接不足，近看像悬露截段；下部大岩仍偏柱体。根侧 18 探针只证明这些截面的实际首命中，不证明默认镜头全部投影可见、任意自交安全或参考已还原。不自行启动新的孤件循环，冻结该版供根代理同镜头实际装配后判断。

尚未执行 p2 的游戏装配、实际机体扫掠、光路与生长动作。p1 的 18 项实际场景检查不自动继承给 p2。无 PBR/最终 UV、美术通过、真人游玩或性能结论。

## 重建

项目根运行（仅写本目录）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --threads 2 --python-exit-code 1 --python asset_sources/v3/growth_approach/west_p2/build_west_p2.py
python asset_sources/v3/growth_approach/west_p2/inspect_review_glb.py
```

可在 Blender 命令后加 `-- --no-render` 跳过单图。生产 JSON 是当前尺寸权威；脚本保存其原字节副本与 SHA，重建前应核对其版本。请在明确的新返修任务中才重建，避免覆盖根代理正在使用的候选字节。

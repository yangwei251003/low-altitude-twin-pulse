# 西短引桥 p1：主形候选

此目录独占建模；没有运行资产、烘焙贴图或引擎接线。根代理追加授权源目录基础材质 `west_p1_review.glb`，仅供实际装配审查，不能视作正式美术交付。

批准输入是 `references/v3/production/growth_approach/growth_approach_west_reference_v2.png`。单图可见的语言为短厚岩肩、宽大斜切面、顶部扁根与局部苔缝。隐藏背面与内部结构是新建的合理延续，不声称从图中恢复。全部尺寸、顶面三角和接口来自当前 `f1_growth_crossing.json`。

## 首轮保留

`first_form_failed/` 是首轮源、模型、两图、数值报告和日志的原字节副本。首轮 72 项数值检查通过，但根代理和制作代理均实际看图后退回：四面方芯过强、附加侧岩像贴块，根在顶部转角被石遮断。它不是可采用的主形。

## 固定装配契约

保留顶部连续承载面、西五点接口、3m 宽正式桥唇与 2.98m 宽下切鼻端。主体要求数块厚实错位断裂岩层；不采用隐藏方芯加薄贴石，也不采用全周同高度收腰的柱形。根与石之间需要真实包络内的局部让位。

Godot 世界原点为 (-14.5,0,25)，模型局部范围 X[0,3.75]、Y[0,5.25]、Z[-1.5,1.5]。Blender 坐标转换为 (x,-z,y)，根节点单位变换。`OuterJoin`、五个 `OuterJoin_i`、`BridgeLip`、`InnerEnd` 是独立锚点；单件静态。实际石/根三角未来同时提供渲染和碰撞，不提供盒碰撞或凸包替代；薄苔为非承重细节。

`build_west_approach.py` 自包含，仅用 Blender 5.2 自带 Python。脚本头为启动方式；加 `--frozen-layout` 可使用本目录生成时原字节保存的 `input_f1_growth_crossing.json` 复现，不覆盖生产 JSON。生成的 `geometry_report.json` 记录当前源、输入和 blend 的 SHA256、实际网格包络、全宽桥唇/鼻端回读、主体侧面剖面和检查结果。

默认图采用生产相机方向 (32,39,32)，但为主形审查裁近，并非游戏画面。反向图只补充隐藏侧面。基础材质没有最终 UV/PBR；未通过实际世界碰撞、接台密集实测、默认游戏镜头或人工游玩验收。

## 当前修订结果与未解决问题

第二版 67 项数值检查通过，但沙漏柱和根体遮断被退回。其原字节源、模型、两图和检查保存在 `second_form_failed/`。

第三版实际运行 Blender 5.2.1 LTS / Cycles CPU 2。65 项数值检查通过；包络 (0,0,-1.5)..(3.75,5.25,1.5)，4 块真实厚岩与 2 个天然叉根副本，共 14,032 三角、4 种实际材质。该版 blend SHA256 为 `3753c9e3bfc4e65c6b2af374d99c4ce42bf6c60601383176c551bc7818f75fa9`。首次外角射线失败是采样点在收边外：X 向内 10 微米时岩缘已收进 6 微米，原 Z 只收进 1.5 微米。改为 X 向内 1 微米，保持原高度标准后通过，未改接口。

**第三版视觉不通过**：已实看默认方向和背面图。上层岩仍像整块矩形盒，天然根大面积被岩体吞没、仅露碎段。数值不能证明美术。第三版原字节已存 `third_form_failed/`。

## 当前第四版：基础材质装配审查候选，未获形体通过

四块深厚岩体按不同高度斜切接合；上层西岩不再从顶面延伸至地面。固定两端和中央承载带，外侧岩沿局部让出天然根体空间。天然根保留原负 Z 厚叉，取消第三版误裁主叉的 Z 裁切；按 sourceY 每 5cm 真实顶点邻域外 X 平移整截面后弯曲贴合，无法向压扁。该操作仍改变原天然根的空间摆位，不能称为未变形扫描。

天然来源是冻结的 `asset_sources/v3/shore_root/p9/rigid_root_main_form.blend`，SHA256 `adc2218b773bef0e4b7f4a37339fe1c79abab3e0311a42014b318e6d3b2a2ed2`。其来源为 Poly Haven Island Tree 01 的树基/粗枝，CC0，作者 Rico Cilliers、Rob Tuytel；不是裸露根扫描。本次原文件读前后哈希不变，完整引用件仍保留在编辑 blend 隐藏集合中。`natural_sections.json` 保存实际截面，`inspect_natural_sections.py` 可重读；原 glTF 式轴为 `(Blender.x, Blender.z, -Blender.y)`。

Blender 5.2.1 LTS / Cycles CPU2 / 16 samples 完成同版两图。65 项源几何检查通过，随后 `inspect_review_glb.py` 用 Python 标准库实际二进制回读，13 项检查通过。6 个编辑/导出网格，22,656 三角，4 种基础材质，13 个绘制 primitive；隐藏来源和摄影棚不在导出中。8 个锚点全部回读一致，根单位变换，Godot 局部边界 `(0,0,-1.5)..(3.75,5.25,1.5)`。GLB 安装位置为 `(-14.5,0,25)`，不得额外旋转/缩放修接缝。正式桥唇局部 X3.5 / Y5.25 / 宽3m；内鼻 X3.75 / Y5.20 / 宽2.98m。

- `growth_approach_west_p1.blend`：SHA256 `a1d22875f043bcc2360d6b7b83a56f447e9d598e19f9b58e7e257790c1106168`。
- `west_p1_review.glb`：446,800 字节，SHA256 `525a5343ce13e74450736e4d478cc1f73fecea7a2bfa15ce26f2072d9b95e08d`。
- `geometry_report.json` / `review_glb_readback.json`：源接口与同字节导出核对。
- `west_p1_default_direction.png` / `west_p1_reverse_direction.png`：同版离线两图，`preview_provenance.json` 关联源 SHA 和图片 SHA。

**制作方实际看图仍保留退回意见**：上面仍偏整齐折面板，侧沿有薄尖唇，根虽是连接网格却仍被岩遮成视觉分段。当前仅交根代理进行真实装配镜头审查，暂时冻结模型和基础色 GLB，避免继续依据孤件放大图盲改。数值只证明指定接口、闭合边、非零面积和导出对应；不证明任意自交、参考美术还原、完整场景物理、玩家舒适度或性能。没有 PBR、最终 UV 或美术通过结论。

本轮低信心恢复复用了既有 route，查阅 [Blender 5.2 Bevel 官方文档](https://docs.blender.org/manual/de/5.2/modeling/modifiers/generate/bevel.html) 的限定顶点组/倒角范围方法；此次仍采用可编辑显式切面，未声称使用了未执行的修改器，也未安装无关工具。

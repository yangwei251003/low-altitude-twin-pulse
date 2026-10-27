# H10 p3：仅材质候选，运行 p2 冻结

本目录保存 2026-10-18 实际游戏图退回后的单件材质试验。父任务已允许进入 **H10 单件候选 GLB** 的实际游戏检查；不代表最终美术通过，不复制到其它高度。周边世界、规整大顶面和前部宽木带没有因此完成。

## 可供导入的冻结候选

- `assets/v3/candidates/root_buttress_h10_p3/root_buttress_h10_p3.glb`
- SHA256 `b751731bc509edbf915d1df61241197ffd8e701e6e5426a298e0672310fe7049`
- 8,007,264 字节，14,182 三角，5 网格，4 材质，全部使用 `TEXCOORD_0`，PBR 图片内嵌。
- `root_buttress_h10_readback_p3.json`：42 / 42 通过；包括实际导出三角面与 p2 等价（0.1 mm 量化）、36 个足面探针、3 条前侧靶线、锚点、UV 和显式 PBR 贴图。
- `root_buttress_h10_glb_preview_p3.png`：删除源对象后，真实重导上面同 SHA 的 GLB，再以 CPU 2 / 8 samples 离线渲染。相机方向采用游戏固定斜角，中性审图灯光；**不是 Godot 截图**。

运行的四个 p2 GLB 没有覆盖。新候选与 p2 的网格、顶点、UV、锚点在源侧指纹完全相同；实际导出后又独立比较了三角面坐标。碰撞与目标接口全部不变。

| 节点 | 用途 |
|---|---|
| `RootButtressH10` | 唯一资产根，原点地面 |
| `RockMasses` / `LivingRoots` | 实体三角碰撞 |
| `BarkPlates` / `MossDetails` | 装饰，排除碰撞 |
| `SapKnot` | 独立宿主能力目标，保留真实碰撞 |
| `GroundOrigin` | Godot `(0,0,0)` |
| `BodyPerch` | Godot `(0,13,0)` |
| `HostTarget` | Godot `(0,11,4.5)` |
| `LowerShelf` | Godot `(-3.7,5,3.2)` |

Godot 完整 bounds：min `(-6.610198,0,-6.804512)`，max `(6.905735,11.932129,6.879330)`。四足支撑顶面仍为 Y10。

## 可编辑来源与实际变化

1. `root_buttress_h10_material_p3.blend`：189 件独立可编辑网格，原始材质节点配方。其输入为冻结 H10 p2 源，没有重建或移动形体。
2. `stone_reference_p3.png`：内建 imagegen 新生成的一张单材质冷灰层状岩图。原字节副本；提示词见 `stone_prompt_p3.txt`，工具返回路径及 SHA 见 `p3_source_report.json`。没有生成整场景，也没有用位图代替几何。
3. 石材在原生节点中混入 10% 冷矿物色；树皮与固定暗棕色混合 48%，减少反差。两项由 Blender Cycles EMIT 原生烘焙为 `textures/*BaseColor_P3.png`。PNG 采用 sRGB；粗糙度/法线采用 Non-Color，保留外部源。不是用截图调色冒充实机。
4. `root_buttress_h10_p3_export_ready.blend`：烘焙后仍保留 189 件网格；运行使用直接 UV → PNG → Principled 的 PBR。源文件保存后才建立单独合并副本导出，源没有合并覆盖。
5. `prepare_h10_p3.py` / `bake_export_h10_p3.py` / `verify_h10_p3.py`：可重复制作及回读。运行需先与其它渲染任务协调 CPU 2 窗口；候选已交付冻结，不应无通知重跑覆盖字节。

`h10_p2_controlled_baseline.png` 与 `h10_p3_material_candidate.png` 为原版/候选的相同相机、相同灯光对照，属于可编辑源渲染。最终回导图另外拍全物体，镜头取景稍宽；不可混称同一画面或实机。

## 剩余差距与验收边界

- 冷灰与较安静的根木解决了旧版黄裂网主导画面的问题，但顶面斜向层理仍明显，需要 Godot 实际光照和 Boss 同框检查。
- 大平顶、较规则顶缘与前侧宽根束几何未变。纹理层理不是新增岩层体积，不以材质检查代替形态改善。
- 少量根缝苔片及琥珀保持 p2 的位置与尺寸；不扩大到满铺绿斑，不把新纹理当新增交互。
- 42 项是 Blender / GLB 数值与回导证据，不是 Godot 飞行体扫掠、真人玩法、性能或最终美术验收。
- 首次回读数值已全过，但新建审图地面材质的英文节点名称在中文环境中找不到，离线渲染中止；改为按节点类型读取后同一 GLB 成功渲染。首次日志保留为 `verify_p3_render_name_failure.log`，没有改模型或放宽断言。

完整文件哈希见 `p3_manifest.json`；实际游戏对照由根代理另行执行。

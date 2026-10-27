# H10 P11：完整单件集成候选

2026-10-18。本轮已完成可编辑源、实际 UV/PBR 烘焙、显式 GLB 和同字节回导。根线程已查看最终源图，允许进入真实游戏镜头审查；**尚未最终美术通过**。没有替换运行 P2，也没有量产 H12/H17/H3。

## 当前交付

| 文件 | 用途 |
|---|---|
| `root_buttress_h10_complete_p11.blend` | 未烘焙、可编辑源；独立主岩体、前根、右根、原 Sap 和四锚点 |
| `root_buttress_h10_p11_export_ready.blend` | 同几何的显式 UV/PBR 源，贴图已保存并打包；源部件仍独立 |
| `textures/` | 石/根各三张 1536×1536 原生烘焙图，共六张；原 Sap 三图保留原字节 |
| `root_buttress_h10_p11.glb` | 独立候选，位于候选资产目录，准确路径见下文 |
| `h10_p11_complete_material_source.png` | 最终可编辑源的 CPU 离线图，不是游戏画面 |
| `h10_p11_same_byte_glb_preview.png` | 删除源对象后，实际导入冻结 GLB 的 CPU 离线图 |
| `p11_source_report.json` / `p11_glb_readback.json` | 源 16 项与实际回导 37 项的原始数值记录 |
| `ASSET_CONTRACT.md` / `manifest.json` / `selfcheck.json` | 节点接口、逐文件哈希及交付核对 |

GLB 的准确项目相对路径是 `assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb`，相对本 README 为 `../../../../../assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb`。冻结 SHA256：

`d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f`

8,530,596 字节；63,996 三角；3 网格、3 材质、9 张内嵌图片。只有 `TEXCOORD_0`，贴图明确采样这一层。`P11_Bark_Recipe` 和 `P11_Stone_Recipe` 是保留的材质名称，导出时已经是真正烘焙的显式 PBR，不依赖程序节点。

## 本轮改变与验证

沿用 P10 连续闭合岩体，局部清理后脊锯齿与小直角，前/右侧增加两处宽断裂面打断层纹。天然树干粗叉副本经裁枝、断面封口、横截面压扁和贴壁调整成为两条宽分叉根；原件没有改动。未用新随机细碎石块或苔片掩饰形体。

主岩体及两个根源分别为单一闭合组件。四足每处 R0.75 共 772 个探针保持 Y10，中台五点保持 Y5；三条靶射线无遮挡，主根实际进入 Sap 体积，Sap 原几何/UV/变换与四锚点不变，全部仍在原包围范围内。真正 GLB 回导的三个网格与源三角几何指纹一致。

源检查 16/16、GLB 回导检查 37/37 通过；这些是离线几何和文件管线验证，不代替完整冠兽体积、迁移/逼落路径、Godot 光照、真人体验或性能测试。报告的阶段字符串保留生成当时状态；导出报告中的“pending reimport”已由其后的 `p11_glb_readback.json` 完成，不改写原始记录。

石/根 BaseColor、Roughness、OpenGL tangent Normal 由原生 Blender 对实际网格逐材质烘焙，无光照/AO 烘焙。BaseColor 为 sRGB，数据贴图为 Non-Color。合并只发生于导出副本，源中两根仍可分别编辑。实际 GLB 节点与锚点值见接口卡和回导 JSON。

## 未解决的形体差距

根线程实看后仍指出整片顶面平整、后脊偏直斜坡、前根存在扁带和断端感；右侧宽断裂阴影也需实际相机确认权重。没有宣称还原批准参考，尚未加入成熟的苔土交界处理。暂不继续新一轮形体，先由根线程使用冻结候选检查真实镜头。

## 可追溯失败

首次构建因依赖本地化后的 `Principled BSDF` 节点名称失败，改为按节点类型识别，原日志 `build_source_node_name_failure.log` 保留。`visual_reject_v1/` 虽数值通过，但根过度埋入岩体，图上呈断续木片；`visual_reject_v2/` 调整贴壁深度后，第三条小左根的切端在中台上方暴露，仍不接受。最终删除可选第三根，保留两条主根并修其贴合。这两目录的图、源、脚本和报告是历史失败版本，不能混作最终候选。

## 来源与许可

岩面形体源是 Poly Haven 的 [Rock Face 01](https://polyhaven.com/a/rock_face_01)，作者 Dario Barresi；经过采样补闭、切削和本体修形，并非扫描原样导入。根源来自 [Island Tree 01](https://polyhaven.com/a/island_tree_01)，作者 Rico Cilliers、Rob Tuytel；只使用木质 primitive，不加载枝叶，粗叉经过适配，不是原始天然长树根。二者 [CC0](https://polyhaven.com/license)，原文件只读，来源与哈希见 manifest。

批准的单件 imagegen 参考与 P3 已审冷灰材质为只读输入。此次没有生成新概念图，也没有将扫描照片直接称为手绘效果。

## 重现与冻结

构建 `build_complete_p11.py --render` → `bake_export_complete_p11.py --bake-only` → `--export-only` → `verify_complete_p11.py`。使用本机 Blender 5.2.1、后台模式和 2 个 CPU 线程；需先取得队列窗口，不能在根 GPU/性能任务期间重跑。上述命令会重写本候选，因此冻结后不应仅为检查再次执行。

轻量交付核对使用 `freeze_p11.py --check`，不启动 Blender、不改模型。源 P10、树叉源及运行四个 P2 GLB 的预期哈希均固定于脚本和 manifest；最终模型、贴图与 GLB 本轮不再改动。

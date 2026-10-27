# 西引桥 / 封印闸基座：真实岩体资源取证

2026-10-18。状态：**资源验证完成并冻结，尚未装配、裁切、导入或通过美术验收**。路线沿用 `5e455d78-37b2-423b-b660-0cc3185eae49`。P1–P4 保持冻结；本轮未运行 Blender、Godot、GPU，未安装工具或下载纹理。Powered by [Poly Haven](https://polyhaven.com)。

## 选择结论

首选 **Boulder 01 作主断岩、Namaqualand Boulder 03 作厚承托体**，以实际艺术家网格取代规则盒体构形。小锁石可从已有 Rock Moss Set 01 的 `modelShape` 取一件；它不是第三种主体。官方灰材预览已逐件实际查看，保留在对应子目录，只作资源形态研究。

| 资源 / 作者 | 实际可用低模（原生文件读回） | 下载 / 编辑性 | 对本项目的适配判断 |
| --- | --- | --- | --- |
| [Boulder 01](https://polyhaven.com/a/boulder_01) / Rico Cilliers | `boulder_01_LOD2` 16,530 三角；`LOD3` 8,264。LOD0/1 为 66,122/33,060。 | 原生 `.blend` 5,370,351 B，含四个独立 LOD 网格；1K 含贴图包 9,275,622 B。 | 宽而不等大的破裂面、斜切肩部和连续厚体积最适合西坡主视觉；优先保留扫描的大轮廓，不能再压成方芯或薄饰面。 |
| [Namaqualand Boulder 03](https://polyhaven.com/a/namaqualand_boulder_03) / Dario Barresi（摄影）、Jenelle van Heerden（建模） | `namaqualand_boulder_03_LOD2` 16,206；`LOD3` 8,102。LOD0/1 为 64,826/32,412。 | 原生 `.blend` 4,213,652 B，含四个 LOD；1K 含贴图包 7,407,537 B。 | 宽低、厚重、较平静的破角岩体适合作承托或闸底；独占整件会重现方墩感，需与第一件斜向体块错接。 |
| [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) / Kless Gyzen | 现有 glTF 中 `modelShape` 为 **5,000** 三角；整个六件集为 63,127。 | 复用本项目原始 glTF/bin，不再下载模型。官方原生文件 2,697,968 B（本轮未下载）；1K glTF 全包 1,937,065 B。 | 轮廓更圆钝，只可作小锁石，不承担主岩语言。`medium.001` 有拓扑边界，明确不选它。 |

上述“低模”不是仅信页面标签：本轮用现有 Git 附带的 zstd 库在内存解压原生文件，再按 Blender SDNA 读取真实 Object/Mesh、面和环数；三角数按 `corners - 2 × faces` 计算，且字段长度核对通过。计数是**修改器求值前**，没有宣称已经用当前 Blender 打开编辑或证明低 LOD 无自交。Nama LOD0 有多边面，64,763 是面数，不能当三角数。官方页面总 polycount 是多 LOD 合计，不能当一个运行网格的成本。

## 原文件与完整性

项目根：`.`。

1. 主岩：`asset_sources/v3/growth_approach/resource_recovery/boulder_01/boulder_01_1k.blend`
   - [官方原始下载](https://dl.polyhaven.org/file/ph-assets/Models/blend/1k/boulder_01/boulder_01_1k.blend)
   - SHA256 `8f8004fb52ebd00c4702a50873ac799e7bd7a0bea3415f2d8bc9986e1c58e371`
   - 本地 MD5 `8841af39e9ee00855f47187c86f30fda` 与官方 files API 一致。
2. 承托岩：`asset_sources/v3/growth_approach/resource_recovery/namaqualand_boulder_03/namaqualand_boulder_03_1k.blend`
   - [官方原始下载](https://dl.polyhaven.org/file/ph-assets/Models/blend/1k/namaqualand_boulder_03/namaqualand_boulder_03_1k.blend)
   - SHA256 `43e8e12ebbd694b73b1c8ffd2ca75983f7b5c8f41672792d98a7cfde328f5e66`
   - 本地 MD5 `833226cbfdc369d6466eccceab6180fd` 与官方 files API 一致。
3. 可选小锁石：`asset_sources/v3/root_buttress/p6/vendor/rock_moss_set_01.bin`，对应 glTF 保留于本目录 `rock_moss_set_01/rock_moss_set_01_1k.gltf`，本轮对已有 bin 只读。
   - bin SHA256 `de8360e6175879aaf02c171911069cf5f1852547f9ca7f10e440085dbcc3315e`

两件新 `.blend` 均为 4.02 文件格式。另保存对应原始 glTF/bin 供独立几何读取；**未下载外部贴图，当前并非开箱完整材质包**。本轮新下载原生文件和几何 bin 共 **13,973,079 B（13.33 MiB）**；含 API、预览、脚本的归档在本说明写入前为 17,297,389 B，无数百 MB 下载。最终逐文件大小及 SHA 见 `frozen_manifest.json`。

## 真实形体与低模边界

独立解析实际 glTF 的 POSITION/indices，未根据缩略图猜尺寸：Boulder 01 的 X/Y/Z 跨度为 **1.2721 / 1.0038 / 1.8303 m**；Namaqualand 为 **2.4071 / 1.4732 / 3.0654 m**，两个节点均无额外变换。这是 glTF Y-up 轴序，不能直接套用官网 Blender 轴序尺寸。

两个 glTF 的实际 LOD0 网格，在位置按 1 µm 合并后均为 **0 开边、0 超过两面的边**。这只证实这项边拓扑检查，**不证明无自交，也不替代所选原生 LOD2/3 的装配检查**。glTF 仅含 LOD0；真正的较低 LOD 在 `.blend` 内。

已排除现有 [Rock Face 01](https://polyhaven.com/a/rock_face_01) / [Rock Face 02](https://polyhaven.com/a/rock_face_02) 作为封闭主岩：它们实际为 20,174 / 29,566 三角，但有 **886 / 754 条开边**，另有 2 / 10 条超双面边，灰材预览也是表面岩壁。补成厚主体需要重建大片背面，违背本轮“真实厚岩，仅局部适配”的目的。这里保留排除证据，不再扩大候选。

## 下一稿的单一验证方案（建议，未实施）

- 西坡仍是 3.75 × 3 × 5.25 m 接口约束：用 Boulder 的非轴对齐厚体作为主断岩，Nama 的宽厚体承托桥口，必要时再放一件转向不同的 Boulder。先以等比缩放/旋转找三块互相承托的整体，不能把各自拉成窄柱，也不加覆盖全顶面的薄盖。
- 仅西端五点接面、桥唇/内鼻、八锚点和中央承载带做局部接合；自由侧面保留资源本身的大裂面及厚度。主根继续独立可编辑曲线，并沿实际表面连续可追踪；本轮未更换根源。
- 封印闸基座优先 Nama 的低宽厚体作地接面，Boulder 作较小斜肩；保持基座真实 footprint/水域参数由当前世界数据决定，不能拿缩略图推导碰撞。
- 一种规模估计是 16,530 + 8,264 + 16,206 + 5,000 = **46,000 三角**（尚未含裁切和根）；这是候选预算，**不是性能通过或必须凑四件**。先只出一版基础材质装配图和实际接口/身体通行检查，轮廓通过后再做 F-B 表面。扫描本身的写实材质不等于本游戏手绘美术。

## 许可与可复核证据

[Poly Haven 官方许可](https://polyhaven.com/license) 明确模型与纹理为 CC0，可修改和再分发；**网站内容中的资产示例渲染不在该 CC0 资产许可内**，因此本目录官方预览仅作研究，不当作可发行游戏贴图或自制作品。数据来自每件的 `https://api.polyhaven.com/info/{id}` / `files/{id}`，原响应与直达下载地址已存档；[官方 API 仓库](https://github.com/Poly-Haven/Public-API) 为接口来源。

- `resource_facts.json`：官方元信息、文件清单、实际 glTF 计数/边检查、URL、大小、SHA 与既有只读文件路径。
- `native_lod_counts.json`：两个原生文件的四级 LOD、真实网格名、计数、限制。
- `inspect_resources.py`：有界下载及独立 glTF 解析；只研究，不生成新资产。
- `read_blend_lods.py`：原生 SDNA 只读解析，不调用 Blender，不安装依赖。
- `frozen_manifest.json`：此目录冻结的逐文件散列（不含清单自身）。

**本轮到此停止，不生成 P5，不改运行资源。** 后续首次打开所选原生低模、局部裁切、默认实机装配及几何/性能验证仍待 root 决定和单独任务执行。

# P12 — 单块官方扫描天然石样件（静态准备，未运行）

只替换 P10 的 `SedimentBankStone_047`，原 20 三角；使用 Poly Haven `Rock 07` 的原生 `rock_07_LOD3`，1,854 三角。原 143 件、土沟/断板/接边/数量/材料不动，预计总 9,290 三角。FallenConcreteFragment 不用天然石材质。本轮不批量替换，不烘焙、不导 GLB、不改运行资源。

输入 `inputs/polyhaven_rock_07_1k/`：Jenelle van Heerden / Poly Haven / CC0。原始 blend 与三张官方 1024² 无损 PNG，实际 URL、大小、SHA256 和官方 MD5 对照均在 provenance.json；总 10,454,572 B。相比初始调查的 1.71 MB JPEG 纹理包，本次刻意取得无损 PNG，避免法线额外 JPEG 压缩。没有重新采样/编辑图片。

实际查看三张原图：色图为暖褐/浅矿物斑的独立 UV 岛，NormalGL 有真实面内起伏，ARM 为原包装。原生 Blender 文件仍保留自带 EXR 相对引用；新样件仅追加 LOD3 对象并自建标准 Principled，使用此三 PNG，不执行供应商脚本或改原 blend。Diffuse=sRGB，NormalGL/ARM=Non-Color；ARM G→rough、B→metal，原 NormalGL→同原 UV 的 tangent NormalMap strength 1。ARM R 保留数据，此首轮不把 AO 乘进色图，接触阴影由实际场景几何产生。没有用颜色制造深坑。

定位方法：原模型统一缩放，使原水平长轴精确为 0.12 m，再刚性朝向旧石水平主轴；X/Z 中心保持旧石 ground_center。针对 P10 真实土三角逐顶点向下射线，求第一次垂直接触，再整体下埋 12 mm；记录真实埋入/露出数量与距离，不逐顶点压扁。检查旧全件 X[-3,3]/Z[0,2.4]/底 Y≥−.18/顶 Y≤.03 范围；失败停下保留报告，不自动下压凑数。实际 LOD3 UV、边闭合、体积、法线及变换将在运行时读回，不能把 LOD0 调查当作已验证的 LOD3。

两图：P10 原全件相机，以及 P11 三石对照的相同 1.25 m 局部相机。只改变那一块石，邻石遮挡仍按原位置保留；若新石仍被遮挡，将如实记为样件证据不足，不隐藏邻石。局部图不是默认 26 m 游戏镜头。

入口：`python -B asset_sources/v3/clinic_ground_transition/p12/run_preview.py`

预计 CPU2 约 110–150 秒，硬限 240 秒只自身进程树。当前仅 AST 静态检查；等 root 的明确串行运行窗口。输出进入新 `sample_review_01/`，旧输入和 P10/P11 均核对 SHA 不变。保存后原生重开源，再以 abspath/实际像素读取检查图像，之后两图；失败即停。

若样件有效，未来仍需用少量代表石/更低合理 LOD 控制成本；绝不把 1,854 三角乘到全部 112 枚小砾。此次新增三角数不代表获准运行预算或美术通过。

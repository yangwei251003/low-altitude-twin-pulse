# V3 原创资产来源

2026-10-17。用户在四方向对比后选择 I-B 与 F-B。

- 单件概念：本项目使用内建 imagegen 生成；原始提示、参考关系、图片 SHA-256 与用户选择保存在 `references/v3/concepts/manifest.json`。这些图片不是实机截图。
- 工业桥与神殿门：本项目基于所选概念在 Blender 5.2.1 中独立制作的网格、UV 和材质；程序绘制的 PBR 图像，没有下载或裁切第三方游戏纹理。可编辑源位于 `asset_sources/v3/industrial` 与 `asset_sources/v3/fantasy`。
- 地表/水面研究：本项目自行编写的 Godot shader；没有外部采样图片，没有把材质纹路当作真实地形碰撞。
- 运行时包装、光路与交互：本项目 GDScript。GLB 可重新导出，不覆盖包装场景中的玩法与碰撞。
- 第二批四件：工业工作台地/继电柜、巨木洞岩台地/感光根簇逐件使用内建 imagegen 生成生产参考，再由 Blender 建模与制作 PBR 图像。工业生产参考清单在 `references/v3/production/industrial/manifest.json`，奇幻两份 `_provenance.json` 在对应 fantasy 目录；生产参考沿用已批准 I-B/F-B，不代表新增风格批准。源文件位于两套 `asset_sources/v3/*_kit`；没有下载第三方游戏模型或纹理。
- 台地返修保留过程图与明确失败项。工业 v4 使用专用混凝土与安全标记图集，不覆盖柜体或首桥图像；奇幻最终导出已重读贯通洞与 UV。实际镜头、可编辑源和当前美术差距见两份 `docs/v3/assets/*_KIT.md`。

旧版本保留的字体、音频、模型与运行库仍分别遵循原有第三方来源说明；本文件不覆盖它们的许可。

# 第三方资源与许可

## 四世界重建追加资源 — 2026-10-16

- [Kenney Conveyor Kit](https://kenney-assets.itch.io/conveyor-kit)，作者 Kenney，原作者页面与包内 License.txt 标注 Creative Commons CC0 1.0。仅使用 `conveyor-long-stripe-sides`、`robot-arm-a`、`scanner-high` 三个部件，统一尺寸、原点及本项目石墨/米白/赭黄材质后导出为 `assets/models/worldui/conveyor.glb`、`robot_arm.glb`、`scanner_gate.glb`。原包、许可、原文件、来源和下载 SHA-256 保存于 `assets/source/worldui/conveyor_kenney`；修改后的可编辑 Blender 源在 `assets/source/worldui`。原包 SHA-256：`5ae214fb473cc5d4aa75828da2a61310c0f88abefbfb1fb6c7da592b18d0ee50`。
- 本轮研发楼、工坊、试飞架、光伏架、储能柜、配电站、三叶风机、集装箱组、仓库、岸桥、服务柜及风格化岸岩为项目原创模型。源文件和生成器保留；不将程序建模作品归属于外部素材作者。
- `references/worldui` 内图片由 ImageGen 生成，用作设计、材质、布局参考；它们不是实机截图。游戏区域卡使用 Godot 实际运行截图。

游戏代码、无人机、敌人、Boss、建筑模块、UI 和程序音效为本项目制作。ImageGen 概念用于方向与生产参考，不是实机截图，也没有作为不可游玩的背景来替代三维世界。

| 内容 | 作者与来源 | 许可 / 使用 |
| --- | --- | --- |
| Nature Kit 2.1 | [Kenney](https://kenney.nl/assets/nature-kit) | CC0，源包留在 asset_sources/third_party |
| City Kit Industrial 2.0 | [Kenney](https://kenney.nl/assets/city-kit-industrial) | CC0，工业储罐及材质 |
| Particle Pack 1.1 | [Kenney](https://kenney.nl/assets/particle-pack) | CC0，火花、枪口、烟雾纹理 |
| Sandstone Blocks 04、Aerial Grass Rock、Rock Boulder Dry | [Poly Haven](https://polyhaven.com/license) | CC0，1K 材质；通过作者公开 API 下载 |
| Coast Rocks 01 | [Poly Haven](https://polyhaven.com/a/coast_rocks_01) | CC0，远岸岩石，原始模型保留并做比例/几何适配 |
| Noto Sans SC | [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc) | SIL Open Font License 1.1，OFL 在 assets/fonts；550 字重由原变量字体实例化 |
| Godot Engine 4.7.2 | [Godot Engine](https://godotengine.org/license/) | MIT，官方 Windows 导出运行时 |
| GUT 9.7.1 | [bitwes/Gut](https://github.com/bitwes/Gut) | MIT，仅开发测试使用，不随游戏导出 |
| godot-qr-code | Iceflower S, [kenyoni/godot-qr-code](https://github.com/kenyoni/godot-qr-code) | MIT；本地生成手机配对地址二维码，许可保留在 phone/vendor/qr_code/LICENSE.md |

下载 URL 与完整性摘要记录于 docs/asset_sources.json、docs/polyhaven_models.json。源包附带的许可原文另存 assets/licenses。参考游戏的截图只用于内部研究，不纳入发行包。本项目与上述参考游戏及资源作者无隶属或背书关系。

Poly Haven 的 Island Tree 01 与 Shrub 01 曾作为适配实验，原始文件保留在开发项目；它们未进入发行版。发行版树木和灌木为本项目制作的实体网格。

Godot 及其捆绑组件完整许可保留在 assets/licenses/Godot-runtime.txt；Noto Sans SC 的 OFL 全文位于 assets/fonts/OFL.txt。请在再分发时保留这些许可证。

V2 的六机体与十五个挂件提供 Blender 源文件和生成脚本。早期 V2 的 35 个合成音源已由本轮 37 个音频产物替代，其中包含下列六项 CC0 外部来源与本项目制作的声音。处理参数与校验摘要位于 asset_sources/v2 和 assets/v2/audio/audio_manifest.json。

## V2.1 art and audio upgrade — 2026-10-14

- Four vehicle models adapted from [Kenney Car Kit](https://kenney.nl/assets/car-kit), CC0. Full original license: `assets/licenses/V2StreetVehicles.txt`. 21 other new street/building models are original editable Blender work, not Kenney assets.
- Audio includes Kenney UI Audio / Impact Sounds; Sheyvan's Freesound Drone Flying (public HQ preview), isaiah658 bird sounds, jasinski/qubodup ocean waves, Chris Murphy (zesona) Sherwood music. All six external source records are explicitly CC0. Authors, direct URLs, license evidence, transformations and hashes: `assets/v2/audio/source_credits.json`, `asset_sources/v2/audio/sources.json` and `docs/V2_AUDIO_UPGRADE.md`.
- `assets/v2/ui/waterfront_menu.png` is an illustration generated with the built-in ImageGen tool for this game menu. It is not a screenshot or a claim about runtime graphics. Native controls and all 3D gameplay are rendered separately.
- Source packs are retained for editable-source recovery; only actually used runtime assets enter the game. Downloaded Kenney commercial/road packs are reference alternatives, not copied wholesale into the playable scene.
# V2.2 additional media attribution

V2.2 adds six complete Kevin MacLeod compositions under CC BY 4.0, credited by title, author, source page, license link and processing in `assets/audio/v22/CREDITS.txt` and `assets/audio/v22/manifest.json`. Those files accompany the portable release and are accessible in the settings credits screen. Environmental recordings are individually documented CC0 sources; original synthesized layers are identified as such. Offline Mandarin narration was generated with the MIT-licensed MeloTTS Chinese model through sherpa-onnx; only generated audio is distributed in the game. Source snapshots, hashes and editable processing steps are in `assets/source_audio/v22` and `docs/v2/V22_AUDIO.md`.

Earlier-version notices above remain applicable to their respective bundled assets.

## V3 gameplay audio bank — 2026-10-20

The V3 runtime bank reuses 34 previously credited CC0/original project sounds and adds one original industrial BGM composition. Runtime attribution is included in `assets/v3/audio/CREDITS.txt`; editable generation and processing source is `scripts/v3/audio/build_audio_assets.py`. Its cue/source catalog is `data/v3/audio`. No new external sample pack was downloaded for this bank.

## V3 forest ground surface — 2026-10-18

`assets/v3/materials/forest_floor_surface_v1.png` is a single surface reference generated with the built-in ImageGen tool for this project. The original image bytes, generation prompt and provenance are preserved in `references/v3/production/materials`. The shader blends this base color in world coordinates with the functional mud path and wet bank. It is surface appearance only; it does not create geometry or collision. The source image is not a game screenshot. The P2 material is an intermediate development asset, with repetition and final art review still outstanding.

## V2.2 combat media attribution — 2026-10-15

- 37 combat sound files in 13 families (37.475 seconds of variations) combine selected [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds), licensed [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), with original project synthesis. The recordings were layered, filtered, edited, leveled and converted to 48 kHz mono PCM for spatial playback. The original synthesis is identified as project-original, not attributed to Kenney. Runtime attribution and processing records: `assets/audio/v22_combat/CREDITS.txt` and `assets/audio/v22_combat/manifest.json`. The original Kenney license, selected recordings and source hashes are retained in `assets/source_audio/v22_combat`; editable synthesis is in `scripts_tools/v22_combat_audio_build.py`.
- 10 original combat GLB models (four enemy roles, three weapons and three wreck pieces), their editable Blender sources and generator are dedicated by this project to CC0 1.0. No external geometry, textures, fonts or images were used in these models. The author declaration and license are in `assets/models/v22_combat/LICENSE.txt`; the model manifest records each source, scale, orientation and SHA256. Editable sources are in `assets/source_models/v22_combat` and `scripts_tools/build_v22_combat_assets.py`.
- Both new attribution/license files accompany the portable release. The existing six music tracks, 27 narration clips and all earlier notices remain unchanged by this combat addition. `docs/v2/V22_COMBAT_ART.md` and `docs/v2/V22_COMBAT_AUDIO.md` describe the editable assets and the limits of their verification.


## V3 pump roof material study — 2026-10-19

[Metal012 by ambientCG / Lennart Demes](https://ambientcg.com/view?id=Metal012), [CC0 1.0](https://docs.ambientcg.com/license/), supplies a steel PBR layer baked into the editable pump-shell V8 source and runtime `assets/v3/clinic_pump_shell/clinic_pump_shell.glb`. The initial three Release packages did not contain the complete Metal012 source directory. The editable Metal012 material source and associated CC0 resources are now documented and supplied by the separate `v3.0.0-legacy-editable-20261027` supplement; see [the per-member inventory](archive/legacy-native-assets/release-assets.json) and [verified CC0 source records](archive/legacy-native-assets/new-CC0-resource-provenance.json). The combined UV textures also include project-authored weathering and generated material reference; no external model geometry was used. Source/export and actual-engine review evidence are recorded separately in `docs/v3/DEV18_PUMP_ART_REVIEW.md`.


### Dev88中文合成对白与复用人物

关键对白来自本项目已有主线/章节/支线可编辑字幕，使用本机已安装的Microsoft Huihui Desktop、Kangkang、Yaoyao离线合成。WAV为临时合成演绎，不是真人演员表演；未分发语音引擎或声库。字幕、来源映射与生成源保留在data/scripts/v3/content/dev88_presentation，资源说明见assets/v3/content/dev88_presentation/CREDITS.txt。联系人影像复用已有pedestrian_worker/walker/citizen GLB和本项目程序化饰件，沿其原来源/许可，不新增第三方模型包。


### 整体内容终章语音补充

新增177个离线中文合成音频文件，覆盖185个明确台词/摘要事件，实际采用本机Microsoft Kangkang声线。不是人类角色表演。字幕正文、音频事件和生成脚本分别保留在final_story及final_flow内容目录；复用原音频池。未添加第三方录音或新音乐。六Boss展示复用原thermal_bypass、parasitic_crown、photosensitive_roots及power_relay_cabinet的导入网格，原可编辑源和许可记录保留。


## 2026-10-26公开副本边界

根MIT只适用于本项目自有部分。以上声明保留各历史资源的来源；本公开批次不包含Windows SAPI生成的556段WAV或任何语音引擎/声库。字幕和程序源保留，不能把这些音频说成已经公开归档。运行/编辑Release附件中的第三方LICENSE/CREDITS与本文件共同适用。GUT另行准备，仅开发使用。原作者网页全文与商业研究截图不随此公开副本分发。

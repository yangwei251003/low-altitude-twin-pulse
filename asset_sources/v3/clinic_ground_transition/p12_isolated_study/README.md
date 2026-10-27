# Rock07 单件近图诊断

状态：独立样件已渲染并人工查看；仅支持继续评价这一种天然石来源，未批准批量替换、GLB 或游戏集成。

`rock07_isolated.png` 是中性摄影台上的 Blender 源模型近图，不是游戏截图，也不是与 P12 原场景同灯光的 A/B。仅从冻结 P12 提取已经替换的那一块石，保留原始 UV、三张 1K PBR 及 1,854 三角；完整露出轮廓，不保留邻石遮挡。诊断场景另存为 `isolated_diagnostic.blend`，没有覆写 P12。

实际看图结论：非均匀凹缺、侧面厚度和连续矿物纹理比原均色多面石更可信，具备作为少量天然碎石来源的价值。当前暖棕色和强细碎高光使表面偏湿亮，尚不能直接当作全组干砾的材质。模型有 1,854 三角，不能按此成本直接铺 112 粒。此图没有证明它在原场景小尺寸下的辨识收益；由根根据单件图决定下一步。

- 原长轴按统一比例 0.3743516734 缩至 0.12m；沿用 P12 的平面旋转，世界轴包围尺寸约 0.121678×0.071574×0.053784m。旋转后 AABB 不是缩放前主轴长度。
- 诊断只将该物体整体平移到摄影台，最低顶点接地。网格/UV 签名不变；未改接地几何、贴图、粗糙度或 NormalMap 强度。
- 官方原始色图 sRGB；NormalGL、ARM 为 Non-Color，ARM G 为粗糙度、B 为金属度。沿用 P12：ARM R 保留在原图，本轮不另乘入色图，接触阴影来自实际几何与光照。
- 3 张 1024² 图在本次打开源后实际读取像素并核对路径/哈希。`result.json` 保存相机、原输入哈希、尺寸与材质图记录。
- 来源：Poly Haven [Rock 07](https://polyhaven.com/a/rock_07)，作者 Jenelle van Heerden，[CC0](https://polyhaven.com/license)；完整下载 URL/哈希见 `../p12/inputs/polyhaven_rock_07_1k/provenance.json`。

首轮 PID22136 在 1.372s 自然 exit3：Blender 新 World 没有默认 `Background` 节点，尚未渲染。`render_sample_failed_01.py` 与同时间戳日志保留。唯一修复为显式建立 Background → World Output。重跑 PID35268 CPU2，在 67.385s 自然 exit0，120s 自有进程树上限未触发；完成后立即归还引擎窗口。没有追加渲染。

PNG SHA256：`e4bf0e90315f1f65cc12aa732e7366087959fabb1daac39503db8fdd1a54568e`。
冻结 P12 源 SHA256 仍为 `9243d28066712f8d34aae4e532cf47eb97adc23bc46befd24ef89ff6c1e69291`。

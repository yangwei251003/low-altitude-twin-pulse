# H10 P11 候选接口

本文件描述独立 H10 候选，不授权替换运行 P2 或量产其他高度。最终文件哈希、原始 GLB 节点变换、图与实测以本目录 `p11_export_report.json`、`p11_glb_readback.json`、`manifest.json` 为准。

候选路径：`assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb`。

| 节点 | 用途与坐标（Godot Y-up） |
|---|---|
| RootButtressH10 | 资产根，保持模型地面原点；使用实际导出变换，不额外猜测Z-up修正 |
| RockMasses | 连续闭合主岩体，静态三角碰撞 |
| LivingRoots | 两条独立天然粗叉源在导出副本合并；静态三角碰撞 |
| SapKnot | 保留原几何/UV/变换的独立琥珀靶；包装需保留实际碰撞及entity_id |
| GroundOrigin | (0,0,0) |
| BodyPerch | (0,13,0) |
| HostTarget | (0,11,4.5) |
| LowerShelf | (-3.7,5,3.2) |

没有 BarkPlates/MossDetails 装饰组，本候选没有额外苔片。材质只有石、根、原Sap三类；不以节点缺失补造装饰或碰撞。源 `.blend` 保留 RockMasses、Root_FrontSap、Root_RightFork、SapKnot，合并仅发生在导出副本。

四足接触中心 XZ：(-2.54,2.17)、(2.51,2.22)、(-2.28,-2.50)、(2.31,-2.48)，各 R0.75 的193个向下探针应为Y10。实际三条靶射线从(0,11,8)、(-3,12,8)、(3,12,8)指向HostTarget，根必须真实接入Sap体积而不是浮置宝石。

所有渲染图为 CPU 离线，`h10_p11_same_byte_glb_preview.png` 已由真正删源、回导冻结 GLB 生成，`p11_glb_readback.json` 的 37 项实际检查全过。源图不等于运行画面。完整冠兽体积与迁移/逼落扫掠、Godot真实照明与性能由根线程另行验证。

GLB 冻结 SHA256：`d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f`；8,530,596 字节，63,996 三角，3 网格/3 材质/9 张内嵌图。原始 GLB 根与三网格没有额外缩放或旋转，锚点直接为表中 Y-up 位移。每个材质使用唯一 `TEXCOORD_0`。实际包围 min=(-6.55000019,0,-6.66439295)，max=(6.66439295,11.77999973,6.66439295)。

已知美术差距：宽平顶、后脊规则斜坡、前根扁带/断端感仍保留；不是最终美术通过。P10与所有运行P2文件保持原字节。

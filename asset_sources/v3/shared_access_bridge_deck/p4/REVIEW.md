# P4 实际源三图与进入交付候选的边界

2026-10-19，Blender 5.2.1 LTS，CPU 2、16 samples、1400×1050，沿用 P1–P3 相机/照明。PID 41484 自然退出 0，外部墙钟 147.828 秒，240 秒时限未触发；[原始日志](run-20261019_075431_54f309/blender.log)与启动/退出记录保留。没有烘焙、GLB、Godot 或运行文件修改。

根线程和制作代理均实际逐张查看了[斜视](source_review_01/01-oblique.png)、[小车下方](source_review_01/02-bogies-underneath.png)、[锁件近景](source_review_01/03-lock-closeup.png)。根批准以当前自然碎漆/使用痕迹进入显式 GLB 候选制作，**不是最终美术验收**。

## 实际结果

- 12 个网格、5 个源材质、20 个材质面、10,912 个 evaluated 三角（构造层 9,664）。逐件几何、父级、姿态和包络与 P3 完全相同；护板承肩继续保留。
- 缩回态 AABB：X[-3,3]、Y[-0.7599999905,1.1999988556]、Z[-2.0599999428,1.7000000477]。插销插入态最低 Y=-1m。
- [24/24 原文件读回](source_review_01/readback_validation.json)核对源/输出字节、12 件几何、UV 层、原图、相机与自然退出，不把这种检查称为视觉或性能验收。
- P3 白色椭圆盐斑、橙色短椭圆滴刷及亮白甲板擦痕已消失。碎漆/细锈流比旧程序遮罩自然；甲板暗磨擦保留防滑凸纹层次。
- 宽面油漆仍较参考明亮，底部破损仍略连续，轮组/锁杆偏清洁；这些作为后续游戏镜头观察限制保留，不在本轮无限重调宏观材质。

## 已定位的局部 UV 修正

BridgeDeck 短端和护板窄 X 端盖使用 `U=(X+3)/6`，X 恒定的面退化为一维采样，在三图可见条纹。长护板真实 6×1m 主表面映射正确；“全范围 0…1”检查不能证明所有窄端面映射正确。下一交付副本只按端面法向改用 Z/Y 投影与同幅原图安静区，不改主体几何、其他面或原图像素。P4 原 `.blend`、脚本和图片不覆盖。

原 `source_report.json` 的 `p4_only_geometry_change` 文案沿用了 P3 承肩描述；实际是 **P4 相对 P3 无几何变化**，由 `geometry.py` 相同 SHA 和逐件报告证明，不把承肩重复计为 P4 改动。

## 原始字节

| 文件 | bytes | SHA256 |
|---|---:|---|
| `shared_access_bridge_deck_p4.blend` | 350122 | `81b545bd88a3f4017d7a04e2c16f9bef9bf7a71f046be34d5d457727024d952e` |
| `01-oblique.png` | 1440040 | `68b37c998f829af38d84b7ea55402feb79ab1a503bcd10a7238cf467d34a90bb` |
| `02-bogies-underneath.png` | 1365004 | `4eab42797fbf14319de5176e928e49454228d6234cb158fb9586af67a61e1c6c` |
| `03-lock-closeup.png` | 1547727 | `6cc0b9db78284e29242a86eea953e64c7e4d02d1bfedba2999bbedf438c86d33` |
| `source_report.json` | 33251 | `123e6770eca3abf3420907784f40d4aaae58ca5bfae68ad0d94cea66e70e5b3f` |
| `readback_validation.json` | 3231 | `ef3b14502ba91189fb4d2b1b952119014506b624aea15bffc939fcd234dc9f75` |

原日志 SHA256：`c4933d3c0f44274ecee010199d5a4c93815ac46746a00884186dad8dc76a14f8`。原图/原 P3 证据均未修改。下一步须使用独立交付目录，保留显式源 UV/角点属性、完整可编辑源，并验证真实 PBR 图像、12 件导出/同字节回导；这些当前仍待运行。

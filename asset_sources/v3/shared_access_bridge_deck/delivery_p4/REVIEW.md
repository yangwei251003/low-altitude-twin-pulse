# P4 完整可编辑源 / 原生 PBR / 12 件 GLB 候选

2026-10-19。原生烘焙、显式 GLB 和同字节回导预览实际完成，全部进程已自然退出，CPU/GPU窗口已归还。制作代理已实际看[GLB回导斜视](same_byte_reimport/01-oblique.png)：P4批准的自然碎漆保持，短端条纹消失，甲板真实防滑凸纹与板缝可读，没有观察到新的宏观材质退步。仍是离线单件候选，**不是游戏截图、最终美术/性能/通行验收**。

## 原字节与结构

| 交付 | bytes | SHA256 |
|---|---:|---|
| `shared_access_bridge_deck.glb` | 4442516 | `ea8aa0e10f35a637c7deef341471de771e364d9db938f502bd387cb41b9a7c28` |
| `shared_access_bridge_deck_editable.blend` | 346373 | `206bce235a67021b5d1aa7f93a47d1b779e1caea33705af44568ab3812bb7f6f` |
| `shared_access_bridge_deck_delivery.blend` | 429798 | `1fe760a9e8008a768605eb9f03702d701a220afafefd78d0145ba725e5c8d480` |
| `same_byte_reimport/01-oblique.png` | 1424334 | `aa2dee09cf3c81de0d2819e7ede23cbd1241acbd6df66c7e4812148749223cfe` |

实际12 Mesh、12材质面、1 PBR材质、10,912三角、20节点；共同2048²三图集。P4原几何/角点法线指纹修UV前后严格相同；只修改BridgeDeck/两护板102个X朝向源面的PaintPanelUV，完整面/循环前后值在[end_uv_correction.json](end_uv_correction.json)。原P4源/图不覆盖。

真实GLB矩阵、父级、逐件accessor局部界限、三角计数和内嵌图像在[raw_glb_report.json](raw_glb_report.json)。总根和MovingDeck/LockPin为identity；各mesh保留原center translation，**不能当作所有节点identity**。缩回整体界限X[-3,3]、Y[-.7599999905,1.1999988556]、Z[-2.0599999428,1.7000000477]；同字节回导真实移动LockPin到-Y.3后最低Y=-1。

12件三角与带绕序三角多重集匹配；源位置到GLB误差0、UV最大2.98e-8。法线使用仓库已验证Blender5.2.1导出器float32 round(4)后normalize规则，期望到GLB最大1.19e-7；原源法线到GLB量化差6.32e-5单独保留，未用宽松位置误差掩盖。12件同字节回导的父级/位置/三角/单材质实例及真实插销行程再次核对。

## 贴图与可编辑性

- BaseColor：2,436,932B，SHA `a675fc9b57adf16fe9dbadbc7092eee8d15ed3c365eb47db283fbe7c78ba18f5`，sRGB。
- ORM：1,010,661B，SHA `94904cfe408a5801875f85323fffc90d7c8a21df99e26267380cbcab56f7c60b`，Non-Color，R恒1/G作者粗糙/B作者金属；未烘光照/AO。
- Normal：60,682B，SHA `bcae02918c836b6d57e6433b4a0855bf46a6b1b4ecd93e12ab5083b8e4256b0e`，Non-Color，切线+Y；真实防滑几何仍在，不用法线代替。

三图原PNG字节均与GLB内嵌PNG完全相同。真实源角点属性在evaluated复制、新图集展开前后完全相同；实际UV有效且所有三角非退化。smart_project图集有效面积约50.96%，不把该检查扩称为独立穷举UV重叠证明。

`shared_access_bridge_deck_editable.blend`保留12件原几何和modifiers、程序源材质、修正显式UV；其图像指向本交付目录完整`source_inputs/`原图，未对像素改色/裁切。它当前保留本机绝对图像引用，搬迁工程时可重连同目录原图；最终`shared_access_bridge_deck_delivery.blend`已重开验证相对纹理路径。原P4源亦保留，完整制作和交付脚本可复现。

## 运行与失败记录

1. `run-20261019_080954_783daf`：PID27188，1.156秒exit1。图像reload后直接查has_data，尚未读懒加载pixels；原脚本在`failed_01_lazy_image/`。未烘焙。
2. `run-20261019_081135_488d74`：bake PID31428自然exit0，内部12.780秒，三个通道一次完成，各checkpoint保存。export PID28112在delivery重开后的相同懒加载检查停下，未写GLB；原脚本/该次delivery副本保存在`failed_02_export_lazy_image/`。
3. 仅补实际pixels读取，未改材质/原图/几何，未重新烘焙任何成功通道。`run-20261019_081242_918c05` export PID3304自然exit0，墙钟3.75秒。
4. `run-20261019_081255_9bac3a`同字节回导PID7088自然exit0，墙钟46.610秒，原01机位/光照/16samples/1400×1050；没有缩图/后期。

成功阶段无执行错误；export只有Blender6.0将移除Material.use_nodes的弃用提示。所有失败与成功原始stdout/stderr保留，不把失败阶段称全程一次通过。

## 交接边界

未写`assets/`，未启动Godot。根需按同字节复制后统一import，并验证原body/隐藏Visual、完整运动包络、目标/锁销不淡出和固定游戏相机。模型中心不等于body当前位置：挂接须保留模型根到mesh的累计authored变换，再施加`Transform(ORIGIN-layout spec.center)*authored`，ORIGIN=(15,5,0)。未扩大旧碰撞，不修改权威规则。风化宽带/轮组清洁度与防滑高频在常用26m镜头仍需根实看。

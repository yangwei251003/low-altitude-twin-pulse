# I2 中部检修坪 P1 — 静态制作候选

沿用 route `5e455d78-37b2-423b-b660-0cc3185eae49`。当前完成代码与 CPU 裁域检查，并已核对 Root 的095828实时World导出；本代理没有启动 Blender/Godot、生成新图或改运行资产。等待 Root 授权一次源预览。

## 范围与空间职责

- 世界框 X[-13.25,8.4]、Z[-10,10.5]，顶 Y0。它是裁剪框，不是可填满的矩形地板。
- Godot 底面原点 `(-2.425,0,0.25)`；Blender local `(worldX+2.425, -(worldZ-.25), worldY)`，单位米，源 mesh identity。
- 读取实际院坪安装后的 remainder105原三角，逐三角裁分；静态替换约336.2118m²。原296.5806m²连续院坪、288m²板院、检修井/坡、维护地坪与水岸均不覆盖。
- 实体基脚、两屋、泵房Floor/墙脚及 UnderDeckFloor 原16m²足迹扣除。抬高地台不能被改成Y0平路。高处移动机构只按真实3D扫域核验，不因其XZ投影虚构地面孔洞。
- 输入原有微米级裂缝/点接触保留；不snap、不凸包、不补环。浮点共线残片只记录真实储存退化，不作为新洞口。
- 现有碰撞保持。本件所有表面/密封条均Y0，切缝是材质分区，不声明有物理凹槽、排水网、交互盖板。

## 一件连续场地的构图

- 横向主通路 Z[0,3.75]，接西屋前缘与东侧工作区；北南宽通路 X[-1.75,8.4] 连到已完成院坪。
- T形通路暖中灰，设备下方为较深低反射维护面；板距主要3–6m，随既有基础边界结束，不均匀铺小砖。
- 仅一处1.5×.8m锯切维修区（含20mm边缝），位置 X[-5.5,-4]、Z[.35,1.15]。没有重复排水沟/标线/石堆，也不暗示泵房北面有门。
- 少量沿维护方向的低对比使用痕以顶点色保留可编辑性；不是光照烘入底色。主面保留安静空间。

## 参考和材料继承

引用 `references/v3/production/central_service_apron/inherited_yard_reference_v1.png`，与已批准yard单件参考原字节相同，来源见同目录provenance.json。它仅定义I-B宽面混凝土/修补语言；本件不是把12×4参考拉伸成场地，也不继承图中排水位置、18cm展示厚边和碎石肩。

直接复用已批准revision2院坪的native2K混凝土BaseColor/ORM/Normal三图，完整SHA见inputs.json，米制周期3.6m。BaseColor sRGB，ORM/Normal Non-Color；ORM R=1无AO，G粗糙、B金属。Normal接RuntimeUV tangent强度1仅一次；原缓存测量近中性，不声称明显微起伏。

三材质：ApronConcrete、ApronMaintenance（同缓存乘.64，低频使用纹）、ApronJoint（既有密封胶色/roughness.95）。约30件编辑分板；预计1148tri；以后可合3mesh但本阶段不导出。原输入UV/法线/切线保留角点属性与三角对应记录，材质使用新的世界米制RuntimeUV。

## 当前证据与后续入口

`prepare_static.py`仅CPU读取/裁剪、AST/JSON解析、逐原三角守恒、独立集合差核对、UnderDeckFloor零覆盖及float32三角数。旧输入仅证明静态方案，不替代新实时验证。

实时补证：`artifacts/v3/central-ground-20261020_095828/geometry.json` SHA `5a854ff84970fedfb54764158ea039f4ef4f45f6707b63f1867b2127d456ccef`，Root只读World build PID304/6.125秒/exit0/0残留，七输入前后不变。四原始数组与历史余面逐字节一致；新源ID改用当前remainder的0–104，不复用旧pre-yard编号。`verify_live.py`已实跑，报告/原字节输入副本见live_verification.json与live_input；选域336.2117846568m²，1148tri，最大逐原三角面积差1.42e−14m²，独立集合差4.75e−15m²，UnderDeckFloor覆盖0。Ground碰撞SHA `d665779e1312e2783a2992ab30538164394a3d7d31e76fa8221ba242d9e709fc` 由该只读导出保全；这不是MAIN、图形或新物理测试。

预览入口：`run_preview.py --live-geometry <Root新导出geometry.json> --group <实际group> --sha256 <新manifestSHA>`。它拒绝直接把历史062538 manifest当新实时输入，要求本目录prepared锁与源布局/上下文资产SHA正确。

唯一图：固定游戏斜视方向的完整中部源视图，含只读真实两屋/固定平台/水箱/泵房/接诊/井及院坪，图中上下文不属于新资产。完整框适配缩放不等于实际26m游戏截图；正式MAIN26m需Root后续验证T形用途与通行口。

预计构建/重开10–20秒、1440×1080单图60–110秒，CPU2/private Job硬180秒；预计峰值内存约3GiB，尚未实测。本阶段零烘焙，后续沿共享三图直接导出，避免整场大atlas与重复烘焙。实际模型/图未通过前不放候选GLB。

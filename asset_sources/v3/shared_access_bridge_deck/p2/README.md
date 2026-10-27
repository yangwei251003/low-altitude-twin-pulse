# P2 静态修正，待源渲染

2026-10-19。P1三图已由根实际查看并否决。本目录是独立P2副本，P1源、图、日志和报告未覆盖。当前仅普通Python编译/几何数据检查，**尚未运行Blender**；地面P9占用引擎窗口。

## 已证实原因与修正边界

1. **护板黑线有明确几何缺陷。** P1的web和上下hem分别是相交盒，Y0/Y1及端盖存在外露共面区域。P2改为同一个12角YZ折边截面沿X挤出，前后端盖按相同截面三角化；web与hem不再是相叠的三件。12个功能Mesh不变，连续实心护板、尺寸和碰撞合同不变。只静态证明新单件闭合与绕序，黑线实际消失仍待同镜头图。
2. **整块涂漆错误泛金属。** P1 `IB_BlueSteel` 默认Metallic=.56，`IB_OchreGrip`=.40，完整漆层也混入有色金属反射。官方Principled说明0为介电模型、1为纯金属反射：[Blender 5.2 LTS](https://docs.blender.org/manual/uk/latest/render/shader_nodes/shader/principled.html)。P2两种涂漆默认0，仅真实折边/竖肋附近的有限chip mask同时改变底色和Metallic；其余大面保持介电涂漆。蓝绿基色压到`173d45..244b53`，深灰钢面`343e44..4a545a`；不改摄影棚照明/曝光藏问题。
3. **P1防滑纹的法线读取未产生可见结果。** 已证实源码将两路高频Wave经`GREATER_THAN`变为二值后相乘，Bump距离仅1mm/强度.32；三张实际图中可行走面近乎平滑。Bump根据局部高度差改变法线，平坦二值区域本身不形成连续坡度（[官方Bump说明](https://docs.blender.org/manual/en/3.1/render/shader_nodes/vector/bump.html)）；滤波/去噪是否吞掉边界是推断，尚未做逐节点实拍证明。不能把唯一UV层检查等同为法线正确。P2不继续调阈值：改成**360个真实2.8mm渐缩凸纹**，全部在原BridgeDeck一个网格中，顶Y0、底板仍连续；六块面板有4mm真实浅接缝，最高点不越原桥面。该高模可供后续烘焙，但本轮尚未烘焙或定运行低模。
4. **P1通用倒角浪费在微小重复边上。** P1实际25,712三角，双护板各7,996，其中大部分来自微小螺钉/轮件倒角。P2使用明确`bevel_weight_edge`仅选承重轮架、主护板、底板、导框的非共面硬边；螺钉、轮面和已建坡度的凸纹不再再倒角。[官方5.2倒角权重](https://docs.blender.org/manual/ka/5.2/modeling/modifiers/generate/bevel.html)。不为了数字缩小轮组或锁销。

盐迹也从满面长纵条收回到下缘少数竖肋旁，保留大块安静漆面。当前不新增imagegen材质图：已定位问题来自结构/涂层模型/凸纹高度表达，先验证这些修正，不借新图掩盖错误。若后续需要更可信的风化图集，可按根授权使用原生工具，但本次未生成。

## 静态结果与待验证

普通Python检查：12件、9,640个未倒角三角（含360凸纹），对应原包络内；各制造子件闭合/绕序/正体积检查通过。两护板主件各是单个闭合折边体。5材质、独立LockPin行程和其余节点关系保持。仍有设计上的螺钉/轮毂接触，不宣称整个零件已做Boolean并集或全局无交叠。

实际倒角后三角数、涂层读色、防滑可读性、黑线消失与UV范围均待Blender同三镜头验证；脚本新增UV min/max读回，桥面投影不能塌缩。源程序材质未烘焙，不称可用GLB PBR。原生产文件、参考V2和旧P1输入hash不变。

根释放窗口后才可执行一次CPU2/240秒外部时限，保留原日志；不自动重试、不写运行GLB：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --threads 2 --python-exit-code 1 --python 'asset_sources/v3/shared_access_bridge_deck/p2/build_source.py' -- --render --samples 16 --output source_review_01
```

三相机/1400×1050/16samples/AgX曝光.45沿用P1，文件名相同但在P2新目录。根先看三张原图再决定下一步，当前不预填通过。

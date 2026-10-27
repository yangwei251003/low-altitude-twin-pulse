# 泵房 V8 PBR / 显式 GLB 开发候选

**已执行并冻结，待实际 Godot 镜头与集成验证。** 输入为冻结 prototype_v8/pump_shell_prototype.blend，200个独立编辑件/13,600个 evaluated loop triangles。保留原编辑源和全部旧字节，最终合并仅发生在本独立交付目录的副本。运行assets新增仅本件，不改World/Works/布局/7碰撞。

根 ClinicPumpShell，顶点相对世界原点(-7,0,8)，Godot +Z为正门。所有根/子根/mesh本地identity：PermanentNavigation→FloorSurface、WallFeetAndJambs；OccludingCover→WestCover、EastCover、NorthCover、RoofCover。6 mesh / 1共享PBR材质 / 3内嵌图 / 13,600三角，不做减面。遮挡包装按对象复制需要的材质实例，原7个实体与机关均由root维护。

原源材质有显式MetricUV/PanelUV/FinishUV/SteelUV及四种角点属性。运行时从实际Principled有效上游核查，出现Generated/Object/Geometry Position或隐式向量材质立即失败；合并烘焙体按每个源loop-triangle复制全部UV/角点属性/法线，并逐值验证UV和属性，避免复制200物件逐次烘焙成本。该合并不是几何减面，不改变每个源三角的位置、winding和原UV输入。

单一临时体增加独立DeliveryBakeUV。原生Cycles CPU2，BaseColor用EMIT不含灯光；ORM用R=1/G=原实际roughness/B=原实际metallic（支持链接，不是假常量）；Normal用原生TANGENT bake，+X/+Y/+Z，匹配新BakeUV。输出2k是图集分辨率，不把1254源atlas/1k Metal012说成2k新增细节。三个PNG为sRGB色图、Non-Color ORM/Normal。8px边扩，源几何和材质保存在UV/每图完成checkpoint。

导出阶段从同一proxy按原面分组建6mesh，保留精确三角与BakeUV→SurfaceUV。标准Principled只有BaseColor、同图ORM分通道及NormalMap；Alpha=1、Emission=0、背面裁剪。只选择9个明确节点导出，不含相机/灯/背景/碰撞。导出先在本目录，rawGLB逐三角位置+winding、UV与法线比较、全节点identity、6组/1材质/3内嵌2kPNG与文件SHA匹配，过后实际同字节回导并渲染一图；完成才复制到assets/v3/clinic_pump_shell/clinic_pump_shell.glb和三个PNG。

来源：[ambientCG Metal012](https://ambientcg.com/view?id=Metal012)，[CC0许可](https://docs.ambientcg.com/license/)。只读取官方PNG，没有执行vendor .blend/.mtlx/.tres代码。原包和SHA记录由root保存在asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json；本交付会保留其原字节元数据副本。图像只原字节复制与Blender原生节点烘焙，不直接编辑生成图像像素。

分两次串行窗口，不能一口气自行运行：

1. `python run_delivery.py bake`：预计120–240秒，300秒自有树限；UV、BaseColor、ORM、Normal各checkpoint，失败保留，不自动重来。
2. root再次排期后 `python run_delivery.py export`：预计50–70秒，最终按root授权收紧为120秒自有树限；不重烘焙，rawGLB+同字节回导图。

## 实际执行与证据

烘焙 PID29840 自然 exit0，用时13.0455秒（实际烘焙脚本11.7544秒）。BaseColor、ORM、Normal均为2048²原生烘焙，保留UV与逐图checkpoint。三个原图已实际查看；BaseColor/ORM非空且色区对应，法线为非常浅的细纹：R123..132、G122..132、B255，共15,124像素的XY值偏离128超过2。没有为了增强观感凭空放大法线，这不替代引擎光照验收。

首轮导出 PID44268 在4.064秒 exit3，未发布或渲染。失败是自定的源法线误差阈值未考虑官方导出器四位量化，位置误差0、UV最大2.98e-8、三角多重集与朝向相同。原脚本、GLB、交付blend、期望三角、日志和诊断保存在 `failed_export_normal_threshold_v1/`；其GLB与最终GLB字节相同，失败属于验证语义，不把其原失败日志改成通过。

实际安装的Blender 5.2.1 glTF插件 `blender/exp/primitive_extract.py:1462` 用 `np.round(normals, ROUNDING_DIGIT)`，`io/com/constants.py:160` 定义4位，然后float32归一化。修正后的验证器按同一确定性映射比较，仍保留原差值：原源→GLB最大6.1690807e-5；量化预期→GLB最大1.1920929e-7。几何位置、winding、UV门槛未放宽，未改导出器/模型/贴图。

第二轮 PID26780 自然 exit0，用时41.956秒，包含raw二进制审查、删除源网格后的真实GLB重导入及离线图。两轮前后均核对V1–V8共165个冻结文件SHA相同。只在全部检查和回导渲染完成后复制到 `assets/v3/clinic_pump_shell/`。源编辑文件仍为V8的200独立件；本目录交付blend是六组合并副本。

GLB为10,149,560字节，SHA `7d5d51d8134967b890c26b0cc7f541096e882bb0ce463a51c2fc52a534cb7100`。局部AABB为 `(-5.25,0,-4.25)` 至 `(5.25,3.4979991913,4.25)`。六组分别224/1932/2916/2916/2916/2696三角；总13,600。全部9节点identity，6 surfaces共用1材质，3张内嵌PNG逐字节等于外部原生烘焙图。UV仅TEXCOORD_0，源位置误差0，UV误差2.98e-8。详见 `raw_glb_report.json`、`delivery_report.json` 和 `visual_review.md`。

导出日志有“More than one shader node tex image used for a texture”的插件提示；实际同一ORM图的G/B被分别接入roughness/metallic。已通过raw验证只有1张共享ORM、3张总图且内嵌SHA完全相同；不把这条离线导出提示说成GPU告警或引擎通过。

离线候选通过不等于实际游戏材质/遮挡/性能/整区美术通过。默认镜头细节、物理通行、机关LOS和原7盒不变由root接入复验。

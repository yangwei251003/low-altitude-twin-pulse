# WestLandingPlatform 候选交付

Root已亲看单件源并接受进入交付；本件尚未声明实际游戏通过。

GLB：`assets/v3/candidates/west_landing_platform/west_landing_platform.glb`，7,066,076B。
SHA256：`a5291b3b620522550b0e59f1e48eb6f4e7c0a556eb05796c53c2f388c25e4af5`。

| Identity层级 | 三角 | 共享材质 |
|---|---:|---|
| WestLandingPlatform / PlatformAssembly / PlatformSteel | 672 | Steel |
| WestLandingPlatform / PlatformAssembly / PlatformPaint | 660 | Paint |
| WestLandingPlatform / LegAssembly / LegSteel | 960 | Steel |
| WestLandingPlatform / LegAssembly / LegPaint | 836 | Paint |

总3,128tri/4mesh/2material/6内嵌PNG。无碰撞/相机/灯/动画；不导入高模浅肋。
源底心世界(-6,0,-4)，Godot Y-up。Platform局部[-4,4.6,-2]..[4,5,2]；Leg[-3.6,0,1]..[-3.1,4.6,1.5]。
Root若分别挂原两body，Platform补偿平移(0,-4.8,0)，Leg补偿(3.35,-2.3,-1.25)；保持原Box/活动端/标线职责。
这两个补偿值是当前layout中心推算，最终安装器仍应从实际body transform核验。

源可编辑：`../p1/west_landing_platform_editable.blend`及其`source_inputs/`5原PNG。
源106低模编辑件+8高模条肋件；保存源SHA `a7908e2e3a114f8a0a73bfb26e7216698b941a51de92f5915c1d2df3608d9105`。
交付源：`west_landing_platform_delivery.blend`，与6张`textures/`同存；根/组/mesh都是identity。
钢材复用ambientCG Metal012/CC0四原图；青漆复用项目原生imagegen atlas，像素未编辑。来源见`provenance/`。

Steel：BaseColor/ORM/Normal 2K；Paint：同三图1K。每类只烘一次，共享两body。
8钢板顶面8独立大UV区，约331.53×344.11px/m；其他面为次级区。钢Normal来自逐板匹配的真实浅肋和原细法线(.25一次)；导出NormalMap强度1，不再重复施.25。
漆Normal实际中性8bit(128,128,255)。ORM R=1，无新AO/烘灯光；微凸不以复杂色图假造宏观破损。

实际检查：raw GLB三角/绕序/UV/法线/父组/逐体包络、2材质共享和6原PNG内嵌SHA；同字节回导位置0、UV2.98e−8、最大法线角0.011724°。
源预览已检查；没有新增离线GLB图。实际平台高/低位、遮挡及MAIN同光效果由Root验证。
源偏冷/钢面较均匀/边蚀线性为已知参考差异，未追加离线调色。

第一源严格SHA失败保留：Bevel后非活动UV末位不一致；原几何/绕序/法线/MetricUV严格不变，最大1.19209e−7（2K下0.000244像素），经真实逐loop读回后续图。原失败不被成功报告覆盖。
制作进程：source续图PID17228/54.485s；bake11584/42.375s；export35064/4.484s。均CPU2/private Job、0残留。

精选清单`selected_files.txt`与`manifest.json`供Root精确提交；不包含UV/bake中间大blend、重复input_snapshot或.blend1。

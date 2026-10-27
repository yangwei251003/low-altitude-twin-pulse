# P1 WestLanding源合同

- 整体底心世界(-6,0,-4)，Blender坐标`(localX,-localZ,localY)`。
- 根`WestLandingPlatform`，两identity父组`PlatformAssembly`与`LegAssembly`。
- Platform逐件限定局部X[-4,4]/Y[4.6,5]/Z[-2,2]。
- Leg逐件限定局部X[-3.6,-3.1]/Y[0,4.6]/Z[1,1.5]。
- 检查各组实际边界、每件闭合/正体积、UV有限值和原图实际pixels；不以全件AABB代替两Box并集。
- 低模106编辑件/3,128tri；未来合成PlatformSteel(672)、PlatformPaint(660)、LegSteel(960)、LegPaint(836)。
- 8件可编辑浅肋源/92,928tri有`high_source`和`not_runtime_geometry`标记，只供Normal烘焙。
- 2共享材质，计划Steel2K与Paint1K，6张标准PBR图；此阶段不烘焙、不导GLB。
- 无新增脚座/柱/斜撑/栏杆/灯/碰撞；WestBearingLine与移动Deck由Root保留。
- 原始失败与后续数值容差证据并存，不将退出0等同美术通过。

`run_preview.py`是首次构建入口；首轮已保留重开SHA失败，不能不经新版本直接重跑覆盖源。
`run_resume_preview.py`只读两份已存源、实测evaluated UV末位差并继续同一镜头；不保存任何blend。
所有运行经`dev.execute_command`隐藏私有Windows Job/CPU2/有界180s；只在Root授予窗口执行。

源输入是原泵房atlas与Metal012的5张原PNG；`source_inputs/`为逐字节副本，blend保存为可解析相对路径。
许可来自`asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json`；不加载第三方blend或脚本。
源预览使用中性AgX固定照明，不是实际MAIN、性能、控制或碰撞试飞证据。

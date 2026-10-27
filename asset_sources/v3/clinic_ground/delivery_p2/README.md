# Clinic ground P2 显式GLB准备

**SOURCE_GLB_READY_FOR_ROOT_IMPORT**。已在授权CPU2窗口执行一次，PID31232，3.59秒自然exit0；窗口立即交还。原始二进制25/25检查通过，根可复制接入首块实际镜头。补丁偏规整、湿尘较弱仍记录，不再堆全域脏噪；未在本任务运行Godot或GLB回导渲染。

冻结产物 `clinic_ground_p2.glb`，9,444,352 bytes，SHA256 `03e063e4f5e77468b9d1770c7a29686e600fdafce07a537a6018e45c1cc2a691`。实际3276三角、两mesh/两surface/一材质，根及子节点全部identity；源和4张PNG字节未变。原始结果见 `delivery_report.json`，不以文件检查替代游戏视觉/碰撞验收。

输入 `../p2/clinic_ground_p2.blend` SHA256 `db2fc7404c5f39be93339b541e9f15c96c6bd5a5b9f93b176ce3cac6a90cc8cf`。77编辑件及四张原生2k贴图全部只读；不保存回源、不重烘焙、不重新生成图像。导出器仅复制evaluated网格后合并临时副本，删除未使用槽位，保持三角及UV角点对应。

| 导出节点 | 原源组 | 编辑件 | 已知实际三角 | 合同 |
| --- | --- | ---: | ---: | --- |
| ClinicGroundModule | 顶面中心原点 | — | — | identity空父节点；Godot Y向上 |
| SlabsAndSeals | ConcreteSurface | 10 | 680 | 单mesh/surface；大板+封缝 |
| DrainAndHardware | DrainAssembly | 67 | 2596 | 单mesh/surface；槽底/端壁/框/栅/螺栓 |

合计3276三角，2 meshes / 2 surfaces / 1共享 `CGround_BakedPBR`。无灯、相机、预览地板、碰撞、隐藏旧源或动画。模型局部包围盒目标X/Z±3，Y[-0.18000000715,0]；不把源厚度浮点误差伪装成新尺寸。三个节点全部identity；首个集成位置建议世界(-19,0,15)，实际由根控制。

四张已有烘焙图：BaseColor sRGB；Roughness/Metallic/Normal Non-Color。仅标准Principled、UVMap、Image与NormalMap节点导出；最终零有效Emission。Blender原生glTF导出器负责将已有粗糙/金属图组合为标准G/B通道，不经自写像素处理或重烘焙。预期GLB内嵌3张PNG（基色、MR、法线），4张原烘焙PNG仍独立留源。导出后逐项读回二进制，不能只依赖Blender界面。

实际内嵌三张2048²PNG已读回：BaseColor与Normal字节严格等于原烘焙文件；MR SHA `fbf75ebd885ddb02bbee30561e1a8a038c7f8b42df3048b090f4154071347901`，由原生导出器生成。三个textureInfo均使用UV0；材质实际OPAQUE、doubleSided=true、无Emission和Unlit扩展。日志保留原生“同一输出texture使用多个Image节点，采用第一个sampler”警告；本件是粗糙/金属双输入合图，三个导出贴图共享同一sampler。未隐去该警告或宣称日志完全无警告；另有未来Blender6的use_nodes弃用提示，不影响本次5.2.1执行。

验证：原编辑源和四图SHA未变；合并前后有向三角多重集及UV角点严格相等；原始GLB3276三角/两组包围/UV0/法线/identity/node范围；UV0按glTF V翻转后与源角点严格匹配；材质三类贴图都绑定UV0，基色和法线内嵌字节与源PNG相等；MR由原生导出器合成并记录哈希，内嵌图实际尺寸2048²。若任一失败保留GLB但禁止集成，不放宽断言。

运行：`python ./asset_sources/v3/clinic_ground/delivery_p2/run_export.py`。预计10–30秒，CPU2、自身进程树180秒上限；不渲染不烘焙。产物仅本源目录 `clinic_ground_p2.glb`、实际报告和日志；不写assets或共享布局。执行后立即释放窗口。

运行碰撞合同：仍使用根已有Ground Y0保守平面，20mm窄封缝/实际75mm槽底不会新增可进入空间。早期约60mm是概念近似，真实源槽底为Y−0.075；不能把此模块称为物理排水网或积水互动。视觉须由根从旧Ground可见顶面切出6×6占位，保留旧碰撞；禁止共面叠加或抬高整个模块避免闪烁。GLB读回不是Godot真实光照、飞行/落地或整区美术通过。

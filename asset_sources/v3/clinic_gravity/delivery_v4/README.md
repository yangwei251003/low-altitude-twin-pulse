# Gravity v4 显式 GLB 源目录交付

状态：Blender CPU2 显式导出完成，PID 32720，exit 0，实际进程历时 2.431 秒；14 项实际二进制检查全部通过。唯一输出目录为此目录；未写运行 `assets`，未另存/覆盖 v4 编辑源，未启动 Godot。

冻结输出 `clinic_gravity_v4.glb`：7,624,932 字节，SHA256 `87b596b5bb5f4cb66e40d7a019ce9167b1eb3c1d406a5d66d086d3728fa0710e`。实际 5 meshes / 5 surfaces / 2 materials / 14,296 triangles，3 张内嵌 PNG（基础色、法线、官方导出器打包的粗糙度/金属度）。

输入 `../revision_v4/clinic_gravity_material_v4.blend`，SHA `f2e574f60c72a8763ecbf16b8253ff558eb7238d29e8f3f35ac311fd0daffa40`。每个独立编辑件保持在输入文件中。导出时读取 evaluated geometry，临时复制并烘入物体变换后才合并；删除无用材质槽，保留 UV 和既有 PBR，原始 `.blend` 不保存。

| GLB 节点/网格 | 来源 | 实际源件数 | 碰撞职责 |
|---|---|---:|---|
| DeckStructure | 原 DeckAssembly_VisibleUnion，包括既有柱梁/台体 | 1 | 根现有固定 solid 保留 |
| CisternStructure | 原罐壁/框、完整盖、注水颈帽、封帽接口 | 13 | 根现有固定 solid 保留 |
| DeckDetails | 台边角钢/护角/接缝盖条/柱连接及其紧固件 | 129 | 根从实际 mesh 另做补充三角碰撞 |
| CisternDetails | 窗压框/密封/黄色护角/侧接缝/刻度及罐紧固件 | 54 | 根从实际 mesh 另做补充三角碰撞 |
| CisternWindow | 独立玻璃 | 1 | 不合入金属材质，根按既有窗体物理处理 |

上表已在实际导出时重新枚举确认；未知可见件会报错，不能默默漏出。详细源件名字和每组实际三角数、包围盒见 `delivery_report.json`。

模型放置原点是 Godot 世界 `(-9,6,-7)`；源 Blender 局部为 `(worldX+9, -(worldZ+7), worldY-6)`，glTF 导出转换 Y-up。所有五个 mesh、`ClinicGravityAssembly` 根节点和 `SourceWaterBase` 空节点实际导出 transform 均为 identity；空节点局部 `(0,0,0)`。实际局部 Godot AABB 为 `[-3.0180001259,-6,-3.0180001259]..[4.0180001259,3.2399997711,2.6180000305]`。

水预览、演示地板/相机/灯、隐藏原件与作者节点平面全不选入。玻璃保持单独标准 Principled，其他四组共享 `CG_V4_BakedPBR`。输入 4 张 PBR PNG，glTF 官方导出器可能将 Roughness/Metallic 打包为一张嵌入图；实际嵌入数另报，不能机械声称 GLB 内仍是 4 张。生成材质图输入与复杂作者节点树不进入运行材质。

已执行命令（重跑仍需根安排窗口，当前字节冻结）：

`python ./asset_sources/v3/clinic_gravity/delivery_v4/run_export_v4.py`

CPU2，无渲染，180 秒仅自身子进程超时。实际二进制读回验证 5 网格、每件 1 surface、节点 identity、嵌入图片、独立透明窗，以及每组有向 float32 三角多重集与 evaluated 临时副本严格一致；另检输入源 SHA 未变。标准错误只有 Blender 6.0 将移除 `Material.use_nodes` 的弃用提示；本次 Blender 5.2.1 成功退出。

四组实体共享 `CG_V4_BakedPBR`，窗使用 `CG_V3_ClearObservationPane`（alpha BLEND，0.035）。保留独立窗不代表引擎透明排序已验收。水必须由游戏独立高度驱动，本 GLB 不包含预览水。静态几何/字节检查不等于 Godot 真实碰撞、光照、透明排序、游戏镜头或整区美术通过；这些留给根线程接入后验证。

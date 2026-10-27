# WestOffsetRoom — source-approved candidate

2026-10-20，Root已亲看修后源图，对比例、上下检修带、双百叶背板与三块低亮屋面批准进入候选。当前为**可编辑源、PBR和同字节GLB数值回导通过**；实际Godot五镜头由Root接手，尚未据此宣称游戏或整区美术通过。

## 交付契约

- 候选：`assets/v3/candidates/west_offset_room/west_offset_room.glb`，4,568,736 B。
- SHA256：`bea2bb84e42705e8b38b229d5dde0e4417326e56fad91a9e43ff1632f3ad6c65`。
- 根 `WestOffsetRoom`，底心世界原点 `(-12.5,0,-2.5)`；Godot本地AABB `[-1.5,0,-2.5]..[1.5,4.1000003815,2.5]`。最高值0.381µm为float32表示误差。
- 根与3个mesh均identity；每mesh一个surface/一种opaque PBR，无灯、相机、动画、碰撞。
- `PaintedShell` **3256tri**，`ConcreteBase` **220tri**，`RoofMetal` **2220tri**，合计**5696tri**。
- 9张1024² PNG内嵌，3组BaseColor/ORM/Normal；BaseColor=sRGB，其余Non-Color。ORM为R=1、G粗糙度、B金属度；没有AO烘焙或灯光烘入底色。
- 仅Root安装到原WestOffsetRoof；完整Box实体及遮挡父级保持。1m邻屋缝不是1.4m机体可通过路线，不填缝、不改变布局。

## 可恢复制作源

`west_offset_room_editable.blend`保留**184独立编辑件**、原始源UV/材质和非破坏倒角。SHA256 `09d0c6711f78a8dd64cd34bd52cd9833e402db931659628a81a025bb5b9c83a8`；烘焙/导出前后未变。所有部件独立闭合、正体积；这些检查不等于全体叠合部件进行了自交零重叠证明。工程端接/内部实体交叠不伪称单壳。

原图放`source_inputs/`，已在最终源上下文解析`bpy.path.abspath`、SHA、尺寸并读真实像素；保存前先绝对解析，再写本目录相对路径。来源、许可、原始URL和原图SHA见`source_material_provenance.json`。沿用已批准泵房imagegen色图和ambientCG Metal012 CC0的Color/Roughness/Metalness/NormalGL；没有执行外部blend或原材质脚本。概念图没有直接贴到模型。

`west_offset_room_delivery.blend`保留最终identity三mesh/三烘焙材质，依赖`textures/`九图，可直接重导。源模型按3×5×4.1m独立构造，不是低屋非等比拉伸；窄面两列上下板，长东面两组各八片实体百叶，后有闭合不透明背板。三大屋面是Root明确批准的参考简化，避免细密条缝。

源材质浅微起伏在1K/8bit结果里非常弱：PaintedShell与ConcreteBase Normal全图量化为中性(128,128,255)，不宣称存在可读的纹理起伏。RoofMetal RG约126..129，轻微扫描法线保留。面板/倒角/百叶/施工缝的轮廓来自真实几何。原始Normal强度只在源节点中应用一次，最终NormalMap强度1。

## 实际验证与失败保留

| 阶段 | PID | 秒 | 结果 |
|---|---:|---:|---|
| 首源图 | 11488 | 55.687 | exit0/0残留；艺术退回中柱交接黑块 |
| 确定性端接修正源图 | 30868 | 56.875 | exit0/0残留；Root实看批准 |
| 九图烘焙+源重开 | 43204 | 11.891 | exit0/0残留，图像实际像素finite |
| GLB导出+原字节数值回导 | 29052 | 4.219 | exit0/0残留 |

全部通过`run_stage.py`调用项目`dev.execute_command`隐藏私有Windows Job、CPU2，源180s/烘焙180s/导出90s上限；没有共享进程终止、无后台残留。原始process/log保留于各`run_*`。第一轮南北中柱与横梁的外表面共面，图上出现黑方块；仅把中柱改成横梁上下端接的两段，材质/相机/其余形体不变。原失败脚本、原源、原图和报告均在`failed_midband_overlap/`，精选manifest保留关键证据但不重复提交大blend。

实际二进制GLB验证：原三角绕序/多重集、位置、UV0、切线、材质通道与9内嵌PNG原SHA；再导入同SHA字节。回导最大位置误差0m、UV误差2.98023224e-8、法线角误差0.01243399°，无零法线或翻面，单位长度约0.99999987..1.00000012。raw glTF按安装版导出器float32四位量化后归一化检查；回导再编码按已批准≤0.1°可视容差，非声称法线位级相同。具体最坏角点及全部原数值见`raw_glb_report.json`和`export_report.json`。

## 视觉判断边界与下一步

已亲看修后`01-single-object.png`与批准参考，交接黑块消失、全部对象居中完整、上下结构与双百叶可读。Root同意进入实际MAIN检查；记录墙板比参考浅、百叶较蓝且沿边剥漆偏密。维持低屋同族材料，交实际游戏同光照判断，不新增离线色阶迭代。该图是离线源图，没有把它标成游戏画面，也没有重跑无收益的离线GLB全幅渲染。

只提交`selected_files.txt` / `delivery_manifest.json`精选文件：源、源依赖、九图、delivery blend、GLB、原参考、最少脚本/报告/实际过程与关键失败。排除UV/烘焙大中间blend、重复输入快照及blend1；全部旧产物仍在磁盘。冻结低屋63文件manifest SHA仍为 `9b95e8668282fec0ce83665723aabaea687ac0e1327f40baf880a07f007fb1a7`。

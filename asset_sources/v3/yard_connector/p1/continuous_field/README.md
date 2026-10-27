# 实际连续前场入口

当前代码已实现真实裁域逐三角分区与两套周期材质缓存；未运行 Blender。Root批准revision2为材质母版，当前直接制作约296.58m²的真实连续场地，不再烘12×4m样件。

下一次获准的唯一入口：

`python -B asset_sources/v3/yard_connector/p1/continuous_field/run_field.py preview`

- CPU2 / Cycles CPU / Windows私有Job180秒，预计120–180秒。只source+两图，自然结束后停止，不自动cache/export。
- 输入锁定 gameplay实际 `exports/20261020_062538_edcbfd/geometry.json`，SHA `d337d057cda1beadfa45f915a2c33900713174440e52b4f3d38a759c4bd536f1`。JSON内原117三角是权威，不将5数值分量/微环当设计岛。
- `field_geometry.py`逐原三角裁分并保留原face ID；`field_config.json`只定义宽用途分区。不会从轮廓凸包重填孔。原288m²/井/实际桥脚与护岸保护由最终输入排除。
- 约224m²安静混凝土，约69m²压实基层（其中仅4.398m²局部湿区），一处修补、一个2.2×.16m齐平排水，其余接缝。实数见`static_actual_partition.json`。
- 世界Y0主面保留；密封缝-8mm/排水闭底-15mm沿原保守Y0碰撞。源是视觉表面，不强造埋地封壳；无新高凸物/碰撞。
- Blender局部坐标为 `(worldX+5.7, 19.25-worldZ, worldY)`；导出回Godot时Root加(-5.7,0,19.25)。全部本件mesh identity。
- 既有院面8块及真实检修井GLB只读导入作两图上下文，标`review_context_only`，不混入新交付统计。第一图完整场地+旧院/井，第二图26m看井—院连接；均是Blender源图，不声称游戏镜头。
- 原灯光能量/发光面积同比扩大，保持revision2中性材质判断；不整体调暗来隐藏噪点。
- checkpoint保存后实际重开原四图，用abspath/hash/像素/尺寸检查。原GLB上下文内嵌图打包；所有外源输入运行前后hash保持。

后续独立授权才执行：

`python -B asset_sources/v3/yard_connector/p1/continuous_field/run_field.py cache`

`bake_shared.py`仅原生烘两套2K共享BaseColor/ORM/Normal，逐图checkpoint。混凝土色采样3.6m镜像周期，微Bump以4D环坐标周期化；土2.53m，原NormalMap强度.32只在源应用一次，缓存材质用1。R=1无新AO，混凝土rough=.88、土rough=.78+.16原rough，不互串。原图不重绘。

局部湿区/排水/封胶后续同源单独1K atlas，保留全场米制相位；其烘焙/最终GLB尚未执行，先由Root看完整场地决定。标准Principled/纹理，避免未授权runtime shader依赖。目标2套共享+1局部材质，不做全场大atlas。

`prepare_static.py`仅普通Python，无引擎：解析所有JSON/AST、核对实际数组SHA及面积，量化世界到Blender float32的残差并冻结脚本/输入。最大位置误差限1e-5m；只在存储后严格共线且原宽≤1e-5m的三角记录为数值残余，面积计入原.0005m²分解容差。没有snap原域或生成新孔来“美化”输入。

静态结果不是Blender API/渲染/平铺无缝/实际MAIN通过。执行结果会写唯一新时间戳目录，失败保存现场源/日志；没有自动重跑。

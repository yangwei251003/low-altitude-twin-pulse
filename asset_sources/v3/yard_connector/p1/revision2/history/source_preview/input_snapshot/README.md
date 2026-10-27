# Yard Connector P1 / 静态就绪

Root已亲看并批准单件V1参考的大形，要求减少云纹与亮砂。参考与原始prompt/来源见 `references/v3/production/yard_connector/`。新源是12×4m制作样件，不是已集成约300m²前场。

运行入口（需要Root独占引擎窗口）：

    python -B asset_sources/v3/yard_connector/p1/run_preview.py

入口使用现有 `scripts_tools/v3/dev.py.execute_command` 隐藏Windows私有Job，CPU2/硬180秒；先查其他引擎进程，保留每次唯一输出/输入快照/日志。当前从未运行。普通源码AST与纯Python二维面积分区已查，不能代替Blender实测。

## 可观察交付

- `yard_connector_editable.blend`：独立施工板、修补板/封缝、基层、集水口框/格栅，SourceMetric显式UV；顶面Godot Y0，不改运行碰撞。
- `01-single-reference-oblique.png`：完整主件、固定中性灯/同参考方向；`02-single-26m-readability.png`：同物同灯26m正交读感，不冒充实际MAIN。
- `geometry.json`、`result.json`和`process.json`：实际三角、包络、逐件闭边、图像abspath/SHA/size/真实pixels重开、自然退出/残留由dev helper记录。日志ERROR即失败，不以exit0放行。
- 贴图原字节在运行时复制至该次 `source_inputs`，先绝对路径load/读pixels，再保存相对路径并重开。不修改原atlas/扫描文件。

## 预算与边界

源构造/检查/重开预计10–25秒，两图预计45–90秒，总55–115秒；以实际CPU2为准，硬180秒不自动重试。源审查后才另排烘焙，初估三组2K/1K PBR原生bake60–150秒并逐图checkpoint，实际布局后再收紧贴图/材质数；本入口不含bake或GLB。

扫描Sandy Gravel 02按官方2.53m米制铺底，保留原diff/rough/nor_gl、Non-Color数据图；不位移、不添高模粒、不伪造高度。混凝土用已批准院面原atlas的1.8m采样方式，局部修补与泥土宽面通过真实分区表达，避免覆盖12m的巨型云纹。三类运行材料/mesh是后续atlas目标，当前编辑材料可以多于三种。

复用指生成真实裁段/保持SourceMetric米制密度及正确接边，不是把完整12m拉伸到井口1.5m。后续相邻派生件需延续统一米制UV相位；不可直接把本固定局部UV重复平铺整前场。当前geometry不包含约300m²总场地或任何World替换代码。

静态已修一个明确裁切实现错误：恰在裁线上的点必须进入两个半平面，旧代码/面积差值保留于 `build_source_before_static_boundary_fix.py.txt`、`static_failure_01.json`、`static_partition_check.json`；无引擎失败。最后一次报告列修复后面积严格闭合，源实际拓扑仍待运行。

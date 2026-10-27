# 交付副本角点法线精度口径（2026-10-20）

本轮实际 prepare：PID33344，4.859秒自然exit3，runner exit1，0残留；97个前置检查通过，在复制Bank0角点法线后因最大向量差5.8247019510678744e-05超过自设1e-6而停止。未进入UV打包、孔边检查或保存checkpoint，也未烘焙/导出。该向量差按单位向量弦长折算约0.0033373084°；本次失败日志没有记录逐点原向量，因此这里不是实际逐角点角度测量。

8项源脚本/原始日志/审计报告保存在`normal_quantization_failure_20261020_022541/`。清单SHA为`6b555b939c7b7340dcaeab2be48b76bea5e2bf8e9aecbe4ab6841f5e2baae4b6`。33项冻结输入逐字节SHA均保持，原blend不变。目录根现有cleanup_report/delivery_contract仍是上次16725三角阶段，不能用它们证明本轮16724已通过。

只读核对了[Blender官方v5.2.1 mesh_normals.cc](https://github.com/blender/blender/blob/v5.2.1/source/blender/blenkernel/intern/mesh_normals.cc)：`mesh_set_custom_normals`写入Corner域short2属性；`corner_space_custom_normal_to_data`在方向分量与自动法线相差不超过1e-4时采用自动方向，其他情况将角度编码为short值。实际调用路径为`fresh.normals_split_custom_set(normals)`后读取`fresh.corner_normals`。该接口不保证输入float向量逐位返回；现有微小误差与这一自动方向归并/编码精度相容。未另外启动引擎来区分本次具体角点落入哪一种编码分支，不声称已精确定位到某一角点的short码。

Root批准交付副本采用每角点方向误差≤0.01°。新脚本对每个保留loop的原方向与实际方向用atan2(|cross|,dot)比较，拒绝非有限/非单位向量，记录最大角度、最大向量差、改变角点数、最差新旧loop及其原/前置/实际方向、是否调用custom setter和实际属性类型。不写“法线完全相同”。顶点、剩余面/三角、绕序、材质、三个作者UV、孔边和包络仍按原严格合同；不改薄片清理白名单、不放宽UV面积和岛距。

当前只完成静态修正：3文件AST与7个角度/无效输入案例通过。新的实际角点读回、16724三角、图集与孔边结果仍待下一次获准prepare。

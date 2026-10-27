# 分级UV prepare入口（静态就绪，未运行）

入口：`python asset_sources/v3/i2_east_maintenance_extension/delivery_p2/run_prepare.py`。

需root另授串行引擎窗口。私有进程树CPU2/240秒，原始stdout/stderr及PID/时间/退出/残留记录写`runs/`；仅prepare，没有bake/export/render阶段或自动续跑。已有checkpoint不可覆盖，任何分类、装箱、正面积、重叠或间距失败立即保留报告退出，不自动降分辨率或密度。

`prepare_uv.py`读取P1冻结源，只对92个交付副本新增/重排`DeliveryUV`（即本轮BakeUV）。原SourceUV/ConcreteUV/PaintUV逐角点及所有16728源三角保持；原材质图像/法线源必须显式读取三层作者UV之一或原物体坐标，不允许隐式active UV在切换烘焙层后换采样。后续bake目标、交付ImageTexture/NormalMap和GLB UV0须共同来自DeliveryUV；本入口尚未创建交付PBR材质。

分级和坐标预算见`ATLAS_PLAN.md`，实际逻辑按原部件身份、面高程/方向与真实共享边分连通岛。宽面/盖面上倒角与顶面同投影，竖面不压扁；空心框顶按四边分岛；原共面封胶格网仅合并为UV长条，不改网格。所有剩余面均明确分类，未知件不静默放到埋底。

先按175/275px/m安排主顶面，再在剩余图幅放侧/封胶/埋面，最终2K/1K不变。每岛矩形5px护距，图边8px，不做最后全图缩放。检查实际float32 UV三角正面积与有限值、同岛三角内部重叠；不同岛先校验矩形不交，再用实际边界线段计算每岛最近距离（非仅AABB距离），必须≥8px。记录逐岛UV面积、最近邻、像素中心覆盖和按类别统计的真实px/m。图像占用只做数学栅格统计，不生成/改写贴图像素。

所有UV通过后才保存`uv_checkpoint.blend`，真实重开后核对两组逐三角UV签名；33输入前后SHA保持。结果为`uv_checkpoint.json`，其中仍标明仅prepare、不代表烘焙或视觉通过。失败产生`prepare_failure.json`，进行中分类/阶段结果写独立报告，不覆盖P1。

静态验证：4个Python文件AST解析通过；`atlas_geometry.py`的7个小型独立二维数学例通过（正面积、包含相交、共享边、重复三角拒绝、真实10px间距、像素覆盖等），该结果不等同真实Blender源UV验证。没有启动Blender/Godot。

# 已证实节点枚举修复

首运行 `preview_20261020_063427_595281`：PID16648，自然exit3，3.609s，残留0，输入未变；failed_source.blend、完整input_snapshot、engine.log/process/failure均保留。材料树创建尚未结束，场地没有建成、没有渲染。

实际Blender5.2.1 RNA异常完整枚举明确包含 `SINE` / `COSINE`，不包含脚本使用的 `SIN` / `COS`。仅更正这两处名称；环映射公式、尺度70、周期3.6m、Bump强度/距离、输入图与几何合同均不变。不调整材质以隐藏失败。

静态AST/标准JSON/真实数组面积与输入SHA重新检查，prepared更新。未将失败退出称为源预览完成；新执行仍按Root串行窗口安排。

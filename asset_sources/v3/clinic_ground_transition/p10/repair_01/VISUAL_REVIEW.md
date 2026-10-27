# P10 单件源图自审：仍未达到参考，不进入烘焙 / GLB

本轮实际查看以下原始 PNG，并重新对照批准的 imagegen V2 单件形状参考：

- `evidence/transition_source_p10.png`：原完整机位。
- `evidence/transition_contact_close_p10.png`：原接触近机位。
- 参考：`../../../../../references/v3/production/clinic_ground_transition/ground_transition_reference_v2.png`。

这些是 CPU Cycles 源材质渲染，不是 GLB 回导或游戏截图。没有进行本轮烘焙，没有新 GLB，也没有运行游戏物理。

## 画面判断

1. 近图第一条真实沟的岸肩和沟底较 P9 清楚，实际增大的深度在局部有收益；但完整机位仍由大片浅泥面主导，另外两沟及末端/分叉的沉积粗细变化较弱，没有达到参考的连续混粒岸带和低密度沟底。
2. 真实大砾具有侧面和体积，已不是纸片；但灰色平整多边形仍像独立摆放的低模石块，与暖色扫描土砂岸带脱节，多个石簇间的空档仍明显。不能用三角数或覆盖数字宣称其自然。
3. 混凝土断口仍是一条相对整齐的深色薄边；参考中更宽、更深浅不一的崩蚀面和断口粗骨料层次尚未还原。当前不建议烘焙或导出。

侧面的 18 cm 结构底在 studio 地板 Y=-0.19 下全部露出；实际与 Y0 地面邻接时应埋入。它是装配验证的待核项，不因源图露出就擅自改变 Y0 接边合同。

## 本轮实际结果与边界

- 最小修复仅删除全埋的 `FractureAggregate_23`（20 triangles），其余 144 件在同次构造前后逐点/逐面签名一致。原失败源和脚本保留。
- 实际 7,456 triangles / 144 editable parts；149 项既有几何门槛通过。这不等于完整自交审计、游戏碰撞或美术通过。
- 12 断面来自实际新土面 triangle BVH，平均双岸相对中心深度为 38.693–65.240 mm。4–7 cm 是造型设计范围，不将两处接近 4 cm 的实测值强制改成通过值。
- 土面目标 BakeUV 按未来 2048² 计算约 374.868 texels/m；这是已经构造的 UV 规划密度，未生成新的烘焙图。
- 扫描纹理实际绑定：Sandy Gravel 2.5 m、Rocky Trail 2.0 m；6 张原图均 2048²，Diffuse sRGB，NormalGL/Roughness Non-Color。实际源 UV 映射最大误差 5.72e-8。
- 7 张文件图像均按打开的 blend 上下文用 bpy.path.abspath 解析、文件存在、SHA 记录、真实像素读取。实际记录为 reload 后 has_data=false，读取 pixels 后 true。上次失败是过早的加载状态断言，本次未删除检查，也未改源图像。
- 恢复渲染 PID 41084，CPU 2，106.807 秒，自然 exit 0。完成即归还窗口，没有追加一轮。

## 冻结与限制

`failure_manifest.json` 保留前一次加载检查失败及 18 个原字节文件。恢复脚本只重开 `preview_source.blend`，不重建、不存回它，不改材质节点；恢复前后所有失败清单输入 SHA 不变。完整本轮清单见 `manifest.json`。后续是否继续由 root 结合参考判断，当前仅报告明确差距，不自行制作 P11。

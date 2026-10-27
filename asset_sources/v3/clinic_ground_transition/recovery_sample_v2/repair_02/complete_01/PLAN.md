# 单次组合验证：静态准备，未运行

仅处理 0.9 m 方法样。沿用已冻结的 repair_02 局部侧壁裁切算法；原 repair_01 Normal/侧面 UV 修复、已有 BaseColor 和 Normal PNG 不重做。输入/输出限定本支目录及已授权资产卡，原源不改。

入口：`python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_02/complete_01/run_complete.py`

一次 Blender CPU 2，私有进程树硬限 **240 秒**。预计：局部裁切与边界/UV 读回 35–65 秒，11 组 AO 与原生 ORM 合成 20–35 秒，保存重开及两图 100–120 秒；合计约 155–220 秒。按实测先后输出边界源、映射/覆盖报告、逐组 AO checkpoint、最终可编辑源，再出高/低两图。真实几何/材质/烘焙错误停止，不能为了凑总时间跳过关卡。未授权自行启动。

## AO 投射和遮挡分开

1. 从本次裁切后的高/低源按既有 11 组身份复制投射工具。低模 BakeUV 和角点法线沿用原面插值；35 mm cage 按已验证组的原角点偏移插值，不重新加大距离。
2. 每次只选择“当前匹配高模组+当前低模目标”。其他 10 个真实高模组未选中、render 可见；原完整副本、旧工具、cage、背景展示平面不混进 AO 遮挡集合。
3. AO 节点改为 `only_local=False`，35 mm、16 samples 不变。这样匹配源决定投射位置，全部真实高模参与遮挡。低模目标的 camera/diffuse/glossy/transmission/volume/shadow 可见性关闭，以避免低模副本成为多余遮挡物；它仍是显式 bake target。实际运行会记录每组 selected/render 名单和属性。
4. 只原生烘焙 AO。原生 EMIT 合成新 ORM：R 取本次同组 AO，G/B 取原图。Normal 和 BaseColor 使用同一原 PNG；不以改色、抹亮或删 AO 达标。

## 前后检查与两图

- 边界局部剩余重叠、组合外表面缺口、原面对应/UV/法线及高低裁切面积按既定方案验收；独立壳边与组合覆盖分开记录。
- 新三角的切线基/符号与原插值基核对，防止保留旧 Normal 贴图却悄悄改变其含义。
- 32 暗点对应的 28 实际邻居 texel 记录旧/新 AO；不设置“必须变亮”的美术数值门槛，保留真实接触暗部。
- G/B 与原图实际像素比较，Normal/BaseColor 前后 SHA 保持；1K 实际像素和原源图解析检查，错误日志即失败。
- 保存后重开，实际高低三角/全部 UV、PBR 接线与原相机/灯光复核；两张均沿用该样件原固定相机，输出 `01_high_source.png` / `02_low_baked.png`。
- 高模参考也只显示完整候选高模与原背景，使用原 BSDF/颜色及同一全场 AO 语义；低模图启用真实 AO 与现 Normal。图片须实际看过后再报告，不以 exit0 或统计数认定修复完成。

本轮不包含 GLB、整件 P14、布局或运行资产导入。

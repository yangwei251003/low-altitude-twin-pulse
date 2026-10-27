# P2 原生交付流程（静态准备，待窗口）

复用已完成维护铺面的`delivery_p3/build_delivery.py`原生四通道烘焙、普通GLB导出和二进制读取，以及本件P1准备过的显式两组导出/固定机位回导工具。只替换输入为当前已实际通过的P2检查点和16724实测合同，不重排UV、不重做几何、不用P1低密度图集。

## 两个连续窗口

1. `python asset_sources/v3/i2_east_maintenance_extension/delivery_p2/run_delivery.py --run-authorized-stage bake`
   - 一个CPU2私有进程树，硬240秒；按FloorSurface→InspectionBand连续运行，每组依次BaseColor/Roughness/Metallic/Normal。
   - 2K地面与1K检修件不变。所有源图像、3层作者UV与DeliveryUV经实际合并拷贝再检查；角点方向逐一≤0.01°。原作者显式UV继续采样，DeliveryUV只作烘焙/交付UV。
   - 原生EMIT提取无灯光BaseColor/粗糙/金属；切线NORMAL原生烘焙。每张图写盘SHA后记入该组bake_progress，已成功通道后续只能核对复用。扩边4px，prepare实际最短间距10/10.0088px，不越过既定护距。
   - 两组各保存可编辑baked_editable.blend。此窗口不导出GLB。
2. `python asset_sources/v3/i2_east_maintenance_extension/delivery_p2/run_delivery.py --run-authorized-stage deliver`
   - 一个CPU2私有进程树，硬240秒；连续导出→实际二进制检查→同字节重新导入→2张1536×1024原机位图，不按图片拆排队。
   - 三个identity节点：EastMaintenanceExtension根、FloorSurface、InspectionBand；2网格/2标准PBR材质/预期2surface，9240+7484=16724三角。世界装配原点仍(20.7,0,8.8)，无碰撞/上下文/隐藏旧地板导出。
   - 同材质BaseColor/Normal/MR均UV0，金属/粗糙由glTF标准合并；预计6张嵌入PNG（两组各3），原生烘焙文件仍8张。读真实GLB的三角/UV多重集、全部node变换、边界、实际材质/纹理角色和尺寸；BaseColor/Normal必须与原生PNG字节相同。
   - 回导检查真实孔口、三角、UV0、材质与图像可加载；原GLB哈希前后不变。图仅为离线Blender回导，明确不含北侧原件/生产支柱，不冒称Godot实机或最终美术。

预估每窗约60–150秒，依据既有维护铺面一次完整烘焙/导出/两图实际78.141秒及本件两张源图的既有耗时；不是本次新流程实测。每树硬240秒始终生效。任一操作报Error或Traceback即失败，即使进程exit0也不放行。失败保全输出，不自动重试、降密度或跳过检查；通道检查点避免已成功烘焙重做。

## 数据与预算

UV prepare289项已过：2K地面实际面积占69.49%、1K检修49.45%，像素中心覆盖69.41%/50.03%。地面宽面中位175px/m；检修盖含倒角中位231.25px/m、水平约275px/m。已按需降低埋底/侧面的密度，而非缩小所有可见面。

两组3贴图角色合计15,728,640像素；若RGBA8含完整mip、未压缩约80MiB，这只是格式预算，不能当作Godot实际显存占用。PNG压缩字节和最终GLB体积以导出真实读回为准，不预写成功大小。没有增加贴图分辨率、额外材质或runtime面数。

冻结输入清单`delivery_phase_inputs.json`包括已通过checkpoint、实测合同、源保留报告和两阶段脚本；原33个作者输入仍独立核对。当前两脚本AST检查及无参数“不启动”入口通过，尚未执行bake或deliver。完整源/失败和成功prepare证据均保留。

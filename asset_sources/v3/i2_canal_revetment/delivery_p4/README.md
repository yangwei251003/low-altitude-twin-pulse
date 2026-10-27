# 护岸 P4：4 米交付候选

已完成原生三图烘焙、显式 GLB、严格二进制回读及同字节 Blender 回导图。root 已亲看回导，准入实际游戏审查。运行资产与共享代码未写入；P4 原文件保持不变。

- `i2_canal_revetment_p4.glb`：5,791,792 bytes，SHA `46dd85357ba8cdcee41fe3aeabfe77ca7cb3aa3f1842450ad8a393e27f7cb197`。
- 根 `I2CanalRevetment` → mesh `RevetmentSurface`：均 identity；1 mesh / 1 surface / 1 material `I2Revetment_PBR`，5152 实际三角。
- Godot 本地范围 X[-2,2]、Y[-2.8,0]、Z[-.35,0]；顶面水侧中点原点，+Z 朝水。没有碰撞、灯、相机、动画。
- `i2_canal_revetment_editable.blend` 保留 8 件独立编辑物；清理后的 body 已显式固化，原始带 modifier 的 P4 仍完整保留。
- `textures/`：三张 2048²；BaseColor=sRGB，ORM/Normal=Non-Color。ORM 有效 UV 岛 R=1，未声称 AO，G粗糙度/B金属度。Normal 实际完全中性，未将色图孔边伪造为法线。色图源 1500×1049、旧图1254²，2K烘焙不会增加原始细节。

## 有界微面修复

原 P4 5320 三角含施工缝倒角上的纳米薄片。保全失败，先实测，得到 root 授权后仅在 delivery 副本以不超过1µm的显式代表点映射处理连通纳米邻域；保留原 loop 的 UV/属性/法线，并沿4条既有共享边插入原有中点。删除172个退化三角，补4个拆分三角，总5152。没有全局减面。原件映射与具体坐标见 `local_cleanup_report.json`。

最大代表点变化0.266586µm；独立float64双向三角表面样本最大0.266586µm；54条施工缝/水线/顶边射线最大0.119209µm；闭合且包络相同。Blender BVHTree在一个细长三角报0.728mm伪最近面，已保留原始值和真正float64最近距离，未放宽1µm检查。原P4 SHA `374d2fafe2efabd5272ede99e36c58d1ccc38612c43e59099343dbefe91c8a53` 不变。

全部BakeUV非零，最小面积8.7614e-10。材质输入仍用原显式SurfaceMetric/FrontFaceUV，新增独立DeliveryBakeUV；没有用Generated/世界Position替代原映射。烘焙只读取验证后的 checkpoint。

## 实际进程与证据

成功 clean+UV：PID30960 /17.890s；bake：PID32472 /12.844s；export：PID22868 /3.500s；同字节回导：PID36292 /68.750s。均CPU2、自然exit0、日志无ERROR、无残留。此前统计残留、BMesh原面ID不稳定、浮点BVH误差、剩余邻接薄面均原字节保存在对应run目录，不冒称首次成功。`surface_transfer_unexecuted.py` 是未执行的备选方案，正式路径未采用。

`raw_glb_report.json`：源三角多重集/绕序、位置、UV、切线/法线、节点、包络及三张内嵌PNG原字节校验。法线按本机官方glTF exporter float32四位量化后归一化验证，原始差值另保留。`same_byte_reimport/report.json` 与PNG实际使用相同GLB SHA。图见 `same_byte_reimport/01-reference-oblique.png`；视觉结论见 `visual_review.md`。

## 短件阶段

后续仅在独立 `delivery_short_1p3/` 中真裁 X[-.65,.65] 并封口；保持前面原4m映射U.3375..6625，端口从邻近正面0.35m条映射，绝不整件缩放。保留中心锚3件、去左锚/右修补及两条原施工缝，预计4编辑件；实际tri后测。该短件在此4m交付中尚未制作或执行。

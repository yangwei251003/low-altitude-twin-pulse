# 接诊连廊楼下承重 V1：源候选冻结，待实机接入

2026-10-19 已完成 CPU2 Blender 源构建、实际打开、完整离线装配图和显式 GLB 二进制回读。只写本目录；Reception V5、其 GLB、运行代码及布局未改。**不是实机截图、真实飞行或最终美术通过证据。**

## 接线合同

- 编辑源 clinic_reception_support_v1.blend，SHA256 a408f11c5abda5adae8cfe33c1a41830e49f89c740a770106a243b83eab4606c。94 独立编辑件：30 承重件、64 垫圈/六角头。
- clinic_reception_support_v1.glb：7,062,660 字节，SHA256 5d713b0bd4db083f674bdbcdffd280f60488eec35ea4ca275d4b547c427fa54b；2 mesh、1 material、4,520 三角，不含参照建筑/灯/相机。
- 根 ClinicReceptionSupport 放 Godot 世界 **(7,0,-6)**，identity rotation/scale；若挂在接诊根 (7,5,-6) 下，子位移 **(0,-5,0)**。Blender 点是 (worldX-7,-(worldZ+6),worldY)，GLB 已转换 Y-up。
- 直接子 SupportStructure：2,472 三角；SupportDetails：2,048 三角，螺栓 visual_only。三节点均 identity TRS。结构可取真实面碰撞，不得用包住整个楼下的凸包。
- 实际世界 AABB **[2.079999924,0,-9.920000076] → [11.920000076,4.599999905,-2.079999924]**；局部 **[-4.920000076,0,-3.920000076] → [4.920000076,4.599999905,3.920000076]**。全部螺栓已计入，没有遗漏外伸细节。

## 承托与接头

四柱世界 XZ：(2.5,-9.5)、(11.5,-9.5)、(2.5,-2.5)、(11.5,-2.5)。脚板 .84×.84、Y0..0.14；柱身 .60×.60、Y0.14..4.1，梁外两顶肩补 Y4.1..4.12；承重点 .78m 外轮廓、Y4.12..4.6 拆为围梁的两侧带和外端块，中央由梁占据。避免整柱/完整承重点穿梁产生共面黑结。

两 X 梁 X[2.2,11.8]、Y[4.1,4.6]，Z[-9.75,-9.25]/[-2.75,-2.25]。北梁顶4.6接后室地板底（X[2,12]、Z[-10,-6]），南梁接前坪地板底（X[2,12]、Z[-6,-2]）。四脚底 Y0 接 Ground；没有新地板、地下基础或横堵通路的斜撑，不作钢结构应力认证。

Root 已通知布局有 14 个承重 box，旧 EastLandingLeg/ClinicRearPost 已移除。**本轮没有测试这些生产 box，也不宣称其与所有倒角完全等价。** 编辑源保留真实 30 件接头。

## 既有纯数值避让

prepare_support.py 对当时真实布局做分析，原字节保存在 layout_readonly_snapshot.json，SHA 在 support_plan.json；不把 root 后续布局当成已测。

4×4浮台全升程 X[-2,2]、Z[-6,-2]、顶Y4..5及北连杆，与新结构无正体积交叠。梁到浮台X边 .20m、承重点 .11m；脚板 .08m间隙仅在 Y≤.14，不能称可飞净道。病房水池/支架、北连杆、高位源水池及西侧检修台无新增交叠。Y5上方原3m路线未被最高4.6的新体占据。梁底4.1、柱间名义净宽8.4/净深6.4，仍待TR/HX全包络实测。

首次如实检出南梁与旧 EastLandingLeg 约 .0625m³ 重叠，plan 单列 required_old_body_removal；不是原场景无冲突。Root 后续移除不由本源脚本完成。

## 材质与导出

只读复用批准 clinic_gravity/revision_v4/textures/CG_V4_{BaseColor,Roughness,Metallic,Normal}.png，原字节复制 source_inputs/，准确 SHA 在 plan/delivery report。柱、梁、钢脚采 atlas 的 post/beam/steel 区，沿受力长轴布UV，未用台面世界坐标warp。BaseColor 为sRGB，其他Non-Color；R/M与中性法线继承原人工材质规则，不冒充测量或雕刻细节。

GLB含3张内嵌2048² PNG：原BaseColor、原中性Normal、Blender合成的metallicRoughness。前两图原字节SHA一致。每mesh一个surface，全部顶点有有效UV0。导出器有“多个图像节点合成时采用第一个sampler”警告；R/M同UV、同EXTEND，未缺通道。原警告保留stdout。

## 实际证据与冻结

入口：python asset_sources/v3/clinic_reception/support_v1/run_bounded.py；显式导出加 --export。CPU2、--python-exit-code 2、自身进程树240秒限时，已有产物拒绝覆盖；不运行Godot。

| 阶段 | 原始日志前缀 | 结果 |
|---|---|---|
| 首次 | build-20261019_010614_653203 | exit2；几何通过，但5.2默认World无Background节点。failure_world_node保留原脚本/报告；修为显式节点。 |
| 首图 | build-20261019_010727_116718 | 16.75s、exit0；实看裁屋顶/脚，自行退回。failure_framing保留blend/PNG/脚本/报告。 |
| 完整图 | build-20261019_011022_564048 | 14.89s、exit0；相机ortho30，实际所有装配顶点在6%画框余边内。6项检查通过。 |
| 导出 | export-20261019_011521_638949 | 2.30s、exit0；15/15回读检查，编辑源SHA未变。 |

support_geometry.json：94件均正体积、零开边/非流形、零面积三角；部件AABB无正体积重叠；尺寸、4,520三角通过。AABB排重不代表任意自相交全面证明，也不替代游戏物理。

support_delivery_report.json：join前后和实际GLB的**有向float32三角多重集与源完全一致**；有效索引、有限UV0/normal/position、节点、材料图片、包络和源字节全部核对。导出只改内存副本，不覆盖源。

support_v1_assembly.png 已实看：屋面/四脚完整入框，支撑与楼板关系可读，未见此前门柱式黑结。REFERENCE_frozen_V5_NOT_EXPORT只是冻结建筑的离线装配参照，不入本GLB。柱磨损复用较明显、远景螺栓收益仍待实际镜头判断。Root继续验证运行导入、两机体通路、浮台升程、楼板接合及游戏相机。此处冻结，不继续离线迭代。

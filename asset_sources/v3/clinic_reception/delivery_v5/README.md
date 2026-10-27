# Reception V5：候选已导出回读，尚待真实游戏验证

Root 已实看 V5 正常图：柱帽/脚黑结消失，可进入引擎候选；屋面重复钢片图案仍待场景审查。此许可不是最终美术通过。V5 原 blend、脚本、两图、检查和原图全部不覆盖。本目录的 `prepared_contract.json` 按其实际顶点报告分类，含旧文件逐项 SHA/大小；不是新 GLB 实测。

## 下一次入口与边界

执行入口为 `python asset_sources/v3/clinic_reception/delivery_v5/run_export.py`。入口限制自身 Blender 进程树 300 秒，`--python-exit-code 2`，原始 stdout/stderr 分文件保留；超时返回 124、不认通过。首轮超时与恢复后的报告错误均保留；当前实际最终证据见下一节。无 Godot/GPU。

## 2026-10-19 实际交付与证据边界

- 恢复轮 PID44496，156.672秒内完成两张原生贴图、保存独立delivery blend、显式GLB导出（导出本身0.461秒）。随后报告函数的 `path` 被枢轴循环变量遮蔽，SHA读取抛异常，exit2；日志 `export-20261019_001744_016243.stdout/stderr.log` 和该时点脚本 `failure_report_shadow/export_reception_v5.py` 保留，不能把这一轮exit2改称成功。
- 只修报告变量名，新增 `--verify-only`，PID42464独立重新打开已保存delivery blend并重新回读**同一GLB字节**，1.359秒自然exit0；没有重烘焙、重导出或修改GLB。日志 `export-20261019_002220_089611.stdout/stderr.log` 和同时间run JSON。窗口已释放。
- 最终 `clinic_reception_v5.glb`：**4,890,548 bytes，186 mesh，15,951 triangles，19 materials**，SHA `3e812dfa70c48585425ea1c9b572d4fb91340e588d96fa57a1ad048e7fd1db07`。
- `clinic_reception_v5_delivery.blend`：SHA `4ed0b50326786349d1f2774208e0bee57c25704dbedd8f3555ee8ab4d77d63a6`。外部BaseColor与ORM均2048²，实际GLB内部两PNG与外部文件逐字节相同。BaseColor SHA `576a87b0e38072ab75cc50027c7cfeeeec99fe65f692c913f913e53203fce44c`；ORM SHA `81f6ebe6a29345a16f392b44005cdc266da4eb61c4967cb44deb70a71c8eeb10`。
- `delivery_report.json` 给实际GLB全部节点累计矩阵、网格AABB、材质名和源SHA；实际所有186网格边界与源相差≤0.01mm，单UV0、全部锚点/枢轴保留。`actual_byte_audit.json` 额外验证实际GLB的门洞/前廊/天窗净空棱柱均无网格AABB占入、5块玻璃BLEND和灯面独立。它们不是游戏PhysicsServer扫掠或任意网格自交认证。
- 原V5 SHA仍 `5f09e7feb7c03d346a98c199d34fa710fc3444537e055bf2c07f4f1a97532efe`；未写任何运行目录。没有本轮烘焙后GLB回导相机图，也没有游戏碰撞/遮挡/性能/真人验证。源V5正常/淡出图只能证明导出前源外观，不能当最终GLB图。

屋面4组、门左右实体、家具3组分别持有独立不透明材质；所有玻璃独立材质，灯面独立。接诊状态灯是暖色非发光标准材质，**没有凭空设成任务完成亮灯**；两室内扩散面保留原暖光emission及强度2.5，实际环境照明仍由root灯锚点接线。GLB未创建碰撞体或灯源。

## 首轮失败与有界恢复

2026-10-19 00:05:07 启动 PID23760，首轮进程在300.782秒超时，所属子进程28924与23760均已终止，运行记录明确 `timed_out=true, exit_code=124`。保留 `export-20261019_000507_626701.stdout.log`、`.stderr.log`、`run-20261019_000507_626701.json`，首轮原脚本和已完成BaseColor原字节存于 `failure_300s/`。没有 GLB；没有通过结论。

BaseColor约157秒完成并实际查看，十字/导引/青框区域在图中；多物件ORM烘焙未在上限内结束。**首轮没有逐loop UV快照，因此不复用该PNG做新GLB，也不把固定顺序等同已证明UV相同。**

恢复仅改变烘焙调度：BaseColor继续在原186独立源物件中对应的不透明件上烘一次，保持原局部顶点/物件矩阵/Generated bounds/Object/Geometry Position；不在临时join上烘颜色。完成马上保存 `base_complete_checkpoint.blend`、`bake_uv_checkpoint.json`（逐mesh、逐loop float32 UV SHA），防再次无依据重做。只将ORM烘焙放在临时世界面副本，原对象不合并导出；实际运行须断言所有源Roughness/Metallic输入均无连接且为常量，逐loop复制同UV并核对不变。若以后源材质不是常量就拒绝该快路，不猜坐标等价。

恢复前预算沿首轮BaseColor约157秒估算，加ORM单对象及导出约20–40秒，仍300秒硬上限；实际本轮156.672秒在报告阶段退出，后补只读1.359秒回读。原图/旧源未改，未降低图尺寸或碰撞/几何验收线。

`export_reception_v5.py` 从冻结 V5 显式打开，在独立副本中整理层级、唯一 UV0，CPU 原生 EMIT 烘焙 2048² BaseColor 和 ORM，再显式导出本目录 `clinic_reception_v5.glb`。不写运行 assets。GLB 存在即拒覆盖。源 shader 的屋顶十字、地面引导和前檐调色必须烘焙，不能把直接材质导出当等价。清洁内墙不另添加污迹；ORM 的 AO=1，粗糙度/金属度沿用 V5 保守常量，不烘固定光照、不伪造法线。透明玻璃、两室内灯面和接诊状态灯保持独立标准材质。

导出副本保存 `clinic_reception_v5_delivery.blend` 和外部贴图，原 V5 保持完整可编辑。186 网格不合并：本轮保真和明确分组优先；这不是 draw-call 或性能通过。已对实际 GLB JSON/BIN 累积 TRS、顶点、索引和 UV0 回读，每对象 AABB 与源差≤0.01mm，节点/枢轴/锚点均保留；详情在 `delivery_report.json`。还须后续同字节回导/实际游戏相机检查，不能以数值回读替代。

## 精确分组与碰撞用途

唯一根 `ClinicReception`，**局部变换 identity**。根放 Godot 世界 `(7,5,-6)`，scale=1，不旋转。源 Blender 点 `(x,-z,y)` 经 glTF Y-up 导出回到 Godot 局部 `(x,y,z)`，回读检查该转换。总局部 AABB `(-5,-.4,-4)..(5,3.3,4)`；世界 `(2,4.6,-10)..(12,8.3,-2)`。小数实际值见 JSON。

| 根下路径/实际节点名 | 网格数 | 接线用途 |
|---|---:|---|
| `Structure/FloorFront`、`FloorRear` | 1+1 | 各真实地板三角面；前地板替换旧对应面，不能重叠铺第二层；后室楼板/承重由 root 接入 |
| `Structure/ShellWalls`、`CornerPosts`、`FrontPosts` | 18+2+6 | 真实墙柱三角面，不把窗/门洞填成包围盒 |
| `Structure/DoorFrame`、`WindowFrames`、`Drainage` | 4+16+4 | 实际门轨、框、排水管；不填门洞或窗洞 |
| `Occlusion/RearRoofLeft`、`RearRoofRight` | 21+21 | 独立后室屋面及全部随属压条/螺栓，可视觉淡出；真实屋面碰撞仍保留 |
| `Occlusion/CanopyLeft`、`CanopyRight` | 17+17 | 独立左右前檐；中间没有屋顶网格，禁止保留旧整板碰撞 |
| `Occlusion/MedicalSign` | 5 | 标牌/文字单独可淡出，visual_only |
| `Doors/DoorLeft/{DoorLeft_Solid,DoorLeft_Glazing}` | 4+1 | 独立开态叶片，玻璃仍属于可动实体碰撞 |
| `Doors/DoorRight/{DoorRight_Solid,DoorRight_Glazing}` | 4+1 | 同上，不实现自动关门或交互逻辑 |
| `Glazing/StaticWindows` | 3 | 前侧观察窗真实薄网格；透明不表示可以穿过 |
| `Furniture/Stretcher`、`TreatmentBed`、`ReceptionDesk` | 20+7+6 | 独立家具和实际三角碰撞，保留腿/轮/台面空间，不合成整栋包围盒 |
| `Lighting/InteriorFixtureDesk`、`InteriorFixtureBeds`、`ReceptionStatus` | 3+3+1 | 灯罩/扩散面独立，visual_only；源 AREA 灯不导出，用锚点供实际灯接线 |

上表所有 AABB 仅诊断，不是碰撞盒建议。除明确灯和标牌 visual_only，其余按实际部件三角面；门动件跟随门父节点。小倒角/玻璃厚度不得用整片箱体替代。后室地板新增世界 X[2,12]、Z[-10,-6]、顶 Y5、底 Y4.6；没有暗加地下支撑。

**中央前檐天窗**：局部 X(-1.7,+1.7)、Z(0,4)、Y[3,3.3] 完全开放，名义净宽 **3.4m**、净深 **4m**（浮点边缘误差 <1μm）。世界 X(5.3,8.7)、Z(-6,-2)、Y[8,8.3]。左右前檐真实边界分别 X[-5,-1.7] 和 [1.7,5]；主屋顶止于 Z0。不能仅隐藏旧 ClinicCanopy 可见面却保留整板碰撞。门头位于 Y≤3 的后缘，入口门洞另按下项约束。

## 门、通路与家具的真实接口

- 门洞局部 X[-1.7,1.7]、Y[0,2.8]、Z[-.33,.5]；前廊 X[-5,5]、Y[0,3]、Z[.5,3.5]。前区深4m。既有独立检查保持；不代表完整机体转弯已实测。
- 门叶枢轴 `DoorLeft=(-2.55,0,-.43)`、`DoorRight=(2.55,0,-.43)`，当前开态各宽1.7m。若未来关门，左本地 +X1.7m、右 -X1.7m；应由 root 加扫掠/防夹、状态同步与真正动态碰撞，资产本身不触发。
- `CheckPoint=(0,.8,3)`、`DoorOpening=(0,1.4,0)`、`WestJoin=(-5,0,2)`、`EastExit=(5,0,2)`。两室内灯锚点为 `(0,2.82,-2.75)` / `(3.2,2.82,-2.1)`，仅位置，不导入源85W作为既定游戏亮度。

| 独立家具 | pivot 局部 | 实际结构局部 AABB（四舍五入毫米） | 世界 AABB |
|---|---|---|---|
| Stretcher | (3.2,0,-2.2) | (2.790,0,-3.280)..(3.610,.960,-1.120) | (9.790,5,-9.280)..(10.610,5.960,-7.120) |
| TreatmentBed | (4.3,0,-2.25) | (3.950,0,-3.300)..(4.650,.900,-1.200) | (10.950,5,-9.300)..(11.650,5.900,-7.200) |
| ReceptionDesk（含独立台上显示器） | (0,0,-3.15) | (-1.340,0,-3.700)..(1.340,1.480,-2.600) | (5.660,5,-9.700)..(8.340,6.480,-8.600) |

各家具最低点为局部 Y0（浮点微差≤3nm）；显示器与床栏仍独立可编辑。柜台从门口眼高3条源 ray 可见，不等于默认俯视相机可见。正常屋顶仍遮挡柜台，屋面淡出需要 root 实际遮挡机制验证。清晰门/医疗标识有改善，但本目录不宣称建成诊所玩法或最终美术。

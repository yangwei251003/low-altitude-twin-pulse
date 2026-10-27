# WestLanding 西侧固定接驳平台＋原单腿

沿routeId `5e455d78-37b2-423b-b660-0cc3185eae49`、用户已选I-B。Root已亲看参考及P1完整源图并批准进入交付。当前2套共享PBR、4mesh显式GLB与同字节数值回导已完成，仅写独立candidate；生产安装/实际游戏镜头仍由Root验收。高/低屋冻结字节未改。

## 定位与硬合同

实际读取 `data/v3/terrain/i2_clinic_layout.json` 并保留源SHA及两Box原记录于 `layout_readback.json`。已亲看正式MAIN `artifacts/v3/west-service-20261020_073913_83a44d/02-room-default.png`、`03-room-whole-yard.png`、`05-offset-room-cutaway.png`：高屋旁大片灰绿架空面是WestLanding，非已完成PumpRoof，也非右侧移动Deck。

| 原实体 | 世界AABB | 尺寸 |
|---|---|---|
| WestLanding | X[-10,-2], Y[4.6,5], Z[-6,-2] | 8×0.4×4m |
| WestLandingLeg | X[-9.6,-9.1], Y[0,4.6], Z[-3,-2.5] | 0.5×4.6×0.5m |

源底心世界原点 **(-6,0,-4)**，Godot局部板X[-4,4]/Y[4.6,5]/Z[-2,2]，局部柱X[-3.6,-3.1]/Y[0,4.6]/Z[1,1.5]。Blender源坐标映射 `(worldX+6, -(worldZ+4), worldY)`。全部新增可见几何只在这两个Box的并集内，不以整体AABB许可填满空中空间。保留顶Y5与现有两个完整碰撞Box。

单柱位于板左前偏角：柱心离左短边0.65m、离前长边0.75m，既有布局的偏置悬挑关系须如实保留，不暗增支撑或改变柱位置。视觉参考不提供现实结构承载验证。新柱、斜撑、梁下挂件、拓宽柱脚/柱帽、栏杆、护栏、梯/坡道均不在授权内。

东端世界X=-2是精确活动接缝。邻接移动Deck为X[-2,2]/Z[-6,-2]、厚0.35m，正常顶部Y4→5，联合扫掠Y[3.65,5]；本固定件不能向X>-2伸出，不放连接舌或跨缝金属，不把低位缝封成实体。下方飞行空间与UnderDeckFloor/原机关不动。

## 一个对象的造型目标

将这块占画面较大的纯色板明确表现为工业承台：0.4m厚度内的深青钢边梁，顶面约4×2宽板分区、低反射灰钢与可读但不密的浅防滑纹；单柱用内收检修包板、合理接缝/少量栓件表达。板顶没有凸起围边，所有防滑浅肋后续最高仍Y5；柱脚或柱头不得扩大0.5m足迹。闭合板与柱外形不是透明格栅或虚假入口。

与已装高/低机房青钢、灰钢同族。可复用已批准泵房/机房青钢原图和Metal012钢材方法、校准架浅防滑纹制作经验；不直接将透视概念贴成底色，不新增大场景图。大面安静，明显但局部的剥漆/盐蚀集中板边、接缝、少数紧固处，柱有几条非等距雨痕与下部污迹，禁止全幅云纹/砂点。

已有 `WestBearingLine` 位于世界X=-3、Y5.004、Z=-5.75/-2.25，各1.8×0.005×0.07m，是生产可读性标记，由Root保留；本件不烘入标线、不画常亮灯或状态灯，不添加新的交互与动态语义。

## 责任与验收

资产负责独立可编辑零件、显式UV/PBR/GLB、真实两Box范围和材质/轮廓。Root负责生产安装、原静态碰撞/升降运动/相机遮挡、接缝检查与实际操作。未来默认/近景沿上述02/03/05检查全组关系，并检查Deck低位与Y5齐平台面；单件图片不代替实际游戏证据。

本轮图已原生imagegen生成并实际打开：`references/v3/production/west_landing_platform/west_landing_platform_reference_v1.png`，1536×1024，SHA256 `72fe540f4ff28570b15020abfeff9ef5cf16ee99df84811c4f9a3327b8f9bdc3`。中性光、固定斜视，全板和单腿完整居中；原PNG/完整提示词/实际tool payload/来源SHA均在同目录。五条实看记录见`REVIEW_v1.md`。

一板一偏置柱、宽板分区和同族材质成立；Root批准时明确柱脚围领内收、降低防滑密纹强度。源中两项均按合同实现：脚帽不超原0.5m足迹，浅肋16cm周期、6.2×1.4cm短条，峰值仍为Y5。尺寸/偏置/活动缝以真实合同为准，不把图上的透视自动升级为模型。不再生成第二张参考。

## P1源准备与执行边界

整体根`WestLandingPlatform`、`PlatformAssembly`/`LegAssembly`及所有源物件变换identity；顶点采用共同底心世界(-6,0,-4)坐标。运行规划为4mesh/2共享材质，分别挂到原body时由Root抵消body中心，不把腿并入板体的碰撞或遮挡语义。

| 组/拟运行mesh | 已实际evaluated低模三角 |
|---|---:|
| PlatformAssembly / PlatformSteel | 672 |
| PlatformAssembly / PlatformPaint | 660 |
| LegAssembly / LegSteel | 960 |
| LegAssembly / LegPaint | 836 |

106个独立编辑低模件、3,128三角。8件高模浅肋源包含2,112条独立闭合浅肋、92,928三角，仅用于未来高低模法线烘焙，禁止导入运行网格。8块钢板顶面Y4.9985，浅肋峰值与四边齐平盖板Y5；原Box顶面碰撞保持Y5，最大1.5mm表面落差如实记录。封闭芯体内收于边梁，不再让同向共面外壁叠在一起。

Paint复用已批准泵房原atlas青漆区域；Steel复用ambientCG Metal012原Color/Roughness/Metalness/NormalGL，CC0来源与原SHA随输入记录。钢面显式2m米制UV，NormalGL强度0.25仅一次；浅肋来自真实编辑几何，非重复Bump。2K钢/1K漆、各BaseColor/ORM/Normal为后续预算，此时尚未烘焙或实测交付UV面积。

首轮PID11872/8.234s自然exit3/0残留：实际两Box、闭合、材质图像与保存已通过，但重开后综合evaluated哈希不等，在渲染前停止。失败源/脚本/报告原字节保存在`p1/failed_first_reopen/`，未删或覆盖成成功。

只读诊断PID39152/8.109s/exit0/0残留：两份保存源的位置、绕序/材质、父组/变换、原UV分别严格相同；仅Bevel生成的非活动UV有末位插值差。后续续跑逐loop实测FinishUV最大5.9604645e−8、PanelUV最大1.1920929e−7，最大折合2K为0.00024414像素；MetricUV差为0。原位置/绕序/法线/原图未改。该差异按Root明确≤1e−5的UV交付精度记录，不声称evaluated UV位级一致。只从已有blend继续单图，不重建模型。

续跑PID17228/54.485s自然exit0/0残留、日志无ERROR。已实际打开`p1/resume_preview_01/01-single-object.png`；源SHA256 `a7908e2e3a114f8a0a73bfb26e7216698b941a51de92f5915c1d2df3608d9105`，图SHA256 `dd48093ac6389f215f7f6bb7a0295ebf5c92a3a26006e71fe3f7d25d273384f3`。两原blend和5张原PNG未改，未进行烘焙/GLB/运行写入。源与图等待Root审查后决定下一步骤。

Agent实看：完整板/腿与8块宽板、内收脚帽成立，未见共面黑块或缺图；浅肋清楚且密度较参考降低。相对批准参考，钢面偏冷灰且较均匀，青框偏蓝、边缘剥漆较线性，作为当前离线差异保留；这些主观判断不替代实际MAIN和Root美术验收。

## 共享材质与显式交付

Root亲看源图后接受单腿/宽板/同族框架，冷蓝灰差异留实际场景复核，没有追加调色轮次。bake PID11584/42.375s，export及同字节数值回导PID35064/4.484s，均自然exit0/0残留/无ERROR。

候选`assets/v3/candidates/west_landing_platform/west_landing_platform.glb`，7,066,076B，SHA256 `a5291b3b620522550b0e59f1e48eb6f4e7c0a556eb05796c53c2f388c25e4af5`。4mesh面数与源表一致，共3,128tri；2材料、6嵌入PNG，不按body复制贴图。身份根与两组均保持identity，无灯、相机、动画、碰撞。

钢3图2048²、漆3图1024²；钢板主顶实际约331.53×344.11像素/米。8块板分别投射各自真实高模浅肋，未将92,928高模三角导出；钢Normal有真实条肋变化。漆Normal量化后为中性(128,128,255)，不能声称明显表面微凸。ORM R=1，非AO烘焙；原基础色不含新烘灯光。原始bake报告的float32 std对常量图有累加误差，`delivery_p1/bake_texture_inspection.json`以实际8bit原PNG及float64统计明确纠正，不重烘或改图。

GLB原始二进制逐三角/绕序/UV/法线、两body父组、每组原Box、嵌图SHA与材料接线通过。同字节Blender回导位置差0、UV最大2.98023e−8、法线最大夹角0.011724°，无零/反向法线。不是实际MAIN渲染或高低位运动通过；不增加离线回导图。

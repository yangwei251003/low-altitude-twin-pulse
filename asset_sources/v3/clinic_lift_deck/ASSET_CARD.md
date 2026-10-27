# I2 ClinicLiftDeck — 真正移动桥板单件

沿 routeId `5e455d78-37b2-423b-b660-0cc3185eae49`、用户已选 I-B。Root 已亲看并批准原生参考与 P1 源图；本件已完成可编辑源、两类 PBR 烘焙、显式 GLB 与同字节数值回导，并复制至独立 candidate。制作代理未运行 Godot；实际运动/碰撞/同光画面仍由 Root 接入验证。已冻结西平台和高低屋字节不动。下文源制作段保留其发生时状态，最终交付记录见末尾。

## 实际对象与制作取舍

亲看正式 MAIN `artifacts/v3/west-landing-20261020_082427_bf3504/01-platform-close-low.png` 与 `05-platform-raised-joint.png`：固定西平台已成为灰钢宽面，正中下方/升起接缝仍是纯浅绿的 `moving_bodies.Deck`。本件只替换该板体可见网格，保留该 body 和全部 9 件原运动/碰撞。这是对既有截图的主观视觉优先级判断，不是本件已通过游戏检查。

`GravityArt` 中的 `DeckStructure` 属于固定 `UpperWorkDeck/ValveWorkPad`，不是本 moving Deck。不复用其名称或拆改其已冻结资产。

九件整体重制会触及北方双连杆、吊杆、横梁和浮子，增加运动身份/细杆净空的工作量；它们在当前画面面积小，不能比先消除中心大色块提供更高的本轮收益。因此不把 9 件合为一个新美术根，不设计新升降机/电机/支腿。

## 精确运动与几何合同

已读取 `i2_clinic_layout.json`、`i2_clinic_water_network.json`、`twin_clinic_water_runtime.gd`、`twin_clinic_waterworks.gd` 及现有测试。原记录与全部 9 件低/高位/连续扫域保存在同目录 `layout_readback.json`，含读取时源 SHA。

| 项 | 合同 |
|---|---|
| 原 body / 大小 | moving_bodies.Deck，4 × 0.35 × 4 m |
| 布局 offset | (0, −0.175, −4)，实际位置 = offset + (0, accepted_top, 0) |
| 运行源原点 | 建议板体中心原点，GLB 根 `ClinicLiftDeck` identity |
| Godot 局部 AABB | X[−2,2]、Y[−0.175,0.175]、Z[−2,2] |
| Blender 映射 | 局部 Godot (x,y,z) → Blender (x,−z,y)，1 单位=1 m |
| 初始实际板体 | 世界 X[−2,2]，Y[3.65,4]，Z[−6,−2] |
| 截止后实际板体 | 世界 X[−2,2]，Y[4.65,5]，Z[−6,−2] |
| 正常行程 / 联合扫域 | 竖直 1 m；本板扫域 X[−2,2]，Y[3.65,5]，Z[−6,−2] |
| 西/东精确接缝 | 世界 X=−2 / +2；两固定 Landing 顶 Y5 |
| 下穿底面 | UnderDeckFloor 顶 Y1；原净高低位 2.65 m，高位 3.65 m |

水槽基底 Y3.5、面积 2 m²，正常从 0 到截止量 2,000,000 ml，对应水位 3.5→4.5，液压目标板顶 = 水位+0.5，即 4→5。槽总容量 4,000,000 ml 不是升降行程；不据容量画出额外 1 m 运动。desired_deck_top_m 是液压设定值，只有原碰撞扫掠被接受后才同步原实体；资产不能自行移动或绕过阻挡。

原 9 件为 Deck、NorthArmLeft、NorthArmRight、NorthDropLeft、NorthDropRight、NorthCrossbar、FloatTopArm、FloatStem、TankFloat。它们逐件同增量平移，`_lift_sweep_clear`逐件检查原 Box，1 mm margin；仅原西/东邻接 Landing 在排除列表。所有其余静态物、机体与道具保留。美术不能外伸去占用或伪装这些空隙。

后续所有可见板体均在上述局部 Box 内；浅肋峰值/螺钉/盖条最高 Y0.175，可通过板面内沉容纳，不加栏杆、支腿、护边、连接舌、下挂电机、灯或贴在 Box 外的装饰。板北缘与现双臂接触，不把臂画入本件或在未来 GLB 中重复。底面闭合，不假作可飞穿格栅。

## 造型 / 材质职责

4 m 方板由 2×2 块宽钢板和 0.35 m 深的闭合边梁组成，横向穿行面不增加实体障碍。与刚通过的西平台采用同族低反射灰钢 + 深蓝青漆；中心保持安静，剥漆/盐渍/短锈痕沿盖边、板缝和少量栓件。主形是浅而结实的活动钢板盒，不是旧浅绿方块、桌子或整座桥。

复用西平台已验 Metal012 钢底、青漆输入与真实浅防滑肋→法线的制作方法；源图/许可证只读复用，不能修改冻结目录。最终为 2 mesh / 2 材质（DeckSteel、DeckPaint），钢三图 2K、青漆三图 1K，按本件实际 UV 烘焙；4 块板共用钢图，不按零件重复材质。不把本概念的照明/阴影直接贴进基础色。实际计数与密度见交付记录。

生成图的浅肋密度/凸度仅为方向；建模须按实际米制间距约 0.12–0.16 m 控制、峰值内收。图中部分角盖看似外凸、板边亮线与锈痕偏连续，不能照图突破包络；后续将以实际 Box 和局部不均匀磨损收束，不另生变体。

## 本轮参考与人工审查

原生 `image_gen.imagegen` 一次，单对象/灰背景/约32°斜视/上左宽面中性光；没有把实机截图作为编辑目标。已观看的实图和原平台参考仅用于提示词与审美校准，来源分别列在 `provenance_v1.json`。

图：`references/v3/production/clinic_lift_deck/clinic_lift_deck_reference_v1.png`，1536×1024，2,491,731 B，SHA256 `b513fc8d7e13d326eaddd24e5026f8acc284042d12eafaa65abf35c94644e8c1`。PNG 为工具原字节复制，原输出保留，无裁切/像素修改。完整提示词 `prompt_v1.txt`、精确工具参数 `prompt_payload_v1.json`、原输出路径与 SHA `provenance_v1.json` 均在同目录。

Agent 判断：方形浅板、四大板、深青边梁可读；没有附加支腿/栏杆/连杆、场景或假灯。板边/紧固处风化比旧浅绿块明确，和西平台同族。细防滑纹在图中仍略密，侧框掉漆比较连续，概念不证明 0.35 m 厚度和每个角盖精确内收。逐项审查见 `REVIEW_v1.md`。不把这张图称作可导入模型或游戏验证。

参考后续已获 Root 批准进入源制作，见下方实际记录；预览窗口已释放。未来实际检查应复用 01 低位和 05 高位接缝，以及默认26m/板下视角，验证两接缝与完整扫域、保留九 body/RID/shape、真实机械链和状态标记不受美术改变。


## P1 源执行与当前结果

Root 实际看参考后批准四宽板/闭盒方向，要求肋按0.12–0.16m米制、减弱连续亮边/均匀锈点、Box内收。必要5原图和许可/来源已复制到本件p1，旧平台代码只读复制并独立改写，无跨目录导入依赖，无原图像素编辑。

源为17个闭合可编辑盒件+24个六角紧固件，共41低模件、1,228实际evaluated三角；拟运行DeckSteel 656/DeckPaint 572，2共享材质。四板各有单独高模浅肋源，共992条/43,648三角，后续仅烘Normal，不进入运行模型。肋周期0.16m、长0.062m/宽0.014m/高0.0015m，避开16个顶栓位置。板面内沉1.5mm，最高仍局部Y0.175；两个运动接边/原9件body不改。

青漆使用原atlas 88%+12%同族底漆混合，顶帽UV裁取较安静的内区；接缝盖片仍保留原边缘磨损，避免所有边均匀银白。钢保留已通过西平台响应/2m米制UV/原NormalGL强度0.25一次。材质依旧是可编辑源节点，源图不是已完成运行PBR。

实际运行`p1/run_preview_20261020_084108_253921/process.json`：PID20448，51.187s，自然exit0、无ERROR、0残留；只此一次源构造+重开+图。外限120s由dev.execute_command私有Windows Job执行，CPU2。窗口已明确归还Root，不自动烘焙或导出。

源`p1/clinic_lift_deck_editable.blend` SHA256 `13c0948a423853e43d96a6b19a35801083dfdc6eef6af07c2bcc881800df2bd5`。原编辑几何/绕序/源UV/组别保存重开hash一致；evaluated位置最大差0、法线最大角差0、UV最大5.9604645e-8，MetricUV为0。未因非活动UV最后位差伪称evaluated位级相同。每件正体积/闭体、实际包络X/Z±2、Y±0.174999997均通过，源图像用bpy.path.abspath解析并真实pixel读回，5图SHA/尺寸/色彩空间与原输入一致。

单件图`p1/01-single-object.png` SHA256 `fc319f07f849c427529d06adbbad57df0a2ab257b7e7084ea87442f663f9b377`。Agent已view原图：四宽板和浅肋可读、深青边梁完整、无共面黑块/洋红；钢面比参考更冷且均匀，顶栓同钢色读感弱。这个差异交Root源图判断，不以数值通过代替美术。尚未实际MAIN或运动/碰撞回归。

## P1 交付完成 — 源图获准，实际游戏待查

Root 亲看后接受主比例和同族关系，明确将较均匀冷灰、弱顶螺钉读感留至实际镜头判断，不继续离线调色。授权后仅运行两阶段，没有重复源渲染：bake PID1996 / 33.860s / exit0，export及同字节数值回导 PID27264 / 3.578s / exit0；均 CPU2、dev.execute_command 私有 Windows Job、无 ERROR、0 owned residual。引擎已明确交还。

`delivery_p1/textures/` 的 Steel BaseColor/ORM/Normal 为2048²，Paint同三图为1024²。四块主钢板的实际UV密度约466.21px/m；992条高模浅肋仅投射至匹配板面，运行仍1228tri。Normal来自真实高模与原细法线，原NormalGL强度0.25仅在源中施加一次，最终NormalMap强度1。实际Paint Normal为中性(128,128,255)，不宣称它有可见微起伏。没有AO烘焙，ORM有效UV内R=1；GLB未挂不存在的遮蔽效果。BaseColor是sRGB；ORM与Normal为Non-Color。六图实际重开/pixels/尺寸/finite/SHA检查通过，Agent亲看钢法线和两张基础色，无品红或串色。

最终候选`assets/v3/candidates/clinic_lift_deck/clinic_lift_deck.glb`，5,767,060 B，SHA256 `3326274d19063c0af717b9c2e766b834162fa5f1cc225c61494a0dcb78ffd1d7`。identity根ClinicLiftDeck下直接为DeckSteel（656tri）、DeckPaint（572tri）；2不透明PBR、6嵌入PNG，与原PNG字节一致。无碰撞/灯/相机/动画，不导出高模肋；原运动body中心即资产原点。

实际raw AABB为[-2,-0.17499999701976776,-2]至[2,0.17499999701976776,2]。原低模位置/绕序三角多重集保持，原source SHA及5原图SHA未变。同字节回导位置最大差0、UV2.98023e-8、法线最大角0.002944°；raw GLB法线最大角0.004657°，与本机glTF四位量化后归一化结果一致，未假称法线位级相同。

可重开编辑源为`p1/clinic_lift_deck_editable.blend`，保留41低模件和4高模肋件；标准PBR交付源为`delivery_p1/clinic_lift_deck_delivery.blend`。选择性清单`delivery_p1/manifest.json`保留这两源、实际相对图依赖、六缓存、单张获准源图、参考/来源、脚本和3阶段日志；不收巨大UV/bake中间源、重复input_snapshot或.blend1。未运行本件Godot/游戏相机/真实运动验证，不把源图或数值回导作为整区美术通过。

# I2 移动桥面单件 · I-B 参考卡

状态：2026-10-19，P4源三图获根批准后，已完成原生PBR烘焙、12分件显式GLB与同字节回导斜视。候选仅在source目录交付，未自行改运行资产/启动Godot；不代表用户单件审美验收或最终美术通过。P1/P2/P3失败与P4原源/图全部保留；交付副本只修短端UV，不重改主体几何/宏观材质。沿用已选 I-B，不重新征选风格。

## 当前 GLB 候选（离线完成，游戏集成待验证）

[完整交付审查](../../../asset_sources/v3/shared_access_bridge_deck/delivery_p4/REVIEW.md)、[实际GLB矩阵/界限/材质读回](../../../asset_sources/v3/shared_access_bridge_deck/delivery_p4/raw_glb_report.json)、[同字节回导图](../../../asset_sources/v3/shared_access_bridge_deck/delivery_p4/same_byte_reimport/01-oblique.png)已保存。候选[shared_access_bridge_deck.glb](../../../asset_sources/v3/shared_access_bridge_deck/delivery_p4/shared_access_bridge_deck.glb)为4,442,516B，SHA `ea8aa0e10f35a637c7deef341471de771e364d9db938f502bd387cb41b9a7c28`；实际12Mesh/12材质面/1PBR/10,912三角/20节点，三张2048²PNG与GLB内嵌原字节一致。

保留完整可编辑12件源、modifiers、源材质与显式角点UV。只对102个X朝向源面修投影，修前后实际几何/角点法线指纹相同。三通道原生烘焙一次完成；两个读取懒加载状态的脚本检查失败已保全并修复，成功通道未重烘。导出与同字节回导自然exit0；短端条纹消失，批准的碎漆语言保持。所有阶段是离线候选证据，尚未验证生产Godot导入、淡出、碰撞/运动或固定游戏相机。

节点合同按本页12件表及raw报告：SharedBridgeDeck→MovingDeck/LockPin为identity，各mesh仍带作者center translation。根挂body须用`Transform(ORIGIN-layout spec.center)*authored`，ORIGIN=(15,5,0)，authored是模型根到mesh累计变换，不能减已移动body.position。原Visual隐藏但保留既有物理合同；BridgeHandle、LockRod/Grip与目标不淡出。三张RGBA8全mip未压缩上界约64MiB，实际导入压缩/驻留和性能未测，不把12surface称实测drawcalls。

历史（P2→P3）：P2实际消除原顶/端共面黑带，防滑厚度和板缝可读，保留12分件/原包络；材质过于新净未通过。当时[P3范围与PBR路径](../../../asset_sources/v3/shared_access_bridge_deck/p3/README.md)只做有成因的下缘盐垢、少量螺栓流锈、抓握露底、通行带和轴承油污；另按根明确授权，在原Deck内补两条6mm承肩，让护板脚实际接地。旧P1/P2源/图/日志保留，当时不放行正式材质/GLB；当前候选状态以上节为准。

**批准作为建模外观依据的 V2**：[修正参考](../../../references/v3/production/shared_access_bridge_deck/shared_access_bridge_deck_v2.png)。本轮在 V1 上原生编辑，保留原材质方向，降低锁件并调整小车分组；下面的源坐标表仍是建模依据，参考图不是尺寸证明。根线程已认可 V1 的材质/薄护板方向，但否决其高锁件和角落轮组；V2 已经根复看，精确12件与运动尺寸仍按生产数据制作。

## P2 / P3 实际历史

P2 CPU2/16samples/同P1三相机，PID20356，127.844秒自然exit0；实际12 Mesh、5材质、20材质面、10,888 evaluated三角（未倒角9,640），包络和独立插销行程保持。完整原日志在[source run](../../../asset_sources/v3/shared_access_bridge_deck/p2/run-20261019_072038_6dc7f8/blender.log)，[回读20/20](../../../asset_sources/v3/shared_access_bridge_deck/p2/source_review_01/readback_validation.json)覆盖源报告、文件SHA、尺寸、UV、姿态/父级与相机相同，不代表视觉验收。

三图均已逐张查看：[斜视](../../../asset_sources/v3/shared_access_bridge_deck/p2/source_review_01/01-oblique.png)、[下方小车](../../../asset_sources/v3/shared_access_bridge_deck/p2/source_review_01/02-bogies-underneath.png)、[低锁件](../../../asset_sources/v3/shared_access_bridge_deck/p2/source_review_01/03-lock-closeup.png)。根结论：护板旧黑带/防滑结构改善可保留，但大面像新喷漆，不能进入正式PBR。近景另发现护板Y0与底板顶Y-.006间存在真实6mm悬空缝；P3获准只补同包络承肩，不重做结构。

P3使用明确米制UV与角点用途属性，风化区域按真实部件坐标确定；普通Python28项静态检查通过，12件、未倒角9,664三角，只有两条承肩新增。实际CPU2三图207.313秒自然exit0，evaluated10,912三角，原文件/报告回读23项通过。三图自审显示盐迹呈人工椭圆白斑、螺栓锈流过于规则、擦痕偏亮；技术遮罩存在不等于外观可信，当前不放行。[P3三图与审查](../../../asset_sources/v3/shared_access_bridge_deck/p3/REVIEW.md)保留原SHA。无运行GLB、Godot物理或游戏镜头证据。

## 单张涂漆钢材候选与 P4 实际结果

根实际复看P3并同样否决材质，授权以原生imagegen制作单张平视钢板底色候选，保留已验证结构和承肩。[painted_steel_material_v1.png](../../../references/v3/production/shared_access_bridge_deck/painted_steel_material_v1.png)为工具原字节副本，2172×724、2,631,351 B，SHA `2ab3fdfab826eddf4736f92c34faeece79ff76278144a0430943a2924d6f50be`；[完整提示](../../../references/v3/production/shared_access_bridge_deck/painted_steel_material_v1_prompt.txt)和[来源记录](../../../references/v3/production/shared_access_bridge_deck/painted_steel_material_v1_provenance.json)留存。没有裁切、改色、拼图或程序画补丁。

实际图含深蓝绿宽漆面、底边不规则碎漆和少量细锈流，未出现要求排除的螺栓/面板缝/把手/白毛团；形状比P3椭圆斑自然，但底部损漆仍偏连续、偏重，上部存在细斑密度。实际像素比例3:1，不是请求的6:1；如将整图映射6×1m，会横向拉伸其形状，不能隐瞒这一差别。图只提供底色与中尺度形状候选，不证明完整PBR、可平铺或实机可读。

根已看图并批准[P4同机位源对照](../../../asset_sources/v3/shared_access_bridge_deck/p4/README.md)，不因宽高再生成。P4源码将两块真实6×1m护板各完整映射一次显式PaintPanelUV，取消P3椭圆盐/锈叠层，原图以.58–.64权重与同色完整漆混合；小五金不重置整幅图，甲板亮白擦痕改为暗磨擦。P3几何与承肩逐字保留，普通Python9项静态检查通过。

P4实际CPU2源三图147.828秒自然exit0，PID41484；12网格/5源材质/20材质面/10,912 evaluated三角，逐件几何/姿态/父级与P3相同。[原三图与完整审查](../../../asset_sources/v3/shared_access_bridge_deck/p4/REVIEW.md)及24项原字节读回保存。根确认自然碎漆/使用痕迹足以进入引擎候选，尚非最终美术通过。Deck短端与护板窄X端盖的X投影退化随后只在独立交付副本修面向UV；源图本身不覆盖。图集烘焙/GLB的后续实际结果见本页顶部，游戏相机仍未验证。

## P1 源首轮（结构候选，外观未过）

[源脚本与运行说明](../../../asset_sources/v3/shared_access_bridge_deck/p1/README.md)、[三图审查记录](../../../asset_sources/v3/shared_access_bridge_deck/p1/REVIEW.md)已保存。Blender5.2.1 CPU2本轮131.031秒自然exit0；实际12 Mesh、5材质、20材质面、倒角后25,712三角（未倒角构造层5,232），保持原包络。根为 `SharedBridgeDeck`，原10个移动件在 `MovingDeck`，`LockRod/LockGrip` 在独立 `LockPin`；唯一显式 `SurfaceUV`。

三张均已逐张查看：[完整斜视](../../../asset_sources/v3/shared_access_bridge_deck/p1/source_review_01/01-oblique.png)、[下方小车](../../../asset_sources/v3/shared_access_bridge_deck/p1/source_review_01/02-bogies-underneath.png)、[低位锁件近视](../../../asset_sources/v3/shared_access_bridge_deck/p1/source_review_01/03-lock-closeup.png)。源材质仍为程序节点，尚未烘焙，不作游戏PBR交付宣称。当前主要差距是涂漆偏浅/偏干净、盐迹均匀长条、防滑面阅读弱；护板顶缘黑带对应已定位的web/hem共面重复面。通用倒角使小螺钉/轮件三角数增加明显。首轮原图/源/日志保留，不自动返修重跑，更未用数值成功代替外观通过。

新建模读取当前生产 layout 原字节 [p1/layout_intake.json](../../../asset_sources/v3/shared_access_bridge_deck/p1/layout_intake.json)，raw SHA `ad357fc68c68692a99f2d5394f8774569e3fa3caceaade0920a917468104b556`，15,854 B。与 V1 冻结 layout 的唯一语义差异是 `labels[1].text` 从“巡检落台 / 新建”改为“巡检通路”；所有非 labels 字段完全相同，几何数值未变。[intake.json](../../../asset_sources/v3/shared_access_bridge_deck/p1/intake.json)保留比较结果。

更新前V2资产卡原字节另存 [I2_SHARED_BRIDGE_DECK_v2.md](../../../asset_sources/v3/shared_access_bridge_deck/I2_SHARED_BRIDGE_DECK_v2.md)，其 SHA 与 `provenance_v2.json` 对应，不拿本页的新字节替换旧证明。V1/V2参考及两份原始 provenance 均未覆盖。当前有实际Blender源网格/源三图、包络与制造子件检查；正式贴图、显式GLB、Godot通行和实际游戏相机仍未验证。

## V2 编辑记录与复查

- V1 图、提示和 `provenance_v1.json` 原字节不变；更新前的完整资产卡另存 [I2_SHARED_BRIDGE_DECK_v1.md](../../../asset_sources/v3/shared_access_bridge_deck/I2_SHARED_BRIDGE_DECK_v1.md)。V1 provenance 中的资产卡哈希对应这份历史副本，不应拿它与本页更新后的字节比较。
- 第一轮使用 V1 作为唯一编辑目标：[prompt_v2.txt](../../../references/v3/production/shared_access_bridge_deck/prompt_v2.txt) → [v2_first.png](../../../references/v3/production/shared_access_bridge_deck/shared_access_bridge_deck_v2_first.png)。小车开始呈现连接车架，杆底缩短，但锁柄/导框仍过高，近侧护板末端被缩短；因此保留失败原图，没有把它冒充满足源合同。
- 随后只针对低位锁件和连续护板再编辑一次：[prompt_v2_lock_correction.txt](../../../references/v3/production/shared_access_bridge_deck/prompt_v2_lock_correction.txt) → 当前 V2。两次均为原生 `image_gen.imagegen`，各自以已查看的上一张本地图为编辑输入；所有输出按原字节复制，没有用程序裁切/画补丁/改色。
- 当前 V2 中，锁柄已明显低于护板顶，导向件降至桥面边梁处，近侧护板恢复延续到短端；原来悬得很长的杆底缩短。可见近侧短端的两轮属于一组连接车架，较 V1 四角轮盒更接近用途；薄板、局部盐蚀、两开放短端保持。
- **仍不能由图宣称精确满足 Y0.475/-0.25、Rod1.1m 或两小车的轴向/包络。** 锁柄的视觉高度仍应在建模时按表固定，不能沿图反推尺寸；远端小车的轮轴朝向和完整车架受遮挡，不能以可见几块轮廓证明其 Z 向长1.2m。单图透视也不能证明桥面6×3.4比例。所有精确尺寸、4片导框和销行程继续以真实12件数据为准。

编辑链、各原图/提示/历史卡/当时资产卡 SHA 记录在 [provenance_v2.json](../../../references/v3/production/shared_access_bridge_deck/provenance_v2.json)。该参考阶段已经结束；根复看后授权进入上面的P1源准备，不再重出参考。

## V1 文件与来源（原字节保留）

- 原生成图：[shared_access_bridge_deck_v1.png](../../../references/v3/production/shared_access_bridge_deck/shared_access_bridge_deck_v1.png)，1536×1024；原字节复制，无裁剪、改色或后期。
- 完整提示：[prompt_v1.txt](../../../references/v3/production/shared_access_bridge_deck/prompt_v1.txt)。调用 `image_gen.imagegen`，新图模式，无图像编辑输入，无 API/CLI 替代。
- 来源与逐项 SHA：[provenance_v1.json](../../../references/v3/production/shared_access_bridge_deck/provenance_v1.json)。原生成文件保留在 Codex `generated_images`，项目副本与之逐字节相同。
- 冻结读取的生产布局：[production_layout_readback_v1.json](../../../asset_sources/v3/shared_access_bridge_deck/production_layout_readback_v1.json)；其原文件是 `data/v3/terrain/i2_shared_access_layout.json`，raw SHA256 `3c7a4812562b9b10fd6aa48fabe363fca3ba22580933ffe22a1dcd8481481358`。该摘要只标明本次读取时点，不替代未来生产布局的最新验收。
- 12 件活动部件的原世界坐标、尺寸与建议单件局部坐标：[source_facts_v1.json](../../../asset_sources/v3/shared_access_bridge_deck/source_facts_v1.json)。没有创建 `.blend` 或运行资产。
- 实际查看过的风格依据：[I-B 单件方向](../../../references/v3/concepts/I-B.png)、[检修滑门参考](../../../references/v3/production/underdeck_door/underdeck_door_v1.png)。仅采用精密制造、蓝绿钢构、灰色金属与沿接缝/边缘分布的盐蚀，不搬入其桥墩、卷帘门或整套场景。

## 本件职责与硬边界

这是一块沿世界 +Z 平移 8m 的步桥活动模块。桥面实体为 **6×3.4×0.35m**，东/西短端用于通行；北/南长边各有 **6×1×0.1m** 护栏。生产护栏当前是连续实心盒，所以参考采用薄实心折边护板；不能照开放细栏杆造型保留一整面不可见挡墙。

建议资产根设在公共端点的桥面顶中心 **world (15,5,0)**，Godot 局部 +Y 向上、X 沿过桥方向、+Z 沿移动方向。这个源原点是从现布局推导的工程建议，不是栅格图量测。整体根随桥移动；独立锁销在根内再沿 **-Y 0…0.3m** 伸出。制作源保持插销缩回态，插入态由包装应用。不可把锁销与桥面合成无法独立运动的网格。

| 现生产件 ID | 建议资产局部中心（m） | 现碰撞尺寸 X/Y/Z（m） | 约束 |
|---|---|---|---|
| BridgeDeck | (0,-0.175,0) | 6 / 0.35 / 3.4 | 顶 Y0，底 Y-0.35，连续可行走实体 |
| NorthGuard | (0,0.5,-1.65) | 6 / 1 / 0.1 | 北长边，X 两端不加横向门栏 |
| SouthGuard | (0,0.5,1.65) | 6 / 1 / 0.1 | 南长边，同样保持短端开放 |
| WestCarriage | (-2.83,-0.555,0) | 0.24 / 0.41 / 1.2 | 单个沿 Z 的小车，不能变成角部万向脚轮 |
| EastCarriage | (2.83,-0.555,0) | 0.24 / 0.41 / 1.2 | 与西侧共两组；两轨中心距 5.66m |
| BridgeHandle | (-2.5,1.1,-1.65) | 0.3 / 0.2 / 0.1 | 位于北边西端；真实推拉靶，不改成曲柄转轮 |
| PinBracketLeft | (2.25,-0.25,-1.88) | 0.14 / 0.1 / 0.36 | 桥下外侧导向框的一边 |
| PinBracketRight | (2.55,-0.25,-1.88) | 0.14 / 0.1 / 0.36 | 不封死中间插销运动通道 |
| PinBracketFront | (2.4,-0.25,-1.76) | 0.16 / 0.1 / 0.12 | 随整桥移动，不随销上下 |
| PinBracketBack | (2.4,-0.25,-2.02) | 0.16 / 0.1 / 0.08 | 外缘 Z-2.06，超出桥面是现有功能构件 |
| LockRod | (2.4,-0.15,-1.9) | 0.1 / 1.1 / 0.1 | 缩回态；向下行程 0.3m，不能被装饰壳包死 |
| LockGrip | (2.4,0.475,-1.9) | 0.3 / 0.15 / 0.3 | 跟销上下；高度低于护栏顶，不以图中较高把手为准 |

以上小数是生产 JSON 的可读四舍五入；源记录保留原双精度值。缩回态整体 AABB 约 X[-3,3]、Y[-0.76,1.2]、Z[-2.06,1.7]；全插入时最低 Y-1.0。它不是只包住桥面板的 6×3.4m 矩形。未来模型任何额外螺栓/折边必须在实际通行、扫掠与操作射线约束内，不能用这张图扩碰撞包络。

两条固定轨道、轨道支撑、公共端悬臂插座/巡检端插座、落台、固定绕廊、继电器与双控制器 **不属于本单件**。尤其当前公共端固定插座已由悬臂承托，不可又在移动桥上造一根落地立柱。参考中的小车只提示实际轮组外观，不需要画整段固定轨道。沿 X 的东/西出口保持完整通行，桥下原走廊和既有 Trial 操作路径不能被新装饰挡住。

尚无本件经过授权的三角数/材质数预算；不把任务里的“8k?”当成已定上限。建模阶段应先确保轮廓、两运动组、真实窄件与贴图分层，再报实际统计，由主线程结合目标设备裁定。参考图的密集防滑纹、螺钉和盐斑不意味着都要增加几何。

## 参考阶段外观方向与分件建议（历史）

保持薄而结实的蓝绿折边钢护板、灰色实心防滑面、低调深钢色轮组；两处真实手柄用少量磨损赭黄作为操作提示。盐迹来自竖向接缝下方，锈迹局限于露钢、紧固件、积水边缘，抓握与轮面表现为被磨亮；大面留出不均匀的安静区，不铺均匀脏噪声。

未来可编辑源建议保留 `SharedBridgeDeck` 总根、静态桥面/两护板/两小车/外框，以及 `LockPin` 独立运动父节点（Rod/Grip）。手动靶和销靶应有与上表一致的明确锚点。此处只是后续源拆分建议，不是已经导出的节点契约；材质、UV、显式 GLB、运动枢轴与坐标转换尚未做。

## V1 首轮图片实际审查（历史）

可采用的部分：画面确为一个孤立活动单元，没有整岸/桥墩/楼梯；短端开放，长边薄护板和板层厚度可读；制造边缘、低饱和蓝绿与沿下缘流淌的盐蚀，符合 I-B 的局部风化方向。手动柄和外侧独立锁杆能被区分，主层次可拆成有限可编辑实体。

必须修正或尚不能从图证明的部分：

1. **锁销把手被画在护栏顶附近，导向盒也抬到护板表面。** 生产 LockGrip 是局部 Y0.475，四片导框在 Y-0.25；建模应按真实低位外支架与 0.3m 行程重排，不能把图的高位长杆直接用于操作靶。
2. **轮组读成四角小脚轮。** 生产是 X±2.83 的两组沿 Z 纵向小车，每组包络 0.24×0.41×1.2m；需要按两条固定轨的方向还原轴/轮，而非复制图里可见的每个轮盒。底部被遮住的结构不作为四面完整设计证据。
3. **防滑花纹偏密，薄板接缝与局部锈迹也较密。** 后续应在实际 26m 相机检查是否闪烁或糊成均匀灰噪声；不能用缩图看着丰富来宣称可读。精确长宽比例、10cm 护板厚度、把手净空、所有背面和三角碰撞都无法由一张栅格参考验证。

因此本图可供根线程裁定外观与建模方向，但不作为几何等比样板，更不算单件还原通过。下一阶段仍需根确认后再制作可编辑源，随后检查真实节点/尺寸/两端开口/全程插销与桥扫掠，以及生产固定相机；本轮未启动 Blender、Godot、GPU 捕获或网络。

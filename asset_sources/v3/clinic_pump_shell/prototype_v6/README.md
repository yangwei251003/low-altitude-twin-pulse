# V6 屋面材质原因对照（独立研究，不是整件新版验收）

只读冻结 V5 源，自建节点，只使用 ambientCG Metal012 的四张 PNG。没有加载 vendor .blend / mtlx / tres 脚本；mtlx 只作文本核对图种。CC0 原始来源与 SHA 由 root 放在 vendor/provenance.json，研究结果再次记录。图像只原字节复制，不编辑像素。

同 V5 几何、镜头、灯光、曝光与 AgX。仅隐藏下部以隔离屋顶；1024×720、8 samples、CPU2 预期50–80秒。三张分别为 A原V5、B原色图+真实metal/rough/NormalGL、C完整Metal012+边缘稀疏污迹。B并不能单独区分粗糙/金属/法线每一项，但能将颜色图语义与响应模型分开。

真实 V5 已保存节点在运行时从实际 RoofZincPanel_0 材质读取所有有效上游节点，避免把脚本文字/旧未连接节点当实际接线。已知代码把整屋面设为 .36–.65 metal、.42–.66 rough；这可能保留介电漫反射并模糊反射，但不是已证明的唯一失败原因。大白斑、色图微法线、均匀反射环境同样是候选原因。

Metal012：Color 为 sRGB；Roughness/Metalness/NormalGL 为 Non-Color；Normal Map 使用相同 SteelUV 的切线空间，不翻绿、不接 NormalDX。四图共同使用作者明确设定的2m尺度，不把它说成来源实测尺度。无 displacement，模型几何摘要必须仍等于V5。C只在18cm边缘带由原atlas控制少量非金属污迹，中心完全不受旧白斑影响。

官方资料：

- [Blender 4.5 Principled](https://docs.blender.org/manual/en/4.5/render/shader_nodes/shader/principled.html)：本轮搜索返回正文已读取，金属度是介电/金属混合，纯金属没有漫反射基底。latest直接抓取402，未伪称已读latest。
- [Blender Normal Map](https://docs.blender.org/manual/fr/4.5/render/shader_nodes/vector/normal_map.html)：本轮搜索正文核实切线法线图需匹配UV、Non-Color。
- [Metal012](https://ambientcg.com/view?id=Metal012)：官方列为银钢、刷纹/划痕PBR。
- [ambientCG许可](https://docs.ambientcg.com/license/)：资产及预览CC0，原始资源可随项目分发。

三图已实际查看，详见 [实际视觉审查](evidence/visual_review.md)。B 保留石板读感，C 消除整面白斑，说明先前色图语义是明确问题；仅换响应不能补救。C 仍均匀平，只有底材可继续，并非整件美术通过。固定灰色世界缺少复杂倒影，本轮也没有用换灯光来取巧。

实际执行 PID 35712，47.0474 秒、自然 exit 0。保存后重开核对六张图路径/加载/哈希；200 编辑件、7,584 三角及几何 SHA 与 V5 相同，V1–V5 共 84 个冻结文件未变。没有烘焙、GLB或运行资源；CPU2 窗口已明确释放。

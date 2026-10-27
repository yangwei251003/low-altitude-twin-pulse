from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
load=lambda n:json.loads((HERE/n).read_text(encoding='utf-8'))
s=load('source_report.json');e=load('export_report.json');r=load('glb_readback.json');b=load('bake_report.json')
assert s['all_pass'] and r['all_pass'] and e['glb_sha256']==r['glb_sha256']
text=f'''# F1 升降封印闸 P2：独立集成候选

本目录交付可编辑源、外部 PBR 贴图、显式候选 GLB 和同字节回导图。当前是开发集成候选，**不是最终美术通过**。本代理没有启动 Godot、修改运行场景或验证真实升降/防夹/联机。P1、原参考及共享文档保持只读。

## 采用依据及具体改变

已完整读取共享 F1_RISING_SEAL.md 与单件 provenance-v1.json，实际查看批准 reference_v1、P1 首版/第二版以及本轮各图。参考不是游戏截图。

- 保留 1×5×7 米整体升降包络、底接面及原核心/锚点。六块石体从背至前具有真实厚度、少量非共面宽切面与不等宽边带；缝后有闭合石底。
- 两侧连续圆厚主根穿过顶角并贯穿正面到底，支根经 Exact Boolean 形成连通主叉；根附近石体切浅床。新增下段宽叉保留，新增两个顶小叉因实际角度被遮成尖片撤去，没有为装饰扩大切石。
- 铜带进入真实浅槽、扣件连续跨顶/底边。旧悬贴直片及其小铆点被替换，不再宣称铜件与 P1 原样相同；核心与锚点仍保持 P1 原几何及变换。
- 石色保持冷灰低对比大面，不恢复 Voronoi 迷彩。木材纵向纹理与真实圆厚截面配合；材质变化不是用来冒充额外岩块体积。
- source 保留独立网格和隐藏根构造分件。运行导出只在副本上按四材质合并；源未被合并覆盖。

## 实际交付与验证

- 可编辑几何/作者材质：`rising_seal_source_p2.blend`，SHA `{s['source_sha256']}`。
- 保留 UV/PBR 且仍可编辑：`rising_seal_p2_export_ready.blend`，SHA `{e['ready_sha256']}`。
- 候选 `{e['glb']}`，{e['bytes']:,} 字节，SHA `{e['glb_sha256']}`。
- 当前源检查 {s['passed']}/{s['total']}；真实 GLB 读回 {r['passed']}/{r['total']}，{r['triangles']:,} 三角，4 个网格、4 个材质，{r['images']} 个内嵌图像。实际 bounds（Godot） `{json.dumps(r['bounds_godot'])}`。
- {len(e['maps'])} 张外部 PNG 位于 `textures/`：石/木 1536，铜 1024，核心 512；各含基础色、粗糙度、OpenGL 切线法线。烘焙只取材质，不取 AO/灯光/阴影。原细节 UV 与目标 `SurfaceUV` 分开，运行导出仅 UV0，材料实际绑定 UV0。
- 三个实际锚点 `{json.dumps(r['anchors_godot'])}`。完整节点与碰撞建议见 `CANDIDATE_CONTRACT.md`、`glb_readback.json`。
- `rising_seal_source_p2.png` 是当前可编辑源离线基础图；`rising_seal_p2_same_byte_glb_preview.png` 是删除全部作者几何后实际导入上述相同 GLB 字节得到的离线图，CPU 2/同一 P1 相机/12 samples。都不是游戏图。

闭边、正体积、根连通、范围和接口检查不等于独立全面三角自交审计。此次对同顶点三角做了专门重复检查，最终重复组为 0，但不据此声称排除了所有非重合面的共面包含或穿插。石分件与缝底交埋属于设计，不能声称它们已成为单一无重叠并集。游戏运动、碰撞、防夹、同步、真实光照和性能仍由根线程接入测试。

## 保留负面证据与未解决差距

1. `envelope_reject_v1/`：第一次源超 +X 包络 6.74mm，36/37，停止出图。数据文件原字节保留；其中历史脚本由记录的逆补丁恢复，没有独立捕获旧哈希，这个限制在 archive.json 写明。
2. `occluded_roots_v1/`：37/37 但视觉读成四断根的首图，9 文件在新编辑前原字节归档。数值通过未用于掩盖失败。
3. `continuous_roots_v2/`：35/35 的连续主根版，根实际审图通过连续性，9 文件原字节冻结；不等于最终艺术通过。
4. `refinement_occluded_fork.*` 与 `pre_*.png`：新增顶叉/铜扣首次细化的负面图；源、图或报告按各文件真实保留情况列示，不冒称每一历史尝试都有完整独立源链。`refinement_node_lookup_failure.log` 保留按本地化材质节点名查找失败，后改按节点类型读取。
5. `boolean_boundary_failure.log` 和 `boolean_boundary_diagnostic.json`：去掉顶小叉后，Exact Boolean 在 StoneMass_03 留下一个约 0.002004 平方米三角缺面。只对记录的三个顶点补面，未改宽度/闭合门槛；最终源报告有具体修复坐标。
6. `bake_uv_handle_failure.log` 和 `bake_uv_handle_crash.txt`：首轮烘焙在已失效的 UV 层句柄读取时软件崩溃。修为在模式切换后重新取 `SurfaceUV`，先复制纯坐标再传回源对象，完整重跑退出码 0。未把首轮的部分贴图当成功。官方文档抓取本次不可用，诊断依据本机崩溃栈及复跑结果。
7. `ngon_geometry_diagnostic.json`：合并 n-gon 导出最初改变了石组 6 片三角的对角线；改为在导出副本上使用作者真实 loop triangles 并保留 UV/法线，原始 GLB 的三角多重集现在严格等于源。
8. `pre_coincident_cleanup/`：完整保存局部清理前的 12 个源/ready/GLB/报告等原字节文件。只读分析找到 20 对同一石块、相同三顶点 ID、相反绕序的零厚薄面，总面积约 0.001289 平方米；12 对默认相机被遮，8 对可能可见，并非相邻石块共享接触面。根授权后仅抵消这 20 对（40 三角），不移动顶点、不重构整石体、不改其余唯一三角。源总数从 18,568 降到 18,528，闭合/正体积/根/包络仍 27/27，最终实际重复组 0；原始GLB及回导核对全过。位置、法线、面积的历史证据在该目录，当前 `duplicate_face_classification.json` 是清理后结果。
9. `review_studio_copy_failure.log`：36 项已经通过但演播室复制对象被清理列表误删，未产图；改为删除复制前的原对象清单后，同字节重跑完整退出码 0。此修复不改变任何候选字节。

目前六块石面的边带仍偏整齐，主根局部切端与表面比批准参考干净，金属缺少更丰富的局部氧化/磨边。真实游戏相机下的可读性尚待根验证；不能把拥有贴图、导出成功或离线图称为完成还原。

`source_report.json`、`bake_report.json`、`export_report.json`、`glb_readback.json` 是各阶段实际读回；`manifest.json`、`selfcheck.json` 只证明文件/哈希与引用完整性。构建脚本会覆盖当前候选，冻结后不要自行重跑。
'''
(HERE/'README.md').write_text(text,encoding='utf-8')
contract=HERE/'CANDIDATE_CONTRACT.md';t=contract.read_text(encoding='utf-8').replace('计划导出根','实际导出根');contract.write_text(t,encoding='utf-8')
print('Notes refreshed from actual reports')

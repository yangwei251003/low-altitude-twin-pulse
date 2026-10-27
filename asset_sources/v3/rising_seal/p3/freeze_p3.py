from pathlib import Path
import json, hashlib, datetime
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda n:json.loads((HERE/n).read_text(encoding='utf-8'))
sr=load('source_report.json');ex=load('export_report.json');rb=load('glb_readback.json');bake=load('bake_report.json')
assert sr['all_pass'] and rb['all_pass'] and bake['geometry_unchanged']
assert rb['triangles']==18528 and rb['total']>=36
assert 'SEAL_SAME_BYTE_PREVIEW_DONE' in (HERE/'verify_p3.log').read_text(encoding='utf-8',errors='replace')
assert 'SEAL_P3_MATERIAL_SOURCE_DONE' in (HERE/'build_p3.log').read_text(encoding='utf-8',errors='replace')
assert all(sha(ROOT/p)==h for p,h in sr['input_hashes'].items())
assert sha(ROOT/ex['glb'])==ex['glb_sha256']
readme=f'''# 升降封印闸 P3：纯材质候选

本件保持 P2 形体；不是最终美术通过，未替换运行资源。P2 实机历史批次为 `artifacts/v3/art/20261018_070126_seal_p2/`，7 图、16 项运动/通路等检查通过，但石面平灰、木纹远处密线和核心读色被根退回。P3 先实际查看该批次 03/05、批准单件参考与独立石材素材后制作。

## 材质改动

- 石材使用原生 imagegen 的独立图 `references/v3/production/materials/temple_stone_surface_v1.png`，1254×1254，SHA `6f139127394eb9c59913f6fdd66dec510c18a658460efd594a9fd73475c939a8`。完整提示词/工具来源在同目录。原图未编辑，已嵌入可编辑源。它不是 PBR 套件、三维结构或游戏画面。
- 所有石块共享根对象米制坐标，4 米覆盖一张、BOX 混合 0.18；主面仅 57% 图像与冷灰底色融合，磨边 43%，缝底 30%，不把整张图重复塞进每块石头。原图自带暗缝仅作基色，法线与粗糙度由独立低频节点生成；没有把黑缝当成物理凹洞。图像循环接缝尚未单独证明无缝，必须在游戏镜头看其权重。
- 根取消旧 Scale 6 与 X4.5 叠加的细 Wave 凹纹。保留原顺根 UV，首轮单用低频 Noise 后实际图过于光滑，原字节保留在 `low_grain_v1/`；本轮改 Wave Scale0.68 / X3 / 低轴向频率，带噪声扭曲与较宽色带，配独立 0.76–0.91 粗糙度和温和凹凸。宽带仍有规则条带读感，后续实际镜头判断；未改截面、顶点、叉根或切端。
- 铜色改为较克制的深黄铜/局部磨损，避免铜绿抢核心。核心仍是唯一青绿发光材质，基色与粗糙度改善，离线/GLB 基准 emission 为 0.75。
- 注意：共享包装 `set_gate_state` 会覆盖核心色为 `43a595`，亮度闭合 0.12 / 供电 0.38 / 全开 0.65。因此 GLB 的 0.75 不能证明实机亮度已解决；根会在后续 P3 同镜头评审中决定状态亮度。

## 保持的接口与验证

从冻结 P2 可编辑源打开后只换材质；没有调用 P2 造型重建脚本。几何顶点、polygon 索引、所有变换和 Centre/BottomContact/StateInlay 三锚点的摘要完全相同。P2 源、P2 UV/PBR 源及 P2 GLB 的 SHA 在制作前后保持。

- 显式候选：`{ex['glb']}`，{ex['bytes']:,} 字节，SHA `{ex['glb_sha256']}`。
- 18,528 三角；4 网格：StoneMasses / LivingRoots / BronzeFittings / SealEnergyGlass；4 材质：SealP3_stone / SealP3_wood / SealP3_bronze / SealP3_core。
- 锚点 Godot：Centre=(0,0,0)、BottomContact=(0,-2.5,0)、StateInlay=(0.49,-0.1,0)。范围保持 P2 的 X[-0.3655000031,0.4900000095]、Y[-2.5,2.4667613506]、Z[-3.4564738274,3.4521043301]。
- `source_report.json`：{len(sr['checks'])} 项材质改动前后不变性检查。P2 的 27 项造型检查标为继承历史证据，不伪称本轮重新做了游戏物理。
- `bake_report.json`：4 组各基色/粗糙度/切线法线，共 12 张外部 PNG。基色和粗糙度通过 Emission 烘焙以排除棚拍光照；法线独立烘焙。木/石1536²、铜1024²、核心512²。DetailUV 与 SurfaceUV 明确分开，模式切换后按名重取 UV 层，未继承旧 RNA 句柄错误。
- `glb_readback.json`：{rb['passed']}/{rb['total']} 通过，保留原 36 门槛并新增 P2 比较。除按 0.1mm 量化的源/原始 GLB 三角多重集严格相等外，还比较 P2 与 P3 原始 GLB 经节点变换后的浮点三角坐标，不进行四舍五入；全部相等。实际 Blender 回导也要求完整三角多重集相等，不再容许导入器删除重复面。
- `rising_seal_p3_same_byte_glb_preview.png` 是删除作者几何后，从冻结候选字节实际回导的离线图；源图 `rising_seal_source_p3.png` 不是游戏画面。CPU2、Cycles，当前链路没有启动 Godot。

## 尚未解决或验证

P2 六块石板仍偏规则，连续根仍有软藤读感与小切端，P3 未做形体外科。石材图片中的暗缝/细节是否在默认镜头仍偏密、循环接缝、核心状态对比，须由根的实际游戏镜头决定。没有真人、网络、全游戏性能或最终美术结论。

## 复现

现有 Blender 5.2.1，固定 CPU 2 线程，依次运行本目录 build_material_p3.py → bake_export_p3.py → verify_glb_p3.py；加 `--python-exit-code 1`。源/运行路径均为新 P3，P2 只读。工具窗口先与根协调；勿与 GPU/性能任务并发。
'''
(HERE/'README.md').write_text(readme,encoding='utf-8')
files=[p for p in HERE.rglob('*') if p.is_file() and p.name not in ['manifest.json','selfcheck.json'] and '__pycache__' not in p.parts]
files+=[ROOT/ex['glb']]
items=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(files)]
manifest={'stage':'P3 standalone material candidate; pending actual game review','created_local':datetime.datetime.now().isoformat(timespec='seconds'),'inputs':sr['input_hashes'],'files':items,'limits':['offline preview only','no geometry changes','P2 frozen','not final artistic acceptance']}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
checks=[{'path':it['path'],'exists':(ROOT/it['path']).is_file(),'sha_match':sha(ROOT/it['path'])==it['sha256']} for it in items]
result={'scope':'file/hash integrity only','files':checks,'passed':sum(v['exists'] and v['sha_match'] for v in checks),'total':len(checks),'readonly_inputs_unchanged':all(sha(ROOT/p)==h for p,h in sr['input_hashes'].items()),'manifest_sha256':sha(HERE/'manifest.json')}
(HERE/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'glb_sha256':ex['glb_sha256'],'readback':f"{rb['passed']}/{rb['total']}",'files':f"{result['passed']}/{result['total']}",'manifest_sha256':result['manifest_sha256']},ensure_ascii=False))

# F1 thermal P3：实际源轮完成，等待视觉决定

2026-10-20 源轮 `runs/20261020_100415_51449c` 已自然exit0：PID14468、39.594s、0残留、22输入不变、源与重开报告一致。唯一同机位源PNG已实际查看，详见 `RESULT.md`；未bake/export/Godot。以下静态说明保留为本轮设计输入。

仅响应P2审图退回的三项。P2成功源图、首败和输入闭包全部保留；P2改善了石块/石环，但没有美术通过。P3不改变石块分区、石环、原3×2×2碰撞合同、相机/照明、温度规则，不增加灯或杂物，不自动烘焙/导出。

## 有证据的修改

1. **根的连续截面。** P2按高度1.48/.20m硬切向外/向上frame，源图出现折痕。`root_geometry.py`改为相邻切线的最小旋转平行输送，只在Y.10–.34m用连续权重逐渐对齐地面。上身椭圆比例约.805–.915，保留轻微不均匀三脊；只有根脚趋于.30。根体半径主.156m、前.132m，原前根−Z50mm已在顶点中应用一次。端脚落到距Y0约.17–.62mm，仍没有越过原Box。不是全根压扁成带。
2. **恢复真实笔触尺度。** 已实际查看的FB_stone_BaseColor是一整张手绘纹理，P1/P2却把它按4×4分格采样。P3改显式PaintUV：主体/环.52 UV/m（周期约1.923m），较长底基.34 UV/m以完整容纳，不修改PNG像素。原笔触线性颜色以.18为中心做1.55倍对比并移至.24；CORNER `StoneTone`只给顶部暖砂与侧面冷灰，`StoneWear`只在少量实际小倒角面上作克制暖磨边，不画全表面白裂网。normal强度保留.28。
3. **晶芯实际切面。** 18个不等角扇区、不同半径的三环、偏心小峰，使用明确三角面；中性底(.61,.64,.61)和低强度预览温色不变，CORNER `CoreFacet`仅做约±11%的中性明度差，不编码温度/损坏事实。

厚石/环仍调用冻结P2构造，不换摄影棚。最终六mesh/五材质仅为后续合并目标，当前没有GLB。P3两根和核心最终三角数由实际Blender审计给出，不将静态估数写成实际交付。

## 静态结果与待验证

`static_root_check.json`来自源制作也直接调用的纯Python根生成函数，未加载Blender。两根闭边/包络通过，最大相邻frame角分别5.525°/2.620°；它只能排除原不连续公式和明显越界，不能证明图像自然、法线/颜色正确。

source入口仍会检查实际Blender逐对象边界、闭边、正面积、PaintUV、材质与新增命名角点属性；保存后重开读回。源图判定仍由同机位实际渲染决定。未来烘焙副本必须保留命名PaintUV/StoneTone/StoneWear/CoreFacet，不能让新BakeUV激活后隐式切换源取样；温色预览节点不得烘入中性底图。

运行入口（仅Root授予窗口后）：

```
python asset_sources/v3/f1_thermal_stone/p3/run_source.py --run
```

默认不运行；CPU2/privateJob硬240s，只源+一张1100×900原机位图+重开，预计40–60s，以实际时间为准。静态runner输入清单22项，真实运行仍记录前后哈希；不沿用P2输入个数。

## 方法核查

复用既有routeId的恢复检查，没有新安装需求。已核官方[Color Attribute实现](https://github.com/blender/blender/blob/main/source/blender/nodes/shader/nodes/node_shader_vertex_color.cc)：显式layer_name按属性名取值，空名才退回active color；本源全部显式命名。官方[UV Map说明](https://docs.blender.org/manual/en/5.0/render/shader_nodes/input/uv_map.html)与[Mathutils索引](https://docs.blender.org/api/main/mathutils.html)的搜索摘要可读，但本次全文入口返回402，故不宣称已全文读取。根平行输送使用自包含数学函数，不依赖未核对的Blender旋转API。

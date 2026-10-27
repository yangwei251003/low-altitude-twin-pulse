# P8：天然粗分叉来源结构研究

仅来源对照，无拉伸、材质纹理、雕刻、运行导出或完整岸肩。根已实际查看 `branch-source-structure.png`，认为天然粗叉比 P7 拉长树基可信，后续另在 p9 数值推演。P8 图不是实机，不是最终造型通过。

## 原件与实际分类

只读已有 `asset_sources/third_party/island_tree_01/island_tree_01_1k.gltf/.bin`。来源为 [Poly Haven Island Tree 01](https://polyhaven.com/a/island_tree_01)，作者 Rico Cilliers、Rob Tuytel，使用 [CC0](https://polyhaven.com/license)。未下载新模型。

| mesh0 primitive | 实际元数据 / 几何 | 本轮判断 |
|---|---|---|
| 0 | 19,345顶点、34,787三角；材质`island_tree_01`，无alpha混合；位置缝合统计为1个连续组件 | 木质主体含树基、粗干及真实分叉；实际对照图证明分叉形态，不只依赖材质名 |
| 1 | 927,528顶点、1,060,032三角；材质`island_tree_01_leaves`，alphaMode BLEND、叶片贴图 | 排除叶片；只读metadata，未解码或加载叶片几何 |
| 2 | 357,055顶点、504,584三角；材质`island_tree_01_branches`，不透明 | 只读拓扑统计约8,357个组件，最大132三角，非一条连续厚主干；不加载到Blender |

组件统计用位置各轴保留5位小数合并UV缝后，按真实三角边做并查集；它是来源筛选统计，不是引擎碰撞或精确流形验收。

## 唯一对照图

`branch-source-structure.png` 为 Blender 5.2.1 LTS 单次 CPU2、12 samples、1680×960 基础色离线渲染。左是完整primitive0木质骨架，展示均匀比例1.35；中是 glTF Y0.85..1.80 的真实粗分叉裁片，展示均匀比例2.35；右为同一裁片刚性转155°。没有非均匀缩放、连续变形、减面或新增分叉。

裁片为12,190三角，实际原单位包络 `min(-0.800107,0.85,-1.429682)`、`max(1.146300,1.80,0.645979)`。新裁口封面单独基本色，原始面编号、截面与材质metadata见 `branch_source_structure.json`；可编辑源 `branch_source_structure.blend`。原件前后SHA不变；执行日志 `build-branch-source.log`，exit 0。

## 适配判断与下一步边界

这次找到真实的不等粗连接、弯曲和分叉肩，适合作为局部根系形体来源。仍是地上枝干而非地下根扫描；片段同时含长细侧枝，不能全部放大当承重根。当前截取过短，缺少由厚树基延伸到分叉的完整主干，不能直接拼进岸肩。

下一步已由根限定：p9 保留较完整的下部约Y0.1..2.2/2.4，统一缩放3–4倍并刚性倾转，使厚树基在高端、较细分叉在低端；先计算可达长度、宽度、接口差距，不拉伸填跨度。若不合适，停止复用并走有主干/分叉体块与局部雕刻的原创路线，不重复 P7 的轴向拉长。

额外官方窄检索确认有 [Root Cluster 02](https://polyhaven.com/a/root_cluster_02) 等CC0根簇，但本轮没有足够结构证据证明更适合，故未下载或声称胜过当前粗叉。只保留来源记录，不扩大资源库。

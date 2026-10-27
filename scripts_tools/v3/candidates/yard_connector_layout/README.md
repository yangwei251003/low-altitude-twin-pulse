# 西南前场：实际残余地表输入

2026-10-20；route `5e455d78-37b2-423b-b660-0cc3185eae49`。只读生产，不安装新铺面，不修改碰撞。

## 当前边界

dev27 最终五图的输入清单与本次 18 个几何依赖逐字节一致，但该证据未保存最终 ArrayMesh 原数组。**当前实际可见面积仍未知**，不以候选矩形面积或规划估计冒充测量。纯 Python 的 7 项合成边界检查已通过；Godot 导出等待 Root 明确独占窗口。

导出在真实 `TwinTestWorld` 入树后 `build("I2")`，读取 `waterfront_install.meshes.dry_surface` 的 `surface_get_arrays(0)`，再与最后检修井安装返回的 `inspection_pit.remaining_visual` 完整属性 SHA 对比。不能读取初始 `waterfront.geometry()`，也不能用 `Mesh.get_faces()` 的量化 BVH 顶点代替 GPU 原数组。

实际安装顺序：原地面/院面 → 航槽 → 西护岸 → 东护岸 → 东维护延铺 → 护岸折段 closure → 检修井/井艺术。工具只在这些安装成功后读取最终表面。

## 裁域及保护

- 上限为 world X[-24,12.6]、Z[10.5,28]，顶 Y0。原点 (-5.7,0,19.25)，Godot Y-up、identity。
- 原院216m²和接诊引道72m²、井口、护岸精确顶盖已经从最终表面扣掉；检查它们实际没有残余交叠，不按斜岸猜退距。
- 另按实时 BoxShape3D 的世界矩形保留 WestFoot2 和六块泵房落地结构（floor、两侧墙、北墙、两门垛）。不把悬空屋顶投影当作禁铺区域；实际门洞不填成墙。
- `visible` 是可替换的新可见域，`remainder` 包括界外及结构下应保留部分，`under_structures` 只用于说明扣除量。三者来自同一原始三角裁剪；保留原最终三角 ID、normal、UV、真实 tangent。当前生产 Reader 明确要求原数组存在合法 tangent，若不满足则失败，绝不补假 tangent。
- 0.0005m² 仅沿用生产 float32 面积累计误差界，不移动切面、不扩大保护、不补微缝。源/碰撞/RID 读取前后须相同。

## 运行和交付

Root 明确窗口后才运行：

```powershell
python scripts_tools/v3/candidates/yard_connector_layout/run_export.py
```

继承 CPU2 affinity、现有 dev 私有进程树、外限60s/内部45s。每次 fresh 目录拒绝覆盖；只读构造 World，不启动 Session、存档或物理推进。日志/选定源快照在 `tests_v3/candidates/yard_connector_layout/evidence/<id>/`，实际数据在本目录 `exports/<id>/`。未新增工具安装。

`geometry.json` + `.f32le` 保存世界 float32 顶点/法线/UV/tangent 原字节与 SHA，裁剪生成的角点同样存 float32。`derived/visible_triangles_world.json` 给可读三角及原面 ID；`boundary_world_xz.json` 使用现有 Shapely 2.1.2 对真实三角做并集，不 snap/buffer/简化/凸包，不修补微小缝隙。真实原数组始终是权威输入。

`yard_visible_blender_local.obj` 仅坐标转换为 `(X-originX, -(Z-originZ), Y)`，Godot 顺时针面转 Blender 逆时针；无厚度、无材质、无假地形。艺术制作应沿实际剩余域、不缩放，米制材质相位连续。这里的精确原域不包含以后为接既有 tile 半缝而做的可见收边设计；不能凭此导出声称美术/新碰撞已经通过。

# I2 低模候选：部分交付，整批非 PASS

实际运行：`runs/20261021_021300_adedde/`。主 Agent 串行执行 Blender；runner 用时 **8.984 秒**，所属进程残留 **0**，5 个原 GLB 的前后 SHA256 全部一致。
`result.json` 有 4 个候选、1 个取消；完整批次不是 PASS。未再次运行或调整取消门。

**四个候选尚未经过实际默认相机、生产碰撞精确比较或包内性能验证。**
结果中的 `camera_verified=false` 继续有效，不能把几何过滤通过写成画面/碰撞/性能验收通过。

## 五件实际结果

有效 GLB 基目录：`assets/v3/environment/i2_visual_lod/20261021_021300_adedde/`。
可编辑 blend 基目录：`asset_sources/v3/i2_visual_lod/runs/20261021_021300_adedde/`。

| 件 | 源 tri → 候选 tri | mesh / surface / material | 产物与可编辑源 | 结果 |
|---|---:|---:|---|---|
| 4m 护岸 | 5,152 → **1,804** | 1 / 1 / 1 | `revetment_4m_lod.glb`；`revetment_4m_editable.blend` | 候选，待实镜头/原碰撞核对 |
| 1.3m 护岸 | 1,172 → **411** | 1 / 1 / 1 | `revetment_1p3_lod.glb`；`revetment_1p3_editable.blend` | 候选，待实镜头/原碰撞核对 |
| 护岸闭合段 | 32,122 → **未交付** | 原件 12 / 14 / 2 | 不生成可采用的低模 GLB 或 editable blend | **取消，继续用原件** |
| 东侧检修扩展 | 16,724 → **4,051** | 2 / 2 / 2 | `east_maintenance_lod.glb`；`east_maintenance_editable.blend` | 候选，待实镜头/原碰撞核对 |
| 检修坑 | 19,640 → **7,374** | 3 / 3 / 3 | `inspection_pit_lod.glb`；`inspection_pit_editable.blend` | 候选，待实镜头/原碰撞核对 |

闭合段的明确取消原因：`EastMouth_03: material surface bounds shifted 0.002422m`，超过本轮 2 mm 面边界门；保留原 32,122 tri，不重试、不放宽。

东侧新精确分件：`FloorSurface=1431`、`InspectionBand=2620`。
坑新精确分件：`FloorAndRamp=1860`、`Hardware=3054`、`WallConcrete=2460`。
原节点层级/局部变换、材质名称/槽、材质和图像定义保持原值；完整旧/新 contract、逐面 min/max 与差值均在本次 `result.json`，生产接线只能采用这些明确新值。

四个有效源文件合计 42,688 → 13,640 tri。若沿用当前 6 个长件、2 个短件实例，且闭合段继续原件，这四类装饰的场地源几何合计预计 101,742 → 55,193 tri。
这只是按现有实例数计算，**不是实测屏幕绘制量、帧率或性能收益**。

## 精确边界与接线注意

4m 件唯一 AABB 变化：

```text
min = (-2, -2.799999952316284, -0.3499999940395355)
max = ( 2,  0,                  0.0008031860925257206)
size = (4, 2.799999952316284, 0.35080318013206124)
```

即局部 zmax 比原值增加 **0.8031860925257206 mm**。这是该候选的已知精确 contract，不能改成笼统增大所有模型的容差。

- `scripts/v3/art/twin_i2_revetment_art.gd`：旧局部 `expected AABB` 约第 55 行；仅长件换上方精确 AABB，短件保持原值；约第 60 行按明确新 tri 检查。
- `scripts/v3/art/twin_i2_east_revetment_art.gd`：约第 136 行同样有局部旧 AABB；约第 70 行另有 **-90° 旋转后的世界 AABB**，不能只改局部检查。长件旋转后 x 下界是原 `16.9 - 0.0008031860925257206`，x 宽为 `0.35080318013206124`，z 范围仍为放置 z±2；实现时由明确新局部 AABB 经原 transform 算，保留引擎 float32 表示。短件不变。
- `scripts/v3/art/twin_i2_east_maintenance_art.gd`：约第 47 行是旧分件 tri；约第 68 行总 AABB 不变，不能为了接低模放宽。
- `scripts/v3/art/twin_i2_inspection_pit_art.gd`：约第 50 行是旧总 tri。`Hardware` 自身 zmax 从 `4.71999979019165` 到 `4.718999862670898`，偏差 `-0.0009999275207519531`；整体合并 AABB 仍由墙/坡道决定，原 `BOUNDS` 不变。

以上行号是接线前只读定位，主 Agent 修改后以函数/常量名为准。
原地面裁切范围、原 layout、原 GLB-derived collision shape 与 mask 不随视觉边界变化。
候选没有生成/替换碰撞；切勿把低模几何传入原碰撞构造路径。

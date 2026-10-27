# P1 可编辑源准备

状态：首轮 Blender 已执行，12件可编辑源和三张源图已生成；自然 exit0，但外观自审未通过V2还原。详见 [REVIEW.md](REVIEW.md)。源码、首图和日志保留，未烘焙、未导出GLB；根线程未给予本件最终美术验收。

当前生产 layout 原字节保存为 `layout_intake.json`，SHA256 `ad357fc68c68692a99f2d5394f8774569e3fa3caceaade0920a917468104b556`，15,854 B。与原参考的 `production_layout_readback_v1.json` 解析后只差 `labels[1].text`：`巡检落台 / 新建` 改为 `巡检通路`，所有非 labels 合同完全相等。旧原字节和 provenance 均保留。当前 V2 原图 SHA256 `bc0086a0c348e5a214109f86596293df223c7ec19458ffe2bdb3a6eb02058cb4`。

## 文件与方法

- `geometry.py`：只产生纯 Python 顶点/面数据；按生产布局生成12个独立 Mesh 的数据，不读取 Blender，不写场景。每个 Mesh 中保留明确命名的可编辑制造子件。
- `materials.py`：五种源材质，蓝绿涂钢、深灰防滑面、深钢轮框、磨亮金属、少量赭黄操作柄。低频色块与局部低缘盐迹；防滑纹只作1mm浅凹凸。此阶段程序节点未烘焙，不能冒充游戏 PBR 贴图或正确 glTF 材质。
- `build_source.py`：Blender 5.2 原生接口组装源，测量倒角后的真实网格，保存 `.blend`。只有 `--render` 才出三张源审查图。没有 GLB 导出调用，也不会写 `assets/`。
- `geometry_static_report.json`：静态几何记录，12件、倒角前5,232三角、五材质。所有顶点在对应原盒包络内；独立制造子件逐一闭合、绕序和正体积核对。**不是**对整网格Boolean并集、所有自交、Godot碰撞或渲染的证明；螺栓、折边和轮毂仍按实际制造用途交埋。

## 坐标、层级与可编辑性

以 world `(15,5,0)` 为建议资产原点，Godot 坐标经 `(x,-z,y)` 写为 Blender 坐标，再由以后明确 glTF Y-up 导出。根 `SharedBridgeDeck` 为 identity；`MovingDeck` 包含原10个 moving 子件，`LockPin` 包含 `LockRod` 与 `LockGrip`，父节点缩回态 identity。插入只需将 `LockPin` 沿 Godot-Y 移动0.3m。每 Mesh 的名字与原12件ID完全相同，位置为真实局部中心，无非等比缩放。

两小车各沿Z长1.2m，轮轴沿X，没有角落万向脚轮。北/南护板保留连续厚钢面，所有折边/螺钉在原100mm护板厚度内。两端不加门栏。导框保持160mm方孔，100mm直径销杆在其中每侧有30mm几何净距；实际运行射线/扫掠仍待集成验证。销柄中心Y0.475，导框中心Y-0.25。

制造件按面域 `construction_piece` 和对象属性 `construction_piece_names` 对应，可在编辑模式独立选取。只有一个明确 active-render `SurfaceUV`，使用米制面投影给源材质采样；它可以重复/重叠，**不是**交付用唯一UV图集。后续如源形通过，再制作独立烘焙UV和正式贴图/候选GLB，不由本脚本自动越阶段。

## 首轮实际运行命令与重跑约束

首轮在根线程明确分配窗口后执行，调用者限制240秒墙钟并保留stdout/stderr。PID22448，131.031秒自然exit0。输出子目录已存在，再运行会拒绝覆盖；后续必须先获根新的窗口和返修范围、保留旧字节，换新的唯一目录。这里没有后台无限渲染或自动重试。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --threads 2 --python-exit-code 1 --python 'asset_sources/v3/shared_access_bridge_deck/p1/build_source.py' -- --render --samples 16 --output source_review_01
```

预期输出：`source_review_01/shared_access_bridge_deck_p1.blend`、`01-oblique.png`、`02-bogies-underneath.png`、`03-lock-closeup.png`、`source_report.json`。三相机拍同一原姿态，第二张只移除摄影棚地面以避免挡住下视，没有隐藏资产功能件。报告记录实际倒角后三角数、材质面数量（不称draw calls）、12件界限、相机、输入前后hash、输出hash及耗时。根实际查看三图后才决定进入下一阶段。

Blender接口依据：[Mesh/from_pydata](https://docs.blender.org/api/current/bpy.types.Mesh.html)。本轮为源脚本/后续源渲染，不是 Godot 产品镜头、GPU性能或用户体验证据。

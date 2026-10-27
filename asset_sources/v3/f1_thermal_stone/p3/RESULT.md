# F1 thermal P3 源轮

2026-10-20：仅同相机离线源近景、editable与数值重开；引擎已归还，未烘焙、未导出、未进入Godot。

- 批次 `runs/20261020_100415_51449c`：PID14468，39.594s，自然exit0，0残留，未超时/清理。日志无ERROR、Traceback或Warning。
- CPU2私有Job/硬240s；22项真实输入前后SHA一致，已逐字节保全到本批 `input_source`，`input_manifest.json` 记录来源与SHA。
- 24可编辑源网格、7896三角、5材质；不是已经合并成六mesh的GLB。原六mesh/五材质交付分组目标尚未执行。
- 实际Godot坐标bounds：min=(-1.4863517284,0,-.8399999738)，max=(1.4932415485,1.9928277731,.9728262424)；原3×2×2范围内，identity根、模型内0灯。
- 闭边、正三角面积、有限PaintUV、有效材质槽以及31项命名CORNER属性检查通过。保存后重开 `geometry.json` 与 `readback.json` 字节一致。`root_frames.json` 保留连续根每截面实际构造数据；不将其替代真实游戏物理测试。
- 唯一图 `output/01-game-direction-close.png`：1100×900、1,187,959B、SHA256 `68e3e0295a0020f4332b6eb2a34d5cca3b004b120009de4d008762888cc4c69c`。
- `output/f1_thermal_stone_editable.blend`：3,106,278B、SHA256 `9547909f7ea2a84e7aa6d5055de50659040989688115a52714403f0e276b7028`。
- 全部输出见 `output_manifest.json`；P1/P2源与失败/成功历史未改。

实际查看：P2右上/前底的根截面硬折已消失；石顶暖砂色、侧面冷灰和手绘笔触可见，核心不规则晶面可读。整体仍是较规整的厚石机关，是否足够进入引擎候选交由Root亲看；不宣称最终美术通过。

核心中性底色与独立温色接口仍保留，源图青色只是20态预览。尚无默认26m真实MAIN镜头、20/45/70实机联动或PBR回导证据，本轮不扩写这些完成状态。

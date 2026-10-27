# P11 三石诊断（已执行，REJECTED_ART）

三图在 `source_review_01/`：A 原 P10，B 分用途贴图且平着色，C 同 B 材质加真实角度平滑。执行 PID 28888 / CPU2 / 178.899 秒 / exit 0。此轮无烘焙、无 GLB、无生产导入。

`VISUAL_REVIEW.md` 是最终审查；`PREPARED.md` 与 `prepared_check.json` 是运行前历史快照，不表示当前仍未运行。`source_review_01/study_report.json` 保留原运行报告；其 pending 状态由最终审查明确收束为退回，不覆盖原始数据。

局部接色有变化，但混凝土块粗糊、平滑收益小，不能整件推广。144 件 / 7,456 三角及位置严格未变；该约束只证明本轮对照受控，后续已由 root 解除强制相同低模的自设限制。

可编辑研究源：`source_review_01/three_stone_study.blend`，只保存 C 状态，引用只读原图。没有把三图修改或拼接成新证据。所有源/图/脚本/日志在 manifest.json 记录原字节，selfcheck.json 读回核对。

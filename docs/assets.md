# 资源恢复与完整性

资源附件是源码交付的一部分。Git中 `release-assets.json` 固定附件名称、下载位置、字节数、SHA-256及每个还原文件的相对路径和哈希。发布标签为 `v3.0.0-dev94-assets`，不可把不同版本的附件混用。

```powershell
python tools/fetch_segmented_assets.py --group runtime --group editable
python tools/fetch_assets.py --local-dir .runtime/asset-zips
python tools/fetch_assets.py --local-dir .runtime/asset-zips --runtime-only
python tools/fetch_assets.py --local-dir C:/Downloads/TwinPulseAssets
python tools/fetch_assets.py --local-dir C:/Downloads/TwinPulseAssets --verify-only
```

默认恢复到项目根；`--verify-only` 会读取并验证每一个压缩条目，不提取。路径检查拒绝越界、重解析链接、重名条目或额外条目。已有文件符合清单时保留；已修改时停止，先备份自己的成果，只有显式 `--force` 才替换。下载缓存位于被忽略的 `.runtime/asset-downloads/`。

运行包中的字体、CC0/CC BY资源和原作者声明继续适用各自许可。可编辑包只含本次已确认范围；它不能代替未映射的本地模型历史、真实存档或整个原开发目录。请保留原件。

原制作记录中的哈希可能指向脱敏前的本地文件；公开文件以 `release-assets.json` 为准。已有制作脚本尚未逐个完成跨机器重新制作验证，可编辑模型已做原生读回，不将这一点写成全部制作流程可一键复现。

每个附件均小于2GiB，按[GitHub Release说明](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)分发。当前资源ZIP约905MiB与1.29GiB；下载前应留出解压空间。

Release 附件以独立 SHA-256 分段分发；先用 `python tools/fetch_segmented_assets.py --group runtime --group editable` 下载并重组完整 ZIP。工具不覆盖不同内容的已有文件；网络中断后已验证分段可复用。仅运行版可只选 `--group runtime`。

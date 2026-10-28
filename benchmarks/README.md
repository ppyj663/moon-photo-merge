# 公开照片扫描基准

记录日期：2026-10-28。设备为 Windows 10 x64，Node.js 24.19.0，MoonBit 0.1.20261023。每组先暖机一次，再测量 5 次完整 `scan`，包括进程启动、读取、解码、分类、分组和报告生成；p95 采用最近秩法。两组顺序运行。

| 数据 | 现有 / 待导入文件 | 内容 | 中位数 | p95 | 原始汇总 |
| --- | ---: | --- | ---: | ---: | --- |
| 公开照片小样本 | 3 / 4 | 6 张不同照片，含 1 个完全重复、1 个同名冲突 | 787.364 ms | 794.136 ms | [JSON](public-photo-small-windows-2026-10-28.json) |
| 重复扩展样本 | 30 / 40 | 将上述数据复制 10 份，仍只有 6 张不同照片 | 3,855.594 ms | 4,106.855 ms | [JSON](public-photo-repeated-windows-2026-10-28.json) |

数据来自 [scikit-image v0.25.2 样例照片](https://scikit-image.org/docs/0.25.x/api/skimage.data.html)：astronaut、camera、chelsea、clock、coffee 和 rocket。上游分别注明公开领域、无已知版权限制或 CC0；项目不再分发这些照片。下载脚本固定版本并校验每张照片的 SHA-256。样本仅用于观察本机运行及重复文件处理，不代表真实相册分布、识别准确率或大规模性能。

复现需要 Python 3 标准库联网下载照片，以及 README 中列出的运行环境。以下目标目录必须尚不存在：

```powershell
python scripts/prepare-public-photo-benchmark.py "D:\PhotoBenchSmall" --copies 1
node scripts/benchmark.mjs "D:\PhotoBenchSmall\library" "D:\PhotoBenchSmall\incoming" --runs 5
python scripts/prepare-public-photo-benchmark.py "D:\PhotoBenchRepeated" --copies 10
node scripts/benchmark.mjs "D:\PhotoBenchRepeated\library" "D:\PhotoBenchRepeated\incoming" --runs 5
```

也可传入自己的照片目录进行本地测量，基准汇总不含源文件路径、文件名、哈希或图片内容。小样本的 p95 是 5 次测量中的最大值；测量结果随机器和负载变化，不能作为性能保证。

# 照片备份合并预检

一个用 MoonBit 编写的本地工具：先比较现有相册与待导入备份，生成可审核的 HTML 清单，再按确认的清单复制照片。适合合并多次备份产生的重复、近似和同名照片。

项目只读取 JPEG、PNG，复制时不删除原件，也不覆盖现有文件。扫描与审核都在本机进行。

## 使用

需要 [MoonBit 工具链](https://www.moonbitlang.com/download/)、Git 和 Node.js 24。已在 Windows 的 MoonBit `0.1.20261023`、Node.js 24 及 GitHub Actions 的 Linux 环境运行。先获取仓库并进入项目目录：

```sh
git clone https://github.com/ppyj663/moon-photo-merge.git
cd moon-photo-merge
```

核心 MoonBit 模块已发布至 [Mooncakes](https://mooncakes.io/docs/ppyj663/photo_merge)，可在其他 MoonBit 项目中用 `moon add ppyj663/photo_merge` 引入。下面的命令行工具通过源码仓库运行。

```powershell
moon update
moon run cmd/main -- scan "D:\Photos" "E:\PhoneBackup" "D:\PhotoReview"
```

在浏览器打开输出的 `review.html`。页面会列出每张待导入图片及参考图片，并汇总各类数量；可以按文件名或路径搜索，也可按分类筛选。“只选可新增”可一次勾选明确的新照片，“清空选择”会取消所有勾选。“疑似相似”和“同名冲突”需手动勾选。下载 `approved.json` 后执行：

```powershell
moon run cmd/main -- check "D:\Photos" "E:\PhoneBackup" "C:\Users\你的用户名\Downloads\approved.json"
moon run cmd/main -- apply "D:\Photos" "E:\PhoneBackup" "C:\Users\你的用户名\Downloads\approved.json"
```

`check` 会重新扫描并验证审核清单，列出将复制的文件名与容量；它是只读预检，不改动照片。确认预检输出后再运行 `apply`。

每次扫描还会在报告文件夹输出 `review.csv`、`review.json`、`inventory.json`、`extensions.csv`、`similar-groups.json` 和 `similar-groups.csv`。这些文件用于查看或二次分析；只有网页下载的 `approved.json` 是 `apply` 接受的审核清单。`inventory.json` 汇总容量、方向、像素、文件扩展名和大小区间；CSV 字段会转义分隔符、引号和换行，并给公式样式的文本字段添加单引号以便在电子表格中按文本打开。需要原始字段值时使用 JSON 导出。

### 常见使用场景

1. **合并一次手机备份**：按默认阈值扫描，打开 HTML 报告，保留“可新增”的默认选择，下载审核清单后执行 `apply`。
2. **处理同名不同内容**：报告会把文件标为“同名冲突”，给出带 `-import-1` 的建议文件名；查看两张预览后再决定是否勾选。
3. **更敏感地查找近似照片**：提高指纹差异阈值，例如 `--similarity-limit 8`，报告会把更多近似候选交给人工复核；扫描与执行必须使用相同阈值。

阈值是 176 位视觉指纹的最大差异位数，范围为 `0..176`，默认值为 `5`。距离越小，指纹越接近；该分值不是相似概率。调低阈值会减少疑似提示，调高会增加提示。阈值不会代替人工审核。

报告会显示图片尺寸、估算像素数、平均亮度和平均颜色的简单观察提示。工具还会按阈值把现有相册和备份中有直接匹配边的照片整理成“相似候选组”；组按直接匹配关系的连通性构成，因此同一组里的任意两张照片不一定彼此直接相似。候选组只用于缩小人工核对范围，不会自动排除或删除照片。

```powershell
moon run cmd/main -- scan "D:\Photos" "E:\PhoneBackup" "D:\PhotoReview" --similarity-limit 8
moon run cmd/main -- check "D:\Photos" "E:\PhoneBackup" "C:\Users\你的用户名\Downloads\approved.json" --similarity-limit 8
moon run cmd/main -- apply "D:\Photos" "E:\PhoneBackup" "C:\Users\你的用户名\Downloads\approved.json" --similarity-limit 8
```

`scan` 要求三个文件夹彼此独立。`check` 和 `apply` 会重新扫描；若相册或备份内的 JPEG/PNG 内容、文件名、数量改变，旧清单就会被拒绝，需重新审核。`check` 只显示将复制的项目和容量。`apply` 只复制清单中勾选的文件到现有相册**根目录**，同名时使用 `-import-1` 等新文件名。复制后校验 SHA-256，且目标名已存在时停止，不会覆盖。

命令帮助：`moon run cmd/main -- --help`。

## 判断规则

| 分类 | 含义 | 默认选择 |
| --- | --- | --- |
| 完全重复 | 文件字节 SHA-256 相同 | 不可选择 |
| 疑似相似 | 可解码，亮度和颜色的简易视觉指纹接近 | 不选择，人工核对 |
| 同名冲突 | 文件名相同但内容不同 | 不选择，人工核对 |
| 可新增 | 未命中上述情况 | 选择 |
| 图片无法解码 | 扩展名符合，但 JPEG/PNG 解码失败 | 不可选择 |

视觉指纹是提示，不保证识别所有重编码、裁剪或旋转后的照片，也可能误报。JPEG 的 EXIF 朝向不参与归一化。PNG 的解压数据上限为 128 MiB，超出上限、校验失败或无法解码的文件标为无法解码。亮度、颜色和分辨率提示是对采样图像的粗略统计，不等于图像质量判断。现有相册和备份的目录结构不会在目标中保留；目标文件名会被展开到相册根目录。首版不处理 HEIC、RAW、视频或云端照片。

## 示例与测试

`examples/fixtures` 是合成测试素材，不含真实相册照片；其中包含五种待导入文件：完全重复、像素略变、同名不同内容、可新增 JPEG，以及损坏 JPEG。演示前复制它们到临时工作目录，避免修改仓库样例。跨平台运行方式：

```sh
node scripts/demo.mjs
```

脚本会打印临时报告路径。打开报告，下载清单，然后按上面的 `apply` 命令尝试复制。Windows 用户也可运行 `./scripts/demo.ps1`。运行自动化测试：

```powershell
moon test --target js
node scripts/integration-test.mjs
```

核心分类、命名冲突、分段索引的候选召回、连通分组、统计边界、筛选分页、CSV/JSON 转义、损坏图片及重复导入的规则见测试；文件复制和报告导出流程可用演示数据复核。

集成测试还覆盖空参数、空目录、阈值边界、嵌套目录、大写扩展名、零字节图片、PNG 分块及校验错误、较大 PNG、未支持格式、目录符号链接、路径穿越、过期清单、重复/不可复制清单项、目标文件碰撞、报告文件与原照片的硬链接，以及拒绝把基准汇总写进照片输入目录。扫描不会跟随符号链接目录；报告里可见的每个待导入路径都会在 `check` 和 `apply` 时重新校验。

大赛验收项、仓库证据与本机复现命令见[验收自查](docs/验收自查.md)。

### 本地照片目录基准

可用自己的照片目录测量完整 `scan` 命令。脚本先暖机一次，再按指定次数测量；每次报告写入系统临时目录并在结束时清理。汇总仅包含环境、文件数、字节数、分类数量和耗时，不写入路径、文件名、哈希或照片内容。扫描本身是只读的。

```powershell
node scripts/benchmark.mjs "D:\Photos" "E:\PhoneBackup" --runs 5
node scripts/benchmark.mjs "D:\Photos" "E:\PhoneBackup" --runs 5 --output "D:\PhotoReview\benchmark-summary.json"
```

基准报告中的 `medianMs` 是重复运行中位数，`p95Ms` 使用最近秩法；耗时包括 CLI 启动、扫描、解码、分类、分组和报告导出。建议固定设备、目录和 MoonBit/Node.js 版本后比较。`examples/fixtures` 是便于 CI 复现的合成夹具，性能结果不能当作真实相册的性能或识别准确率承诺；上面的命令可直接生成真实照片目录的本机汇总。

当前 Windows 10 x64 参考运行（Node.js 24.19.0、MoonBit 0.1.20261023，2026-10-28）使用仓库合成夹具，现有相册 1 张/198 B，待导入 5 张/1,212 B；5 次测量中位数 399.306 ms，p95 为 477.864 ms。五张待导入样例各覆盖完全重复、疑似相似、同名冲突、可新增和无法解码一种分类。完整汇总见 [基准 JSON](benchmarks/synthetic-fixtures-windows-2026-10-28.json)。该小样本主要验证基准流程与报告统计，进程启动开销占比高，不用于推断大相册性能。

另用 scikit-image 的 6 张公开照片构造两组输入，测量真实 JPEG/PNG 解码与扫描：7 个文件时 5 次中位数为 787.364 ms；把同一组照片复制扩展到 70 个文件时中位数为 3,855.594 ms。扩展组只有 6 张不同原图，不能视为 70 张不同照片或真实用户相册。数据来源、生成方法、全部测量和局限见[公开照片基准](benchmarks/README.md)。

## 实现

MoonBit 负责照片数据建模、图片解码后的视觉指纹、分类和导入决策。JPEG/PNG 解码使用 `gmlewis/image`，文件系统及 SHA-256 使用 Node.js 适配代码。PNG 使用 Node.js zlib 校验并转换压缩数据后交给 MoonBit 解码，以避免依赖库在 JS 目标上发生深层递归；像素不因此改变。报告通过临时文件替换，避免跟随已有输出文件的硬链接或符号链接改写其目标。执行阶段再次核对扫描摘要和来源文件哈希，通过同目录临时文件校验后创建目标硬链接，因此不会覆盖同名文件；若执行中途失败，已成功复制的文件会保留，重新扫描后可继续审核。

直接依赖为 [gmlewis/image](https://github.com/gmlewis/moonbit-image) 和 [gmlewis/io](https://github.com/gmlewis/moonbit-io)；传递依赖与上游来源说明见[第三方来源](docs/第三方来源.md)。本项目使用了 Codex 辅助编写代码、测试和文档；分类规则、限制与复现方式见上文及仓库测试。

许可证：Apache-2.0。

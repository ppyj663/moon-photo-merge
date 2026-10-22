# 照片备份合并预检

一个用 MoonBit 编写的本地工具：先比较现有相册与待导入备份，生成可审核的 HTML 清单，再按确认的清单复制照片。适合合并多次备份产生的重复、近似和同名照片。

项目只读取 JPEG、PNG，复制时不删除原件，也不覆盖现有文件。扫描与审核都在本机进行。

## 使用

需要 [MoonBit 工具链](https://www.moonbitlang.com/download/) 和 Node.js。已在 Windows 的 MoonBit `0.1.20261020`、Node.js 环境运行。

```powershell
moon update
moon run cmd/main -- scan "D:\Photos" "E:\PhoneBackup" "D:\PhotoReview"
```

在浏览器打开输出的 `review.html`。页面会列出每张待导入图片及参考图片；“可新增”默认选中，“疑似相似”和“同名冲突”需手动勾选。下载 `approved.json` 后执行：

```powershell
moon run cmd/main -- apply "D:\Photos" "E:\PhoneBackup" "C:\Users\你的用户名\Downloads\approved.json"
```

`scan` 要求三个文件夹彼此独立。`apply` 会重新扫描；若相册或备份内的 JPEG/PNG 内容、文件名、数量改变，旧清单就会被拒绝，需重新审核。仅清单中勾选的文件会复制到现有相册**根目录**，同名时使用 `-import-1` 等新文件名。复制后校验 SHA-256，且目标名已存在时停止，不会覆盖。

## 判断规则

| 分类 | 含义 | 默认选择 |
| --- | --- | --- |
| 完全重复 | 文件字节 SHA-256 相同 | 不可选择 |
| 疑似相似 | 可解码，亮度和颜色的简易视觉指纹接近 | 不选择，人工核对 |
| 同名冲突 | 文件名相同但内容不同 | 不选择，人工核对 |
| 可新增 | 未命中上述情况 | 选择 |
| 图片无法解码 | 扩展名符合，但 JPEG/PNG 解码失败 | 不可选择 |

视觉指纹是提示，不保证识别所有重编码、裁剪或旋转后的照片，也可能误报。JPEG 的 EXIF 朝向不参与归一化。现有相册和备份的目录结构不会在目标中保留；目标文件名会被展开到相册根目录。首版不处理 HEIC、RAW、视频或云端照片。

## 示例与测试

`examples/fixtures` 包含五种待导入文件：完全重复、像素略变、同名不同内容、可新增 JPEG，以及损坏 JPEG。演示前复制它们到临时工作目录，避免修改仓库样例：

```powershell
./scripts/demo.ps1
```

脚本会打印临时报告路径。打开报告，下载清单，然后按上面的 `apply` 命令尝试复制。运行自动化测试：

```powershell
moon test --target js
node scripts/integration-test.mjs
```

核心分类、命名冲突、损坏图片及重复导入的规则见测试；文件复制流程可用演示数据复核。

## 实现

MoonBit 负责照片数据建模、图片解码后的视觉指纹、分类和导入决策。JPEG/PNG 解码使用 `gmlewis/image`，文件系统及 SHA-256 使用少量 Node.js 适配代码。执行阶段再次核对扫描摘要和来源文件哈希，通过同目录临时文件校验后创建目标硬链接，因此不会覆盖同名文件；若执行中途失败，已成功复制的文件会保留，重新扫描后可继续审核。

许可证：Apache-2.0。

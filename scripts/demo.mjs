import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = path.join(project, 'examples', 'fixtures');
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'moon-photo-merge-demo-'));
const library = path.join(output, 'library');
const incoming = path.join(output, 'incoming');
const report = path.join(output, 'report');

fs.cpSync(path.join(fixtures, 'library'), library, { recursive: true });
fs.cpSync(path.join(fixtures, 'incoming'), incoming, { recursive: true });
fs.mkdirSync(report);

const result = spawnSync(
  process.platform === 'win32' ? 'moon.exe' : 'moon',
  ['run', 'cmd/main', '--', 'scan', library, incoming, report],
  { cwd: project, encoding: 'utf8' },
);
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.status !== 0) {
  process.exitCode = result.status ?? 2;
} else {
  console.log(`示例报告：${path.join(report, 'review.html')}`);
  console.log('样例已复制到临时目录；仓库内的示例文件未修改。');
}

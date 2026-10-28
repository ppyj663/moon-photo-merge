import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixture = path.join(project, 'examples', 'fixtures');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'photo-merge-test-'));
const library = path.join(temp, 'library');
const incoming = path.join(temp, 'incoming');
const report = path.join(temp, 'report');
fs.cpSync(path.join(fixture, 'library'), library, { recursive: true });
fs.cpSync(path.join(fixture, 'incoming'), incoming, { recursive: true });
fs.mkdirSync(report);
const nested = path.join(incoming, 'nested');
fs.mkdirSync(nested);
fs.renameSync(path.join(incoming, 'new.jpg'), path.join(nested, 'new.jpg'));
fs.copyFileSync(path.join(incoming, 'duplicate.png'), path.join(nested, 'UPPERCASE.PNG'));
fs.writeFileSync(path.join(nested, 'empty.png'), Buffer.alloc(0));
fs.writeFileSync(path.join(nested, 'unsupported.heic'), Buffer.from('not a supported image'));
const linkedTarget = path.join(temp, 'linked-photos');
fs.mkdirSync(linkedTarget);
fs.copyFileSync(path.join(fixture, 'incoming', 'new.jpg'), path.join(linkedTarget, 'outside.jpg'));
fs.symlinkSync(linkedTarget, path.join(incoming, 'linked-directory'), process.platform === 'win32' ? 'junction' : 'dir');
const escapedName = "相册, O'Neil.png";
fs.copyFileSync(path.join(incoming, 'similar.png'), path.join(incoming, escapedName));
const formulaName = '=SUMMARY.png';
fs.copyFileSync(path.join(incoming, 'similar.png'), path.join(incoming, formulaName));

const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const run = (...args) => spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', ['run', 'cmd/main', '--', ...args], {
  cwd: project, encoding: 'utf8',
});
const unsafeBenchmarkOutput = path.join(library, 'benchmark-summary.json');
const rejectedBenchmarkOutput = spawnSync(process.execPath, [
  path.join(project, 'scripts', 'benchmark.mjs'), library, incoming, '--runs', '1', '--output', unsafeBenchmarkOutput,
], { cwd: project, encoding: 'utf8' });
assert.equal(rejectedBenchmarkOutput.status, 2, rejectedBenchmarkOutput.stderr);
assert.match(rejectedBenchmarkOutput.stderr, /outside both input directories/);
assert.ok(!fs.existsSync(unsafeBenchmarkOutput), 'benchmark cannot write its summary into a source folder');
const filesystemRoot = path.parse(process.cwd()).root;
const rootOverlap = run('scan', filesystemRoot, temp, filesystemRoot);
assert.equal(rootOverlap.status, 2, rootOverlap.stderr + rootOverlap.stdout);
assert.match(rootOverlap.stdout, /现有相册和待导入备份不能互相包含/);
const help = run('--help');
assert.equal(help.status, 0, help.stderr + help.stdout);
assert.match(help.stdout, /scan <现有相册>/);
assert.match(help.stdout, /apply <现有相册>/);
assert.match(help.stdout, /check <现有相册>/);
assert.match(help.stdout, /--similarity-limit 0\.\.176/);
const noArgs = run();
assert.equal(noArgs.status, 2, noArgs.stderr + noArgs.stdout);
assert.match(noArgs.stdout, /scan <现有相册>/);
assert.doesNotMatch(noArgs.stderr, /Index out of bounds/);
const linkedReport = path.join(temp, 'linked-report');
fs.mkdirSync(linkedReport);
const protectedPhoto = path.join(library, 'original.png');
const protectedHash = hash(protectedPhoto);
fs.linkSync(protectedPhoto, path.join(linkedReport, 'review.html'));
const linkedReportScan = run('scan', library, incoming, linkedReport);
assert.equal(linkedReportScan.status, 0, linkedReportScan.stderr + linkedReportScan.stdout);
assert.equal(hash(protectedPhoto), protectedHash, 'report output cannot modify a hard-linked source photo');
assert.match(fs.readFileSync(path.join(linkedReport, 'review.html'), 'utf8'), /<!doctype html>/i);
const emptyLibrary = path.join(temp, 'empty-library');
const emptyIncoming = path.join(temp, 'empty-incoming');
const emptyReport = path.join(temp, 'empty-report');
fs.mkdirSync(emptyLibrary);
fs.mkdirSync(emptyIncoming);
const emptyScan = run('scan', emptyLibrary, emptyIncoming, emptyReport, '--similarity-limit', '0');
assert.equal(emptyScan.status, 0, emptyScan.stderr + emptyScan.stdout);
assert.deepEqual(JSON.parse(fs.readFileSync(path.join(emptyReport, 'review.json'), 'utf8')), []);
const negativeLimit = run('scan', emptyLibrary, emptyIncoming, emptyReport, '--similarity-limit', '-1');
assert.equal(negativeLimit.status, 2, negativeLimit.stderr + negativeLimit.stdout);
assert.match(negativeLimit.stdout, /相似阈值必须是/);
// PNG with many literal deflate symbols exercises the JS decompressor's stack boundary.
const pngChunk = (type, data) => {
  const tag = Buffer.from(type);
  const size = Buffer.alloc(4);
  const checksum = Buffer.alloc(4);
  size.writeUInt32BE(data.length);
  checksum.writeUInt32BE(zlib.crc32(Buffer.concat([tag, data])));
  return Buffer.concat([size, tag, data, checksum]);
};
const width = 256;
const header = Buffer.alloc(13);
header.writeUInt32BE(width, 0);
header.writeUInt32BE(width, 4);
header[8] = 8;
header[9] = 2;
const pixels = Buffer.alloc((width * 3 + 1) * width);
let seed = 1;
for (let row = 0; row < width; row += 1) {
  for (let col = 1; col <= width * 3; col += 1) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    pixels[row * (width * 3 + 1) + col] = seed >>> 28;
  }
}
const compressedPixels = zlib.deflateSync(pixels);
const png = Buffer.concat([
  Buffer.from('89504e470d0a1a0a', 'hex'), pngChunk('IHDR', header),
  pngChunk('IDAT', compressedPixels), pngChunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(path.join(emptyIncoming, 'large.png'), png);
const split = Math.floor(compressedPixels.length / 2);
const splitPng = Buffer.concat([
  Buffer.from('89504e470d0a1a0a', 'hex'), pngChunk('IHDR', header),
  pngChunk('IDAT', compressedPixels.subarray(0, split)),
  pngChunk('IDAT', compressedPixels.subarray(split)), pngChunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(path.join(emptyIncoming, 'split.png'), splitPng);
const badCrc = Buffer.from(png);
badCrc[badCrc.length - 1] ^= 1;
fs.writeFileSync(path.join(emptyIncoming, 'bad-crc.png'), badCrc);
const pngScan = run('scan', emptyLibrary, emptyIncoming, emptyReport);
assert.equal(pngScan.status, 0, pngScan.stderr + pngScan.stdout);
const pngRows = JSON.parse(fs.readFileSync(path.join(emptyReport, 'review.json'), 'utf8'));
for (const name of ['large.png', 'split.png']) {
  const row = pngRows.find(row => row.name === name);
  assert.notEqual(row.kind, 'unreadable');
  assert.equal(row.imageInfo.width, width);
}
assert.equal(pngRows.find(row => row.name === 'bad-crc.png').kind, 'unreadable');
assert.deepEqual(
  pngRows.find(row => row.name === 'large.png').imageInfo,
  pngRows.find(row => row.name === 'split.png').imageInfo,
  'splitting IDAT chunks must not change decoded pixel statistics',
);
const nestedIncoming = path.join(library, 'nested-input');
fs.mkdirSync(nestedIncoming);
const overlapping = run('scan', library, nestedIncoming, path.join(temp, 'overlap-report'));
assert.equal(overlapping.status, 2, overlapping.stderr + overlapping.stdout);
assert.match(overlapping.stdout, /不能互相包含/);
fs.rmdirSync(nestedIncoming);
const reportInsideInput = path.join(incoming, 'review-output');
const invalidReport = run('scan', library, incoming, reportInsideInput);
assert.equal(invalidReport.status, 2, invalidReport.stderr + invalidReport.stdout);
assert.match(invalidReport.stdout, /报告文件夹不能位于输入文件夹内/);
const first = run('scan', library, incoming, report);
assert.equal(first.status, 0, first.stderr + first.stdout);
const invalidLimit = run('scan', library, incoming, path.join(temp, 'invalid-limit'), '--similarity-limit', '177');
assert.equal(invalidLimit.status, 2, invalidLimit.stderr + invalidLimit.stdout);
assert.match(invalidLimit.stdout, /相似阈值范围是 0 到 176/);
const html = fs.readFileSync(path.join(report, 'review.html'), 'utf8');
assert.ok(html.includes('incoming/相册, O&#39;Neil.png'), 'report escapes user-controlled filenames');
const id = html.match(/const scanId="([a-f0-9]{64})"/);
assert.ok(id, 'report contains a scan ID');
for (const kind of ['exact', 'similar', 'conflict', 'new', 'unreadable']) {
  assert.ok(html.includes(`<tr data-kind="${kind}">`), `missing ${kind} classification`);
}
const summary = html.match(/<span class="summary" id="summary" data-exact="(\d+)" data-similar="(\d+)" data-conflict="(\d+)" data-new="(\d+)" data-unreadable="(\d+)"/);
assert.ok(summary, 'report contains category counts');
assert.ok(html.includes('id="search"'), 'report can search by filename or path');
assert.ok(html.includes('id="select-new"'), 'report can select new files in one action');
assert.ok(html.includes('id="clear-selection"'), 'report can clear selections in one action');
assert.ok(html.includes('当前阈值为 5/176 位'), 'report documents the active threshold');
assert.ok(html.includes('class="score"'), 'similar rows show their fingerprint distance');
assert.ok(html.includes('class="meta"'), 'report shows decoded image dimensions');
assert.ok(html.includes('相似候选组'), 'report explains connected visual candidate groups');
for (const [index, kind] of ['exact', 'similar', 'conflict', 'new', 'unreadable'].entries()) {
  const rows = [...html.matchAll(new RegExp(`<tr data-kind="${kind}">`, 'g'))].length;
  assert.equal(Number(summary[index + 1]), rows, `${kind} summary matches report rows`);
}
const exportedRows = JSON.parse(fs.readFileSync(path.join(report, 'review.json'), 'utf8'));
assert.equal(exportedRows.length, summary.slice(1).reduce((total, count) => total + Number(count), 0), 'JSON export includes every review row');
assert.ok(exportedRows.some(row => row.path === 'incoming/nested/new.jpg' && row.kind === 'new'), 'nested JPEG files are scanned');
assert.ok(exportedRows.some(row => row.path === 'incoming/nested/UPPERCASE.PNG'), 'uppercase extensions are supported');
assert.ok(exportedRows.some(row => row.path === 'incoming/nested/empty.png' && row.kind === 'unreadable'), 'zero-byte images are reported as unreadable');
assert.ok(!exportedRows.some(row => row.path.includes('linked-directory')), 'directory symlinks are not followed');
assert.ok(!exportedRows.some(row => row.name.endsWith('.heic')), 'unsupported formats are excluded');
const escapedRow = exportedRows.find(row => row.name === escapedName);
assert.ok(escapedRow, 'JSON export preserves Unicode filenames');
assert.equal(typeof escapedRow.imageInfo.width, 'number', 'decoded rows include image dimensions');
const reviewCsv = fs.readFileSync(path.join(report, 'review.csv'), 'utf8');
assert.match(reviewCsv, /"incoming\/相册, O'Neil\.png"/);
assert.ok(reviewCsv.includes("\"'=SUMMARY.png\""), 'spreadsheet formula-like names are escaped as text');
const inventory = JSON.parse(fs.readFileSync(path.join(report, 'inventory.json'), 'utf8'));
assert.equal(inventory.total, exportedRows.length, 'inventory and review exports describe the same incoming scan');
assert.ok(inventory.extensions.some(item => item.extension === '.png'));
assert.ok(fs.readFileSync(path.join(report, 'extensions.csv'), 'utf8').includes('extension,count,readable,unreadable,bytes'));
const groups = JSON.parse(fs.readFileSync(path.join(report, 'similar-groups.json'), 'utf8'));
assert.ok(Array.isArray(groups), 'similarity groups export is valid JSON');
assert.ok(fs.readFileSync(path.join(report, 'similar-groups.csv'), 'utf8').includes('group,path,member_count'));
const originalHash = hash(path.join(library, 'original.png'));
const approved = path.join(report, 'approved.json');
fs.writeFileSync(approved, 'not json');
const malformed = run('apply', library, incoming, approved);
assert.equal(malformed.status, 2, malformed.stderr + malformed.stdout);
assert.match(malformed.stdout, /不是有效 JSON/);
for (const invalid of [
  { scanId: id[1] },
  { scanId: id[1], selected: ['incoming/new.jpg', 7] },
  { scanId: id[1], selected: ['incoming/nested/new.jpg', 'incoming/nested/new.jpg'] },
]) {
  fs.writeFileSync(approved, JSON.stringify(invalid));
  const rejected = run('apply', library, incoming, approved);
  assert.equal(rejected.status, 2, rejected.stderr + rejected.stdout);
  assert.deepEqual(fs.readdirSync(library), ['original.png']);
}
fs.writeFileSync(approved, JSON.stringify({
  scanId: id[1],
  selected: ['incoming/nested/new.jpg', 'incoming/../library/original.png'],
}));
const traversal = run('apply', library, incoming, approved);
assert.equal(traversal.status, 2, traversal.stderr + traversal.stdout);
assert.match(traversal.stdout, /审核清单路径不存在/);
assert.deepEqual(fs.readdirSync(library), ['original.png']);
fs.writeFileSync(approved, JSON.stringify({
  scanId: id[1], selected: ['incoming/nested/new.jpg', 'incoming/duplicate.png'],
}));
const rejected = run('apply', library, incoming, approved);
assert.equal(rejected.status, 2, rejected.stderr + rejected.stdout);
assert.deepEqual(fs.readdirSync(library), ['original.png']);

const nestedNew = path.join(nested, 'new.jpg');
const originalIncomingBytes = fs.readFileSync(nestedNew);
fs.writeFileSync(nestedNew, Buffer.concat([originalIncomingBytes, Buffer.from([0])]));
fs.writeFileSync(approved, JSON.stringify({ scanId: id[1], selected: ['incoming/nested/new.jpg'] }));
const staleCheck = run('check', library, incoming, approved);
assert.equal(staleCheck.status, 2, staleCheck.stderr + staleCheck.stdout);
assert.match(staleCheck.stdout, /审核清单与当前相册或备份不一致/);
assert.deepEqual(fs.readdirSync(library), ['original.png'], 'stale read-only check does not modify the library');
fs.writeFileSync(nestedNew, originalIncomingBytes);

fs.writeFileSync(approved, JSON.stringify({ scanId: id[1], selected: ['incoming/nested/empty.png'] }));
const unreadableSelection = run('apply', library, incoming, approved);
assert.equal(unreadableSelection.status, 2, unreadableSelection.stderr + unreadableSelection.stdout);
assert.match(unreadableSelection.stdout, /不可复制/);
assert.deepEqual(fs.readdirSync(library), ['original.png']);

fs.writeFileSync(approved, JSON.stringify({
  scanId: id[1], selected: ['incoming/nested/new.jpg', 'incoming/original.png', `incoming/${formulaName}`],
}));
const checked = run('check', library, incoming, approved);
assert.equal(checked.status, 0, checked.stderr + checked.stdout);
assert.match(checked.stdout, /审核清单通过：将复制 3 张/);
assert.match(checked.stdout, /只读预检完成；未复制、删除或覆盖任何文件/);
assert.match(checked.stdout, /new\.jpg/);
assert.deepEqual(fs.readdirSync(library), ['original.png'], 'read-only check does not write to the library');
const applied = run('apply', library, incoming, approved);
assert.equal(applied.status, 0, applied.stderr + applied.stdout);
assert.equal(hash(path.join(library, 'original.png')), originalHash);
assert.equal(hash(path.join(library, 'new.jpg')), hash(path.join(nested, 'new.jpg')));
assert.equal(hash(path.join(library, 'original-import-1.png')), hash(path.join(incoming, 'original.png')));
assert.equal(hash(path.join(library, formulaName)), hash(path.join(incoming, formulaName)));
const stale = run('apply', library, incoming, approved);
assert.equal(stale.status, 2, stale.stderr + stale.stdout);

const highLibrary = path.join(temp, 'high-limit-library');
const highReport = path.join(temp, 'high-limit-report');
fs.cpSync(path.join(fixture, 'library'), highLibrary, { recursive: true });
fs.mkdirSync(highReport);
const highScan = run('scan', highLibrary, incoming, highReport, '--similarity-limit', '176');
assert.equal(highScan.status, 0, highScan.stderr + highScan.stdout);
const highHtml = fs.readFileSync(path.join(highReport, 'review.html'), 'utf8');
const highSummary = highHtml.match(/<span class="summary" id="summary" data-exact="(\d+)" data-similar="(\d+)" data-conflict="(\d+)" data-new="(\d+)" data-unreadable="(\d+)"/);
assert.ok(highSummary, 'custom-threshold report contains category counts');
assert.ok(Number(highSummary[2]) > Number(summary[2]), 'larger threshold flags more rows for review');
const highId = highHtml.match(/const scanId="([a-f0-9]{64})"/);
assert.ok(highId, 'custom-threshold report contains a scan ID');
const highApproval = path.join(highReport, 'approved.json');
fs.writeFileSync(highApproval, JSON.stringify({ scanId: highId[1], selected: [] }));
const mismatchedLimit = run('apply', highLibrary, incoming, highApproval);
assert.equal(mismatchedLimit.status, 2, mismatchedLimit.stderr + mismatchedLimit.stdout);
assert.match(mismatchedLimit.stdout, /审核清单与当前相册或备份不一致/);
const sameLimit = run('apply', highLibrary, incoming, highApproval, '--similarity-limit', '176');
assert.equal(sameLimit.status, 0, sameLimit.stderr + sameLimit.stdout);
console.log('Integration test passed: review exports, image metadata, groups, thresholds, safe copy, stale approvals.');

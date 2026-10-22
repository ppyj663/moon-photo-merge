import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
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
const escapedName = "相册 & O'Neil.png";
fs.copyFileSync(path.join(incoming, 'similar.png'), path.join(incoming, escapedName));

const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const run = (...args) => spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', ['run', 'cmd/main', '--', ...args], {
  cwd: project, encoding: 'utf8',
});
const help = run('--help');
assert.equal(help.status, 0, help.stderr + help.stdout);
assert.match(help.stdout, /scan <现有相册>/);
assert.match(help.stdout, /apply <现有相册>/);
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
const html = fs.readFileSync(path.join(report, 'review.html'), 'utf8');
assert.ok(html.includes("incoming/相册 &amp; O&#39;Neil.png"), 'report escapes user-controlled filenames');
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
for (const [index, kind] of ['exact', 'similar', 'conflict', 'new', 'unreadable'].entries()) {
  const rows = [...html.matchAll(new RegExp(`<tr data-kind="${kind}">`, 'g'))].length;
  assert.equal(Number(summary[index + 1]), rows, `${kind} summary matches report rows`);
}
const originalHash = hash(path.join(library, 'original.png'));
const approved = path.join(report, 'approved.json');
fs.writeFileSync(approved, 'not json');
const malformed = run('apply', library, incoming, approved);
assert.equal(malformed.status, 2, malformed.stderr + malformed.stdout);
assert.match(malformed.stdout, /不是有效 JSON/);
for (const invalid of [
  { scanId: id[1] },
  { scanId: id[1], selected: ['incoming/new.jpg', 7] },
]) {
  fs.writeFileSync(approved, JSON.stringify(invalid));
  const rejected = run('apply', library, incoming, approved);
  assert.equal(rejected.status, 2, rejected.stderr + rejected.stdout);
  assert.deepEqual(fs.readdirSync(library), ['original.png']);
}
fs.writeFileSync(approved, JSON.stringify({
  scanId: id[1], selected: ['incoming/new.jpg', 'incoming/duplicate.png'],
}));
const rejected = run('apply', library, incoming, approved);
assert.equal(rejected.status, 2, rejected.stderr + rejected.stdout);
assert.deepEqual(fs.readdirSync(library), ['original.png']);

fs.writeFileSync(approved, JSON.stringify({
  scanId: id[1], selected: ['incoming/new.jpg', 'incoming/original.png', 'incoming/similar.png'],
}));
const applied = run('apply', library, incoming, approved);
assert.equal(applied.status, 0, applied.stderr + applied.stdout);
assert.equal(hash(path.join(library, 'original.png')), originalHash);
assert.equal(hash(path.join(library, 'new.jpg')), hash(path.join(incoming, 'new.jpg')));
assert.equal(hash(path.join(library, 'original-import-1.png')), hash(path.join(incoming, 'original.png')));
assert.equal(hash(path.join(library, 'similar.png')), hash(path.join(incoming, 'similar.png')));
const stale = run('apply', library, incoming, approved);
assert.equal(stale.status, 2, stale.stderr + stale.stdout);
console.log('Integration test passed: classifications, prevalidation, safe copy, stale approval.');

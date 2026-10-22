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

const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const run = (...args) => spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', ['run', 'cmd/main', '--', ...args], {
  cwd: project, encoding: 'utf8',
});
const first = run('scan', library, incoming, report);
assert.equal(first.status, 0, first.stderr + first.stdout);
const html = fs.readFileSync(path.join(report, 'review.html'), 'utf8');
const id = html.match(/const scanId="([a-f0-9]{64})"/);
assert.ok(id, 'report contains a scan ID');
for (const kind of ['exact', 'similar', 'conflict', 'new', 'unreadable']) {
  assert.ok(html.includes(`<tr data-kind="${kind}">`), `missing ${kind} classification`);
}
const originalHash = hash(path.join(library, 'original.png'));
const approved = path.join(report, 'approved.json');
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

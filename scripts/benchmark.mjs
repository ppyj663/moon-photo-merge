import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const imageExtension = /\.(jpe?g|png)$/i;

function usage() {
  console.error('Usage: node scripts/benchmark.mjs <library-dir> <incoming-dir> [--runs 1..20] [--output file]');
  process.exit(2);
}

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function canonicalFuturePath(candidate) {
  let current = path.resolve(candidate);
  const suffix = [];
  while (!fs.existsSync(current)) {
    const parent = path.dirname(current);
    if (parent === current) throw new Error('Could not resolve output path.');
    suffix.unshift(path.basename(current));
    current = parent;
  }
  return path.join(fs.realpathSync(current), ...suffix);
}

function parseArgs(args) {
  if (args.length < 2) usage();
  const options = { library: path.resolve(args[0]), incoming: path.resolve(args[1]), runs: 5, output: null };
  for (let index = 2; index < args.length; index += 1) {
    const option = args[index];
    const value = args[index + 1];
    if (!value || value.startsWith('--')) usage();
    if (option === '--runs') {
      if (!/^\d+$/.test(value)) usage();
      options.runs = Number(value);
      index += 1;
    } else if (option === '--output') {
      options.output = path.resolve(value);
      index += 1;
    } else {
      usage();
    }
  }
  if (options.runs < 1 || options.runs > 20) usage();
  for (const input of [options.library, options.incoming]) {
    if (!fs.statSync(input).isDirectory()) throw new Error('Both input paths must be directories.');
  }
  const libraryRoot = fs.realpathSync(options.library);
  const incomingRoot = fs.realpathSync(options.incoming);
  if (isInside(libraryRoot, incomingRoot) || isInside(incomingRoot, libraryRoot)) {
    throw new Error('Input directories must not contain one another.');
  }
  if (options.output && [libraryRoot, incomingRoot].some(root => isInside(root, canonicalFuturePath(options.output)))) {
    throw new Error('The summary output file must be outside both input directories.');
  }
  return options;
}

function imageStats(root) {
  let files = 0;
  let bytes = 0n;
  const visit = directory => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const fullPath = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      else if (entry.isFile() && imageExtension.test(entry.name)) {
        files += 1;
        bytes += BigInt(fs.statSync(fullPath).size);
      }
    }
  };
  visit(root);
  return { files, bytes: bytes.toString() };
}

function invokeScan(library, incoming, report, label) {
  const started = process.hrtime.bigint();
  const result = spawnSync(
    process.platform === 'win32' ? 'moon.exe' : 'moon',
    ['run', 'cmd/main', '--', 'scan', library, incoming, report],
    { cwd: project, encoding: 'utf8', timeout: 15 * 60 * 1000, maxBuffer: 10 * 1024 * 1024 },
  );
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  if (result.error) throw new Error(`${label} failed to launch MoonBit CLI: ${result.error.message}`);
  if (result.status !== 0) {
    throw new Error(`${label} scan failed (exit ${result.status ?? result.signal ?? 'unknown'}); rerun the command locally to inspect its output.`);
  }
  const inventory = JSON.parse(fs.readFileSync(path.join(report, 'inventory.json'), 'utf8'));
  const rows = JSON.parse(fs.readFileSync(path.join(report, 'review.json'), 'utf8'));
  const groups = JSON.parse(fs.readFileSync(path.join(report, 'similar-groups.json'), 'utf8'));
  const categories = { exact: 0, similar: 0, conflict: 0, new: 0, unreadable: 0 };
  for (const row of rows) categories[row.kind] = (categories[row.kind] ?? 0) + 1;
  return {
    elapsedMs,
    metrics: {
      incomingFiles: inventory.total,
      incomingBytes: inventory.bytes,
      readableFiles: inventory.readable,
      unreadableFiles: inventory.unreadable,
      decodedPixels: inventory.pixels,
      duplicateFileGroups: inventory.duplicateFileGroups,
      duplicateExtraFiles: inventory.duplicateExtraFiles,
      categories,
      similarityGroups: groups.length,
      directSimilarityPairs: groups.reduce((sum, group) => sum + group.pairCount, 0),
    },
  };
}

function percentile(sortedValues, fraction) {
  return sortedValues[Math.max(0, Math.ceil(sortedValues.length * fraction) - 1)];
}

function summarize(values) {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
  return {
    samplesMs: sorted.map(value => Number(value.toFixed(3))),
    minimumMs: Number(sorted[0].toFixed(3)),
    medianMs: Number(median.toFixed(3)),
    p95Ms: Number(percentile(sorted, 0.95).toFixed(3)),
    maximumMs: Number(sorted.at(-1).toFixed(3)),
  };
}

function toolVersion() {
  const result = spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', ['--version'], {
    cwd: project,
    encoding: 'utf8',
    timeout: 15000,
  });
  if (result.status !== 0) return 'unavailable';
  const match = result.stdout.match(/^moon\s+\S+\s+\([^)]+\)/m);
  return match ? match[0] : result.stdout.trim().split(/\r?\n/)[0].split(/[\\/]/)[0];
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'moon-photo-merge-benchmark-'));
  try {
    const scratchRoot = fs.realpathSync(scratch);
    if ([options.library, options.incoming].some(input => isInside(fs.realpathSync(input), scratchRoot))) {
      throw new Error('Temporary reports would be created inside an input folder; choose different input paths.');
    }
    const existing = imageStats(options.library);
    const incoming = imageStats(options.incoming);
    const warmup = invokeScan(options.library, options.incoming, path.join(scratch, 'warmup'), 'Warm-up');
    const timings = [];
    let metrics = null;
    for (let run = 0; run < options.runs; run += 1) {
      const result = invokeScan(
        options.library,
        options.incoming,
        path.join(scratch, `run-${run + 1}`),
        `Run ${run + 1}`,
      );
      if (JSON.stringify(warmup.metrics) !== JSON.stringify(result.metrics)) {
        throw new Error('Scan results changed after warm-up; an input file may have changed during the benchmark.');
      }
      if (metrics && JSON.stringify(metrics) !== JSON.stringify(result.metrics)) {
        throw new Error('Scan results changed between runs; an input file may have changed during the benchmark.');
      }
      metrics = result.metrics;
      timings.push(result.elapsedMs);
    }
    const totalBytes = BigInt(existing.bytes) + BigInt(incoming.bytes);
    const timing = summarize(timings);
    const summary = {
      schemaVersion: 1,
      measuredAtUtc: new Date().toISOString(),
      measurement: 'end_to_end_moon_run_scan',
      warmupRuns: 1,
      measuredRuns: options.runs,
      environment: {
        platform: process.platform,
        architecture: process.arch,
        osRelease: os.release(),
        nodeVersion: process.version,
        moonVersion: toolVersion(),
      },
      dataset: {
        existingImages: existing,
        incomingImages: incoming,
        totalInputBytes: totalBytes.toString(),
        scanMetrics: metrics,
      },
      timing,
      throughput: {
        totalInputMiBPerSecond: timing.medianMs === 0
          ? 0
          : Number((Number(totalBytes) / (1024 * 1024) / (timing.medianMs / 1000)).toFixed(3)),
      },
      privacy: 'Aggregate counts and timings only; paths, names, hashes, and image contents are omitted.',
      note: 'End-to-end CLI timing includes process startup, scan, decode, classification, grouping, and report export. Compare runs on the same machine and dataset.',
    };
    if (options.output) {
      fs.mkdirSync(path.dirname(options.output), { recursive: true });
      fs.writeFileSync(options.output, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
    }
    process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

try {
  main();
} catch (error) {
  console.error(`Benchmark failed: ${error.message}`);
  process.exitCode = 2;
}

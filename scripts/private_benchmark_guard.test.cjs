'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {validatePrivateBenchmark} = require('./private_benchmark_guard.cjs');

function setup(t) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'doku-guard-'));
  t.after(() => fs.rmSync(tmp, {recursive: true, force: true}));
  const repoRoot = path.join(tmp, 'repo');
  const privateDir = path.join(tmp, 'private');
  fs.mkdirSync(repoRoot); fs.mkdirSync(privateDir);
  const manifestPath = path.join(privateDir, 'manifest.json');
  fs.writeFileSync(manifestPath, '{}');
  fs.writeFileSync(path.join(privateDir, 'label.jpg'), 'synthetic placeholder');
  return {repoRoot, manifestPath, dest: path.join(privateDir, 'reports'),
    baseUrl: 'http://127.0.0.1:8082/etiket/',
    fixtures: [{imagePath: 'label.jpg'}], env: {}};
}

test('local consented paths outside repo pass without creating artifacts', t => {
  const opts = setup(t);
  assert.equal(validatePrivateBenchmark(opts), 'http://127.0.0.1:8082');
  assert.equal(fs.existsSync(opts.dest), false);
});
test('CI and non-loopback servers are refused before reading photos', t => {
  const opts = setup(t);
  assert.throws(() => validatePrivateBenchmark({...opts, env: {GITHUB_ACTIONS:'true'}}), /disabled in CI/);
  assert.throws(() => validatePrivateBenchmark({...opts, env: {CI:'1'}}), /disabled in CI/);
  for (const baseUrl of ['https://127.0.0.1:8082/', 'http://example.org/', 'file:///tmp/app', 'http://user:pass@localhost/']) {
    assert.throws(() => validatePrivateBenchmark({...opts, baseUrl}), /loopback HTTP|local HTTP/);
  }
});
test('rejects repo output, repo manifest and symlink output into repo', t => {
  const opts = setup(t);
  assert.throws(() => validatePrivateBenchmark({...opts, dest:path.join(opts.repoRoot,'build','private')}), /outside repository/);
  const linked = path.join(path.dirname(opts.manifestPath), 'linked');
  fs.symlinkSync(opts.repoRoot, linked, 'dir');
  assert.throws(() => validatePrivateBenchmark({...opts, dest:path.join(linked,'report')}), /outside repository/);
  assert.throws(() => validatePrivateBenchmark({...opts, manifestPath:path.join(opts.repoRoot,'manifest.json')}), /outside repository/);
});
test('rejects absolute, escaping and symlinked photo paths', t => {
  const opts = setup(t);
  const outside = path.join(path.dirname(opts.repoRoot), 'other.jpg');
  fs.writeFileSync(outside, 'placeholder');
  for (const imagePath of [outside, '../other.jpg', '../repo/not-here.jpg']) {
    assert.throws(() => validatePrivateBenchmark({...opts, fixtures:[{imagePath}]}));
  }
  fs.symlinkSync(outside, path.join(path.dirname(opts.manifestPath),'escape.jpg'));
  assert.throws(() => validatePrivateBenchmark({...opts, fixtures:[{imagePath:'escape.jpg'}]}), /inside private/);
});

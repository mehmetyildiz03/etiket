'use strict';
// Guard for consented real OCR fixtures. No image, GT or path is logged.
const fs = require('node:fs');
const path = require('node:path');

function canonicalPath(input) {
  let current = path.resolve(input);
  const missing = [];
  while (true) {
    try {
      return path.join(fs.realpathSync(current), ...missing);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      const parent = path.dirname(current);
      if (parent === current) throw new Error('Cannot resolve private benchmark path');
      missing.unshift(path.basename(current));
      current = parent;
    }
  }
}

function within(parent, child) {
  const relative = path.relative(parent, child);
  return relative === '' || (relative !== '..' &&
    !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative));
}

function validatePrivateBenchmark({repoRoot, manifestPath, dest, baseUrl, fixtures, env = process.env}) {
  if (env.GITHUB_ACTIONS === 'true' || (env.CI && env.CI !== 'false')) {
    throw new Error('Real-photo benchmark is disabled in CI');
  }
  let url;
  try { url = new URL(baseUrl); } catch (_) {
    throw new Error('Real-photo benchmark requires a local HTTP server');
  }
  if (url.protocol !== 'http:' ||
      !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      url.username || url.password) {
    throw new Error('Real-photo benchmark requires loopback HTTP only');
  }
  const root = canonicalPath(repoRoot);
  const manifest = canonicalPath(manifestPath);
  const output = canonicalPath(dest);
  if (within(root, manifest) || within(root, output)) {
    throw new Error('Real-photo manifest and reports must stay outside repository');
  }
  const privateDir = path.dirname(manifest);
  if (!Array.isArray(fixtures) || fixtures.length === 0) {
    throw new Error('Real-photo manifest requires cases');
  }
  for (const fixture of fixtures) {
    const imagePath = fixture.imagePath;
    if (typeof imagePath !== 'string' || !imagePath || path.isAbsolute(imagePath)) {
      throw new Error('Real-photo paths must be relative to private manifest');
    }
    const image = canonicalPath(path.resolve(privateDir, imagePath));
    if (!within(privateDir, image) || within(root, image)) {
      throw new Error('Real-photo images must stay inside private manifest directory');
    }
    if (!fs.statSync(image).isFile()) {
      throw new Error('Real-photo fixture is not a file');
    }
  }
  return url.origin;
}

module.exports = {validatePrivateBenchmark};

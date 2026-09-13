import { lstat, readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { sha256 } from './serialization.mjs';

export function validateArtifactPath(path) {
  if (typeof path !== 'string' || !path || path.split('/').some((part) => (
    !/^[A-Za-z0-9_.-]+$/.test(part) || part === '.' || part === '..'
  ))) throw new Error(`Invalid artifact path: ${path}`);
  return path;
}

async function filesBelow(directory, expected, directories, prefix = '') {
  const files = [];
  for (const entry of await readdir(join(directory, prefix), { withFileTypes: true })) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      if (!directories.has(path)) throw new Error(`Snapshot file list contains an unowned directory: ${path}`);
      files.push(...await filesBelow(directory, expected, directories, path));
    } else if (entry.isFile()) {
      if (!expected.has(path)) throw new Error(`Snapshot file list contains an unowned file: ${path}`);
      files.push(path);
    } else throw new Error(`Snapshot contains a non-regular file: ${path}`);
  }
  return files.sort();
}

// Repair may omit owned artifacts, but never the manifest, hashes of present
// artifacts, or validation of the complete remaining file tree.
export async function readSnapshotArtifacts({ directory, allowMissingArtifacts = false }) {
  if (!(await lstat(join(directory, 'manifest.json'))).isFile()) {
    throw new Error('Snapshot manifest is a non-regular file');
  }
  const manifestBytes = await readFile(join(directory, 'manifest.json'));
  const manifest = JSON.parse(manifestBytes);
  if (manifest.formatVersion !== 1 || !Array.isArray(manifest.artifacts)) {
    throw new Error('Unsupported SDK snapshot manifest');
  }
  const expected = new Set(['manifest.json']);
  const folded = new Set(['manifest.json']);
  const directories = new Set();
  const roots = new Set();
  for (const artifact of manifest.artifacts) {
    validateArtifactPath(artifact.path);
    if (folded.has(artifact.path.toLowerCase())) {
      throw new Error(`Duplicate or reserved artifact path: ${artifact.path}`);
    }
    if (!['schema', 'fixture', 'catalog', 'notice'].includes(artifact.kind)
      || !/^[a-f0-9]{64}$/.test(artifact.sha256) || !Number.isSafeInteger(artifact.bytes) || artifact.bytes < 0) {
      throw new Error(`Invalid SDK snapshot artifact metadata: ${artifact.path}`);
    }
    if (artifact.kind === 'schema' || artifact.kind === 'fixture') {
      if (typeof artifact.root !== 'string' || !artifact.root || roots.has(artifact.root)) {
        throw new Error(`Duplicate or missing schema root: ${artifact.root}`);
      }
      roots.add(artifact.root);
    }
    if ((artifact.kind === 'catalog') !== (artifact.path === 'catalog.json')) {
      throw new Error(`Invalid SDK snapshot catalogue: ${artifact.path}`);
    }
    expected.add(artifact.path);
    folded.add(artifact.path.toLowerCase());
    for (let parent = dirname(artifact.path); parent !== '.'; parent = dirname(parent)) directories.add(parent);
  }
  if (!expected.has('catalog.json')) throw new Error('SDK snapshot is missing catalog.json');
  for (const directory of directories) {
    if (folded.has(directory.toLowerCase())) throw new Error(`Conflicting file-directory ownership: ${directory}`);
  }
  const actualFiles = await filesBelow(directory, expected, directories);
  const present = new Set(actualFiles);
  const bytes = new Map();
  for (const artifact of manifest.artifacts) {
    if (allowMissingArtifacts && !present.has(artifact.path)) continue;
    const contents = await readFile(join(directory, artifact.path));
    if (sha256(contents) !== artifact.sha256 || contents.byteLength !== artifact.bytes) {
      throw new Error(`SHA-256 mismatch: ${artifact.path}`);
    }
    bytes.set(artifact.path, contents);
  }
  const files = [...expected].sort();
  if (!allowMissingArtifacts && JSON.stringify(files) !== JSON.stringify(actualFiles)) {
    throw new Error('Snapshot file list does not match its manifest');
  }
  return { manifest, manifestBytes, bytes, files };
}

export async function readSnapshot({ directory }) {
  const { manifest, manifestBytes, bytes, files } = await readSnapshotArtifacts({ directory });
  // All bytes have been verified before parsing any schema or catalogue.
  const schemas = {};
  for (const artifact of manifest.artifacts.filter(({ kind }) => kind === 'schema' || kind === 'fixture')) {
    schemas[artifact.root] = JSON.parse(bytes.get(artifact.path));
  }
  const catalog = JSON.parse(bytes.get('catalog.json'));
  bytes.set('manifest.json', manifestBytes);
  return {
    manifest, schemas, catalog, files,
    hashes: Object.fromEntries([...bytes].map(([path, contents]) => [path, sha256(contents)]).sort()),
  };
}

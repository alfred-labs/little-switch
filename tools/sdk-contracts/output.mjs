import { constants } from 'node:fs';
import { lstat, mkdir, readdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, parse, resolve, sep } from 'node:path';
import { readSnapshotArtifacts, validateArtifactPath } from './snapshot.mjs';

async function statIfPresent(path) {
  try {
    return await lstat(path);
  } catch (error) {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  }
}

async function checkDirectory(path) {
  const absolute = resolve(path);
  let current = parse(absolute).root;
  for (const part of absolute.slice(current.length).split(sep).filter(Boolean)) {
    current = join(current, part);
    const info = await statIfPresent(current);
    if (!info) return false;
    if (info.isSymbolicLink()) throw new Error(`Symbolic link in SDK output path: ${current}`);
    if (!info.isDirectory()) throw new Error(`SDK output ancestor is not a directory: ${current}`);
  }
  return true;
}

async function previousOwnership(directory) {
  if (!await checkDirectory(directory)) return [];
  const manifest = await statIfPresent(join(directory, 'manifest.json'));
  if (manifest) return (await readSnapshotArtifacts({ directory, allowMissingArtifacts: true })).files;
  const entries = await readdir(directory, { withFileTypes: true });
  if (entries.some((entry) => entry.isSymbolicLink())) {
    throw new Error('SDK bootstrap contains a symbolic link');
  }
  if (entries.length) throw new Error('Cannot bootstrap an SDK snapshot over unowned files or directories');
  return [];
}

async function preflight(directory, paths) {
  const previous = await previousOwnership(directory);
  const owned = new Set(previous);
  const existingNames = new Map(previous.map((path) => [path.toLowerCase(), path]));
  const planned = new Set();
  for (const path of paths) {
    validateArtifactPath(path);
    const folded = path.toLowerCase();
    if (planned.has(folded) || (existingNames.has(folded) && existingNames.get(folded) !== path)) {
      throw new Error(`Case-colliding SDK output path: ${path}`);
    }
    planned.add(folded);
    const destination = join(directory, path);
    await checkDirectory(dirname(destination));
    const info = await statIfPresent(destination);
    if (info && !info.isFile()) throw new Error(`SDK output is a non-regular file: ${path}`);
    if (info && !owned.has(path)) throw new Error(`SDK output is unowned: ${path}`);
  }
  for (const path of planned) {
    for (let parent = dirname(path); parent !== '.'; parent = dirname(parent)) {
      if (planned.has(parent)) throw new Error(`Conflicting SDK output file and directory: ${parent}`);
    }
  }
  return previous;
}

export async function writeSnapshot({ directory, outputs }) {
  const absolute = resolve(directory);
  const previous = await preflight(absolute, outputs.keys());
  const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | constants.O_NOFOLLOW;
  await mkdir(absolute, { recursive: true });
  for (const [path, { contents }] of outputs) {
    if (path === 'manifest.json') continue;
    await mkdir(dirname(join(absolute, path)), { recursive: true });
    await writeFile(join(absolute, path), contents, { flag: flags });
  }
  for (const path of previous.filter((path) => !outputs.has(path))) {
    await rm(join(absolute, path), { force: true });
  }
  // Publish the manifest only after all planned writes and owned removals finish.
  await writeFile(join(absolute, 'manifest.json'), outputs.get('manifest.json').contents, { flag: flags });
}

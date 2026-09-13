import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cp, mkdir, mkdtemp, readFile, readdir, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import test, { after, before } from 'node:test';
import { extractContracts } from './extract.mjs';
import { writeSnapshot } from './output.mjs';
import { readSnapshot } from './snapshot.mjs';

const toolingDirectory = fileURLToPath(new URL('.', import.meta.url));
const repositoryDirectory = fileURLToPath(new URL('../..', import.meta.url));
const missingArtifact = 'AnthropicCountTokensRequest.schema.json';
let temporaryDirectory;
let originalDirectory;

before(async () => {
  temporaryDirectory = await mkdtemp(join(await realpath(tmpdir()), 'wire-extraction-safety-'));
  originalDirectory = join(temporaryDirectory, 'original');
  await extractContracts({ outputDirectory: originalDirectory });
});

after(async () => {
  await rm(temporaryDirectory, { recursive: true, force: true });
});

async function workspace(name) {
  const directory = join(temporaryDirectory, name);
  await mkdir(directory);
  return directory;
}

async function repairFixture(name) {
  const directory = join(temporaryDirectory, name);
  await cp(originalDirectory, directory, { recursive: true });
  await rm(join(directory, missingArtifact));
  return directory;
}

test('bootstrap refuses an existing unowned output without replacing it', async () => {
  const directory = await workspace('foreign-output');
  const path = join(directory, 'catalog.json');
  await writeFile(path, 'unowned contents');
  await assert.rejects(extractContracts({ outputDirectory: directory }), /bootstrap|unowned/i);
  assert.equal(await readFile(path, 'utf8'), 'unowned contents');
  assert.deepEqual(await readdir(directory), ['catalog.json']);
});

for (const kind of ['root', 'ancestor', 'nested directory', 'file']) {
  test(`bootstrap refuses a symlink at the ${kind} without writing its target`, async () => {
    const directory = await workspace(`symlink-${kind.replaceAll(' ', '-')}`);
    const outside = join(directory, 'outside');
    await mkdir(outside);
    let output = join(directory, 'output');
    if (kind === 'root' || kind === 'ancestor') {
      await symlink(outside, output, 'dir');
      if (kind === 'ancestor') output = join(output, 'new-snapshot');
    } else {
      await mkdir(output);
      if (kind === 'nested directory') await symlink(outside, join(output, 'notices'), 'dir');
      else {
        await writeFile(join(outside, 'catalog.json'), 'unowned target');
        await symlink(join(outside, 'catalog.json'), join(output, 'catalog.json'));
      }
    }
    await assert.rejects(extractContracts({ outputDirectory: output }), /symlink|symbolic link|non-regular/i);
    assert.deepEqual(await readdir(outside), kind === 'file' ? ['catalog.json'] : []);
    if (kind === 'file') assert.equal(await readFile(join(outside, 'catalog.json'), 'utf8'), 'unowned target');
  });
}

test('a missing owned artifact does not hide corruption in a remaining artifact', async () => {
  const directory = await repairFixture('corrupt-repair');
  const manifest = await readFile(join(directory, 'manifest.json'));
  await writeFile(join(directory, 'catalog.json'), 'corrupt catalogue');
  await assert.rejects(extractContracts({ outputDirectory: directory }), /SHA-256 mismatch: catalog.json/);
  assert.equal(await readFile(join(directory, 'catalog.json'), 'utf8'), 'corrupt catalogue');
  assert.deepEqual(await readFile(join(directory, 'manifest.json')), manifest);
  await assert.rejects(readFile(join(directory, missingArtifact)), { code: 'ENOENT' });
});

test('a missing owned artifact does not hide an unowned file', async () => {
  const directory = await repairFixture('unowned-repair');
  const manifest = await readFile(join(directory, 'manifest.json'));
  await writeFile(join(directory, 'foreign.txt'), 'keep me');
  await assert.rejects(extractContracts({ outputDirectory: directory }), /unowned|file list/i);
  assert.equal(await readFile(join(directory, 'foreign.txt'), 'utf8'), 'keep me');
  assert.deepEqual(await readFile(join(directory, 'manifest.json')), manifest);
  await assert.rejects(readFile(join(directory, missingArtifact)), { code: 'ENOENT' });
});

test('a missing owned artifact does not hide a symlink in the remaining tree', async () => {
  const directory = await repairFixture('symlink-repair');
  const outside = join(temporaryDirectory, 'outside-catalog.json');
  const original = await readFile(join(directory, 'catalog.json'));
  await writeFile(outside, original);
  await rm(join(directory, 'catalog.json'));
  await symlink(outside, join(directory, 'catalog.json'));
  await assert.rejects(extractContracts({ outputDirectory: directory }), /symlink|symbolic link|non-regular/i);
  assert.deepEqual(await readFile(outside), original);
  await assert.rejects(readFile(join(directory, missingArtifact)), { code: 'ENOENT' });
});

test('repair retains old ownership while restoring missing artifacts and removing retired ones', async () => {
  const directory = await repairFixture('retired-repair');
  const path = join(directory, 'manifest.json');
  const manifest = JSON.parse(await readFile(path, 'utf8'));
  const retired = Buffer.from('{"type":"string"}\n');
  await writeFile(join(directory, 'Retired.schema.json'), retired);
  manifest.artifacts.push({
    path: 'Retired.schema.json', kind: 'schema', root: 'Retired', bytes: retired.byteLength,
    sha256: createHash('sha256').update(retired).digest('hex'),
  });
  await writeFile(path, JSON.stringify(manifest));
  await extractContracts({ outputDirectory: directory });
  await assert.rejects(readFile(join(directory, 'Retired.schema.json')), { code: 'ENOENT' });
  assert.ok((await readSnapshot({ directory })).files.includes(missingArtifact));
});

test('a stale installed TypeScript compiler fails extraction before any output write', async () => {
  const directory = await workspace('compiler-mismatch');
  const tooling = join(directory, 'tools/sdk-contracts');
  await mkdir(tooling, { recursive: true });
  for (const path of await readdir(toolingDirectory)) {
    if ((path.endsWith('.mjs') && !path.endsWith('.test.mjs'))
      || ['contracts.ts', 'package.json', 'package-lock.json', 'tsconfig.json'].includes(path)) {
      await cp(join(toolingDirectory, path), join(tooling, path));
    }
  }
  await symlink(join(toolingDirectory, 'node_modules'), join(tooling, 'node_modules'), 'dir');
  await mkdir(join(directory, 'schemas'));
  for (const path of ['roots.json', 'sdk-sources.json']) {
    await cp(join(repositoryDirectory, 'schemas', path), join(directory, 'schemas', path));
  }
  const lockPath = join(tooling, 'package-lock.json');
  const lock = JSON.parse(await readFile(lockPath, 'utf8'));
  lock.packages['node_modules/typescript'].version = '5.9.2';
  await writeFile(lockPath, JSON.stringify(lock));
  const output = join(directory, 'schemas/upstream');
  await assert.rejects(promisify(execFile)(process.execPath, [join(tooling, 'extract.mjs')], {
    cwd: directory, timeout: 30_000,
  }), /typescript/i);
  await assert.rejects(readdir(output), { code: 'ENOENT' });
});

test('extraction attests the installed TypeScript compiler version', async () => {
  const installed = JSON.parse(await readFile(join(toolingDirectory, 'node_modules/typescript/package.json'), 'utf8'));
  const { manifest } = await readSnapshot({ directory: originalDirectory });
  assert.equal(manifest.generator.typescript, installed.version);
});

test('preflight rejects planned file-directory collisions before writing any artifact', async () => {
  const directory = await workspace('planned-collision');
  await assert.rejects(writeSnapshot({ directory, outputs: new Map([
    ['Parent.schema.json', { contents: 'first artifact' }],
    ['Parent.schema.json/Child.schema.json', { contents: 'second artifact' }],
    ['manifest.json', { contents: '{}' }],
  ]) }));
  assert.deepEqual(await readdir(directory), []);
});

test('missing artifacts cannot hide conflicting file-directory ownership in the manifest', async () => {
  const directory = await repairFixture('manifest-collision');
  const path = join(directory, 'manifest.json');
  const manifest = JSON.parse(await readFile(path, 'utf8'));
  manifest.artifacts.push({
    ...manifest.artifacts.find((entry) => entry.path === 'catalog.json'),
    path: 'catalog.json/Hidden.schema.json', kind: 'schema', root: 'Hidden',
  });
  const original = JSON.stringify(manifest);
  await writeFile(path, original);
  await assert.rejects(extractContracts({ outputDirectory: directory }), /collision|conflict/i);
  assert.equal(await readFile(path, 'utf8'), original);
  await assert.rejects(readFile(join(directory, missingArtifact)), { code: 'ENOENT' });
});

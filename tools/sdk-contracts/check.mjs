import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defaultOutputDirectory, extractContracts } from './extract.mjs';
import { readSnapshot } from './snapshot.mjs';

const previous = await readSnapshot({ directory: defaultOutputDirectory });
const temporaryDirectory = await mkdtemp(join(await realpath(tmpdir()), 'littleswitch-sdk-check-'));
try {
  const current = await extractContracts({ outputDirectory: temporaryDirectory });
  const changed = [...new Set([...previous.files, ...current.files])].sort()
    .filter((path) => previous.hashes[path] !== current.hashes[path]);
  if (changed.length) throw new Error(`SDK snapshots are stale; run mise run schemas:extract:\n${changed.join('\n')}`);
  console.log(`Verified ${current.files.length} SDK contract artifacts and a fresh extraction.`);
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}

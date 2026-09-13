import { cp, mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compareSnapshots } from './compare.mjs';
import { defaultOutputDirectory, extractContracts } from './extract.mjs';
import { serialize } from './serialization.mjs';
import { readSnapshot } from './snapshot.mjs';

export async function updateContracts({ directory = defaultOutputDirectory } = {}) {
  // Fail before writing if the old baseline is absent, incomplete, or modified.
  await readSnapshot({ directory });
  const temporaryDirectory = await mkdtemp(join(await realpath(tmpdir()), 'littleswitch-sdk-update-'));
  try {
    const previousDirectory = join(temporaryDirectory, 'previous');
    await cp(directory, previousDirectory, { recursive: true, errorOnExist: true, force: false });
    await readSnapshot({ directory: previousDirectory });
    // Dependencies must already match the deliberately edited exact pins and lock.
    await extractContracts({ outputDirectory: directory });
    return await compareSnapshots({ previousDirectory, currentDirectory: directory });
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length > 3) throw new Error('Usage: mise run schemas:update -- [upstream-directory]');
  const directory = process.argv[2]
    ? resolve(process.env.INIT_CWD ?? process.cwd(), process.argv[2]) : defaultOutputDirectory;
  process.stdout.write(serialize(await updateContracts({ directory })));
}

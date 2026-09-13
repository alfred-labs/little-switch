import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGenerator } from 'ts-json-schema-generator';
import ts from 'typescript';
import { buildCatalog } from './catalog.mjs';
import { validateContractBindings } from './inputs.mjs';
import { writeSnapshot } from './output.mjs';
import { compareText, serialize, sha256 } from './serialization.mjs';

const toolingDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryDirectory = resolve(toolingDirectory, '../..');
export const defaultOutputDirectory = join(repositoryDirectory, 'schemas/upstream');
const dialect = 'http://json-schema.org/draft-07/schema#';
const nodeVersion = '24.16.0';
const generatorOptions = Object.freeze({
  additionalProperties: true, functions: 'fail', jsDoc: 'basic', skipTypeCheck: false, sortProps: true,
});

async function readJSON(path) {
  return JSON.parse(await readFile(path, 'utf8'));
}

async function provenance(roots, sources, outputs) {
  const packageManifest = await readJSON(join(toolingDirectory, 'package.json'));
  const lock = await readJSON(join(toolingDirectory, 'package-lock.json'));
  const versions = {};
  for (const [name, version] of Object.entries(packageManifest.dependencies)) {
    const installed = await readJSON(join(toolingDirectory, 'node_modules', name, 'package.json'));
    if (!/^\d+\.\d+\.\d+$/.test(version) || installed.version !== version
      || lock.packages[`node_modules/${name}`]?.version !== version) {
      throw new Error(`Dependency must match its exact pinned version: ${name}`);
    }
    versions[name] = installed.version;
  }
  const compiler = await readJSON(join(toolingDirectory, 'node_modules/typescript/package.json'));
  if (compiler.version !== ts.version || ts.version !== lock.packages['node_modules/typescript']?.version) {
    throw new Error('Installed typescript compiler must match its locked version');
  }
  versions.typescript = ts.version;
  const sourceRecords = [];
  for (const source of sources) {
    const packageDirectory = join(toolingDirectory, 'node_modules', source.package);
    const installed = await readJSON(join(packageDirectory, 'package.json'));
    if (installed.version !== source.version || installed.license !== source.license) {
      throw new Error(`SDK source metadata does not match installed package: ${source.id}`);
    }
    const notice = await readFile(join(packageDirectory, source.noticeFile));
    const noticePath = `notices/${source.id}.LICENSE`;
    outputs.set(noticePath, { contents: notice, kind: 'notice' });
    const declarations = [];
    const modules = [...new Set(roots.filter(({ sdk }) => sdk === source.id).map(({ module }) => module))].sort();
    for (const module of modules) {
      for (const suffix of ['.d.mts', '.d.ts']) {
        const path = `${module}${suffix}`;
        declarations.push({ path, sha256: sha256(await readFile(join(packageDirectory, path))) });
      }
    }
    sourceRecords.push({ ...source, notice: noticePath, noticeSHA256: sha256(notice), declarations });
  }
  const inputPaths = [
    'schemas/roots.json', 'schemas/sdk-sources.json',
    ...['package.json', 'package-lock.json', 'tsconfig.json', 'contracts.ts', 'extract.mjs', 'catalog.mjs', 'inputs.mjs', 'serialization.mjs', 'snapshot.mjs', 'output.mjs']
      .map((path) => `tools/sdk-contracts/${path}`),
  ].sort();
  const inputs = {};
  for (const path of inputPaths) inputs[path] = sha256(await readFile(join(repositoryDirectory, path)));
  return { sourceRecords, inputs, versions };
}

export async function extractContracts({ outputDirectory = defaultOutputDirectory } = {}) {
  if (process.versions.node !== nodeVersion) {
    throw new Error(`Extraction requires Node ${nodeVersion}; use mise run schemas:extract`);
  }
  const { roots } = await readJSON(join(repositoryDirectory, 'schemas/roots.json'));
  const { sources } = await readJSON(join(repositoryDirectory, 'schemas/sdk-sources.json'));
  validateContractBindings({ sourceText: await readFile(join(toolingDirectory, 'contracts.ts'), 'utf8'), sources, roots });
  const outputs = new Map();
  const { sourceRecords, inputs, versions } = await provenance(roots, sources, outputs);
  const generator = createGenerator({
    ...generatorOptions, type: '*',
    path: join(toolingDirectory, 'contracts.ts'), tsconfig: join(toolingDirectory, 'tsconfig.json'),
  });
  const schemas = {};
  for (const root of [...roots].sort((left, right) => compareText(left.name, right.name))) {
    const schema = generator.createSchema(root.name);
    if (schema.$schema !== dialect) throw new Error(`Unexpected schema dialect: ${root.name}`);
    schemas[root.name] = schema;
    outputs.set(root.schema, { contents: serialize(schema), kind: 'schema', root: root.name });
  }
  outputs.set('PresenceProbe.schema.json', {
    contents: serialize(generator.createSchema('PresenceProbe')), kind: 'fixture', root: 'PresenceProbe',
  });
  outputs.set('catalog.json', { contents: serialize(buildCatalog(schemas)), kind: 'catalog' });
  const artifacts = [...outputs].sort(([left], [right]) => compareText(left, right)).map(([path, entry]) => ({
    path, kind: entry.kind, sha256: sha256(entry.contents), bytes: Buffer.byteLength(entry.contents),
    ...(entry.root ? { root: entry.root } : {}),
  }));
  const manifest = {
    formatVersion: 1, dialect,
    generator: {
      package: 'ts-json-schema-generator', version: versions['ts-json-schema-generator'],
      typescript: versions.typescript, ajv: versions.ajv, node: nodeVersion, options: generatorOptions,
      scope: 'TypeScript declarations only; not complete API business validation.',
      additionalPropertiesPolicy: 'Objects are open unless their extracted index signature constrains additional values.',
    },
    sources: sourceRecords, inputs, artifacts,
  };
  outputs.set('manifest.json', { contents: serialize(manifest), kind: 'manifest' });
  await writeSnapshot({ directory: outputDirectory, outputs });
  const files = [...outputs.keys()].sort();
  return { files, hashes: Object.fromEntries(files.map((path) => [path, sha256(outputs.get(path).contents)])) };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await extractContracts({
    outputDirectory: process.argv[2]
      ? resolve(process.env.INIT_CWD ?? process.cwd(), process.argv[2]) : defaultOutputDirectory,
  });
  console.log(`Extracted ${result.files.length} deterministic SDK contract artifacts.`);
}

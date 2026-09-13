import assert from 'node:assert/strict';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import test, { after, before } from 'node:test';
import Ajv from 'ajv';
import { extractContracts } from './extract.mjs';
import { buildCatalog } from './catalog.mjs';
import { compareCatalogs, compareSnapshots } from './compare.mjs';
import { readSnapshot } from './snapshot.mjs';
import { validateContractBindings } from './inputs.mjs';
import { updateContracts } from './update.mjs';

let temporaryDirectory;
let first;
let second;
let snapshot;
const validators = new Map();

before(async () => {
  temporaryDirectory = await mkdtemp(join(await realpath(tmpdir()), 'wire-contracts-'));
  first = await extractContracts({ outputDirectory: join(temporaryDirectory, 'first') });
  second = await extractContracts({ outputDirectory: join(temporaryDirectory, 'second') });
  snapshot = await readSnapshot({ directory: join(temporaryDirectory, 'first') });
});

after(async () => {
  await rm(temporaryDirectory, { recursive: true, force: true });
});

function validate(root, value) {
  if (!validators.has(root)) {
    validators.set(root, new Ajv({ strict: false, validateFormats: false }).compile(snapshot.schemas[root]));
  }
  const before = structuredClone(value);
  const result = validators.get(root)(value);
  assert.deepEqual(value, before, `${root} validation must not coerce input`);
  return result;
}

test('same SDK inputs produce identical contracts', async () => {
  assert.deepEqual(first.hashes, second.hashes);
  assert.deepEqual(first.files, [...first.files].sort());
  assert.ok(first.files.includes('AnthropicCountTokensRequest.schema.json'));
  assert.ok(first.files.includes('OpenAIResponseCompactRequest.schema.json'));
  assert.equal(snapshot.manifest.dialect, 'http://json-schema.org/draft-07/schema#');
  assert.equal(snapshot.manifest.generator.options.additionalProperties, true);
  for (const schema of Object.values(snapshot.schemas)) {
    assert.equal(schema.$schema, 'http://json-schema.org/draft-07/schema#');
  }
});

test('presence fixtures preserve absent, explicit null, open values, and closed enums', async () => {
  const fixture = JSON.parse(await readFile(new URL('../../schemas/fixtures/presence.json', import.meta.url), 'utf8'));
  for (const entry of fixture.cases) {
    assert.equal(validate(fixture.root, entry.value), entry.valid, entry.name);
  }
});

test('the TypeScript contract admits fractional max_tokens and additional vendor properties', () => {
  assert.equal(validate('AnthropicRequest', {
    model: 'model-probe', max_tokens: 0.5, messages: [{ role: 'user', content: 'hello' }],
    vendor: { opaque: true },
  }), true);
});

test('the closed SDK finish reason rejects the provider extension sensitive', () => {
  const chunk = {
    id: 'chunk-probe', object: 'chat.completion.chunk', created: 1, model: 'model-probe',
    choices: [{ index: 0, delta: {}, finish_reason: null }],
  };
  assert.equal(validate('OpenAIChatChunk', chunk), true);
  assert.equal(validate('OpenAIChatChunk', {
    ...chunk, choices: [{ index: 0, delta: {}, finish_reason: 'sensitive' }],
  }), false);
});

for (const [root, request, nullIsValid] of [
  ['AnthropicRequest', { model: 'model-probe', max_tokens: 1, messages: [{ role: 'user', content: 'hello' }] }, false],
  ['OpenAIResponseRequest', { model: 'model-probe', input: 'hello' }, true],
  ['OpenAIChatRequest', { model: 'model-probe', messages: [{ role: 'user', content: 'hello' }] }, true],
]) {
  test(`${root} preserves absent, false, true, and null stream branches`, () => {
    assert.equal(validate(root, request), true, 'absent stream');
    assert.equal(validate(root, { ...request, stream: false }), true, 'false stream');
    assert.equal(validate(root, { ...request, stream: true }), true, 'true stream');
    assert.equal(validate(root, { ...request, stream: null }), nullIsValid, 'null stream');
  });
}

test('count, compact, and exported error roots extract without inventing an HTTP envelope', () => {
  assert.equal(validate('AnthropicCountTokensRequest', {
    model: 'model-probe', messages: [{ role: 'user', content: 'hello' }],
  }), true);
  assert.equal(validate('OpenAIResponseCompactRequest', { model: 'model-probe', input: 'hello' }), true);
  assert.equal(validate('AnthropicError', {
    type: 'error', error: { type: 'invalid_request_error', message: 'invalid' }, request_id: null,
  }), true);
  const openAIError = { type: 'invalid_request_error', message: 'invalid', code: null, param: null };
  assert.equal(validate('OpenAIError', openAIError), true);
  assert.equal(validate('OpenAIError', { error: openAIError }), false);
});

test('the routing base keeps model IDs open without selecting a streaming branch', () => {
  assert.equal(validate('OpenAIResponseRequestBase', { model: 'future-provider-model', stream: true }), true);
  assert.equal(validate('OpenAIResponseRequestBase', { model: 'future-provider-model', stream: false }), true);
  assert.equal(validate('OpenAIResponseRequestBase', { input: 'hello' }), true);
  assert.equal(validate('OpenAIResponseRequestBase', { model: null }), false);
});

test('catalogue resolves nullable enum references at their owning property context', () => {
  const schema = {
    definitions: {
      Choice: { type: 'string', enum: ['a', 'b'] },
      Holder: {
        type: 'object', required: ['name'], properties: {
          name: { $ref: '#/definitions/Choice' },
          optional: { anyOf: [{ $ref: '#/definitions/Choice' }, { type: 'null' }] },
          open: { type: 'string' },
          next: { $ref: '#/definitions/Holder' },
        },
      },
    },
  };
  const catalog = buildCatalog({ Example: schema });
  assert.deepEqual(catalog.properties, [
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/name', key: 'name', required: true, nullable: false },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/next', key: 'next', required: false, nullable: false },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/open', key: 'open', required: false, nullable: false },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/optional', key: 'optional', required: false, nullable: true },
  ]);
  assert.deepEqual(catalog.enums, [
    { root: 'Example', definition: 'Choice', path: '#/definitions/Choice', values: ['a', 'b'] },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/name', values: ['a', 'b'] },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/optional', values: ['a', 'b', null] },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/optional/anyOf/0', values: ['a', 'b'] },
    { root: 'Example', definition: 'Holder', path: '#/definitions/Holder/properties/optional/anyOf/1', values: [null] },
  ]);
});

test('snapshot verification rejects modified bytes before attempting to parse a schema', async () => {
  const path = join(temporaryDirectory, 'second', 'AnthropicMessage.schema.json');
  const original = await readFile(path);
  await writeFile(path, 'not JSON');
  try {
    await assert.rejects(readSnapshot({ directory: join(temporaryDirectory, 'second') }), /SHA-256 mismatch: AnthropicMessage.schema.json/);
  } finally {
    await writeFile(path, original);
  }
});

test('snapshot verification rejects paths escaping the snapshot directory', async () => {
  const path = join(temporaryDirectory, 'second', 'manifest.json');
  const original = await readFile(path);
  const manifest = JSON.parse(original);
  manifest.artifacts[0].path = '../outside.schema.json';
  await writeFile(path, JSON.stringify(manifest));
  try {
    await assert.rejects(readSnapshot({ directory: join(temporaryDirectory, 'second') }), /Invalid artifact path/);
  } finally {
    await writeFile(path, original);
  }
});

test('checks reject a missing snapshot artifact and explicit extraction repairs its owned path', async () => {
  const path = join(temporaryDirectory, 'second', 'AnthropicMessage.schema.json');
  const original = await readFile(path);
  await rm(path);
  try {
    await assert.rejects(readSnapshot({ directory: join(temporaryDirectory, 'second') }), /ENOENT/);
    await extractContracts({ outputDirectory: join(temporaryDirectory, 'second') });
    assert.deepEqual((await readSnapshot({ directory: join(temporaryDirectory, 'second') })).hashes, first.hashes);
  } finally {
    await writeFile(path, original);
  }
});

test('provenance rejects value imports, incorrect SDK bindings, and unsafe output paths', () => {
  const sources = [{ id: 'example', package: 'sdk-example', noticeFile: 'LICENSE' }];
  const roots = [{ name: 'Example', sdk: 'example', module: 'resources/messages', export: 'Message', schema: 'Example.schema.json' }];
  const sourceText = "import type * as SDK from 'sdk-example/resources/messages';\nexport type Example = SDK.Message;";
  assert.doesNotThrow(() => validateContractBindings({ sourceText, sources, roots }));
  assert.throws(() => validateContractBindings({ sourceText: sourceText.replace('import type', 'import'), sources, roots }), /type-only/);
  assert.throws(() => validateContractBindings({ sourceText: sourceText.replace('SDK.Message', 'SDK.NonStreamingMessage'), sources, roots }), /does not match/);
  assert.throws(() => validateContractBindings({ sourceText, sources, roots: [{ ...roots[0], schema: '../escape.schema.json' }] }), /Invalid artifact path/);
  assert.throws(() => validateContractBindings({ sourceText, sources, roots: [roots[0], roots[0]] }), /unique/);
});

test('upgrade comparison classifies added, removed, required, nullable, and enum changes', () => {
  const oldCatalog = buildCatalog({ Example: { definitions: { Value: {
    type: 'object', properties: {
      removed: { type: 'string' },
      value: { type: 'string', enum: ['a', 'b'] },
    },
  } } } });
  const newCatalog = buildCatalog({ Example: { definitions: { Value: {
    type: 'object', required: ['value'], properties: {
      added: { type: 'number' },
      value: { type: ['string', 'null'], enum: ['b', 'c', null] },
    },
  } } } });
  const changes = compareCatalogs(oldCatalog, newCatalog);
  assert.deepEqual(changes.map(({ kind }) => kind).sort(), [
    'enum-values-added', 'enum-values-removed', 'nullable-changed', 'property-added',
    'property-removed', 'required-changed',
  ]);
  assert.deepEqual(changes.find(({ kind }) => kind === 'enum-values-added').values, ['c', null]);
  assert.deepEqual(changes.find(({ kind }) => kind === 'enum-values-removed').values, ['a']);
});

test('identical verified snapshots have no upgrade changes', async () => {
  const comparison = await compareSnapshots({
    previousDirectory: join(temporaryDirectory, 'first'),
    currentDirectory: join(temporaryDirectory, 'second'),
  });
  assert.deepEqual(comparison.changes, []);
});

test('the mise comparison command emits only parseable JSON on stdout', async () => {
  const cwd = fileURLToPath(new URL('../..', import.meta.url));
  for (const directory of [temporaryDirectory, relative(cwd, temporaryDirectory)]) {
    const { stdout } = await promisify(execFile)('mise', [
      'run', 'schemas:compare', '--', join(directory, 'first'), join(directory, 'second'),
    ], { cwd });
    assert.deepEqual(JSON.parse(stdout).changes, []);
  }
});

test('an unchanged upstream update preserves all artifact hashes and reports no changes', async () => {
  const directory = join(temporaryDirectory, 'second');
  const previous = await readSnapshot({ directory });
  assert.deepEqual((await updateContracts({ directory })).changes, []);
  assert.deepEqual((await readSnapshot({ directory })).hashes, previous.hashes);
});

test('upstream updates require an existing snapshot and do not bootstrap implicitly', async () => {
  const directory = join(temporaryDirectory, 'missing');
  await assert.rejects(updateContracts({ directory }), /ENOENT/);
  await assert.rejects(readFile(join(directory, 'manifest.json')), /ENOENT/);
});

test('upstream updates reject corrupt old snapshots before making any write', async () => {
  const directory = join(temporaryDirectory, 'second');
  const path = join(directory, 'AnthropicMessage.schema.json');
  const original = await readFile(path);
  const originalManifest = await readFile(join(directory, 'manifest.json'));
  await writeFile(path, 'corrupt old snapshot');
  try {
    await assert.rejects(updateContracts({ directory }), /SHA-256 mismatch/);
    assert.equal(await readFile(path, 'utf8'), 'corrupt old snapshot');
    assert.deepEqual(await readFile(join(directory, 'manifest.json')), originalManifest);
  } finally {
    await writeFile(path, original);
  }
});

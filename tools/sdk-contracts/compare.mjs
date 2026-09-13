import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSnapshot } from './snapshot.mjs';
import { compareText, serialize, sortedValues } from './serialization.mjs';

const identity = ({ root, path }) => JSON.stringify([root, path]);
const context = ({ root, definition, path }) => ({ root, definition, path });

export function compareCatalogs(previous, current) {
  const changes = [];
  const oldProperties = new Map(previous.properties.map((entry) => [identity(entry), entry]));
  const newProperties = new Map(current.properties.map((entry) => [identity(entry), entry]));
  for (const [id, old] of oldProperties) {
    const replacement = newProperties.get(id);
    if (!replacement) changes.push({ ...context(old), kind: 'property-removed' });
    else {
      for (const field of ['required', 'nullable']) {
        if (old[field] !== replacement[field]) {
          changes.push({ ...context(old), kind: `${field}-changed`, before: old[field], after: replacement[field] });
        }
      }
    }
  }
  for (const [id, added] of newProperties) {
    if (!oldProperties.has(id)) changes.push({ ...context(added), kind: 'property-added' });
  }
  const oldEnums = new Map(previous.enums.map((entry) => [identity(entry), entry]));
  const newEnums = new Map(current.enums.map((entry) => [identity(entry), entry]));
  for (const [id, old] of oldEnums) {
    const replacement = newEnums.get(id);
    if (!replacement) changes.push({ ...context(old), kind: 'enum-removed', values: old.values });
    else {
      const added = replacement.values.filter((value) => !old.values.includes(value));
      const removed = old.values.filter((value) => !replacement.values.includes(value));
      if (added.length) changes.push({ ...context(old), kind: 'enum-values-added', values: sortedValues(added) });
      if (removed.length) changes.push({ ...context(old), kind: 'enum-values-removed', values: sortedValues(removed) });
    }
  }
  for (const [id, added] of newEnums) {
    if (!oldEnums.has(id)) changes.push({ ...context(added), kind: 'enum-added', values: added.values });
  }
  return changes.sort((left, right) => (
    compareText(left.root, right.root) || compareText(left.path, right.path) || compareText(left.kind, right.kind)
  ));
}

export async function compareSnapshots({ previousDirectory, currentDirectory }) {
  const previous = await readSnapshot({ directory: previousDirectory });
  const current = await readSnapshot({ directory: currentDirectory });
  const changes = compareCatalogs(previous.catalog, current.catalog);
  const schemaArtifacts = (snapshot) => new Map(snapshot.manifest.artifacts
    .filter(({ kind }) => kind === 'schema').map((entry) => [entry.root, entry]));
  const oldSchemas = schemaArtifacts(previous);
  const newSchemas = schemaArtifacts(current);
  for (const root of [...new Set([...oldSchemas.keys(), ...newSchemas.keys()])].sort()) {
    const old = oldSchemas.get(root);
    const replacement = newSchemas.get(root);
    if (!old) changes.push({ root, kind: 'schema-added' });
    else if (!replacement) changes.push({ root, kind: 'schema-removed' });
    else if (old.sha256 !== replacement.sha256) {
      // Preserve evidence of every changed schema, including constraints and annotations
      // not represented by the field/enum catalogue; this is not a compatibility verdict.
      changes.push({ root, kind: 'schema-changed', before: old.sha256, after: replacement.sha256 });
    }
  }
  return {
    formatVersion: 1, previousSources: previous.manifest.sources, currentSources: current.manifest.sources,
    changes: changes.sort((left, right) => (
      compareText(left.root, right.root) || compareText(left.path ?? '', right.path ?? '') || compareText(left.kind, right.kind)
    )),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [, , previousDirectory, currentDirectory] = process.argv;
  if (!previousDirectory || !currentDirectory || process.argv.length !== 4) {
    throw new Error('Usage: mise run schemas:compare -- <old-upstream-directory> <new-upstream-directory>');
  }
  const invocationDirectory = process.env.INIT_CWD ?? process.cwd();
  process.stdout.write(serialize(await compareSnapshots({
    previousDirectory: resolve(invocationDirectory, previousDirectory),
    currentDirectory: resolve(invocationDirectory, currentDirectory),
  })));
}

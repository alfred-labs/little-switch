import { compareText, sortedValues } from './serialization.mjs';

const pointerToken = (value) => value.replaceAll('~', '~0').replaceAll('/', '~1');

function resolveReference(root, reference) {
  if (!reference.startsWith('#/')) throw new Error(`Unsupported schema reference: ${reference}`);
  const value = reference.slice(2).split('/').reduce((node, token) => (
    node?.[decodeURIComponent(token).replaceAll('~1', '/').replaceAll('~0', '~')]
  ), root);
  if (value === undefined) throw new Error(`Unresolved schema reference: ${reference}`);
  return value;
}

// Evaluate a scalar only. Object and array constraints do not apply to scalars.
function acceptsScalar(schema, value, root, visited = new Set()) {
  if (typeof schema === 'boolean') return schema;
  if (schema.$ref) {
    if (visited.has(schema.$ref)) return false;
    return acceptsScalar(resolveReference(root, schema.$ref), value, root, new Set([...visited, schema.$ref]));
  }
  const type = value === null ? 'null' : typeof value;
  if (schema.type && ![].concat(schema.type).some((allowed) => (
    allowed === type || (allowed === 'integer' && Number.isInteger(value))
  ))) return false;
  if ('const' in schema && schema.const !== value) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.allOf && !schema.allOf.every((part) => acceptsScalar(part, value, root, visited))) return false;
  if (schema.anyOf && !schema.anyOf.some((part) => acceptsScalar(part, value, root, visited))) return false;
  if (schema.oneOf && schema.oneOf.filter((part) => acceptsScalar(part, value, root, visited)).length !== 1) return false;
  if (schema.not && acceptsScalar(schema.not, value, root, visited)) return false;
  return true;
}

function closedValues(schema, root, visited = new Set()) {
  if (typeof schema === 'boolean') return schema ? undefined : [];
  if (schema.$ref) {
    if (visited.has(schema.$ref)) return undefined;
    return closedValues(resolveReference(root, schema.$ref), root, new Set([...visited, schema.$ref]));
  }
  let values;
  if ('const' in schema) values = [schema.const];
  else if (schema.enum) values = schema.enum;
  else if (schema.type === 'null') values = [null];
  else if (schema.anyOf || schema.oneOf) {
    const branches = (schema.anyOf ?? schema.oneOf).map((part) => closedValues(part, root, visited));
    if (branches.every((branch) => branch !== undefined)) values = branches.flat();
  } else if (schema.allOf) {
    values = schema.allOf.map((part) => closedValues(part, root, visited)).find((part) => part !== undefined);
  }
  if (values === undefined || values.some((value) => value !== null && typeof value === 'object')) return undefined;
  return sortedValues(values.filter((value) => acceptsScalar(schema, value, root)));
}

export function buildCatalog(schemas) {
  const properties = [];
  const enums = [];
  for (const [root, schema] of Object.entries(schemas).sort(([left], [right]) => compareText(left, right))) {
    function visit(node, path, definition) {
      if (typeof node === 'boolean') return;
      const values = closedValues(node, schema);
      if (values !== undefined) enums.push({ root, definition, path, values });
      for (const [key, property] of Object.entries(node.properties ?? {})) {
        const propertyPath = `${path}/properties/${pointerToken(key)}`;
        properties.push({
          root, definition, path: propertyPath, key,
          required: (node.required ?? []).includes(key),
          nullable: acceptsScalar(property, null, schema),
        });
        visit(property, propertyPath, definition);
      }
      for (const [name, child] of Object.entries(node.definitions ?? {})) {
        visit(child, `${path}/definitions/${pointerToken(name)}`, name);
      }
      for (const keyword of ['anyOf', 'oneOf', 'allOf']) {
        (node[keyword] ?? []).forEach((child, index) => visit(child, `${path}/${keyword}/${index}`, definition));
      }
      for (const keyword of ['items', 'additionalItems', 'additionalProperties', 'not', 'contains']) {
        if (node[keyword] !== undefined) {
          if (Array.isArray(node[keyword])) {
            node[keyword].forEach((child, index) => visit(child, `${path}/${keyword}/${index}`, definition));
          } else visit(node[keyword], `${path}/${keyword}`, definition);
        }
      }
      for (const [key, child] of Object.entries(node.patternProperties ?? {})) {
        visit(child, `${path}/patternProperties/${pointerToken(key)}`, definition);
      }
    }
    visit(schema, '#', root);
  }
  const sortEntries = (entries) => entries.sort((left, right) => (
    compareText(left.root, right.root) || compareText(left.path, right.path)
  ));
  return { formatVersion: 1, properties: sortEntries(properties), enums: sortEntries(enums) };
}

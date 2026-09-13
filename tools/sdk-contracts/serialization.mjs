import { createHash } from 'node:crypto';

export function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

export function serialize(value) {
  return `${JSON.stringify(canonical(value), null, 2)}\n`;
}

export function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

export function sortedValues(values) {
  const unique = new Map(values.map((value) => [JSON.stringify(value), value]));
  return [...unique].sort(([left], [right]) => compareText(left, right)).map(([, value]) => value);
}

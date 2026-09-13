// Strict unified diffs for this source copy: no fuzz, renames, shell or file writes.
export function reconstructPatch(original, patch, target) {
  const decode = (bytes) => new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const source = decode(original);
  const diff = decode(patch);
  const fail = () => { throw new Error(`Invalid patch for ${target}`); };
  if (!source.endsWith("\n") || !diff.endsWith("\n")) fail();
  const lines = source.slice(0, -1).split("\n");
  const changes = diff.slice(0, -1).split("\n");
  if (changes.shift() !== `--- a/${target}` || changes.shift() !== `+++ b/${target}`) fail();
  let cursor = 0;
  let index = 0;
  let hunks = 0;
  const output = [];
  while (index < changes.length) {
    const match = /^@@ -(\d+),(\d+) \+(\d+),(\d+) @@$/.exec(changes[index++]);
    if (!match) fail();
    const [oldStart, oldCount, newStart, newCount] = match.slice(1).map(Number);
    if (![oldStart, oldCount, newStart, newCount].every(Number.isSafeInteger)
      || oldStart < 1 || newStart < 1 || oldStart - 1 < cursor || oldStart - 1 > lines.length) fail();
    output.push(...lines.slice(cursor, oldStart - 1));
    cursor = oldStart - 1;
    if (output.length !== newStart - 1) fail();
    let removed = 0;
    let added = 0;
    while (index < changes.length && !changes[index].startsWith("@@ ")) {
      const change = changes[index++];
      const kind = change[0];
      const value = change.slice(1);
      if (![" ", "-", "+"].includes(kind)) fail();
      if (kind !== "+") {
        if (cursor >= lines.length || lines[cursor++] !== value) fail();
        removed++;
      }
      if (kind !== "-") {
        output.push(value);
        added++;
      }
      if (removed > oldCount || added > newCount) fail();
    }
    if (removed !== oldCount || added !== newCount) fail();
    hunks++;
  }
  if (!hunks) fail();
  output.push(...lines.slice(cursor));
  return Buffer.from(`${output.join("\n")}\n`);
}

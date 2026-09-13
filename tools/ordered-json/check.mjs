import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { reconstructPatch } from "./patch.mjs";

const vendorRoot = fileURLToPath(new URL("../../Vendor/OrderedJSON", import.meta.url));
const sourcePaths = [
  "Array+JSONValue.swift", "JSONNumberLiteral.swift", "JSONType.swift", "JSONValue+Codable.swift",
  "JSONValue+ExpressibleByLiteral.swift", "JSONValue+Parse.swift", "JSONValue+Serialize.swift",
  "JSONValue+merge.swift", "JSONValue.swift",
].map((name) => `Sources/OrderedJSON/${name}`);
const testPaths = ["JSONNumberLiteralTests.swift", "JSONParserTests.swift", "JSONTestSuiteConformance.swift"]
  .map((name) => `Tests/OrderedJSONTests/${name}`);
const corpusPrefix = "Tests/OrderedJSONTests/JSONTestSuite/";
const upstreamPaths = new Set([...sourcePaths, ...testPaths, "LICENSE"]);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const fail = (message) => { throw new Error(message); };

function keys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).sort().join("\0") !== [...expected].sort().join("\0")) {
    fail("Invalid OrderedJSON manifest structure");
  }
}

function safePath(value) {
  if (typeof value !== "string" || !value || value.includes("\\") || value.includes("\0")
    || path.posix.isAbsolute(value) || value.split("/").some((part) => ["", ".", ".."].includes(part))) {
    fail("Invalid OrderedJSON manifest path");
  }
  return value;
}

function validHash(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail("Invalid manifest hash");
}

async function inventory(root) {
  for (const directory of [path.dirname(root), root]) {
    const info = await fs.lstat(directory);
    if (info.isSymbolicLink()) fail("OrderedJSON symbolic link is forbidden");
    if (!info.isDirectory()) fail("OrderedJSON inventory root is not a directory");
  }
  const files = [];
  const directories = [];
  async function walk(relative) {
    for (const entry of await fs.readdir(path.join(root, relative), { withFileTypes: true })) {
      const name = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isSymbolicLink()) fail(`OrderedJSON symbolic link is forbidden: ${name}`);
      if (entry.isDirectory()) {
        directories.push(name);
        await walk(name);
      } else if (entry.isFile()) files.push(name);
      else fail(`Unsupported OrderedJSON inventory entry: ${name}`);
    }
  }
  await walk("");
  return { files: files.sort(), directories: directories.sort() };
}

function readManifest(value) {
  keys(value, ["formatVersion", "upstream", "corpus", "files", "patchedFiles"]);
  keys(value.upstream, ["repository", "version", "revision"]);
  keys(value.corpus, ["repository", "revision"]);
  if (value.formatVersion !== 1 || value.upstream.version !== "0.14.0"
    || value.upstream.repository !== "https://github.com/ajevans99/swift-json-schema.git"
    || value.upstream.revision !== "88abaf2e821f55f7c3c04eb53385b3c0dd2fbf8f"
    || value.corpus.repository !== "https://github.com/nst/JSONTestSuite.git"
    || value.corpus.revision !== "1ef36fa01286573e846ac449e8683f8833c5b26a"
    || !Array.isArray(value.files) || !Array.isArray(value.patchedFiles)) fail("Invalid manifest revision or format");
  const files = new Map();
  for (const file of value.files) {
    const local = file?.origin === "local";
    keys(file, local ? ["path", "sha256", "origin"] : ["path", "sha256", "origin", "upstreamPath", "upstreamSha256"]);
    safePath(file.path);
    validHash(file.sha256);
    if (files.has(file.path)) fail(`Duplicate manifest path: ${file.path}`);
    if (local) {
      if (!["Package.swift", "Package.resolved", "README.md"].includes(file.path)
        && !/^patches\/\d{4}-[a-z0-9-]+\.patch$/.test(file.path)
        && !/^Tests\/OrderedJSONTests\/Local[A-Za-z]+Tests\.swift$/.test(file.path)) fail("Invalid local manifest path");
    } else {
      safePath(file.upstreamPath);
      validHash(file.upstreamSha256);
      if (file.origin === "orderedjson") {
        if (!upstreamPaths.has(file.upstreamPath)
          || !(file.path === file.upstreamPath
            || (sourcePaths.includes(file.upstreamPath) && file.path === `Upstream/${path.posix.basename(file.upstreamPath)}`))) {
          fail("Invalid upstream source path");
        }
      } else if (file.origin === "corpus") {
        if (file.path !== corpusPrefix + file.upstreamPath
          || !(file.upstreamPath === "LICENSE" || /^test_parsing\/[yni]_[^/]+\.json$/.test(file.upstreamPath))) {
          fail("Invalid corpus path");
        }
      } else fail("Invalid manifest origin");
    }
    files.set(file.path, file);
  }
  for (const required of [...upstreamPaths, `${corpusPrefix}LICENSE`, "Package.swift", "Package.resolved", "README.md"]) {
    if (!files.has(required)) fail(`Incomplete upstream inventory: ${required}`);
  }
  const corpus = [...files.values()].filter((file) => file.origin === "corpus" && file.upstreamPath !== "LICENSE");
  if (corpus.length !== 318 || ["y_", "n_", "i_"].some((prefix, index) =>
    corpus.filter((file) => path.posix.basename(file.path).startsWith(prefix)).length !== [95, 188, 35][index])) {
    fail("Invalid corpus inventory: expected 318 fixtures (95/188/35)");
  }
  return { files, patches: value.patchedFiles };
}

function verifyInventory(actual, files) {
  const expected = [...files.keys(), "provenance.json"].sort();
  const directories = new Set();
  for (const name of expected) {
    let directory = path.posix.dirname(name);
    while (directory !== ".") {
      directories.add(directory);
      directory = path.posix.dirname(directory);
    }
  }
  if (JSON.stringify(actual.files) !== JSON.stringify(expected)
    || JSON.stringify(actual.directories) !== JSON.stringify([...directories].sort())) {
    fail("OrderedJSON inventory mismatch: missing or unexpected file/directory");
  }
}

function verifyPatches(patches, files, contents) {
  const targets = new Set();
  const used = new Set();
  for (const item of patches) {
    keys(item, ["path", "original", "patches"]);
    safePath(item.path);
    safePath(item.original);
    if (targets.has(item.path)) fail("Duplicate patched source");
    targets.add(item.path);
    const target = files.get(item.path);
    const original = files.get(item.original);
    if (!sourcePaths.includes(item.path) || item.original !== `Upstream/${path.posix.basename(item.path)}`
      || !original || original.origin !== "orderedjson" || original.upstreamPath !== item.path
      || original.sha256 !== target?.upstreamSha256 || !Array.isArray(item.patches) || !item.patches.length) {
      fail("Invalid patch original or target");
    }
    used.add(item.original);
    let result = contents.get(item.original);
    for (const patchPath of item.patches) {
      safePath(patchPath);
      if (used.has(patchPath)) fail("Duplicate patch attribution");
      if (!patchPath.startsWith("patches/") || files.get(patchPath)?.origin !== "local") fail("Invalid patch path");
      used.add(patchPath);
      result = reconstructPatch(result, contents.get(patchPath), item.path);
    }
    if (!result.equals(contents.get(item.path))) fail(`Patch reconstruction mismatch: ${item.path}`);
  }
  for (const file of files.values()) {
    if ((file.path.startsWith("Upstream/") || file.path.startsWith("patches/")) && !used.has(file.path)) {
      fail(`Unattributed patch/original: ${file.path}`);
    }
    if (file.origin !== "local" && !targets.has(file.path) && file.sha256 !== file.upstreamSha256) {
      fail(`Upstream original hash mismatch or missing patch: ${file.path}`);
    }
  }
}

function verifyDependencyLock(data) {
  let lock;
  try { lock = JSON.parse(data); }
  catch { fail("Invalid OrderedJSON dependency lock"); }
  if (lock?.version !== 3 || !Array.isArray(lock.pins) || lock.pins.length !== 1) {
    fail("Invalid OrderedJSON dependency lock");
  }
  const pin = lock.pins[0];
  if (pin?.identity !== "swift-collections" || pin.kind !== "remoteSourceControl"
    || pin.location !== "https://github.com/apple/swift-collections.git"
    || pin.state?.version !== "1.6.0" || pin.state.revision !== "a0cb0954ecb21e4e31b0070e6ed5674e8556685a") {
    fail("Invalid OrderedJSON dependency lock: expected only swift-collections 1.6.0");
  }
}

export async function checkOrderedJSON(root = vendorRoot) {
  root = path.resolve(root);
  const actual = await inventory(root);
  let raw;
  try { raw = JSON.parse(await fs.readFile(path.join(root, "provenance.json"), "utf8")); }
  catch { fail("Cannot read OrderedJSON manifest"); }
  const { files, patches } = readManifest(raw);
  verifyInventory(actual, files);
  const contents = new Map();
  for (const file of files.values()) {
    const bytes = await fs.readFile(path.join(root, file.path));
    if (hash(bytes) !== file.sha256) fail(`OrderedJSON hash mismatch: ${file.path}`);
    contents.set(file.path, bytes);
  }
  verifyPatches(patches, files, contents);
  verifyDependencyLock(contents.get("Package.resolved"));
  return { sources: 9, upstreamTests: 3, fixtures: 318, patches: patches.reduce((count, item) => count + item.patches.length, 0) };
}

const invocationPath = process.argv[1] ? await fs.realpath(process.argv[1]).catch(() => null) : null;
if (invocationPath === fileURLToPath(import.meta.url)) {
  try {
    const result = await checkOrderedJSON();
    process.stdout.write(`OrderedJSON verified: ${result.sources} sources, ${result.upstreamTests} upstream tests, ${result.fixtures} fixtures, ${result.patches} patches\n`);
  } catch (error) {
    process.stderr.write(`OrderedJSON verification failed: ${error.message}\n`);
    process.exitCode = 1;
  }
}

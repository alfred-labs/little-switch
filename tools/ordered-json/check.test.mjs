import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { checkOrderedJSON } from "./check.mjs";

const sourceRoot = fileURLToPath(new URL("../../Vendor/OrderedJSON", import.meta.url));
const parser = "Sources/OrderedJSON/JSONValue+Parse.swift";
const digest = (data) => createHash("sha256").update(data).digest("hex");

async function withVendor(body) {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "ordered-json-check-"));
  const root = path.join(temporary, "Vendor", "OrderedJSON");
  try {
    await fs.cp(sourceRoot, root, { recursive: true });
    await body(root, temporary);
  } finally {
    await fs.rm(temporary, { recursive: true, force: true });
  }
}

async function editManifest(root, edit) {
  const location = path.join(root, "provenance.json");
  const manifest = JSON.parse(await fs.readFile(location, "utf8"));
  await edit(manifest);
  await fs.writeFile(location, `${JSON.stringify(manifest, null, 2)}\n`);
}

async function snapshot(root) {
  const result = [];
  for (const entry of await fs.readdir(root, { recursive: true, withFileTypes: true })) {
    if (entry.isFile()) {
      const location = path.join(entry.parentPath, entry.name);
      result.push([path.relative(root, location), digest(await fs.readFile(location))]);
    }
  }
  return result.sort(([left], [right]) => left.localeCompare(right));
}

test("verifies the actual pinned copy without writing to it", async () => {
  await withVendor(async (root) => {
    const before = await snapshot(root);
    await assert.doesNotReject(checkOrderedJSON(root));
    assert.deepEqual(await snapshot(root), before);
  });
});

test("rejects an upstream source edit and leaves the failed tree untouched", async () => {
  await withVendor(async (root) => {
    await fs.appendFile(path.join(root, "Sources/OrderedJSON/JSONType.swift"), "// changed\n");
    const before = await snapshot(root);
    await assert.rejects(checkOrderedJSON(root), /hash/i);
    assert.deepEqual(await snapshot(root), before);
  });
});

test("rejects a missing corpus input instead of testing a reduced corpus", async () => {
  await withVendor(async (root) => {
    const directory = path.join(root, "Tests/OrderedJSONTests/JSONTestSuite/test_parsing");
    await fs.rm(path.join(directory, (await fs.readdir(directory))[0]));
    await assert.rejects(checkOrderedJSON(root), /inventory/i);
  });
});

test("rejects extra files and empty directories", async () => {
  for (const directory of [false, true]) {
    await withVendor(async (root) => {
      const extra = path.join(root, "unexpected");
      if (directory) await fs.mkdir(extra);
      else await fs.writeFile(extra, "unowned");
      await assert.rejects(checkOrderedJSON(root), /inventory/i);
    });
  }
});

test("rejects file, directory and root symlinks before reading their targets", async () => {
  for (const kind of ["file", "directory", "root"]) {
    await withVendor(async (root, temporary) => {
      let checked = root;
      if (kind === "file") {
        const location = path.join(root, "LICENSE");
        await fs.rm(location);
        await fs.symlink(path.join(root, "README.md"), location);
      } else if (kind === "directory") {
        await fs.symlink(temporary, path.join(root, "elsewhere"));
      } else {
        checked = path.join(temporary, "linked");
        await fs.symlink(root, checked);
      }
      await assert.rejects(checkOrderedJSON(checked), /symbolic link/i);
    });
  }
});

test("rejects unsafe manifest paths and duplicate entries", async () => {
  for (const unsafe of ["../outside", "/absolute", "Sources/../outside", "Sources\\outside", ""]) {
    await withVendor(async (root) => {
      await editManifest(root, (manifest) => { manifest.files[0].path = unsafe; });
      await assert.rejects(checkOrderedJSON(root), /path/i);
    });
  }
  await withVendor(async (root) => {
    await editManifest(root, (manifest) => { manifest.files.push(manifest.files[0]); });
    await assert.rejects(checkOrderedJSON(root), /duplicate/i);
  });
});

test("rejects a changed source even if its current hash was resealed", async () => {
  await withVendor(async (root) => {
    await fs.appendFile(path.join(root, parser), "// not in the explicit patch\n");
    await editManifest(root, async (manifest) => {
      manifest.files.find((file) => file.path === parser).sha256 = digest(await fs.readFile(path.join(root, parser)));
    });
    await assert.rejects(checkOrderedJSON(root), /reconstruct/i);
  });
});

test("rejects a modified original despite a resealed current hash", async () => {
  await withVendor(async (root) => {
    const original = "Upstream/JSONValue+Parse.swift";
    await fs.appendFile(path.join(root, original), "// modified original\n");
    await editManifest(root, async (manifest) => {
      manifest.files.find((file) => file.path === original).sha256 = digest(await fs.readFile(path.join(root, original)));
    });
    await assert.rejects(checkOrderedJSON(root), /upstream|original/i);
  });
});

test("rejects a resealed patch whose context or target is invalid", async () => {
  for (const change of [
    (patch) => patch.replace("--- a/Sources/", "--- a/../Sources/"),
    (patch) => patch.replace("-        return String", "-        return Missing"),
    (patch) => patch.replace(/@@ -\d+,\d+/, "@@ -1,99999"),
  ]) {
    await withVendor(async (root) => {
      await editManifest(root, async (manifest) => {
        const patchPath = manifest.patchedFiles[0].patches[0];
        const location = path.join(root, patchPath);
        await fs.writeFile(location, change(await fs.readFile(location, "utf8")));
        manifest.files.find((file) => file.path === patchPath).sha256 = digest(await fs.readFile(location));
      });
      await assert.rejects(checkOrderedJSON(root), /patch/i);
    });
  }
});

test("rejects lost patch attribution and patches assigned more than once", async () => {
  await withVendor(async (root) => {
    await editManifest(root, (manifest) => { manifest.patchedFiles = []; });
    await assert.rejects(checkOrderedJSON(root), /patch/i);
  });
  await withVendor(async (root) => {
    await editManifest(root, (manifest) => { manifest.patchedFiles.push(manifest.patchedFiles[0]); });
    await assert.rejects(checkOrderedJSON(root), /duplicate/i);
  });
});

test("rejects malformed metadata and revision drift", async () => {
  await withVendor(async (root) => {
    await fs.writeFile(path.join(root, "provenance.json"), "{");
    await assert.rejects(checkOrderedJSON(root), /manifest/i);
  });
  for (const edit of [
    (manifest) => { manifest.upstream.revision = "other"; },
    (manifest) => { manifest.corpus.revision = "other"; },
    (manifest) => { manifest.files[0].sha256 = "not-a-hash"; },
    (manifest) => { manifest.formatVersion = 2; },
  ]) {
    await withVendor(async (root) => {
      await editManifest(root, edit);
      await assert.rejects(checkOrderedJSON(root), /manifest|hash|revision/i);
    });
  }
});

test("rejects an empty or reduced corpus even when removed entries were dropped from the manifest", async () => {
  for (const empty of [false, true]) {
    await withVendor(async (root) => {
      await editManifest(root, async (manifest) => {
        const corpus = manifest.files.filter((file) => file.path.includes("/test_parsing/"));
        const removed = empty ? corpus : corpus.slice(0, 1);
        for (const file of removed) await fs.rm(path.join(root, file.path));
        manifest.files = manifest.files.filter((file) => !removed.includes(file));
      });
      await assert.rejects(checkOrderedJSON(root), /corpus inventory/i);
    });
  }
});

test("rejects a resealed dependency lock that changes the sole exact pin", async () => {
  await withVendor(async (root) => {
    const location = path.join(root, "Package.resolved");
    const lock = JSON.parse(await fs.readFile(location, "utf8"));
    lock.pins[0].state.version = "1.7.0";
    await fs.writeFile(location, JSON.stringify(lock));
    await editManifest(root, async (manifest) => {
      manifest.files.find((file) => file.path === "Package.resolved").sha256 = digest(await fs.readFile(location));
    });
    await assert.rejects(checkOrderedJSON(root), /dependency lock/i);
  });
});

test("CLI verifies its local copy and exits nonzero on drift without writing files", async () => {
  await withVendor(async (root, temporary) => {
    const scripts = path.join(temporary, "tools", "ordered-json");
    await fs.mkdir(scripts, { recursive: true });
    for (const file of ["check.mjs", "patch.mjs"]) {
      await fs.copyFile(fileURLToPath(new URL(file, import.meta.url)), path.join(scripts, file));
    }
    const run = () => spawnSync(process.execPath, [path.join(scripts, "check.mjs")], { encoding: "utf8" });
    const success = run();
    assert.equal(success.status, 0, success.stderr);
    assert.match(success.stdout, /OrderedJSON verified/);
    await fs.appendFile(path.join(root, "LICENSE"), "unexpected\n");
    const before = await snapshot(root);
    const failed = run();
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /hash mismatch/);
    assert.deepEqual(await snapshot(root), before);
  });
});

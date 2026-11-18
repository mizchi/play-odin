import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = new URL("../", import.meta.url);
const profiles = ["minimal", "size", "no-rtti", "optimized"];

for (const profile of profiles) {
  test(`add (${profile}): exported C ABI works without host imports`, async () => {
    const bytes = readFileSync(new URL(`build/wasm/add.${profile}.wasm`, root));
    const module = await WebAssembly.compile(bytes);
    assert.deepEqual(WebAssembly.Module.imports(module), []);
    const { exports } = await WebAssembly.instantiate(module);
    for (const [a, b, expected] of [
      [20, 22, 42], [0, 0, 0], [-5, 3, -2],
      [2147483647, 1, -2147483648], [-2147483648, -1, 2147483647],
    ]) {
      assert.equal(exports.add(a, b), expected);
    }
  });

  for (const [name, expected] of [
    ["hello", "Hello, Odin!\n"], ["basics", "14\n"],
    ["hello-os", "Hello, Odin!\n"], ["hello-wasi", "Hello, Odin!\n"],
    ["hello-wasi-minimal", "Hello, Odin!\n"],
  ]) {
    // This Odin release restricts -no-rtti to freestanding targets.
    if (profile === "no-rtti" && name !== "hello-wasi-minimal") continue;
    test(`${name} (${profile}): WASI stdout preserves program behavior`, async () => {
      const path = fileURLToPath(new URL(`build/wasm/${name}.${profile}.wasm`, root));
      const module = await WebAssembly.compile(readFileSync(path));
      assert.ok(WebAssembly.Module.imports(module).every(item => item.module === "wasi_snapshot_preview1"));
      if (name === "hello-wasi-minimal") {
        assert.deepEqual(WebAssembly.Module.imports(module).map(item => item.name).sort(), ["fd_write", "proc_exit"]);
      }
      const result = spawnSync(process.env.WASMTIME ?? "wasmtime", [path], {
        encoding: "utf8", timeout: 30_000,
      });
      if (result.error) throw result.error;
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, expected);
    });
  }
}

test("direct WASI write retries short writes and exits on I/O failure", async () => {
  const module = await WebAssembly.compile(readFileSync(new URL("build/wasm/hello-wasi-minimal.optimized.wasm", root)));
  for (const failure of ["none", "errno", "no-progress"]) {
    let instance;
    let text = "";
    const exit = new Error("proc_exit");
    instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: {
        fd_write(fd, iovs, count, written) {
          assert.equal(fd, 1);
          assert.equal(count, 1);
          if (failure === "errno") return 29; // WASI EIO
          const memory = new DataView(instance.exports.memory.buffer);
          const pointer = memory.getUint32(iovs, true);
          const length = memory.getUint32(iovs + 4, true);
          const n = failure === "no-progress" ? 0 : Math.min(length, 3);
          text += new TextDecoder().decode(new Uint8Array(memory.buffer, pointer, n));
          memory.setUint32(written, n, true);
          return 0;
        },
        proc_exit(code) {
          assert.equal(code, 1);
          throw exit;
        },
      },
    });
    if (failure === "none") {
      instance.exports._start();
      assert.equal(text, "Hello, Odin!\n");
    } else {
      assert.throws(() => instance.exports._start(), error => error === exit);
    }
  }
});

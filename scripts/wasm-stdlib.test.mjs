import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import { WASI } from "node:wasi";
import test from "node:test";

const output = new URL("../build/wasm-stdlib/", import.meta.url);

test("freestanding: exported checks actually execute instead of being removed", async () => {
  const manifest = JSON.parse(readFileSync(new URL("results.json", output), "utf8"));
  assert.equal(manifest.results.find(row => row.target === "freestanding_wasm32").built, true);
  const { instance } = await WebAssembly.instantiate(readFileSync(new URL("freestanding_wasm32.wasm", output)), {});
  assert.equal(instance.exports.run_checks(3), 255);
});

test("WASI: data processing, allocation, clock, and preopened files work", async () => {
  const manifest = JSON.parse(readFileSync(new URL("results.json", output), "utf8"));
  assert.equal(manifest.results.find(row => row.target === "wasi_wasm32").built, true);
  const bytes = readFileSync(new URL("wasi_wasm32.wasm", output));
  const directory = mkdtempSync(join(tmpdir(), "play-odin-stdlib-"));
  try {
    const wasi = new WASI({ version: "preview1", args: ["stdlib"], preopens: { "/sandbox": directory }, returnOnExit: true });
    const { instance } = await WebAssembly.instantiate(bytes, wasi.getImportObject());
    assert.equal(wasi.start(instance), 0);
    assert.equal(instance.exports.get_result(), 255);
    assert.equal(instance.exports.get_platform_result(), 3);
    instance.exports._end();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("JS: data processing works with the official odin.js imports in Node", async () => {
  const manifest = JSON.parse(readFileSync(new URL("results.json", output), "utf8"));
  assert.equal(manifest.results.find(row => row.target === "js_wasm32").built, true);
  const helper = readFileSync(join(manifest.odinRoot, "core/sys/wasm/js/odin.js"), "utf8");
  const window = {};
  vm.runInNewContext(helper, { window, console, performance, crypto: globalThis.crypto, TextDecoder, TextEncoder });
  const memory = new window.odin.WasmMemoryInterface();
  const imports = window.odin.setupDefaultImports(memory);
  const { instance } = await WebAssembly.instantiate(readFileSync(new URL("js_wasm32.wasm", output)), imports);
  memory.setMemory(instance.exports.memory);
  memory.setExports(instance.exports);
  instance.exports._start();
  assert.equal(instance.exports.get_result(), 255);
  assert.equal(instance.exports.get_platform_result(), 2);
  instance.exports._end();
});

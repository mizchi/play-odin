import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../build/wasm/", import.meta.url);
const profiles = ["minimal", "size", "no-rtti", "optimized"];

async function load(name, profile, functions) {
  const module = await WebAssembly.compile(readFileSync(new URL(`${name}.${profile}.wasm`, root)));
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  assert.deepEqual(WebAssembly.Module.exports(module).filter(item => item.kind === "function").map(item => item.name).sort(), functions.toSorted());
  return (await WebAssembly.instantiate(module)).exports;
}

for (const profile of profiles) {
  test(`bit_set (${profile}): flags match integer masks including unknown bits`, async () => {
    for (const name of ["bit-set", "bit-set-manual"]) {
      const api = await load(name, profile, ["update", "has_execute"]);
      const values = [0, 1, 4, 7, 31, 255, 0x80000000, 0xffffffff];
      for (const initial of values) {
        for (const grant of values) {
          for (const revoke of values) {
            const expected = ((initial | grant) & ~revoke) >>> 0;
            assert.equal(api.update(initial, grant, revoke) >>> 0, expected, name);
            assert.equal(api.has_execute(expected), (expected & 4) !== 0 ? 1 : 0, name);
          }
        }
      }
    }
  });

  test(`bit_field (${profile}): packing truncates and signed fields extend correctly`, async () => {
    for (const name of ["bit-field", "bit-field-manual"]) {
      const api = await load(name, profile, ["pack", "payload", "delta"]);
      for (const [kind, compressed, payload, delta] of [
        [1, 1, 512, -1], [0, 0, 0, 0], [7, 0, 4095, 127],
        [9, 2, 4096, 128], [0xffffffff, 0xffffffff, 0xffffffff, -129],
      ]) {
        const expected = ((kind & 7) | ((compressed !== 0 ? 1 : 0) << 3) | ((payload & 4095) << 4) | ((delta & 255) << 16)) >>> 0;
        assert.equal(api.pack(kind, compressed, payload, delta) >>> 0, expected, name);
      }
      for (let byte = 0; byte <= 255; byte++) {
        const raw = (0xff00000f | (byte << 16) | (byte << 4)) >>> 0;
        assert.equal(api.payload(raw), byte, name);
        assert.equal(api.delta(raw), byte < 128 ? byte : byte - 256, name);
      }
    }
  });

  test(`defer (${profile}): cleanup survives both returns and reads the late value`, async () => {
    for (const name of ["defer", "defer-manual"]) {
      const api = await load(name, profile, ["evaluate", "read_state"]);
      for (const input of [0, 1, 9, -1, 2147483647, -2147483648]) {
        for (const stop of [0, 1, 42]) {
          assert.equal(api.evaluate(input, stop), (input + (stop ? 10 : 20)) | 0, name);
          assert.equal(api.read_state(), (input + (stop ? 20 : 340)) | 0, name);
        }
      }
    }
  });
}

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../build/wasm/", import.meta.url);
const names = ["async-state", "async-callback"];

async function load(name, profile, schedule) {
  const module = await WebAssembly.compile(readFileSync(new URL(`${name}.${profile}.wasm`, root)));
  assert.deepEqual(WebAssembly.Module.imports(module), [{ module: "host", name: "request", kind: "function" }]);
  assert.deepEqual(WebAssembly.Module.exports(module).filter(item => item.kind === "function").map(item => item.name).sort(), ["begin", "cancel", "complete", "result", "status"]);
  const requests = [];
  const { exports: api } = await WebAssembly.instantiate(module, { host: {
    request(step, ticket, value) {
      const request = { step, ticket: ticket >>> 0, value };
      requests.push(request);
      schedule?.(request, () => api.complete(ticket, step, step === 0 ? (value + 1) | 0 : (value * 2) | 0, 0));
    },
  } });
  return { api, requests };
}

for (const profile of ["minimal", "size", "no-rtti", "optimized"]) {
  test(`async (${profile}): both implementations suspend twice and reject duplicate completions`, async () => {
    for (const name of names) {
      const { api, requests } = await load(name, profile);
      assert.equal(api.status(), 0);
      const ticket = api.begin(20) >>> 0;
      assert.equal(api.status(), 1);
      assert.equal(api.result(), 0);
      assert.deepEqual(requests, [{ step: 0, ticket, value: 20 }]);
      api.complete(ticket, 1, 99, 0); // Out-of-order delivery.
      assert.equal(api.status(), 1);
      api.complete(ticket, 0, 21, 0);
      assert.equal(api.status(), 2);
      assert.deepEqual(requests[1], { step: 1, ticket, value: 21 });
      api.complete(ticket, 0, 100, 0); // Duplicate first completion.
      assert.equal(requests.length, 2);
      api.complete(ticket, 1, 42, 0);
      assert.equal(api.status(), 3);
      assert.equal(api.result(), 42);
      api.complete(ticket, 1, 99, 0);
      assert.equal(api.result(), 42);
    }
  });

  test(`async (${profile}): cancellation, replacement, and errors stop later work`, async () => {
    for (const name of names) {
      const { api, requests } = await load(name, profile);
      const old = api.begin(10);
      api.cancel();
      api.complete(old, 0, 11, 0);
      assert.equal(api.status(), 5);
      assert.equal(requests.length, 1);
      const current = api.begin(30);
      api.complete(old, 0, 11, 0);
      assert.equal(api.status(), 1);
      api.complete(current, 0, 0, 7);
      assert.equal(api.status(), 4);
      assert.equal(requests.length, 2);
      const first = api.begin(40);
      const second = api.begin(50);
      api.complete(first, 0, 41, 0);
      assert.equal(api.status(), 1);
      api.complete(second, 0, 51, 0);
      api.complete(second, 1, 0, 7);
      assert.equal(api.status(), 4);
      assert.equal(requests.length, 5);
    }
  });

  test(`async (${profile}): JS promises complete work after begin has returned`, async () => {
    for (const name of names) {
      for (const input of [20, -1, 2147483647]) {
        const { api, requests } = await load(name, profile, (_, complete) => { Promise.resolve().then(complete); });
        api.begin(input);
        assert.equal(api.status(), 1);
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(api.status(), 3);
        assert.equal(api.result(), Math.imul((input + 1) | 0, 2));
        assert.equal(requests.length, 2);
      }
    }
  });
}

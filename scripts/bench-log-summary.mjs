import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { closeSync, openSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const output = fileURLToPath(new URL("../build/log-summary/", import.meta.url));
const inputPath = join(output, "benchmark.jsonl");
const repeats = 100_000;
const records = [
  { level: "info", duration_ms: 12, message: "completed" },
  { level: "warn", duration_ms: 8, labels: { stage: "commit" } },
  { level: "error", duration_ms: 30, retry: false },
];
const expected = {
  valid: 3 * repeats, invalid: 0, info: repeats, warn: repeats, error: repeats,
  total_ms: 50 * repeats, max_ms: 30,
};
const fixture = records.map(record => JSON.stringify(record) + "\n").join("").repeat(repeats);
writeFileSync(inputPath, fixture);
const wasmtime = process.env.WASMTIME ?? "wasmtime";
const cases = [
  ...["minimal", "size", "speed"].map(profile => [`native-${profile}`, join(output, `native-${profile}`), []]),
  ...["minimal", "size", "speed", "size-fmt", "size-optimized"].map(profile =>
    [`wasi-${profile}`, wasmtime, ["run", join(output, `wasi-${profile}.wasm`)]],
  ),
];

function sample(command, args) {
  const input = openSync(inputPath, "r");
  try {
    const start = performance.now();
    const result = spawnSync(command, args, { stdio: [input, "pipe", "pipe"], encoding: "utf8", timeout: 60_000 });
    const ms = performance.now() - start;
    if (result.error) throw result.error;
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), expected);
    return ms;
  } finally {
    closeSync(input);
  }
}

const results = cases.map(([name, command, args]) => {
  sample(command, args); // Warm the executable, data and Wasmtime cache.
  const samples_ms = Array.from({ length: 5 }, () => sample(command, args));
  const median_ms = samples_ms.toSorted((a, b) => a - b)[2];
  return { name, median_ms, samples_ms };
});
writeFileSync(join(output, "bench.json"), JSON.stringify({
  inputBytes: Buffer.byteLength(fixture), records: 3 * repeats, warmup: 1, results,
}, null, 2) + "\n");
console.table(results.map(({ name, median_ms }) => ({ name, median_ms: median_ms.toFixed(1) })));

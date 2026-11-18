import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { closeSync, mkdtempSync, openSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const path = name => fileURLToPath(new URL(`../build/log-summary/${name}`, import.meta.url));
const programs = [
  ["native", path("log-summary"), []],
  ["WASI", process.env.WASMTIME ?? "wasmtime", ["run", path("log-summary.wasm")]],
];
if (process.env.LOG_SUMMARY_COMPARE === "1") {
  programs.push(["WASI fmt", process.env.WASMTIME ?? "wasmtime", ["run", path("wasi-size-fmt.wasm")]]);
  programs.push(["WASI wasm-opt", process.env.WASMTIME ?? "wasmtime", ["run", path("wasi-size-optimized.wasm")]]);
}

for (const [name, command, args] of programs) {
  function run(input, extra = []) {
    const result = spawnSync(command, [...args, ...extra], { input, encoding: "utf8", timeout: 15_000 });
    if (result.error) throw result.error;
    return result;
  }

  function run_file(input) {
    const directory = mkdtempSync(join(tmpdir(), "odin-log-summary-"));
    try {
      const file = join(directory, "events.jsonl");
      writeFileSync(file, input);
      const fd = openSync(file, "r");
      try {
        const result = spawnSync(command, args, { stdio: [fd, "pipe", "pipe"], encoding: "utf8", timeout: 15_000 });
        if (result.error) throw result.error;
        return result;
      } finally {
        closeSync(fd);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }

  test(`${name}: streams JSONL, rejects invalid records, and accepts final line without LF`, () => {
    const input = [
      '{"level":"info","duration_ms":12,"ignored":{"tag":"x"}}\r',
      "",
      " \t",
      '{"level":"warn","duration_ms":0}',
      '{"level":"error","duration_ms":30}',
      '{"level":"debug","duration_ms":2}',
      '{"level":"warn","duration_ms":-1}',
      '{"level":"warn","duration_ms":1.5}',
      '{"level":"warn","duration_ms":4294967296}',
      '{"level":"warn","duration_ms":18446744073709551616}',
      '{"level":"warn","duration_ms":"1"}',
      '{"level":"warn","duration_ms":1.0}',
      '{"level":"warn"}',
      '{"level":"warn","duration_ms":null}',
      '{"level":"warn","duration_ms":1,"duration_ms":2}',
      '{level:"info",duration_ms:1}',
      '{"level":"info","duration_ms":1} {}',
      '{"level":"info","duration_ms":1}\0',
      '{"level":"info","duration_ms":1} garbage',
      '{"level":"info","duration_ms":1,,}',
      '{"level":"info","duration_ms":1,}',
      '{"level":"info",\v"duration_ms":1}',
      '{"level":"info","duration_ms":1,',
      '{"level":"info","duration_ms":1,"x":' + "[".repeat(100) + "0" + "]".repeat(100) + "}",
      '{"level":"\\u0069nfo","duration_ms":4294967295}',
    ].join("\n");
    const result = run(input);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, "");
    assert.deepEqual(JSON.parse(result.stdout), {
      valid: 4, invalid: 19, info: 2, warn: 1, error: 1,
      total_ms: 4294967337, max_ms: 4294967295,
    });
  });

  test(`${name}: handles oversized lines and resets at the next record`, () => {
    const record = '{"level":"info","duration_ms":1}';
    const boundary = record.padEnd(65536);
    const input = `${record.padEnd(200000)}\n${boundary}\n${record}\n${boundary} `;
    const result = run_file(input);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), {
      valid: 2, invalid: 2, info: 2, warn: 0, error: 0, total_ms: 2, max_ms: 1,
    });
    const final = run_file(boundary);
    assert.equal(final.status, 0, final.stderr);
    assert.equal(JSON.parse(final.stdout).valid, 1);
  });

  test(`${name}: empty stream and CLI argument contract`, () => {
    const empty = run("");
    assert.equal(empty.status, 0, empty.stderr);
    assert.deepEqual(JSON.parse(empty.stdout), {
      valid: 0, invalid: 0, info: 0, warn: 0, error: 0, total_ms: 0, max_ms: 0,
    });
    const help = run("", ["--help"]);
    assert.equal(help.status, 0, help.stderr);
    assert.match(help.stdout, /Usage: log-summary/);
    const unknown = run("", ["--unknown"]);
    assert.equal(unknown.status, 2, unknown.stderr);
    assert.equal(unknown.stdout, "");
    assert.match(unknown.stderr, /Usage: log-summary/);
  });
}

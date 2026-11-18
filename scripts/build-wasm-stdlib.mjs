import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = join(root, "build/wasm-stdlib");
const odin = process.env.ODIN ?? "odin";
const env = { ...process.env };
mkdirSync(output, { recursive: true });
function run(args) {
  const result = spawnSync(odin, args, { cwd: root, env, encoding: "utf8", timeout: 60_000 });
  if (result.error) throw result.error;
  return result;
}
const version = run(["version"]);
const location = run(["root"]);
if (version.status !== 0 || location.status !== 0) throw new Error("Cannot inspect Odin toolchain");
const linker = spawnSync("wasm-ld", ["--version"], { env });
if (linker.error?.code === "ENOENT" && process.platform !== "win32") {
  const tools = join(output, ".tools");
  mkdirSync(tools, { recursive: true });
  writeFileSync(join(tools, "wasm-ld"), '#!/bin/sh\nexec "${ZIG:-zig}" wasm-ld "$@"\n', { mode: 0o755 });
  env.PATH = `${tools}${delimiter}${env.PATH ?? ""}`;
}
const results = [];
for (const target of ["wasi_wasm32", "js_wasm32", "freestanding_wasm32"]) {
  const file = `${target}.wasm`;
  const args = ["build", "examples/wasm/stdlib", `-target:${target}`, "-o:size", "-vet", `-out:${join(output, file)}`];
  const result = run(args);
  const row = { target, file, command: [odin, ...args], built: result.status === 0, exitCode: result.status, signal: result.signal, diagnostic: result.stdout + result.stderr };
  if (row.built) {
    const bytes = readFileSync(join(output, file));
    const module = await WebAssembly.compile(bytes);
    row.bytes = bytes.length;
    row.imports = WebAssembly.Module.imports(module);
  }
  results.push(row);
  console.log(`${target}: ${row.built ? `built, ${row.bytes} B` : "unavailable; diagnostic saved"}`);
}
writeFileSync(join(output, "results.json"), `${JSON.stringify({ version: version.stdout.trim(), odinRoot: location.stdout.trim(), results }, null, 2)}\n`);
if (results.some(row => !row.built)) {
  for (const row of results.filter(row => !row.built)) console.error(row.diagnostic);
  process.exitCode = 1;
}

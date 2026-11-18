import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = join(root, "build/log-summary");
const odin = process.env.ODIN ?? "odin";
const wasmOpt = process.env.WASM_OPT ?? "wasm-opt";
const env = { ...process.env };
const mode = process.argv[2];
mkdirSync(output, { recursive: true });

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, env, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")}\n${result.stdout}${result.stderr}`);
  return result.stdout.trim();
}

if (!["native", "wasi", "compare"].includes(mode)) {
  throw new Error("Expected native, wasi, or compare");
}

if (mode !== "native") {
  const linker = spawnSync("wasm-ld", ["--version"], { env });
  if (linker.error?.code === "ENOENT" && process.platform !== "win32") {
    run(process.env.ZIG ?? "zig", ["wasm-ld", "--version"]);
    const bin = join(output, ".tools");
    mkdirSync(bin, { recursive: true });
    writeFileSync(join(bin, "wasm-ld"), '#!/bin/sh\nexec "${ZIG:-zig}" wasm-ld "$@"\n', { mode: 0o755 });
    env.PATH = `${bin}${delimiter}${env.PATH ?? ""}`;
  }
}

function build(file, profile, target = [], extra = []) {
  run(odin, ["build", "examples/log-summary", "-vet", `-o:${profile}`,
    ...target, ...extra, `-out:${join(output, file)}`]);
}

const wasi = ["-target:wasi_wasm32"];
if (mode === "native") build("log-summary", "speed");
if (mode === "wasi") build("log-summary.wasm", "size", wasi);
if (mode === "compare") {
  const profiles = ["minimal", "size", "speed"];
  const files = [];
  for (const profile of profiles) {
    build(`native-${profile}`, profile);
    const file = `wasi-${profile}.wasm`;
    build(file, profile, wasi);
    files.push(file);
  }

  const fmt = "wasi-size-fmt.wasm";
  build(fmt, "size", wasi, ["-define:LOG_SUMMARY_USE_FMT=true"]);
  const optimized = "wasi-size-optimized.wasm";
  run(wasmOpt, ["-Oz", "--strip-debug", "--strip-producers",
    join(output, "wasi-size.wasm"), "-o", join(output, optimized)]);
  files.push(fmt, optimized);

  const results = files.map(file => {
    const bytes = readFileSync(join(output, file));
    const brotli = brotliCompressSync(bytes, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } });
    return { file, bytes: bytes.length, gzip: gzipSync(bytes, { level: 9 }).length, brotli: brotli.length };
  });
  const tools = { odin: run(odin, ["version"]), linker: run("wasm-ld", ["--version"]), wasmOpt: run(wasmOpt, ["--version"]) };
  writeFileSync(join(output, "sizes.json"), JSON.stringify({ tools, results }, null, 2) + "\n");
  console.table(results);
}

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = join(root, "build/wasm");
const odin = process.env.ODIN ?? "odin";
const wasmOpt = process.env.WASM_OPT ?? "wasm-opt";
const env = { ...process.env };

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, env, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout}${result.stderr}`);
  }
  return result.stdout.trim();
}

mkdirSync(output, { recursive: true });
// Odin invokes wasm-ld by name. Zig bundles the same linker, so it can supply
// the executable without changing the user's global PATH or installing LLVM.
const linker = spawnSync("wasm-ld", ["--version"], { env, encoding: "utf8" });
let linkerProvider = "wasm-ld";
if (linker.error?.code === "ENOENT" && process.platform !== "win32") {
  run(process.env.ZIG ?? "zig", ["wasm-ld", "--version"]);
  const tools = join(output, ".tools");
  mkdirSync(tools, { recursive: true });
  writeFileSync(join(tools, "wasm-ld"), '#!/bin/sh\nexec "${ZIG:-zig}" wasm-ld "$@"\n', { mode: 0o755 });
  env.PATH = `${tools}${delimiter}${env.PATH ?? ""}`;
  linkerProvider = "zig wasm-ld";
}

const versions = {
  odin: run(odin, ["version"]),
  linker: run("wasm-ld", ["--version"]),
  linkerProvider,
  wasmOpt: run(wasmOpt, ["--version"]),
  node: process.version,
};
const cases = [
  { name: "add", source: "examples/wasm/add", target: "freestanding_wasm32", flags: ["-no-entry-point"] },
  { name: "hello", source: "examples/wasm/hello", target: "wasi_wasm32", flags: [] },
  { name: "basics", source: "examples/basics", target: "wasi_wasm32", flags: [] },
  { name: "hello-os", source: "examples/wasm/hello-os", target: "wasi_wasm32", flags: [] },
  { name: "hello-wasi", source: "examples/wasm/direct-write", target: "wasi_wasm32", flags: [] },
  { name: "hello-wasi-minimal", source: "examples/wasm/direct-write", target: "freestanding_wasm32", flags: ["-no-entry-point"] },
  { name: "async-state", source: "examples/wasm/async-host", target: "freestanding_wasm32", flags: ["-no-entry-point"] },
  { name: "async-callback", source: "examples/wasm/async-host", target: "freestanding_wasm32", flags: ["-no-entry-point", "-define:USE_CALLBACKS=true"] },
  ...["bit-set", "bit-field", "defer"].flatMap(name => [
    { name, source: `examples/wasm/features/${name}`, target: "freestanding_wasm32", flags: ["-no-entry-point"] },
    { name: `${name}-manual`, source: `examples/wasm/features/${name}`, target: "freestanding_wasm32", flags: ["-no-entry-point", "-define:USE_FEATURE=false"] },
  ]),
];
const profiles = [
  { name: "minimal", flags: ["-o:minimal"] },
  { name: "size", flags: ["-o:size"] },
  { name: "no-rtti", flags: ["-o:size", "-no-rtti"] },
];
const results = [];
const commands = [];

for (const sample of cases) {
  for (const profile of [...profiles, { name: "optimized" }]) {
    if (profile.name === "no-rtti" && sample.target !== "freestanding_wasm32") continue;
    const file = `${sample.name}.${profile.name}.wasm`;
    const path = join(output, file);
    const optimizeFrom = sample.target === "freestanding_wasm32" ? "no-rtti" : "size";
    const command = profile.name === "optimized"
      ? [wasmOpt, join(output, `${sample.name}.${optimizeFrom}.wasm`), "-Oz", "--strip-debug", "--strip-producers", "-o", path]
      : [odin, "build", sample.source, `-target:${sample.target}`, ...sample.flags, ...profile.flags, "-vet", `-out:${path}`];
    console.log(`Building ${file}`);
    run(command[0], command.slice(1));
    commands.push(command);
    const bytes = readFileSync(path);
    const module = await WebAssembly.compile(bytes);
    const gzip = gzipSync(bytes, { level: 9 });
    const brotli = brotliCompressSync(bytes, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } });
    writeFileSync(`${path}.gz`, gzip);
    writeFileSync(`${path}.br`, brotli);
    results.push({
      sample: sample.name, target: sample.target, profile: profile.name, file,
      bytes: bytes.length, gzip: gzip.length, brotli: brotli.length,
      imports: WebAssembly.Module.imports(module),
    });
  }
}

const comparisons = ["bit-set", "bit-field", "defer"].flatMap(feature =>
  [...profiles.map(profile => profile.name), "optimized"].map(profile => {
    const featureFile = `${feature}.${profile}.wasm`;
    const manualFile = `${feature}-manual.${profile}.wasm`;
    const generated = readFileSync(join(output, featureFile));
    const manual = readFileSync(join(output, manualFile));
    return {
      feature, profile, featureFile, manualFile,
      featureBytes: generated.length, manualBytes: manual.length,
      delta: generated.length - manual.length,
      byteIdentical: generated.equals(manual),
    };
  }),
);

// A capability probe is kept separate from the runnable size samples. This
// compiler's nbio fallback currently fails type checking on WASI; never report
// an unavailable implementation as a zero-byte async runtime.
const probeArgs = ["check", "examples/wasm/nbio-next-tick", "-target:wasi_wasm32", "-vet"];
const probe = spawnSync(odin, probeArgs, { cwd: root, env, encoding: "utf8" });
if (probe.error) throw probe.error;
const availability = [{
  sample: "nbio-next-tick", target: "wasi_wasm32", command: [odin, ...probeArgs],
  checkPassed: probe.status === 0, diagnostic: probe.stdout + probe.stderr,
}];

// Publish a report only after every size sample has built and validated.
const report = { versions, commands, results, comparisons, availability };
writeFileSync(join(output, "results.json"), `${JSON.stringify(report, null, 2)}\n`);
const table = [
  "| Sample | Target | Profile | Wasm (B) | gzip -9 (B) | Brotli 11 (B) |",
  "| --- | --- | --- | ---: | ---: | ---: |",
  ...results.map(row => `| ${row.sample} | ${row.target} | ${row.profile} | ${row.bytes} | ${row.gzip} | ${row.brotli} |`),
].join("\n");
writeFileSync(join(output, "results.md"), `${table}\n`);
const featureTable = [
  "| Feature | Profile | Feature (B) | Manual (B) | Delta (B) | Byte-identical |",
  "| --- | --- | ---: | ---: | ---: | --- |",
  ...comparisons.map(row => `| ${row.feature} | ${row.profile} | ${row.featureBytes} | ${row.manualBytes} | ${row.delta} | ${row.byteIdentical} |`),
].join("\n");
writeFileSync(join(output, "features.md"), `${featureTable}\n`);
console.log(`\n${table}\n\n${featureTable}\n\nReports: build/wasm/results.{json,md}, build/wasm/features.md`);
console.log(`nbio WASI type check: ${availability[0].checkPassed ? "passed (not sized)" : "unavailable; diagnostic saved in results.json"}`);

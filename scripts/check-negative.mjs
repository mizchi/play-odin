import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import process from "node:process";

const root = fileURLToPath(new URL("../", import.meta.url));
const cases = [
  ["unnamed-return", "requires that the return values are named"],
  ["distinct-assignment", "Cannot assign value 'raw'"],
  ["captured-local", "Undeclared name: value"],
  ["deferred-return", "Assignments to named return values within 'defer'"],
];
for (const [name, diagnostic] of cases) {
  const result = spawnSync(process.env.ODIN ?? "odin", ["check", `examples/compile-errors/${name}`], {
    cwd: root, encoding: "utf8",
  });
  if (result.error) throw result.error;
  const output = result.stdout + result.stderr;
  if (result.status === 0 || !output.includes(diagnostic)) {
    throw new Error(`Unexpected compiler result for ${name}:\n${output}`);
  }
  console.log(`Expected rejection: ${name}`);
}

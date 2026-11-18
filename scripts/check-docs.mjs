import { accessSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const write = process.argv.includes("--write");
let count = 0;
for (const file of [
  "docs/odin-blog.md", "docs/practices.md", "docs/wasm-size.md", "docs/wasm-support.md",
  "docs/log-summary.md", "docs/odin-issues.md", "README.md",
  "skills/odin-practice/SKILL.md", "skills/odin-practice/references/pitfalls.md", "skills/odin-practice/references/wasm.md",
  "skills/odin-practice/references/toolchain.md",
]) {
  const target = new URL(file, root);
  const original = readFileSync(target, "utf8");
  const generated = original.replace(
    /<!-- snippet: ([\w/.-]+)#([\w-]+) -->\n```odin\n[\s\S]*?\n```\n<!-- \/snippet -->/g,
    (block, sourcePath, name) => {
      const source = readFileSync(new URL(sourcePath, root), "utf8");
      const startMarker = `// snippet: ${name}\n`;
      const endMarker = `// endsnippet: ${name}`;
      const start = source.indexOf(startMarker);
      const end = source.indexOf(endMarker, start);
      if (start < 0 || end < 0) throw new Error(`Missing snippet: ${sourcePath}#${name}`);
      const lines = source.slice(start + startMarker.length, end).trimEnd().split("\n");
      const indent = Math.min(...lines.filter(line => line.trim()).map(line => line.match(/^\s*/)[0].length));
      const code = lines.map(line => line.slice(indent)).join("\n");
      count++;
      return `<!-- snippet: ${sourcePath}#${name} -->\n\`\`\`odin\n${code}\n\`\`\`\n<!-- /snippet -->`;
    },
  );
  if (generated !== original) {
    if (write) writeFileSync(target, generated);
    else throw new Error(`${file}: snippet differs from source; run node scripts/check-docs.mjs --write`);
  }
  const localLinks = [...generated.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)]
    .map(match => match[1]).filter(link => !/^(https?:|#)/.test(link));
  for (const link of localLinks) accessSync(new URL(link.split("#")[0], target));
  console.log(`Checked ${fileURLToPath(target)}`);
}
if (!count) throw new Error("No source snippets found");
console.log(`Verified ${count} source snippets and local links`);

// Turns `eslint --format json` output into a markdown table.
//
// Why a script instead of inline `node -e`: a shell-quoted JavaScript program
// containing `:` and `{` inside a YAML `run:` block is a quoting trap that will
// bite you. A file has none of those problems, and it is testable locally.
//
// Usage: npx eslint . --format json > /tmp/lint.json && node scripts/lint-summary.mjs /tmp/lint.json
import { readFileSync } from 'node:fs';

const path = process.argv[2];
if (!path) {
  console.error('usage: node scripts/lint-summary.mjs <eslint-json-file>');
  process.exit(2);
}

const results = JSON.parse(readFileSync(path, 'utf8'));

// Strip the absolute path so the table is short and stable across runners.
const rel = (p) => p.replace(`${process.cwd()}/`, '');

const rows = results.map((r) => ({
  file: rel(r.filePath),
  errors: r.errorCount,
  warnings: r.warningCount,
}));

const width = Math.max(4, ...rows.map((r) => r.file.length));

let out = `| ${'file'.padEnd(width)} | errors | warnings |\n`;
out += `| ${'-'.repeat(width)} | -----: | -------: |\n`;
for (const r of rows) {
  out += `| ${r.file.padEnd(width)} | ${String(r.errors).padStart(6)} | ${String(r.warnings).padStart(8)} |\n`;
}

const totalErrors = rows.reduce((t, r) => t + r.errors, 0);
const totalWarnings = rows.reduce((t, r) => t + r.warnings, 0);
out += `\n**Total: ${totalErrors} error(s), ${totalWarnings} warning(s)**\n`;

console.log(out);

// Exit 0 always: this script reports, it does not decide. The lint step's own
// exit code is the verdict. Conflating the two is how a pipeline ends up green
// after a lint failure.
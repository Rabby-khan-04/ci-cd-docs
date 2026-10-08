// Turns `eslint --format json` output into GitHub Actions workflow commands,
// so lint problems appear as annotations next to the offending lines in the
// pull request diff instead of only in a log nobody scrolls to.
//
// Usage: npx eslint . --format json > /tmp/lint.json || true
//        node scripts/lint-annotations.mjs /tmp/lint.json
//
// Why not `eslint-formatter-github`? It is a real package, but it uploads results
// through a GitHub App using a hard-coded application id and key rather than
// emitting workflow commands. Inside Actions you want workflow commands: no
// extra account, no network call, no credentials. This script is about 30 lines
// and has no dependencies.
//
// Severity 1 = warning, 2 = error. Anything else is treated as a warning.
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/lint-annotations.mjs <eslint-json-file>');
  process.exit(2);
}

const results = JSON.parse(readFileSync(file, 'utf8'));

// Repo-relative paths. Absolute runner paths would be meaningless in the diff.
const root = `${process.cwd()}/`;
const rel = (p) => p.startsWith(root) ? p.slice(root.length) : p;

// Workflow commands are newline-separated, so a newline in a message would
// truncate it and let the rest be read as another command. Escape defensively.
const escape = (s) => String(s)
  .replace(/\r/g, '%0D')
  .replace(/\n/g, '%0A')
  // `::` starts a new command; escaping the colons stops message injection.
  .replace(/::/g, '%3A%3A')
  // Commas separate the properties, so one inside a value would shift them.
  .replace(/,/g, '%2C');

let errors = 0;
let warnings = 0;

for (const r of results) {
  for (const m of r.messages ?? []) {
    const level = m.severity === 2 ? 'error' : 'warning';
    if (level === 'error') errors += 1;
    else warnings += 1;

    const props = [
      `file=${escape(rel(r.filePath))}`,
      `line=${m.line ?? 1}`,
      `col=${m.column ?? 1}`,
      `title=${escape(m.ruleId ?? 'eslint')}`,
    ].join(',');

    console.log(`::${level} ${props}::${escape(m.message)}`);
  }
}

console.log(`::notice title=Lint summary::${errors} error(s), ${warnings} warning(s)`);

// Always exit 0. This step reports; the lint step's own exit code is the
// verdict. Deciding here as well would make a red lint look green.
// The build step: bundle src/ into dist/ with esbuild.
// Keeping it in plain JS means no extra config file to explain.
import { build } from 'esbuild';
import { rm } from 'node:fs/promises';

const outdir = 'dist';

// Clean first so removed source files never linger in the output.
await rm(outdir, { recursive: true, force: true });

const result = await build({
  entryPoints: ['src/app.js'],
  outfile: `${outdir}/app.js`,
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node22',
  minify: true,
  sourcemap: true,
  metafile: true,
});

// Print the real output size so build logs show something useful.
const bytes = Object.values(result.metafile.outputs).reduce((t, f) => t + f.bytes, 0);
console.log(`built dist/app.js (${bytes} bytes)`);
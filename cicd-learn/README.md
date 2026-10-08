# cicd-learn

A deliberately small Node.js app used as the running example for every chapter of
this CI/CD course.

It has four things a real project has, so the pipeline has something real to do:

| npm script     | What it does                                  |
| -------------- | --------------------------------------------- |
| `npm run lint` | ESLint over `src/` and `build.mjs`            |
| `npm test`     | Vitest unit tests (13 tests, 2 files)         |
| `npm run coverage` | Same tests with a V8 coverage report       |
| `npm run build`  | esbuild bundles `src/app.js` into `dist/`   |

## Run it locally

```bash
npm ci          # install exactly what package-lock.json pins
npm run lint
npm test
npm run coverage
npm run build
npm start -- Ada
```

`npm start -- Ada` prints:

```json
{
  "message": "HELLO, ADA!",
  "total": 10,
  "mean": 2.5
}
```

## Layout

```
src/greet.js     pure functions: greet, shout, slugify, add
src/sum.js       pure functions: sum, average
src/app.js       entry point, exports report()
build.mjs        the build step (esbuild -> dist/app.js)
test/            Vitest tests, one file per source file
eslint.config.js flat ESLint config
vitest.config.js test include + coverage thresholds (90% lines)
```

## Why `npm ci` and not `npm install`

`npm ci` installs the exact versions in `package-lock.json` and fails if
`package.json` and the lock file disagree. `npm install` is free to update the
lock file. In CI you want the locked, reproducible result, so every workflow in
this course uses `npm ci`.
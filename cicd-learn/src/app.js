// The app entry point. The build step bundles this into dist/app.js.
import { greet, shout } from './greet.js';
import { sum, average } from './sum.js';

export function report(name = 'world', values = [1, 2, 3, 4]) {
  return {
    message: shout(greet(name)),
    total: sum(...values),
    mean: average(...values),
  };
}

// Only print when executed directly, so importing it in tests stays silent.
if (process.argv[1] && process.argv[1].endsWith('app.js')) {
  console.log(JSON.stringify(report(process.argv[2] ?? 'world'), null, 2));
}
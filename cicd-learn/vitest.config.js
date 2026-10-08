import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.js'],
    // Report only on the source we actually test, not on the config files.
    coverage: {
      provider: 'v8',
      include: ['src/**/*.js'],
      reporter: ['text', 'json', 'html'],
      // Fail the pipeline if total line coverage drops below this.
      thresholds: {
        lines: 90,
      },
    },
  },
});
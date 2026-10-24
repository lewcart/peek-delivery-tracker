import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    alias: {
      'server-only': fileURLToPath(new URL('./src/test/serverOnly.ts', import.meta.url)),
    },
  },
  test: {
    include: ['src/server/**/*.test.ts'],
    environment: 'node',
    // A run took every core of the shared machine beside other projects' suites. Four is the scraper's
    // cap, and as many as a CI runner has.
    maxWorkers: 4,
    testTimeout: 10_000,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json-summary', 'html'],
      reportsDirectory: 'coverage/server',
      include: ['src/server/**/*.ts'],
      exclude: [
        'src/server/**/*.test.ts',
        'src/server/types.ts',
      ],
      thresholds: {
        statements: 85,
        branches: 80,
        functions: 85,
        lines: 85,
      },
    },
  },
});

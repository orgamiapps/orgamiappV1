const {defineConfig, devices} = require('@playwright/test');
module.exports = defineConfig({
  testDir: '.', testMatch: '*.spec.cjs', fullyParallel: false, workers: 1,
  timeout: 300000, expect: {timeout: 20000}, retries: 0,
  reporter: [['list'], ['json', {outputFile: 'test-results/results.json'}]],
  globalTeardown: require.resolve('./cleanup.cjs'),
  use: {baseURL: 'http://127.0.0.1:4173', trace: 'retain-on-failure', screenshot: 'only-on-failure'},
  webServer: {command: 'node server.cjs', url: 'http://127.0.0.1:4173/__health',
    reuseExistingServer: false, timeout: 60000},
  projects: [
    {name: 'chromium', use: {...devices['Desktop Chrome']}},
    {name: 'firefox', use: {...devices['Desktop Firefox']}},
    {name: 'webkit', use: {...devices['Desktop Safari']}},
    {name: 'mobile-chromium', use: {...devices['Pixel 7']}},
    ...(process.env.ATTENDUS_TEST_EDGE === '1' ? [{name: 'edge', use: {...devices['Desktop Edge'], channel: 'msedge'}}] : []),
  ],
});

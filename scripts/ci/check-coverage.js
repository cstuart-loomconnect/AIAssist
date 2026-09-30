// Usage: node scripts/ci/check-coverage.js <test-results-dir> <min-percent>
// Reads the JSON written by `sf apex run test --result-format json` and fails below the threshold.
const fs = require('fs');
const path = require('path');

const [dir = 'test-results', min = '75'] = process.argv.slice(2);
const file = fs.readdirSync(dir).find((f) => /^test-result-\d+\.json$/.test(f) || f === 'test-result.json');
if (!file) {
    console.error(`No test result JSON found in ${dir}`);
    process.exit(1);
}
const { summary } = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
const coverage = parseInt(String(summary.orgWideCoverage).replace('%', ''), 10);
console.log(`Tests: ${summary.passing} passing, ${summary.failing} failing. Org-wide coverage: ${coverage}%`);
if (Number(summary.failing) > 0) process.exit(1);
if (Number.isNaN(coverage) || coverage < Number(min)) {
    console.error(`Coverage ${coverage}% is below the required ${min}%`);
    process.exit(1);
}

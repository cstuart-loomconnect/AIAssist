const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver", "<rootDir>/e2e/"],
  // The browser tests in e2e/ run with Playwright, not Jest.
  testPathIgnorePatterns: [
    ...(jestConfig.testPathIgnorePatterns || ["/node_modules/"]),
    "<rootDir>/e2e/"
  ]
};

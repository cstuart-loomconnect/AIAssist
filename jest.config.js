const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    // A CSS-only module (shared styles imported by @import) has no script for Jest to resolve.
    "^c/aiChatStyles$":
      "<rootDir>/force-app/main/default/lwc/aiChatStyles/aiChatStyles.css"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};

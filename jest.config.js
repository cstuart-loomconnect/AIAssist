const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};

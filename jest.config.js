const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    "^lightning/select$": "<rootDir>/force-app/test/jest-mocks/lightning/select"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};

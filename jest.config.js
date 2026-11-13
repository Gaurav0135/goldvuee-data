const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: { ...jestConfig.moduleNameMapper, '^@salesforce/community/basePath$': '<rootDir>/test/jest-mocks/communityBasePath.js' },
    testPathIgnorePatterns: ['/node_modules/', '<rootDir>/backups/', '<rootDir>/verification/'],
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};

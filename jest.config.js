const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    roots: ['<rootDir>/force-app/main/default/lwc'],
    moduleNameMapper: {
        ...jestConfig.moduleNameMapper,
        '^@salesforce/community/basePath$': '<rootDir>/test/jest-mocks/communityBasePath.js',
        '^@salesforce/community/Id$': '<rootDir>/test/jest-mocks/communityId.js'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};

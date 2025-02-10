const functions = require("firebase-functions/v2");

// Default configuration
const defaultConfig = {
  timeoutSeconds: 300,
  memory: "4GiB",
  region: "us-central1",
  enforceAppCheck: false
};

// Environment-specific configurations
const configurations = {
  production: {
    ...defaultConfig,
    enforceAppCheck: true,
    minInstances: 1,
    maxInstances: 10
  },
  development: {
    ...defaultConfig,
    timeoutSeconds: 540,  // 9 minutes for development
    memory: "8GiB"       // More memory for development
  },
  local: {
    ...defaultConfig,
    timeoutSeconds: 3600  // 1 hour for local development
  }
};

// Get current environment
const environment = process.env.FUNCTIONS_ENVIRONMENT || 'development';

// Export the configuration
module.exports = {
  environment,
  config: configurations[environment] || configurations.development,
  isDevelopment: environment === 'development',
  isProduction: environment === 'production',
  isLocal: environment === 'local'
}; 
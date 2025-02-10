#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const environment = process.argv[2] || 'development';
const validEnvironments = ['development', 'production', 'local'];

if (!validEnvironments.includes(environment)) {
  console.error(`Invalid environment: ${environment}`);
  console.error(`Valid environments are: ${validEnvironments.join(', ')}`);
  process.exit(1);
}

console.log(`🚀 Deploying to ${environment} environment...`);

// Copy environment-specific .env file
const envFile = path.join(__dirname, `.env.${environment}`);
const targetEnvFile = path.join(__dirname, '.env');

if (!fs.existsSync(envFile)) {
  console.error(`❌ Environment file not found: ${envFile}`);
  process.exit(1);
}

fs.copyFileSync(envFile, targetEnvFile);

// Set environment variable
process.env.FUNCTIONS_ENVIRONMENT = environment;

try {
  if (environment === 'local') {
    // Start emulators for local development
    execSync('firebase emulators:start', { stdio: 'inherit' });
  } else {
    // Deploy to Firebase
    execSync(`firebase deploy --only functions --project=${environment}`, { stdio: 'inherit' });
  }
  console.log(`✅ Successfully deployed to ${environment}`);
} catch (error) {
  console.error('❌ Deployment failed:', error.message);
  process.exit(1);
} 
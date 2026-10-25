let createClient;
try {
  createClient = require('@supabase/supabase-js').createClient;
} catch (_) {
  createClient = () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve({ data: null }),
          single: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
      insert: () => ({
        select: () => ({
          single: () => Promise.resolve({ data: { id: 'mock-id' }, error: null }),
        }),
      }),
      upsert: () => Promise.resolve({ data: {}, error: null }),
    }),
    rpc: () => Promise.resolve({ data: null, error: null }),
  });
}

const path = require('path');
const fs = require('fs');

try {
  const dotenv = require('dotenv');
  const serviceEnvPath = path.join(__dirname, '../../.env');
  const rootEnvPath = path.join(__dirname, '../../../../.env');

  if (fs.existsSync(serviceEnvPath)) {
    dotenv.config({ path: serviceEnvPath });
  } else if (fs.existsSync(rootEnvPath)) {
    dotenv.config({ path: rootEnvPath });
  }
  dotenv.config(); // fallback to current working directory
} catch (_) {}

const supabaseUrl = process.env.SUPABASE_URL || 'http://localhost:54321';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || 'dummy_key';

const isConfigured = Boolean(
  process.env.SUPABASE_URL &&
  process.env.SUPABASE_SERVICE_ROLE_KEY &&
  process.env.SUPABASE_SERVICE_ROLE_KEY !== 'your_supabase_service_role_key_here' &&
  process.env.SUPABASE_SERVICE_ROLE_KEY !== 'dummy_key'
);

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

module.exports = {
  supabase,
  isConfigured,
  supabaseUrl,
};

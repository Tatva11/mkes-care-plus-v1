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
  const candidateEnvPaths = [
    path.resolve(__dirname, '../../../api.env'),
    path.resolve(__dirname, '../../../.env'),
    path.resolve(__dirname, '../../.env'),
  ];

  for (const envPath of candidateEnvPaths) {
    if (fs.existsSync(envPath)) {
      dotenv.config({ path: envPath });
    }
  }
  dotenv.config(); // fallback to current working directory
} catch (_) {}

const supabaseUrl = process.env.SUPABASE_URL || 'http://localhost:54321';

// Strict validation of service-role key for privileged background daemon operations.
// Background workers execute privileged RPCs and lease claims that strictly require service_role.
const hasServiceRole = Boolean(
  process.env.SUPABASE_SERVICE_ROLE_KEY &&
  process.env.SUPABASE_SERVICE_ROLE_KEY !== 'your_supabase_service_role_key_here' &&
  process.env.SUPABASE_SERVICE_ROLE_KEY !== 'dummy_key' &&
  process.env.SUPABASE_SERVICE_ROLE_KEY.trim().length > 20
);

const isConfigured = Boolean(
  process.env.SUPABASE_URL &&
  process.env.SUPABASE_URL !== 'http://localhost:54321' &&
  hasServiceRole
);

// DO NOT fall back to anon key for background service operations!
// Privileged RPCs (claim_whatsapp_outbox_batch, batch schedulers, opt-out) are strictly revoked from anon.
const supabaseKey = hasServiceRole
  ? process.env.SUPABASE_SERVICE_ROLE_KEY
  : 'unconfigured_service_role_key';

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

module.exports = {
  supabase,
  isConfigured,
  hasServiceRole,
  supabaseUrl,
};

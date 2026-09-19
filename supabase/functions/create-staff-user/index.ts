// supabase/functions/create-staff-user/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: create-staff-user
//
// Creates a new Supabase Auth user via the GoTrue Admin API (correct password
// hashing), then inserts the matching profiles row.
//
// Called by: Flutter → supabase.functions.invoke('create-staff-user', body)
//
// Auth:
//   - Caller must pass a valid user JWT (supabase_flutter does this automatically
//     via the Authorization header when calling functions.invoke).
//   - Function verifies the caller is an active admin before creating anyone.
//
// The SUPABASE_SERVICE_ROLE_KEY is injected automatically as an env var
// inside every Supabase Edge Function — it never leaves the server.
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  // ── CORS preflight ──────────────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return respond({ ok: true }, 200);
  }

  try {
    // ── 1. Verify the caller has a valid JWT ─────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return respond({ error: "Missing Authorization header" }, 401);
    }

    // Build a caller-scoped client (anon key + user JWT) to check identity
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const {
      data: { user: callerUser },
      error: callerErr,
    } = await callerClient.auth.getUser();

    if (callerErr || !callerUser) {
      return respond({ error: "Unauthorized: not authenticated" }, 401);
    }

    // ── 2. Verify caller is an active admin ──────────────────────────────
    const { data: callerProfile, error: profileErr } = await callerClient
      .from("profiles")
      .select("role, is_active")
      .eq("id", callerUser.id)
      .maybeSingle();

    if (profileErr || !callerProfile) {
      return respond({ error: "Unauthorized: caller profile not found" }, 401);
    }

    if (callerProfile.role !== "admin" || !callerProfile.is_active) {
      return respond(
        { error: "Forbidden: only active admins can create users" },
        403,
      );
    }

    // ── 3. Parse and validate request body ──────────────────────────────
    const body = await req.json();
    const {
      p_email,
      p_password,
      p_full_name,
      p_phone_number = null,
      p_department_id = null,
      p_designation = null,
      p_role = "staff",
      p_salary = null,
      p_joining_date = null,
    } = body;

    if (!p_email || !p_password || !p_full_name) {
      return respond(
        { error: "p_email, p_password, and p_full_name are required" },
        400,
      );
    }

    if (!["admin", "staff"].includes(p_role)) {
      return respond({ error: "p_role must be 'admin' or 'staff'" }, 400);
    }

    if (p_password.length < 6) {
      return respond(
        { error: "p_password must be at least 6 characters" },
        400,
      );
    }

    // ── 4. Build service-role client (Admin API access) ──────────────────
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // ── 5. Create Auth user via GoTrue Admin API ─────────────────────────
    //    This is the ONLY correct way to programmatically create a password-
    //    authenticated user. Directly inserting into auth.users with
    //    pgcrypto.crypt() produces a hash that GoTrue cannot verify.
    const { data: newAuthData, error: createAuthErr } =
      await adminClient.auth.admin.createUser({
        email: p_email,
        password: p_password,
        email_confirm: true, // admin-created → skip confirmation email
        user_metadata: { full_name: p_full_name },
      });

    if (createAuthErr || !newAuthData?.user) {
      console.error("GoTrue createUser error:", createAuthErr);
      return respond(
        {
          error: createAuthErr?.message ?? "Failed to create auth user",
          code: createAuthErr?.status,
        },
        400,
      );
    }

    const newUserId = newAuthData.user.id;

    // ── 6. Insert the profiles row ────────────────────────────────────────
    const profilePayload: Record<string, unknown> = {
      id: newUserId,
      full_name: p_full_name,
      email: p_email,
      role: p_role,
      is_active: true,
    };

    // Only include optional fields when they have a value (avoid null FK violations)
    if (p_phone_number) profilePayload.phone_number = p_phone_number;
    if (p_department_id) profilePayload.department_id = p_department_id;
    if (p_designation) profilePayload.designation = p_designation;
    if (p_salary !== null) profilePayload.salary = p_salary;
    if (p_joining_date) profilePayload.joining_date = p_joining_date;

    const { error: profileInsertErr } = await adminClient
      .from("profiles")
      .insert(profilePayload);

    if (profileInsertErr) {
      console.error("Profile insert error:", profileInsertErr);
      // Roll back the auth user to avoid an orphan auth.users row
      await adminClient.auth.admin.deleteUser(newUserId);
      return respond(
        {
          error: `Profile creation failed: ${profileInsertErr.message}`,
          detail: profileInsertErr.details,
        },
        500,
      );
    }

    // ── 7. Success ────────────────────────────────────────────────────────
    return respond({ user_id: newUserId }, 200);
  } catch (err) {
    console.error("Unexpected Edge Function error:", err);
    return respond({ error: String(err) }, 500);
  }
});

// ─── Helper ──────────────────────────────────────────────────────────────────
function respond(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

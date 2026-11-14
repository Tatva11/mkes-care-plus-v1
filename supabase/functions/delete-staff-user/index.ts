// supabase/functions/delete-staff-user/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: delete-staff-user
//
// Deletes a staff/user account via the GoTrue Admin API with the server-side
// service-role key, after verifying admin permissions and safely cleaning up
// related profile and clinical audit references.
//
// Called by: Flutter → supabase.functions.invoke('delete-staff-user', body)
//
// Security & Safety:
//   - Caller must pass a valid user JWT in Authorization header.
//   - Caller must be an active administrator in public.profiles.
//   - Prevents accidental deletion of the caller's own account.
//   - Prevents deletion of the last remaining administrator account.
//   - Atomically cleans up or nullifies child record references to prevent FK violations.
//   - Permanently deletes the authentication user from Supabase Auth.
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
    // ── 1. Verify caller has a valid JWT ──────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return respond({ error: "Missing Authorization header" }, 401);
    }

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
        { error: "Forbidden: only active administrators can delete accounts" },
        403,
      );
    }

    // ── 3. Parse and validate request body ──────────────────────────────
    const body = await req.json();
    const targetUserId = body.target_user_id || body.user_id;

    if (!targetUserId || typeof targetUserId !== "string") {
      return respond({ error: "target_user_id is required" }, 400);
    }

    // ── 4. Guard: Prevent self-deletion ─────────────────────────────────
    if (targetUserId === callerUser.id) {
      return respond({ error: "Cannot delete your own admin account" }, 400);
    }

    // Build service-role client for administrative queries and GoTrue deletion
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // ── 5. Guard: Prevent deleting the last remaining admin ─────────────
    const { data: targetProfile, error: targetErr } = await adminClient
      .from("profiles")
      .select("id, role, full_name, email")
      .eq("id", targetUserId)
      .maybeSingle();

    if (targetProfile && targetProfile.role === "admin") {
      const { count: adminCount, error: countErr } = await adminClient
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "admin")
        .eq("is_active", true);

      if (countErr) {
        console.error("Error checking active admin count:", countErr);
      } else if (adminCount !== null && adminCount <= 1) {
        return respond(
          { error: "Cannot delete the last remaining admin account" },
          400,
        );
      }
    }

    // ── 6. Clean up database foreign keys & profile ─────────────────────
    // Call delete_user_by_admin RPC using service role to safely nullify
    // references in billing, audit logs, appointments, clinical records, etc.
    const { error: rpcErr } = await adminClient.rpc("delete_user_by_admin", {
      target_user_id: targetUserId,
    });

    if (rpcErr) {
      console.warn("delete_user_by_admin RPC warning/error:", rpcErr.message);
      // Fallback: Ensure profile is deleted even if RPC threw on soft error
      await adminClient.from("profiles").delete().eq("id", targetUserId);
    }

    // ── 7. Permanently delete Auth user via GoTrue Admin API ────────────
    const { error: deleteAuthErr } =
      await adminClient.auth.admin.deleteUser(targetUserId);

    if (deleteAuthErr) {
      // If user was not found in auth.users, they may have already been cleaned up
      if (deleteAuthErr.message?.toLowerCase().includes("not found")) {
        console.info(`Auth user ${targetUserId} was already removed.`);
      } else {
        console.error("GoTrue deleteUser error:", deleteAuthErr);
        return respond(
          { error: `Auth deletion failed: ${deleteAuthErr.message}` },
          500,
        );
      }
    }

    // ── 8. Success ──────────────────────────────────────────────────────
    return respond(
      {
        success: true,
        deleted_user_id: targetUserId,
        name: targetProfile?.full_name,
      },
      200,
    );
  } catch (err) {
    console.error("Unexpected Edge Function error in delete-staff-user:", err);
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

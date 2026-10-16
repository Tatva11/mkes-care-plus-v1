// supabase/functions/sync-excel-workbook/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Supabase Edge Function: sync-excel-workbook (Sprint 9.4)
// Handles schema discovery, template generation, full historical export,
// and 5-minute incremental synchronization with transactional outbox,
// distributed leases, fencing tokens, and atomic version publication.
//
// Authentication:
//   - Admin JWT (Bearer <user_jwt>): active administrator (role = 'admin', is_active = true)
//   - Service-Role (Bearer <service_role_key>): trusted automated scheduler
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import {
  MASTER_WORKSHEETS,
  MASTER_WORKBOOK_FILENAME,
  sortRecordsForWorksheet,
} from "./schema.ts";
import { MasterWorkbookBuilder } from "./workbook_builder.ts";
import {
  WorksheetExportSummary,
  HistoricalExportResult,
  IncrementalSyncResult,
  SingleWorksheetExportResult,
} from "./types.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function respond(
  data: Record<string, any> | Uint8Array,
  status = 200,
  contentType = "application/json",
  filename = MASTER_WORKBOOK_FILENAME
) {
  if (data instanceof Uint8Array) {
    return new Response(data, {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": contentType,
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  }
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function resolveProfileReferences(
  client: any,
  tableName: string,
  rows: any[]
): Promise<void> {
  if (!rows || rows.length === 0) return;

  const idFieldMap: Record<string, string[]> = {
    stock_requests: ["requested_by", "reviewed_by", "fulfilled_by"],
    sales: ["sold_by"],
    purchase_orders: ["created_by", "ordered_by"],
    billing: ["billed_by"],
    billing_payments: ["recorded_by"],
  };

  const fields = idFieldMap[tableName];
  if (!fields) return;

  const userIds = new Set<string>();
  for (const r of rows) {
    for (const f of fields) {
      if (r[f] && typeof r[f] === "string") {
        userIds.add(r[f]);
      }
    }
  }

  if (userIds.size === 0) return;

  try {
    const { data: profiles } = await client
      .from("profiles")
      .select("id, full_name, email")
      .in("id", Array.from(userIds));

    if (!profiles || profiles.length === 0) return;

    const profMap = new Map<string, { full_name: string; email?: string }>();
    for (const p of profiles) {
      profMap.set(p.id, { full_name: p.full_name, email: p.email });
    }

    for (const r of rows) {
      if (tableName === "stock_requests") {
        if (r.requested_by && profMap.has(r.requested_by)) {
          r.requester = profMap.get(r.requested_by);
          r.requester_name = r.requester.full_name;
        }
      } else if (tableName === "sales") {
        if (r.sold_by && profMap.has(r.sold_by)) {
          r.profiles = profMap.get(r.sold_by);
          r.seller = r.profiles;
          r.sold_by_name = r.profiles.full_name;
        }
      } else if (tableName === "purchase_orders") {
        if (r.created_by && profMap.has(r.created_by)) {
          r.creator = profMap.get(r.created_by);
          r.creator_name = r.creator.full_name;
        }
        if (r.ordered_by && profMap.has(r.ordered_by)) {
          r.orderer = profMap.get(r.ordered_by);
          r.orderer_name = r.orderer.full_name;
        }
      } else if (tableName === "billing") {
        if (r.billed_by && profMap.has(r.billed_by)) {
          r.profiles = profMap.get(r.billed_by);
          r.billed_by_name = r.profiles.full_name;
        }
      } else if (tableName === "billing_payments") {
        if (r.recorded_by && profMap.has(r.recorded_by)) {
          r.profiles = profMap.get(r.recorded_by);
          r.received_by_name = r.profiles.full_name;
        }
      }
    }
  } catch {
    // Non-fatal: formatters provide fallback '-'
  }
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return respond({ ok: true }, 200);
  }

  try {
    const authHeader =
      req.headers.get("Authorization") || req.headers.get("authorization");
    const apikeyHeader =
      req.headers.get("apikey") ||
      req.headers.get("apiKey") ||
      req.headers.get("x-api-key");

    if (!authHeader && !apikeyHeader) {
      return respond({ error: "Missing Authorization or apikey header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return respond(
        { error: "Server misconfiguration: missing Supabase environment variables" },
        500
      );
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Helper: strip quotes, whitespace, and all leading "Bearer " prefixes
    const sanitizeToken = (token: string | null | undefined): string => {
      if (!token) return "";
      let t = token.trim().replace(/^["']|["']$/g, "").trim();
      while (/^Bearer\s+/i.test(t)) {
        t = t.replace(/^Bearer\s+/i, "").trim().replace(/^["']|["']$/g, "").trim();
      }
      return t;
    };

    const cleanAuthToken = sanitizeToken(authHeader);
    const cleanApiKey = sanitizeToken(apikeyHeader);
    const cleanServiceRoleKey = sanitizeToken(serviceRoleKey);

    // Dual-authentication: Service-Role (Scheduler) or Admin JWT (User)
    let callerUserId: string | null = null;
    const isServiceRole =
      (cleanAuthToken.length > 0 && cleanAuthToken === cleanServiceRoleKey) ||
      (cleanApiKey.length > 0 && cleanApiKey === cleanServiceRoleKey);

    if (!isServiceRole) {
      // Helper to inspect JWT claims safely without external libs
      const parseJwtRole = (token: string): string | null => {
        try {
          const parts = token.split(".");
          if (parts.length !== 3) return null;
          const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
          const json = JSON.parse(atob(base64));
          return json?.role || null;
        } catch {
          return null;
        }
      };

      const incomingRole = parseJwtRole(cleanAuthToken) || parseJwtRole(cleanApiKey);

      if (incomingRole === "anon") {
        console.error(
          "[Auth] Rejected: Incoming credentials contain 'role': 'anon'. Scheduled Edge Function invocations require the 'service_role' secret key."
        );
        return respond(
          {
            error:
              "Unauthorized: received anon key instead of service_role key. Scheduled Edge Function invocations require the service_role key. Update your Supabase Vault secret 'service_role_key' with the service_role secret from Supabase Dashboard -> Project Settings -> API.",
            receivedRole: "anon",
          },
          401
        );
      }

      if (incomingRole === "service_role") {
        const inFp = cleanAuthToken.length > 10 ? `${cleanAuthToken.slice(0, 6)}...${cleanAuthToken.slice(-4)}` : "too_short";
        const expFp = cleanServiceRoleKey.length > 10 ? `${cleanServiceRoleKey.slice(0, 6)}...${cleanServiceRoleKey.slice(-4)}` : "not_configured";
        console.error(
          `[Auth] Rejected: Incoming service_role key mismatch against SUPABASE_SERVICE_ROLE_KEY. Incoming: ${inFp} (len ${cleanAuthToken.length}), Expected: ${expFp} (len ${cleanServiceRoleKey.length})`
        );
        return respond(
          {
            error:
              "Unauthorized: service_role key mismatch. The key provided in the request does not match SUPABASE_SERVICE_ROLE_KEY in the Edge Function environment. Please verify that the secret stored in Supabase Vault matches the active service_role key in Project Settings -> API.",
            incomingFingerprint: inFp,
            expectedFingerprint: expFp,
          },
          401
        );
      }

      // If not service_role and not anon, authenticate as end-user session
      const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${cleanAuthToken}` } },
      });

      const {
        data: { user: callerUser },
        error: userErr,
      } = await callerClient.auth.getUser();

      if (userErr || !callerUser) {
        return respond({ error: "Unauthorized: invalid user session" }, 401);
      }

      const { data: profile, error: profileErr } = await adminClient
        .from("profiles")
        .select("role, is_active")
        .eq("id", callerUser.id)
        .maybeSingle();

      if (profileErr || !profile) {
        return respond({ error: "Unauthorized: profile not found" }, 401);
      }

      if (profile.role !== "admin" || !profile.is_active) {
        return respond(
          { error: "Forbidden: only active administrators can access workbook synchronization" },
          403
        );
      }

      callerUserId = callerUser.id;
    }

    // Process action
    let action = "get-schema";
    let requestBody: Record<string, any> = {};
    if (req.method === "POST") {
      try {
        requestBody = await req.json();
        action = requestBody.action || action;
      } catch {
        // Fallback
      }
    }

    const url = new URL(req.url);
    if (url.searchParams.has("action")) {
      action = url.searchParams.get("action")!;
    }

    switch (action) {
      case "get-schema": {
        return respond({
          workbookName: MASTER_WORKBOOK_FILENAME,
          worksheetCount: MASTER_WORKSHEETS.length,
          worksheets: MASTER_WORKSHEETS.map((w) => ({
            name: w.name,
            sourceTable: w.sourceTable,
            stableIdKey: w.stableIdKey,
            timestampKey: w.timestampKey,
            columnCount: w.columns.length,
            columns: w.columns.map((c) => ({
              header: c.header,
              key: c.key,
              width: c.width,
              format: c.format,
            })),
            sensitiveExcludedFields: w.sensitiveExcludedFields || [],
          })),
        });
      }

      case "get-active-version": {
        const { data: activeVersion, error: verErr } = await adminClient
          .rpc("get_excel_sync_active_version")
          .maybeSingle();

        if (verErr) {
          return respond({ error: `Failed to fetch active version: ${verErr.message}` }, 500);
        }

        if (!activeVersion) {
          return respond({ activeVersion: null, message: "No active workbook version found" });
        }

        return respond({
          activeVersion: {
            versionId: activeVersion.version_id,
            versionNumber: activeVersion.version_number,
            storagePath: activeVersion.storage_path,
            fileSizeBytes: activeVersion.file_size_bytes,
            totalRecords: activeVersion.total_records,
            worksheetsSummary: activeVersion.worksheets_summary,
            publishedAt: activeVersion.published_at,
            syncId: activeVersion.sync_id,
          },
        });
      }

      case "generate-template": {
        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();
        const buffer = await builder.writeBuffer();

        if (url.searchParams.get("download") === "true") {
          return respond(
            buffer,
            200,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          );
        }

        return respond({
          success: true,
          workbookName: MASTER_WORKBOOK_FILENAME,
          worksheetCount: MASTER_WORKSHEETS.length,
          fileSizeBytes: buffer.byteLength,
          generatedAt: new Date().toISOString(),
        });
      }

      case "download-worksheet":
      case "export-worksheet": {
        const targetSheetName =
          requestBody.worksheet_name ||
          requestBody.sheet ||
          url.searchParams.get("worksheet_name") ||
          url.searchParams.get("sheet");

        if (!targetSheetName) {
          return respond(
            {
              error: "Missing required parameter 'worksheet_name'.",
              availableWorksheets: MASTER_WORKSHEETS.map((w) => w.name),
            },
            400
          );
        }

        const sheetDef = MASTER_WORKSHEETS.find(
          (w) => w.name.toLowerCase() === String(targetSheetName).trim().toLowerCase()
        );

        if (!sheetDef) {
          return respond(
            {
              error: `Worksheet [${targetSheetName}] not found.`,
              availableWorksheets: MASTER_WORKSHEETS.map((w) => w.name),
            },
            404
          );
        }

        const builder = new MasterWorkbookBuilder();
        builder.initializeWorksheet(sheetDef.name);

        const PAGE_SIZE = 500;
        let offset = 0;
        let sheetFetchedCount = 0;
        let expectedTotalCount: number | null = null;
        const allRows: Record<string, any>[] = [];

        while (true) {
          let query = adminClient
            .from(sheetDef.sourceTable)
            .select(sheetDef.selectQuery, { count: "exact" });

          if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
            for (const sort of sheetDef.sortClauses) {
              query = query.order(sort.column, {
                ascending: sort.ascending,
                nullsFirst: sort.nullsFirst ?? false,
              });
            }
          } else {
            query = query.order(sheetDef.stableIdKey, { ascending: true });
          }

          const { data: pageData, count: totalCount, error: queryErr } =
            await query.range(offset, offset + PAGE_SIZE - 1);

          if (queryErr) {
            return respond(
              {
                error: `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`,
              },
              500
            );
          }

          if (totalCount !== null) {
            expectedTotalCount = totalCount;
          }

          if (!pageData || pageData.length === 0) {
            break;
          }

          await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
          allRows.push(...pageData);
          sheetFetchedCount += pageData.length;
          offset += pageData.length;

          if (totalCount !== null && offset >= totalCount) {
            break;
          }
        }

        if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
          return respond(
            {
              error: `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`,
            },
            500
          );
        }

        const sortedRows = sortRecordsForWorksheet(sheetDef.name, allRows);
        builder.appendWorksheetRows(sheetDef.name, sortedRows, 0);

        const buffer = await builder.writeBuffer();
        if (
          buffer.byteLength < 4 ||
          buffer[0] !== 0x50 ||
          buffer[1] !== 0x4B ||
          buffer[2] !== 0x03 ||
          buffer[3] !== 0x04
        ) {
          return respond(
            { error: "Generated worksheet workbook buffer failed PK ZIP signature validation" },
            500
          );
        }

        const fileName = `MKES_CARE_Plus_${sheetDef.name}.xlsx`;

        // Direct stream download
        if (url.searchParams.get("download") === "true" || requestBody.download === true) {
          return respond(
            buffer,
            200,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName
          );
        }

        // Upload to storage under sheets/ and generate signed URL
        const sheetStoragePath = `sheets/${fileName}`;
        const { error: uploadErr } = await adminClient.storage
          .from("clinic-excel-sync")
          .upload(sheetStoragePath, buffer, {
            contentType:
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            upsert: true,
          });

        if (uploadErr) {
          return respond(
            { error: `Storage upload failed for worksheet [${sheetDef.name}]: ${uploadErr.message}` },
            500
          );
        }

        const { data: signedData, error: signErr } = await adminClient.storage
          .from("clinic-excel-sync")
          .createSignedUrl(sheetStoragePath, 3600);

        if (signErr) {
          return respond(
            { error: `Signed URL generation failed for worksheet [${sheetDef.name}]: ${signErr.message}` },
            500
          );
        }

        const result: SingleWorksheetExportResult = {
          success: true,
          worksheetName: sheetDef.name,
          fileName,
          storagePath: `clinic-excel-sync/${sheetStoragePath}`,
          recordCount: sortedRows.length,
          fileSizeBytes: buffer.byteLength,
          downloadUrl: signedData?.signedUrl,
        };

        return respond(result);
      }

      case "sync-incremental": {
        const syncId = crypto.randomUUID();
        const startTime = new Date();
        const syncType = isServiceRole ? "scheduled" : requestBody.sync_type || "manual";

        // 1. Acquire distributed lease with fencing generation
        const { data: leaseData, error: leaseErr } = await adminClient
          .rpc("acquire_excel_sync_lease", {
            p_holder_id: syncId,
            p_ttl_seconds: 300,
          });

        if (leaseErr) {
          return respond({ error: `Lease acquisition error: ${leaseErr.message}` }, 500);
        }

        const lease = Array.isArray(leaseData) ? leaseData[0] : leaseData;
        if (!lease || !lease.acquired) {
          return respond({
            success: true,
            status: "already_running",
            message: "A synchronization worker is already running or holding active lease.",
            currentHolder: lease?.current_holder,
            expiresAt: lease?.expires_at,
          });
        }

        const fencingToken = lease.fencing_token;

        // 2. Initialize sync state audit record
        await adminClient.from("excel_sync_state").insert({
          id: syncId,
          sync_type: syncType,
          status: "in_progress",
          started_at: startTime.toISOString(),
          triggered_by: callerUserId,
          records_upserted: 0,
          file_size_bytes: 0,
          storage_path: `clinic-excel-sync/versions/MKES_CARE_Plus_Master_${syncId}.xlsx`,
          worksheets_synced: [],
        });

        // 3. Claim pending outbox mutation events
        const { data: claimData, error: claimErr } = await adminClient
          .rpc("claim_excel_sync_outbox_events", {
            p_sync_id: syncId,
            p_limit: 2000,
          });

        if (claimErr) {
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });
          return respond({ error: `Outbox claim failed: ${claimErr.message}` }, 500);
        }

        const claimInfo = Array.isArray(claimData) ? claimData[0] : claimData;
        const eventsClaimed = claimInfo?.claimed_count ?? 0;

        const { data: activeVersion } = await adminClient
          .rpc("get_excel_sync_active_version")
          .maybeSingle();

        if (!activeVersion) {
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });
          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message:
                "No active baseline workbook exists. Please initialize the baseline with a full historical export first.",
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              status: "failed",
              syncId,
              error:
                "No active baseline workbook exists. Please initialize the baseline with a full historical export first.",
            },
            400
          );
        }

        // 4. Fast No-Op Exit if outbox has no pending mutations
        if (eventsClaimed === 0) {
          // Release lease immediately and finalize audit
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });

          const endTime = new Date();
          await adminClient
            .from("excel_sync_state")
            .update({
              status: "success",
              completed_at: endTime.toISOString(),
              records_upserted: 0,
              file_size_bytes: activeVersion.file_size_bytes,
              storage_path: activeVersion.storage_path,
              error_message: null,
            })
            .eq("id", syncId);

          const noOpResult: IncrementalSyncResult = {
            success: true,
            status: "no_op",
            syncId,
            versionId: activeVersion.version_id,
            versionNumber: activeVersion.version_number,
            fencingToken,
            totalRecords: activeVersion.total_records,
            fileSizeBytes: activeVersion.file_size_bytes,
            storagePath: activeVersion.storage_path,
            durationMs: endTime.getTime() - startTime.getTime(),
            eventsProcessed: 0,
          };
          return respond(noOpResult);
        }

        // 5. Full Regeneration of all 21 worksheets from authoritative DB
        try {
          const builder = new MasterWorkbookBuilder();
          builder.initializeAllWorksheets();

          const PAGE_SIZE = 500;
          let totalExportedRecords = 0;
          const worksheetSummaries: WorksheetExportSummary[] = [];
          const checkpointsData: Array<{
            worksheetName: string;
            sourceTable: string;
            highWaterMark: string;
            recordCount: number;
          }> = [];

          for (const sheetDef of MASTER_WORKSHEETS) {
            let offset = 0;
            let sheetFetchedCount = 0;
            let maxTimestamp = "1970-01-01T00:00:00.000Z";
            let expectedTotalCount: number | null = null;

            while (true) {
              let query = adminClient
                .from(sheetDef.sourceTable)
                .select(sheetDef.selectQuery, { count: "exact" });

              if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
                for (const sort of sheetDef.sortClauses) {
                  query = query.order(sort.column, {
                    ascending: sort.ascending,
                    nullsFirst: sort.nullsFirst ?? false,
                  });
                }
              } else {
                query = query.order(sheetDef.stableIdKey, { ascending: true });
              }

              const { data: pageData, count: totalCount, error: queryErr } =
                await query.range(offset, offset + PAGE_SIZE - 1);

              if (queryErr) {
                throw new Error(
                  `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`
                );
              }

              if (totalCount !== null) {
                expectedTotalCount = totalCount;
              }

              if (!pageData || pageData.length === 0) {
                break;
              }

              for (const row of pageData) {
                const ts = row[sheetDef.timestampKey];
                if (ts && typeof ts === "string" && ts > maxTimestamp) {
                  maxTimestamp = ts;
                }
              }

              await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
              const sortedPage = sortRecordsForWorksheet(sheetDef.name, pageData);
              builder.appendWorksheetRows(sheetDef.name, sortedPage, offset);
              sheetFetchedCount += pageData.length;
              offset += pageData.length;

              if (totalCount !== null && offset >= totalCount) {
                break;
              }
            }

            if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
              throw new Error(
                `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`
              );
            }

            worksheetSummaries.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              recordCount: sheetFetchedCount,
              highWaterMark: maxTimestamp,
              status: sheetFetchedCount > 0 ? "success" : "empty",
            });

            checkpointsData.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              highWaterMark: maxTimestamp,
              recordCount: sheetFetchedCount,
            });

            totalExportedRecords += sheetFetchedCount;
          }

          // 6. Build and validate XLSX binary package
          const buffer = await builder.writeBuffer();

          if (
            buffer.byteLength < 4 ||
            buffer[0] !== 0x50 ||
            buffer[1] !== 0x4B ||
            buffer[2] !== 0x03 ||
            buffer[3] !== 0x04
          ) {
            throw new Error("Generated workbook buffer failed PK ZIP signature validation");
          }

          // 7. Upload to unique immutable version path in private storage
          const versionId = crypto.randomUUID();
          const versionStoragePath = `versions/MKES_CARE_Plus_Master_${versionId}.xlsx`;

          const { error: uploadErr } = await adminClient.storage
            .from("clinic-excel-sync")
            .upload(versionStoragePath, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: false,
            });

          if (uploadErr) {
            throw new Error(`Storage version upload failed: ${uploadErr.message}`);
          }

          // 8. Atomic Database Publication & Checkpoint Commitment RPC
          const { data: pubData, error: pubErr } = await adminClient.rpc(
            "publish_excel_sync_version",
            {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
              p_sync_id: syncId,
              p_version_id: versionId,
              p_storage_path: `clinic-excel-sync/${versionStoragePath}`,
              p_file_size_bytes: buffer.byteLength,
              p_total_records: totalExportedRecords,
              p_worksheets_summary: worksheetSummaries,
              p_checkpoints: checkpointsData,
              p_claim_id: syncId,
            }
          );

          if (pubErr) {
            throw new Error(`Publication RPC failed: ${pubErr.message}`);
          }

          // 9. Best-effort update of canonical storage pointer (database remains authoritative)
          try {
            await adminClient.storage
              .from("clinic-excel-sync")
              .upload(MASTER_WORKBOOK_FILENAME, buffer, {
                contentType:
                  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                upsert: true,
              });
          } catch {
            // Non-fatal: DB version pointer guarantees consistency
          }

          const endTime = new Date();
          const durationMs = endTime.getTime() - startTime.getTime();

          const result: IncrementalSyncResult = {
            success: true,
            status: "success",
            syncId,
            versionId,
            versionNumber: pubData?.version_number ?? 1,
            fencingToken,
            totalRecords: totalExportedRecords,
            fileSizeBytes: buffer.byteLength,
            storagePath: `clinic-excel-sync/${versionStoragePath}`,
            durationMs,
            eventsProcessed: eventsClaimed,
            worksheetSummaries,
          };

          return respond(result);
        } catch (workerErr: any) {
          const errMsg = workerErr?.message || "Incremental sync execution failed";

          // Safely release lease and mark failed state
          try {
            await adminClient.rpc("release_excel_sync_lease", {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
            });
          } catch {
            // Ignore lease release error during failure recovery
          }

          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message: errMsg,
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              status: "failed",
              syncId,
              error: errMsg,
            },
            500
          );
        }
      }

      case "export-historical": {
        const syncId = crypto.randomUUID();
        const startTime = new Date();
        const syncType = requestBody.sync_type || "initial";

        // Acquire lease for historical export as well to prevent concurrency conflicts
        const { data: leaseData } = await adminClient.rpc(
          "acquire_excel_sync_lease",
          {
            p_holder_id: syncId,
            p_ttl_seconds: 600,
          }
        );

        const lease = Array.isArray(leaseData) ? leaseData[0] : leaseData;
        if (lease && !lease.acquired) {
          return respond(
            {
              success: false,
              error: "Another synchronization worker is currently active. Please try again later.",
            },
            409
          );
        }

        const fencingToken = lease?.fencing_token ?? 1;

        // Record sync state
        await adminClient.from("excel_sync_state").insert({
          id: syncId,
          sync_type: syncType,
          status: "in_progress",
          started_at: startTime.toISOString(),
          triggered_by: callerUserId,
          records_upserted: 0,
          file_size_bytes: 0,
          storage_path: `clinic-excel-sync/${MASTER_WORKBOOK_FILENAME}`,
          worksheets_synced: [],
        });

        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();

        const PAGE_SIZE = 500;
        let totalExportedRecords = 0;
        const worksheetSummaries: WorksheetExportSummary[] = [];
        const successfulSheets: string[] = [];
        const checkpointsData: Array<{
          worksheetName: string;
          sourceTable: string;
          highWaterMark: string;
          recordCount: number;
        }> = [];

        try {
          for (const sheetDef of MASTER_WORKSHEETS) {
            let offset = 0;
            let sheetFetchedCount = 0;
            let maxTimestamp = "1970-01-01T00:00:00.000Z";
            let expectedTotalCount: number | null = null;

            while (true) {
              let query = adminClient
                .from(sheetDef.sourceTable)
                .select(sheetDef.selectQuery, { count: "exact" });

              if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
                for (const sort of sheetDef.sortClauses) {
                  query = query.order(sort.column, {
                    ascending: sort.ascending,
                    nullsFirst: sort.nullsFirst ?? false,
                  });
                }
              } else {
                query = query.order(sheetDef.stableIdKey, { ascending: true });
              }

              const { data: pageData, count: totalCount, error: queryErr } =
                await query.range(offset, offset + PAGE_SIZE - 1);

              if (queryErr) {
                throw new Error(
                  `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`
                );
              }

              if (totalCount !== null) {
                expectedTotalCount = totalCount;
              }

              if (!pageData || pageData.length === 0) {
                break;
              }

              for (const row of pageData) {
                const ts = row[sheetDef.timestampKey];
                if (ts && typeof ts === "string" && ts > maxTimestamp) {
                  maxTimestamp = ts;
                }
              }

              await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
              const sortedPage = sortRecordsForWorksheet(sheetDef.name, pageData);
              builder.appendWorksheetRows(sheetDef.name, sortedPage, offset);
              sheetFetchedCount += pageData.length;
              offset += pageData.length;

              if (totalCount !== null && offset >= totalCount) {
                break;
              }
            }

            if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
              throw new Error(
                `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`
              );
            }

            worksheetSummaries.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              recordCount: sheetFetchedCount,
              highWaterMark: maxTimestamp,
              status: sheetFetchedCount > 0 ? "success" : "empty",
            });
            checkpointsData.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              highWaterMark: maxTimestamp,
              recordCount: sheetFetchedCount,
            });

            successfulSheets.push(sheetDef.name);
            totalExportedRecords += sheetFetchedCount;
          }

          const buffer = await builder.writeBuffer();

          // Upload immutable version
          const versionId = crypto.randomUUID();
          const versionStoragePath = `versions/MKES_CARE_Plus_Master_${versionId}.xlsx`;

          await adminClient.storage
            .from("clinic-excel-sync")
            .upload(versionStoragePath, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: false,
            });

          // Upload canonical copy
          await adminClient.storage
            .from("clinic-excel-sync")
            .upload(MASTER_WORKBOOK_FILENAME, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: true,
            });

          // Publish version and update checkpoints atomically
          await adminClient.rpc("publish_excel_sync_version", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
            p_sync_id: syncId,
            p_version_id: versionId,
            p_storage_path: `clinic-excel-sync/${versionStoragePath}`,
            p_file_size_bytes: buffer.byteLength,
            p_total_records: totalExportedRecords,
            p_worksheets_summary: worksheetSummaries,
            p_checkpoints: checkpointsData,
            p_claim_id: null,
          });

          const endTime = new Date();
          const durationMs = endTime.getTime() - startTime.getTime();

          if (url.searchParams.get("download") === "true") {
            return respond(
              buffer,
              200,
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            );
          }

          const result: HistoricalExportResult = {
            success: true,
            syncId,
            totalRecords: totalExportedRecords,
            fileSizeBytes: buffer.byteLength,
            storagePath: `clinic-excel-sync/${versionStoragePath}`,
            durationMs,
            worksheetSummaries,
          };

          return respond(result);
        } catch (exportErr: any) {
          const errMsg = exportErr?.message || "Historical export failed";

          try {
            await adminClient.rpc("release_excel_sync_lease", {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
            });
          } catch {
            // Ignore
          }

          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message: errMsg,
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              syncId,
              error: errMsg,
              worksheetsCompleted: successfulSheets,
            },
            500
          );
        }
      }

      default:
        return respond({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (e: any) {
    return respond({ error: e?.message || "Internal server error" }, 500);
  }
});

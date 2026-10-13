// supabase/functions/sync-excel-workbook/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Supabase Edge Function: sync-excel-workbook (Sprint 9.2)
// Handles schema discovery, template generation, and workbook structural verification.
//
// Authentication:
//   - Requires valid JWT Authorization header.
//   - Requires caller to be an active admin (role = 'admin', is_active = true).
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MASTER_WORKSHEETS, MASTER_WORKBOOK_FILENAME } from "./schema.ts";
import { MasterWorkbookBuilder } from "./workbook_builder.ts";
import { WorksheetExportSummary, HistoricalExportResult } from "./types.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function respond(data: Record<string, any> | Uint8Array, status = 200, contentType = "application/json") {
  if (data instanceof Uint8Array) {
    return new Response(data, {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": contentType,
        "Content-Disposition": `attachment; filename="${MASTER_WORKBOOK_FILENAME}"`,
      },
    });
  }
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return respond({ ok: true }, 200);
  }

  try {
    // 1. Verify Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return respond({ error: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      return respond({ error: "Server misconfiguration: missing Supabase environment variables" }, 500);
    }

    const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user: callerUser },
      error: userErr,
    } = await callerClient.auth.getUser();

    if (userErr || !callerUser) {
      return respond({ error: "Unauthorized: invalid user session" }, 401);
    }

    // 2. Verify caller is an active administrator
    const { data: profile, error: profileErr } = await callerClient
      .from("profiles")
      .select("role, is_active")
      .eq("id", callerUser.id)
      .maybeSingle();

    if (profileErr || !profile) {
      return respond({ error: "Unauthorized: profile not found" }, 401);
    }

    if (profile.role !== "admin" || !profile.is_active) {
      return respond({ error: "Forbidden: only active administrators can access workbook synchronization" }, 403);
    }

    // 3. Process action
    let action = "get-schema";
    let requestBody: Record<string, any> = {};
    if (req.method === "POST") {
      try {
        requestBody = await req.json();
        action = requestBody.action || action;
      } catch {
        // Fallback to query param or default
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

      case "generate-template": {
        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();
        const buffer = await builder.writeBuffer();

        // If client requests raw binary download
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

      case "export-historical": {
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
        if (!serviceRoleKey) {
          return respond(
            { error: "Server misconfiguration: missing SUPABASE_SERVICE_ROLE_KEY" },
            500
          );
        }

        const adminClient = createClient(supabaseUrl, serviceRoleKey);
        const syncId = crypto.randomUUID();
        const startTime = new Date();
        const syncType = requestBody.sync_type || "initial";

        // 1. Record sync in-progress state
        const { error: insertStateError } = await adminClient
          .from("excel_sync_state")
          .insert({
            id: syncId,
            sync_type: syncType,
            status: "in_progress",
            started_at: startTime.toISOString(),
            triggered_by: callerUser.id,
            records_upserted: 0,
            file_size_bytes: 0,
            storage_path: `clinic-excel-sync/${MASTER_WORKBOOK_FILENAME}`,
            worksheets_synced: [],
          });

        if (insertStateError) {
          return respond(
            { error: `Failed to initialize sync state: ${insertStateError.message}` },
            500
          );
        }

        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();

        const PAGE_SIZE = 500;
        let totalExportedRecords = 0;
        const worksheetSummaries: WorksheetExportSummary[] = [];
        const successfulSheets: string[] = [];

        try {
          // Process all 21 worksheets sequentially
          for (const sheetDef of MASTER_WORKSHEETS) {
            let offset = 0;
            let sheetFetchedCount = 0;
            let maxTimestamp = "1970-01-01T00:00:00.000Z";

            while (true) {
              const { data: pageData, count: totalCount, error: queryErr } =
                await adminClient
                  .from(sheetDef.sourceTable)
                  .select(sheetDef.selectQuery, { count: "exact" })
                  .order(sheetDef.stableIdKey, { ascending: true })
                  .range(offset, offset + PAGE_SIZE - 1);

              if (queryErr) {
                throw new Error(
                  `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`
                );
              }

              if (!pageData || pageData.length === 0) {
                break;
              }

              // Update high-water mark timestamp from records
              for (const row of pageData) {
                const ts = row[sheetDef.timestampKey];
                if (ts && typeof ts === "string" && ts > maxTimestamp) {
                  maxTimestamp = ts;
                }
              }

              // Append rows to worksheet in batches
              builder.appendWorksheetRows(sheetDef.name, pageData, offset);
              sheetFetchedCount += pageData.length;
              offset += pageData.length;

              if (totalCount !== null && offset >= totalCount) {
                break;
              }
            }

            worksheetSummaries.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              recordCount: sheetFetchedCount,
              highWaterMark: maxTimestamp,
              status: sheetFetchedCount > 0 ? "success" : "empty",
            });
            successfulSheets.push(sheetDef.name);
            totalExportedRecords += sheetFetchedCount;
          }

          // 2. Generate ExcelJS binary workbook
          const buffer = await builder.writeBuffer();

          // 3. Upload to private Storage bucket clinic-excel-sync
          const { error: uploadErr } = await adminClient.storage
            .from("clinic-excel-sync")
            .upload(MASTER_WORKBOOK_FILENAME, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: true,
            });

          if (uploadErr) {
            throw new Error(`Storage upload failed: ${uploadErr.message}`);
          }

          // 4. Update checkpoints for all 21 worksheets
          for (const summary of worksheetSummaries) {
            await adminClient.from("excel_sync_checkpoints").upsert({
              worksheet_name: summary.worksheetName,
              source_table: summary.sourceTable,
              last_sync_timestamp: summary.highWaterMark,
              record_count: summary.recordCount,
              updated_at: new Date().toISOString(),
            });
          }

          // 5. Finalize excel_sync_state
          const endTime = new Date();
          const durationMs = endTime.getTime() - startTime.getTime();

          await adminClient
            .from("excel_sync_state")
            .update({
              status: "success",
              completed_at: endTime.toISOString(),
              records_upserted: totalExportedRecords,
              file_size_bytes: buffer.byteLength,
              worksheets_synced: successfulSheets,
              error_message: null,
            })
            .eq("id", syncId);

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
            storagePath: `clinic-excel-sync/${MASTER_WORKBOOK_FILENAME}`,
            durationMs,
            worksheetSummaries,
          };

          return respond(result);
        } catch (exportErr: any) {
          const errMsg = exportErr?.message || "Historical export failed";
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


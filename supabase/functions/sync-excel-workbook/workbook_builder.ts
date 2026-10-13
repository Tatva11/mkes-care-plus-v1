// supabase/functions/sync-excel-workbook/workbook_builder.ts
// ─────────────────────────────────────────────────────────────────────────────
// ExcelJS Master Workbook Generator (Sprint 9.2)
// Builds styled, normalized .xlsx workbooks for MKES CARE+ in Deno runtime.
// ─────────────────────────────────────────────────────────────────────────────

import ExcelJS from "npm:exceljs@4.4.0";
import { MASTER_WORKSHEETS } from "./schema.ts";
import { ExcelWorksheetDefinition } from "./types.ts";

export interface WorkbookBuildOptions {
  includeSampleRows?: boolean;
  clinicName?: string;
}

/**
 * Sanitizes untrusted text strings to prevent spreadsheet formula injection.
 * If a string (or the string after stripping leading whitespace and control characters)
 * begins with '=', '+', '-', '@', tab, or carriage return, prepends an apostrophe (').
 *
 * Legitimate numeric values (numbers and currency) are preserved as numeric types
 * and never converted to strings or prepended with an apostrophe.
 */
export function sanitizeSpreadsheetString(val: string): string {
  if (!val) return val;
  if (val.startsWith("\t") || val.startsWith("\r")) {
    return `'${val}`;
  }
  const trimmed = val.replace(/^[\s\u0000-\u001F]+/, "");
  if (trimmed.length > 0) {
    const firstChar = trimmed[0];
    if (
      firstChar === "=" ||
      firstChar === "+" ||
      firstChar === "-" ||
      firstChar === "@" ||
      firstChar === "\t" ||
      firstChar === "\r"
    ) {
      return `'${val}`;
    }
  }
  return val;
}

export class MasterWorkbookBuilder {
  private workbook: ExcelJS.Workbook;

  constructor(clinicName = "MKES CARE+ Clinical Management Platform") {
    this.workbook = new ExcelJS.Workbook();
    this.workbook.creator = clinicName;
    this.workbook.lastModifiedBy = "MKES CARE+ Automated Synchronizer";
    this.workbook.created = new Date();
    this.workbook.modified = new Date();
    this.workbook.properties.date1904 = false;
  }

  /**
   * Initializes all 21 normalized worksheets according to the authoritative schema.
   */
  public initializeAllWorksheets(options: WorkbookBuildOptions = {}): ExcelJS.Workbook {
    for (const sheetDef of MASTER_WORKSHEETS) {
      this.createWorksheet(sheetDef, options);
    }
    return this.workbook;
  }

  /**
   * Creates and styles an individual worksheet.
   */
  public createWorksheet(
    sheetDef: ExcelWorksheetDefinition,
    _options: WorkbookBuildOptions = {}
  ): ExcelJS.Worksheet {
    const sheet = this.workbook.addWorksheet(sheetDef.name, {
      views: [{ state: "frozen", xSplit: 0, ySplit: 1, activeCell: "A2" }],
      properties: { defaultRowHeight: 20 },
    });

    // Configure columns
    sheet.columns = sheetDef.columns.map((col) => ({
      header: col.header,
      key: col.key,
      width: Math.max(col.width, 12),
      style: this.getColumnStyle(col.format),
    }));

    // Style the header row (Row 1)
    const headerRow = sheet.getRow(1);
    headerRow.height = 28;
    headerRow.eachCell((cell) => {
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FF0D9488" }, // MKES Teal (#0D9488)
      };
      cell.font = {
        name: "Segoe UI",
        size: 11,
        bold: true,
        color: { argb: "FFFFFFFF" }, // White text
      };
      cell.alignment = {
        vertical: "middle",
        horizontal: "left",
        wrapText: true,
      };
      cell.border = {
        bottom: { style: "medium", color: { argb: "FF0F766E" } },
      };
    });

    return sheet;
  }

  /**
   * Appends a batch of rows to a worksheet, with an optional row index offset for alternating styling.
   */
  public appendWorksheetRows(
    sheetName: string,
    records: Record<string, any>[],
    rowIndexOffset = 0
  ): void {
    const sheetDef = MASTER_WORKSHEETS.find((w) => w.name === sheetName);
    if (!sheetDef) {
      throw new Error(`Worksheet definition not found for name: ${sheetName}`);
    }

    const sheet = this.workbook.getWorksheet(sheetName) || this.createWorksheet(sheetDef);

    records.forEach((record, index) => {
      const rowValues: Record<string, any> = {};

      for (const col of sheetDef.columns) {
        // Enforce strict redaction of sensitive fields
        if (
          sheetDef.sensitiveExcludedFields?.includes(col.sourceField) ||
          col.key.toLowerCase().includes("salary")
        ) {
          continue;
        }

        const rawValue = record[col.sourceField];
        let transformed = col.transform
          ? col.transform(rawValue, record)
          : rawValue;

        if (transformed === null || transformed === undefined || transformed === "") {
          transformed = col.defaultValue ?? "-";
        } else if (typeof transformed === "string") {
          // Prevent formula injection on string cells
          transformed = sanitizeSpreadsheetString(transformed);
        } else if (typeof transformed === "object" && !Array.isArray(transformed)) {
          // Guard against untrusted objects that might contain a formula property
          if ("formula" in transformed) {
            transformed = sanitizeSpreadsheetString(String(transformed.formula));
          }
        }

        rowValues[col.key] = transformed;
      }

      const row = sheet.addRow(rowValues);
      row.height = 22;

      // Zebra striping: alternate light gray / white accounting for batch offset
      const isEven = (rowIndexOffset + index) % 2 === 0;
      row.eachCell((cell) => {
        if (isEven) {
          cell.fill = {
            type: "pattern",
            pattern: "solid",
            fgColor: { argb: "FFF8FAFC" }, // Slate 50
          };
        }
        cell.font = { name: "Segoe UI", size: 10 };
        cell.alignment = { vertical: "middle" };
        cell.border = {
          bottom: { style: "thin", color: { argb: "FFE2E8F0" } },
        };
      });
    });
  }

  /**
   * Populates a worksheet with database records, applying transforms and formatting.
   */
  public populateWorksheetRows(
    sheetName: string,
    records: Record<string, any>[]
  ): void {
    this.appendWorksheetRows(sheetName, records, 0);
  }

  /**
   * Returns current data row count (excluding header row) for a given worksheet.
   */
  public getWorksheetRowCount(sheetName: string): number {
    const sheet = this.workbook.getWorksheet(sheetName);
    if (!sheet) return 0;
    return Math.max(0, sheet.rowCount - 1);
  }

  /**
   * Generates the binary Uint8Array buffer of the complete .xlsx file.
   */
  public async writeBuffer(): Promise<Uint8Array> {
    const buffer = await this.workbook.xlsx.writeBuffer();
    return new Uint8Array(buffer);
  }

  /**
   * Helper returning standard cell formatting per column type.
   */
  private getColumnStyle(format: string): Partial<ExcelJS.Style> {
    switch (format) {
      case "currency":
        return { numFmt: '"₹"#,##0.00' };
      case "date":
        return { numFmt: "yyyy-mm-dd" };
      case "datetime":
        return { numFmt: "yyyy-mm-dd hh:mm" };
      case "number":
        return { numFmt: "#,##0.0" };
      default:
        return {};
    }
  }
}

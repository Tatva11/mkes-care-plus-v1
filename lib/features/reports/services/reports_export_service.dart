import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/inventory_reports_model.dart';
import '../models/reports_filter_model.dart';

/// Service providing export capabilities (Excel-compatible CSV & Print-to-PDF HTML)
/// for MKES CARE+ Admin Reports without requiring external native dependencies.
class ReportsExportService {
  static final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd-MM-yyyy hh:mm a');

  /// Generates the complete Inventory Analytics report as an Excel-compatible CSV string.
  static String generateCsvContent(InventoryReportsData data,
      [AdminReportsFilter filter = const AdminReportsFilter()]) {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM for Microsoft Excel

    // 1. Header & Metadata
    buffer.writeln('"MKES CARE+ CLINICAL MANAGEMENT PLATFORM"');
    buffer.writeln('"INVENTORY & STOCK ANALYTICS REPORT"');
    buffer.writeln('"Generated At","${_dateFormat.format(DateTime.now())}"');
    buffer.writeln(
        '"Date Range Preset","${_cleanCsvValue(filter.datePresetLabel)}"');
    buffer.writeln(
        '"Department Filter","${_cleanCsvValue(filter.department.toUpperCase())}"');
    buffer.writeln();

    // 2. Executive Snapshot
    buffer.writeln('"=== EXECUTIVE INVENTORY SNAPSHOT ==="');
    buffer.writeln('"Metric","Value"');
    buffer.writeln('"Total Catalog Items","${data.totalCatalogItems}"');
    buffer.writeln('"Active Items","${data.activeItemsCount}"');
    buffer
        .writeln('"Total Stock Units","${data.totalUnits.toStringAsFixed(1)}"');
    buffer.writeln(
        '"Total Stock Valuation","${_cleanCsvValue(_currencyFormat.format(data.totalValuation))}"');
    buffer.writeln(
        '"Central Store Valuation","${_cleanCsvValue(_currencyFormat.format(data.centralValuation))}"');
    buffer.writeln(
        '"Eye Clinic Valuation","${_cleanCsvValue(_currencyFormat.format(data.eyeValuation))}"');
    buffer.writeln(
        '"Dental Clinic Valuation","${_cleanCsvValue(_currencyFormat.format(data.dentalValuation))}"');
    buffer.writeln('"Central Low Stock Items","${data.centralLowStockCount}"');
    buffer.writeln(
        '"Department Low Stock Items","${data.departmentLowStockCount}"');
    buffer.writeln('"Critical Stock-Outs","${data.stockOutCount}"');
    buffer.writeln('"Expired Batches","${data.expiredBatchesCount}"');
    buffer.writeln(
        '"Expired Stock Value Lost","${_cleanCsvValue(_currencyFormat.format(data.expiredValueLost))}"');
    buffer.writeln(
        '"Expiring in 30 Days (At-Risk Value)","${_cleanCsvValue(_currencyFormat.format(data.expiring30DaysValue))}"');
    buffer.writeln();

    // 3. Category Breakdown
    buffer.writeln('"=== CATEGORY VALUATION BREAKDOWN ==="');
    buffer.writeln(
        '"Category","Items Count","Total Units","Valuation (INR)","Share (%)"');
    for (final cat in data.categoryValuations) {
      buffer.writeln(
          '"${_cleanCsvValue(cat.category)}","${cat.itemCount}","${cat.totalUnits.toStringAsFixed(1)}","${cat.totalValuation.toStringAsFixed(2)}","${cat.percentage.toStringAsFixed(1)}%"');
    }
    buffer.writeln();

    // 4. Low-Stock & Reorder Priority List
    buffer.writeln('"=== LOW-STOCK & REORDER PRIORITIES ==="');
    buffer.writeln(
        '"Item Name","SKU","Location","Current Stock","Min Stock","Shortfall","Unit","Preferred Vendor","Vendor Phone","Last Price (INR)","Status"');
    for (final item in data.lowStockItems) {
      buffer.writeln(
          '"${_cleanCsvValue(item.itemName)}","${_cleanCsvValue(item.sku ?? '-')}","${_cleanCsvValue(item.location)}","${item.currentStock.toStringAsFixed(1)}","${item.minimumStock.toStringAsFixed(1)}","${item.shortfall.toStringAsFixed(1)}","${_cleanCsvValue(item.unit)}","${_cleanCsvValue(item.vendorName ?? '-')}","${_cleanCsvValue(item.vendorPhone ?? '-')}","${item.lastPrice?.toStringAsFixed(2) ?? '-'}","${item.isStockOut ? 'OUT OF STOCK' : 'LOW STOCK'}"');
    }
    buffer.writeln();

    // 5. Batch Expiry Traceability
    buffer.writeln('"=== BATCH EXPIRY & RISK TRACEABILITY ==="');
    buffer.writeln(
        '"Batch Number","Item Name","Category","Expiry Date","Days Remaining","Remaining Qty","Unit Price (INR)","Total Batch Value (INR)","Status"');
    for (final b in data.batchExpiryDetails) {
      final expStr = b.expiryDate != null
          ? DateFormat('dd-MM-yyyy').format(b.expiryDate!)
          : 'No Expiry';
      buffer.writeln(
          '"${_cleanCsvValue(b.batchNumber)}","${_cleanCsvValue(b.itemName)}","${_cleanCsvValue(b.category)}","$expStr","${b.daysRemaining ?? '-'}","${b.remainingQuantity.toStringAsFixed(1)}","${b.unitPrice.toStringAsFixed(2)}","${b.totalAmount.toStringAsFixed(2)}","${b.urgencyStatus.toUpperCase()}"');
    }
    buffer.writeln();

    // 6. Stock Movement Audit Ledger
    buffer.writeln('"=== STOCK MOVEMENT AUDIT LEDGER (SELECTED PERIOD) ==="');
    buffer.writeln(
        '"Timestamp","Item Name","Transaction Type","Quantity","Stock Before","Stock After","Reason","Performed By","Recipient / Patient","Remarks"');
    for (final tx in data.auditLedger) {
      buffer.writeln(
          '"${_dateFormat.format(tx.date)}","${_cleanCsvValue(tx.itemName)}","${tx.transactionType.toUpperCase()}","${tx.quantity.toStringAsFixed(1)}","${tx.stockBefore?.toStringAsFixed(1) ?? '-'}","${tx.stockAfter?.toStringAsFixed(1) ?? '-'}","${_cleanCsvValue(tx.reason ?? '-')}","${_cleanCsvValue(tx.performedByName ?? '-')}","${_cleanCsvValue(tx.recipientInfo ?? '-')}","${_cleanCsvValue(tx.remarks ?? '-')}"');
    }

    return buffer.toString();
  }

  /// Exports the complete Inventory Analytics report as an Excel-compatible CSV file.
  static Future<bool> exportInventoryToCsv({
    required InventoryReportsData data,
    AdminReportsFilter filter = const AdminReportsFilter(),
  }) async {
    final csv = generateCsvContent(data, filter);
    return _launchDataUri(
      content: csv,
      mimeType: 'text/csv',
      filename:
          'MKES_Inventory_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
    );
  }

  /// Generates a styled, printable HTML report string.
  static String generateHtmlContent(InventoryReportsData data,
      [AdminReportsFilter filter = const AdminReportsFilter()]) {
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final nowStr = _dateFormat.format(DateTime.now());

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>MKES CARE+ Inventory & Stock Report</title>
  <style>
    @media print {
      body { font-size: 11px; margin: 10mm; }
      .no-print { display: none; }
      .page-break { page-break-after: always; }
    }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; color: #1e293b; line-height: 1.4; padding: 24px; background: #fff; }
    .header { border-bottom: 2px solid #0d9488; padding-bottom: 12px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: flex-start; }
    .header h1 { margin: 0; color: #0d9488; font-size: 24px; font-weight: 700; }
    .header p { margin: 4px 0 0 0; color: #64748b; font-size: 12px; }
    .meta { font-size: 11px; color: #475569; text-align: right; }
    .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
    .kpi-card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px; background: #f8fafc; }
    .kpi-title { font-size: 11px; color: #64748b; text-transform: uppercase; font-weight: 600; margin-bottom: 4px; }
    .kpi-value { font-size: 20px; font-weight: 700; color: #0f172a; }
    .kpi-sub { font-size: 10px; color: #94a3b8; margin-top: 2px; }
    h2 { font-size: 15px; border-left: 4px solid #0d9488; padding-left: 8px; margin: 24px 0 10px 0; color: #0f172a; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 11px; }
    th { background: #f1f5f9; text-align: left; padding: 8px; border: 1px solid #e2e8f0; font-weight: 600; color: #334155; }
    td { padding: 7px 8px; border: 1px solid #e2e8f0; }
    tr:nth-child(even) { background: #f8fafc; }
    .badge-alert { background: #fee2e2; color: #b91c1c; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .badge-warn { background: #fef3c7; color: #d97706; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .badge-success { background: #dcfce7; color: #15803d; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .footer { text-align: center; margin-top: 30px; font-size: 10px; color: #94a3b8; border-top: 1px solid #e2e8f0; padding-top: 10px; }
    .print-btn { background: #0d9488; color: #fff; border: none; padding: 10px 18px; border-radius: 6px; font-weight: 600; cursor: pointer; font-size: 13px; }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <h1>MKES CARE+ Clinical Management Platform</h1>
      <p>Comprehensive Inventory, Stock Valuation & Movement Audit</p>
    </div>
    <div class="meta">
      <strong>Generated:</strong> $nowStr<br>
      <strong>Preset:</strong> ${filter.datePresetLabel}<br>
      <strong>Department:</strong> ${filter.department.toUpperCase()}<br>
      <div class="no-print" style="margin-top: 8px;">
        <button class="print-btn" onclick="window.print()">Print / Save as PDF</button>
      </div>
    </div>
  </div>

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-title">Total Stock Valuation</div>
      <div class="kpi-value">${currency.format(data.totalValuation)}</div>
      <div class="kpi-sub">Central: ${currency.format(data.centralValuation)}</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Total Catalog Items</div>
      <div class="kpi-value">${data.totalCatalogItems}</div>
      <div class="kpi-sub">${data.activeItemsCount} active SKUs • ${data.totalUnits.toInt()} units</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Low Stock & Stock-Outs</div>
      <div class="kpi-value" style="color: ${data.totalUrgentAlerts > 0 ? '#dc2626' : '#15803d'};">${data.lowStockItems.length}</div>
      <div class="kpi-sub">${data.stockOutCount} completely depleted</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Expired & At-Risk Value</div>
      <div class="kpi-value" style="color: ${data.totalAtRiskValue > 0 ? '#d97706' : '#15803d'};">${currency.format(data.totalAtRiskValue)}</div>
      <div class="kpi-sub">${data.expiredBatchesCount} expired batches (${currency.format(data.expiredValueLost)})</div>
    </div>
  </div>

  <h2>1. Stock Valuation by Category</h2>
  <table>
    <thead>
      <tr>
        <th>Category</th>
        <th>Items Count</th>
        <th>Total Units</th>
        <th>Valuation</th>
        <th>Share (%)</th>
      </tr>
    </thead>
    <tbody>
      ${data.categoryValuations.map((c) => '''
      <tr>
        <td><strong>${c.category}</strong></td>
        <td>${c.itemCount}</td>
        <td>${c.totalUnits.toStringAsFixed(1)}</td>
        <td>${currency.format(c.totalValuation)}</td>
        <td>${c.percentage.toStringAsFixed(1)}%</td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <h2>2. Low-Stock & Reorder Priorities (${data.lowStockItems.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Item Name</th>
        <th>SKU</th>
        <th>Location</th>
        <th>Current Stock</th>
        <th>Min Stock</th>
        <th>Shortfall</th>
        <th>Preferred Vendor</th>
        <th>Contact</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${data.lowStockItems.isEmpty ? '<tr><td colspan="9" style="text-align:center; color:#94a3b8;">All items are comfortably stocked above minimum thresholds.</td></tr>' : data.lowStockItems.map((i) => '''
      <tr>
        <td><strong>${i.itemName}</strong></td>
        <td>${i.sku ?? '-'}</td>
        <td>${i.location}</td>
        <td>${i.currentStock.toStringAsFixed(1)} ${i.unit}</td>
        <td>${i.minimumStock.toStringAsFixed(1)} ${i.unit}</td>
        <td style="color:#dc2626; font-weight:600;">+${i.shortfall.toStringAsFixed(1)}</td>
        <td>${i.vendorName ?? '-'}</td>
        <td>${i.vendorPhone ?? '-'}</td>
        <td><span class="${i.isStockOut ? 'badge-alert' : 'badge-warn'}">${i.isStockOut ? 'DEPLETED' : 'LOW STOCK'}</span></td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <div class="page-break"></div>

  <h2>3. Batch Expiry & Risk Traceability (${data.batchExpiryDetails.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Batch Number</th>
        <th>Item Name</th>
        <th>Category</th>
        <th>Expiry Date</th>
        <th>Days Remaining</th>
        <th>Remaining Units</th>
        <th>Unit Price</th>
        <th>Batch Value</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${data.batchExpiryDetails.isEmpty ? '<tr><td colspan="9" style="text-align:center; color:#94a3b8;">No expired or soon-to-expire batches identified.</td></tr>' : data.batchExpiryDetails.map((b) => '''
      <tr>
        <td><strong>${b.batchNumber}</strong></td>
        <td>${b.itemName}</td>
        <td>${b.category}</td>
        <td>${b.expiryDate != null ? DateFormat('dd-MM-yyyy').format(b.expiryDate!) : '-'}</td>
        <td>${b.daysRemaining != null ? (b.daysRemaining! < 0 ? '${b.daysRemaining!.abs()}d ago' : '${b.daysRemaining}d') : '-'}</td>
        <td>${b.remainingQuantity.toStringAsFixed(1)}</td>
        <td>${currency.format(b.unitPrice)}</td>
        <td><strong>${currency.format(b.totalAmount)}</strong></td>
        <td><span class="${b.isExpired ? 'badge-alert' : 'badge-warn'}">${b.urgencyStatus.toUpperCase()}</span></td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <h2>4. Stock Movement Audit Ledger (${data.auditLedger.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Timestamp</th>
        <th>Item Name</th>
        <th>Type</th>
        <th>Quantity</th>
        <th>Stock (Before &rarr; After)</th>
        <th>Reason</th>
        <th>Performed By</th>
        <th>Recipient</th>
      </tr>
    </thead>
    <tbody>
      ${data.auditLedger.isEmpty ? '<tr><td colspan="8" style="text-align:center; color:#94a3b8;">No stock transactions recorded in the selected period.</td></tr>' : data.auditLedger.map((tx) => '''
      <tr>
        <td>${DateFormat('dd-MM-yyyy hh:mm a').format(tx.date)}</td>
        <td><strong>${tx.itemName}</strong></td>
        <td><span class="${tx.transactionType.toLowerCase() == 'stock_in' ? 'badge-success' : 'badge-warn'}">${tx.transactionType.toUpperCase()}</span></td>
        <td>${tx.quantity.toStringAsFixed(1)}</td>
        <td>${tx.stockBefore?.toStringAsFixed(1) ?? '-'} &rarr; ${tx.stockAfter?.toStringAsFixed(1) ?? '-'}</td>
        <td>${tx.reason ?? '-'}</td>
        <td>${tx.performedByName ?? '-'}</td>
        <td>${tx.recipientInfo ?? '-'}</td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <div class="footer">
    MKES CARE+ Internal Confidential Document • Generated by Admin Reports System
  </div>
</body>
</html>
''';
  }

  /// Exports a styled, printable HTML report that triggers browser/OS Print to PDF.
  static Future<bool> exportInventoryToPrintableHtml({
    required InventoryReportsData data,
    AdminReportsFilter filter = const AdminReportsFilter(),
  }) async {
    final html = generateHtmlContent(data, filter);
    return _launchDataUri(
      content: html,
      mimeType: 'text/html',
      filename: 'MKES_Inventory_Report.html',
    );
  }

  /// Helper to launch Data URI in browser/web/desktop environment.
  static Future<bool> _launchDataUri({
    required String content,
    required String mimeType,
    required String filename,
  }) async {
    try {
      final base64Content = base64Encode(utf8.encode(content));
      final uri =
          Uri.parse('data:$mimeType;charset=utf-8;base64,$base64Content');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        // Fallback: launch as plain data string
        final plainUri = Uri.dataFromString(
          content,
          mimeType: mimeType,
          encoding: utf8,
        );
        return await launchUrl(plainUri);
      }
    } catch (e) {
      debugPrint('ReportsExportService error launching export: $e');
      return false;
    }
  }

  static String _cleanCsvValue(String value) {
    return value.replaceAll('"', '""');
  }
}

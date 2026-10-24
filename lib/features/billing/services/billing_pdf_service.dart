import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/billing_invoice_model.dart';
import 'pdf_platform_delivery.dart';

class BillingPdfService {
  /// Generates the raw PDF bytes for an invoice without writing to disk.
  Future<Uint8List> generateInvoicePdf(BillingInvoiceModel invoice) async {
    return generateInvoiceBytes(invoice);
  }

  /// Generates the raw PDF bytes for an invoice.
  static Future<Uint8List> generateInvoiceBytes(BillingInvoiceModel invoice) async {
    final pdf = _buildPdfDocument(invoice);
    return await pdf.save();
  }

  /// Generates and saves the PDF to local storage (native platforms) or downloads (web).
  /// Returns the saved file path on native platforms, or null on web.
  Future<String?> saveInvoicePdf(BillingInvoiceModel invoice) async {
    return generateAndSaveInvoicePdf(invoice);
  }

  /// Downloads, saves, or shares the invoice PDF depending on platform:
  /// - Web: downloads directly in browser via HTML Blob/AnchorElement
  /// - Android: saves to accessible storage, opens via system viewer/intent, shares safely
  /// - iOS: saves to documents, opens native share/save sheet
  /// - Desktop: saves to user Downloads/Documents and opens system viewer
  Future<bool> downloadOrShareInvoicePdf(BillingInvoiceModel invoice) async {
    final bytes = await generateInvoiceBytes(invoice);
    final filename = getSafeInvoiceFilename(invoice.invoiceNumber);
    return await deliverPdfBytes(bytes: bytes, filename: filename);
  }

  /// Opens platform print preview/dialog.
  Future<bool> printInvoicePdf(BillingInvoiceModel invoice) async {
    final bytes = await generateInvoiceBytes(invoice);
    final filename = getSafeInvoiceFilename(invoice.invoiceNumber);
    return await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: filename,
    );
  }

  /// Opens the PDF file with platform viewer.
  Future<bool> openPdf(String filePath) async {
    return await openPdfDocument(filePath);
  }

  /// Sanitized collision-safe filename.
  String getInvoiceFilename(String invoiceNumber) {
    return getSafeInvoiceFilename(invoiceNumber);
  }

  static String getSafeInvoiceFilename(String invoiceNumber) {
    final sanitizedNumber = invoiceNumber
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
        .trim();
    final safeNumber = sanitizedNumber.replaceAll('_', '').isEmpty
        ? 'Invoice_Generated'
        : sanitizedNumber;
    return 'Invoice_$safeNumber.pdf';
  }

  /// Generates a professional A4 PDF invoice and saves it locally.
  /// Returns the saved file path on native platforms, or null on web.
  static Future<String?> generateAndSaveInvoicePdf(BillingInvoiceModel invoice) async {
    final bytes = await generateInvoiceBytes(invoice);
    final filename = getSafeInvoiceFilename(invoice.invoiceNumber);
    return await savePdfLocally(bytes: bytes, filename: filename);
  }

  static pw.Document _buildPdfDocument(BillingInvoiceModel invoice) {
    final pdf = pw.Document();

    final isPaid = invoice.isPaid;
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(invoice.createdAt);
    final statusColor = isPaid
        ? PdfColors.green800
        : invoice.isPartiallyPaid
            ? PdfColors.orange800
            : PdfColors.red800;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MKES CARE+',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('005A9C'),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'CLINICAL MANAGEMENT PLATFORM',
                        style: pw.TextStyle(
                          fontSize: 8,
                          letterSpacing: 1.2,
                          color: PdfColors.grey700,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Department of ${invoice.department.toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: statusColor,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          isPaid
                              ? 'PAID'
                              : invoice.isPartiallyPaid
                                  ? 'PARTIALLY PAID'
                                  : 'PENDING',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'INVOICE: ${invoice.invoiceNumber}',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        'Date: $dateStr',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1.5, color: PdfColor.fromHex('005A9C')),
              pw.SizedBox(height: 12),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'MKES CARE+ Clinical System - This is a computer generated invoice',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // Patient details card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('F3F4F6'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BILL TO:',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        invoice.patientName ?? 'Walk-in Patient',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Patient ID: ${invoice.patientNumber ?? "-"}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                      if (invoice.patientMobile != null && invoice.patientMobile!.isNotEmpty)
                        pw.Text(
                          'Mobile: ${invoice.patientMobile}',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Department:',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        '${invoice.department.toUpperCase()} CLINIC',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('005A9C'),
                        ),
                      ),
                      if (invoice.billedBy != null && invoice.billedBy!.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Billed By: ${invoice.billedBy}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Itemized Services Table
            pw.Text(
              'ITEMIZED SERVICES & PROCEDURES',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('005A9C'),
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(5),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('E5E7EB')),
                  children: [
                    _tableHeader('#'),
                    _tableHeader('Service / Description'),
                    _tableHeader('Qty', align: pw.TextAlign.center),
                    _tableHeader('Unit Price (Rs)', align: pw.TextAlign.right),
                    _tableHeader('Total (Rs)', align: pw.TextAlign.right),
                  ],
                ),
                if (invoice.items.isEmpty)
                  pw.TableRow(
                    children: [
                      _tableCell('1', align: pw.TextAlign.center),
                      _tableCell('Clinical Consultation / Service'),
                      _tableCell('1', align: pw.TextAlign.center),
                      _tableCell(invoice.subtotal.toStringAsFixed(2), align: pw.TextAlign.right),
                      _tableCell(invoice.subtotal.toStringAsFixed(2), align: pw.TextAlign.right),
                    ],
                  )
                else
                  for (int i = 0; i < invoice.items.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: i % 2 == 1 ? PdfColor.fromHex('F9FAFB') : PdfColors.white,
                      ),
                      children: [
                        _tableCell('${i + 1}', align: pw.TextAlign.center),
                        _tableCell(invoice.items[i].serviceName),
                        _tableCell('${invoice.items[i].quantity}', align: pw.TextAlign.center),
                        _tableCell(invoice.items[i].unitPrice.toStringAsFixed(2), align: pw.TextAlign.right),
                        _tableCell(invoice.items[i].totalAmount.toStringAsFixed(2), align: pw.TextAlign.right),
                      ],
                    ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Financial Summary Block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Notes or terms
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (invoice.notes != null && invoice.notes!.trim().isNotEmpty) ...[
                        pw.Text(
                          'Notes / Remarks:',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          invoice.notes!.trim(),
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 8),
                      ],
                      pw.Text(
                        'Thank you for trusting MKES CARE+ with your healthcare.',
                        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                // Totals summary
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('F9FAFB'),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      children: [
                        _summaryRow('Subtotal:', 'Rs. ${invoice.subtotal.toStringAsFixed(2)}'),
                        if (invoice.discount > 0)
                          _summaryRow(
                            'Discount:',
                            '- Rs. ${invoice.discount.toStringAsFixed(2)}',
                            color: PdfColors.green800,
                          ),
                        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                        _summaryRow(
                          'Total Amount:',
                          'Rs. ${invoice.totalAmount.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        _summaryRow(
                          'Amount Paid:',
                          'Rs. ${invoice.amountPaid.toStringAsFixed(2)}',
                          color: PdfColor.fromHex('005A9C'),
                        ),
                        pw.Divider(thickness: 1, color: PdfColors.grey400),
                        _summaryRow(
                          'Balance Due:',
                          'Rs. ${invoice.remainingAmount.toStringAsFixed(2)}',
                          isBold: true,
                          color: invoice.remainingAmount > 0 ? PdfColors.red800 : PdfColors.green800,
                          fontSize: 11,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Payment History Table (if payments recorded)
            if (invoice.payments.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'PAYMENT TRANSACTIONS (${invoice.payments.length})',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('005A9C'),
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('E5E7EB')),
                    children: [
                      _tableHeader('Payment Date'),
                      _tableHeader('Mode'),
                      _tableHeader('Reference / Notes'),
                      _tableHeader('Amount (Rs)', align: pw.TextAlign.right),
                    ],
                  ),
                  for (final p in invoice.payments)
                    pw.TableRow(
                      children: [
                        _tableCell(
                          p.paidAt != null
                              ? DateFormat('dd/MM/yyyy hh:mm a').format(p.paidAt!)
                              : '-',
                        ),
                        _tableCell(p.paymentMode.toUpperCase()),
                        _tableCell(p.paymentReference ?? p.notes ?? '-'),
                        _tableCell('Rs. ${p.amount.toStringAsFixed(2)}', align: pw.TextAlign.right),
                      ],
                    ),
                ],
              ),
            ],
          ];
        },
      ),
    );
    return pdf;
  }

  /// Attempts to open the generated PDF file using the platform's default viewer.
  /// Accepts either a file path [String] or any object with a `.path` property.
  static Future<bool> openPdfFile(dynamic file) async {
    if (file == null) return false;
    final path = file is String ? file : (file as dynamic).path.toString();
    return await openPdfDocument(path);
  }

  static pw.Widget _tableHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    PdfColor? color,
    double fontSize = 9,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

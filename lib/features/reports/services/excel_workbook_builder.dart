import 'dart:convert';
import 'dart:typed_data';

import 'excel_workbook_schema.dart';

/// In-memory OpenXML (.xlsx) builder for MKES CARE+ Master Workbook.
///
/// Implements the ISO/IEC 29500 (Office Open XML) standard with zero external native dependencies.
/// Generates a valid .xlsx package containing all 21 normalized worksheets with
/// frozen header rows, styled column widths, and formatting rules.
class ExcelWorkbookBuilder {
  ExcelWorkbookBuilder({
    this.clinicName = 'MKES CARE+ Clinical Management Platform',
  });

  final String clinicName;

  /// Builds a complete .xlsx binary buffer containing all 21 normalized worksheets.
  ///
  /// [recordsByWorksheet] is an optional map of worksheet name to list of row maps.
  /// If omitted, generates the formatted master workbook template with frozen header rows.
  Uint8List buildWorkbook({
    Map<String, List<Map<String, dynamic>>> recordsByWorksheet = const {},
  }) {
    final zipWriter = _SimpleZipWriter();
    final worksheets = ExcelWorkbookSchema.worksheets;

    // 1. [Content_Types].xml
    final contentTypesXml = _generateContentTypesXml(worksheets.length);
    zipWriter.addFile('[Content_Types].xml', utf8.encode(contentTypesXml));

    // 2. _rels/.rels
    final rootRelsXml = _generateRootRelsXml();
    zipWriter.addFile('_rels/.rels', utf8.encode(rootRelsXml));

    // 3. xl/workbook.xml
    final workbookXml = _generateWorkbookXml(worksheets);
    zipWriter.addFile('xl/workbook.xml', utf8.encode(workbookXml));

    // 4. xl/_rels/workbook.xml.rels
    final workbookRelsXml = _generateWorkbookRelsXml(worksheets.length);
    zipWriter.addFile('xl/_rels/workbook.xml.rels', utf8.encode(workbookRelsXml));

    // 5. xl/styles.xml
    final stylesXml = _generateStylesXml();
    zipWriter.addFile('xl/styles.xml', utf8.encode(stylesXml));

    // 6. xl/worksheets/sheet1.xml .. sheetN.xml
    for (int i = 0; i < worksheets.length; i++) {
      final sheetSpec = worksheets[i];
      final rows = recordsByWorksheet[sheetSpec.name] ?? const [];
      final sheetXml = _generateWorksheetXml(sheetSpec, rows);
      zipWriter.addFile('xl/worksheets/sheet${i + 1}.xml', utf8.encode(sheetXml));
    }

    return zipWriter.finalize();
  }

  // ── XML GENERATORS ────────────────────────────────────────────────────────

  String _generateContentTypesXml(int sheetCount) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    buffer.write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n');
    buffer.write('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n');
    buffer.write('  <Default Extension="xml" ContentType="application/xml"/>\n');
    buffer.write('  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\n');
    buffer.write('  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\n');

    for (int i = 1; i <= sheetCount; i++) {
      buffer.write('  <Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\n');
    }

    buffer.write('</Types>');
    return buffer.toString();
  }

  String _generateRootRelsXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
  }

  String _generateWorkbookXml(List<ExcelWorksheetSpec> worksheets) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    buffer.write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\n');
    buffer.write('  <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="24000" windowHeight="12000"/></bookViews>\n');
    buffer.write('  <sheets>\n');

    for (int i = 0; i < worksheets.length; i++) {
      final sheet = worksheets[i];
      final sheetId = i + 1;
      final rId = 'rId$sheetId';
      buffer.write('    <sheet name="${_escapeXml(sheet.name)}" sheetId="$sheetId" r:id="$rId"/>\n');
    }

    buffer.write('  </sheets>\n');
    buffer.write('</workbook>');
    return buffer.toString();
  }

  String _generateWorkbookRelsXml(int sheetCount) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    buffer.write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n');

    for (int i = 1; i <= sheetCount; i++) {
      buffer.write('  <Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>\n');
    }

    final stylesId = 'rId${sheetCount + 1}';
    buffer.write('  <Relationship Id="$stylesId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\n');
    buffer.write('</Relationships>');
    return buffer.toString();
  }

  String _generateStylesXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="4">
    <numFmt numFmtId="164" formatCode="&quot;₹&quot;#,##0.00"/>
    <numFmt numFmtId="165" formatCode="yyyy-mm-dd"/>
    <numFmt numFmtId="166" formatCode="yyyy-mm-dd hh:mm"/>
    <numFmt numFmtId="167" formatCode="#,##0.0"/>
  </numFmts>
  <fonts count="2">
    <font><sz val="10"/><color rgb="FF1E293B"/><name val="Segoe UI"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Segoe UI"/></font>
  </fonts>
  <fills count="4">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF0D9488"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFC"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/></border>
    <border>
      <left style="thin"><color rgb="FFE2E8F0"/></left>
      <right style="thin"><color rgb="FFE2E8F0"/></right>
      <top style="thin"><color rgb="FFE2E8F0"/></top>
      <bottom style="thin"><color rgb="FFE2E8F0"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="6">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="left" vertical="center" wrapText="1"/>
    </xf>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="167" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
  </cellXfs>
</styleSheet>''';
  }

  String _generateWorksheetXml(ExcelWorksheetSpec sheet, List<Map<String, dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    buffer.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n');

    // 1. Frozen top header row pane
    buffer.write('  <sheetViews>\n');
    buffer.write('    <sheetView tabSelected="1" workbookViewId="0">\n');
    buffer.write('      <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>\n');
    buffer.write('    </sheetView>\n');
    buffer.write('  </sheetViews>\n');

    // 2. Column widths
    buffer.write('  <cols>\n');
    for (int c = 0; c < sheet.columns.length; c++) {
      final col = sheet.columns[c];
      final colIdx = c + 1;
      buffer.write('    <col min="$colIdx" max="$colIdx" width="${col.width}" customWidth="1"/>\n');
    }
    buffer.write('  </cols>\n');

    // 3. Sheet Data
    buffer.write('  <sheetData>\n');

    // Row 1: Headers (style index 1 = bold white, teal fill)
    buffer.write('    <row r="1" ht="28" customHeight="1">\n');
    for (int c = 0; c < sheet.columns.length; c++) {
      final col = sheet.columns[c];
      final cellRef = '${_colLetter(c + 1)}1';
      buffer.write('      <c r="$cellRef" t="inlineStr" s="1"><is><t>${_escapeXml(col.header)}</t></is></c>\n');
    }
    buffer.write('    </row>\n');

    // Data rows
    for (int r = 0; r < rows.length; r++) {
      final rowNum = r + 2;
      final record = rows[r];
      buffer.write('    <row r="$rowNum" ht="22" customHeight="1">\n');

      for (int c = 0; c < sheet.columns.length; c++) {
        final col = sheet.columns[c];
        final cellRef = '${_colLetter(c + 1)}$rowNum';

        // Redaction enforcement: ensure salary is NEVER written
        if (sheet.sensitiveExcludedFields.contains(col.sourceField) ||
            col.sourceField.toLowerCase().contains('salary')) {
          buffer.write('      <c r="$cellRef" t="inlineStr" s="0"><is><t>-</t></is></c>\n');
          continue;
        }

        final rawValue = record[col.sourceField];
        final cellContent = _formatCellValue(col, rawValue);

        if (cellContent.isNumeric) {
          final styleIndex = col.type == ExcelColumnType.currency ? 2 : 5;
          buffer.write('      <c r="$cellRef" s="$styleIndex"><v>${cellContent.text}</v></c>\n');
        } else {
          final styleIndex = col.type == ExcelColumnType.date
              ? 3
              : col.type == ExcelColumnType.datetime
                  ? 4
                  : 0;
          buffer.write('      <c r="$cellRef" t="inlineStr" s="$styleIndex"><is><t>${_escapeXml(cellContent.text)}</t></is></c>\n');
        }
      }

      buffer.write('    </row>\n');
    }

    buffer.write('  </sheetData>\n');
    buffer.write('</worksheet>');
    return buffer.toString();
  }

  _CellContent _formatCellValue(ExcelColumnSpec col, dynamic value) {
    if (value == null) {
      return _CellContent(text: col.defaultValue.toString(), isNumeric: false);
    }

    switch (col.type) {
      case ExcelColumnType.number:
      case ExcelColumnType.currency:
        final numVal = num.tryParse(value.toString());
        if (numVal != null) {
          return _CellContent(text: numVal.toString(), isNumeric: true);
        }
        return const _CellContent(text: '0', isNumeric: true);

      case ExcelColumnType.boolean:
        final boolVal = value == true || value.toString().toLowerCase() == 'true';
        return _CellContent(text: boolVal ? 'YES' : 'NO', isNumeric: false);

      case ExcelColumnType.date:
        final str = value.toString();
        final dateOnly = str.contains('T') ? str.split('T').first : str;
        return _CellContent(text: dateOnly.isNotEmpty ? dateOnly : '-', isNumeric: false);

      case ExcelColumnType.datetime:
      case ExcelColumnType.text:
        if (value is Map || value is List) {
          try {
            final encoded = jsonEncode(value);
            if (encoded == '{}' || encoded == '[]') {
              return const _CellContent(text: '-', isNumeric: false);
            }
            return _CellContent(
              text: sanitizeSpreadsheetString(encoded),
              isNumeric: false,
            );
          } catch (_) {
            return _CellContent(
              text: sanitizeSpreadsheetString(value.toString()),
              isNumeric: false,
            );
          }
        }
        final str = value.toString();
        if (str.isEmpty) {
          return _CellContent(text: col.defaultValue.toString(), isNumeric: false);
        }
        return _CellContent(
          text: sanitizeSpreadsheetString(str),
          isNumeric: false,
        );
    }
  }

  /// Sanitizes untrusted text strings to prevent spreadsheet formula injection.
  ///
  /// If a string (or the string after stripping leading whitespace and control characters)
  /// begins with '=', '+', '-', '@', tab, or carriage return, prepends an apostrophe (').
  /// This forces spreadsheet applications to treat the cell purely as literal text.
  ///
  /// Legitimate numeric database values (handled via [ExcelColumnType.number] and
  /// [ExcelColumnType.currency]) are never converted into strings or prepended with an apostrophe.
  static String sanitizeSpreadsheetString(String val) {
    if (val.isEmpty) return val;
    // Check if raw string begins with tab or carriage return
    if (val.startsWith('\t') || val.startsWith('\r')) {
      return "'$val";
    }
    // Check if trimmed-left string begins with formula trigger chars
    final trimmedLeading = val.replaceFirst(RegExp(r'^[\s\x00-\x1F]+'), '');
    if (trimmedLeading.isNotEmpty) {
      final firstChar = trimmedLeading[0];
      if (firstChar == '=' ||
          firstChar == '+' ||
          firstChar == '-' ||
          firstChar == '@' ||
          firstChar == '\t' ||
          firstChar == '\r') {
        return "'$val";
      }
    }
    return val;
  }

  static String _colLetter(int index) {
    int quotient = index;
    String name = '';
    while (quotient > 0) {
      final rem = (quotient - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      quotient = (quotient - 1) ~/ 26;
    }
    return name;
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _CellContent {
  const _CellContent({required this.text, required this.isNumeric});
  final String text;
  final bool isNumeric;
}

// ─────────────────────────────────────────────────────────────────────────────
// Zero-Dependency In-Memory ZIP Archive Writer (Standard Store Method 0)
// Compatible with all ISO/IEC 29500 XLSX parsers (Excel, Numbers, LibreOffice).
// ─────────────────────────────────────────────────────────────────────────────
class _SimpleZipWriter {
  final List<_ZipEntry> _entries = [];

  void addFile(String name, List<int> bytes) {
    _entries.add(_ZipEntry(name: name, data: Uint8List.fromList(bytes)));
  }

  Uint8List finalize() {
    final centralDirBytes = <int>[];
    final fileDataBytes = <int>[];
    int currentOffset = 0;

    for (final entry in _entries) {
      final crc = _crc32(entry.data);
      final nameBytes = utf8.encode(entry.name);

      // Local Header
      final localHeader = ByteData(30);
      localHeader.setUint32(0, 0x04034b50, Endian.little); // Local file header signature
      localHeader.setUint16(4, 20, Endian.little); // Version needed (2.0)
      localHeader.setUint16(6, 0, Endian.little); // General purpose bit flag
      localHeader.setUint16(8, 0, Endian.little); // Compression method (0 = Stored)
      localHeader.setUint16(10, 0, Endian.little); // File last mod time
      localHeader.setUint16(12, 0, Endian.little); // File last mod date
      localHeader.setUint32(14, crc, Endian.little); // CRC-32
      localHeader.setUint32(18, entry.data.length, Endian.little); // Compressed size
      localHeader.setUint32(22, entry.data.length, Endian.little); // Uncompressed size
      localHeader.setUint16(26, nameBytes.length, Endian.little); // File name length
      localHeader.setUint16(28, 0, Endian.little); // Extra field length

      fileDataBytes.addAll(localHeader.buffer.asUint8List());
      fileDataBytes.addAll(nameBytes);
      fileDataBytes.addAll(entry.data);

      // Central Directory Header
      final cdHeader = ByteData(46);
      cdHeader.setUint32(0, 0x02014b50, Endian.little); // Central directory file header signature
      cdHeader.setUint16(4, 20, Endian.little); // Version made by
      cdHeader.setUint16(6, 20, Endian.little); // Version needed to extract
      cdHeader.setUint16(8, 0, Endian.little); // General purpose bit flag
      cdHeader.setUint16(10, 0, Endian.little); // Compression method (0 = Stored)
      cdHeader.setUint16(12, 0, Endian.little); // File last mod time
      cdHeader.setUint16(14, 0, Endian.little); // File last mod date
      cdHeader.setUint32(16, crc, Endian.little); // CRC-32
      cdHeader.setUint32(20, entry.data.length, Endian.little); // Compressed size
      cdHeader.setUint32(24, entry.data.length, Endian.little); // Uncompressed size
      cdHeader.setUint16(28, nameBytes.length, Endian.little); // File name length
      cdHeader.setUint16(30, 0, Endian.little); // Extra field length
      cdHeader.setUint16(32, 0, Endian.little); // File comment length
      cdHeader.setUint16(34, 0, Endian.little); // Disk number start
      cdHeader.setUint16(36, 0, Endian.little); // Internal file attributes
      cdHeader.setUint32(38, 0, Endian.little); // External file attributes
      cdHeader.setUint32(42, currentOffset, Endian.little); // Relative offset of local header

      centralDirBytes.addAll(cdHeader.buffer.asUint8List());
      centralDirBytes.addAll(nameBytes);

      currentOffset += 30 + nameBytes.length + entry.data.length;
    }

    final centralDirOffset = fileDataBytes.length;
    final centralDirSize = centralDirBytes.length;

    // End of Central Directory Record
    final eocd = ByteData(22);
    eocd.setUint32(0, 0x06054b50, Endian.little); // End of central dir signature
    eocd.setUint16(4, 0, Endian.little); // Number of this disk
    eocd.setUint16(6, 0, Endian.little); // Disk where central directory starts
    eocd.setUint16(8, _entries.length, Endian.little); // Number of central directory records on this disk
    eocd.setUint16(10, _entries.length, Endian.little); // Total number of central directory records
    eocd.setUint32(12, centralDirSize, Endian.little); // Size of central directory
    eocd.setUint32(16, centralDirOffset, Endian.little); // Offset of start of central directory
    eocd.setUint16(20, 0, Endian.little); // Comment length

    final fullPackage = Uint8List(fileDataBytes.length + centralDirSize + 22);
    fullPackage.setRange(0, fileDataBytes.length, fileDataBytes);
    fullPackage.setRange(fileDataBytes.length, fileDataBytes.length + centralDirSize, centralDirBytes);
    fullPackage.setRange(fileDataBytes.length + centralDirSize, fullPackage.length, eocd.buffer.asUint8List());

    return fullPackage;
  }

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (int b in bytes) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xEDB88320 : 0);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _ZipEntry {
  _ZipEntry({required this.name, required this.data});
  final String name;
  final Uint8List data;
}

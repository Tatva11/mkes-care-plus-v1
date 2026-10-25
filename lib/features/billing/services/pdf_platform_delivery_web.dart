// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Flutter Web implementation of invoice PDF delivery.
/// Uses browser Blob and AnchorElement to initiate a real, native browser download
/// without invoking any unimplemented native method channels (e.g. Printing.sharePdf).
Future<bool> deliverPdfBytes({
  required Uint8List bytes,
  required String filename,
}) async {
  try {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);

    // Clean up the object URL after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });

    return true;
  } catch (e) {
    throw Exception('Web browser download failed: $e');
  }
}

/// On web, saving locally initiates a browser download and returns null.
Future<String?> savePdfLocally({
  required Uint8List bytes,
  required String filename,
}) async {
  await deliverPdfBytes(bytes: bytes, filename: filename);
  return null;
}

/// On web, direct file path opening is not supported.
Future<bool> openPdfDocument(String filePath) async {
  return false;
}

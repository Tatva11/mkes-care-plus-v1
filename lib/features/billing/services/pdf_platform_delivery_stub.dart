import 'dart:typed_data';

/// Abstract or stub platform delivery for invoice PDF bytes.
Future<bool> deliverPdfBytes({
  required Uint8List bytes,
  required String filename,
}) async {
  throw UnsupportedError('Cannot deliver PDF bytes without a platform implementation.');
}

/// Abstract or stub local saving of invoice PDF bytes.
Future<String?> savePdfLocally({
  required Uint8List bytes,
  required String filename,
}) async {
  throw UnsupportedError('Cannot save PDF bytes without a platform implementation.');
}

/// Abstract or stub PDF document opening.
Future<bool> openPdfDocument(String filePath) async {
  return false;
}

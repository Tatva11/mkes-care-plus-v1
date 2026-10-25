import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

Future<File> _resolveAndWriteFile({
  required Uint8List bytes,
  required String filename,
}) async {
  String? chosenDirPath;

  if (Platform.isAndroid) {
    try {
      final externalDirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (externalDirs != null && externalDirs.isNotEmpty) {
        chosenDirPath = externalDirs.first.path;
      }
    } catch (_) {}

    if (chosenDirPath == null) {
      try {
        final extCache = await getExternalCacheDirectories();
        if (extCache != null && extCache.isNotEmpty) {
          chosenDirPath = extCache.first.path;
        }
      } catch (_) {}
    }

    if (chosenDirPath == null) {
      final docsDir = await getApplicationDocumentsDirectory();
      chosenDirPath = docsDir.path;
    }
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        chosenDirPath = downloadsDir.path;
      }
    } catch (_) {}

    if (chosenDirPath == null) {
      final docsDir = await getApplicationDocumentsDirectory();
      chosenDirPath = docsDir.path;
    }
  } else {
    final docsDir = await getApplicationDocumentsDirectory();
    chosenDirPath = docsDir.path;
  }

  final targetFile = File('$chosenDirPath/$filename');
  await targetFile.writeAsBytes(bytes, flush: true);
  debugPrint('PDF saved successfully to: ${targetFile.path}');
  return targetFile;
}

/// Native (Android, iOS, Desktop) implementation of invoice PDF delivery.
Future<bool> deliverPdfBytes({
  required Uint8List bytes,
  required String filename,
}) async {
  File? targetFile;

  try {
    targetFile = await _resolveAndWriteFile(bytes: bytes, filename: filename);

    // 2. Open or Share the saved file via platform-specific intent
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final openResult = await OpenFilex.open(
          targetFile.path,
          type: 'application/pdf',
        );

        if (openResult.type == ResultType.done) {
          return true;
        }
      } catch (openError) {
        debugPrint('OpenFilex error on mobile: $openError');
      }

      // Fallback: try Printing.sharePdf defensively
      try {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        return true;
      } on MissingPluginException catch (mpe) {
        debugPrint('Printing.sharePdf MissingPluginException: $mpe. File is saved at ${targetFile.path}');
        return true;
      } on PlatformException catch (pe) {
        debugPrint('Printing.sharePdf PlatformException: $pe. File is saved at ${targetFile.path}');
        return true;
      } catch (e) {
        debugPrint('Printing.sharePdf general error: $e');
        return true;
      }
    } else {
      // Desktop: Open with system default viewer
      try {
        await OpenFilex.open(targetFile.path);
      } catch (e) {
        debugPrint('Desktop OpenFilex error: $e');
      }
      return true;
    }
  } catch (e) {
    debugPrint('Native deliverPdfBytes error: $e');
    try {
      final tempDir = await getTemporaryDirectory();
      final fallbackFile = File('${tempDir.path}/$filename');
      await fallbackFile.writeAsBytes(bytes, flush: true);
      try {
        await OpenFilex.open(fallbackFile.path, type: 'application/pdf');
      } catch (_) {}
      return true;
    } catch (fallbackError) {
      throw Exception('Failed to save or deliver PDF: $e (Fallback: $fallbackError)');
    }
  }
}

/// Native implementation of saving PDF locally and returning the file path.
Future<String?> savePdfLocally({
  required Uint8List bytes,
  required String filename,
}) async {
  try {
    final file = await _resolveAndWriteFile(bytes: bytes, filename: filename);
    return file.path;
  } catch (e) {
    debugPrint('Native savePdfLocally error: $e');
    final tempDir = await getTemporaryDirectory();
    final fallbackFile = File('${tempDir.path}/$filename');
    await fallbackFile.writeAsBytes(bytes, flush: true);
    return fallbackFile.path;
  }
}

/// Native implementation of opening a PDF file path.
Future<bool> openPdfDocument(String filePath) async {
  try {
    final result = await OpenFilex.open(filePath, type: 'application/pdf');
    return result.type == ResultType.done;
  } catch (e) {
    debugPrint('openPdfDocument error: $e');
    return false;
  }
}

// lib/features/reports/widgets/excel_sync_manager_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────
// Admin Dialog for Central Excel Master Workbook Synchronization (Sprint 9.4).
// Allows administrators to:
// - View the currently active workbook version and published timestamp
// - Monitor pending change-capture outbox mutations
// - Trigger on-demand 5-minute incremental sync with no-op detection
// - Download the authoritative active .xlsx workbook
// - Run a manual full historical export baseline
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/reports_provider.dart';
import '../services/excel_workbook_schema.dart';

class ExcelSyncManagerDialog extends ConsumerStatefulWidget {
  const ExcelSyncManagerDialog({super.key});

  @override
  ConsumerState<ExcelSyncManagerDialog> createState() =>
      _ExcelSyncManagerDialogState();
}

class _ExcelSyncManagerDialogState
    extends ConsumerState<ExcelSyncManagerDialog> {
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isError = false;
  String _selectedWorksheet = 'Stock_Transactions';
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto-refresh sync state, active version, and outbox count every 15 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_isProcessing) {
        ref.invalidate(activeExcelSyncVersionProvider);
        ref.invalidate(excelPendingOutboxCountProvider);
        ref.invalidate(latestExcelSyncStateProvider);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleDownloadSelectedWorksheet() async {
    final targetSheet = _selectedWorksheet;
    final expectedFileName = 'MKES_CARE_Plus_$targetSheet.xlsx';

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Preparing single worksheet "$expectedFileName"...';
      _isError = false;
    });

    final service = ref.read(excelHistoricalExportServiceProvider);

    try {
      final signedUrl = await service.getSingleWorksheetSignedUrl(targetSheet);
      final uri = Uri.parse(signedUrl);

      bool launched = false;
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;

      if (launched) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Download initiated for "$expectedFileName". Check your notification bar or device Downloads folder.';
          _isError = false;
        });
      } else {
        // Fallback: download bytes directly
        final bytes = await service.downloadSingleWorksheet(targetSheet);
        if (!mounted) return;
        final kb = (bytes.length / 1024).toStringAsFixed(1);
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Generated "$expectedFileName" ($kb KB). Single worksheet download ready.';
          _isError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = e
            .toString()
            .replaceAll('Exception:', '')
            .replaceAll('StateError:', '')
            .trim();
        _isError = true;
      });
    }
  }

  Future<void> _handleIncrementalSync() async {
    final activeVersion = ref.read(activeExcelSyncVersionProvider).valueOrNull;
    if (activeVersion == null) {
      setState(() {
        _statusMessage =
            'No baseline workbook published yet. Please run "Run Full Historical Export" first to initialize Version 1.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Running incremental sync...';
      _isError = false;
    });

    final service = ref.read(excelHistoricalExportServiceProvider);
    final result = await service.triggerIncrementalSync(syncType: 'manual');

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      if (result.isNoOp) {
        _statusMessage =
            'Workbook is already up-to-date. Zero pending database changes.';
        _isError = false;
      } else if (result.isAlreadyRunning) {
        _statusMessage =
            'Another synchronization worker is currently running. Please wait.';
        _isError = false;
      } else if (result.isSuccess) {
        _statusMessage =
            'Synced successfully! Version #${result.versionNumber ?? 1} active with ${result.totalRecords} records (${result.eventsProcessed} events processed).';
        _isError = false;
      } else {
        _statusMessage =
            result.errorMessage ?? 'Incremental synchronization failed.';
        _isError = true;
      }
    });

    // Invalidate providers to refresh active version and outbox counts
    ref.invalidate(activeExcelSyncVersionProvider);
    ref.invalidate(excelPendingOutboxCountProvider);
    ref.invalidate(latestExcelSyncStateProvider);
  }

  Future<void> _handleDownloadActiveWorkbook() async {
    final activeVersion = ref.read(activeExcelSyncVersionProvider).valueOrNull;
    if (activeVersion == null) {
      setState(() {
        _statusMessage =
            'No active workbook published yet. Tap "Full Export" to initialize the baseline first.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Requesting active master workbook download...';
      _isError = false;
    });

    final service = ref.read(excelHistoricalExportServiceProvider);
    try {
      final signedUrl = await service.getActiveWorkbookSignedUrl();
      final uri = Uri.parse(signedUrl);

      bool launched = false;
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;

      if (launched) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Download started! Saved to your device "Downloads" folder (or PC browser Downloads if using web).';
          _isError = false;
        });
      } else {
        // Fallback: download bytes directly
        final bytes = await service.downloadActiveWorkbook();
        if (!mounted) return;
        final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(2);
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Workbook retrieved ($mb MB). Stored in clinic cloud storage.';
          _isError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = e
            .toString()
            .replaceAll('Exception:', '')
            .replaceAll('StateError:', '')
            .trim();
        _isError = true;
      });
    }
  }

  Future<void> _handleHistoricalExport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run Full Historical Baseline?'),
        content: const Text(
          'This will query all 21 normalized worksheets from the database and publish a fresh baseline version to storage. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Run Full Export'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Building full 21-sheet historical baseline...';
      _isError = false;
    });

    final service = ref.read(excelHistoricalExportServiceProvider);
    final result = await service.triggerServerHistoricalExport();

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      if (result.success) {
        _statusMessage =
            'Historical baseline exported successfully! ${result.totalRecords} total records across 21 worksheets.';
        _isError = false;
      } else {
        _statusMessage =
            result.errorMessage ?? 'Historical baseline export failed.';
        _isError = true;
      }
    });

    ref.invalidate(activeExcelSyncVersionProvider);
    ref.invalidate(excelPendingOutboxCountProvider);
    ref.invalidate(latestExcelSyncStateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final activeVersionAsync = ref.watch(activeExcelSyncVersionProvider);
    final outboxCountAsync = ref.watch(excelPendingOutboxCountProvider);
    final latestSyncAsync = ref.watch(latestExcelSyncStateProvider);
    final mediaQuery = MediaQuery.of(context);
    final maxDialogHeight = mediaQuery.size.height * 0.85;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: maxDialogHeight,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cloud_sync_rounded,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Central Excel Synchronization',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Master 21-worksheet workbook synchronization',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Active Version Information Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.15)),
                ),
                child: activeVersionAsync.when(
                  data: (activeVersion) {
                    if (activeVersion == null) {
                      return Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: AppColors.outline, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'No active version published yet. Click "Run Full Historical Export" to initialize baseline.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Colors.green, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Version #${activeVersion.versionNumber} ACTIVE',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${activeVersion.fileSizeMegabytes.toStringAsFixed(2)} MB',
                              style: TextStyle(
                                color: AppColors.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Total Records: ${activeVersion.totalRecords} across 21 worksheets',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Published: ${activeVersion.publishedAt.toLocal().toString().split('.')[0]}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.outline,
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  error: (e, _) => Text(
                    'Failed to read active version: $e',
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Outbox & Real Sync State Summary
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Changes',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.outline),
                                ),
                                outboxCountAsync.when(
                                  data: (count) => Text(
                                    '$count mutation${count == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: count > 0
                                          ? Colors.orange.shade800
                                          : Colors.green,
                                    ),
                                  ),
                                  loading: () => const Text('...',
                                      style: TextStyle(fontSize: 12)),
                                  error: (_, __) => const Text('0',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.history_toggle_off_rounded,
                              color: AppColors.secondary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Last Sync Run',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.outline),
                                ),
                                latestSyncAsync.when(
                                  data: (syncState) {
                                    if (syncState == null) {
                                      return const Text(
                                        'Never',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    }
                                    final time = syncState.completedAt ?? syncState.startedAt;
                                    final hh = time.toLocal().hour.toString().padLeft(2, '0');
                                    final mm = time.toLocal().minute.toString().padLeft(2, '0');
                                    return Text(
                                      '${syncState.status.toUpperCase()} ($hh:$mm)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: syncState.isSuccess
                                            ? Colors.green
                                            : (syncState.isFailed ? AppColors.error : Colors.orange),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  },
                                  loading: () => const Text('...',
                                      style: TextStyle(fontSize: 12)),
                                  error: (_, __) => const Text('—',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status / Feedback Area
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? AppColors.errorContainer.withValues(alpha: 0.4)
                        : AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isError
                          ? AppColors.error.withValues(alpha: 0.3)
                          : AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isProcessing) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
                        Icon(
                          _isError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color:
                              _isError ? AppColors.error : AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _isError
                                ? AppColors.error
                                : AppColors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons - Dynamic based on active baseline state
              Builder(
                builder: (context) {
                  final hasActiveBaseline =
                      activeVersionAsync.valueOrNull != null;

                  if (!hasActiveBaseline) {
                    // When no baseline exists, make "Run Full Historical Export" the primary call-to-action
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.history_rounded, size: 20),
                                label: const Text(
                                  'Run Full Historical Export (Initialize Baseline)',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                onPressed: _isProcessing
                                    ? null
                                    : _handleHistoricalExport,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.sync_rounded, size: 18),
                                label: const Text('Sync Now (Incremental)'),
                                onPressed: _isProcessing
                                    ? null
                                    : () {
                                        setState(() {
                                          _statusMessage =
                                              'No baseline workbook published yet. Please run "Full Historical Export" first to initialize Version 1.';
                                          _isError = true;
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  // Active baseline exists: normal operation
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('Sync Now (Incremental)'),
                          onPressed:
                              _isProcessing ? null : _handleIncrementalSync,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download Active (.xlsx)'),
                          onPressed: _isProcessing
                              ? null
                              : _handleDownloadActiveWorkbook,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text('Run Full Historical Re-Export'),
                          onPressed: _isProcessing
                              ? null
                              : _handleHistoricalExport,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // Individual Worksheet Download Section (Sprint 9.5)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.table_chart_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Download Individual Worksheet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Download a single worksheet with chronologically sorted records and column headers.',
                      style: TextStyle(fontSize: 11, color: AppColors.outline),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const Key('worksheet_selector_dropdown'),
                      initialValue: _selectedWorksheet,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                      items: ExcelWorkbookSchema.worksheetNames.map((name) {
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: _isProcessing
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _selectedWorksheet = val);
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('download_selected_sheet_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 9, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : _handleDownloadSelectedWorksheet,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.download_rounded, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Download Selected Sheet ($_selectedWorksheet)',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // File Save Location Guidance Note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 16, color: AppColors.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saved via device download manager or browser default downloads directory.',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

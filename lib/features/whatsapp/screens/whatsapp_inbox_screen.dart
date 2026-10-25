import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_details_screen.dart';
import '../models/whatsapp_message.dart';
import '../providers/whatsapp_inbox_provider.dart';

class WhatsAppInboxScreen extends ConsumerStatefulWidget {
  const WhatsAppInboxScreen({
    super.key,
    this.initialPhoneNumber,
    this.initialPatient,
  });

  final String? initialPhoneNumber;
  final PatientModel? initialPatient;

  @override
  ConsumerState<WhatsAppInboxScreen> createState() => _WhatsAppInboxScreenState();
}

class _WhatsAppInboxScreenState extends ConsumerState<WhatsAppInboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _filter = 'all'; // 'all' | 'matched' | 'unmatched' | 'eye' | 'dental'
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final initialPhone =
        widget.initialPhoneNumber ?? widget.initialPatient?.mobile;
    if (initialPhone != null && initialPhone.trim().isNotEmpty) {
      final digits = initialPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final clean = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeConversationPhoneProvider.notifier).state = clean;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(whatsappConversationsProvider);
    final activePhone = ref.watch(activeConversationPhoneProvider);
    final activeConv = ref.watch(activeConversationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shared WhatsApp Inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Inbox',
            onPressed: () =>
                ref.read(whatsappConversationsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 768;

          return conversationsAsync.when(
            loading: () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppSpacing.md),
                  Text('Loading WhatsApp conversations...'),
                ],
              ),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Failed to load WhatsApp conversations',
                      style: AppTypography.headlineMd
                          .copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(err.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(whatsappConversationsProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (conversations) {
              final filtered = _filterConversations(conversations);

              if (isWide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 380,
                      child: _buildConversationList(filtered, activePhone),
                    ),
                    const VerticalDivider(
                        width: 1, color: AppColors.outlineVariant),
                    Expanded(
                      child: activeConv != null
                          ? _buildConversationDetail(activeConv)
                          : _buildEmptyState(),
                    ),
                  ],
                );
              } else {
                // Mobile layout: Show detail if selected, otherwise list
                if (activeConv != null) {
                  return PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) {
                        ref
                            .read(activeConversationPhoneProvider.notifier)
                            .state = null;
                      }
                    },
                    child: _buildConversationDetail(activeConv, isMobile: true),
                  );
                }
                return _buildConversationList(filtered, activePhone);
              }
            },
          );
        },
      ),
    );
  }

  List<WhatsAppConversation> _filterConversations(
      List<WhatsAppConversation> all) {
    var list = all;

    if (_filter == 'matched') {
      list = list.where((c) => c.isMatchedPatient).toList();
    } else if (_filter == 'unmatched') {
      list = list.where((c) => !c.isMatchedPatient).toList();
    } else if (_filter == 'eye') {
      list = list
          .where((c) => (c.department ?? '').toLowerCase() == 'eye')
          .toList();
    } else if (_filter == 'dental') {
      list = list
          .where((c) => (c.department ?? '').toLowerCase() == 'dental')
          .toList();
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((c) {
        final name = (c.patientName ?? '').toLowerCase();
        final phone = c.phoneNumber.toLowerCase();
        final number = (c.patientNumber ?? '').toLowerCase();
        return name.contains(query) ||
            phone.contains(query) ||
            number.contains(query);
      }).toList();
    }

    return list;
  }

  Widget _buildConversationList(
      List<WhatsAppConversation> list, String? activePhone) {
    return Container(
      color: AppColors.surfaceContainerLowest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search patient name, phone, or ID...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide:
                          const BorderSide(color: AppColors.outlineVariant),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Matched', 'matched'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Unmatched', 'unmatched'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Eye', 'eye'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Dental', 'dental'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 40, color: AppColors.outline),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No conversations found',
                            style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.outlineVariant),
                    itemBuilder: (context, index) {
                      final conv = list[index];
                      final isSelected = conv.phoneNumber == activePhone;

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor:
                            AppColors.primaryContainer.withValues(alpha: 0.2),
                        leading: CircleAvatar(
                          backgroundColor: conv.isMatchedPatient
                              ? AppColors.primaryContainer
                              : AppColors.surfaceContainerHigh,
                          child: Icon(
                            conv.isMatchedPatient
                                ? Icons.person
                                : Icons.phone_outlined,
                            size: 20,
                            color: conv.isMatchedPatient
                                ? AppColors.onPrimaryContainer
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                conv.patientName ??
                                    'Unmatched: +91 ${conv.phoneNumber}',
                                style: AppTypography.headlineMd.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatTime(conv.lastTimestamp),
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.outline,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              conv.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (conv.isMatchedPatient)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Matched',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: Colors.green.shade800,
                                        fontSize: 9,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Unmatched',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: Colors.orange.shade900,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                if (conv.department != null) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      conv.department!.toUpperCase(),
                                      style: AppTypography.labelCaps.copyWith(
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                                if (conv.isOptedOut) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'OPTED OUT',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: AppColors.error,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          ref
                              .read(activeConversationPhoneProvider.notifier)
                              .state = conv.phoneNumber;
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
      },
    );
  }

  Widget _buildConversationDetail(WhatsAppConversation conv,
      {bool isMobile = false}) {
    return Column(
      children: [
        // Conversation Top Bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              if (isMobile)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    ref.read(activeConversationPhoneProvider.notifier).state =
                        null;
                  },
                ),
              CircleAvatar(
                backgroundColor: conv.isMatchedPatient
                    ? AppColors.primaryContainer
                    : AppColors.surfaceContainerHigh,
                child: Icon(
                  conv.isMatchedPatient ? Icons.person : Icons.phone_outlined,
                  color: conv.isMatchedPatient
                      ? AppColors.onPrimaryContainer
                      : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            conv.patientName ??
                                widget.initialPatient?.name ??
                                'Unmatched Contact',
                            style: AppTypography.headlineMd.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        if (conv.patientNumber != null ||
                            widget.initialPatient?.patientNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              conv.patientNumber ??
                                  widget.initialPatient!.patientNumber,
                              style: AppTypography.labelCaps
                                  .copyWith(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '+91 ${conv.phoneNumber}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Action Buttons
              if (conv.patientId != null)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientDetailsScreen(patientId: conv.patientId!),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_circle_outlined, size: 16),
                  label: const Text('View Record'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _showLinkPatientDialog(context, conv.phoneNumber),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Link Patient'),
                ),
            ],
          ),
        ),

        // Opt-out Warning Banner
        if (conv.isOptedOut)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xs),
            color: AppColors.errorContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 16, color: AppColors.error),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Patient opted out of automated WhatsApp messages via STOP command.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onErrorContainer),
                ),
              ],
            ),
          ),

        // Messages List
        Expanded(
          child: Container(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.3),
            child: conv.messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages in this conversation yet.',
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: conv.messages.length,
                    itemBuilder: (context, index) {
                      final msg = conv.messages[index];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),
        ),

        // Message Input Bar
        _buildMessageComposer(conv),
      ],
    );
  }

  Widget _buildMessageBubble(WhatsAppMessage msg) {
    final isOut = msg.isOutbound;
    final align = isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isOut
        ? AppColors.primary
        : AppColors.surfaceContainerLowest;
    final textColor = isOut ? Colors.white : AppColors.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isOut ? 16 : 4),
                bottomRight: Radius.circular(isOut ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.messageBody,
                  style: AppTypography.bodyMd.copyWith(color: textColor),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('h:mm a').format(msg.timestamp),
                      style: AppTypography.labelCaps.copyWith(
                        color: isOut
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.outline,
                        fontSize: 10,
                      ),
                    ),
                    if (isOut) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.status == 'sent'
                            ? Icons.done_all
                            : (msg.status == 'failed'
                                ? Icons.error_outline
                                : Icons.schedule),
                        size: 14,
                        color: msg.status == 'failed'
                            ? Colors.yellowAccent
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer(WhatsAppConversation conv) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Quick Templates:',
                style: AppTypography.labelCaps.copyWith(fontSize: 11),
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(
                label: const Text('Reminder'),
                onPressed: () {
                  _messageController.text =
                      'Hello ${conv.patientName ?? "Patient"}, this is a reminder from MKES CARE+ regarding your scheduled visit. Please let us know if you have any questions.';
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(
                label: const Text('Lab Ready'),
                onPressed: () {
                  _messageController.text =
                      'Good news ${conv.patientName ?? "Patient"}! Your dental/medical lab appliance has arrived at MKES CARE+ and is ready for fitting. Please contact us to book your insertion slot.';
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(
                label: const Text('Follow-Up'),
                onPressed: () {
                  _messageController.text =
                      'Dear ${conv.patientName ?? "Patient"}, we are following up on your recovery progress at MKES CARE+. How are you feeling today?';
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: conv.isOptedOut
                        ? 'Patient has opted out of WhatsApp messages'
                        : 'Type message to send via MKES CARE+ WhatsApp...',
                    isDense: true,
                    enabled: !conv.isOptedOut && !_isSending,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide:
                          const BorderSide(color: AppColors.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: conv.isOptedOut || _isSending
                    ? null
                    : () => _handleSendMessage(conv),
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendMessage(WhatsAppConversation conv) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);

    final success = await ref
        .read(whatsappConversationsProvider.notifier)
        .sendMessage(
          phone: conv.phoneNumber,
          patientId: conv.patientId ?? widget.initialPatient?.id,
          department: conv.department ??
              widget.initialPatient?.department ??
              'general',
          messageText: text,
        );

    setState(() => _isSending = false);

    if (mounted) {
      if (success) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message enqueued to clinic WhatsApp outbox.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to enqueue message. Please check permissions.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showLinkPatientDialog(
      BuildContext context, String phone) async {
    final patientsAsync = ref.read(patientsProvider);
    PatientModel? selected;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Link Phone to Patient Record'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Linking +91 $phone to a registered patient profile will associate this WhatsApp chat thread with their medical record.',
                      style: AppTypography.bodySm,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    patientsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Error: $e'),
                      data: (patients) {
                        return DropdownButtonFormField<PatientModel>(
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Select Patient',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                          items: patients.map((p) {
                            final pNum = p.patientNumber.isNotEmpty ? p.patientNumber : 'No ID';
                            return DropdownMenuItem(
                              value: p,
                              child: Text('${p.name} ($pNum)'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selected = val;
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          final ok = await ref
                              .read(whatsappConversationsProvider.notifier)
                              .linkPatient(
                                phone: phone,
                                patientId: selected!.id,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Phone linked to ${selected!.name}.'
                                    : 'Failed to link patient.'),
                                backgroundColor:
                                    ok ? Colors.green : AppColors.error,
                              ),
                            );
                          }
                        },
                  child: const Text('Confirm Link'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: AppColors.outline,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Select a conversation',
            style: AppTypography.headlineMd.copyWith(
              fontSize: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose a patient or phone number from the list to view history and reply.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return DateFormat('h:mm a').format(dt);
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat('EEE').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }
}

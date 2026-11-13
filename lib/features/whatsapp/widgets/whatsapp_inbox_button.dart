import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/whatsapp_inbox_provider.dart';
import '../screens/whatsapp_inbox_screen.dart';

class WhatsAppInboxButton extends ConsumerWidget {
  const WhatsAppInboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(whatsappConversationsProvider);
    final totalUnread = conversationsAsync.valueOrNull?.fold<int>(
          0,
          (sum, c) => sum + (c.unreadCount > 0 ? 1 : 0),
        ) ??
        0;

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          color: AppColors.onSurfaceVariant,
          iconSize: 22,
          tooltip: 'Shared WhatsApp Inbox',
          onPressed: () {
            ref.read(whatsappConversationsProvider.notifier).refresh();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const WhatsAppInboxScreen(),
              ),
            );
          },
        ),
        if (totalUnread > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$totalUnread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

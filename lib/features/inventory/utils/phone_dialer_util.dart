import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

/// Utility to safely open the device/system phone dialer.
class PhoneDialerUtil {
  /// Cleans the phone string, preserving digits and leading '+'.
  static String cleanNumber(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Checks if [phoneNumber] has valid dialable format without placing a call.
  static bool isValidPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) return false;
    final cleanPhone = cleanNumber(phoneNumber);
    return cleanPhone.length >= 3;
  }

  /// Opens the system phone dialer with [phoneNumber] populated.
  /// Returns `true` if dialer opened, `false` otherwise.
  static Future<bool> openDialer(BuildContext context, String? phoneNumber) async {
    if (!isValidPhoneNumber(phoneNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Phone number unavailable.'),
        ),
      );
      return false;
    }

    final cleanPhone = cleanNumber(phoneNumber!);

    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Could not open phone dialer for: $phoneNumber'),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Error opening dialer: $e'),
          ),
        );
      }
      return false;
    }
  }

  /// Alias for [openDialer] for backward compatibility.
  static Future<bool> launchDialer(BuildContext context, String? phoneNumber) =>
      openDialer(context, phoneNumber);
}

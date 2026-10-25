import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/screens/role_selection_screen.dart';
import 'package:mkes_care/features/notifications/models/notification_model.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/whatsapp/models/whatsapp_message.dart';
import 'package:mkes_care/core/services/push_notification_service.dart';

void main() {
  group('1. WhatsApp Models & Serialization', () {
    test('WhatsAppMessage parses inbound message safely', () {
      final json = {
        'id': 'msg-101',
        'phone_number': '9876543210',
        'patient_id': 'pat-1',
        'department': 'dental',
        'message_body': 'Can I change my appointment to Monday at 10 AM?',
        'direction': 'inbound',
        'status': 'received',
        'created_at': '2026-10-24T10:00:00Z',
      };

      final msg = WhatsAppMessage.fromJson(json);
      expect(msg.id, equals('msg-101'));
      expect(msg.phoneNumber, equals('9876543210'));
      expect(msg.isInbound, isTrue);
      expect(msg.isOutbound, isFalse);
      expect(msg.patientId, equals('pat-1'));
      expect(msg.department, equals('dental'));
      expect(msg.messageBody, contains('Monday at 10 AM'));
    });

    test('WhatsAppMessage parses outbound outbox record safely', () {
      final json = {
        'id': 'msg-202',
        'recipient_phone': '919876543210',
        'patient_id': null,
        'department': 'eye',
        'message_text': 'Your appointment has been confirmed.',
        'status': 'sent',
        'created_at': '2026-10-24T10:05:00Z',
      };

      final msg = WhatsAppMessage.fromJson(json);
      expect(msg.id, equals('msg-202'));
      expect(msg.phoneNumber, equals('919876543210'));
      expect(msg.isInbound, isFalse);
      expect(msg.isOutbound, isTrue);
      expect(msg.status, equals('sent'));
    });

    test('WhatsAppConversation correctly aggregates metrics and opt-out state', () {
      final conv = WhatsAppConversation(
        phoneNumber: '9876543210',
        patientId: 'pat-123',
        patientName: 'Jane Doe',
        patientNumber: 'P-1001',
        department: 'eye',
        lastMessage: 'Appointment rescheduled successfully.',
        lastTimestamp: DateTime(2026, 10, 24, 11, 0),
        unreadCount: 2,
        isOptedOut: true,
        messages: [],
      );

      expect(conv.isMatchedPatient, isTrue);
      expect(conv.isOptedOut, isTrue);
      expect(conv.unreadCount, equals(2));
      expect(conv.department, equals('eye'));
    });

    test('Unmatched WhatsAppConversation reports isMatchedPatient false', () {
      final conv = WhatsAppConversation(
        phoneNumber: '9999999999',
        lastMessage: 'Hello, need info',
        lastTimestamp: DateTime.now(),
        messages: [],
      );

      expect(conv.isMatchedPatient, isFalse);
      expect(conv.patientName, isNull);
      expect(conv.patientId, isNull);
    });
  });

  group('2. Unified Notification Types & Iconography', () {
    test('NotificationModel supports all extended notification types', () {
      final types = [
        'whatsapp_reply',
        'appointment_rescheduled',
        'lab_ready',
        'attendance_exception',
        'inventory_alert',
      ];

      for (final type in types) {
        final notif = NotificationModel(
          id: 'notif-$type',
          userId: 'user-admin',
          type: type,
          title: 'Title for $type',
          message: 'Notification detail message',
          isRead: false,
          createdAt: DateTime.now(),
        );

        expect(notif.icon, isA<IconData>());
        expect(notif.iconColor, isA<Color>());
      }
    });

    test('WhatsApp notification routes to distinct icon and WhatsApp green color', () {
      final notif = NotificationModel(
        id: 'n-wa',
        userId: 'staff-1',
        type: 'whatsapp_reply',
        title: 'New WhatsApp Message',
        message: 'Patient sent a message',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notif.icon, equals(Icons.chat_bubble_outline));
      expect(notif.iconColor, equals(Colors.green));
    });

    test('Appointment rescheduled notification displays edit_calendar icon', () {
      final notif = NotificationModel(
        id: 'n-resched',
        userId: 'staff-1',
        type: 'appointment_rescheduled',
        title: 'Appointment Rescheduled via WhatsApp',
        message: 'Dr. Smith slot moved',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notif.icon, equals(Icons.edit_calendar_outlined));
    });
  });

  group('3. Patient WhatsApp Opt-Out Preference', () {
    test('PatientModel defaults whatsappOptOut to false', () {
      final p = PatientModel(
        id: 'pat-default',
        patientNumber: 'P-1',
        name: 'John',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(p.whatsappOptOut, isFalse);
    });

    test('PatientModel preserves whatsappOptOut in serialization and copyWith', () {
      final p = PatientModel(
        id: 'pat-optout',
        patientNumber: 'P-2',
        name: 'Alice',
        whatsappOptOut: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = p.toJson();
      expect(json['whatsapp_opt_out'], isTrue);

      final deserialized = PatientModel.fromJson(json);
      expect(deserialized.whatsappOptOut, isTrue);

      final updated = deserialized.copyWith(whatsappOptOut: false);
      expect(updated.whatsappOptOut, isFalse);
    });
  });

  group('4. Push Notification Routing & Lock Screen Privacy', () {
    test('formatPrivacyPreservingPayload sanitizes lock screen content for Eye and Dental', () {
      final service = PushNotificationService();
      final apptPayload = service.formatPrivacyPreservingPayload(
        type: 'appointment_rescheduled',
        patientName: 'Sarah Connor',
        actionSummary: 'Detailed medical procedure rescheduled',
      );

      expect(apptPayload['title'], equals('Appointment Update'));
      expect(apptPayload['body'], equals('Sarah Connor rescheduled their consultation.'));
      expect(apptPayload['type'], equals('appointment_rescheduled'));
      expect(apptPayload['requires_auth'], equals('true'));

      final dentalLabPayload = service.formatPrivacyPreservingPayload(
        type: 'lab_ready',
        department: 'dental',
        patientName: 'Arun Verma',
        actionSummary: 'Crown ready',
      );
      expect(dentalLabPayload['title'], equals('Dental Lab Alert'));

      final eyeLabPayload = service.formatPrivacyPreservingPayload(
        type: 'lab_ready',
        department: 'eye',
        patientName: 'Kavita Roy',
        actionSummary: 'Toric IOL ready',
      );
      expect(eyeLabPayload['title'], equals('Eye Lab Alert'));
    });

    test('handleNotificationTap maps WhatsApp, rescheduling, and Eye/Dental lab types correctly', () {
      final service = PushNotificationService();

      expect(service.handleNotificationTap({'type': 'whatsapp_reply'}),
          equals('/whatsapp/inbox'));
      expect(service.handleNotificationTap({'type': 'appointment_rescheduled'}),
          equals('/appointments'));
      expect(service.handleNotificationTap({'type': 'dental_lab_ready'}),
          equals('/dental/lab'));
      expect(service.handleNotificationTap({'type': 'eye_lab_ready'}),
          equals('/eye/surgery'));
      expect(service.handleNotificationTap({'type': 'lab_ready', 'department': 'dental'}),
          equals('/dental/lab'));
      expect(service.handleNotificationTap({'type': 'lab_ready', 'department': 'eye'}),
          equals('/eye/surgery'));
      expect(service.handleNotificationTap({'type': 'eye_surgery'}),
          equals('/eye/surgery'));
      expect(service.handleNotificationTap({'type': 'inventory_alert'}),
          equals('/inventory'));
      expect(service.handleNotificationTap({'type': 'leave_request'}),
          equals('/staff/leave'));
      expect(service.handleNotificationTap({'type': 'leave_rejected'}),
          equals('/staff/leave'));
      expect(service.handleNotificationTap({'type': 'attendance_exception'}),
          equals('/staff/attendance'));
      expect(service.handleNotificationTap({'type': 'task_assigned'}),
          equals('/staff/tasks'));
    });

    test('PushNotificationService manages lifecycle, permission request, and reset correctly', () async {
      final service = PushNotificationService();
      expect(service.isInitialized, isFalse);
      expect(service.currentToken, isNull);

      final hasPermission = await service.requestNotificationPermissions();
      expect(hasPermission, isTrue);

      await service.initialize();
      expect(service.isInitialized, isTrue);

      await service.deactivateToken();
      expect(service.isInitialized, isFalse);
      expect(service.currentToken, isNull);
    });

    test('PushNotificationService handles onTokenRefresh and deactivateInvalidToken cleanly', () async {
      final service = PushNotificationService();

      // Refresh without user logged in returns false safely without throwing
      final refreshed = await service.onTokenRefresh('fcm_refreshed_tok_999');
      expect(refreshed, isFalse);

      // Deactivating invalid token executes without throwing
      await service.deactivateInvalidToken('bad_token_000');
      expect(service.currentToken, isNull);
    });
  });

  group('5. MKES CARE+ Branding & Logo Integration', () {
    test('Official logo assets exist in assets/images/ directory', () {
      final original = File('assets/images/mkes_logo_original.png');
      final square = File('assets/images/mkes_logo.png');

      expect(original.existsSync(), isTrue, reason: 'Original logo must exist');
      expect(square.existsSync(), isTrue, reason: 'Derived square logo must exist');
      expect(original.lengthSync(), greaterThan(1000000));
      expect(square.lengthSync(), greaterThan(10000));
    });

    testWidgets('RoleSelectionScreen displays official MKES CARE+ logo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoleSelectionScreen(),
        ),
      );

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      final assetImage = imageWidget.image as AssetImage;
      expect(assetImage.assetName, equals('assets/images/mkes_logo.png'));
      expect(imageWidget.fit, equals(BoxFit.contain));
    });
  });
}

class WhatsAppMessage {
  final String id;
  final String? outboxId;
  final String direction; // 'inbound' | 'outbound'
  final String phoneNumber;
  final String? patientId;
  final String? patientName;
  final String messageBody;
  final String status; // 'sent' | 'delivered' | 'read' | 'pending' | 'failed' | 'inbound'
  final DateTime timestamp;
  final String? department;

  const WhatsAppMessage({
    required this.id,
    this.outboxId,
    required this.direction,
    required this.phoneNumber,
    this.patientId,
    this.patientName,
    required this.messageBody,
    this.status = 'sent',
    required this.timestamp,
    this.department,
  });

  bool get isInbound => direction.toLowerCase() == 'inbound';
  bool get isOutbound => direction.toLowerCase() == 'outbound';
  bool get isRead => status.toLowerCase() == 'read';
  bool get isDelivered => status.toLowerCase() == 'delivered' || isRead;
  bool get isSent => status.toLowerCase() == 'sent' || isDelivered;
  bool get isPending => status.toLowerCase() == 'pending' || status.toLowerCase() == 'processing';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isCancelled => status.toLowerCase() == 'cancelled';

  factory WhatsAppMessage.fromJson(Map<String, dynamic> json) {
    String derivedStatus = json['status']?.toString() ?? '';
    if (derivedStatus.isEmpty) {
      if (json['raw_payload'] != null && json['raw_payload'] is Map) {
        final raw = json['raw_payload'] as Map;
        if (raw['status'] != null) {
          derivedStatus = raw['status'].toString();
        } else if (raw['ack'] != null) {
          final ack = int.tryParse(raw['ack'].toString()) ?? 0;
          if (ack >= 3) {
            derivedStatus = 'read';
          } else if (ack == 2) {
            derivedStatus = 'delivered';
          } else if (ack == 1) {
            derivedStatus = 'sent';
          } else if (ack == -1) {
            derivedStatus = 'failed';
          }
        }
      }
    }
    if (derivedStatus.isEmpty) {
      derivedStatus = json['direction']?.toString().toLowerCase() == 'inbound'
          ? 'inbound'
          : 'sent';
    }

    return WhatsAppMessage(
      id: json['id']?.toString() ?? '',
      outboxId: json['outbox_id']?.toString(),
      direction: json['direction']?.toString() ??
          (json['recipient_phone'] != null || json['outbox_id'] != null
              ? 'outbound'
              : 'inbound'),
      phoneNumber: json['phone_number']?.toString() ??
          json['recipient_phone']?.toString() ??
          '',
      patientId: json['patient_id']?.toString(),
      patientName: json['patients'] != null && json['patients'] is Map
          ? (json['patients'] as Map)['name']?.toString()
          : null,
      messageBody: json['message_body']?.toString() ??
          json['message_text']?.toString() ??
          '',
      status: derivedStatus,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
      department: json['department']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'outbox_id': outboxId,
        'direction': direction,
        'phone_number': phoneNumber,
        'patient_id': patientId,
        'message_body': messageBody,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        'department': department,
      };
}

class WhatsAppConversation {
  final String phoneNumber;
  final String? patientId;
  final String? patientName;
  final String? patientNumber;
  final String? department;
  final bool isOptedOut;
  final String lastMessage;
  final DateTime lastTimestamp;
  final int unreadCount;
  final List<WhatsAppMessage> messages;

  const WhatsAppConversation({
    required this.phoneNumber,
    this.patientId,
    this.patientName,
    this.patientNumber,
    this.department,
    this.isOptedOut = false,
    required this.lastMessage,
    required this.lastTimestamp,
    this.unreadCount = 0,
    required this.messages,
  });

  bool get isMatchedPatient => patientId != null && patientId!.isNotEmpty;

  WhatsAppConversation copyWith({
    String? phoneNumber,
    String? patientId,
    String? patientName,
    String? patientNumber,
    String? department,
    bool? isOptedOut,
    String? lastMessage,
    DateTime? lastTimestamp,
    int? unreadCount,
    List<WhatsAppMessage>? messages,
  }) {
    return WhatsAppConversation(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      department: department ?? this.department,
      isOptedOut: isOptedOut ?? this.isOptedOut,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      messages: messages ?? this.messages,
    );
  }
}

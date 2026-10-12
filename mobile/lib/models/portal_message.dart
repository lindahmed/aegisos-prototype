class MessageContact {
  const MessageContact({
    required this.type,
    required this.id,
    required this.name,
    required this.subtitle,
    this.major,
  });

  factory MessageContact.fromJson(Map<String, dynamic> json) {
    return MessageContact(
      type: json['type']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      major: json['major']?.toString(),
    );
  }

  const MessageContact.broadcast()
    : type = 'broadcast',
      id = 'all-students',
      name = 'Professor announcements',
      subtitle = 'Messages sent to all students',
      major = null;

  final String type;
  final String id;
  final String name;
  final String subtitle;
  final String? major;

  String get key => '$type:$id';
  bool get isBroadcast => type == 'broadcast';
}

class PortalMessageAttachment {
  const PortalMessageAttachment({
    required this.filename,
    required this.sizeBytes,
  });

  factory PortalMessageAttachment.fromJson(Map<String, dynamic> json) {
    return PortalMessageAttachment(
      filename: json['filename']?.toString() ?? 'Document',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String filename;
  final int sizeBytes;
}

class PortalMessage {
  const PortalMessage({
    required this.messageId,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.recipientType,
    required this.recipientId,
    required this.recipientName,
    required this.isBroadcast,
    required this.body,
    required this.createdAt,
    required this.read,
    this.attachment,
  });

  factory PortalMessage.fromJson(Map<String, dynamic> json) {
    final attachment = json['attachment'];
    return PortalMessage(
      messageId: json['message_id']?.toString() ?? '',
      senderType: json['sender_type']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      recipientType: json['recipient_type']?.toString(),
      recipientId: json['recipient_id']?.toString(),
      recipientName: json['recipient_name']?.toString(),
      isBroadcast: json['is_broadcast'] == true,
      body: json['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: json['read'] == true,
      attachment: attachment is Map<String, dynamic>
          ? PortalMessageAttachment.fromJson(attachment)
          : null,
    );
  }

  final String messageId;
  final String senderType;
  final String senderId;
  final String senderName;
  final String? recipientType;
  final String? recipientId;
  final String? recipientName;
  final bool isBroadcast;
  final String body;
  final DateTime createdAt;
  final bool read;
  final PortalMessageAttachment? attachment;

  bool isOutgoing(String studentId) =>
      senderType == 'student' && senderId == studentId;

  String conversationKey(String studentId) {
    if (isBroadcast) return 'broadcast:all-students';
    if (isOutgoing(studentId)) return '$recipientType:$recipientId';
    return '$senderType:$senderId';
  }
}

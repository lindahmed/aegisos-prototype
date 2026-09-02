class StudentNotification {
  const StudentNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.read,
  });

  factory StudentNotification.fromJson(Map<String, dynamic> json) {
    return StudentNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: json['timestamp'] as String,
      read: json['read'] as bool,
    );
  }

  final String id;
  final String type;
  final String category;
  final String title;
  final String body;
  final String timestamp;
  final bool read;

  StudentNotification copyWith({bool? read}) {
    return StudentNotification(
      id: id,
      type: type,
      category: category,
      title: title,
      body: body,
      timestamp: timestamp,
      read: read ?? this.read,
    );
  }
}

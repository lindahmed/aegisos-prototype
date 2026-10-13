enum AdvisorActionType { addStudySession, openCourse, fixMyWeek }

class AdvisorAction {
  const AdvisorAction({required this.type, required this.label});

  final AdvisorActionType type;
  final String label;
}

class AdvisorMessage {
  const AdvisorMessage({
    required this.role,
    required this.content,
    this.actions = const [],
  });

  const AdvisorMessage.user(String content)
    : this(role: 'user', content: content);

  const AdvisorMessage.assistant(
    String content, {
    List<AdvisorAction> actions = const [],
  }) : this(role: 'assistant', content: content, actions: actions);

  final String role;
  final String content;
  final List<AdvisorAction> actions;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AdvisorReply {
  const AdvisorReply({
    required this.intent,
    required this.response,
    required this.language,
  });

  final String intent;
  final String response;
  final String language;

  factory AdvisorReply.fromJson(Map<String, dynamic> json) {
    return AdvisorReply(
      intent: json['intent'] as String,
      response: json['response'] as String,
      language: json['language'] as String? ?? 'english',
    );
  }
}

import 'dart:typed_data';

class AdvisorMessage {
  const AdvisorMessage({required this.role, required this.content});

  const AdvisorMessage.user(String content)
    : this(role: 'user', content: content);

  const AdvisorMessage.assistant(String content)
    : this(role: 'assistant', content: content);

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AdvisorVoiceReply extends AdvisorReply {
  const AdvisorVoiceReply({
    required super.intent,
    required super.response,
    required super.language,
    required this.transcript,
    required this.audioBytes,
  });

  final String transcript;
  final Uint8List audioBytes;
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

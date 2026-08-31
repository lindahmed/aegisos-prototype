import 'package:flutter/material.dart';

import '../models/advisor_message.dart';
import '../models/student.dart';
import '../services/api_service.dart';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({
    required this.student,
    this.apiService,
    super.key,
  });

  final Student student;
  final ApiService? apiService;

  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen> {
  static const _suggestions = [
    'Help me plan my next semester',
    'What careers match my major?',
    'How can I improve my academic progress?',
  ];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AdvisorMessage> _messages = [];

  late final ApiService _apiService;
  late final bool _ownsApiService;
  bool _isSending = false;
  String _language = 'english';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
  }

  Future<void> _sendMessage([String? suggestedMessage]) async {
    final message = (suggestedMessage ?? _messageController.text).trim();
    if (message.isEmpty || _isSending) return;

    final history = List<AdvisorMessage>.from(_messages);
    _messageController.clear();
    setState(() {
      _messages.add(AdvisorMessage.user(message));
      _isSending = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final reply = await _apiService.askAdvisor(
        studentId: widget.student.studentId,
        message: message,
        history: history,
        language: _language,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(AdvisorMessage.assistant(reply.response));
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Advisor AI could not answer. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advisor AI'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Response language',
            initialValue: _language,
            onSelected: (value) => setState(() => _language = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'english', child: Text('English')),
              PopupMenuItem(value: 'arabic', child: Text('العربية')),
            ],
            icon: const Icon(Icons.language),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyAdvisorState(
                      studentName: widget.student.name,
                      suggestions: _suggestions,
                      onSuggestionSelected: _sendMessage,
                    )
                  : ListView.builder(
                      key: const Key('advisor-message-list'),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
            ),
            if (_isSending)
              const LinearProgressIndicator(key: Key('advisor-loading')),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _errorMessage!,
                  key: const Key('advisor-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            _MessageComposer(
              controller: _messageController,
              enabled: !_isSending,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAdvisorState extends StatelessWidget {
  const _EmptyAdvisorState({
    required this.studentName,
    required this.suggestions,
    required this.onSuggestionSelected,
  });

  final String studentName;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(
          Icons.auto_awesome,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'How can I help, ${studentName.split(' ').first}?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask about semester planning, careers, courses, or your academic progress.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ...suggestions.map(
          (suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () => onSuggestionSelected(suggestion),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(suggestion),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AdvisorMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(message.content),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('advisor-input'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ask your advisor...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('advisor-send'),
              tooltip: 'Send',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

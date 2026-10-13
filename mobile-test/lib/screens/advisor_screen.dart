import 'dart:async';

import 'package:flutter/material.dart';

import '../models/advisor_message.dart';
import '../models/calendar_event.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/advisor_voice_service.dart';
import '../theme/app_theme.dart';
import '../widgets/study_session_dialog.dart';
import 'courses_schedule_screen.dart';
import 'weekly_plan_screen.dart';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({
    required this.student,
    this.apiService,
    this.voiceService,
    this.initialMessage,
    super.key,
  });

  final Student student;
  final ApiService? apiService;
  final AdvisorVoiceService? voiceService;
  final String? initialMessage;

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
  late final AdvisorVoiceService _voiceService;
  late final bool _ownsVoiceService;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isSpeaking = false;
  int _recordingSession = 0;
  String? _errorMessage;

  String get _appLanguage => appLanguageController.advisorLanguage;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    _ownsVoiceService = widget.voiceService == null;
    _voiceService = widget.voiceService ?? DeviceAdvisorVoiceService();
    final initialMessage = widget.initialMessage?.trim();
    if (initialMessage != null && initialMessage.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_sendMessage(initialMessage));
      });
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isSending) return;

    if (!_isRecording) {
      try {
        if (_isSpeaking) await _stopSpeaking();
        if (!mounted) return;
        _messageController.clear();
        final recordingSession = ++_recordingSession;
        final started = await _voiceService.startListening(
          language: _appLanguage,
          onResult: (words) {
            if (!mounted || recordingSession != _recordingSession) return;
            _messageController.value = TextEditingValue(
              text: words,
              selection: TextSelection.collapsed(offset: words.length),
            );
          },
        );
        if (!mounted) return;
        if (!started) {
          _recordingSession += 1;
          _messageController.clear();
        }
        setState(() {
          _isRecording = started;
          _errorMessage = started ? null : 'Speech recognition is unavailable. Check microphone permission.';
        });
      } catch (_) {
        if (mounted) {
          setState(() => _errorMessage = 'Could not start speech recognition.');
        }
      }
      return;
    }

    _recordingSession += 1;
    setState(() {
      _isRecording = false;
      _errorMessage = null;
    });

    try {
      final transcript = await _voiceService.stopListening();
      if (transcript.trim().isEmpty) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'I did not hear any words. Tap the microphone and speak again.',
          );
        }
        return;
      }
      await _sendMessage(transcript, true);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not finish speech recognition.');
      }
    }
  }

  Future<void> _discardVoiceRecording() async {
    if (!_isRecording) return;

    _recordingSession += 1;
    _messageController.clear();
    setState(() {
      _isRecording = false;
      _errorMessage = null;
    });

    try {
      await _voiceService.cancelListening();
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not discard the recording.');
      }
    }
  }

  Future<void> _sendMessage([
    String? suggestedMessage,
    bool speakReply = false,
  ]) async {
    final message = (suggestedMessage ?? _messageController.text).trim();
    if (message.isEmpty || _isSending || _isRecording) return;
    final requestLanguage = containsArabic(message) ? 'arabic' : _appLanguage;

    if (_isSpeaking) await _stopSpeaking();
    if (!mounted) return;

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
        language: requestLanguage,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          AdvisorMessage.assistant(
            reply.response,
            actions: const [
              AdvisorAction(
                type: AdvisorActionType.addStudySession,
                label: 'Add to Calendar',
              ),
              AdvisorAction(
                type: AdvisorActionType.openCourse,
                label: 'View Courses',
              ),
              AdvisorAction(
                type: AdvisorActionType.fixMyWeek,
                label: 'Week Planner',
              ),
            ],
          ),
        );
      });
      if (speakReply) {
        try {
          final audioBytes = await _apiService.speakAdvisor(
            text: reply.response,
            language: requestLanguage,
          );
          if (!mounted) return;
          setState(() => _isSpeaking = true);
          await _voiceService.play(
            audioBytes,
            onComplete: () {
              if (mounted) setState(() => _isSpeaking = false);
            },
          );
        } on Exception {
          if (mounted) {
            setState(() {
              _isSpeaking = false;
              _errorMessage =
                  'The answer is ready, but its audio could not play.';
            });
          }
        }
      }
    } on ApiException catch (error) {
      final fallback = await _localAdvisorFallback(
        message,
        language: requestLanguage,
      );
      if (!mounted) return;
      if (fallback == null) {
        setState(() => _errorMessage = error.message);
      } else {
        setState(() {
          _messages.add(
            AdvisorMessage.assistant(
              fallback,
              actions: const [
                AdvisorAction(
                  type: AdvisorActionType.addStudySession,
                  label: 'Add to Calendar',
                ),
                AdvisorAction(
                  type: AdvisorActionType.openCourse,
                  label: 'View Courses',
                ),
                AdvisorAction(
                  type: AdvisorActionType.fixMyWeek,
                  label: 'Week Planner',
                ),
              ],
            ),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Aegis AI could not answer. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  Future<String?> _localAdvisorFallback(
    String message, {
    required String language,
  }) async {
    try {
      final progress = await _apiService.getStudentProgress(
        widget.student.studentId,
        forceRefresh: true,
      );
      final courses = ((progress['courses'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (courses.isEmpty) return null;
      int priority(Map<String, dynamic> course) =>
          switch (course['risk_level']?.toString().toLowerCase()) {
            'high' => 0,
            'medium' => 1,
            'low' => 2,
            _ => 3,
          };
      courses.sort((a, b) => priority(a).compareTo(priority(b)));
      final mentioned = courses.where(
        (course) => message.toLowerCase().contains(
          (course['course_name']?.toString() ?? '').toLowerCase(),
        ),
      );
      final course = mentioned.isNotEmpty ? mentioned.first : courses.first;
      final risks = ((course['risks'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final reason = risks.isEmpty
          ? 'No active risk is currently recorded for this course.'
          : risks.first['message']?.toString() ??
                'This course needs attention.';
      final health = progress['overall_academic_health'];
      final week = progress['current_week'];
      if (language == 'arabic') {
        return 'بناءً على بياناتك الحالية في الأسبوع $week، صحتك الأكاديمية العامة هي '
            '$health/100. الأولوية الآن هي ${course['course_name']}. السبب: $reason '
            'ابدئي بمراجعة مركزة لمدة 30 دقيقة، ثم أضيفي جلسة متابعة من زر Add to Calendar.';
      }
      return 'Based on your live week $week data, your overall academic health is '
          '$health/100. Your current priority is ${course['course_name']}. Why: $reason '
          'Start with one focused 30-minute review, then use Add to Calendar for the follow-up.';
    } on Exception {
      return null;
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

  Future<void> _stopSpeaking() async {
    try {
      await _voiceService.stopPlayback();
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _handleAction(
    AdvisorAction action,
    AdvisorMessage message,
  ) async {
    if (action.type == AdvisorActionType.openCourse) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CoursesScheduleScreen(
            student: widget.student,
            apiService: _apiService,
          ),
        ),
      );
      return;
    }
    if (action.type == AdvisorActionType.fixMyWeek) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WeeklyPlanScreen(
            student: widget.student,
            apiService: _apiService,
          ),
        ),
      );
      return;
    }

    final courseName = widget.student.courses.firstWhere(
      (course) => message.content.toLowerCase().contains(course.toLowerCase()),
      orElse: () => 'Focused Study',
    );
    var alreadyInWeekPlanner = false;
    try {
      final plan = await _apiService.getWeeklyPlan(widget.student.studentId);
      alreadyInWeekPlanner = plan.items.any(
        (item) =>
            item.courseName.trim().toLowerCase() ==
            courseName.trim().toLowerCase(),
      );
    } catch (_) {
      // Date and time selection still works when Week Planner is unavailable.
    }
    if (!mounted) return;
    final event = await showStudySessionDialog(
      context,
      courseName: courseName,
      reason: 'Added from this Advisor recommendation: ${message.content}',
      alreadyInWeekPlanner: alreadyInWeekPlanner,
    );
    if (event == null) return;
    try {
      final saved = await StudentCalendarStore.load(widget.student.studentId);
      await StudentCalendarStore.save(widget.student.studentId, [
        ...saved,
        event,
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            '${event.title} added to Calendar on ${event.startAt.day}/${event.startAt.month} at ${_clock(event.startAt)}.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not save the Calendar session.'),
        ),
      );
    }
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    if (_isRecording) unawaited(_voiceService.cancelListening());
    if (_ownsVoiceService) {
      unawaited(_voiceService.dispose());
    } else if (_isSpeaking) {
      unawaited(_voiceService.stopPlayback());
    }
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppText('AI Advisor'),
        actions: const [ThemeModeToggleButton()],
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
                        return _MessageBubble(
                          message: _messages[index],
                          onAction: _handleAction,
                        );
                      },
                    ),
            ),
            if (_isSending)
              const LinearProgressIndicator(key: Key('advisor-loading')),
            if (_isRecording)
              Container(
                key: const Key('advisor-recording'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: AppText('Listening… Tap stop to send'),
                    ),
                    IconButton(
                      key: const Key('advisor-discard-recording'),
                      tooltip: 'Discard recording',
                      onPressed: _discardVoiceRecording,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            if (_isSpeaking)
              Container(
                key: const Key('advisor-speaking'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_up,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: AppText('Reading response aloud')),
                    TextButton.icon(
                      key: const Key('advisor-stop-speaking'),
                      onPressed: _stopSpeaking,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const AppText('Stop speaking'),
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: AppText(
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
              isRecording: _isRecording,
              onSend: _sendMessage,
              onVoice: _toggleVoiceRecording,
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
        AppText(
          'How can I help, ${studentName.split(' ').first}?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const AppText(
          'Ask about semester planning, careers, courses, or your academic progress.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ...suggestions.map(
          (suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () => onSuggestionSelected(suggestion),
              style: OutlinedButton.styleFrom(
                foregroundColor: uniTrackNavy,
                backgroundColor: appScreenSurface,
                side: BorderSide(color: uniTrackBlue.withValues(alpha: 0.38)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 5,
                ),
              ),
              icon: const Icon(Icons.north_east_rounded, size: 20),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppText(suggestion),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onAction});

  final AdvisorMessage message;
  final Future<void> Function(AdvisorAction, AdvisorMessage) onAction;

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
          color: isUser
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.content,
              textDirection: containsArabic(message.content)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
            if (!isUser && message.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: message.actions
                    .map(
                      (action) => ActionChip(
                        key: Key('advisor-action-${action.type.name}'),
                        avatar: Icon(switch (action.type) {
                          AdvisorActionType.addStudySession =>
                            Icons.event_available_outlined,
                          AdvisorActionType.openCourse =>
                            Icons.menu_book_outlined,
                          AdvisorActionType.fixMyWeek =>
                            Icons.auto_fix_high_rounded,
                        }, size: 17),
                        label: AppText(action.label),
                        backgroundColor: colors.surface,
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.35),
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        labelStyle: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                        onPressed: () => onAction(action, message),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.isRecording,
    required this.onSend,
    required this.onVoice,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isRecording;
  final VoidCallback onSend;
  final VoidCallback onVoice;

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
                enabled: enabled && !isRecording,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                textDirection: isArabicApp
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: tr('Ask your advisor...'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('advisor-voice'),
              tooltip: isRecording
                  ? tr('Stop and send recording')
                  : tr('Record a question'),
              onPressed: enabled ? onVoice : null,
              style: isRecording
                  ? IconButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              icon: Icon(isRecording ? Icons.stop : Icons.mic),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('advisor-send'),
              tooltip: tr('Send'),
              onPressed: enabled && !isRecording ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

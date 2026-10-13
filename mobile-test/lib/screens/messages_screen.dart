import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/portal_message.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _searchController = TextEditingController();
  List<MessageContact> _contacts = const [];
  List<PortalMessage> _messages = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        widget.apiService.getMessageContacts(widget.student.studentId),
        widget.apiService.getMessages(widget.student.studentId),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = values[0] as List<MessageContact>;
        _messages = values[1] as List<PortalMessage>;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MessageContact> get _availableContacts {
    final contacts = <String, MessageContact>{
      for (final contact in _contacts) contact.key: contact,
    };
    for (final message in _messages) {
      if (message.isBroadcast) {
        const broadcast = MessageContact.broadcast();
        contacts[broadcast.key] = broadcast;
        continue;
      }
      if (message.isOutgoing(widget.student.studentId)) {
        final type = message.recipientType;
        final id = message.recipientId;
        if (type != null && id != null) {
          contacts.putIfAbsent(
            '$type:$id',
            () => MessageContact(
              type: type,
              id: id,
              name: message.recipientName ?? id,
              subtitle: type == 'staff' ? 'Professor' : 'Student',
            ),
          );
        }
      } else {
        contacts.putIfAbsent(
          '${message.senderType}:${message.senderId}',
          () => MessageContact(
            type: message.senderType,
            id: message.senderId,
            name: message.senderName.isEmpty
                ? message.senderId
                : message.senderName,
            subtitle: message.senderType == 'staff' ? 'Professor' : 'Student',
          ),
        );
      }
    }

    final query = _searchController.text.trim().toLowerCase();
    final result = contacts.values.where((contact) {
      if (query.isEmpty) return true;
      return contact.name.toLowerCase().contains(query) ||
          contact.id.toLowerCase().contains(query) ||
          contact.subtitle.toLowerCase().contains(query);
    }).toList();
    result.sort((a, b) {
      final aLatest = _latestFor(a)?.createdAt;
      final bLatest = _latestFor(b)?.createdAt;
      if (aLatest != null || bLatest != null) {
        return (bLatest ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aLatest ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
      if (a.type != b.type) return a.type == 'staff' ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  PortalMessage? _latestFor(MessageContact contact) {
    PortalMessage? latest;
    for (final message in _messages) {
      if (message.conversationKey(widget.student.studentId) != contact.key) {
        continue;
      }
      if (latest == null || message.createdAt.isAfter(latest.createdAt)) {
        latest = message;
      }
    }
    return latest;
  }

  int _unreadFor(MessageContact contact) => _messages
      .where(
        (message) =>
            message.conversationKey(widget.student.studentId) == contact.key &&
            !message.isOutgoing(widget.student.studentId) &&
            !message.read,
      )
      .length;

  Future<void> _openConversation(MessageContact contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageThreadScreen(
          student: widget.student,
          contact: contact,
          apiService: widget.apiService,
          initialMessages: _messages,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _availableContacts;
    final unread = _messages
        .where(
          (message) =>
              !message.isOutgoing(widget.student.studentId) && !message.read,
        )
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const AppText(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            _MessagesHero(unread: unread),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: tr('Search professors or classmates'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('Clear search'),
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            const AppText(
              'CONVERSATIONS',
              style: TextStyle(
                color: uniTrackBlue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading && _messages.isEmpty)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && contacts.isEmpty)
              _MessageError(message: _error!, onRetry: _load)
            else if (contacts.isEmpty)
              const _EmptyInbox()
            else
              ...contacts.map(
                (contact) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ConversationTile(
                    contact: contact,
                    latest: _latestFor(contact),
                    unread: _unreadFor(contact),
                    onTap: () => _openConversation(contact),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    required this.student,
    required this.contact,
    required this.apiService,
    required this.initialMessages,
    super.key,
  });

  final Student student;
  final MessageContact contact;
  final ApiService apiService;
  final List<PortalMessage> initialMessages;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late List<PortalMessage> _messages;
  Timer? _refreshTimer;
  PlatformFile? _attachment;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages = _forContact(widget.initialMessages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterLoad());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(_refresh(quiet: true)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<PortalMessage> _forContact(List<PortalMessage> messages) {
    final result =
        messages
            .where(
              (message) =>
                  message.conversationKey(widget.student.studentId) ==
                  widget.contact.key,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Future<void> _afterLoad() async {
    _scrollToLatest();
    await _markRead();
  }

  Future<void> _refresh({bool quiet = false}) async {
    try {
      final messages = await widget.apiService.getMessages(
        widget.student.studentId,
      );
      if (!mounted) return;
      final nearBottom =
          !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <
              90;
      setState(() {
        _messages = _forContact(messages);
        _error = null;
      });
      if (nearBottom) _scrollToLatest();
      await _markRead();
    } on ApiException catch (error) {
      if (!quiet && mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _markRead() async {
    final unread = _messages
        .where(
          (message) =>
              !message.isOutgoing(widget.student.studentId) && !message.read,
        )
        .map((message) => message.messageId)
        .toList();
    if (unread.isEmpty) return;
    try {
      await widget.apiService.markMessagesRead(
        studentId: widget.student.studentId,
        messageIds: unread,
      );
    } on ApiException {
      return;
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if ((body.isEmpty && _attachment == null) ||
        _sending ||
        widget.contact.isBroadcast) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final selectedAttachment = _attachment;
      final message = selectedAttachment == null
          ? await widget.apiService.sendMessage(
              studentId: widget.student.studentId,
              recipient: widget.contact,
              body: body,
            )
          : await widget.apiService.sendMessageAttachment(
              studentId: widget.student.studentId,
              recipient: widget.contact,
              filename: selectedAttachment.name,
              bytes: selectedAttachment.bytes!,
              body: body,
            );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _attachment = null;
        _messages = [..._messages, message];
      });
      _scrollToLatest();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    if (_sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.size <= 0 || file.bytes == null || file.bytes!.isEmpty) {
        setState(() => _error = 'The selected document is empty.');
        return;
      }
      if (file.size > 10 * 1024 * 1024) {
        setState(() => _error = 'Documents must be 10 MB or smaller.');
        return;
      }
      setState(() {
        _attachment = file;
        _error = null;
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Choose a PDF, Word, spreadsheet, presentation, or text document.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _ContactAvatar(contact: widget.contact, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    widget.contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  AppText(
                    widget.contact.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: appScreenMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('Refresh messages'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: colors.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AppText(
                _error!,
                style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const _EmptyConversation()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _MessageBubble(
                        message: message,
                        outgoing: message.isOutgoing(widget.student.studentId),
                      );
                    },
                  ),
          ),
          if (widget.contact.isBroadcast)
            Container(
              width: double.infinity,
              color: colors.surfaceContainerLow,
              padding: const EdgeInsets.all(14),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 18),
                  SizedBox(width: 8),
                  AppText('Professor announcements are read-only.'),
                ],
              ),
            )
          else
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: appScreenBorder)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_attachment != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              color: colors.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _attachment!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _documentSize(_attachment!.size),
                                    style: TextStyle(
                                      color: colors.onPrimaryContainer,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('remove-message-attachment'),
                              tooltip: tr('Remove attachment'),
                              onPressed: _sending
                                  ? null
                                  : () => setState(() => _attachment = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          key: const Key('attach-message-document'),
                          tooltip: tr('Attach document'),
                          onPressed: _sending ? null : _pickAttachment,
                          icon: const Icon(Icons.attach_file_rounded),
                        ),
                        Expanded(
                          child: TextField(
                            key: const Key('message-composer'),
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: tr('Write a message…'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const Key('send-message'),
                          tooltip: tr('Send message'),
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessagesHero extends StatelessWidget {
  const _MessagesHero({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF123765), Color(0xFF2563EB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x332563EB),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.forum_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText(
                'Campus Messages',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              AppText(
                unread == 0 ? 'You are all caught up.' : '$unread unread',
                style: const TextStyle(color: Color(0xFFDCEAFF)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.contact,
    required this.latest,
    required this.unread,
    required this.onTap,
  });

  final MessageContact contact;
  final PortalMessage? latest;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: appScreenSurface,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appScreenBorder),
        ),
        child: Row(
          children: [
            _ContactAvatar(contact: contact),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (latest != null)
                        Text(
                          _shortTime(latest!.createdAt),
                          style: TextStyle(color: appScreenMuted, fontSize: 11),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          latest?.body.isNotEmpty == true
                              ? latest!.body
                              : latest?.attachment?.filename ??
                                    contact.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? appScreenInk : appScreenMuted,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: uniTrackBlue,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.contact, this.radius = 25});
  final MessageContact contact;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final staff = contact.type == 'staff';
    final icon = contact.isBroadcast
        ? Icons.campaign_rounded
        : staff
        ? Icons.school_rounded
        : Icons.person_rounded;
    return CircleAvatar(
      radius: radius,
      backgroundColor: staff || contact.isBroadcast
          ? const Color(0xFFEAF2FF)
          : const Color(0xFFEAF9F5),
      foregroundColor: staff || contact.isBroadcast
          ? uniTrackBlue
          : const Color(0xFF13866F),
      child: Icon(icon, size: radius),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.outgoing});
  final PortalMessage message;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .78,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: outgoing
            ? uniTrackBlue
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(outgoing ? 18 : 4),
          bottomRight: Radius.circular(outgoing ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.body.isNotEmpty)
            Text(
              message.body,
              textDirection: containsArabic(message.body)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: TextStyle(
                color: outgoing ? Colors.white : appScreenInk,
                height: 1.35,
              ),
            ),
          if (message.attachment != null) ...[
            if (message.body.isNotEmpty) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: outgoing
                    ? Colors.white.withValues(alpha: .14)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: outgoing ? Colors.white : uniTrackBlue,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      message.attachment!.filename,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: outgoing ? Colors.white : appScreenInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _documentSize(message.attachment!.sizeBytes),
                    style: TextStyle(
                      color: outgoing ? Colors.white70 : appScreenMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            _shortTime(message.createdAt),
            style: TextStyle(
              color: outgoing ? Colors.white70 : appScreenMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageError extends StatelessWidget {
  const _MessageError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        AppText(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const AppText('Try again'),
        ),
      ],
    ),
  );
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(36),
    child: Column(
      children: [
        Icon(Icons.forum_outlined, size: 46, color: uniTrackBlue),
        SizedBox(height: 12),
        AppText('No message contacts are available yet.'),
      ],
    ),
  );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.waving_hand_outlined, size: 42, color: uniTrackBlue),
          SizedBox(height: 12),
          AppText(
            'Start the conversation with a clear question or update.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String _shortTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
  return '${local.day}/${local.month}/${local.year}';
}

String _documentSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil().clamp(1, 1024)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

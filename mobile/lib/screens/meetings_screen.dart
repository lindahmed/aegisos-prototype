import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/student.dart';
import '../services/meeting_session.dart';
import '../theme/app_theme.dart';

class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({required this.student, super.key});

  final Student student;

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  late final MeetingSession _session;
  final _titleController = TextEditingController(text: 'Study meeting');
  final _invitationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session = MeetingSession(student: widget.student);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _invitationController.dispose();
    _session.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    await _session.leave();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _session,
    builder: (context, _) => PopScope(
      canPop: !_session.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leave();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: AppText(
            _session.active ? _session.title : 'Live Meetings',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (_session.active)
              IconButton(
                tooltip: tr('Participants'),
                onPressed: () => _showParticipants(context),
                icon: Badge(
                  label: Text('${_session.members.length}'),
                  child: const Icon(Icons.groups_rounded),
                ),
              ),
          ],
        ),
        body: _session.active ? _room(context) : _lobby(context),
      ),
    ),
  );

  Widget _lobby(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF123765), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.video_call_rounded, color: Colors.white, size: 38),
            SizedBox(height: 18),
            AppText(
              'Host or join a live meeting',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 7),
            AppText(
              'Start a room, approve participants, and control speaking and presenting permissions.',
              style: TextStyle(color: Color(0xFFDCEAFF), height: 1.4),
            ),
          ],
        ),
      ),
      if (_session.error != null) ...[
        const SizedBox(height: 14),
        _MeetingNotice(message: _session.error!, error: true),
      ],
      const SizedBox(height: 22),
      const AppText(
        'HOST A MEETING',
        style: TextStyle(
          color: uniTrackBlue,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 9),
      _MeetingCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('meeting-title'),
              controller: _titleController,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: tr('Meeting title'),
                prefixIcon: const Icon(Icons.edit_calendar_rounded),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('host-meeting'),
              onPressed: _session.connecting
                  ? null
                  : () => _session.host(_titleController.text),
              icon: const Icon(Icons.video_call_rounded),
              label: const AppText('Start meeting'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const AppText(
        'JOIN A MEETING',
        style: TextStyle(
          color: uniTrackBlue,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 9),
      _MeetingCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('meeting-invitation'),
              controller: _invitationController,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr('Meeting invitation'),
                hintText: 'ws://192.168.1.10:8765#…',
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('join-meeting'),
              onPressed: _session.connecting
                  ? null
                  : () => _session.join(_invitationController.text),
              icon: const Icon(Icons.login_rounded),
              label: const AppText('Request to join'),
            ),
          ],
        ),
      ),
      if (_session.connecting) ...[
        const SizedBox(height: 18),
        const LinearProgressIndicator(),
        const SizedBox(height: 9),
        AppText(_session.status, textAlign: TextAlign.center),
      ],
      const SizedBox(height: 20),
      const _MeetingNotice(
        message: 'For nearby devices, keep the host and participants on the same Wi-Fi network. Internet meetings require the public WSS and TURN setup described by the desktop meeting service.',
      ),
    ],
  );

  Widget _room(BuildContext context) {
    final admitted = _session.me?.admitted == true;
    final videoMembers = _session.members.where(
      (member) => member.admitted && (member.camera || member.screen),
    );
    return Column(
      children: [
        if (_session.error != null)
          _MeetingNotice(message: _session.error!, error: true),
        if (_session.hosting && _session.invitation.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'INVITATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _session.invitation,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('copy-meeting-invitation'),
                  tooltip: tr('Copy invitation'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _session.invitation),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: AppText('Invitation copied.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF20B486),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  _session.status,
                  style: TextStyle(color: appScreenMuted),
                ),
              ),
              AppText(
                '${_session.members.where((member) => member.admitted).length} in meeting',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Expanded(
          child: !admitted
              ? const _WaitingRoom()
              : videoMembers.isEmpty
              ? _StageEmpty(session: _session)
              : GridView.count(
                  padding: const EdgeInsets.all(12),
                  crossAxisCount: MediaQuery.sizeOf(context).width > 700
                      ? 3
                      : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 3 / 4,
                  children: [
                    for (final member in videoMembers)
                      if (member.camera)
                        _VideoTile(
                          session: _session,
                          member: member,
                          lane: 'camera',
                        ),
                    for (final member in videoMembers)
                      if (member.screen)
                        _VideoTile(
                          session: _session,
                          member: member,
                          lane: 'screen',
                        ),
                  ],
                ),
        ),
        if (admitted) _controls(context),
      ],
    );
  }

  Widget _controls(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: appScreenBorder)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 7,
        children: [
          _MeetingControl(
            key: const Key('meeting-microphone'),
            icon: _session.microphoneOn
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            label: _session.microphoneOn ? 'Mute' : 'Unmute',
            active: _session.microphoneOn,
            enabled: _session.me?.canSpeak == true,
            onTap: () => _run(_session.toggleMicrophone),
          ),
          _MeetingControl(
            key: const Key('meeting-camera'),
            icon: _session.cameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: _session.cameraOn ? 'Camera off' : 'Camera on',
            active: _session.cameraOn,
            onTap: () => _run(_session.toggleCamera),
          ),
          _MeetingControl(
            key: const Key('meeting-screen'),
            icon: _session.screenOn
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            label: _session.screenOn ? 'Stop sharing' : 'Share screen',
            active: _session.screenOn,
            enabled: _session.me?.canShare == true,
            onTap: () => _run(_session.toggleScreen),
          ),
          _MeetingControl(
            icon: Icons.pan_tool_alt_rounded,
            label: _session.me?.hand == true ? 'Lower hand' : 'Raise hand',
            active: _session.me?.hand == true,
            onTap: _session.toggleHand,
          ),
          _MeetingControl(
            icon: Icons.draw_rounded,
            label: 'Whiteboard',
            enabled: _session.admitted,
            onTap: () => _openWhiteboard(context),
          ),
          _MeetingControl(
            icon: Icons.call_end_rounded,
            label: _session.isHost ? 'End' : 'Leave',
            danger: true,
            onTap: () => _confirmExit(context),
          ),
        ],
      ),
    ),
  );

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // MeetingSession publishes the user-facing error itself.
    }
  }

  Future<void> _confirmExit(BuildContext context) async {
    final endForEveryone = _session.isHost;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(endForEveryone ? 'End meeting?' : 'Leave meeting?'),
        content: AppText(
          endForEveryone
              ? 'This will end the meeting for everyone.'
              : 'You can rejoin later with the invitation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(endForEveryone ? 'End for everyone' : 'Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (endForEveryone) {
      _session.endForEveryone();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _session.leave();
  }

  Future<void> _showParticipants(
    BuildContext context,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => AnimatedBuilder(
      animation: _session,
      builder: (context, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            const AppText(
              'Participants',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            AppText(
              '${_session.members.where((member) => member.admitted).length} admitted · ${_session.members.where((member) => !member.admitted).length} waiting',
              style: TextStyle(color: appScreenMuted),
            ),
            if (_session.isHost) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _session.muteAll,
                icon: const Icon(Icons.mic_off_rounded),
                label: const AppText('Mute all'),
              ),
            ],
            const SizedBox(height: 12),
            for (final member in _session.members)
              _ParticipantCard(session: _session, member: member),
          ],
        ),
      ),
    ),
  );

  Future<void> _openWhiteboard(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MeetingWhiteboardScreen(session: _session),
        ),
      );
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: appScreenBorder),
    ),
    child: child,
  );
}

class _MeetingNotice extends StatelessWidget {
  const _MeetingNotice({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: AppText(message, style: const TextStyle(height: 1.35)),
  );
}

class _WaitingRoom extends StatelessWidget {
  const _WaitingRoom();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 18),
          AppText(
            'Waiting for the host to approve your request',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 7),
          AppText(
            'Your camera and microphone stay off until you are admitted.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _StageEmpty extends StatelessWidget {
  const _StageEmpty({required this.session});
  final MeetingSession session;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: const BoxDecoration(
              color: uniTrackBlueSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: uniTrackBlue,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          AppText(
            session.isHost ? 'Your meeting is live' : 'You are in the meeting',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          AppText(
            session.isHost
                ? 'Share the invitation and approve participants when they arrive.'
                : 'Camera and shared screens will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: appScreenMuted),
          ),
        ],
      ),
    ),
  );
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.session,
    required this.member,
    required this.lane,
  });
  final MeetingSession session;
  final MeetingMember member;
  final String lane;

  @override
  Widget build(BuildContext context) {
    final renderer = session.rendererFor(member.id, lane);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (renderer != null)
            RTCVideoView(
              renderer,
              mirror: lane == 'camera' && member.id == session.selfId,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${member.name}${member.id == session.selfId ? ' · ${tr('You')}' : ''}${lane == 'screen' ? ' · ${tr('Screen')}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingControl extends StatelessWidget {
  const _MeetingControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
    this.danger = false,
    super.key,
  });
  final IconData icon;
  final String label;
  final FutureOr<void> Function() onTap;
  final bool active;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: enabled ? () => onTap() : null,
          style: IconButton.styleFrom(
            backgroundColor: danger
                ? const Color(0xFFFFE4E8)
                : active
                ? uniTrackBlue
                : null,
            foregroundColor: danger
                ? const Color(0xFFCC294B)
                : active
                ? Colors.white
                : null,
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: 2),
        AppText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({required this.session, required this.member});
  final MeetingSession session;
  final MeetingMember member;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: appScreenBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: uniTrackBlueSoft,
              foregroundColor: uniTrackBlue,
              child: Icon(member.host ? Icons.workspace_premium : Icons.person),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${member.hand ? '✋ ' : ''}${member.name}${member.id == session.selfId ? ' · ${tr('You')}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  AppText(
                    member.host
                        ? 'Host'
                        : !member.admitted
                        ? 'Waiting for approval'
                        : '${member.mic ? 'Speaking' : 'Muted'} · ${member.canShare ? 'May present' : 'View only'}',
                    style: TextStyle(color: appScreenMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (session.isHost && !member.host) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: member.admitted
                ? [
                    _SmallAction(
                      label: member.canSpeak
                          ? 'Revoke speaking'
                          : 'Allow speaking',
                      onTap: () => session.setSpeakingPermission(
                        member,
                        !member.canSpeak,
                      ),
                    ),
                    _SmallAction(
                      label: member.canShare
                          ? 'Revoke presenting'
                          : 'Allow presenting',
                      onTap: () => session.setPresentingPermission(
                        member,
                        !member.canShare,
                      ),
                    ),
                    _SmallAction(
                      label: 'Remove',
                      danger: true,
                      onTap: () => session.remove(member),
                    ),
                  ]
                : [
                    _SmallAction(
                      label: 'Admit',
                      onTap: () => session.admit(member),
                    ),
                    _SmallAction(
                      label: 'Decline',
                      danger: true,
                      onTap: () => session.reject(member),
                    ),
                  ],
          ),
        ],
      ],
    ),
  );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: danger ? const Color(0xFFCC294B) : null,
      visualDensity: VisualDensity.compact,
    ),
    child: AppText(label),
  );
}

class MeetingWhiteboardScreen extends StatefulWidget {
  const MeetingWhiteboardScreen({required this.session, super.key});
  final MeetingSession session;

  @override
  State<MeetingWhiteboardScreen> createState() =>
      _MeetingWhiteboardScreenState();
}

class _MeetingWhiteboardScreenState extends State<MeetingWhiteboardScreen> {
  final List<OffsetValue> _drawing = [];
  String _color = '#2563EB';
  double _width = 3;

  bool get _canDraw => widget.session.me?.canShare == true;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const AppText(
          'Whiteboard',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (widget.session.isHost)
            IconButton(
              tooltip: tr('Clear whiteboard'),
              onPressed: widget.session.clearBoard,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final color in const [
                  '#2563EB',
                  '#101D39',
                  '#E83E5A',
                  '#20B486',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: _canDraw
                          ? () => setState(() => _color = color)
                          : null,
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _hexColor(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: _color == color
                              ? const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 1,
                    max: 12,
                    divisions: 11,
                    onChanged: _canDraw
                        ? (value) => setState(() => _width = value)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (!_canDraw)
            const _MeetingNotice(
              message: 'The host must allow presenting before you can draw.',
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                key: const Key('meeting-whiteboard'),
                onPanStart: !_canDraw
                    ? null
                    : (details) =>
                          _addPoint(details.localPosition, constraints.biggest),
                onPanUpdate: !_canDraw
                    ? null
                    : (details) =>
                          _addPoint(details.localPosition, constraints.biggest),
                onPanEnd: !_canDraw
                    ? null
                    : (_) {
                        if (_drawing.length > 1) {
                          widget.session.sendStroke(
                            MeetingStroke(
                              color: _color,
                              width: _width,
                              points: List.of(_drawing),
                            ),
                          );
                        }
                        setState(_drawing.clear);
                      },
                child: CustomPaint(
                  size: constraints.biggest,
                  painter: _WhiteboardPainter(
                    strokes: widget.session.strokes,
                    drawing: _drawing,
                    drawingColor: _color,
                    drawingWidth: _width,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _addPoint(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0 || _drawing.length >= 256) return;
    setState(
      () => _drawing.add(
        OffsetValue(
          (position.dx / size.width).clamp(0, 1),
          (position.dy / size.height).clamp(0, 1),
        ),
      ),
    );
  }
}

class _WhiteboardPainter extends CustomPainter {
  const _WhiteboardPainter({
    required this.strokes,
    required this.drawing,
    required this.drawingColor,
    required this.drawingWidth,
  });
  final List<MeetingStroke> strokes;
  final List<OffsetValue> drawing;
  final String drawingColor;
  final double drawingWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    for (final stroke in strokes) {
      _draw(canvas, size, stroke.points, _hexColor(stroke.color), stroke.width);
    }
    _draw(canvas, size, drawing, _hexColor(drawingColor), drawingWidth);
  }

  void _draw(
    Canvas canvas,
    Size size,
    List<OffsetValue> points,
    Color color,
    double width,
  ) {
    if (points.length < 2) return;
    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) => true;
}

Color _hexColor(String value) =>
    Color(int.parse(value.replaceFirst('#', 'FF'), radix: 16));

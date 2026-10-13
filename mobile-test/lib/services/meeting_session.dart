import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/student.dart';
import 'meeting_server.dart';

const meetingLanes = ['audio', 'camera', 'screen'];

class MeetingMember {
  const MeetingMember({
    required this.id,
    required this.name,
    required this.role,
    required this.host,
    required this.admitted,
    required this.canSpeak,
    required this.canShare,
    required this.mic,
    required this.camera,
    required this.screen,
    required this.hand,
  });

  factory MeetingMember.fromJson(Map<String, dynamic> json) => MeetingMember(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Participant',
    role: json['role']?.toString() ?? 'guest',
    host: json['host'] == true,
    admitted: json['admitted'] == true,
    canSpeak: json['canSpeak'] == true,
    canShare: json['canShare'] == true,
    mic: json['mic'] == true,
    camera: json['camera'] == true,
    screen: json['screen'] == true,
    hand: json['hand'] == true,
  );

  final String id;
  final String name;
  final String role;
  final bool host;
  final bool admitted;
  final bool canSpeak;
  final bool canShare;
  final bool mic;
  final bool camera;
  final bool screen;
  final bool hand;
}

class MeetingStroke {
  const MeetingStroke({
    required this.color,
    required this.width,
    required this.points,
  });

  factory MeetingStroke.fromJson(Map<String, dynamic> json) => MeetingStroke(
    color: json['color']?.toString() ?? '#2563EB',
    width: (json['width'] as num?)?.toDouble() ?? 3,
    points: ((json['points'] as List<dynamic>?) ?? const [])
        .whereType<List<dynamic>>()
        .where((point) => point.length == 2)
        .map(
          (point) => OffsetValue(
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
        )
        .toList(),
  );

  final String color;
  final double width;
  final List<OffsetValue> points;

  Map<String, dynamic> toJson() => {
    'color': color,
    'width': width,
    'points': points.map((point) => [point.dx, point.dy]).toList(),
  };
}

class OffsetValue {
  const OffsetValue(this.dx, this.dy);
  final double dx;
  final double dy;
}

class MeetingSession extends ChangeNotifier {
  MeetingSession({required this.student});

  final Student student;
  bool _disposed = false;
  MobileMeetingServer? _server;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Completer<Map<String, dynamic>>? _configurationCompleter;
  Map<String, dynamic> _rtcConfiguration = const {};
  final Map<String, _MeetingPeer> _peers = {};
  final Map<String, MediaStreamTrack> _tracks = {};
  final Map<String, MediaStream> _localStreams = {};
  final Map<String, RTCVideoRenderer> _renderers = {};
  final List<MeetingStroke> _strokes = [];

  bool connecting = false;
  bool active = false;
  bool hosting = false;
  String status = 'Host a meeting or paste an invitation.';
  String? error;
  String? selfId;
  String title = 'Live meeting';
  String invitation = '';
  List<MeetingMember> members = const [];

  MeetingMember? get me {
    final id = selfId;
    if (id == null) return null;
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  bool get admitted => me?.admitted == true;
  bool get isHost => me?.host == true;
  bool get microphoneOn => _tracks.containsKey('audio');
  bool get cameraOn => _tracks.containsKey('camera');
  bool get screenOn => _tracks.containsKey('screen');
  List<MeetingStroke> get strokes => List.unmodifiable(_strokes);

  RTCVideoRenderer? rendererFor(String memberId, String lane) =>
      _renderers['$memberId:$lane'];

  Future<void> host(String meetingTitle) async {
    if (connecting) return;
    await leave();
    connecting = true;
    error = null;
    status = 'Starting meeting…';
    notifyListeners();
    try {
      _server = await MobileMeetingServer.start(
        title: meetingTitle,
        identityName: student.name,
      );
      invitation = await _server!.invitation();
      hosting = true;
      final localEndpoint = Uri(
        scheme: 'ws',
        host: '127.0.0.1',
        port: _server!.port,
      );
      await _connect(
        localEndpoint,
        roomKey: _server!.roomKey,
        hostKey: _server!.hostKey,
      );
      status = 'Meeting started. Share the invitation and approve requests.';
    } on Object catch (caught) {
      error = _friendlyError(caught);
      await leave(preserveMessage: true);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> join(String rawInvitation) async {
    if (connecting) return;
    await leave();
    connecting = true;
    error = null;
    status = 'Connecting to the host…';
    notifyListeners();
    try {
      final parsed = parseMeetingInvitation(rawInvitation);
      Object? lastError;
      for (final endpoint in parsed.endpoints) {
        try {
          await _connect(endpoint, roomKey: parsed.roomKey);
          lastError = null;
          break;
        } on Object catch (caught) {
          lastError = caught;
          await _disconnectSocket();
        }
      }
      if (lastError != null || !active) {
        throw lastError ??
            const MeetingException('Cannot reach the meeting host.');
      }
      status = 'Join request sent. Please wait for host approval.';
    } on Object catch (caught) {
      error = _friendlyError(caught);
      await leave(preserveMessage: true);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> _connect(
    Uri endpoint, {
    required String roomKey,
    String? hostKey,
  }) async {
    final socket = await WebSocket.connect(endpoint.toString()).timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw const MeetingException(
        'Cannot reach the meeting host. Check the address and network.',
      ),
    );
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 15);
    _configurationCompleter = Completer<Map<String, dynamic>>();
    _socketSubscription = socket.listen(
      _onMessage,
      onDone: () {
        if (!active) return;
        error = 'Meeting connection lost. Rejoin with your invitation.';
        unawaited(leave(preserveMessage: true));
      },
      onError: (_) {
        if (active) error = 'Meeting connection lost.';
      },
      cancelOnError: false,
    );
    _send({
      'type': 'join',
      'roomKey': roomKey,
      'hostKey': ?hostKey,
      'name': student.name,
    });
    _rtcConfiguration = await _configurationCompleter!.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw const MeetingException(
        'The meeting host did not provide media configuration.',
      ),
    );
    active = true;
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final type = decoded['type']?.toString();
      if (type == 'configuration') {
        final configuration = decoded['configuration'];
        if (configuration is! Map<String, dynamic>) {
          throw const MeetingException('Invalid meeting media configuration.');
        }
        if (!(_configurationCompleter?.isCompleted ?? true)) {
          _configurationCompleter!.complete(configuration);
        }
      } else if (type == 'joined') {
        selfId = decoded['id']?.toString();
      } else if (type == 'state') {
        _applyState(decoded);
      } else if (type == 'signal') {
        unawaited(_receiveSignal(decoded));
      } else if (type == 'board') {
        _strokes
          ..clear()
          ..addAll(
            ((decoded['strokes'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MeetingStroke.fromJson),
          );
        notifyListeners();
      } else if (type == 'stroke') {
        final stroke = decoded['stroke'];
        if (stroke is Map<String, dynamic>) {
          _strokes.add(MeetingStroke.fromJson(stroke));
          notifyListeners();
        }
      } else if (type == 'error') {
        final message = decoded['message']?.toString() ?? 'Meeting error.';
        error = message;
        if (!(_configurationCompleter?.isCompleted ?? true)) {
          _configurationCompleter!.completeError(MeetingException(message));
        }
        notifyListeners();
      } else if (type == 'ended' ||
          type == 'removed' ||
          type == 'disconnected') {
        final reason = decoded['reason']?.toString() ?? 'Meeting ended.';
        error = type == 'ended' ? null : reason;
        status = reason;
        unawaited(leave(preserveMessage: true));
      }
    } on Object {
      error = 'Invalid meeting response.';
      notifyListeners();
    }
  }

  void _applyState(Map<String, dynamic> state) {
    title = state['title']?.toString() ?? title;
    selfId = state['selfId']?.toString() ?? selfId;
    members = ((state['members'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MeetingMember.fromJson)
        .toList();
    final current = me;
    if (current?.admitted == true) {
      status =
          '${members.where((member) => member.admitted).length} in meeting';
    } else {
      status = 'Waiting for approval';
    }
    if (microphoneOn && current?.canSpeak != true) unawaited(stopLane('audio'));
    if (screenOn && current?.canShare != true) unawaited(stopLane('screen'));
    if (current?.admitted != true) {
      for (final lane in meetingLanes) {
        if (_tracks.containsKey(lane)) unawaited(stopLane(lane));
      }
    }
    unawaited(_syncPeers());
    notifyListeners();
  }

  Future<void> _syncPeers() async {
    final currentId = selfId;
    if (currentId == null || !admitted) return;
    final ids = members
        .where((member) => member.admitted && member.id != currentId)
        .map((member) => member.id)
        .toSet();
    for (final entry in _peers.entries.toList()) {
      if (!ids.contains(entry.value.memberId)) await _dropPeer(entry.key);
    }
    for (final id in ids) {
      for (final lane in meetingLanes) {
        await _createPeer(id, lane);
      }
    }
  }

  Future<_MeetingPeer> _createPeer(String memberId, String lane) async {
    final key = '$memberId:$lane';
    final existing = _peers[key];
    if (existing != null) return existing;
    final connection = await createPeerConnection({
      ..._rtcConfiguration,
      'sdpSemantics': 'unified-plan',
    });
    final currentId = selfId!;
    final offerer = currentId.compareTo(memberId) < 0;
    final peer = _MeetingPeer(
      memberId: memberId,
      lane: lane,
      connection: connection,
      offerer: offerer,
    );
    _peers[key] = peer;
    connection.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || !active) return;
      _send({
        'type': 'signal',
        'target': memberId,
        'lane': lane,
        'data': {
          'candidate': {
            'candidate': candidateValue,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        },
      });
    };
    connection.onTrack = (event) {
      unawaited(_attachRemoteTrack(memberId, lane, event));
    };
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error =
            'Media connection failed. The host may need TURN configuration.';
        notifyListeners();
      }
    };
    if (offerer) {
      final transceiver = await connection.addTransceiver(
        kind: lane == 'audio'
            ? RTCRtpMediaType.RTCRtpMediaTypeAudio
            : RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      peer.sender = transceiver.sender;
      await peer.sender?.replaceTrack(_tracks[lane]);
      final offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      _sendDescription(memberId, lane, offer);
    }
    return peer;
  }

  Future<void> _attachRemoteTrack(
    String memberId,
    String lane,
    RTCTrackEvent event,
  ) async {
    final renderer = await _renderer('$memberId:$lane');
    if (event.streams.isNotEmpty) {
      renderer.srcObject = event.streams.first;
    } else {
      final stream = await createLocalMediaStream('remote-$memberId-$lane');
      stream.addTrack(event.track);
      renderer.srcObject = stream;
    }
    notifyListeners();
  }

  Future<RTCVideoRenderer> _renderer(String key) async {
    final existing = _renderers[key];
    if (existing != null) return existing;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _renderers[key] = renderer;
    return renderer;
  }

  Future<void> _receiveSignal(Map<String, dynamic> message) async {
    if (!admitted) return;
    final from = message['from']?.toString();
    final lane = message['lane']?.toString();
    final data = message['data'];
    if (from == null || !meetingLanes.contains(lane) || data is! Map) return;
    final peer = await _createPeer(from, lane!);
    peer.chain = peer.chain
        .then((_) async {
          if (!active) return;
          final description = data['description'];
          final candidate = data['candidate'];
          if (description is Map) {
            final type = description['type']?.toString();
            final sdp = description['sdp']?.toString();
            if (type == null ||
                sdp == null ||
                !{'offer', 'answer'}.contains(type)) {
              throw const MeetingException('Invalid media negotiation.');
            }
            await peer.connection.setRemoteDescription(
              RTCSessionDescription(sdp, type),
            );
            if (type == 'offer') {
              final transceivers = await peer.connection.getTransceivers();
              if (transceivers.isEmpty) {
                throw const MeetingException('Invalid media offer.');
              }
              await transceivers.first.setDirection(
                TransceiverDirection.SendRecv,
              );
              peer.sender = transceivers.first.sender;
              await peer.sender?.replaceTrack(_tracks[lane]);
            }
            for (final queued in peer.candidates.toList()) {
              await peer.connection.addCandidate(queued);
            }
            peer.candidates.clear();
            if (type == 'offer') {
              final answer = await peer.connection.createAnswer();
              await peer.connection.setLocalDescription(answer);
              _sendDescription(from, lane, answer);
            }
          } else if (candidate is Map) {
            final parsed = RTCIceCandidate(
              candidate['candidate']?.toString(),
              candidate['sdpMid']?.toString(),
              (candidate['sdpMLineIndex'] as num?)?.toInt(),
            );
            if (await peer.connection.getRemoteDescription() != null) {
              await peer.connection.addCandidate(parsed);
            } else if (peer.candidates.length < 100) {
              peer.candidates.add(parsed);
            }
          }
        })
        .catchError((Object caught) {
          error = 'Media connection failed: ${_friendlyError(caught)}';
          notifyListeners();
        });
  }

  void _sendDescription(
    String memberId,
    String lane,
    RTCSessionDescription description,
  ) {
    _send({
      'type': 'signal',
      'target': memberId,
      'lane': lane,
      'data': {
        'description': {'type': description.type, 'sdp': description.sdp},
      },
    });
  }

  Future<void> toggleMicrophone() async {
    if (microphoneOn) return stopLane('audio');
    if (!admitted || me?.canSpeak != true) {
      throw const MeetingException('The host must allow you to speak.');
    }
    await _startLane(
      'audio',
      () => navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': false,
      }),
    );
  }

  Future<void> toggleCamera() async {
    if (cameraOn) return stopLane('camera');
    if (!admitted) throw const MeetingException('Wait for host approval.');
    await _startLane(
      'camera',
      () => navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 360},
          'frameRate': {'ideal': 20},
        },
      }),
    );
  }

  Future<void> toggleScreen() async {
    if (screenOn) return stopLane('screen');
    if (!admitted || me?.canShare != true) {
      throw const MeetingException('The host must allow screen sharing.');
    }
    await _startLane(
      'screen',
      () => navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': {'frameRate': 15},
      }),
    );
  }

  Future<void> _startLane(
    String lane,
    Future<MediaStream> Function() acquire,
  ) async {
    error = null;
    try {
      final stream = await acquire();
      final candidates = lane == 'audio'
          ? stream.getAudioTracks()
          : stream.getVideoTracks();
      if (candidates.isEmpty) {
        throw MeetingException('${_laneName(lane)} is unavailable.');
      }
      final track = candidates.first;
      _tracks[lane] = track;
      _localStreams[lane] = stream;
      track.onEnded = () => unawaited(stopLane(lane));
      for (final peer in _peers.values.where((peer) => peer.lane == lane)) {
        await peer.sender?.replaceTrack(track);
      }
      if (lane != 'audio' && selfId != null) {
        final renderer = await _renderer('$selfId:$lane');
        renderer
          ..srcObject = stream
          ..muted = true;
      }
      _send({'type': 'media', lane == 'audio' ? 'mic' : lane: true});
      status = '${_laneName(lane)} on.';
      notifyListeners();
    } on Object catch (caught) {
      error = '${_laneName(lane)} unavailable: ${_friendlyError(caught)}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopLane(String lane, {bool announce = true}) async {
    final track = _tracks.remove(lane);
    track?.onEnded = null;
    await track?.stop();
    final stream = _localStreams.remove(lane);
    await stream?.dispose();
    if (selfId != null) {
      final renderer = _renderers['$selfId:$lane'];
      if (renderer != null) renderer.srcObject = null;
    }
    for (final peer in _peers.values.where((peer) => peer.lane == lane)) {
      await peer.sender?.replaceTrack(null);
    }
    if (announce && active && admitted) {
      _send({'type': 'media', lane == 'audio' ? 'mic' : lane: false});
    }
    notifyListeners();
  }

  Future<void> toggleHand() async {
    if (!admitted) return;
    _send({'type': 'hand', 'raised': !(me?.hand ?? false)});
  }

  void hostAction(String type, MeetingMember member, {bool? value}) {
    if (!isHost) return;
    _send({
      'type': type,
      'target': member.id,
      if (type == 'permissions' && value != null) 'canSpeak': value,
    });
  }

  void setSpeakingPermission(MeetingMember member, bool allowed) =>
      _send({'type': 'permissions', 'target': member.id, 'canSpeak': allowed});

  void setPresentingPermission(MeetingMember member, bool allowed) =>
      _send({'type': 'permissions', 'target': member.id, 'canShare': allowed});

  void admit(MeetingMember member) =>
      _send({'type': 'admit', 'target': member.id});
  void reject(MeetingMember member) =>
      _send({'type': 'reject', 'target': member.id});
  void remove(MeetingMember member) =>
      _send({'type': 'remove', 'target': member.id});
  void muteAll() => _send({'type': 'mute-all'});
  void clearBoard() => _send({'type': 'clear-board'});
  void endForEveryone() => _send({'type': 'end'});

  void sendStroke(MeetingStroke stroke) {
    if (!admitted || me?.canShare != true || stroke.points.length < 2) return;
    _send({'type': 'stroke', 'stroke': stroke.toJson()});
  }

  void _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const MeetingException('Meeting is disconnected.');
    }
    final serialized = jsonEncode(message);
    if (serialized.length > 96000) {
      throw const MeetingException('Meeting message too large.');
    }
    socket.add(serialized);
  }

  Future<void> _dropPeer(String key) async {
    final peer = _peers.remove(key);
    if (peer == null) return;
    await peer.connection.close();
    await peer.connection.dispose();
    final renderer = _renderers.remove(key);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
  }

  Future<void> _disconnectSocket() async {
    active = false;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  Future<void> leave({bool preserveMessage = false}) async {
    active = false;
    connecting = false;
    for (final lane in meetingLanes) {
      if (_tracks.containsKey(lane)) {
        await stopLane(lane, announce: false);
      }
    }
    for (final key in _peers.keys.toList()) {
      await _dropPeer(key);
    }
    for (final renderer in _renderers.values.toList()) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _renderers.clear();
    await _disconnectSocket();
    final server = _server;
    _server = null;
    await server?.close();
    selfId = null;
    members = const [];
    hosting = false;
    invitation = '';
    _strokes.clear();
    if (!preserveMessage) {
      error = null;
      status = 'Host a meeting or paste an invitation.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(leave());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}

class ParsedMeetingInvitation {
  const ParsedMeetingInvitation({
    required this.roomKey,
    required this.endpoints,
  });
  final String roomKey;
  final List<Uri> endpoints;
}

ParsedMeetingInvitation parseMeetingInvitation(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !{'ws', 'wss'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const MeetingException('Use a ws:// or wss:// meeting address.');
  }
  final roomKey = uri.fragment;
  if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(roomKey)) {
    throw const MeetingException('Paste the complete meeting invitation.');
  }
  final base = uri.replace(fragment: '', queryParameters: const {});
  final endpoints = <Uri>[base];
  final fallbacks = uri.queryParametersAll['fallback'] ?? const [];
  if (fallbacks.length > 6) {
    throw const MeetingException('Paste a valid meeting invitation.');
  }
  for (final address in fallbacks) {
    if (InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4) {
      throw const MeetingException('Paste a valid meeting invitation.');
    }
    final fallback = base.replace(host: address);
    if (!endpoints.contains(fallback)) endpoints.add(fallback);
  }
  return ParsedMeetingInvitation(roomKey: roomKey, endpoints: endpoints);
}

class MeetingException implements Exception {
  const MeetingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _MeetingPeer {
  _MeetingPeer({
    required this.memberId,
    required this.lane,
    required this.connection,
    required this.offerer,
  });

  final String memberId;
  final String lane;
  final RTCPeerConnection connection;
  final bool offerer;
  RTCRtpSender? sender;
  List<RTCIceCandidate> candidates = [];
  Future<void> chain = Future.value();
}

String _friendlyError(Object error) {
  if (error is MeetingException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

String _laneName(String lane) => switch (lane) {
  'audio' => 'Microphone',
  'camera' => 'Camera',
  _ => 'Screen sharing',
};

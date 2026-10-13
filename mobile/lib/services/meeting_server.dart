import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const meetingPort = 8765;
const meetingMaxMembers = 12;
const _meetingLanes = {'audio', 'camera', 'screen'};

class MobileMeetingServer {
  MobileMeetingServer._({
    required this.title,
    required this.identityName,
    required this.identityRole,
    required this.roomKey,
    required this.hostKey,
    required this._server,
  });

  final String title;
  final String identityName;
  final String identityRole;
  final String roomKey;
  final String hostKey;
  final HttpServer _server;
  final Map<String, _ServerMember> _members = {};
  final List<Map<String, dynamic>> _strokes = [];
  StreamSubscription<HttpRequest>? _requests;
  String? _hostId;
  int _boardBytes = 0;
  bool _ended = false;

  int get port => _server.port;

  static Future<MobileMeetingServer> start({
    required String title,
    required String identityName,
    String identityRole = 'student',
    int preferredPort = meetingPort,
  }) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        preferredPort,
        shared: false,
      );
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: false);
    }
    final result = MobileMeetingServer._(
      title: title.trim().isEmpty ? 'Online meeting' : title.trim(),
      identityName: identityName,
      identityRole: identityRole,
      roomKey: _randomHex(24),
      hostKey: _randomHex(32),
      server: server,
    );
    result._requests = server.listen(result._handleRequest);
    return result;
  }

  Future<String> invitation() async {
    final addresses = <String>[];
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          final value = address.address;
          if (!value.startsWith('169.254.') && !addresses.contains(value)) {
            addresses.add(value);
          }
        }
      }
    } on SocketException {
      // The loopback fallback still lets the host enter its own room.
    }
    final mainAddress = addresses.isEmpty ? '127.0.0.1' : addresses.first;
    final query = <String, dynamic>{};
    if (addresses.length > 1) {
      query['fallback'] = addresses.skip(1).take(6).toList();
    }
    return Uri(
      scheme: 'ws',
      host: mainAddress,
      port: port,
      queryParameters: query.isEmpty ? null : query,
      fragment: roomKey,
    ).toString();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_ended || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 15);
      _accept(socket);
    } on Object {
      await request.response.close();
    }
  }

  void _accept(WebSocket socket) {
    _ServerMember? member;
    var requestCount = 0;
    var period = DateTime.now();
    final joinTimeout = Timer(const Duration(seconds: 10), () {
      if (member == null) socket.close(1008, 'Join timeout');
    });

    socket.listen(
      (raw) {
        try {
          if (DateTime.now().difference(period) > const Duration(seconds: 1)) {
            period = DateTime.now();
            requestCount = 0;
          }
          requestCount += 1;
          if (requestCount > 320) {
            throw const FormatException('Too many requests.');
          }
          final decoded = jsonDecode(raw.toString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid message.');
          }
          if (member == null) {
            member = _join(socket, decoded);
            joinTimeout.cancel();
            return;
          }
          _handle(member!, decoded);
        } on Object catch (error) {
          _send(socket, {
            'type': 'error',
            'message': error is FormatException
                ? error.message
                : 'Invalid meeting action.',
          });
          if (member == null || requestCount > 320) {
            socket.close(1008, 'Invalid request');
          }
        }
      },
      onDone: () {
        joinTimeout.cancel();
        final departed = member;
        if (departed == null || !_members.containsKey(departed.id)) return;
        _members.remove(departed.id);
        if (departed.host) {
          end('The host disconnected. The lecture has ended.');
        } else {
          _snapshot();
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  _ServerMember _join(WebSocket socket, Map<String, dynamic> message) {
    if (message['type'] != 'join' || message['roomKey'] != roomKey) {
      throw const FormatException('Invalid meeting invitation.');
    }
    final isHost = message['hostKey'] == hostKey;
    if (isHost && _hostId != null) {
      throw const FormatException('The host is already connected.');
    }
    if (!isHost && _hostId == null) {
      throw const FormatException('The host has not started the meeting.');
    }
    if (_members.length >= 48) {
      throw const FormatException('The waiting room is full.');
    }
    final suppliedName = message['name']?.toString().trim() ?? '';
    final name = isHost
        ? identityName
        : suppliedName.substring(0, min(100, suppliedName.length));
    if (name.isEmpty) {
      throw const FormatException('A display name is required.');
    }
    final joined = _ServerMember(
      id: _randomHex(16),
      socket: socket,
      name: name,
      role: isHost ? identityRole : 'guest',
      host: isHost,
      admitted: isHost,
      canSpeak: isHost,
      canShare: isHost,
    );
    _members[joined.id] = joined;
    if (isHost) _hostId = joined.id;
    _send(socket, {
      'type': 'configuration',
      'configuration': {'iceServers': [], 'iceTransportPolicy': 'all'},
    });
    _send(socket, {'type': 'joined', 'id': joined.id});
    _snapshot();
    return joined;
  }

  void _handle(_ServerMember member, Map<String, dynamic> message) {
    final type = message['type']?.toString();
    final target = _members[message['target']?.toString()];
    const hostActions = {
      'admit',
      'reject',
      'remove',
      'permissions',
      'mute-all',
      'end',
      'clear-board',
    };
    if (hostActions.contains(type)) {
      if (!member.host) {
        throw const FormatException('Only the host can perform this action.');
      }
      if (type == 'end') {
        end();
        return;
      }
      if (type == 'clear-board') {
        _strokes.clear();
        _boardBytes = 0;
        for (final item in _members.values.where((value) => value.admitted)) {
          _send(item.socket, {'type': 'board', 'strokes': <Object>[]});
        }
        return;
      }
      if (type == 'mute-all') {
        for (final item in _members.values.where((value) => !value.host)) {
          item
            ..canSpeak = false
            ..mic = false;
        }
      } else {
        if (target == null || target.host) {
          throw const FormatException('Participant unavailable.');
        }
        if (type == 'admit') {
          if (target.admitted) return;
          final admitted = _members.values
              .where((item) => item.admitted)
              .length;
          if (admitted >= meetingMaxMembers) {
            throw const FormatException(
              'This lecture supports up to 12 people.',
            );
          }
          target.admitted = true;
          _send(target.socket, {'type': 'board', 'strokes': _strokes});
        } else if (type == 'reject' || type == 'remove') {
          _remove(
            target,
            type == 'reject'
                ? 'The host declined your request.'
                : 'The host removed you from the lecture.',
          );
          return;
        } else if (type == 'permissions') {
          if (!target.admitted) {
            throw const FormatException('Admit this participant first.');
          }
          if (message['canSpeak'] is bool) {
            target.canSpeak = message['canSpeak'] as bool;
          }
          if (message['canShare'] is bool) {
            target.canShare = message['canShare'] as bool;
          }
          if (!target.canSpeak) target.mic = false;
          if (!target.canShare) target.screen = false;
        }
      }
      _snapshot();
      return;
    }

    if (!member.admitted) {
      throw const FormatException('Wait for host approval.');
    }
    if (type == 'signal') {
      final lane = message['lane']?.toString();
      final data = message['data'];
      if (target == null ||
          !target.admitted ||
          target.id == member.id ||
          !_meetingLanes.contains(lane) ||
          data is! Map<String, dynamic> ||
          jsonEncode(data).length > 64000) {
        throw const FormatException('Invalid signal recipient.');
      }
      _send(target.socket, {
        'type': 'signal',
        'from': member.id,
        'lane': lane,
        'data': data,
      });
    } else if (type == 'media') {
      if (message['mic'] == true && !member.canSpeak) {
        throw const FormatException('The host must allow you to speak.');
      }
      if (message['screen'] == true && !member.canShare) {
        throw const FormatException('The host must allow screen sharing.');
      }
      if (message['mic'] is bool) member.mic = message['mic'] as bool;
      if (message['camera'] is bool) member.camera = message['camera'] as bool;
      if (message['screen'] is bool) member.screen = message['screen'] as bool;
      _snapshot();
    } else if (type == 'hand') {
      member.hand = message['raised'] == true;
      _snapshot();
    } else if (type == 'stroke') {
      if (!member.canShare) {
        throw const FormatException(
          'The host must allow you to present to use the whiteboard.',
        );
      }
      final stroke = message['stroke'];
      if (!_validStroke(stroke)) {
        throw const FormatException('Invalid whiteboard stroke.');
      }
      if (_strokes.length >= 3000) {
        throw const FormatException(
          'Whiteboard full. Ask the host to clear it.',
        );
      }
      final normalized = Map<String, dynamic>.from(stroke as Map);
      final bytes = utf8.encode(jsonEncode(normalized)).length + 1;
      if (_boardBytes + bytes > 2 * 1024 * 1024) {
        throw const FormatException(
          'Whiteboard full. Ask the host to clear it.',
        );
      }
      _boardBytes += bytes;
      _strokes.add(normalized);
      for (final item in _members.values.where((value) => value.admitted)) {
        _send(item.socket, {'type': 'stroke', 'stroke': normalized});
      }
    } else {
      throw const FormatException('Unknown action.');
    }
  }

  bool _validStroke(Object? value) {
    if (value is! Map) return false;
    final color = value['color'];
    final width = value['width'];
    final points = value['points'];
    if (color is! String || !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color)) {
      return false;
    }
    if (width is! num || width < 1 || width > 12) return false;
    if (points is! List || points.length < 2 || points.length > 256) {
      return false;
    }
    return points.every(
      (point) =>
          point is List &&
          point.length == 2 &&
          point.every(
            (coordinate) =>
                coordinate is num && coordinate >= 0 && coordinate <= 1,
          ),
    );
  }

  void _snapshot() {
    for (final member in _members.values) {
      final visible = _members.values
          .where(
            (other) => member.host || other.admitted || other.id == member.id,
          )
          .map((item) => item.publicValue)
          .toList();
      _send(member.socket, {
        'type': 'state',
        'title': title,
        'selfId': member.id,
        'members': visible,
      });
    }
  }

  void _remove(_ServerMember member, String reason) {
    _members.remove(member.id);
    _send(member.socket, {'type': 'removed', 'reason': reason});
    member.socket.close(1000, 'Removed');
    _snapshot();
  }

  void _send(WebSocket socket, Map<String, dynamic> message) {
    if (socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(message));
  }

  Future<void> end([String reason = 'The host ended the lecture.']) async {
    if (_ended) return;
    _ended = true;
    for (final member in _members.values.toList()) {
      _send(member.socket, {'type': 'ended', 'reason': reason});
      await member.socket.close(1000, 'Lecture ended');
    }
    _members.clear();
  }

  Future<void> close() async {
    await end();
    await _requests?.cancel();
    await _server.close(force: true);
  }
}

class _ServerMember {
  _ServerMember({
    required this.id,
    required this.socket,
    required this.name,
    required this.role,
    required this.host,
    required this.admitted,
    required this.canSpeak,
    required this.canShare,
  });

  final String id;
  final WebSocket socket;
  final String name;
  final String role;
  final bool host;
  bool admitted;
  bool canSpeak;
  bool canShare;
  bool mic = false;
  bool camera = false;
  bool screen = false;
  bool hand = false;

  Map<String, dynamic> get publicValue => {
    'id': id,
    'name': name,
    'role': role,
    'host': host,
    'admitted': admitted,
    'canSpeak': canSpeak,
    'canShare': canShare,
    'mic': mic,
    'camera': camera,
    'screen': screen,
    'hand': hand,
  };
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List<int>.generate(
    bytes,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

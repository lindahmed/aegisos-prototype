import 'package:flutter_test/flutter_test.dart';
import 'package:uni_track_mobile/services/meeting_session.dart';

void main() {
  test('parses a complete meeting invitation and safe fallback addresses', () {
    const roomKey = '0123456789abcdef0123456789abcdef0123456789abcdef';
    final invitation = parseMeetingInvitation(
      'ws://192.168.1.8:8765?fallback=192.168.1.9&fallback=10.0.0.8#$roomKey',
    );

    expect(invitation.roomKey, roomKey);
    expect(invitation.endpoints.map((endpoint) => endpoint.host), [
      '192.168.1.8',
      '192.168.1.9',
      '10.0.0.8',
    ]);
    expect(
      invitation.endpoints.every((endpoint) => endpoint.port == 8765),
      isTrue,
    );
  });

  test('rejects an incomplete or unsafe meeting invitation', () {
    expect(
      () => parseMeetingInvitation('https://example.test/meeting'),
      throwsA(isA<MeetingException>()),
    );
    expect(
      () => parseMeetingInvitation('ws://192.168.1.8:8765#short'),
      throwsA(isA<MeetingException>()),
    );
  });
}

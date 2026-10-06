# Desktop live lectures

All meeting code lives in the Electron desktop app (`frontend/`). The FastAPI
backend, database, web portal and Flutter app are unchanged. Existing student
profile lookup and professor password login validate desktop sign-in.

## Using the classroom

1. Start the desktop app normally. Choose **Student** or **Professor** at sign-in.
   Professors use the existing `/portal/staff/login` ID/password contract.
2. Open **Live lecture**, enter a title and click **Start lecture**. A student can
   also host a study meeting. The creator is that room's administrator.
3. Copy the invitation and give it to participants. Each participant signs in
   on their own desktop, pastes the invitation and clicks **Request to join**.
4. The host admits or declines each request. Admitted participants start muted,
   with camera off and presentation disabled.
5. Use **Allow speaking** to let someone unmute. **Allow presenting** permits
   screen sharing and drawing on the shared whiteboard. Revoking permission
   stops the affected capture. **Mute all** also revokes speaking permission.
6. Participants can turn their own camera on/off and raise/lower their hands.
   Screen sharing opens an explicit screen/window picker. Whiteboard viewing
   is available to everyone admitted; the host can clear it.
7. **Leave lecture** disconnects the local participant. **End lecture for
   everyone**, closing the host app, or losing the host connection ends the room.
   Rejoining requires host approval again. New rooms have new invitation keys.

## Connection setup

A host starts a WebSocket signaling service on its own desktop only while hosting.
The default invitation prefers physical Wi-Fi or Ethernet over Docker, VPN and
other virtual adapters, using port **8765**. It also carries other usable local
addresses as fallbacks that joining devices try automatically. This avoids
publishing a single address that another device on the same LAN cannot reach.
This works on a reachable LAN; the OS firewall must allow inbound TCP 8765.
If the machine has several network adapters, set `AEGIS_MEETING_PUBLIC_URL` to the
address reachable by participants. Wi-Fi client isolation can prevent LAN access.

For lectures across the internet, the host desktop must be reachable through a
TLS reverse proxy or an approved secure tunnel that supports WebSocket upgrades.
Set its externally reachable address as `AEGIS_MEETING_PUBLIC_URL`. A private
LAN address cannot be reached from the public internet. TLS terminates at the
proxy; the internal desktop service uses plain WebSocket. Keep the proxy path
pointing at the host desktop and allow long-lived WebSocket connections.

Set these variables on the **host desktop**. The host now sends validated ICE/TURN
configuration to joining apps, so participants only need UniTrack. For a complete
Cloudflare Tunnel and coturn deployment, see [Public desktop meetings](../../docs/PUBLIC_MEETINGS.md).

| Variable | Default | Purpose |
| --- | --- | --- |
| `AEGIS_MEETING_PORT` | `8765` | Host signaling listener port. |
| `AEGIS_MEETING_BIND` | `0.0.0.0` | Host bind address; use `127.0.0.1` with a local proxy. |
| `AEGIS_MEETING_PUBLIC_URL` | LAN `ws://address:8765` | Externally reachable `wss://lectures.example.edu` proxy/tunnel endpoint, without fragment or query. |
| `AEGIS_MEETING_ICE_SERVERS` | `[]` | JSON array of static STUN/TURN configurations distributed to participants. |
| `AEGIS_MEETING_TURN_URLS` | unset | JSON array of coturn `turn:` / `turns:` URLs. |
| `AEGIS_MEETING_TURN_SECRET` | unset | Coturn REST shared secret used only to create time-limited credentials. |
| `AEGIS_MEETING_TURN_TTL_SECONDS` | `86400` | Credential lifetime from 300 to 86400 seconds. |
| `AEGIS_MEETING_RELAY_ONLY` | unset | Set `1` to force media through configured TURN during verification. |

Example (substitute your actual service and short-lived TURN credentials):

```bash
export AEGIS_MEETING_PUBLIC_URL='wss://lectures.example.edu'
export AEGIS_MEETING_BIND='127.0.0.1'
export AEGIS_MEETING_TURN_URLS='["turn:turn.example.edu:3478?transport=udp","turns:turn.example.edu:443?transport=tcp"]'
export AEGIS_MEETING_TURN_SECRET='replace-with-the-coturn-shared-secret'
cd frontend
npm start
```

TURN is needed for reliable media between restrictive networks. No third-party
meeting service, public STUN service, or TURN credential is included by default.
Do not commit TURN credentials. There is no deployed internet relay in this change.

## Design and limits

- Maximum **12 admitted people including the host** per room. Audio, camera and
  screen use separate, fixed WebRTC connections between each pair of participants.
  Device toggles use `replaceTrack`; receivers enforce host permissions per media
  lane as well as senders stopping capture on revocation. Large lectures need an
  SFU and a central signaling service as a later infrastructure change.
- The main Electron process owns network sockets, verified local identity,
  host credentials, and capture source selection. Preload exposes only specific
  meeting operations; renderer Node integration stays disabled and sandboxing
  stays enabled. Screen access is granted only to an explicitly selected source.
- Admission, removal, speaking/presentation permissions, raise-hand state and
  whiteboard operations are checked by the host's signaling service. Only the
  creator has the private host credential; invitations cannot grant admin rights.
  Lobby clients cannot exchange media signals or access whiteboard history.
- Remote display names are **not institutional identity proof**. The existing
  student login is an ID lookup, without a password or issued session token.
  Guest claims therefore remain labeled as guests; the host must recognize
  requests before admission. Institution-wide verified remote identity would
  require backend authentication changes beyond this desktop-only scope.
- Media is encrypted by WebRTC; use WSS for invitations on public networks to
  protect signaling and invitation keys. Rooms, permissions and whiteboards are
  in memory, without recordings, persistence, reconnection or host transfer.
- Whiteboards allow 3,000 strokes or 2 MiB of ink data; the host can clear them. Message sizes, join
  timeouts, connection counts and message rates are bounded. Heartbeats clean up
  dead connections, and closing the host ends the lecture for everyone.
- Camera/microphone permissions and screen recording permissions may also need
  approval in the OS. macOS camera/microphone requests use the OS consent API.

## Verification

```bash
cd frontend
npm run check
npm test
npm run test:meetings
```

`test:meetings` launches two isolated Electron processes against an ephemeral
mock academic API and uses synthetic microphone/camera devices. It exercises
professor and student sign-in, lobby admission, speaking/presentation grants,
actual WebRTC media playback, screen enumeration/capture, mute-all revocation,
room ending and sign-out cleanup. Requires a display; use `xvfb-run -a` on CI.
The protocol tests cover unauthorized controls, lobby privacy, whiteboard
validation and late-join synchronization, capacity and host disconnect behavior.

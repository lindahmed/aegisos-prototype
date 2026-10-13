# Public desktop meetings

This setup lets participants join from any normal internet connection using only
the UniTrack desktop app. Participants do not install a VPN or configure
environment variables.

Two public services are required:

1. A TLS WebSocket hostname, such as `wss://meet.example.com`, which forwards
   signaling to port 8765 on the host desktop.
2. A TURN server, such as `turn.example.com`, which relays WebRTC media when
   participants cannot connect directly through NAT or firewalls.

The meeting room still runs on the host desktop. Closing the host app ends the
meeting.

## 1. Publish signaling with Cloudflare Tunnel

If you do not own a domain, install `cloudflared` and set this in the
project-root `.env`:

```env
AEGIS_MEETING_QUICK_TUNNEL=1
```

The launcher then creates a temporary `trycloudflare.com` address, passes its
`wss://` form to UniTrack, and stops the tunnel when UniTrack exits. The
hostname changes on every launch, but the launcher and generated invitation are
updated automatically. Quick Tunnels are intended for development and have no
uptime guarantee.

For a stable production hostname, create a named Cloudflare Tunnel and route
`meet.example.com` to it. The
`cloudflared` configuration on the host machine should contain:

```yaml
tunnel: YOUR_TUNNEL_UUID
credentials-file: /home/YOU/.cloudflared/YOUR_TUNNEL_UUID.json
ingress:
  - hostname: meet.example.com
    service: http://127.0.0.1:8765
  - service: http_status:404
```

Create the DNS route and run the tunnel:

```bash
cloudflared tunnel route dns YOUR_TUNNEL_UUID meet.example.com
cloudflared tunnel run YOUR_TUNNEL_UUID
```

Cloudflare Tunnel supports WebSocket upgrades. Keep `cloudflared` running
whenever a public meeting is active. No inbound port needs to be opened on the
host desktop.

## 2. Run coturn on a public server

A small VPS with a public IPv4 address is sufficient for prototype use. Point
the DNS-only record `turn.example.com` at that address. Do not proxy this TURN
record through a normal HTTP CDN proxy.

Generate the shared secret:

```bash
openssl rand -hex 32
```

Install coturn and use a configuration based on the following. Replace every
uppercase placeholder. The TLS certificate must cover `turn.example.com`.

```ini
listening-port=3478
tls-listening-port=443
fingerprint
use-auth-secret
static-auth-secret=YOUR_RANDOM_SHARED_SECRET
realm=turn.example.com
external-ip=YOUR_VPS_PUBLIC_IPV4
min-port=49160
max-port=49200
cert=/etc/letsencrypt/live/turn.example.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.example.com/privkey.pem
no-cli
no-multicast-peers
no-loopback-peers
stale-nonce=600
```

Allow these inbound ports in both the VPS firewall and cloud security group:

- UDP and TCP 3478
- TCP 443
- UDP 49160–49200

Restart coturn after changing its configuration. Coturn's official container can
also be used, but its listener and relay port range must be published.

## 3. Configure the host app

Add the following to the host machine's project-root `.env`. Use the same
secret configured in coturn:

```env
AEGIS_MEETING_BIND=127.0.0.1
AEGIS_MEETING_PUBLIC_URL=wss://meet.example.com
AEGIS_MEETING_TURN_URLS=["turn:turn.example.com:3478?transport=udp","turn:turn.example.com:3478?transport=tcp","turns:turn.example.com:443?transport=tcp"]
AEGIS_MEETING_TURN_SECRET=YOUR_RANDOM_SHARED_SECRET
AEGIS_MEETING_TURN_TTL_SECONDS=86400
AEGIS_MEETING_RELAY_ONLY=0
```

The launcher reads these meeting keys from `.env` without evaluating the file
as shell code. An explicitly exported environment variable takes precedence.

Start the tunnel first, then start UniTrack and create a new lecture. New
invitations use the public `wss://` hostname. The host creates a separate,
time-limited TURN username and credential for each connection and sends the
validated media configuration through the authenticated meeting WebSocket. The
coturn shared secret is never sent to participants.

## 4. Verify from outside the LAN

Use a participant computer on a different connection, such as a mobile hotspot:

1. Install and launch the same UniTrack desktop build.
2. Sign in and paste a newly generated invitation.
3. Confirm the participant appears in the host's waiting room.
4. Admit the participant and test microphone, camera, and screen sharing in both
   directions.
5. Temporarily set `AEGIS_MEETING_RELAY_ONLY=1` on the host and restart
   UniTrack. Repeat the test to prove that TURN works. Restore it to `0`
   afterward so direct media paths remain available.

If joining fails before the waiting room, inspect the Cloudflare Tunnel and
`cloudflared` logs. If joining succeeds but media is missing, inspect coturn,
its firewall rules, certificate, public IP, and relay port range.

## Managed TURN alternative

A managed TURN service can replace the coturn VPS. If it supplies static
credentials, configure them on the host with `AEGIS_MEETING_ICE_SERVERS`.
Those credentials are necessarily delivered to participants, so prefer
short-lived credentials or a provider-compatible shared-secret mechanism.

```env
AEGIS_MEETING_ICE_SERVERS=[{"urls":["turn:provider.example:3478?transport=udp","turns:provider.example:443?transport=tcp"],"username":"USERNAME","credential":"CREDENTIAL"}]
```

Do not commit any TURN secret or credential.

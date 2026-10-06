'use strict';

const { randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');

const LANES = ['audio', 'camera', 'screen'];
const MAX_MEMBERS = 12;
const MAX_STROKES = 3000;
const MAX_BOARD_BYTES = 2 * 1024 * 1024;

function sameSecret(a, b) {
  if (typeof a !== 'string' || a.length !== b.length) return false;
  const candidate = Buffer.from(a);
  const expected = Buffer.from(b);
  return candidate.length === expected.length && timingSafeEqual(candidate, expected);
}

// A room belongs to this desktop process. Remote clients cannot create rooms or
// obtain the host credential; join invitations only contain the admission key.
async function createMeetingServer({ port = 8765, host = '0.0.0.0', title, identity,
  configuration = () => ({ iceServers: [], iceTransportPolicy: 'all' }) }) {
  const roomKey = randomBytes(24).toString('hex');
  const hostKey = randomBytes(32).toString('hex');
  const members = new Map();
  const strokes = [];
  let boardBytes = 0;
  let hostId = null;
  let ended = false;
  const wss = new WebSocketServer({ port, host, maxPayload: 96 * 1024, perMessageDeflate: false });
  const send = (ws, message) => {
    if (ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > 8 * 1024 * 1024) { ws.terminate(); return; }
    ws.send(JSON.stringify(message));
  };
  const publicMember = (m) => ({
    id: m.id, name: m.name, role: m.role, host: m.host, admitted: m.admitted,
    canSpeak: m.canSpeak, canShare: m.canShare, mic: m.mic, camera: m.camera,
    screen: m.screen, hand: m.hand,
  });
  function snapshot() {
    for (const m of members.values()) {
      send(m.ws, { type: 'state', title, selfId: m.id, members: [...members.values()]
        .filter((other) => m.host || other.admitted || other.id === m.id).map(publicMember) });
    }
  }
  function end(reason = 'The host ended the lecture.') {
    if (ended) return;
    ended = true;
    for (const m of members.values()) {
      send(m.ws, { type: 'ended', reason });
      m.ws.close(1000, 'Lecture ended');
    }
    members.clear();
  }
  function remove(m, reason) {
    members.delete(m.id);
    send(m.ws, { type: 'removed', reason });
    m.ws.close(1000, 'Removed');
    snapshot();
  }
  wss.on('connection', (ws) => {
    if (ended || wss.clients.size > 64) return ws.close(1008, 'Room unavailable');
    let member;
    let count = 0;
    let period = Date.now();
    ws.alive = true;
    ws.on('pong', () => { ws.alive = true; });
    const timeout = setTimeout(() => { if (!member) ws.close(1008, 'Join timeout'); }, 10000);
    ws.on('error', () => {});
    ws.on('message', (raw) => {
      try {
        if (Date.now() - period > 1000) { period = Date.now(); count = 0; }
        if (++count > 320) throw new Error('Too many requests.');
        const message = JSON.parse(raw.toString());
        if (!message || typeof message !== 'object' || Array.isArray(message)) throw new Error('Invalid message.');
        if (!member) {
          if (message.type !== 'join' || !sameSecret(message.roomKey, roomKey)) throw new Error('Invalid meeting invitation.');
          const isHost = sameSecret(message.hostKey, hostKey);
          if (isHost && hostId) throw new Error('The host is already connected.');
          if (!isHost && !hostId) throw new Error('The host has not started the meeting.');
          if (members.size >= 48) throw new Error('The waiting room is full.');
          const name = isHost ? identity.name : String(message.name || '').trim().slice(0, 100);
          if (!name) throw new Error('A display name is required.');
          const rtc = configuration();
          member = {
            id: randomUUID(), ws, name,
            role: isHost ? identity.role : 'guest', host: isHost, admitted: isHost,
            canSpeak: isHost, canShare: isHost, mic: false, camera: false, screen: false, hand: false,
          };
          members.set(member.id, member);
          if (isHost) hostId = member.id;
          clearTimeout(timeout);
          send(ws, { type: 'configuration', configuration: rtc });
          send(ws, { type: 'joined', id: member.id });
          snapshot();
          return;
        }
        const target = members.get(message.target);
        if (['admit', 'reject', 'remove', 'permissions', 'mute-all', 'end', 'clear-board'].includes(message.type)) {
          if (!member.host) throw new Error('Only the host can perform this action.');
          if (message.type === 'end') return end();
          if (message.type === 'clear-board') {
            strokes.length = 0;
            boardBytes = 0;
            for (const m of members.values()) if (m.admitted) send(m.ws, { type: 'board', strokes: [] });
            return;
          }
          if (message.type === 'mute-all') {
            for (const m of members.values()) if (!m.host) { m.canSpeak = false; m.mic = false; }
          } else {
            if (!target || target.host) throw new Error('Participant unavailable.');
            if (message.type === 'admit') {
              if (target.admitted) return;
              if ([...members.values()].filter((m) => m.admitted).length >= MAX_MEMBERS) throw new Error('This lecture supports up to 12 people.');
              target.admitted = true;
              send(target.ws, { type: 'board', strokes });
            } else if (message.type === 'reject' || message.type === 'remove') {
              return remove(target, message.type === 'reject' ? 'The host declined your request.' : 'The host removed you from the lecture.');
            } else if (message.type === 'permissions') {
              if (!target.admitted) throw new Error('Admit this participant first.');
              if (typeof message.canSpeak === 'boolean') target.canSpeak = message.canSpeak;
              if (typeof message.canShare === 'boolean') target.canShare = message.canShare;
              if (!target.canSpeak) target.mic = false;
              if (!target.canShare) target.screen = false;
            }
          }
          snapshot();
          return;
        }
        if (!member.admitted) throw new Error('Wait for host approval.');
        if (message.type === 'signal') {
          if (!target?.admitted || target.id === member.id || !LANES.includes(message.lane)) throw new Error('Invalid signal recipient.');
          const data = message.data;
          if (!data || typeof data !== 'object' || JSON.stringify(data).length > 64000) throw new Error('Invalid signal.');
          send(target.ws, { type: 'signal', from: member.id, lane: message.lane, data });
        } else if (message.type === 'media') {
          if (message.mic === true && !member.canSpeak) throw new Error('The host must allow you to speak.');
          if (message.screen === true && !member.canShare) throw new Error('The host must allow screen sharing.');
          for (const key of ['mic', 'camera', 'screen']) if (typeof message[key] === 'boolean') member[key] = message[key];
          snapshot();
        } else if (message.type === 'hand') {
          member.hand = message.raised === true;
          snapshot();
        } else if (message.type === 'stroke') {
          if (!member.canShare) throw new Error('The host must allow you to present to use the whiteboard.');
          if (strokes.length >= MAX_STROKES) throw new Error('Whiteboard full. Ask the host to clear it.');
          const s = message.stroke;
          if (!s || !/^#[a-fA-F0-9]{6}$/.test(s.color) || !Number.isFinite(s.width) || s.width < 1 || s.width > 12 ||
              !Array.isArray(s.points) || s.points.length < 2 || s.points.length > 256 ||
              !s.points.every((p) => Array.isArray(p) && p.length === 2 && p.every((v) => Number.isFinite(v) && v >= 0 && v <= 1))) throw new Error('Invalid whiteboard stroke.');
          const stroke = { color: s.color, width: s.width, points: s.points };
          const strokeBytes = Buffer.byteLength(JSON.stringify(stroke)) + 1;
          if (boardBytes + strokeBytes > MAX_BOARD_BYTES) throw new Error('Whiteboard full. Ask the host to clear it.');
          boardBytes += strokeBytes;
          strokes.push(stroke);
          for (const m of members.values()) if (m.admitted) send(m.ws, { type: 'stroke', stroke });
        } else throw new Error('Unknown action.');
      } catch (error) {
        send(ws, { type: 'error', message: error.message });
        if (!member || count > 320) ws.close(1008, 'Invalid request');
      }
    });
    ws.on('close', () => {
      clearTimeout(timeout);
      if (!member || !members.has(member.id)) return;
      members.delete(member.id);
      if (member.host) end('The host disconnected. The lecture has ended.');
      else snapshot();
    });
  });
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) { ws.terminate(); continue; }
      ws.alive = false;
      ws.ping();
    }
  }, 15000);
  heartbeat.unref();
  wss.on('close', () => clearInterval(heartbeat));
  await new Promise((resolve, reject) => {
    wss.once('listening', resolve);
    wss.once('error', reject);
  }).catch((error) => { clearInterval(heartbeat); throw error; });
  return { roomKey, hostKey, port: wss.address().port, end,
    close: () => new Promise((resolve) => {
      end();
      for (const ws of wss.clients) ws.terminate();
      wss.close(resolve);
    }),
  };
}

module.exports = { createMeetingServer, MAX_MEMBERS };

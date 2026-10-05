'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');
const { createMeetingServer, MAX_MEMBERS } = require('../meetings/server');

async function client(server, { host = false, key = server.roomKey, name = 'Student' } = {}) {
  const socket = new WebSocket(`ws://127.0.0.1:${server.port}`);
  const messages = [];
  const waiters = [];
  socket.on('message', (raw) => {
    const message = JSON.parse(raw);
    const index = waiters.findIndex((w) => w.predicate(message));
    if (index >= 0) {
      const waiter = waiters.splice(index, 1)[0];
      clearTimeout(waiter.timer);
      waiter.resolve(message);
    } else messages.push(message);
  });
  await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
  const send = (message) => socket.send(JSON.stringify(message));
  send({ type: 'join', roomKey: key, ...(host ? { hostKey: server.hostKey } : {}), name });
  return { socket, send, messages,
    next(predicate = () => true) {
      const index = messages.findIndex(predicate);
      if (index >= 0) return Promise.resolve(messages.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { predicate, resolve, timer: setTimeout(() => {
          waiters.splice(waiters.indexOf(waiter), 1);
          reject(new Error('Timed out waiting for meeting event'));
        }, 3000) };
        waiters.push(waiter);
      });
    },
  };
}
const type = (expected) => (message) => message.type === expected;
const has = (id, predicate) => (message) => message.type === 'state' && message.members.some((m) => m.id === id && predicate(m));
async function fixture(t) {
  const server = await createMeetingServer({ port: 0, host: '127.0.0.1', title: 'Algorithms', identity: { name: 'Professor', role: 'staff' } });
  t.after(() => server.close());
  const host = await client(server, { host: true });
  host.id = (await host.next(type('joined'))).id;
  return { server, host };
}
async function guest(server, name) {
  const value = await client(server, { name });
  value.id = (await value.next(type('joined'))).id;
  return value;
}
async function admit(host, guestClient) {
  host.send({ type: 'admit', target: guestClient.id });
  await guestClient.next(has(guestClient.id, (m) => m.admitted));
}

test('invitations cannot grant host access and the lobby receives no media or private requests', async (t) => {
  const { server, host } = await fixture(t);
  const invalid = await client(server, { key: '0'.repeat(48) });
  assert.match((await invalid.next(type('error'))).message, /Invalid meeting invitation/);
  const a = await guest(server, 'Alice');
  const b = await guest(server, 'Bob');
  const lobby = await b.next(has(b.id, (m) => !m.admitted));
  assert.equal(lobby.members.some((m) => m.id === a.id), false);
  assert.equal(JSON.stringify(lobby).includes(server.hostKey), false);
  a.send({ type: 'admit', target: b.id });
  assert.match((await a.next(type('error'))).message, /Only the host/);
  a.send({ type: 'signal', target: host.id, lane: 'audio', data: { candidate: {} } });
  assert.match((await a.next(type('error'))).message, /Wait for host approval/);
  a.send({ type: 'media', camera: true });
  assert.match((await a.next(type('error'))).message, /Wait for host approval/);
  host.send({ type: 'reject', target: b.id });
  assert.match((await b.next(type('removed'))).reason, /declined/);
});

test('host approval, speaking and presentation grants, revoke, and mute all are authoritative', async (t) => {
  const { server, host } = await fixture(t);
  const a = await guest(server, 'Alice');
  await admit(host, a);
  a.send({ type: 'media', mic: true });
  assert.match((await a.next(type('error'))).message, /allow you to speak/);
  a.send({ type: 'media', screen: true });
  assert.match((await a.next(type('error'))).message, /allow screen sharing/);
  a.send({ type: 'media', camera: true });
  await host.next(has(a.id, (m) => m.camera));
  a.send({ type: 'hand', raised: true });
  await host.next(has(a.id, (m) => m.hand));
  host.send({ type: 'permissions', target: a.id, canSpeak: true, canShare: true });
  await a.next(has(a.id, (m) => m.canSpeak && m.canShare));
  a.send({ type: 'media', mic: true, screen: true });
  await host.next(has(a.id, (m) => m.mic && m.screen));
  host.send({ type: 'permissions', target: a.id, canShare: false });
  await a.next(has(a.id, (m) => !m.canShare && !m.screen && m.mic));
  host.send({ type: 'mute-all' });
  await a.next(has(a.id, (m) => !m.canSpeak && !m.mic));
  a.send({ type: 'permissions', target: host.id, canSpeak: false });
  assert.match((await a.next(type('error'))).message, /Only the host/);
  host.send({ type: 'remove', target: a.id });
  await a.next(type('removed'));
});

test('signaling goes only to admitted recipients and uses the server sender identity', async (t) => {
  const { server, host } = await fixture(t);
  const a = await guest(server, 'Alice');
  const b = await guest(server, 'Bob');
  await admit(host, a);
  a.send({ type: 'signal', target: b.id, lane: 'camera', data: { candidate: {} } });
  assert.match((await a.next(type('error'))).message, /Invalid signal recipient/);
  a.send({ type: 'signal', from: 'forged', target: host.id, lane: 'camera', data: { description: { type: 'offer', sdp: 'example' } } });
  const received = await host.next(type('signal'));
  assert.equal(received.from, a.id);
  assert.equal(received.lane, 'camera');
  a.send({ type: 'signal', target: host.id, lane: 'unknown', data: {} });
  assert.match((await a.next(type('error'))).message, /Invalid signal recipient/);
});

test('whiteboard is permission checked, bounded, synchronized for late arrivals, and host clear only', async (t) => {
  const { server, host } = await fixture(t);
  const a = await guest(server, 'Alice');
  await admit(host, a);
  await a.next(type('board'));
  const stroke = { color: '#2563eb', width: 5, points: [[0.1, 0.1], [0.3, 0.4]] };
  a.send({ type: 'stroke', stroke });
  assert.match((await a.next(type('error'))).message, /allow you to present/);
  host.send({ type: 'stroke', stroke });
  assert.deepEqual((await a.next(type('stroke'))).stroke, stroke);
  host.send({ type: 'stroke', stroke: { ...stroke, points: [[-1, 0], [1, 1]] } });
  assert.match((await host.next(type('error'))).message, /Invalid whiteboard stroke/);
  const b = await guest(server, 'Bob');
  await admit(host, b);
  assert.deepEqual((await b.next(type('board'))).strokes, [stroke]);
  a.send({ type: 'clear-board' });
  assert.match((await a.next(type('error'))).message, /Only the host/);
  host.send({ type: 'clear-board' });
  const empty = await a.next((m) => m.type === 'board' && m.strokes.length === 0);
  assert.deepEqual(empty.strokes, []);
});

test('admission capacity does not silently overload the media mesh', async (t) => {
  const { server, host } = await fixture(t);
  for (let i = 1; i < MAX_MEMBERS; i++) await admit(host, await guest(server, `Student ${i}`));
  const overflow = await guest(server, 'Overflow');
  host.send({ type: 'admit', target: overflow.id });
  assert.match((await host.next(type('error'))).message, /up to 12/);
});

test('host disconnect ends the room and disconnects admitted and waiting participants', async (t) => {
  const { server, host } = await fixture(t);
  const a = await guest(server, 'Alice');
  const b = await guest(server, 'Bob');
  await admit(host, a);
  host.socket.close();
  assert.match((await a.next(type('ended'))).reason, /host disconnected/);
  assert.match((await b.next(type('ended'))).reason, /host disconnected/);
});


test('whiteboard history stays small enough for late-join synchronization', async (t) => {
  const { server, host } = await fixture(t);
  const stroke = { color: '#2563eb', width: 5,
    points: Array.from({ length: 256 }, () => [0.1234567890123456, 0.6543210987654321]) };
  for (let i = 0; i < 260; i++) host.send({ type: 'stroke', stroke });
  assert.match((await host.next(type('error'))).message, /Whiteboard full/);
  const late = await guest(server, 'Late arrival');
  await admit(host, late);
  const board = await late.next(type('board'));
  assert.ok(board.strokes.length > 0);
  assert.ok(Buffer.byteLength(JSON.stringify(board)) < 4 * 1024 * 1024);
});

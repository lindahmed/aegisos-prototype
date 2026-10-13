'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createInvitation, meetingAddresses, parseInvitation } = require('../meetings/invitation');

const roomKey = 'a'.repeat(48);

test('meeting invitations prefer physical adapters and retain reachable fallbacks', () => {
  const interfaces = {
    docker0: [{ family: 'IPv4', internal: false, address: '172.17.0.1' }],
    wlan0: [{ family: 'IPv4', internal: false, address: '192.168.1.24' }],
    eth0: [{ family: 'IPv4', internal: false, address: '10.0.0.8' }],
    lo: [{ family: 'IPv4', internal: true, address: '127.0.0.1' }],
  };
  assert.deepEqual(meetingAddresses(interfaces), ['192.168.1.24', '10.0.0.8', '172.17.0.1']);
  const invitation = createInvitation({ port: 8765, roomKey, interfaces });
  assert.match(invitation, /^ws:\/\/192\.168\.1\.24:8765\/\?fallback=10\.0\.0\.8&fallback=172\.17\.0\.1#/);
  assert.deepEqual(parseInvitation(invitation), {
    roomKey,
    endpoints: ['ws://192.168.1.24:8765/', 'ws://10.0.0.8:8765/', 'ws://172.17.0.1:8765/'],
  });
});

test('configured public meeting URLs remain unchanged and malformed invitations are rejected', () => {
  const invitation = createInvitation({ publicUrl: 'wss://meet.example.edu/classroom', port: 1, roomKey, interfaces: {} });
  assert.equal(invitation, `wss://meet.example.edu/classroom#${roomKey}`);
  assert.deepEqual(parseInvitation(invitation).endpoints, ['wss://meet.example.edu/classroom']);
  assert.throws(() => parseInvitation(`ws://user:password@host/#${roomKey}`), /meeting address/);
  assert.throws(() => parseInvitation(`ws://host/?redirect=bad#${roomKey}`), /valid meeting invitation/);
});

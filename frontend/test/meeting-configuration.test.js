'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');
const { meetingConfiguration, normalizeRtcConfiguration } = require('../meetings/configuration');

test('host creates time-limited coturn credentials without exposing the shared secret', () => {
  const secret = 'a-secure-random-secret-that-is-long-enough';
  const result = meetingConfiguration({
    AEGIS_MEETING_TURN_URLS: '["turn:turn.example.edu:3478?transport=udp","turns:turn.example.edu:5349?transport=tcp"]',
    AEGIS_MEETING_TURN_SECRET: secret,
    AEGIS_MEETING_TURN_TTL_SECONDS: '3600',
    AEGIS_MEETING_RELAY_ONLY: '1',
  }, () => 2_000_000, () => Buffer.from('0102030405060708', 'hex'));
  assert.equal(result.iceTransportPolicy, 'relay');
  assert.deepEqual(result.iceServers[0].urls, [
    'turn:turn.example.edu:3478?transport=udp',
    'turns:turn.example.edu:5349?transport=tcp',
  ]);
  assert.equal(result.iceServers[0].username, '5600:0102030405060708');
  assert.equal(result.iceServers[0].credential,
    createHmac('sha1', secret).update(result.iceServers[0].username).digest('base64'));
  assert.equal(JSON.stringify(result).includes(secret), false);
});

test('remote ICE configuration is constrained before reaching WebRTC', () => {
  assert.deepEqual(normalizeRtcConfiguration({ iceServers: [{ urls: 'stun:stun.example.edu:3478' }] }), {
    iceServers: [{ urls: 'stun:stun.example.edu:3478' }], iceTransportPolicy: 'all',
  });
  assert.throws(() => normalizeRtcConfiguration({ iceServers: [{ urls: 'https://example.edu' }] }), /stun/);
  assert.throws(() => meetingConfiguration({ AEGIS_MEETING_TURN_SECRET: 'x'.repeat(32) }), /Set both/);
});

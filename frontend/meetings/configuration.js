'use strict';

const { createHmac, randomBytes } = require('node:crypto');

const ICE_PROTOCOLS = new Set(['stun:', 'stuns:', 'turn:', 'turns:']);
const TURN_PROTOCOLS = new Set(['turn:', 'turns:']);

function normalizeUrls(value, protocols = ICE_PROTOCOLS) {
  const urls = typeof value === 'string' ? [value] : value;
  if (!Array.isArray(urls) || urls.length < 1 || urls.length > 8) throw new Error('Each ICE server must contain between 1 and 8 URLs.');
  return urls.map((entry) => {
    if (typeof entry !== 'string' || entry.length > 500) throw new Error('ICE server URLs must be short strings.');
    let url;
    try { url = new URL(entry); } catch { throw new Error('ICE server URL is invalid.'); }
    if (!protocols.has(url.protocol)) throw new Error('ICE servers must use stun:, stuns:, turn:, or turns:.');
    return entry;
  });
}

function normalizeRtcConfiguration(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid meeting media configuration.');
  if (!Array.isArray(value.iceServers) || value.iceServers.length > 8) throw new Error('Invalid meeting media configuration.');
  const iceServers = value.iceServers.map((server) => {
    if (!server || typeof server !== 'object' || Array.isArray(server)) throw new Error('Invalid ICE server configuration.');
    const urls = normalizeUrls(server.urls);
    const normalized = { urls: typeof server.urls === 'string' ? urls[0] : urls };
    if (server.username !== undefined) {
      if (typeof server.username !== 'string' || server.username.length > 512) throw new Error('Invalid ICE server username.');
      normalized.username = server.username;
    }
    if (server.credential !== undefined) {
      if (typeof server.credential !== 'string' || server.credential.length > 512) throw new Error('Invalid ICE server credential.');
      normalized.credential = server.credential;
    }
    return normalized;
  });
  const iceTransportPolicy = value.iceTransportPolicy === 'relay' ? 'relay' : 'all';
  return { iceServers, iceTransportPolicy };
}

function parseArray(raw, name) {
  let value;
  try { value = JSON.parse(raw); } catch { throw new Error(`${name} must contain a JSON array.`); }
  if (!Array.isArray(value)) throw new Error(`${name} must contain a JSON array.`);
  return value;
}

function meetingConfiguration(env = process.env, now = Date.now, nonce = randomBytes) {
  const configured = parseArray(env.AEGIS_MEETING_ICE_SERVERS || '[]', 'AEGIS_MEETING_ICE_SERVERS');
  const turnUrlsValue = env.AEGIS_MEETING_TURN_URLS;
  const turnSecret = env.AEGIS_MEETING_TURN_SECRET;
  if (Boolean(turnUrlsValue) !== Boolean(turnSecret)) throw new Error('Set both AEGIS_MEETING_TURN_URLS and AEGIS_MEETING_TURN_SECRET.');

  if (turnUrlsValue) {
    if (turnSecret.length < 32) throw new Error('AEGIS_MEETING_TURN_SECRET must be at least 32 characters.');
    const urls = normalizeUrls(parseArray(turnUrlsValue, 'AEGIS_MEETING_TURN_URLS'), TURN_PROTOCOLS);
    const ttl = Number(env.AEGIS_MEETING_TURN_TTL_SECONDS || 86400);
    if (!Number.isInteger(ttl) || ttl < 300 || ttl > 86400) throw new Error('AEGIS_MEETING_TURN_TTL_SECONDS must be between 300 and 86400.');
    const expires = Math.floor(now() / 1000) + ttl;
    const username = `${expires}:${nonce(8).toString('hex')}`;
    const credential = createHmac('sha1', turnSecret).update(username).digest('base64');
    configured.push({ urls, username, credential });
  }

  return normalizeRtcConfiguration({
    iceServers: configured,
    iceTransportPolicy: env.AEGIS_MEETING_RELAY_ONLY === '1' ? 'relay' : 'all',
  });
}

module.exports = { meetingConfiguration, normalizeRtcConfiguration };

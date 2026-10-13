'use strict';

const { isIP } = require('node:net');

const VIRTUAL_INTERFACE = /^(?:docker|veth|br-|virbr|vmnet|vboxnet|zt|tailscale|tun|tap|wg)/i;

function meetingAddresses(interfaces) {
  const addresses = [];
  for (const [name, entries] of Object.entries(interfaces || {})) {
    for (const entry of entries || []) {
      if (entry.family !== 'IPv4' || entry.internal || !isIP(entry.address) || entry.address.startsWith('169.254.')) continue;
      addresses.push({ address: entry.address, virtual: VIRTUAL_INTERFACE.test(name) });
    }
  }
  return [...new Map(addresses
    .sort((a, b) => Number(a.virtual) - Number(b.virtual))
    .map((entry) => [entry.address, entry.address])).values()];
}

function validateEndpoint(url, message) {
  if (!['ws:', 'wss:'].includes(url.protocol) || url.username || url.password) throw new Error(message);
}

function createInvitation({ publicUrl, port, roomKey, interfaces }) {
  if (publicUrl) {
    const endpoint = new URL(publicUrl);
    validateEndpoint(endpoint, 'Invalid AEGIS_MEETING_PUBLIC_URL.');
    if (endpoint.search || endpoint.hash) throw new Error('Invalid AEGIS_MEETING_PUBLIC_URL.');
    endpoint.hash = roomKey;
    return endpoint.href;
  }

  const addresses = meetingAddresses(interfaces);
  const endpoint = new URL(`ws://${addresses[0] || '127.0.0.1'}:${port}`);
  for (const address of addresses.slice(1, 7)) endpoint.searchParams.append('fallback', address);
  endpoint.hash = roomKey;
  return endpoint.href;
}

function parseInvitation(invitation) {
  const url = new URL(String(invitation).trim());
  validateEndpoint(url, 'Use a ws:// or wss:// meeting address.');
  const roomKey = url.hash.slice(1);
  if (!/^[a-f0-9]{48}$/.test(roomKey)) throw new Error('Paste the complete meeting invitation.');

  const fallbacks = [];
  for (const [name, value] of url.searchParams) {
    if (name !== 'fallback' || isIP(value) !== 4 || fallbacks.length >= 6) throw new Error('Paste a valid meeting invitation.');
    fallbacks.push(value);
  }
  url.hash = '';
  url.search = '';
  const endpoints = [url.href];
  for (const address of fallbacks) {
    const fallback = new URL(url.href);
    fallback.hostname = address;
    if (!endpoints.includes(fallback.href)) endpoints.push(fallback.href);
  }
  return { roomKey, endpoints };
}

module.exports = { createInvitation, meetingAddresses, parseInvitation };

'use strict';
const { ipcMain, desktopCapturer, systemPreferences, powerSaveBlocker } = require('electron');
const { pathToFileURL } = require('node:url');
const { networkInterfaces } = require('node:os');
const path = require('node:path');
const { WebSocket } = require('ws');
const { createMeetingServer } = require('./server');
const { createInvitation, parseInvitation } = require('./invitation');

function installMeetings(win) {
  const appUrl = pathToFileURL(path.join(__dirname, '..', 'index.html')).href;
  const trusted = (frame) => frame?.url === appUrl && frame === win.webContents.mainFrame;
  let identity = null;
  let server = null;
  let socket = null;
  let sourceId = null;
  let blocker = null;
  let generation = 0;
  const channels = [];
  const emit = (message) => { if (!win.webContents.isDestroyed()) win.webContents.send('meeting:event', message); };
  async function disconnect() {
    generation++;
    sourceId = null;
    const previous = socket;
    socket = null;
    if (previous) previous.terminate();
    const previousServer = server;
    server = null;
    if (previousServer) await previousServer.close();
    if (blocker !== null && powerSaveBlocker.isStarted(blocker)) powerSaveBlocker.stop(blocker);
    blocker = null;
  }
  function handle(name, fn) {
    const channel = `meeting:${name}`;
    channels.push(channel);
    ipcMain.handle(channel, (event, ...args) => {
      if (!trusted(event.senderFrame)) throw new Error('Untrusted meeting request.');
      return fn(...args);
    });
  }
  function configuration() {
    let iceServers;
    try {
      iceServers = JSON.parse(process.env.AEGIS_MEETING_ICE_SERVERS || '[]');
      if (!Array.isArray(iceServers)) throw new Error();
    } catch { throw new Error('AEGIS_MEETING_ICE_SERVERS must contain a JSON array.'); }
    return { iceServers, iceTransportPolicy: process.env.AEGIS_MEETING_RELAY_ONLY === '1' ? 'relay' : 'all' };
  }
  async function connect(endpoint, roomKey, hostKey) {
    const url = new URL(endpoint);
    if (!['ws:', 'wss:'].includes(url.protocol) || url.username || url.password || url.hash || url.search) throw new Error('Use a ws:// or wss:// meeting address.');
    const rtc = configuration();
    const connectionGeneration = generation;
    const client = new WebSocket(url, { maxPayload: 4 * 1024 * 1024, handshakeTimeout: 4000, followRedirects: false });
    let opened = false;
    socket = client;
    client.on('error', () => {});
    client.on('message', (raw) => {
      if (socket !== client) return;
      try { emit(JSON.parse(raw.toString())); } catch { emit({ type: 'error', message: 'Invalid meeting response.' }); }
    });
    client.on('close', () => {
      if (socket !== client) return;
      if (!opened) { socket = null; return; }
      emit({ type: 'disconnected', reason: 'Meeting connection lost. Rejoin with your invitation.' });
      void disconnect();
    });
    try {
      await new Promise((resolve, reject) => {
        client.once('open', resolve);
        client.once('error', () => reject(new Error('Cannot reach the meeting host. Check the address and network.')));
        client.once('close', () => reject(new Error('The meeting connection closed.')));
      });
      opened = true;
    } catch (error) {
      if (socket === client) socket = null;
      client.terminate();
      throw error;
    }
    if (generation !== connectionGeneration) { client.terminate(); throw new Error('Meeting connection cancelled.'); }
    client.send(JSON.stringify({ type: 'join', roomKey, hostKey, name: identity.name }));
    blocker = powerSaveBlocker.start('prevent-app-suspension');
    return rtc;
  }
  async function connectAny(endpoints, roomKey, hostKey) {
    let lastError;
    for (const endpoint of endpoints) {
      try { return await connect(endpoint, roomKey, hostKey); }
      catch (error) { lastError = error; }
    }
    throw lastError || new Error('Cannot reach the meeting host. Check the address and network.');
  }
  handle('authenticate', async ({ role, id, password }) => {
    if (socket) throw new Error('Leave the meeting before changing accounts.');
    identity = null;
    const isStaff = role === 'staff';
    const base = (isStaff ? process.env.AEGIS_ACADEMIC_API_URL : null) || process.env.AEGIS_API_URL || 'http://127.0.0.1:8001';
    if (!isStaff && role !== 'student') throw new Error('Choose student or professor.');
    const response = await fetch(`${base}${isStaff ? '/portal/staff/login' : `/student/${encodeURIComponent(String(id).trim())}`}`, {
      method: isStaff ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json' },
      ...(isStaff ? { body: JSON.stringify({ staff_id: String(id).trim(), password }) } : {}),
      signal: AbortSignal.timeout(15000),
    });
    const profile = await response.json();
    if (!response.ok) throw new Error(profile.detail || 'Sign in failed.');
    identity = { role, id: isStaff ? profile.staff_id : profile.student_id, name: profile.name };
    return profile;
  });
  handle('host', async (title) => {
    if (!identity) throw new Error('Sign in first.');
    await disconnect();
    const startGeneration = generation;
    try {
      const created = await createMeetingServer({
        port: Number(process.env.AEGIS_MEETING_PORT || 8765),
        host: process.env.AEGIS_MEETING_BIND || '0.0.0.0',
        title: String(title || '').trim().slice(0, 120) || 'Online meeting', identity,
      });
      if (generation !== startGeneration) { await created.close(); throw new Error('Meeting cancelled.'); }
      server = created;
      const rtc = await connect(`ws://127.0.0.1:${server.port}`, server.roomKey, server.hostKey);
      const invitation = createInvitation({
        publicUrl: process.env.AEGIS_MEETING_PUBLIC_URL,
        port: server.port,
        roomKey: server.roomKey,
        interfaces: networkInterfaces(),
      });
      return { ...rtc, invitation };
    } catch (error) { if (generation === startGeneration) await disconnect(); throw error; }
  });
  handle('join', async (invitation) => {
    if (!identity) throw new Error('Sign in first.');
    await disconnect();
    try {
      const { roomKey, endpoints } = parseInvitation(invitation);
      return await connectAny(endpoints, roomKey);
    } catch (error) { await disconnect(); throw error; }
  });
  handle('send', (message) => {
    if (socket?.readyState !== WebSocket.OPEN) throw new Error('Meeting is disconnected.');
    const serialized = JSON.stringify(message);
    if (serialized.length > 96000) throw new Error('Meeting message too large.');
    socket.send(serialized);
  });
  handle('leave', disconnect);
  handle('sign-out', async () => { await disconnect(); identity = null; });
  handle('sources', async () => {
    if (!socket) throw new Error('Join a meeting first.');
    const sources = await desktopCapturer.getSources({ types: ['screen', 'window'], thumbnailSize: { width: 240, height: 140 } });
    return sources.map((s) => ({ id: s.id, name: s.name, thumbnail: s.thumbnail.toDataURL() }));
  });
  handle('select-source', async (id) => {
    if (!socket) throw new Error('Join a meeting first.');
    const sources = await desktopCapturer.getSources({ types: ['screen', 'window'], thumbnailSize: { width: 0, height: 0 } });
    if (!sources.some((s) => s.id === id)) throw new Error('This screen or window is no longer available.');
    sourceId = id;
  });
  const ses = win.webContents.session;
  ses.setPermissionCheckHandler((contents, permission, _origin, details) =>
    contents === win.webContents && trusted(win.webContents.mainFrame) &&
    details.isMainFrame !== false && ['media', 'display-capture'].includes(permission));
  ses.setPermissionRequestHandler(async (contents, permission, callback, details) => {
    if (contents !== win.webContents || !trusted(win.webContents.mainFrame) || details.isMainFrame === false || !['media', 'display-capture'].includes(permission)) return callback(false);
    if (process.platform === 'darwin' && permission === 'media') {
      for (const type of details.mediaTypes || []) {
        const device = type === 'audio' ? 'microphone' : type === 'video' ? 'camera' : null;
        if (device && !(await systemPreferences.askForMediaAccess(device))) return callback(false);
      }
    }
    callback(true);
  });
  ses.setDisplayMediaRequestHandler(async (request, callback) => {
    const chosen = sourceId;
    sourceId = null;
    if (!trusted(request.frame) || !chosen || !socket || !request.userGesture) return callback({});
    try {
      const sources = await desktopCapturer.getSources({ types: ['screen', 'window'], thumbnailSize: { width: 0, height: 0 } });
      const source = sources.find((s) => s.id === chosen);
      callback(source ? { video: source } : {});
    } catch { callback({}); }
  });
  win.webContents.on('will-navigate', (event) => event.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.on('closed', () => {
    void disconnect();
    for (const channel of channels) ipcMain.removeHandler(channel);
  });
  return disconnect;
}
module.exports = { installMeetings };

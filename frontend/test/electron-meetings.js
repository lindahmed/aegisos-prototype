'use strict';
// Run with `npm run test:meetings`. Requires a display, or xvfb-run on CI.
const { app, BrowserWindow } = require('electron');
const { spawn } = require('node:child_process');
const { createServer } = require('node:http');
const { mkdtempSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { installMeetings } = require('../meetings/desktop');
const root = path.join(__dirname, '..');
const child = process.env.MEETING_TEST_CHILD === '1';
const profilePath = mkdtempSync(path.join(tmpdir(), 'unitrack-meeting-test-'));
app.setPath('userData', profilePath);
app.disableHardwareAcceleration();
app.commandLine.appendSwitch('use-fake-device-for-media-stream');
app.commandLine.appendSwitch('use-fake-ui-for-media-stream');
app.commandLine.appendSwitch('disable-dev-shm-usage');
let win;
let guest;
let apiServer;
let closeMeetings;
const errors = [];
const js = (code, gesture = false) => win.webContents.executeJavaScript(code, gesture);
async function until(code, description, timeout = 12000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await js(code)) return;
    await new Promise((resolve) => setTimeout(resolve, 80));
  }
  throw new Error(`Timeout: ${description}. Status: ${await js("document.getElementById('meeting-status').textContent")}`);
}
async function click(id) { await js(`document.getElementById(${JSON.stringify(id)}).click()`, true); }
async function login(role) {
  await js(`document.getElementById('login-role').value = ${JSON.stringify(role)}; document.getElementById('login-role').dispatchEvent(new Event('change')); document.getElementById('student-id').value = ${JSON.stringify(role === 'staff' ? '104217' : 'student-1')}; document.getElementById('staff-password').value = 'test-password'; document.getElementById('login-form').requestSubmit();`);
  await until("!document.getElementById('dashboard-view').hidden", 'sign in');
  if (role === 'student') await click('meeting-tab');
  else assert.equal(await js("document.getElementById('workspace-tab').hidden"), true);
}
const inbox = [];
const waiters = [];
function message(value) {
  const i = waiters.findIndex((w) => w.type === value.type);
  if (i < 0) inbox.push(value);
  else { const w = waiters.splice(i, 1)[0]; clearTimeout(w.timer); w.resolve(value); }
}
function wait(type) {
  const i = inbox.findIndex((m) => m.type === type);
  if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
  return new Promise((resolve, reject) => {
    const w = { type, resolve, timer: setTimeout(() => reject(new Error(`Child timeout: ${type}`)), 20000) };
    waiters.push(w);
  });
}
async function shutdown(exitCode) {
  if (guest) guest.kill();
  if (closeMeetings) await closeMeetings();
  if (apiServer) await new Promise((resolve) => apiServer.close(resolve));
  rmSync(profilePath, { recursive: true, force: true });
  app.exit(exitCode);
}

app.whenReady().then(async () => {
  try {
    if (!child) {
      apiServer = createServer((request, response) => {
        response.setHeader('Content-Type', 'application/json');
        response.setHeader('Access-Control-Allow-Origin', '*');
        response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        if (request.method === 'OPTIONS') { response.end('{}'); return; }
        if (request.url === '/portal/staff/login') response.end(JSON.stringify({ staff_id: '104217', name: 'Professor Test', valid: true }));
        else if (request.url === '/student/student-1') response.end(JSON.stringify({ student_id: 'student-1', name: 'Student Test', major: 'Computer Science', year: 2, gpa: 3.5, courses: [] }));
        else response.end(JSON.stringify({ contacts: [], messages: [], notifications: [] }));
      });
      await new Promise((resolve) => apiServer.listen(0, '127.0.0.1', resolve));
      process.env.AEGIS_API_URL = `http://127.0.0.1:${apiServer.address().port}`;
      process.env.AEGIS_MEETING_PORT = '0';
      process.env.AEGIS_MEETING_BIND = '0.0.0.0';
    }
    win = new BrowserWindow({ show: Boolean(process.env.MEETING_TEST_SCREENSHOT) && !child, width: 1440, height: 1000,
      webPreferences: { preload: path.join(root, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true } });
    closeMeetings = installMeetings(win);
    win.webContents.on('console-message', (event) => { if (event.level === 'error') errors.push(event.message); });
    await win.loadFile(path.join(root, 'index.html'));
    // The app's production CSP allows known backend URLs. These ephemeral mock
    // servers are accessed by the main-process login IPC; student background
    // requests may be blocked and are unrelated to the meeting path.
    if (child) {
      await login('student');
      await js(`document.getElementById('meeting-invitation').value = ${JSON.stringify(process.env.MEETING_TEST_INVITE)}; document.getElementById('meeting-join-form').requestSubmit();`);
      await until("document.getElementById('meeting-connection').textContent === 'Waiting for approval'", 'waiting room');
      assert.equal(await js("document.getElementById('meeting-mic').disabled && document.getElementById('meeting-camera').disabled"), true);
      process.send({ type: 'waiting' });
      process.on('message', async (command) => {
        try {
          if (command.type === 'publish') {
            await until("!document.getElementById('meeting-mic').disabled && !document.getElementById('meeting-screen').disabled", 'host grants');
            await click('meeting-mic');
            await until("document.getElementById('meeting-mic').getAttribute('aria-pressed') === 'true'", 'microphone capture');
            await click('meeting-camera');
            await until("document.getElementById('meeting-camera').getAttribute('aria-pressed') === 'true'", 'camera capture');
            await click('meeting-hand');
            process.send({ type: 'publishing' });
          } else if (command.type === 'board') {
            await click('meeting-board-toggle');
            await until("document.getElementById('meeting-canvas').getContext('2d').getImageData(0,0,1200,675).data.some(v => v !== 0)", 'remote whiteboard ink');
            process.send({ type: 'board' });
          } else if (command.type === 'screen') {
            await until("[...document.querySelectorAll('#meeting-screens video')].some(v => v.readyState >= 2 && !v.closest('figure').hidden)", 'remote shared screen');
            process.send({ type: 'screen' });
          } else if (command.type === 'revoked') {
            await until("document.getElementById('meeting-mic').disabled && document.getElementById('meeting-mic').getAttribute('aria-pressed') === 'false'", 'microphone stopped on revoke');
            process.send({ type: 'revoked' });
          } else if (command.type === 'end') {
            await until("!document.getElementById('meeting-lobby').hidden", 'lecture ended');
            assert.equal(await js("document.querySelectorAll('#meeting-room video, #meeting-room audio').length"), 0);
            await click('sign-out-button');
            await until("!document.getElementById('login-view').hidden", 'sign out');
            process.send({ type: 'finished' });
          }
        } catch (error) { process.send({ type: 'failure', message: error.stack }); }
      });
      return;
    }
    await login('staff');
    await js("document.getElementById('meeting-title').value = 'Integration lecture'; document.getElementById('meeting-host-form').requestSubmit();");
    await until("document.getElementById('meeting-share-invitation').value.length > 0", 'start lecture');
    const invitation = await js("document.getElementById('meeting-share-invitation').value");
    guest = spawn(process.execPath, [...(app.commandLine.hasSwitch('no-sandbox') ? ['--no-sandbox'] : []), __filename], {
      env: { ...process.env, MEETING_TEST_CHILD: '1', MEETING_TEST_INVITE: invitation },
      stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
    });
    guest.stdout.on('data', (data) => process.stdout.write(data));
    guest.stderr.on('data', (data) => process.stderr.write(data));
    guest.on('message', (value) => {
      if (value.type === 'failure') { console.error(value.message); void shutdown(1); }
      else message(value);
    });
    await wait('waiting');
    await until("[...document.querySelectorAll('#meeting-members-list button')].some(b => b.textContent === 'Admit')", 'host receives join request');
    await js("[...document.querySelectorAll('#meeting-members-list button')].find(b => b.textContent === 'Admit').click()");
    await until("[...document.querySelectorAll('#meeting-members-list button')].some(b => b.textContent === 'Allow speaking')", 'admitted controls');
    await js("[...document.querySelectorAll('#meeting-members-list button')].find(b => b.textContent === 'Allow speaking').click(); [...document.querySelectorAll('#meeting-members-list button')].find(b => b.textContent === 'Allow presenting').click()");
    guest.send({ type: 'publish' });
    await wait('publishing');
    await until("[...document.querySelectorAll('#meeting-videos video')].some(v => v.readyState >= 2 && !v.closest('figure').hidden)", 'remote camera frames', 20000);
    await until("[...document.querySelectorAll('#meeting-room audio')].some(a => a.readyState >= 2 && !a.muted)", 'remote audio', 20000);
    await until("document.getElementById('meeting-members-list').textContent.includes('✋')", 'raise hand');
    if (process.env.MEETING_TEST_SCREENSHOT) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      writeFileSync(process.env.MEETING_TEST_SCREENSHOT, (await win.webContents.capturePage()).toPNG());
    }
    console.log('PASS: professor and student login, waiting room, admission, permissions, remote audio/video, raise hand');
    await click('meeting-board-toggle');
    const bounds = await js("document.getElementById('meeting-canvas').scrollIntoView(); const r = document.getElementById('meeting-canvas').getBoundingClientRect(); ({x:r.left, y:r.top, width:r.width, height:r.height})");
    const start = {x:Math.round(bounds.x+bounds.width*.1), y:Math.round(bounds.y+bounds.height*.1)};
    const finish = {x:Math.round(bounds.x+bounds.width*.3), y:Math.round(bounds.y+bounds.height*.3)};
    win.webContents.sendInputEvent({type:'mouseDown', ...start, button:'left', clickCount:1});
    win.webContents.sendInputEvent({type:'mouseMove', ...finish, button:'left'});
    win.webContents.sendInputEvent({type:'mouseUp', ...finish, button:'left', clickCount:1});
    guest.send({ type: 'board' });
    await wait('board');
    // Validate real desktop screen/window enumeration and capture.
    await click('meeting-screen');
    await until("document.getElementById('meeting-source-dialog').open", 'screen picker');
    await js("document.querySelector('#meeting-sources button').click()", true);
    await until("document.getElementById('meeting-screen').getAttribute('aria-pressed') === 'true'", 'screen capture');
    guest.send({ type: 'screen' });
    await wait('screen');
    await click('meeting-screen');
    await until("document.getElementById('meeting-screen').getAttribute('aria-pressed') === 'false'", 'screen capture stopped');
    console.log('PASS: synchronized whiteboard ink, screen picker, remote screen playback and capture stop');
    await click('meeting-mute-all');
    guest.send({ type: 'revoked' });
    await wait('revoked');
    await until("[...document.querySelectorAll('#meeting-room audio')].every(a => a.muted)", 'receiver gates audio');
    await click('meeting-end');
    guest.send({ type: 'end' });
    await wait('finished');
    await until("!document.getElementById('meeting-lobby').hidden", 'host cleanup');
    assert.equal(await js("document.querySelectorAll('#meeting-room video, #meeting-room audio').length"), 0);
    const rendererErrors = errors.filter((e) => !e.includes('Content Security Policy') && !e.includes('Failed to fetch'));
    assert.deepEqual(rendererErrors, []);
    console.log('PASS: mute all stops capture, receiver gating, lecture ending, account sign out and media cleanup');
    await shutdown(0);
  } catch (error) { console.error(error.stack); await shutdown(1); }
});

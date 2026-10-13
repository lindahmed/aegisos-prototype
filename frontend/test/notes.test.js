'use strict';

const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { app, BrowserWindow } = require('electron');
const { installMeetings } = require('../meetings/desktop');

const root = path.join(__dirname, '..');
const profilePath = mkdtempSync(path.join(tmpdir(), 'unitrack-notes-test-'));
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let apiServer;
let win;
let closeMeetings;

async function until(expression, description, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await win.webContents.executeJavaScript(expression)) return;
    await wait(80);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function login() {
  await win.webContents.executeJavaScript(`
    document.getElementById('student-id').value = 'notes-student';
    document.getElementById('login-form').requestSubmit();
  `);
  await until("!document.getElementById('dashboard-view').hidden", 'student sign-in');
}

async function shutdown(code) {
  if (closeMeetings) await closeMeetings();
  if (win && !win.isDestroyed()) win.destroy();
  if (apiServer) await new Promise((resolve) => apiServer.close(resolve));
  rmSync(profilePath, { recursive: true, force: true });
  app.exit(code);
}

app.setPath('userData', profilePath);
app.disableHardwareAcceleration();

app.whenReady().then(async () => {
  try {
    apiServer = createServer((request, response) => {
      response.setHeader('Content-Type', 'application/json');
      if (request.url === '/student/notes-student') {
        response.end(JSON.stringify({
          student_id: 'notes-student', name: 'Notes Test', major: 'Computer Science',
          year: 2, gpa: 3.5, courses: [],
        }));
      } else {
        response.end(JSON.stringify({}));
      }
    });
    await new Promise((resolve) => apiServer.listen(0, '127.0.0.1', resolve));
    process.env.AEGIS_API_URL = `http://127.0.0.1:${apiServer.address().port}`;

    win = new BrowserWindow({
      show: false,
      webPreferences: {
        preload: path.join(root, 'preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    closeMeetings = installMeetings(win);
    await win.loadFile(path.join(root, 'index.html'), { query: { launch: 'notes-test' } });

    await win.webContents.executeJavaScript(`
      if (!document.querySelector('#workspace-notes #new-note-button')) {
        throw new Error('Notes button is missing from the workspace HTML');
      }
      if (!(document.querySelector('#workspace-notes').compareDocumentPosition(
        document.querySelector('.workspace-welcome')) & Node.DOCUMENT_POSITION_FOLLOWING)) {
        throw new Error('Notes must appear before the workspace welcome header');
      }
    `);

    await login();
    assert.equal(await win.webContents.executeJavaScript(
      "document.querySelector('#workspace-notes').hidden"), false);

    await win.webContents.executeJavaScript(
      "document.getElementById('new-note-button').click()", true);
    await win.webContents.executeJavaScript(`
      const title = document.getElementById('note-title');
      title.value = 'Integration note';
      title.dispatchEvent(new Event('input', { bubbles: true }));
      const body = document.getElementById('note-body');
      body.value = 'Saved before sign out';
      body.dispatchEvent(new Event('input', { bubbles: true }));
    `);
    assert.equal(await win.webContents.executeJavaScript(`
      JSON.parse(localStorage.getItem('aegisos:student-notes:notes-student'))[0].body
    `), 'Saved before sign out');

    await win.webContents.executeJavaScript(
      "document.getElementById('sign-out-button').click()", true);
    await until("!document.getElementById('login-view').hidden", 'sign out');
    await login();
    assert.equal(await win.webContents.executeJavaScript(
      "document.getElementById('note-title').value"), 'Integration note');

    await win.webContents.executeJavaScript(
      "document.getElementById('delete-note-button').click()", true);
    assert.deepEqual(await win.webContents.executeJavaScript(
      "JSON.parse(localStorage.getItem('aegisos:student-notes:notes-student'))"), []);
    console.log('Desktop notes UI, autosave, sign-in persistence, and deletion passed.');
    await shutdown(0);
  } catch (error) {
    console.error(error);
    await shutdown(1);
  }
});

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { _electron } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const root = path.resolve(__dirname, '..');
const tempRoot = path.join(root, '.tmp');
fs.mkdirSync(tempRoot, { recursive: true });
const runDir = fs.mkdtempSync(path.join(tempRoot, 'attachment-e2e-'));
const api = 'http://127.0.0.1:8001';
const contents = Buffer.from('Shared lecture notes\nChapter 1: operating systems.\n');
let backend;
let electron;
const errors = [];

async function waitForApi() {
  for (let i = 0; i < 120; i++) {
    if (backend.exitCode !== null) throw new Error(`Test backend exited with code ${backend.exitCode}`);
    try { if ((await fetch(`${api}/health`)).ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw new Error('Test backend did not start');
}

async function main() {
  try {
    await fetch(`${api}/health`);
    throw new Error('Port 8001 is occupied; refusing to send test data to an existing service');
  } catch (error) {
    if (!String(error).includes('fetch failed')) throw error;
  }
  backend = spawn(process.env.TEST_PYTHON || 'python', ['-m', 'uvicorn', 'backend.app:app', '--host', '127.0.0.1', '--port', '8001'], {
    cwd: root, windowsHide: true, stdio: 'ignore', env: {
      ...process.env, DATABASE_URL: '', NEO4J_URI: '',
      AEGIS_DB_PATH: path.join(runDir, 'test.db'),
      AEGIS_WORKSPACE_ROOT: path.join(runDir, 'students'),
      AEGIS_MATERIAL_STORAGE_ROOT: path.join(runDir, 'materials'),
    },
  });
  await waitForApi();
  console.log('Isolated test API ready');
  electron = await _electron.launch({
    executablePath: require('electron'),
    args: [path.join(root, 'frontend'), `--user-data-dir=${path.join(runDir, 'profile')}`],
    env: { ...process.env, AEGIS_ELECTRON_TEST: '1', AEGIS_ELECTRON_SMOKE: '0',
      AEGIS_API_URL: api, AEGIS_ACADEMIC_API_URL: api },
  });
  const page = await electron.firstWindow();
  page.setDefaultTimeout(15000);
  await electron.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0].webContents.setBackgroundThrottling(false);
  });
  const screenshot = async name => {
    const pixels = await electron.evaluate(async ({ BrowserWindow }) => {
      const capture = await BrowserWindow.getAllWindows()[0].capturePage(undefined, { stayHidden: true, stayAwake: true });
      return Array.from(capture.toPNG());
    });
    fs.writeFileSync(path.join(runDir, name), Buffer.from(pixels));
  };
  console.log('Electron window ready');
  page.on('pageerror', error => errors.push(error.message));
  const login = async id => {
    await page.locator('#student-id').fill(id);
    await page.locator('#login-button').click();
    await page.locator('#dashboard-view').waitFor({ state: 'visible' });
    await page.locator('#inbox-button').click();
  };
  await login('231027905');
  const contacts = await (await fetch(`${api}/messages/contacts?actor_type=student&actor_id=231027905`)).json();
  const recipient = contacts.contacts.find(contact => contact.id === '231027906');
  const third = contacts.contacts.find(contact => contact.id === '231027907');
  await page.locator('.conversation-item').filter({ hasText: recipient.name }).click();
  const paperclip = page.getByRole('button', { name: 'Attach document', exact: true });
  assert(await paperclip.isVisible(), 'Paperclip must be visible in the composer');
  await paperclip.focus();
  const chooserPromise = page.waitForEvent('filechooser');
  await paperclip.press('Enter');
  const chooser = await chooserPromise;
  await chooser.setFiles([]);
  assert(await page.locator('#message-attachment-preview').isHidden(), 'Cancel must not attach a file');
  console.log('PASS: keyboard activation opens file chooser; cancellation is safe');

  const selectFile = async (name, buffer = contents) => {
    const promise = page.waitForEvent('filechooser');
    await paperclip.click();
    await (await promise).setFiles({ name, mimeType: 'application/octet-stream', buffer });
  };
  await selectFile('lecture-notes.txt');
  assert((await page.locator('#message-attachment-name').textContent()).includes('lecture-notes.txt'));
  await page.getByRole('button', { name: 'Remove attachment' }).click();
  assert(await page.locator('#message-attachment-preview').isHidden());
  await selectFile('lecture-notes.txt');
  await page.locator('.conversation-item').filter({ hasText: third.name }).click();
  assert(await page.locator('#message-attachment-preview').isHidden(), 'Switching recipient must clear attachment');
  await page.locator('.conversation-item').filter({ hasText: recipient.name }).click();
  console.log('PASS: selected-file preview, remove, and conversation switch');

  await selectFile('unsafe.exe');
  assert((await page.locator('#message-status').textContent()).includes('Choose a PDF'));
  await selectFile('empty.txt', Buffer.alloc(0));
  assert((await page.locator('#message-status').textContent()).includes('empty'));
  await selectFile('large.pdf', Buffer.alloc(10 * 1024 * 1024 + 1));
  assert((await page.locator('#message-status').textContent()).includes('10 MB'));
  console.log('PASS: unsupported, empty, and oversized files show useful errors');

  await selectFile('lecture-notes.txt');
  await page.route('**/messages/attachments', route => route.fulfill({
    status: 503, contentType: 'application/json', body: JSON.stringify({ detail: 'Temporary upload failure' }),
  }));
  await page.locator('#message-send-button').click();
  await page.waitForFunction(() => document.querySelector('#message-status').textContent.includes('Temporary upload failure'));
  assert(await page.locator('#message-attachment-preview').isVisible(), 'Failed upload must preserve the file');
  assert(await paperclip.isEnabled());
  await page.unroute('**/messages/attachments');
  const sendPromise = page.waitForResponse(response => response.url().endsWith('/messages/attachments') && response.request().method() === 'POST');
  await page.locator('#message-send-button').click();
  const sent = await sendPromise;
  assert.equal(sent.status(), 200);
  const message = (await sent.json()).message;
  assert.equal(message.body, '');
  await page.getByRole('button', { name: 'Download lecture-notes.txt' }).waitFor();
  assert(await page.locator('#message-attachment-preview').isHidden());
  console.log('PASS: upload failure preserves attachment; retry sends a file without text');

  await selectFile('summary.txt');
  await page.locator('#message-compose-input').fill('Here are my notes');
  const captionPromise = page.waitForResponse(response => response.url().endsWith('/messages/attachments') && response.request().method() === 'POST');
  await page.locator('#message-send-button').click();
  assert.equal((await (await captionPromise).json()).message.body, 'Here are my notes');
  await page.getByRole('button', { name: 'Download summary.txt' }).waitFor();
  console.log('PASS: document with caption');

  await page.evaluate(() => applyTheme('dark'));
  await screenshot('sender-dark.png');
  await page.locator('[data-theme-toggle]').filter({ visible: true }).first().click();
  await screenshot('sender-light.png');
  await page.setViewportSize({ width: 1000, height: 720 });
  const clipBox = await paperclip.boundingBox();
  const sendBox = await page.locator('#message-send-button').boundingBox();
  assert(clipBox && sendBox && clipBox.x >= 0 && sendBox.x + sendBox.width <= 1000);
  await screenshot('minimum-window.png');

  await page.locator('#sign-out-button').click();
  await login('231027906');
  await page.locator('.conversation-item').filter({ hasText: 'Yasmin Wael' }).click();
  const downloadButton = page.getByRole('button', { name: 'Download lecture-notes.txt' });
  await downloadButton.waitFor();
  await electron.evaluate(({ session }, savePath) => {
    session.defaultSession.once('will-download', (_event, item) => item.setSavePath(savePath));
  }, path.join(runDir, 'received-notes.txt'));
  await downloadButton.click();
  const receivedPath = path.join(runDir, 'received-notes.txt');
  for (let i = 0; i < 60 && (!fs.existsSync(receivedPath) || fs.statSync(receivedPath).size !== contents.length); i++) {
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.deepEqual(fs.readFileSync(path.join(runDir, 'received-notes.txt')), contents);
  console.log('PASS: second student receives document and Electron downloads identical contents');
  assert.deepEqual(errors, [], 'No renderer errors');
  console.log(`Desktop attachment checks passed. Screenshots: ${runDir}`);
}

main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  if (electron) await electron.close();
  if (backend) backend.kill();
});

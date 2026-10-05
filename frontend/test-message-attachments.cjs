const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
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
  execFileSync(process.env.TEST_PYTHON || 'python', ['-c',
    'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("INSERT INTO students (student_id,name,major,year,gpa) VALUES (?,?,?,?,?)", ("231006157","Directory Test Student","Cybersecurity",3,3.5)); c.commit(); c.close()',
    path.join(runDir, 'test.db')], { windowsHide: true });
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
  await page.locator('.conversation-item').filter({ hasText: recipient.name }).waitFor();
  assert.equal(await page.locator('.conversation-item').filter({ hasText: third.name }).count(), 0);
  console.log('PASS: same-major classmates appear and other majors are hidden by default');

  // Simulate a running backend that returns the older contact shape without major.
  await page.route('**/messages/contacts?**', route => route.fulfill({
    contentType: 'application/json', body: JSON.stringify({ ...contacts,
      contacts: contacts.contacts.map(({ major, ...contact }) => contact) }),
  }));
  let releaseInbox;
  let inboxReleased = false;
  const delayedInbox = new Promise(resolve => { releaseInbox = resolve; });
  await page.route('**/messages?**', async route => {
    await delayedInbox;
    await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ messages: [] }) });
  });
  await page.locator('#sign-out-button').click();
  await login('231027905');
  await page.locator('.conversation-item').filter({ hasText: recipient.name }).waitFor();
  assert.equal(inboxReleased, false);
  inboxReleased = true;
  releaseInbox();
  await page.unroute('**/messages?**');
  await page.unroute('**/messages/contacts?**');
  console.log('PASS: classmates load with older backend responses without waiting for the inbox');

  // A failed inbox request must not prevent direct student-ID lookup.
  await page.route('**/messages/contacts?**', route => route.fulfill({
    status: 503, contentType: 'application/json', body: JSON.stringify({ detail: 'Directory unavailable' }),
  }));
  await page.route('**/messages?**', route => route.fulfill({
    status: 503, contentType: 'application/json', body: JSON.stringify({ detail: 'Inbox unavailable' }),
  }));
  await page.locator('#sign-out-button').click();
  await login('231027905');
  await page.locator('#message-search').fill('2310006157');
  await page.waitForFunction(() => document.querySelector('#message-search-status').textContent.includes('No registered student has ID 2310006157'));
  await page.locator('#message-search').fill('231006157');
  await page.waitForFunction(() => document.querySelector('#conversation-title').textContent === 'Directory Test Student');
  assert(await page.locator('#message-compose-input').isVisible());
  await page.locator('#message-compose-input').fill('Direct ID lookup works');
  const directSend = page.waitForResponse(response => response.url().endsWith('/messages') && response.request().method() === 'POST');
  await page.locator('#message-send-button').click();
  assert.equal((await (await directSend).json()).message.recipient_id, '231006157');
  await page.waitForFunction(() => !document.querySelector('#message-send-button').disabled);
  const received = await (await fetch(`${api}/messages?actor_type=student&actor_id=231006157`)).json();
  assert(received.messages.some(message => message.body === 'Direct ID lookup works'));
  console.log('PASS: screenshot typo gives an explicit error; correct ID opens and sends even when directory and inbox fail');
  await page.unroute('**/messages/contacts?**');
  await page.unroute('**/messages?**');
  await page.locator('#inbox-button').click();
  await page.locator('#new-message-button').click();
  await page.locator('.conversation-item').filter({ hasText: recipient.name }).waitFor();
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
  await page.locator('#message-search').fill(third.id);
  await page.waitForFunction(name => document.querySelector('#conversation-title').textContent === name, third.name);
  assert(await page.locator('#message-attachment-preview').isHidden(), 'Switching recipient must clear attachment');
  await page.locator('#message-search').fill(recipient.id);
  await page.waitForFunction(name => document.querySelector('#conversation-title').textContent === name, recipient.name);
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

  const sendText = async (senderId, body) => {
    const response = await fetch(`${api}/messages`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sender_type: 'student', sender_id: senderId,
        recipient_type: 'student', recipient_id: '231027906', body }),
    });
    assert.equal(response.status, 200);
    return (await response.json()).message;
  };
  const older = await sendText('231027907', 'Previous conversation from another major');
  const newer = await sendText('231006157', 'Newest incoming message');
  execFileSync(process.env.TEST_PYTHON || 'python', ['-c',
    'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("UPDATE portal_messages SET created_at=? WHERE message_id=?", ("2026-01-01T11:00:00+02:00",sys.argv[2])); c.execute("UPDATE portal_messages SET created_at=? WHERE message_id=?", ("2026-01-01T08:30:00Z",sys.argv[3])); c.commit(); c.close()',
    path.join(runDir, 'test.db'), older.message_id, newer.message_id], { windowsHide: true });
  // Both messages are older than the already-read document chat. Ranking uses real
  // timestamps (including offsets), not unread status or timestamp strings.
  await page.evaluate(() => refreshMessages());
  const keys = await page.locator('.conversation-item').evaluateAll(items => items.map(item => item.dataset.contactKey));
  assert(keys.indexOf('student:231027905') < keys.indexOf('student:231027907'));
  assert(keys.indexOf('student:231027907') < keys.indexOf('student:231006157'));
  console.log('PASS: recent chats include other majors and sort by actual message time');

  await page.evaluate(() => showDashboardSection('workspace'));
  const incoming = await sendText('231027905', 'Unread while on workspace');
  await page.evaluate(() => refreshMessages());
  const inbox = await (await fetch(`${api}/messages?actor_type=student&actor_id=231027906`)).json();
  assert.equal(inbox.messages.find(message => message.message_id === incoming.message_id).read, false);
  await page.locator('#inbox-button').click();
  await page.locator('#new-message-button').click();
  await sendText('231006157', 'Latest message moves this chat to the top');
  await page.evaluate(() => refreshMessages());
  const topChat = page.locator('.conversation-item').first();
  assert.equal(await topChat.getAttribute('data-contact-key'), 'student:231006157');
  assert((await topChat.textContent()).includes('Latest message moves this chat to the top'));
  assert.equal(await topChat.locator('.conversation-unread').textContent(), '2');
  await topChat.click();
  await page.waitForFunction(() => document.querySelector('#message-thread').textContent.includes('Newest incoming message')
    && document.querySelector('#message-thread').textContent.includes('Latest message moves this chat to the top'));
  assert.equal(await page.locator('.conversation-item').first().getAttribute('data-contact-key'), 'student:231006157');
  console.log('PASS: new messages move chats to the top with unread count and complete history');

  // Re-enter the account with an incomplete directory: saved history must rebuild
  // recent contacts and remain searchable even when those classmates are absent.
  await page.route('**/messages/contacts?**', route => route.fulfill({
    contentType: 'application/json', body: JSON.stringify({ contacts: [] }),
  }));
  await page.locator('#sign-out-button').click();
  await login('231027906');
  await page.waitForFunction(() => document.querySelector('.conversation-item')?.dataset.contactKey === 'student:231006157');
  await page.locator('.conversation-item').first().click();
  assert((await page.locator('#message-thread').textContent()).includes('Newest incoming message'));
  assert((await page.locator('#message-thread').textContent()).includes('Latest message moves this chat to the top'));
  await page.locator('#message-search').fill('Mariam');
  assert.equal(await page.locator('.conversation-item').first().getAttribute('data-contact-key'), 'student:231027907');
  await page.locator('#message-search').fill('');
  await page.unroute('**/messages/contacts?**');
  await screenshot('recent-chats.png');
  console.log('PASS: recent chats and history return after signing in again, even with an incomplete directory');
  assert.deepEqual(errors, [], 'No renderer errors');
  console.log(`Desktop attachment checks passed. Screenshots: ${runDir}`);
}

main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  if (electron) await electron.close();
  if (backend) backend.kill();
});

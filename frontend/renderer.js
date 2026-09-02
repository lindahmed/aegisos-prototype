const apiBaseUrl = window.aegis.apiBaseUrl;
const academicApiBaseUrl = window.aegis.academicApiBaseUrl || apiBaseUrl;

const loginView = document.querySelector('#login-view');
const dashboardView = document.querySelector('#dashboard-view');
const loginForm = document.querySelector('#login-form');
const loginButton = document.querySelector('#login-button');
const studentIdInput = document.querySelector('#student-id');
const loginStatus = document.querySelector('#login-status');
const actionStatus = document.querySelector('#action-status');
const courseList = document.querySelector('#course-list');
const createWorkspaceButton = document.querySelector('#create-workspace-button');
const openVsCodeButton = document.querySelector('#open-vscode-button');

const workspaceTab = document.querySelector('#workspace-tab');
const advisorTab = document.querySelector('#advisor-tab');
const progressTab = document.querySelector('#progress-tab');
const workspacePanel = document.querySelector('#workspace-panel');
const advisorPanel = document.querySelector('#advisor-panel');
const progressPanel = document.querySelector('#progress-panel');
const advisorForm = document.querySelector('#advisor-form');
const advisorInput = document.querySelector('#advisor-input');
const advisorSendButton = document.querySelector('#advisor-send-button');
const advisorVoiceButton = document.querySelector('#advisor-voice-button');
const advisorLanguage = document.querySelector('#advisor-language');
const advisorMessages = document.querySelector('#advisor-messages');
const advisorStatus = document.querySelector('#advisor-status');
const advisorIntent = document.querySelector('#advisor-intent');

let currentStudent = null;
let selectedCourse = null;
let advisorHistory = [];
let activeRecording = null;


async function apiRequest(path, options = {}) {
  let response;
  try {
    response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    });
  } catch (_error) {
    throw new Error('AegisOS backend is unavailable. Start the app with desktop/start-aegis.sh.');
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.detail || `Request failed (${response.status})`);
  }
  return payload;
}


async function academicApiRequest(path, options = {}) {
  let response;
  try {
    response = await fetch(`${academicApiBaseUrl}${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    });
  } catch (_error) {
    throw new Error('The shared academic notification service is unavailable.');
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.detail || `Request failed (${response.status})`);
  }
  return payload;
}


function setMessage(element, text, isError = false) {
  element.textContent = text;
  element.classList.toggle('error', isError);
}


function setBusy(isBusy) {
  loginButton.disabled = isBusy;
  createWorkspaceButton.disabled = isBusy;
  openVsCodeButton.disabled = isBusy;
}


function setAdvisorBusy(isBusy) {
  advisorInput.disabled = isBusy;
  advisorSendButton.disabled = isBusy;
  advisorVoiceButton.disabled = isBusy;
}


function selectCourse(course) {
  selectedCourse = course;
  for (const button of courseList.querySelectorAll('.course-button')) {
    button.setAttribute('aria-pressed', String(button.dataset.course === course));
  }
  setMessage(actionStatus, `Selected: ${course}`);
}


function showDashboardSection(section) {
  const showAdvisor = section === 'advisor';
  const showProgress = section === 'progress';
  workspacePanel.hidden = showAdvisor || showProgress;
  advisorPanel.hidden = !showAdvisor;
  progressPanel.hidden = !showProgress;
  workspaceTab.setAttribute('aria-pressed', String(!showAdvisor && !showProgress));
  advisorTab.setAttribute('aria-pressed', String(showAdvisor));
  progressTab.setAttribute('aria-pressed', String(showProgress));

  if (showAdvisor) {
    advisorInput.focus();
  }
}


function displayPercentage(value) {
  return value === null || value === undefined ? '—' : `${Number(value).toFixed(1)}%`;
}

function healthTone(value) {
  if (value === null || value === undefined) return 'health-unknown';
  return value >= 70 ? 'health-green' : value >= 60 ? 'health-yellow' : 'health-red';
}

function gradeMarks(course) {
  const posted = course.assessments.filter((item) => item.mark !== null && item.mark !== undefined);
  return posted.length ? posted.map((item) => `${item.name} ${Number(item.mark).toFixed(1)}/${Number(item.max_marks).toFixed(0)}`).join(' · ') : 'No marks posted yet';
}


function healthHistoryPoints(twin, course) {
  const points = (twin.weekly_history || [])
    .filter((row) => row.course_id === course.course_id)
    .map((row) => ({
      week: Number(row.week_number),
      value: row.course_health === null || row.course_health === undefined ? null : Number(row.course_health),
    }))
    .filter((point) => point.value !== null && !Number.isNaN(point.value))
    .sort((a, b) => a.week - b.week);

  const current = course.metrics.course_health;
  if (current !== null && current !== undefined && !points.some((point) => point.week === twin.current_week)) {
    points.push({ week: twin.current_week, value: Number(current) });
    points.sort((a, b) => a.week - b.week);
  }
  return points;
}


function buildHealthChart(points) {
  const chart = document.createElement('div');
  chart.className = 'health-chart';
  if (points.length === 0) {
    chart.classList.add('empty');
    chart.textContent = 'No weekly history yet';
    return chart;
  }

  const width = 210;
  const height = 60;
  const padX = 10;
  const padY = 10;
  const weeks = points.map((point) => point.week);
  const minWeek = Math.min(...weeks);
  const maxWeek = Math.max(...weeks);
  const span = Math.max(1, maxWeek - minWeek);
  const x = (week) => padX + ((week - minWeek) / span) * (width - padX * 2);
  const y = (value) => padY + (1 - Math.max(0, Math.min(100, value)) / 100) * (height - padY * 2);

  const latest = points[points.length - 1].value;
  const tone = latest >= 70 ? 'var(--green)' : latest >= 60 ? 'var(--amber)' : 'var(--red)';
  const linePoints = points.map((point) => `${x(point.week).toFixed(1)},${y(point.value).toFixed(1)}`).join(' ');
  const dots = points
    .map((point) => `<circle cx="${x(point.week).toFixed(1)}" cy="${y(point.value).toFixed(1)}" r="2.6" fill="${tone}"><title>Week ${point.week}: ${point.value.toFixed(1)}%</title></circle>`)
    .join('');

  chart.innerHTML = `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Weekly course health trend">
    <line x1="${padX}" y1="${y(60)}" x2="${width - padX}" y2="${y(60)}" stroke="var(--border)" stroke-dasharray="3 3" stroke-width="1"></line>
    <polyline points="${linePoints}" fill="none" stroke="${tone}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"></polyline>
    ${dots}
    <text class="health-chart-axis" x="${padX}" y="${height - 1}">W${minWeek}</text>
    <text class="health-chart-axis" x="${width - padX}" y="${height - 1}" text-anchor="end">W${maxWeek}</text>
  </svg>`;
  return chart;
}


function renderProgress(twin) {
  document.querySelector('#progress-week').textContent = `${twin.semester} · Week ${twin.current_week}`;
  const overallHealth = document.querySelector('#overall-health');
  overallHealth.textContent = displayPercentage(twin.overall_academic_health);
  overallHealth.className = healthTone(twin.overall_academic_health);
  const latest = twin.recent_interventions.find((item) => item.status === 'active' || item.status === 'escalated');
  document.querySelector('#current-intervention').textContent = latest?.message || twin.current_recommendation || 'No recommendation is needed right now.';
  const list = document.querySelector('#progress-course-list');
  list.replaceChildren();
  for (const course of twin.courses) {
    const card = document.createElement('article');
    card.className = 'progress-course-card';
    const title = document.createElement('h4');
    title.textContent = course.course_name;
    const risk = document.createElement('span');
    risk.className = `risk-badge ${course.risk_level || 'none'}`;
    risk.textContent = course.risk_level === 'high' ? 'high risk' : course.risk_level === 'medium' ? 'mid risk' : 'safe';
    const facts = document.createElement('p');
    facts.textContent = `Academic health ${displayPercentage(course.metrics.course_health)} · ${gradeMarks(course)} · Lectures ${course.completed_lectures.length}/${course.lectures.filter((lecture) => lecture.available_week <= twin.current_week).length}`;
    facts.classList.add(healthTone(course.metrics.course_health));
    const trendRow = document.createElement('div');
    trendRow.className = 'progress-trend-row';
    const details = document.createElement('p');
    details.className = 'progress-details';
    details.textContent = `Trend: ${course.metrics.trend}`;
    trendRow.append(details, buildHealthChart(healthHistoryPoints(twin, course)));
    card.append(title, risk, facts, trendRow);
    list.append(card);
  }
}


async function loadProgress(studentId) {
  setMessage(document.querySelector('#progress-status'), 'Loading semester progress...');
  try {
    const twin = await apiRequest(`/progress/${encodeURIComponent(studentId)}`);
    renderProgress(twin);
    setMessage(document.querySelector('#progress-status'), '');
  } catch (error) {
    setMessage(document.querySelector('#progress-status'), error.message, true);
  }
}


const notifButton = document.querySelector('#notif-button');
const notifBadge = document.querySelector('#notif-badge');
const notifPanel = document.querySelector('#notif-panel');
const notifList = document.querySelector('#notif-list');
const notifEmpty = document.querySelector('#notif-empty');
const notifClearButton = document.querySelector('#notif-clear-button');

const NOTIF_POLL_MS = 60000;
let notifTimer = null;
let notifPrimed = false;
let notifications = [];


function renderNotifications() {
  const unread = notifications.filter((item) => !item.read);

  notifBadge.hidden = unread.length === 0;
  notifBadge.textContent = String(unread.length);

  notifList.replaceChildren();
  notifEmpty.hidden = notifications.length > 0;
  for (const item of notifications) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = `notif-item ${item.type}${item.read ? '' : ' unread'}`;
    row.setAttribute('aria-label', `${item.read ? 'Mark unread' : 'Mark read'}: ${item.title}`);
    row.addEventListener('click', () => setNotificationReadState(item.id, !item.read));
    const dot = document.createElement('span');
    dot.className = 'notif-dot';
    const text = document.createElement('div');
    const title = document.createElement('p');
    title.className = 'notif-item-title';
    title.textContent = item.title;
    const body = document.createElement('p');
    body.className = 'notif-item-body';
    body.textContent = item.body;
    const meta = document.createElement('p');
    meta.className = 'notif-item-meta';
    meta.textContent = `${item.category} · ${item.timestamp}`;
    text.append(title, body, meta);
    row.append(dot, text);
    notifList.append(row);
  }
}


const toastContainer = document.querySelector('#toast-container');
const TOAST_DURATION_MS = 5000;


function showToasts(items) {
  for (const item of items.slice(0, 4)) {
    const toast = document.createElement('div');
    toast.className = `toast ${item.type}`;

    const body = document.createElement('div');
    body.className = 'toast-body';
    const title = document.createElement('p');
    title.className = 'toast-title';
    title.textContent = item.title;
    const text = document.createElement('p');
    text.className = 'toast-text';
    text.textContent = item.body;
    body.append(title, text);

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'toast-close';
    close.textContent = '✕';
    close.setAttribute('aria-label', 'Dismiss notification');

    let dismissed = false;
    const dismiss = () => {
      if (dismissed) return;
      dismissed = true;
      toast.classList.add('leaving');
      setTimeout(() => toast.remove(), 250);
    };
    close.addEventListener('click', dismiss);

    toast.append(body, close);
    toastContainer.append(toast);
    setTimeout(dismiss, TOAST_DURATION_MS);
  }
}


async function refreshNotifications() {
  if (!currentStudent) return;
  try {
    const response = await academicApiRequest(`/portal/students/${encodeURIComponent(currentStudent.student_id)}/notifications`);
    const items = response.notifications || [];
    const fresh = items.filter((item) => !item.read && !notifications.some((old) => old.id === item.id));
    notifications = items;
    renderNotifications();
    if (notifPrimed && fresh.length > 0) {
      showToasts(fresh);
    }
    notifPrimed = true;
  } catch (_error) {
    // Notification sync is best-effort and must never break the dashboard.
  }
}


function startNotificationSync() {
  stopNotificationSync();
  notifPrimed = false;
  notifications = [];
  renderNotifications();
  refreshNotifications();
  notifTimer = setInterval(refreshNotifications, NOTIF_POLL_MS);
}

function stopNotificationSync() {
  if (notifTimer) {
    clearInterval(notifTimer);
    notifTimer = null;
  }
}


async function markAllNotificationsRead() {
  if (!currentStudent) return;
  const unreadIds = notifications.filter((item) => !item.read).map((item) => item.id);
  if (unreadIds.length === 0) return;
  notifications = notifications.map((item) => ({ ...item, read: true }));
  renderNotifications();
  try {
    const response = await academicApiRequest(
      `/portal/students/${encodeURIComponent(currentStudent.student_id)}/notifications/read`,
      {
        method: 'PUT',
        body: JSON.stringify({ notification_ids: unreadIds, read: true }),
      },
    );
    notifications = response.notifications || [];
    renderNotifications();
  } catch (_error) {
    await refreshNotifications();
  }
}


async function setNotificationReadState(notificationId, read) {
  if (!currentStudent) return;
  notifications = notifications.map((item) =>
    item.id === notificationId ? { ...item, read } : item,
  );
  renderNotifications();
  try {
    const response = await academicApiRequest(
      `/portal/students/${encodeURIComponent(currentStudent.student_id)}/notifications/read`,
      {
        method: 'PUT',
        body: JSON.stringify({ notification_ids: [notificationId], read }),
      },
    );
    notifications = response.notifications || [];
    renderNotifications();
  } catch (_error) {
    await refreshNotifications();
  }
}


notifButton.addEventListener('click', () => {
  const opening = notifPanel.hidden;
  notifPanel.hidden = !opening;
  notifButton.setAttribute('aria-expanded', String(opening));
  if (opening) refreshNotifications();
});

notifClearButton.addEventListener('click', markAllNotificationsRead);

document.addEventListener('click', (event) => {
  if (notifPanel.hidden) return;
  if (event.target instanceof Element && event.target.closest('.notif-wrap')) return;
  notifPanel.hidden = true;
  notifButton.setAttribute('aria-expanded', 'false');
});

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || notifPanel.hidden) return;
  notifPanel.hidden = true;
  notifButton.setAttribute('aria-expanded', 'false');
  notifButton.focus();
});

window.addEventListener('focus', refreshNotifications);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshNotifications();
});


function addAdvisorMessage(role, content, audioUrl = null) {
  const message = document.createElement('div');
  message.className = `chat-message ${role}`;

  const label = document.createElement('span');
  label.className = 'chat-role';
  label.textContent = role === 'user' ? 'You' : 'Advisor AI';

  const body = document.createElement('p');
  body.textContent = content;

  message.append(label, body);

  if (audioUrl) {
    const audio = document.createElement('audio');
    audio.className = 'advisor-audio';
    audio.controls = true;
    audio.src = audioUrl;
    message.append(audio);
  }

  advisorMessages.append(message);
  advisorMessages.scrollTop = advisorMessages.scrollHeight;
}


function resetAdvisor() {
  advisorHistory = [];
  advisorMessages.replaceChildren();
  advisorIntent.textContent = 'Ready';
  setMessage(advisorStatus, '');

  if (currentStudent) {
    addAdvisorMessage(
      'assistant',
      `Hi ${currentStudent.name}. Ask me about academic progress, semester planning, career guidance, or a what-if scenario.`,
    );
  }
}


function renderStudent(student) {
  currentStudent = student;
  document.querySelector('#welcome-title').textContent = `Welcome, ${student.name}`;
  document.querySelector('#student-major').textContent = student.major;
  document.querySelector('#student-year').textContent = `Year ${student.year}`;
  document.querySelector('#student-gpa').textContent = Number(student.gpa).toFixed(2);
  document.querySelector('#course-count').textContent = `${student.courses.length} courses`;

  courseList.replaceChildren();
  for (const course of student.courses) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'course-button';
    button.dataset.course = course;
    button.textContent = course;
    button.setAttribute('aria-pressed', 'false');
    button.addEventListener('click', () => selectCourse(course));
    courseList.append(button);
  }

  loginView.hidden = true;
  dashboardView.hidden = false;
  showDashboardSection('workspace');
  resetAdvisor();
  loadProgress(student.student_id);
  startNotificationSync();

  if (student.courses.length > 0) {
    selectCourse(student.courses[0]);
  } else {
    selectedCourse = null;
    setMessage(actionStatus, 'No enrolled courses are available.');
  }
}


loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const studentId = studentIdInput.value.trim();
  if (!studentId) return;

  setBusy(true);
  setMessage(loginStatus, 'Loading student profile...');
  try {
    const student = await apiRequest(`/student/${encodeURIComponent(studentId)}`);
    setMessage(loginStatus, '');
    renderStudent(student);
  } catch (error) {
    setMessage(loginStatus, error.message, true);
  } finally {
    setBusy(false);
  }
});


async function runWorkspaceAction(path, pendingText) {
  if (!currentStudent || !selectedCourse) return;

  setBusy(true);
  setMessage(actionStatus, pendingText);
  try {
    const result = await apiRequest(path, {
      method: 'POST',
      body: JSON.stringify({
        student_id: currentStudent.student_id,
        course: selectedCourse,
      }),
    });
    setMessage(
      actionStatus,
      result.opened ? `VS Code opened: ${result.path}` : `Workspace ready: ${result.path}`,
    );
  } catch (error) {
    setMessage(actionStatus, error.message, true);
  } finally {
    setBusy(false);
  }
}


createWorkspaceButton.addEventListener('click', () => {
  runWorkspaceAction('/workspace/create', 'Preparing the course workspace...');
});


openVsCodeButton.addEventListener('click', () => {
  runWorkspaceAction('/workspace/vscode', 'Opening the course in VS Code...');
});


workspaceTab.addEventListener('click', () => showDashboardSection('workspace'));
advisorTab.addEventListener('click', () => showDashboardSection('advisor'));
progressTab.addEventListener('click', () => showDashboardSection('progress'));


advisorForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!currentStudent) return;

  const message = advisorInput.value.trim();
  if (!message) return;

  const priorHistory = advisorHistory.slice(-10);
  advisorHistory.push({ role: 'user', content: message });
  addAdvisorMessage('user', message);
  advisorInput.value = '';
  setAdvisorBusy(true);
  advisorIntent.textContent = 'Thinking';
  setMessage(advisorStatus, 'Advisor AI is processing your request...');

  try {
    const language = advisorLanguage.value;
    const result = await apiRequest('/advisor', {
      method: 'POST',
      body: JSON.stringify({
        student_id: currentStudent.student_id,
        message,
        language,
        history: priorHistory,
      }),
    });

    advisorHistory.push({ role: 'assistant', content: result.response });
    advisorHistory = advisorHistory.slice(-10);
    addAdvisorMessage('assistant', result.response);
    advisorIntent.textContent = result.intent.replaceAll('_', ' ');
    setMessage(advisorStatus, '');
  } catch (error) {
    advisorHistory.pop();
    advisorIntent.textContent = 'Unavailable';
    setMessage(advisorStatus, error.message, true);
  } finally {
    setAdvisorBusy(false);
    advisorInput.focus();
  }
});


function encodeWAV(samples, sampleRate = 16000) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);

  const writeString = (offset, string) => {
    for (let i = 0; i < string.length; i += 1) {
      view.setUint8(offset + i, string.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + samples.length * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, samples.length * 2, true);

  let offset = 44;
  for (let i = 0; i < samples.length; i += 1) {
    let sample = Math.max(-1, Math.min(1, samples[i]));
    sample = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
    view.setInt16(offset, sample, true);
    offset += 2;
  }

  return new Blob([buffer], { type: 'audio/wav' });
}


async function startRecording() {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const audioContext = new AudioContext({ sampleRate: 16000 });
  const source = audioContext.createMediaStreamSource(stream);
  const processor = audioContext.createScriptProcessor(4096, 1, 1);
  const chunks = [];

  source.connect(processor);
  processor.connect(audioContext.destination);

  processor.onaudioprocess = (event) => {
    chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)));
  };

  return {
    stream,
    audioContext,
    source,
    processor,
    stop: async () => {
      processor.disconnect();
      source.disconnect();
      stream.getTracks().forEach((track) => track.stop());
      await audioContext.close();

      const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
      const samples = new Float32Array(totalLength);
      let position = 0;
      for (const chunk of chunks) {
        samples.set(chunk, position);
        position += chunk.length;
      }
      return encodeWAV(samples, 16000);
    },
  };
}


function setRecordingState(isRecording) {
  advisorVoiceButton.classList.toggle('recording', isRecording);
  advisorVoiceButton.querySelector('.mic-icon').hidden = isRecording;
  advisorVoiceButton.querySelector('.recording-indicator').hidden = !isRecording;
  advisorVoiceButton.setAttribute(
    'aria-label',
    isRecording ? 'Stop recording' : 'Record voice message',
  );
}


async function sendVoiceMessage(blob) {
  if (!currentStudent) return;

  const language = advisorLanguage.value;
  const formData = new FormData();
  formData.append('student_id', currentStudent.student_id);
  formData.append('language', language);
  formData.append('audio', blob, 'message.wav');

  setAdvisorBusy(true);
  advisorIntent.textContent = 'Listening';
  setMessage(advisorStatus, 'Transcribing and thinking...');

  try {
    const response = await fetch(`${apiBaseUrl}/advisor/voice`, {
      method: 'POST',
      body: formData,
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.detail || `Voice request failed (${response.status})`);
    }

    advisorHistory.push({ role: 'user', content: payload.transcript });
    advisorHistory.push({ role: 'assistant', content: payload.response });
    advisorHistory = advisorHistory.slice(-10);

    addAdvisorMessage('user', payload.transcript);
    const audioUrl = `data:audio/mp3;base64,${payload.audio_base64}`;
    addAdvisorMessage('assistant', payload.response, audioUrl);
    advisorIntent.textContent = payload.intent.replaceAll('_', ' ');
    setMessage(advisorStatus, '');
  } catch (error) {
    setMessage(advisorStatus, error.message, true);
    advisorIntent.textContent = 'Unavailable';
  } finally {
    setAdvisorBusy(false);
  }
}


advisorVoiceButton.addEventListener('click', async () => {
  if (!currentStudent) return;

  if (activeRecording) {
    try {
      const blob = await activeRecording.stop();
      activeRecording = null;
      setRecordingState(false);
      await sendVoiceMessage(blob);
    } catch (error) {
      activeRecording = null;
      setRecordingState(false);
      setMessage(advisorStatus, error.message, true);
    }
    return;
  }

  try {
    activeRecording = await startRecording();
    setRecordingState(true);
    setMessage(advisorStatus, 'Recording... click Mic again to stop.');
  } catch (error) {
    setMessage(advisorStatus, `Microphone access failed: ${error.message}`, true);
  }
});


document.querySelector('#sign-out-button').addEventListener('click', () => {
  stopNotificationSync();
  notifications = [];
  toastContainer.replaceChildren();
  notifPanel.hidden = true;
  notifButton.setAttribute('aria-expanded', 'false');
  currentStudent = null;
  selectedCourse = null;
  advisorHistory = [];
  advisorMessages.replaceChildren();
  dashboardView.hidden = true;
  loginView.hidden = false;
  setMessage(actionStatus, '');
  setMessage(advisorStatus, '');
  studentIdInput.focus();
});

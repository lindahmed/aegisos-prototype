const apiBaseUrl = window.aegis.apiBaseUrl;

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
const advisorMessages = document.querySelector('#advisor-messages');
const advisorStatus = document.querySelector('#advisor-status');
const advisorIntent = document.querySelector('#advisor-intent');

let currentStudent = null;
let selectedCourse = null;
let advisorHistory = [];


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


function renderProgress(twin) {
  document.querySelector('#progress-week').textContent = `${twin.semester} · Week ${twin.current_week}`;
  document.querySelector('#overall-health').textContent = displayPercentage(twin.overall_academic_health);
  const latest = twin.recent_interventions[0];
  document.querySelector('#current-intervention').textContent = latest ? latest.message : 'No intervention recorded yet.';
  const list = document.querySelector('#progress-course-list');
  list.replaceChildren();
  for (const course of twin.courses) {
    const card = document.createElement('article');
    card.className = 'progress-course-card';
    const title = document.createElement('h4');
    title.textContent = course.course_name;
    const risk = document.createElement('span');
    risk.className = `risk-badge ${course.risk_level || 'none'}`;
    risk.textContent = course.risk_level || 'on track';
    const facts = document.createElement('p');
    facts.textContent = `Health ${displayPercentage(course.metrics.course_health)} · Weighted grade ${displayPercentage(course.metrics.weighted_grade)} · Lectures ${course.completed_lectures.length}/${course.lectures.filter((lecture) => lecture.available_week <= twin.current_week).length}`;
    const details = document.createElement('p');
    details.className = 'progress-details';
    details.textContent = `Assignments ${displayPercentage(course.metrics.assignment_average)} · Labs ${displayPercentage(course.metrics.lab_average)} · Exam ${displayPercentage(course.metrics.exam_percentage)} · ${course.metrics.trend}`;
    card.append(title, risk, facts, details);
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


function addAdvisorMessage(role, content) {
  const message = document.createElement('div');
  message.className = `chat-message ${role}`;

  const label = document.createElement('span');
  label.className = 'chat-role';
  label.textContent = role === 'user' ? 'You' : 'Advisor AI';

  const body = document.createElement('p');
  body.textContent = content;

  message.append(label, body);
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
    const result = await apiRequest('/advisor', {
      method: 'POST',
      body: JSON.stringify({
        student_id: currentStudent.student_id,
        message,
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


document.querySelector('#sign-out-button').addEventListener('click', () => {
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

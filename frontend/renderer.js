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

let currentStudent = null;
let selectedCourse = null;


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


function selectCourse(course) {
  selectedCourse = course;
  for (const button of courseList.querySelectorAll('.course-button')) {
    button.setAttribute('aria-pressed', String(button.dataset.course === course));
  }
  setMessage(actionStatus, `Selected: ${course}`);
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
  selectCourse(student.courses[0]);
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

document.querySelector('#sign-out-button').addEventListener('click', () => {
  currentStudent = null;
  selectedCourse = null;
  dashboardView.hidden = true;
  loginView.hidden = false;
  setMessage(actionStatus, '');
  studentIdInput.focus();
});

const apiBaseUrl = window.aegis.apiBaseUrl;
const academicApiBaseUrl = window.aegis.academicApiBaseUrl || apiBaseUrl;
const themeToggleButtons = document.querySelectorAll('[data-theme-toggle]');

const THEME_STORAGE_KEY = 'aegisos-theme';


function preferredTheme() {
  const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);
  if (savedTheme === 'light' || savedTheme === 'dark') return savedTheme;
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
}


function applyTheme(theme, persist = false) {
  const isLight = theme === 'light';
  document.documentElement.dataset.theme = isLight ? 'light' : 'dark';
  if (persist) localStorage.setItem(THEME_STORAGE_KEY, isLight ? 'light' : 'dark');

  for (const button of themeToggleButtons) {
    const nextTheme = isLight ? 'dark' : 'light';
    button.setAttribute('aria-label', `Switch to ${nextTheme} mode`);
    button.setAttribute('title', `Switch to ${nextTheme} mode`);
    button.querySelector('[data-theme-icon]').textContent = isLight ? '\u263E' : '\u2600';
    button.querySelector('[data-theme-label]').textContent =
      `${nextTheme[0].toUpperCase()}${nextTheme.slice(1)} mode`;
  }
}


applyTheme(preferredTheme());

for (const button of themeToggleButtons) {
  button.addEventListener('click', () => {
    const nextTheme = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
    applyTheme(nextTheme, true);
  });
}


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
const advisorBackButton = document.querySelector('#advisor-back-button');
const scoreButton = document.querySelector('#score-button');
const scorePanel = document.querySelector('#score-panel');

const workspaceTab = document.querySelector('#workspace-tab');
const advisorTab = document.querySelector('#advisor-tab');
const progressTab = document.querySelector('#progress-tab');
const calendarTab = document.querySelector('#calendar-tab');
const workspacePanel = document.querySelector('#workspace-panel');
const advisorPanel = document.querySelector('#advisor-panel');
const progressPanel = document.querySelector('#progress-panel');
const calendarPanel = document.querySelector('#calendar-panel');
const messagesPanel = document.querySelector('#messages-panel');
const advisorForm = document.querySelector('#advisor-form');
const advisorInput = document.querySelector('#advisor-input');
const advisorSendButton = document.querySelector('#advisor-send-button');
const advisorVoiceButton = document.querySelector('#advisor-voice-button');
const advisorLanguage = document.querySelector('#advisor-language');
const advisorMessages = document.querySelector('#advisor-messages');
const advisorStatus = document.querySelector('#advisor-status');
const advisorIntent = document.querySelector('#advisor-intent');

const calendarGrid = document.querySelector('#calendar-grid');
const calendarMonthTitle = document.querySelector('#calendar-month-title');
const calendarSelectedTitle = document.querySelector('#calendar-selected-title');
const calendarAgendaList = document.querySelector('#calendar-agenda-list');
const calendarModal = document.querySelector('#calendar-modal');
const calendarEventForm = document.querySelector('#calendar-event-form');
const calendarEventTitle = document.querySelector('#calendar-event-title');
const calendarEventDescription = document.querySelector('#calendar-event-description');
const calendarEventDate = document.querySelector('#calendar-event-date');
const calendarEventTime = document.querySelector('#calendar-event-time');
const calendarEventDuration = document.querySelector('#calendar-event-duration');
const calendarEventType = document.querySelector('#calendar-event-type');
const calendarFormStatus = document.querySelector('#calendar-form-status');

let currentStudent = null;
let selectedCourse = null;
let advisorHistory = [];
let activeRecording = null;
let currentTwin = null;
let progressState = 'loading';
let scoreRequestId = 0;

function closeScorePanel() {
  scorePanel.hidden = true;
  scoreButton.setAttribute('aria-expanded', 'false');
}

function renderScoreRows(container, rows, studentId) {
  container.replaceChildren();
  for (const row of rows) {
    const item = document.createElement('li');
    item.className = `score-row${row.student_id === studentId ? ' is-you' : ''}`;
    const rank = document.createElement('span');
    rank.className = 'score-row-rank';
    rank.textContent = `#${row.rank}`;
    const name = document.createElement('span');
    name.className = 'score-row-name';
    name.textContent = `${row.name}${row.student_id === studentId ? ' (you)' : ''}`;
    const points = document.createElement('strong');
    points.textContent = `${row.score} pts`;
    item.append(rank, name, points);
    container.append(item);
  }
}

async function loadScores(studentId) {
  const requestId = ++scoreRequestId;
  try {
    const data = await apiRequest(`/scores/${encodeURIComponent(studentId)}`);
    if (requestId !== scoreRequestId || currentStudent?.student_id !== studentId) return;
    document.querySelector('#score-value').textContent = data.me.score;
    document.querySelector('#score-rank').textContent = `Rank #${data.me.rank}`;
    const totals = data.me.totals;
    document.querySelector('#score-summary').textContent =
      `${totals.lectures} lectures · ${totals.exams_taken} exams taken (${totals.good_exams} good marks) · ${totals.projects} projects · ${totals.awards} awards`;
    renderScoreRows(document.querySelector('#score-top-five'), data.top_five, studentId);
    renderScoreRows(document.querySelector('#score-nearby'), data.nearby, studentId);
    const weekly = document.querySelector('#score-weekly');
    weekly.replaceChildren();
    if (!data.me.weekly.length) {
      weekly.textContent = 'No scored activity yet.';
    } else {
      for (const week of data.me.weekly) {
        const row = document.createElement('p');
        row.textContent = `Week ${week.week}: +${week.points} pts · ${week.lectures} lectures, ${week.exams_taken} exams, ${week.projects} projects, ${week.awards} awards`;
        weekly.append(row);
      }
    }
  } catch (error) {
    if (requestId !== scoreRequestId || currentStudent?.student_id !== studentId) return;
    document.querySelector('#score-summary').textContent = error.message;
  }
}

scoreButton.addEventListener('click', () => {
  const opening = scorePanel.hidden;
  scorePanel.hidden = !opening;
  scoreButton.setAttribute('aria-expanded', String(opening));
  if (opening && currentStudent) loadScores(currentStudent.student_id);
});
document.addEventListener('click', (event) => {
  if (!event.target.closest('.score-wrap')) closeScorePanel();
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') closeScorePanel();
});
let calendarCustomEvents = [];
let calendarSelectedDate = new Date();
let calendarMonth = new Date(calendarSelectedDate.getFullYear(), calendarSelectedDate.getMonth(), 1);


async function apiRequest(path, options = {}) {
  let response;
  try {
    response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    });
  } catch (_error) {
    throw new Error('UniTrack is unavailable. Start the app with desktop/start-aegis.sh.');
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.detail || `Request failed (${response.status})`);
    error.status = response.status;
    throw error;
  }
  return payload;
}


async function academicApiRequest(path, options = {}) {
  let response;
  try {
    response = await fetch(`${academicApiBaseUrl}${path}`, {
      ...options,
      headers: {
        ...(options.body instanceof FormData ? {} : { 'Content-Type': 'application/json' }),
        ...(options.headers || {}),
      },
    });
  } catch (_error) {
    throw new Error('The shared academic notification service is unavailable.');
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.detail || `Request failed (${response.status})`);
    error.status = response.status;
    throw error;
  }
  return payload;
}


function setMessage(element, text, isError = false) {
  element.textContent = text;
  element.classList.toggle('error', isError);
}


function setBusy(isBusy) {
  loginButton.disabled = isBusy;
  createWorkspaceButton.disabled = isBusy || !currentStudent?.courses.length;
  openVsCodeButton.disabled = isBusy || !currentStudent?.courses.length;
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
  setMessage(actionStatus, '');
  renderWorkspaceOverview();
}

function renderWorkspaceOverview() {
  if (!currentStudent) return;
  const course = currentTwin?.courses.find((item) => item.course_name === selectedCourse);
  document.querySelector('#focus-course-name').textContent = selectedCourse || 'Choose a course';
  document.querySelector('#workspace-week').textContent = currentTwin
    ? `· ${currentTwin.semester} · Week ${currentTwin.current_week}` : '';
  document.querySelector('#focus-course-health').textContent = course?.metrics?.course_health == null
    ? (progressState === 'error' || currentTwin ? 'Progress unavailable' : 'Progress loading') : `${displayPercentage(course.metrics.course_health)} academic health`;
  const availableLectures = course?.lectures.filter((item) => item.available_week <= currentTwin.current_week) || [];
  document.querySelector('#focus-lectures').textContent = course
    ? `${course.completed_lectures.length} / ${availableLectures.length}` : '—';
  document.querySelector('#focus-assessments').textContent = course
    ? `${course.assessments.filter((item) => item.mark != null).length} / ${course.assessments.length}` : '—';
  const nextLecture = course?.unstudied_lectures.find((item) => item.available_week <= currentTwin.current_week);
  const nextAssessment = course?.assessments
    .filter((item) => item.mark == null && item.due_week >= currentTwin.current_week)
    .sort((left, right) => left.due_week - right.due_week)[0];
  document.querySelector('#focus-next').textContent = nextLecture?.title
    || (nextAssessment ? `${nextAssessment.name} · Week ${nextAssessment.due_week}` : course ? 'Caught up for now' : progressState === 'error' ? 'Progress unavailable' : 'Loading course progress…');

  const latest = currentTwin?.recent_interventions.find((item) => item.status === 'active' || item.status === 'escalated');
  document.querySelector('#workspace-recommendation').textContent = latest?.message
    || currentTwin?.current_recommendation
    || (currentTwin ? 'Keep studying your available lectures and check the calendar for upcoming work.' : progressState === 'error' ? 'Progress is unavailable right now. You can still open your course tools and calendar.' : 'Loading your latest recommendation…');

  const upcoming = document.querySelector('#workspace-upcoming');
  upcoming.replaceChildren();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const events = allCalendarEvents()
    .filter((event) => !event.completed && new Date(event.startAt) >= today)
    .slice(0, 3);
  if (events.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'overview-empty';
    empty.textContent = currentTwin || progressState === 'error' ? 'Nothing upcoming yet. Add a study session in your calendar.' : 'Loading upcoming work…';
    upcoming.append(empty);
  }
  for (const event of events) {
    const row = document.createElement('div');
    row.className = 'overview-event';
    const details = document.createElement('div');
    const kind = document.createElement('span');
    kind.className = 'overview-event-kind';
    kind.textContent = eventTypeLabel(event);
    const title = document.createElement('strong');
    title.textContent = event.title;
    details.append(kind, title);
    const date = document.createElement('time');
    date.dateTime = event.startAt;
    date.textContent = new Date(event.startAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    row.append(details, date);
    upcoming.append(row);
  }
}


function showDashboardSection(section) {
  const showAdvisor = section === 'advisor';
  const showProgress = section === 'progress';
  const showCalendar = section === 'calendar';
  const showMessages = section === 'messages';
  workspacePanel.hidden = showAdvisor || showProgress || showCalendar || showMessages;
  advisorPanel.hidden = !showAdvisor;
  progressPanel.hidden = !showProgress;
  calendarPanel.hidden = !showCalendar;
  messagesPanel.hidden = !showMessages;
  dashboardView.dataset.section = section;
  workspaceTab.setAttribute('aria-pressed', String(!showAdvisor && !showProgress && !showCalendar && !showMessages));
  advisorTab.setAttribute('aria-pressed', String(showAdvisor));
  progressTab.setAttribute('aria-pressed', String(showProgress));
  calendarTab.setAttribute('aria-pressed', String(showCalendar));

  if (showAdvisor) {
    advisorInput.focus();
  }
  if (showCalendar) {
    renderCalendar();
  }
  if (showMessages) {
    refreshMessages(true);
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
    if (!currentStudent || currentStudent.student_id !== studentId) return;
    currentTwin = twin;
    progressState = 'ready';
    renderProgress(twin);
    const scheduled = scheduleUrgentStudySessions();
    renderCalendar();
    renderWorkspaceOverview();
    if (scheduled.length > 0) {
      showToasts([{
        type: 'study',
        title: 'AI study plan updated',
        body: `${scheduled.length} urgent study ${scheduled.length === 1 ? 'session was' : 'sessions were'} added to your calendar.`,
      }]);
    }
    setMessage(document.querySelector('#progress-status'), '');
  } catch (error) {
    if (!currentStudent || currentStudent.student_id !== studentId) return;
    currentTwin = null;
    progressState = 'error';
    renderCalendar();
    renderWorkspaceOverview();
    setMessage(document.querySelector('#progress-status'), error.message, true);
  }
}


const CALENDAR_EXAM_TYPES = new Set(['midterm', 'final', 'exam']);

function calendarDateKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function calendarStorageKey(studentId) {
  return `aegisos-calendar:${studentId}`;
}

function loadCalendarEvents(studentId) {
  try {
    const stored = JSON.parse(localStorage.getItem(calendarStorageKey(studentId)) || '[]');
    return Array.isArray(stored)
      ? stored.filter((event) => event?.id && event?.title && event?.startAt && event?.endAt)
      : [];
  } catch (_error) {
    return [];
  }
}

function saveCalendarEvents() {
  if (!currentStudent) return;
  try {
    localStorage.setItem(calendarStorageKey(currentStudent.student_id), JSON.stringify(calendarCustomEvents));
  } catch (_error) {
    // Keep the planner usable for this session when local storage is unavailable.
  }
  renderWorkspaceOverview();
}

function semesterStart(currentWeek) {
  const currentWeekSaturday = new Date();
  currentWeekSaturday.setHours(0, 0, 0, 0);
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() - ((currentWeekSaturday.getDay() + 1) % 7));
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() - (Number(currentWeek) - 1) * 7);
  // Calendar events retain the established Monday-Sunday placement grid.
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() + 2);
  return currentWeekSaturday;
}


function resizeAdvisorInput() {
  advisorInput.style.height = 'auto';
  const inputStyle = window.getComputedStyle(advisorInput);
  const minHeight = Number.parseFloat(inputStyle.minHeight) || 74;
  const maxHeight = Number.parseFloat(inputStyle.maxHeight) || 220;
  const nextHeight = Math.max(minHeight, Math.min(advisorInput.scrollHeight, maxHeight));
  advisorInput.style.height = `${nextHeight}px`;
}

function academicCalendarEvents() {
  if (!currentTwin) return [];
  const startOfSemester = semesterStart(currentTwin.current_week);
  return currentTwin.courses.flatMap((course) => (course.assessments || []).map((assessment) => {
    const isExam = CALENDAR_EXAM_TYPES.has(String(assessment.assessment_type).toLowerCase());
    const start = new Date(startOfSemester);
    start.setDate(start.getDate() + (Number(assessment.due_week) - 1) * 7 + (isExam ? 0 : 6));
    start.setHours(isExam ? 9 : 22, 0, 0, 0);
    return {
      id: `academic:${assessment.assessment_id}`,
      title: assessment.name,
      description: `${course.course_name} · ${assessment.max_marks} marks · academic week ${assessment.due_week}`,
      startAt: start.toISOString(),
      endAt: new Date(start.getTime() + (isExam ? 120 : 60) * 60000).toISOString(),
      type: isExam ? 'exam' : 'assignment',
      source: 'academic',
      courseId: course.course_id,
      completed: assessment.mark !== null && assessment.mark !== undefined,
    };
  }));
}

function allCalendarEvents() {
  return [...academicCalendarEvents(), ...calendarCustomEvents]
    .sort((left, right) => new Date(left.startAt) - new Date(right.startAt));
}

function eventsOverlap(start, end, events) {
  return events.some((event) => start < new Date(event.endAt) && end > new Date(event.startAt));
}

function nextStudySlot(events, offset) {
  const now = new Date();
  const first = new Date(now);
  first.setMinutes(0, 0, 0);
  if (first.getHours() >= 18) first.setDate(first.getDate() + 1);
  const candidates = [];
  for (let day = 0; day < 5; day += 1) {
    for (const hour of [18, 20]) {
      const candidate = new Date(first);
      candidate.setDate(first.getDate() + day);
      candidate.setHours(hour, 0, 0, 0);
      candidates.push(candidate);
    }
  }
  const rotated = [...candidates.slice(offset), ...candidates.slice(0, offset)];
  return rotated.find((start) => start > now && !eventsOverlap(start, new Date(start.getTime() + 90 * 60000), events))
    || candidates[candidates.length - 1];
}

function riskText(course) {
  const risks = Array.isArray(course.risks) ? course.risks : [];
  const messages = risks.slice(0, 2).map((risk) => typeof risk === 'string' ? risk : risk.message).filter(Boolean);
  return messages.length > 0 ? messages.join('; ') : `${course.risk_level || 'elevated'} academic risk was detected`;
}

function scheduleUrgentStudySessions() {
  if (!currentTwin) return [];
  const existing = allCalendarEvents();
  const urgentCourses = currentTwin.courses.filter((course) => {
    const health = course.metrics?.course_health;
    return course.risk_level === 'high'
      || (health !== null && health !== undefined && Number(health) < 60 && (course.risks || []).length > 0);
  });
  const added = [];
  for (const [index, course] of urgentCourses.entries()) {
    const id = `ai:${currentTwin.semester}:${currentTwin.current_week}:${course.course_id}`;
    if (calendarCustomEvents.some((event) => event.id === id)) continue;
    const start = nextStudySlot([...existing, ...added], index);
    added.push({
      id,
      title: `Urgent study: ${course.course_name}`,
      description: `AI scheduled this focus session because ${riskText(course)}.`,
      startAt: start.toISOString(),
      endAt: new Date(start.getTime() + 90 * 60000).toISOString(),
      type: 'study_session',
      source: 'ai',
      courseId: course.course_id,
      urgent: true,
    });
  }
  if (added.length > 0) {
    calendarCustomEvents.push(...added);
    saveCalendarEvents();
  }
  return added;
}

function eventTypeLabel(event) {
  if (event.type === 'study_session') return event.source === 'ai' ? 'AI study session' : 'Study session';
  if (event.type === 'assignment') return 'Assignment deadline';
  return event.type.charAt(0).toUpperCase() + event.type.slice(1);
}

function renderCalendarAgenda(events) {
  calendarSelectedTitle.textContent = calendarSelectedDate.toLocaleDateString(undefined, {
    weekday: 'long', month: 'long', day: 'numeric',
  });
  calendarAgendaList.replaceChildren();
  if (events.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'calendar-empty';
    empty.textContent = 'No events yet. Add a study session or personal event.';
    calendarAgendaList.append(empty);
    return;
  }
  for (const event of events) {
    const card = document.createElement('article');
    card.className = `calendar-agenda-card ${event.type}${event.completed ? ' completed' : ''}`;
    const meta = document.createElement('p');
    meta.className = 'calendar-event-meta';
    meta.textContent = `${new Date(event.startAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} · ${eventTypeLabel(event)}`;
    const title = document.createElement('h5');
    title.textContent = event.title;
    const description = document.createElement('p');
    description.textContent = event.description || (event.source === 'student' ? 'Personal calendar event' : 'Academic calendar event');
    card.append(meta, title, description);
    if (event.completed) {
      const done = document.createElement('span');
      done.className = 'calendar-completed';
      done.textContent = 'Completed';
      card.append(done);
    } else if (event.source !== 'academic') {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'calendar-delete-button';
      remove.textContent = 'Remove';
      remove.addEventListener('click', () => {
        calendarCustomEvents = calendarCustomEvents.filter((item) => item.id !== event.id);
        saveCalendarEvents();
        renderCalendar();
      });
      card.append(remove);
    }
    calendarAgendaList.append(card);
  }
}

function renderCalendar() {
  if (!calendarGrid) return;
  const events = allCalendarEvents();
  calendarMonthTitle.textContent = calendarMonth.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  calendarGrid.replaceChildren();
  const first = new Date(calendarMonth);
  first.setDate(1 - ((first.getDay() + 6) % 7));
  const todayKey = calendarDateKey(new Date());
  const selectedKey = calendarDateKey(calendarSelectedDate);

  for (let index = 0; index < 42; index += 1) {
    const date = new Date(first);
    date.setDate(first.getDate() + index);
    const dateKey = calendarDateKey(date);
    const dayEvents = events.filter((event) => calendarDateKey(new Date(event.startAt)) === dateKey);
    const day = document.createElement('button');
    day.type = 'button';
    day.className = 'calendar-day';
    if (date.getMonth() !== calendarMonth.getMonth()) day.classList.add('outside');
    if (dateKey === todayKey) day.classList.add('today');
    if (dateKey === selectedKey) day.classList.add('selected');
    day.setAttribute('aria-label', `${date.toLocaleDateString()}${dayEvents.length ? `, ${dayEvents.length} events` : ''}`);
    const number = document.createElement('span');
    number.className = 'calendar-day-number';
    number.textContent = String(date.getDate());
    day.append(number);
    for (const event of dayEvents.slice(0, 3)) {
      const pill = document.createElement('span');
      pill.className = `calendar-event-pill ${event.type}`;
      pill.textContent = event.title;
      day.append(pill);
    }
    if (dayEvents.length > 3) {
      const more = document.createElement('span');
      more.className = 'calendar-event-more';
      more.textContent = `+${dayEvents.length - 3} more`;
      day.append(more);
    }
    day.addEventListener('click', () => {
      calendarSelectedDate = date;
      renderCalendar();
    });
    day.addEventListener('dblclick', () => openCalendarModal(date));
    calendarGrid.append(day);
  }
  renderCalendarAgenda(events.filter((event) => calendarDateKey(new Date(event.startAt)) === selectedKey));
}

function openCalendarModal(date = calendarSelectedDate) {
  calendarEventForm.reset();
  calendarEventDate.value = calendarDateKey(date);
  calendarEventTime.value = '18:00';
  calendarEventDuration.value = '60';
  calendarEventType.value = 'study_session';
  setMessage(calendarFormStatus, '');
  calendarModal.hidden = false;
  calendarEventTitle.focus();
}

function closeCalendarModal() {
  calendarModal.hidden = true;
  calendarEventForm.reset();
  setMessage(calendarFormStatus, '');
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
  if (event.key !== 'Escape') return;
  if (!calendarModal.hidden) {
    closeCalendarModal();
    document.querySelector('#calendar-add-button').focus();
    return;
  }
  if (!notifPanel.hidden) {
    notifPanel.hidden = true;
    notifButton.setAttribute('aria-expanded', 'false');
    notifButton.focus();
  }
});

window.addEventListener('focus', refreshNotifications);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshNotifications();
});


const inboxButton = document.querySelector('#inbox-button');
const inboxBadge = document.querySelector('#inbox-badge');
const conversationList = document.querySelector('#conversation-list');
const conversationTitle = document.querySelector('#conversation-title');
const conversationSubtitle = document.querySelector('#conversation-subtitle');
const messageThread = document.querySelector('#message-thread');
const messageSearch = document.querySelector('#message-search');
const messageSearchStatus = document.querySelector('#message-search-status');
const messageComposeForm = document.querySelector('#message-compose-form');
const messageComposeInput = document.querySelector('#message-compose-input');
const messageSendButton = document.querySelector('#message-send-button');
const messageStatus = document.querySelector('#message-status');
const messageSyncStatus = document.querySelector('#message-sync-status');
const messageChatsTab = document.querySelector('#message-chats-tab');
const messageContactsTab = document.querySelector('#message-contacts-tab');
const messageChatsCount = document.querySelector('#message-chats-count');
const messageJumpLatest = document.querySelector('#message-jump-latest');
const messageAttachButton = document.querySelector('#message-attach-button');
const messageAttachmentInput = document.querySelector('#message-attachment-input');
const messageAttachmentPreview = document.querySelector('#message-attachment-preview');
const messageAttachmentName = document.querySelector('#message-attachment-name');
const messageAttachmentRemove = document.querySelector('#message-attachment-remove');
const MESSAGE_DOCUMENT_EXTENSIONS = new Set(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'rtf', 'odt', 'ods', 'odp']);
const MESSAGE_DOCUMENT_MAX_BYTES = 10 * 1024 * 1024;
let selectedMessageFile = null;
let messageSending = false;
const MESSAGE_POLL_MS = 15000;
const MESSAGE_ACTIVE_POLL_MS = 3000;
const MESSAGE_DIRECTORY_POLL_MS = 60000;
let messageContacts = [];
let campusMessages = [];
let selectedMessageContact = null;
let messageTimer = null;
let messageListMode = 'chats';
let messageSyncGeneration = 0;
let messageRefreshTask = null;
let messageDirectoryUpdatedAt = 0;
let renderedMessageThreadKey = null;
let renderedMessageThreadSignature = '';
let renderedConversationListSignature = '';
const pendingMessageReads = new Set();
let messageStudentLookupTimer = null;
let messageStudentLookupSequence = 0;
let messageStudentLookupId = null;
const lookedUpMessageContacts = new Map();


function contactKey(contact) {
  return `${contact.type}:${contact.id}`;
}


function messagesForContact(contact) {
  if (!contact) return [];
  if (contact.type === 'broadcast') {
    return campusMessages.filter((message) => message.is_broadcast);
  }
  return campusMessages.filter((message) => {
    if (message.is_broadcast) return false;
    return (
      (message.sender_type === contact.type && String(message.sender_id) === String(contact.id))
      || (message.recipient_type === contact.type && String(message.recipient_id) === String(contact.id))
    );
  });
}


function conversationContacts() {
  const contacts = new Map();
  for (const message of campusMessages) {
    if (message.is_broadcast) {
      contacts.set('broadcast:all-students', {
        type: 'broadcast', id: 'all-students', name: 'Professor broadcasts',
        subtitle: 'Messages sent to all students',
      });
      continue;
    }
    const outgoing = message.sender_type === 'student'
      && String(message.sender_id) === String(currentStudent?.student_id);
    const type = outgoing ? message.recipient_type : message.sender_type;
    const id = outgoing ? message.recipient_id : message.sender_id;
    if (!type || !id) continue;
    const contact = {
      type, id: String(id),
      name: (outgoing ? message.recipient_name : message.sender_name) || `Student ${id}`,
      subtitle: type === 'staff' ? 'Professor' : `Student ID ${id}`,
    };
    contacts.set(contactKey(contact), contact);
  }
  for (const contact of messageContacts) contacts.set(contactKey(contact), contact);
  return [...contacts.values()];
}


function messageTimestamp(message) {
  return Date.parse(message?.created_at) || 0;
}


function formatMessageTime(value) {
  const date = new Date(value);
  const today = new Date();
  const sameDay = date.toDateString() === today.toDateString();
  return new Intl.DateTimeFormat('en', sameDay
    ? { hour: 'numeric', minute: '2-digit' }
    : { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(date);
}


function updateInboxBadge() {
  const unread = campusMessages.filter((message) => !message.read && !isOutgoingMessage(message)).length;
  inboxBadge.hidden = unread === 0;
  inboxBadge.textContent = String(unread);
  messageChatsCount.hidden = unread === 0;
  messageChatsCount.textContent = String(unread);
}


function isOutgoingMessage(message) {
  return message.sender_type === 'student'
    && String(message.sender_id) === String(currentStudent?.student_id);
}


function setMessageListMode(mode) {
  messageListMode = mode;
  messageChatsTab.setAttribute('aria-pressed', String(mode === 'chats'));
  messageContactsTab.setAttribute('aria-pressed', String(mode === 'contacts'));
  renderConversationList();
}


function renderConversationList() {
  const query = messageSearch.value.trim().toLowerCase();
  const previousTopContact = conversationList.querySelector('.conversation-item')?.dataset.contactKey;
  const previousScrollTop = conversationList.scrollTop;
  const activity = new Map();
  for (const message of campusMessages) {
    const outgoing = message.sender_type === 'student'
      && String(message.sender_id) === String(currentStudent?.student_id);
    const key = message.is_broadcast ? 'broadcast:all-students' : contactKey({
      type: outgoing ? message.recipient_type : message.sender_type,
      id: outgoing ? message.recipient_id : message.sender_id,
    });
    const entry = activity.get(key) || { latest: null, unread: 0 };
    if (!entry.latest || messageTimestamp(message) >= messageTimestamp(entry.latest)) entry.latest = message;
    if (!message.read && !outgoing) entry.unread += 1;
    activity.set(key, entry);
  }
  const visible = conversationContacts().filter((contact) => {
    const isStudent = contact.type === 'student';
    const major = contact.major || contact.subtitle?.split('·').at(-1) || '';
    const sameMajor = isStudent
      && major.trim().toLowerCase() === currentStudent?.major?.trim().toLowerCase();
    const matchesQuery = `${contact.name} ${contact.id} ${contact.subtitle}`
      .toLowerCase().includes(query);
    const exactStudentId = isStudent && String(contact.id).toLowerCase() === query;
    const hasHistory = activity.has(contactKey(contact));
    // Search is for starting a new chat; it must never hide an incoming sender.
    if (hasHistory) return true;
    if (selectedMessageContact && contactKey(selectedMessageContact) === contactKey(contact)) return true;
    if (messageListMode === 'chats' && !query) return false;
    return isStudent ? exactStudentId || (sameMajor && matchesQuery) : matchesQuery;
  });
  visible.sort((left, right) => {
    const leftLatest = activity.get(contactKey(left))?.latest;
    const rightLatest = activity.get(contactKey(right))?.latest;
    return Number(Boolean(rightLatest)) - Number(Boolean(leftLatest))
      || messageTimestamp(rightLatest) - messageTimestamp(leftLatest)
      || left.name.localeCompare(right.name)
      || contactKey(left).localeCompare(contactKey(right));
  });

  const signature = JSON.stringify([messageListMode, Boolean(query),
    selectedMessageContact && contactKey(selectedMessageContact), visible.map((contact) => {
      const { latest, unread } = activity.get(contactKey(contact)) || {};
      return [contactKey(contact), contact.name, contact.subtitle, unread, latest?.message_id,
        latest?.body, latest?.attachment?.filename, latest?.created_at];
    })]);
  if (signature === renderedConversationListSignature) return;
  renderedConversationListSignature = signature;

  conversationList.replaceChildren();
  if (visible.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'conversation-list-empty';
    empty.textContent = query
      ? 'No classmate matches. Enter a registered student’s full ID to start a chat.'
      : messageListMode === 'chats'
        ? 'Your chats will appear here automatically when someone messages you. Choose New message to start a chat.'
        : 'No classmates in your major are available yet.';
    conversationList.append(empty);
    return;
  }

  let section = '';
  for (const contact of visible) {
    const { latest, unread = 0 } = activity.get(contactKey(contact)) || {};
    const nextSection = latest ? 'Recent chats' : query ? 'Search results' : 'Classmates & professors';
    if (section !== nextSection) {
      section = nextSection;
      const heading = document.createElement('h5');
      heading.className = 'conversation-list-heading';
      heading.textContent = section;
      conversationList.append(heading);
    }
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `conversation-item${unread ? ' unread' : ''}${selectedMessageContact && contactKey(selectedMessageContact) === contactKey(contact) ? ' active' : ''}`;
    button.dataset.contactKey = contactKey(contact);
    button.setAttribute('aria-pressed', String(Boolean(selectedMessageContact && contactKey(selectedMessageContact) === contactKey(contact))));
    button.setAttribute('aria-label', `${contact.name}${unread ? `, ${unread} unread messages` : ''}`);
    button.addEventListener('click', () => selectMessageConversation(contact));
    const avatar = document.createElement('span');
    avatar.className = `conversation-avatar ${contact.type}`;
    avatar.textContent = contact.type === 'broadcast'
      ? 'ALL'
      : contact.name.split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase();
    const copy = document.createElement('span');
    copy.className = 'conversation-copy';
    const top = document.createElement('span');
    top.className = 'conversation-name-row';
    const name = document.createElement('strong');
    name.textContent = contact.name;
    top.append(name);
    if (latest) {
      const time = document.createElement('time');
      time.textContent = formatMessageTime(latest.created_at);
      top.append(time);
    }
    const preview = document.createElement('span');
    preview.className = 'conversation-preview';
    const previewText = latest?.body || latest?.attachment?.filename || contact.subtitle;
    preview.textContent = latest && isOutgoingMessage(latest) ? `You: ${previewText}` : previewText;
    copy.append(top, preview);
    button.append(avatar, copy);
    if (unread > 0) {
      const badge = document.createElement('span');
      badge.className = 'conversation-unread';
      badge.textContent = String(unread);
      button.append(badge);
    }
    conversationList.append(button);
  }
  if (previousTopContact === conversationList.querySelector('.conversation-item')?.dataset.contactKey) {
    conversationList.scrollTop = previousScrollTop;
  } else {
    conversationList.scrollTop = 0;
  }
}


function isMessageThreadAtBottom() {
  return messageThread.scrollHeight - messageThread.scrollTop - messageThread.clientHeight < 60;
}


function renderMessageThread(forceScroll = false) {
  if (!selectedMessageContact) return;
  const thread = messagesForContact(selectedMessageContact).sort((left, right) =>
    messageTimestamp(left) - messageTimestamp(right)
      || String(left.message_id).localeCompare(String(right.message_id)));
  conversationTitle.textContent = selectedMessageContact.name;
  conversationSubtitle.textContent = selectedMessageContact.subtitle;
  messageComposeForm.hidden = selectedMessageContact.type === 'broadcast';
  const key = contactKey(selectedMessageContact);
  const signature = JSON.stringify(thread.map((item) => [item.message_id, item.body, item.attachment, item.created_at]));
  if (key === renderedMessageThreadKey && signature === renderedMessageThreadSignature) {
    if (forceScroll) {
      messageThread.scrollTop = messageThread.scrollHeight;
      messageJumpLatest.hidden = true;
    }
    return;
  }
  const scrollToBottom = forceScroll || key !== renderedMessageThreadKey || isMessageThreadAtBottom();
  const oldScrollTop = messageThread.scrollTop;
  renderedMessageThreadKey = key;
  renderedMessageThreadSignature = signature;
  messageThread.replaceChildren();
  if (thread.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'message-thread-empty';
    empty.innerHTML = '<strong>No messages yet</strong><span>Say hello and start the conversation.</span>';
    messageThread.append(empty);
    return;
  }
  for (const item of thread) {
    const outgoing = isOutgoingMessage(item);
    const bubble = document.createElement('article');
    bubble.className = `campus-message ${outgoing ? 'outgoing' : 'incoming'}${item.is_broadcast ? ' broadcast' : ''}`;
    const meta = document.createElement('div');
    meta.className = 'campus-message-meta';
    const sender = document.createElement('strong');
    sender.textContent = outgoing ? 'You' : item.sender_name;
    const time = document.createElement('time');
    time.textContent = formatMessageTime(item.created_at);
    meta.append(sender, time);
    const body = document.createElement('p');
    body.textContent = item.body;
    bubble.append(meta, body);
    if (item.attachment) {
      const documentButton = document.createElement('button');
      documentButton.type = 'button';
      documentButton.className = 'message-document';
      documentButton.textContent = `↓ ${item.attachment.filename} · ${formatDocumentSize(item.attachment.size_bytes)}`;
      documentButton.setAttribute('aria-label', `Download ${item.attachment.filename}`);
      documentButton.addEventListener('click', () => downloadMessageDocument(item, documentButton));
      bubble.append(documentButton);
    }
    messageThread.append(bubble);
  }
  messageThread.scrollTop = scrollToBottom ? messageThread.scrollHeight : oldScrollTop;
  messageJumpLatest.hidden = scrollToBottom;
}


async function markSelectedConversationRead() {
  if (!currentStudent || !selectedMessageContact || messagesPanel.hidden
      || document.visibilityState !== 'visible' || !isMessageThreadAtBottom()) return;
  const actorId = currentStudent.student_id;
  const generation = messageSyncGeneration;
  const unreadIds = messagesForContact(selectedMessageContact)
    .filter((message) => !message.read && !isOutgoingMessage(message))
    .map((message) => message.message_id);
  if (unreadIds.length === 0) return;
  const unreadSet = new Set(unreadIds);
  for (const id of unreadIds) pendingMessageReads.add(id);
  campusMessages = campusMessages.map((message) =>
    unreadSet.has(message.message_id) ? { ...message, read: true } : message);
  renderConversationList();
  updateInboxBadge();
  try {
    await academicApiRequest('/messages/read', {
      method: 'PUT',
      body: JSON.stringify({
        actor_type: 'student',
        actor_id: actorId,
        message_ids: unreadIds,
      }),
    });
  } catch (_error) {
    if (generation !== messageSyncGeneration) return;
    for (const id of unreadIds) pendingMessageReads.delete(id);
    campusMessages = campusMessages.map((message) =>
      unreadSet.has(message.message_id) ? { ...message, read: false } : message);
    renderConversationList();
    updateInboxBadge();
  }
}


function selectMessageConversation(contact) {
  if (messageSending) return;
  if (!selectedMessageContact || contactKey(contact) !== contactKey(selectedMessageContact)) {
    clearMessageAttachment();
    messageComposeInput.value = '';
    setMessage(messageStatus, '');
  }
  selectedMessageContact = contact;
  cancelMessageStudentLookup();
  messageSearch.value = '';
  messageJumpLatest.hidden = true;
  renderConversationList();
  renderMessageThread(true);
  markSelectedConversationRead();
  if (contact.type !== 'broadcast') messageComposeInput.focus();
}


function openStudentConversationById() {
  const enteredId = messageSearch.value.trim().toLowerCase();
  if (!enteredId || !currentStudent || messageSending) return;
  if (enteredId === String(currentStudent.student_id).toLowerCase()) {
    setMessage(messageSearchStatus, 'This is your own student ID. Enter another student’s ID.', true);
    return;
  }
  const exactMatch = conversationContacts().find((contact) =>
    contact.type === 'student' && String(contact.id).toLowerCase() === enteredId);
  if (exactMatch) {
    cancelMessageStudentLookup();
    if (!selectedMessageContact || contactKey(selectedMessageContact) !== contactKey(exactMatch)) {
      selectMessageConversation(exactMatch);
    }
    return;
  }
  if (!/^\d{6,64}$/.test(enteredId) || messageStudentLookupId === enteredId) return;
  cancelMessageStudentLookup();
  messageStudentLookupId = enteredId;
  const sequence = messageStudentLookupSequence;
  const actorId = currentStudent.student_id;
  setMessage(messageSearchStatus, 'Looking up student…');
  messageStudentLookupTimer = setTimeout(async () => {
    const stillCurrent = () => sequence === messageStudentLookupSequence
      && currentStudent?.student_id === actorId
      && messageSearch.value.trim().toLowerCase() === enteredId;
    try {
      const student = await academicApiRequest(`/student/${encodeURIComponent(enteredId)}`);
      if (!stillCurrent()) return;
      const contact = {
        type: 'student', id: String(student.student_id), name: student.name,
        major: student.major, subtitle: `Year ${student.year} · ${student.major}`,
      };
      lookedUpMessageContacts.set(contactKey(contact), contact);
      if (!messageContacts.some((item) => contactKey(item) === contactKey(contact))) {
        messageContacts.push(contact);
      }
      setMessage(messageSearchStatus, '');
      selectMessageConversation(contact);
    } catch (error) {
      if (!stillCurrent()) return;
      setMessage(messageSearchStatus, error.status === 404
        ? `No registered student has ID ${enteredId}. Check the digits and try again.`
        : `Student lookup failed: ${error.message}`, true);
    }
  }, 350);
}


function cancelMessageStudentLookup() {
  clearTimeout(messageStudentLookupTimer);
  messageStudentLookupTimer = null;
  messageStudentLookupSequence += 1;
  messageStudentLookupId = null;
  setMessage(messageSearchStatus, '');
}


async function refreshMessages(showErrors = false) {
  if (!currentStudent) return;
  showErrors = showErrors === true;
  if (messageRefreshTask?.generation === messageSyncGeneration) return messageRefreshTask.promise;
  const actorId = currentStudent.student_id;
  const generation = messageSyncGeneration;
  const isCurrent = () => generation === messageSyncGeneration && currentStudent?.student_id === actorId;
  const existingIds = new Set(campusMessages.map((message) => message.message_id));
  const task = { generation, promise: null };
  messageRefreshTask = task;
  task.promise = (async () => {
    const params = new URLSearchParams({ actor_type: 'student', actor_id: actorId });
    const loadDirectory = !messageDirectoryUpdatedAt || Date.now() - messageDirectoryUpdatedAt >= MESSAGE_DIRECTORY_POLL_MS;
    const [contactsResult, messagesResult] = await Promise.allSettled([
      loadDirectory ? academicApiRequest(`/messages/contacts?${params}`, { signal: AbortSignal.timeout(12000) }).then((response) => {
        if (!isCurrent()) return;
        const merged = new Map(lookedUpMessageContacts);
        for (const contact of response.contacts || []) merged.set(contactKey(contact), contact);
        messageContacts = [...merged.values()];
        messageDirectoryUpdatedAt = Date.now();
        if (selectedMessageContact && selectedMessageContact.type !== 'broadcast') {
          selectedMessageContact = merged.get(contactKey(selectedMessageContact)) || selectedMessageContact;
        }
        renderConversationList();
        if (!selectedMessageContact) openStudentConversationById();
      }) : Promise.resolve(),
      academicApiRequest(`/messages?${params}`, { signal: AbortSignal.timeout(12000) }).then((response) => {
        if (!isCurrent()) return;
        if (!Array.isArray(response.messages)) throw new Error('The message service returned an invalid inbox. Please restart the backend.');
        const receivedIds = new Set(response.messages.map((message) => message.message_id));
        const addedDuringSync = campusMessages.filter((message) => !existingIds.has(message.message_id) && !receivedIds.has(message.message_id));
        campusMessages = [...response.messages, ...addedDuringSync].map((message) => {
          if (message.read) pendingMessageReads.delete(message.message_id);
          return pendingMessageReads.has(message.message_id) ? { ...message, read: true } : message;
        });
        renderConversationList();
        if (selectedMessageContact) {
          renderMessageThread();
          markSelectedConversationRead();
        }
        updateInboxBadge();
      }),
    ]);
    if (!isCurrent()) return;
    const inboxFailed = messagesResult.status === 'rejected';
    setMessage(messageSyncStatus, inboxFailed
      ? `Messages could not sync: ${messagesResult.reason.message} Retrying automatically…`
      : contactsResult.status === 'rejected'
        ? 'Chats are up to date · Classmate directory is reconnecting…'
        : 'Chats are up to date · Updates automatically', inboxFailed);
    if (showErrors) {
      const failure = [contactsResult, messagesResult].find((result) => result.status === 'rejected');
      setMessage(messageStatus, failure ? failure.reason.message : '', Boolean(failure));
    }
  })().finally(() => {
    if (!isCurrent()) return;
    if (messageRefreshTask === task) messageRefreshTask = null;
    scheduleMessageSync();
  });
  return task.promise;
}


function scheduleMessageSync() {
  clearTimeout(messageTimer);
  if (!currentStudent) return;
  const active = !messagesPanel.hidden && document.visibilityState === 'visible';
  messageTimer = setTimeout(() => refreshMessages(), active ? MESSAGE_ACTIVE_POLL_MS : MESSAGE_POLL_MS);
}


function startMessageSync() {
  stopMessageSync();
  messageContacts = [];
  campusMessages = [];
  selectedMessageContact = null;
  renderedMessageThreadKey = null;
  renderedMessageThreadSignature = '';
  messageDirectoryUpdatedAt = 0;
  messageJumpLatest.hidden = true;
  clearMessageAttachment();
  messageComposeInput.value = '';
  messageComposeForm.hidden = true;
  conversationTitle.textContent = 'Choose a conversation';
  conversationSubtitle.textContent = 'Your classmates and professors are here.';
  messageThread.replaceChildren();
  const empty = document.createElement('div');
  empty.className = 'message-thread-empty';
  empty.innerHTML = '<strong>Start a conversation</strong><span>Select someone from the inbox to view or send messages.</span>';
  messageThread.append(empty);
  setMessage(messageStatus, '');
  messageSearch.value = '';
  setMessageListMode('chats');
  setMessage(messageSyncStatus, 'Connecting to your chats…');
  updateInboxBadge();
  refreshMessages();
}


function stopMessageSync() {
  messageSyncGeneration += 1;
  messageRefreshTask = null;
  pendingMessageReads.clear();
  if (messageTimer) {
    clearTimeout(messageTimer);
    messageTimer = null;
  }
  cancelMessageStudentLookup();
  lookedUpMessageContacts.clear();
  clearMessageAttachment();
}


function formatDocumentSize(bytes) {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.ceil(bytes / 1024))} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}


function clearMessageAttachment() {
  selectedMessageFile = null;
  messageAttachmentInput.value = '';
  messageAttachmentPreview.hidden = true;
  messageAttachmentName.textContent = '';
  messageComposeInput.required = true;
}


messageAttachButton.addEventListener('click', () => {
  if (!messageSending) messageAttachmentInput.click();
});
messageAttachmentRemove.addEventListener('click', () => {
  clearMessageAttachment();
  setMessage(messageStatus, '');
  messageAttachButton.focus();
});
messageAttachmentInput.addEventListener('change', () => {
  const file = messageAttachmentInput.files[0];
  if (!file) return;
  const extension = file.name.split('.').at(-1).toLowerCase();
  let error = '';
  if (!MESSAGE_DOCUMENT_EXTENSIONS.has(extension)) error = 'Choose a PDF, Word, spreadsheet, presentation, or text document.';
  else if (!file.size) error = 'The selected document is empty.';
  else if (file.size > MESSAGE_DOCUMENT_MAX_BYTES) error = 'Documents must be 10 MB or smaller.';
  if (error) {
    clearMessageAttachment();
    setMessage(messageStatus, error, true);
    return;
  }
  selectedMessageFile = file;
  messageAttachmentName.textContent = `${file.name} · ${formatDocumentSize(file.size)}`;
  messageAttachmentPreview.hidden = false;
  messageComposeInput.required = false;
  setMessage(messageStatus, '');
});


async function downloadMessageDocument(item, button) {
  if (!currentStudent) return;
  const studentId = currentStudent.student_id;
  button.disabled = true;
  try {
    const params = new URLSearchParams({ actor_type: 'student', actor_id: studentId });
    const response = await fetch(`${academicApiBaseUrl}/messages/${encodeURIComponent(item.message_id)}/attachment?${params}`);
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.detail || 'The document could not be downloaded.');
    }
    const blobUrl = URL.createObjectURL(await response.blob());
    const link = document.createElement('a');
    link.href = blobUrl;
    link.download = item.attachment.filename;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    setMessage(messageStatus, 'Document downloaded.');
  } catch (error) {
    setMessage(messageStatus, error.message, true);
  } finally {
    button.disabled = false;
  }
}


inboxButton.addEventListener('click', () => showDashboardSection('messages'));
messageChatsTab.addEventListener('click', () => {
  cancelMessageStudentLookup();
  messageSearch.value = '';
  setMessageListMode('chats');
  conversationList.scrollTop = 0;
});
messageContactsTab.addEventListener('click', () => setMessageListMode('contacts'));
messageJumpLatest.addEventListener('click', () => {
  messageThread.scrollTop = messageThread.scrollHeight;
  messageJumpLatest.hidden = true;
  markSelectedConversationRead();
});
messageThread.addEventListener('scroll', () => {
  if (isMessageThreadAtBottom()) {
    messageJumpLatest.hidden = true;
    markSelectedConversationRead();
  }
});
document.querySelector('#new-message-button').addEventListener('click', () => {
  if (messageSending) return;
  cancelMessageStudentLookup();
  selectedMessageContact = null;
  renderedMessageThreadKey = null;
  messageJumpLatest.hidden = true;
  clearMessageAttachment();
  messageComposeInput.value = '';
  messageComposeForm.hidden = true;
  conversationTitle.textContent = 'Choose a conversation';
  conversationSubtitle.textContent = 'Search classmates in your major or enter any student’s full ID.';
  messageThread.replaceChildren();
  const empty = document.createElement('div');
  empty.className = 'message-thread-empty';
  empty.innerHTML = '<strong>Start a conversation</strong><span>Choose a classmate or search any registered student by ID.</span>';
  messageThread.append(empty);
  messageSearch.value = '';
  setMessage(messageStatus, '');
  setMessageListMode('contacts');
  messageSearch.focus();
});
messageSearch.addEventListener('input', () => {
  cancelMessageStudentLookup();
  renderConversationList();
  openStudentConversationById();
});
messageComposeInput.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  if (!messageSending) messageComposeForm.requestSubmit();
});
messageComposeForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!currentStudent || !selectedMessageContact || selectedMessageContact.type === 'broadcast') return;
  const body = messageComposeInput.value.trim();
  if ((!body && !selectedMessageFile) || messageSending) return;
  const senderId = currentStudent.student_id;
  const generation = messageSyncGeneration;
  const recipient = { ...selectedMessageContact };
  const file = selectedMessageFile;
  messageSending = true;
  messageSendButton.disabled = true;
  messageAttachButton.disabled = true;
  messageAttachmentRemove.disabled = true;
  messageComposeInput.disabled = true;
  setMessage(messageStatus, file ? 'Sending document…' : 'Sending…');
  try {
    let sent;
    if (file) {
      const formData = new FormData();
      formData.append('sender_type', 'student');
      formData.append('sender_id', senderId);
      formData.append('recipient_type', recipient.type);
      formData.append('recipient_id', recipient.id);
      formData.append('body', body);
      formData.append('file', file);
      sent = await academicApiRequest('/messages/attachments', { method: 'POST', body: formData });
    } else {
      sent = await academicApiRequest('/messages', {
        method: 'POST',
        body: JSON.stringify({
          sender_type: 'student',
          sender_id: senderId,
          recipient_type: recipient.type,
          recipient_id: recipient.id,
          body,
        }),
      });
    }
    if (currentStudent?.student_id !== senderId || messageSyncGeneration !== generation) return;
    if (sent.message) {
      campusMessages = [...campusMessages.filter((message) => message.message_id !== sent.message.message_id), sent.message];
    }
    cancelMessageStudentLookup();
    messageSearch.value = '';
    messageComposeInput.value = '';
    clearMessageAttachment();
    renderConversationList();
    renderMessageThread(true);
    setMessage(messageStatus, '');
    refreshMessages();
  } catch (error) {
    if (currentStudent?.student_id === senderId && messageSyncGeneration === generation) setMessage(messageStatus, error.message, true);
  } finally {
    messageSending = false;
    messageSendButton.disabled = false;
    messageAttachButton.disabled = false;
    messageAttachmentRemove.disabled = false;
    messageComposeInput.disabled = false;
    if (currentStudent?.student_id === senderId && messageSyncGeneration === generation) messageComposeInput.focus();
  }
});


window.addEventListener('focus', refreshMessages);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshMessages();
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
  closeScorePanel();
  document.querySelector('#score-value').textContent = '—';
  currentTwin = null;
  progressState = 'loading';
  calendarCustomEvents = loadCalendarEvents(student.student_id);
  calendarSelectedDate = new Date();
  calendarMonth = new Date(calendarSelectedDate.getFullYear(), calendarSelectedDate.getMonth(), 1);
  document.querySelector('#welcome-title').textContent = `${student.name} · Year ${student.year}`;
  document.querySelector('#workspace-greeting').textContent = `Welcome, ${student.name}`;
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
  document.body.classList.add('is-authenticated');
  showDashboardSection('workspace');
  renderCalendar();
  resetAdvisor();
  loadProgress(student.student_id);
  loadScores(student.student_id);
  startNotificationSync();
  startMessageSync();

  if (student.courses.length > 0) {
    selectCourse(student.courses[0]);
  } else {
    selectedCourse = null;
    setMessage(actionStatus, 'No enrolled courses are available.');
    renderWorkspaceOverview();
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

document.querySelector('#course-progress-button').addEventListener('click', () => showDashboardSection('progress'));
document.querySelector('#workspace-calendar-button').addEventListener('click', () => showDashboardSection('calendar'));
document.querySelector('#upcoming-calendar-button').addEventListener('click', () => showDashboardSection('calendar'));
document.querySelector('#workspace-advisor-button').addEventListener('click', () => {
  showDashboardSection('advisor');
  if (!advisorInput.value.trim() && selectedCourse) {
    advisorInput.value = `Help me plan my next steps in ${selectedCourse}.`;
  }
  advisorInput.focus();
});
advisorBackButton.addEventListener('click', () => {
  showDashboardSection('workspace');
  workspaceTab.focus();
});


workspaceTab.addEventListener('click', () => showDashboardSection('workspace'));
advisorTab.addEventListener('click', () => showDashboardSection('advisor'));
progressTab.addEventListener('click', () => showDashboardSection('progress'));
calendarTab.addEventListener('click', () => showDashboardSection('calendar'));

document.querySelector('#calendar-previous-button').addEventListener('click', () => {
  calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() - 1, 1);
  renderCalendar();
});

document.querySelector('#calendar-next-button').addEventListener('click', () => {
  calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 1);
  renderCalendar();
});

document.querySelector('#calendar-today-button').addEventListener('click', () => {
  calendarSelectedDate = new Date();
  calendarMonth = new Date(calendarSelectedDate.getFullYear(), calendarSelectedDate.getMonth(), 1);
  renderCalendar();
});

document.querySelector('#calendar-add-button').addEventListener('click', () => openCalendarModal());
document.querySelector('#calendar-day-add-button').addEventListener('click', () => openCalendarModal());
document.querySelector('#calendar-modal-close').addEventListener('click', closeCalendarModal);
document.querySelector('#calendar-cancel-button').addEventListener('click', closeCalendarModal);
document.querySelector('#calendar-modal-overlay').addEventListener('click', closeCalendarModal);

document.querySelector('#calendar-ai-button').addEventListener('click', () => {
  if (!currentTwin) {
    showToasts([{ type: 'study', title: 'Academic data is loading', body: 'Try planning again after semester progress has loaded.' }]);
    return;
  }
  const added = scheduleUrgentStudySessions();
  renderCalendar();
  showToasts([{
    type: 'study',
    title: added.length > 0 ? 'AI study plan updated' : 'Study plan is up to date',
    body: added.length > 0
      ? `${added.length} urgent study ${added.length === 1 ? 'session was' : 'sessions were'} added.`
      : 'No new urgent sessions are needed right now.',
  }]);
});

calendarEventForm.addEventListener('submit', (event) => {
  event.preventDefault();
  if (!currentStudent) return;
  const title = calendarEventTitle.value.trim();
  const dateParts = calendarEventDate.value.split('-').map(Number);
  const timeParts = calendarEventTime.value.split(':').map(Number);
  if (!title || dateParts.length !== 3 || timeParts.length !== 2 || dateParts.some(Number.isNaN) || timeParts.some(Number.isNaN)) {
    setMessage(calendarFormStatus, 'Enter a title, date, and start time.', true);
    return;
  }
  const start = new Date(dateParts[0], dateParts[1] - 1, dateParts[2], timeParts[0], timeParts[1]);
  const durationMinutes = Number(calendarEventDuration.value);
  const eventType = calendarEventType.value;
  calendarCustomEvents.push({
    id: `student:${Date.now()}:${Math.random().toString(36).slice(2)}`,
    title,
    description: calendarEventDescription.value.trim(),
    startAt: start.toISOString(),
    endAt: new Date(start.getTime() + durationMinutes * 60000).toISOString(),
    type: eventType,
    source: 'student',
  });
  calendarSelectedDate = start;
  calendarMonth = new Date(start.getFullYear(), start.getMonth(), 1);
  saveCalendarEvents();
  closeCalendarModal();
  renderCalendar();
  showToasts([{ type: eventType, title: 'Calendar updated', body: `${title} was added to your calendar.` }]);
});


advisorForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!currentStudent) return;

  const message = advisorInput.value.trim();
  if (!message) return;

  const priorHistory = advisorHistory.slice(-10);
  advisorHistory.push({ role: 'user', content: message });
  addAdvisorMessage('user', message);
  advisorInput.value = '';
  resizeAdvisorInput();
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

advisorInput.addEventListener('input', resizeAdvisorInput);
resizeAdvisorInput();


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
  scoreRequestId += 1;
  closeScorePanel();
  stopNotificationSync();
  stopMessageSync();
  notifications = [];
  messageContacts = [];
  campusMessages = [];
  selectedMessageContact = null;
  toastContainer.replaceChildren();
  notifPanel.hidden = true;
  notifButton.setAttribute('aria-expanded', 'false');
  currentStudent = null;
  selectedCourse = null;
  currentTwin = null;
  progressState = 'loading';
  calendarCustomEvents = [];
  calendarSelectedDate = new Date();
  calendarMonth = new Date(calendarSelectedDate.getFullYear(), calendarSelectedDate.getMonth(), 1);
  closeCalendarModal();
  advisorHistory = [];
  advisorMessages.replaceChildren();
  dashboardView.hidden = true;
  loginView.hidden = false;
  document.body.classList.remove('is-authenticated');
  setMessage(actionStatus, '');
  setMessage(advisorStatus, '');
  studentIdInput.focus();
});

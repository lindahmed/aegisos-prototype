(() => {
  const launcher = document.querySelector('#notes-launcher');
  const panel = document.querySelector('#workspace-notes');
  const list = document.querySelector('#notes-list');
  const count = document.querySelector('#notes-count');
  const empty = document.querySelector('#notes-empty');
  const fields = document.querySelector('#note-fields');
  const title = document.querySelector('#note-title');
  const body = document.querySelector('#note-body');
  const status = document.querySelector('#note-save-status');
  let studentId = null;
  let notes = [];
  let selectedId = null;
  let saveTimer;

  const storageKey = (id) => `aegisos:student-notes:${id}`;
  const selectedNote = () => notes.find((note) => note.id === selectedId) || null;

  function persist() {
    if (!studentId) return;
    localStorage.setItem(storageKey(studentId), JSON.stringify(notes));
    status.textContent = 'Saved automatically';
  }

  function renderList() {
    list.replaceChildren();
    count.textContent = String(notes.length);
    for (const note of notes) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `note-list-item${note.id === selectedId ? ' is-selected' : ''}`;
      const heading = document.createElement('strong');
      heading.textContent = note.title || 'Untitled note';
      const preview = document.createElement('span');
      preview.textContent = note.body || 'No text yet';
      button.append(heading, preview);
      button.addEventListener('click', () => selectNote(note.id));
      list.append(button);
    }
  }

  function selectNote(id) {
    selectedId = id;
    const note = selectedNote();
    empty.hidden = Boolean(note);
    fields.hidden = !note;
    if (note) {
      title.value = note.title;
      body.value = note.body;
      status.textContent = 'Saved automatically';
    }
    renderList();
  }

  function loadStudentNotes(id) {
    if (!id || id === studentId) return;
    studentId = id;
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey(id)) || '[]');
      notes = Array.isArray(saved) ? saved.filter((note) => note && typeof note.id === 'string' && typeof note.title === 'string' && typeof note.body === 'string') : [];
    } catch {
      notes = [];
    }
    selectedId = notes[0]?.id || null;
    selectNote(selectedId);
  }

  function currentId() {
    return typeof currentStudent !== 'undefined' ? currentStudent?.student_id : null;
  }

  const welcomeTitle = document.querySelector('#welcome-title');
  new MutationObserver(() => {
    launcher.hidden = !currentId();
    if (!currentId()) closePanel();
  }).observe(welcomeTitle, { childList: true, characterData: true, subtree: true });

  launcher.addEventListener('click', () => {
    const id = currentId();
    if (!id) return;
    loadStudentNotes(id);
    if (typeof showDashboardSection === 'function') showDashboardSection('workspace');
    panel.hidden = !panel.hidden;
    launcher.setAttribute('aria-expanded', String(!panel.hidden));
    if (!panel.hidden) {
      if (!selectedId) document.querySelector('#new-note-button').click();
      body.focus({ preventScroll: true });
    }
  });

  function closePanel() {
    panel.hidden = true;
    launcher.setAttribute('aria-expanded', 'false');
  }
  document.querySelector('#close-notes-button').addEventListener('click', closePanel);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !panel.hidden) closePanel();
  });

  document.querySelector('#new-note-button').addEventListener('click', () => {
    const id = currentId();
    if (!id) return;
    loadStudentNotes(id);
    const note = { id: globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`, title: 'New Note', body: '', updatedAt: Date.now() };
    notes.unshift(note);
    selectedId = note.id;
    persist();
    selectNote(selectedId);
    title.focus();
    title.select();
  });

  for (const [key, input] of [['title', title], ['body', body]]) {
    input.addEventListener('input', () => {
      const note = selectedNote();
      if (!note) return;
      note[key] = input.value;
      note.updatedAt = Date.now();
      status.textContent = 'Saving…';
      renderList();
      clearTimeout(saveTimer);
      saveTimer = setTimeout(persist, 180);
    });
  }

  document.querySelector('#delete-note-button').addEventListener('click', () => {
    if (!selectedId) return;
    notes = notes.filter((note) => note.id !== selectedId);
    selectedId = notes[0]?.id || null;
    persist();
    selectNote(selectedId);
  });
})();

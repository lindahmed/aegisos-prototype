/* global RTCPeerConnection, MediaStream */
'use strict';
(() => {
  const api = window.aegis.meetings;
  const $ = (id) => document.getElementById(`meeting-${id}`);
  const LANES = ['audio', 'camera', 'screen'];
  let state = null;
  let selfId = null;
  let rtc = null;
  let active = false;
  let connecting = false;
  let epoch = 0;
  let pending = [];
  let boardVisible = false;
  let strokes = [];
  let drawing = null;
  const tracks = new Map();
  const peers = new Map();
  const tiles = new Map();
  const mediaBusy = new Set();
  const canvas = $('canvas');
  const context = canvas.getContext('2d');
  const me = () => state?.members.find((m) => m.id === selfId);
  const member = (id) => state?.members.find((m) => m.id === id);
  function status(message, error = false) {
    $('status').textContent = message;
    $('status').classList.toggle('error', error);
  }
  async function send(message) {
    if (!active) return;
    await api.send(message);
  }
  function action(message) { void send(message).catch((error) => status(error.message, true)); }
  function allowed(m, lane) {
    return Boolean(m?.admitted && (lane === 'audio' ? m.canSpeak && m.mic : lane === 'screen' ? m.canShare && m.screen : m.camera));
  }
  function tile(id, lane) {
    const key = `${id}:${lane}`;
    if (tiles.has(key)) return tiles.get(key);
    const media = document.createElement(lane === 'audio' ? 'audio' : 'video');
    media.autoplay = true;
    media.playsInline = true;
    media.muted = lane !== 'audio' || id === selfId;
    let frame;
    let caption;
    if (lane !== 'audio') {
      frame = document.createElement('figure');
      frame.className = 'meeting-tile';
      frame.hidden = true;
      caption = document.createElement('figcaption');
      frame.append(media, caption);
      $(lane === 'screen' ? 'screens' : 'videos').append(frame);
    } else {
      // Audio elements remain in the DOM so mute controls can be applied per sender.
      media.hidden = true;
      $('room').append(media);
    }
    const value = { media, frame, caption };
    tiles.set(key, value);
    return value;
  }
  function refreshMedia() {
    let visible = false;
    for (const [key, view] of tiles) {
      const [id, lane] = key.split(':');
      const m = member(id);
      const enabled = allowed(m, lane);
      if (view.frame) {
        view.frame.hidden = !enabled;
        view.caption.textContent = `${m?.name || 'Participant'}${id === selfId ? ' (you)' : ''}${lane === 'screen' ? ' · screen' : ''}`;
        if (enabled) visible = true;
      } else view.media.muted = !enabled;
      for (const track of view.media.srcObject?.getTracks() || []) track.enabled = enabled;
    }
    $('stage-empty').hidden = visible || boardVisible;
  }
  function setControlIcon(buttonId, icon, label) {
    const control = $(buttonId);
    control.textContent = icon;
    control.setAttribute('aria-label', label);
    control.title = label;
  }
  function controls() {
    const m = me();
    for (const [lane, buttonId, off, on, offIcon, onIcon] of [
      ['audio', 'mic', 'Unmute', 'Mute', '🔇', '🎤'],
      ['camera', 'camera', 'Camera on', 'Camera off', '📷', '📹'],
      ['screen', 'screen', 'Share screen', 'Stop sharing', '🖥️', '⏹️'],
    ]) {
      const enabled = tracks.has(lane);
      const permitted = m?.admitted && (lane === 'audio' ? m.canSpeak : lane === 'screen' ? m.canShare : true);
      $(buttonId).disabled = !permitted || mediaBusy.has(lane);
      setControlIcon(buttonId, enabled ? onIcon : offIcon, enabled ? on : off);
      $(buttonId).setAttribute('aria-pressed', String(enabled));
      if (!permitted) $(buttonId).title = `${enabled ? on : off} · Waiting for host permission`;
    }
    $('hand').disabled = !m?.admitted;
    setControlIcon('hand', m?.hand ? '👇' : '✋', m?.hand ? 'Lower hand' : 'Raise hand');
    $('hand').setAttribute('aria-pressed', String(Boolean(m?.hand)));
    $('board-toggle').disabled = !m?.admitted;
    setControlIcon('board-toggle', '📝', boardVisible ? 'Hide whiteboard' : 'Show whiteboard');
    $('board-toggle').setAttribute('aria-pressed', String(boardVisible));
    $('board').hidden = !boardVisible || !m?.admitted;
    $('mute-all').hidden = !m?.host;
    $('end').hidden = !m?.host;
    $('clear-board').hidden = !m?.host;
    $('pen-color').disabled = !m?.canShare;
    $('pen-width').disabled = !m?.canShare;
    canvas.setAttribute('aria-disabled', String(!m?.canShare));
    $('permissions').textContent = !m?.admitted ? 'Waiting for the host to approve your request. Your devices are off.' :
      `${m.host ? 'You are the host. ' : ''}${m.canSpeak ? 'You may unmute.' : 'Raise your hand to request speaking permission.'} ${m.canShare ? 'You may share a screen and draw.' : 'The host must allow presentation before you can share or draw.'}`;
  }
  function button(label, message, container, danger = false) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = `secondary-button${danger ? ' meeting-danger' : ''}`;
    b.textContent = label;
    b.addEventListener('click', () => action(message));
    container.append(b);
  }
  function renderMembers() {
    const list = $('members-list');
    const focused = document.activeElement;
    const focusKey = focused?.dataset.meetingAction;
    list.replaceChildren();
    for (const m of state?.members || []) {
      const row = document.createElement('div');
      row.className = 'meeting-member';
      const name = document.createElement('strong');
      name.textContent = `${m.hand ? '✋ ' : ''}${m.name}${m.id === selfId ? ' (you)' : ''}`;
      const detail = document.createElement('p');
      detail.textContent = m.host ? 'Host' : !m.admitted ? 'Waiting for approval' :
        `${m.mic ? 'Speaking' : 'Muted'} · ${m.canSpeak ? 'May speak' : 'Listen only'} · ${m.canShare ? 'May present' : 'View only'}`;
      row.append(name, detail);
      if (me()?.host && !m.host) {
        const actions = document.createElement('div');
        actions.className = 'meeting-member-controls';
        if (!m.admitted) {
          button('Admit', { type: 'admit', target: m.id }, actions);
          button('Decline', { type: 'reject', target: m.id }, actions, true);
        } else {
          button(m.canSpeak ? 'Revoke speaking' : 'Allow speaking', { type: 'permissions', target: m.id, canSpeak: !m.canSpeak }, actions);
          button(m.canShare ? 'Revoke presenting' : 'Allow presenting', { type: 'permissions', target: m.id, canShare: !m.canShare }, actions);
          button('Remove', { type: 'remove', target: m.id }, actions, true);
        }
        [...actions.children].forEach((b, index) => { b.dataset.meetingAction = `${m.id}:${index}`; });
        row.append(actions);
      }
      list.append(row);
    }
    if (focusKey) [...list.querySelectorAll('button')].find((b) => b.dataset.meetingAction === focusKey)?.focus();
  }
  async function stopLane(lane, announce = true) {
    const currentEpoch = epoch;
    const track = tracks.get(lane);
    tracks.delete(lane);
    if (track) { track.onended = null; track.stop(); }
    const preview = tiles.get(`${selfId}:${lane}`);
    if (preview) preview.media.srcObject = null;
    const replacements = [...peers.values()]
      .filter((peer) => peer.lane === lane && peer.sender && peer.pc.signalingState !== 'closed')
      .map((peer) => peer.sender.replaceTrack(null).catch(() => {}));
    if (announce && active && me()?.admitted) action({ type: 'media', [lane === 'audio' ? 'mic' : lane]: false });
    controls();
    await Promise.all(replacements);
    if (currentEpoch === epoch) controls();
  }
  function dropPeer(key) {
    const peer = peers.get(key);
    if (!peer) return;
    peer.pc.close();
    peers.delete(key);
    const view = tiles.get(key);
    if (view) { view.media.srcObject = null; (view.frame || view.media).remove(); tiles.delete(key); }
  }
  function createPeer(id, lane) {
    const key = `${id}:${lane}`;
    if (peers.has(key)) return peers.get(key);
    const pc = new RTCPeerConnection(rtc);
    const offerer = selfId < id;
    const transceiver = offerer ? pc.addTransceiver(lane === 'audio' ? 'audio' : 'video', { direction: 'sendrecv' }) : null;
    const peer = { id, lane, pc, sender: transceiver?.sender || null, candidates: [], chain: Promise.resolve() };
    peers.set(key, peer);
    // A deterministic offerer avoids simultaneous offers; each fixed lane is
    // negotiated once. Toggling devices uses replaceTrack without renegotiation.
    pc.onicecandidate = ({ candidate }) => {
      if (candidate && active) action({ type: 'signal', target: id, lane, data: { candidate: candidate.toJSON() } });
    };
    pc.ontrack = ({ track }) => {
      const view = tile(id, lane);
      view.media.srcObject = new MediaStream([track]);
      refreshMedia();
      void view.media.play().catch(() => status('Click a meeting control to enable media playback.', true));
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'failed') status(`Media connection to ${member(id)?.name || 'a participant'} failed. The host may need TURN configuration. Leave and rejoin to retry.`, true);
    };
    peer.chain = peer.chain.then(async () => {
      if (peer.sender) await peer.sender.replaceTrack(tracks.get(lane) || null);
      if (offerer && active && pc.signalingState !== 'closed') {
        await pc.setLocalDescription(await pc.createOffer());
        await send({ type: 'signal', target: id, lane, data: { description: pc.localDescription.toJSON() } });
      }
    }).catch((error) => { if (active) status(`Media setup failed: ${error.message}`, true); });
    return peer;
  }
  function syncPeers() {
    if (!rtc || !me()?.admitted) return;
    const ids = new Set(state.members.filter((m) => m.admitted && m.id !== selfId).map((m) => m.id));
    for (const [key, peer] of peers) if (!ids.has(peer.id)) dropPeer(key);
    for (const id of ids) for (const lane of LANES) createPeer(id, lane);
  }
  function receiveSignal(message) {
    if (!me()?.admitted || !member(message.from)?.admitted || !LANES.includes(message.lane)) return;
    const peer = createPeer(message.from, message.lane);
    peer.chain = peer.chain.then(async () => {
      if (!active || peer.pc.signalingState === 'closed') return;
      const { description, candidate } = message.data;
      if (description) {
        if (!['offer', 'answer'].includes(description.type)) throw new Error('Invalid media negotiation.');
        if (description.type === 'offer' && selfId < message.from) throw new Error('Unexpected media offer.');
        await peer.pc.setRemoteDescription(description);
        if (description.type === 'offer') {
          const transceiver = peer.pc.getTransceivers()[0];
          transceiver.direction = 'sendrecv';
          peer.sender = transceiver.sender;
          await peer.sender.replaceTrack(tracks.get(peer.lane) || null);
        }
        for (const queued of peer.candidates.splice(0)) await peer.pc.addIceCandidate(queued);
        if (description.type === 'offer') {
          await peer.pc.setLocalDescription(await peer.pc.createAnswer());
          await send({ type: 'signal', target: message.from, lane: message.lane, data: { description: peer.pc.localDescription.toJSON() } });
        }
      } else if (candidate) {
        if (peer.pc.remoteDescription) await peer.pc.addIceCandidate(candidate);
        else if (peer.candidates.length < 100) peer.candidates.push(candidate);
      }
    }).catch((error) => { if (active) status(`Media connection failed: ${error.message}`, true); });
  }
  function drawStroke(stroke) {
    context.strokeStyle = stroke.color;
    context.lineWidth = stroke.width;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.beginPath();
    stroke.points.forEach(([x, y], index) => {
      if (index === 0) context.moveTo(x * canvas.width, y * canvas.height);
      else context.lineTo(x * canvas.width, y * canvas.height);
    });
    context.stroke();
  }
  function redraw() {
    context.clearRect(0, 0, canvas.width, canvas.height);
    for (const stroke of strokes) drawStroke(stroke);
    if (drawing) drawStroke(drawing);
  }
  function onEvent(message) {
    if (connecting && !rtc) { pending.push(message); return; }
    if (!active) return;
    if (message.type === 'joined') selfId = message.id;
    else if (message.type === 'state') {
      state = message;
      selfId = message.selfId;
      $('heading').textContent = message.title;
      const m = me();
      for (const lane of LANES) {
        if (tracks.has(lane) && (!m?.admitted || (lane === 'audio' && !m.canSpeak) || (lane === 'screen' && !m.canShare))) void stopLane(lane);
      }
      if (!m?.canShare) {
        drawing = null;
        if ($('source-dialog').open) $('source-dialog').close();
      }
      $('connection').textContent = m?.admitted ? `${state.members.filter((p) => p.admitted).length} in meeting` : 'Waiting for approval';
      syncPeers();
      controls();
      renderMembers();
      refreshMedia();
    } else if (message.type === 'signal') receiveSignal(message);
    else if (message.type === 'board') { strokes = message.strokes; redraw(); }
    else if (message.type === 'stroke') { strokes.push(message.stroke); redraw(); }
    else if (message.type === 'error') status(message.message, true);
    else if (['ended', 'removed', 'disconnected'].includes(message.type)) {
      void leave().then(() => status(message.reason, message.type !== 'ended'));
    }
  }
  api.onEvent(onEvent);
  async function enter(host) {
    if (connecting || active) return;
    connecting = true;
    active = true;
    rtc = null;
    pending = [];
    const currentEpoch = ++epoch;
    $('lobby').querySelectorAll('button').forEach((b) => { b.disabled = true; });
    status(host ? 'Starting meeting…' : 'Connecting to the host…');
    try {
      const result = host ? await api.host($('title').value) : await api.join($('invitation').value);
      if (epoch !== currentEpoch) return;
      rtc = { iceServers: result.iceServers, iceTransportPolicy: result.iceTransportPolicy };
      connecting = false;
      $('lobby').hidden = true;
      $('room').hidden = false;
      $('invite-row').hidden = !host;
      $('share-invitation').value = result.invitation || '';
      $('connection').textContent = 'Connected';
      status(host ? 'Meeting started. Share the invitation, then approve join requests.' : 'Join request sent. Please wait for host approval.');
      for (const message of pending.splice(0)) onEvent(message);
      controls();
    } catch (error) {
      await leave();
      status(error.message, true);
    } finally {
      connecting = false;
      $('lobby').querySelectorAll('button').forEach((b) => { b.disabled = false; });
    }
  }
  async function leave() {
    epoch++;
    active = false;
    connecting = false;
    pending = [];
    for (const key of [...peers.keys()]) dropPeer(key);
    for (const track of tracks.values()) { track.onended = null; track.stop(); }
    tracks.clear();
    for (const view of tiles.values()) { view.media.srcObject = null; (view.frame || view.media).remove(); }
    tiles.clear();
    mediaBusy.clear();
    state = null;
    selfId = null;
    rtc = null;
    boardVisible = false;
    strokes = [];
    drawing = null;
    redraw();
    if ($('source-dialog').open) $('source-dialog').close();
    $('lobby').hidden = false;
    $('room').hidden = true;
    $('heading').textContent = 'Live meeting';
    $('connection').textContent = 'Ready';
    $('share-invitation').value = '';
    $('members-list').replaceChildren();
    await api.leave();
    status('Host a meeting or paste an invitation to request admission.');
  }
  async function toggleLane(lane, source = null) {
    if (mediaBusy.has(lane)) return;
    const m = me();
    if (!m?.admitted || (lane === 'audio' && !m.canSpeak) || (lane === 'screen' && !m.canShare)) return;
    if (tracks.has(lane)) return stopLane(lane);
    const currentEpoch = epoch;
    mediaBusy.add(lane);
    controls();
    let acquired;
    try {
      if (lane === 'screen') {
        if (!source) return;
        await api.selectSource(source);
        acquired = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false });
      } else acquired = await navigator.mediaDevices.getUserMedia(lane === 'audio' ?
        { audio: { echoCancellation: true, noiseSuppression: true }, video: false } :
        { video: { width: { ideal: 640 }, height: { ideal: 360 }, frameRate: { ideal: 20 } }, audio: false });
      if (epoch !== currentEpoch || !active || !me()?.admitted || (lane === 'audio' && !me().canSpeak) || (lane === 'screen' && !me().canShare)) {
        acquired.getTracks().forEach((track) => track.stop());
        return;
      }
      const track = acquired.getTracks()[0];
      tracks.set(lane, track);
      track.onended = () => { if (epoch === currentEpoch) void stopLane(lane); };
      await Promise.all([...peers.values()].filter((peer) => peer.lane === lane && peer.sender).map((peer) => peer.sender.replaceTrack(track)));
      if (lane !== 'audio') {
        const preview = tile(selfId, lane);
        preview.media.srcObject = acquired;
        void preview.media.play().catch(() => {});
      }
      await send({ type: 'media', [lane === 'audio' ? 'mic' : lane]: true });
      status(lane === 'screen' ? 'Sharing the selected screen or window.' : lane === 'audio' ? 'Microphone on.' : 'Camera on.');
    } catch (error) {
      acquired?.getTracks().forEach((track) => track.stop());
      if (epoch === currentEpoch) {
        await stopLane(lane);
        status(`${lane === 'audio' ? 'Microphone' : lane === 'camera' ? 'Camera' : 'Screen sharing'} unavailable: ${error.message}`, true);
      }
    } finally {
      if (epoch === currentEpoch) { mediaBusy.delete(lane); controls(); }
    }
  }
  $('host-form').addEventListener('submit', (event) => { event.preventDefault(); void enter(true); });
  $('join-form').addEventListener('submit', (event) => { event.preventDefault(); void enter(false); });
  $('mic').addEventListener('click', () => { void toggleLane('audio'); });
  $('camera').addEventListener('click', () => { void toggleLane('camera'); });
  $('screen').addEventListener('click', async () => {
    if (tracks.has('screen')) return stopLane('screen');
    const currentEpoch = epoch;
    try {
      const sources = await api.sources();
      if (currentEpoch !== epoch || !me()?.canShare) return;
      $('sources').replaceChildren();
      for (const source of sources) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'meeting-source';
        const img = document.createElement('img');
        img.src = source.thumbnail;
        img.alt = '';
        const name = document.createElement('span');
        name.textContent = source.name;
        b.append(img, name);
        b.addEventListener('click', () => { $('source-dialog').close(); void toggleLane('screen', source.id); });
        $('sources').append(b);
      }
      if (!sources.length) throw new Error('No capture sources found. Check your system screen recording permission.');
      $('source-dialog').showModal();
    } catch (error) { status(error.message, true); }
  });
  $('source-cancel').addEventListener('click', () => $('source-dialog').close());
  $('hand').addEventListener('click', () => action({ type: 'hand', raised: !me()?.hand }));
  $('mute-all').addEventListener('click', () => action({ type: 'mute-all' }));
  $('end').addEventListener('click', () => action({ type: 'end' }));
  $('leave').addEventListener('click', () => { void leave(); });
  $('copy').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText($('share-invitation').value); status('Invitation copied.'); }
    catch { $('share-invitation').select(); status('Select and copy the invitation above.'); }
  });
  $('board-toggle').addEventListener('click', () => { boardVisible = !boardVisible; controls(); refreshMedia(); });
  $('clear-board').addEventListener('click', () => action({ type: 'clear-board' }));
  function point(event) {
    const bounds = canvas.getBoundingClientRect();
    return [Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)), Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height))];
  }
  canvas.addEventListener('pointerdown', (event) => {
    if (!me()?.canShare || event.button !== 0 || drawing) return;
    canvas.setPointerCapture(event.pointerId);
    drawing = { color: $('pen-color').value, width: Number($('pen-width').value), points: [point(event)], pointerId: event.pointerId };
  });
  canvas.addEventListener('pointermove', (event) => {
    if (!drawing || !me()?.canShare || drawing.pointerId !== event.pointerId) return;
    drawing.points.push(point(event));
    if (drawing.points.length >= 200) {
      action({ type: 'stroke', stroke: { color: drawing.color, width: drawing.width, points: drawing.points } });
      drawing.points = [drawing.points.at(-1)];
    }
    redraw();
  });
  function finishDrawing(event) {
    if (!drawing || event.pointerId !== drawing.pointerId) return;
    if (drawing.points.length > 1 && me()?.canShare) action({ type: 'stroke', stroke: { color: drawing.color, width: drawing.width, points: drawing.points } });
    drawing = null;
    redraw();
  }
  canvas.addEventListener('pointerup', finishDrawing);
  canvas.addEventListener('pointercancel', finishDrawing);
  window.addEventListener('beforeunload', () => {
    for (const track of tracks.values()) track.stop();
    void api.leave();
  });
  window.lecture = { leave };
})();

const { contextBridge, ipcRenderer } = require('electron');


contextBridge.exposeInMainWorld('aegis', {
  meetings: {
    authenticate: (credentials) => ipcRenderer.invoke('meeting:authenticate', credentials),
    host: (title) => ipcRenderer.invoke('meeting:host', title),
    join: (invitation) => ipcRenderer.invoke('meeting:join', invitation),
    send: (message) => ipcRenderer.invoke('meeting:send', message),
    leave: () => ipcRenderer.invoke('meeting:leave'),
    signOut: () => ipcRenderer.invoke('meeting:sign-out'),
    sources: () => ipcRenderer.invoke('meeting:sources'),
    selectSource: (id) => ipcRenderer.invoke('meeting:select-source', id),
    onEvent: (callback) => {
      const listener = (_event, message) => callback(message);
      ipcRenderer.on('meeting:event', listener);
      return () => ipcRenderer.removeListener('meeting:event', listener);
    },
  },
  apiBaseUrl: process.env.AEGIS_API_URL || 'http://127.0.0.1:8001',
  academicApiBaseUrl:
    process.env.AEGIS_ACADEMIC_API_URL ||
    process.env.AEGIS_API_URL ||
    'http://127.0.0.1:8001',
});

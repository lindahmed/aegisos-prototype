const { app, BrowserWindow, Menu } = require('electron');
const path = require('path');
const { installMeetings } = require('./meetings/desktop');


function createWindow() {
  const mainWindow = new BrowserWindow({
    show: process.env.AEGIS_ELECTRON_TEST !== '1',
    width: 1440,
    height: 900,
    minWidth: 1000,
    minHeight: 720,
    backgroundColor: '#070f1e',
    title: 'UniTrack',
    icon: path.join(__dirname, 'assets', 'unitrack-mark.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  installMeetings(mainWindow);
  Menu.setApplicationMenu(null);
  mainWindow.loadFile(path.join(__dirname, 'index.html'));

  if (process.env.AEGIS_ELECTRON_SMOKE === '1') {
    mainWindow.webContents.once('did-finish-load', async () => {
      try {
        const isReady = await mainWindow.webContents.executeJavaScript(
          "Boolean(document.querySelector('#login-form') && window.aegis?.apiBaseUrl)",
        );
        app.exit(isReady ? 0 : 1);
      } catch (error) {
        console.error('Electron smoke check failed:', error);
        app.exit(1);
      }
    });
  }
}


app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});


app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

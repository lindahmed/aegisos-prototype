const { app, BrowserWindow, Menu } = require('electron');
const path = require('path');


function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 900,
    minHeight: 640,
    backgroundColor: '#08111f',
    title: 'AegisOS EDU',
    icon: path.join(__dirname, '..', 'desktop', 'assets', 'aegisos-logo.svg'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  Menu.setApplicationMenu(null);
  mainWindow.loadFile('index.html');

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

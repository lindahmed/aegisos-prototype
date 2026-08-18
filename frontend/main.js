const { app, BrowserWindow, ipcMain } = require('electron');
const { exec } = require('child_process');
const path = require('path');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 450,
    height: 650,
    resizable: false,
    title: "AegisOS EDU - Student Launcher",
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.loadFile('index.html');
}

// الاستماع لضغط زرار الدخول من الـ HTML
ipcMain.on('trigger-workspace', (event, studentId) => {
  console.log(`[Aegis UI] Executing workspace for student: ${studentId}`);

  // مسار ملف البايثون الخاص بـ Task 3
  const pythonScriptPath = `C:\\Users\\DELL\\OneDrive\\Desktop\\aegis person 2\\workspace_manager.py`;

  // تشغيل ملف البايثون تلقائياً
  exec(`python "${pythonScriptPath}"`, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error: ${error}`);
      event.reply('workspace-response', { success: false, message: 'Failed to run python script' });
      return;
    }
    
    // إرسال النتيجة للشاشة
    event.reply('workspace-response', { success: true, output: stdout });
  });
});

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
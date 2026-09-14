const { contextBridge } = require('electron');


contextBridge.exposeInMainWorld('aegis', {
  apiBaseUrl: process.env.AEGIS_API_URL || 'http://127.0.0.1:8001',
  academicApiBaseUrl:
    process.env.AEGIS_ACADEMIC_API_URL ||
    process.env.AEGIS_API_URL ||
    'http://127.0.0.1:8001',
});

const { contextBridge } = require('electron');


const apiBaseUrl = process.env.AEGIS_API_URL || 'http://127.0.0.1:8000';

contextBridge.exposeInMainWorld('aegis', {
  apiBaseUrl,
  academicApiBaseUrl: process.env.AEGIS_ACADEMIC_API_URL || apiBaseUrl,
});

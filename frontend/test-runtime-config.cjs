const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');


const preloadSource = fs.readFileSync(path.join(__dirname, 'preload.js'), 'utf8');
const launcherSource = fs.readFileSync(path.join(__dirname, '..', 'desktop', 'start-aegis.sh'), 'utf8');

function loadConfig(environment) {
  let exposed;
  vm.runInNewContext(preloadSource, {
    process: { env: environment },
    require(identifier) {
      assert.equal(identifier, 'electron');
      return { contextBridge: { exposeInMainWorld(_name, value) { exposed = value; } } };
    },
  });
  return {
    apiBaseUrl: exposed.apiBaseUrl,
    academicApiBaseUrl: exposed.academicApiBaseUrl,
  };
}

assert.deepEqual(loadConfig({}), {
  apiBaseUrl: 'http://127.0.0.1:8000',
  academicApiBaseUrl: 'http://127.0.0.1:8000',
});

assert.deepEqual(loadConfig({ AEGIS_API_URL: 'http://127.0.0.1:9000' }), {
  apiBaseUrl: 'http://127.0.0.1:9000',
  academicApiBaseUrl: 'http://127.0.0.1:9000',
});

assert.deepEqual(loadConfig({
  AEGIS_API_URL: 'http://127.0.0.1:9000',
  AEGIS_ACADEMIC_API_URL: 'https://academic.example.test',
}), {
  apiBaseUrl: 'http://127.0.0.1:9000',
  academicApiBaseUrl: 'https://academic.example.test',
});

assert.match(
  launcherSource,
  /AEGIS_API_URL="\$API_URL" AEGIS_ACADEMIC_API_URL="\$API_URL" npm start/,
  'The Linux launcher must route the app and messages through the same local backend.',
);

console.log('Desktop runtime configuration checks passed.');

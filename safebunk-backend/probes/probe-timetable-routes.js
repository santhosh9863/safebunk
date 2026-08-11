/**
 * Deep search the Vue.js app bundle for timetable routes and API calls.
 * The timetable feature is in a lazy-loaded chunk — find which chunk
 * by searching the app bundle for student timetable references.
 */

const axios = require('axios');
const fs = require('fs');
const path = require('path');

const BASE = 'https://sfcv4.linways.com';
const API = BASE + '/academics/api/v1';
const USERNAME = process.env.LINWAYS_USERNAME;
const PASSWORD = process.env.LINWAYS_PASSWORD;
const OUTPUT_DIR = path.join(__dirname, 'probe-results');

let rawCookies = '';
let bearerToken = '';

const api = axios.create({
  timeout: 15000,
  validateStatus: () => true,
  headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'text/html,application/json,*/*',
    'Content-Type': 'application/json',
    'Origin': BASE,
    'Referer': BASE + '/student/',
  },
});

api.interceptors.request.use(c => {
  if (rawCookies) c.headers['Cookie'] = rawCookies;
  if (bearerToken) c.headers['Authorization'] = 'Bearer ' + bearerToken;
  return c;
});

api.interceptors.response.use(r => {
  const sc = r.headers['set-cookie'];
  if (sc) {
    for (const c of (Array.isArray(sc) ? sc : [sc])) {
      const p = c.split(';')[0].trim();
      const k = p.split('=')[0];
      const ex = rawCookies ? rawCookies.split('; ').filter(Boolean).filter(e => e.split('=')[0] !== k) : [];
      ex.push(p);
      rawCookies = ex.join('; ');
    }
    const m = rawCookies.match(/AUTH_SESSION=([^;]+)/);
    if (m) bearerToken = m[1];
  }
  return r;
});

async function main() {
  console.log('[~] Logging in...');
  await api.post(API + '/auth/student-login-credentials', {
    username: USERNAME, password: PASSWORD, next: '', userType: 'STUDENT',
  });
  console.log('[✓] Logged in');

  // Download the main app bundle
  console.log('[~] Downloading app bundle...');
  const appRes = await api.get(BASE + '/ams/js/app.753669cc.js', {
    responseType: 'text',
    headers: { 'Accept': '*/*' },
  });
  const appJs = appRes.data;
  console.log('  App bundle size:', (appJs.length / 1024).toFixed(1), 'KB');

  // Search for student timetable routes in the app bundle
  const studentRoutes = [];
  const routePattern = /path:\s*["']([^"']+)["'][^}]*component[^:]*:\s*\(\)\s*=>\s*(?:Promise\.resolve\(\)\.then\(function\s*\(\s*\)\s*\{|Promise\.resolve\(\)\.then\(function\s*\(\)\s*\{|import\s*\([^)]+\))/g;
  let routeMatch;
  while ((routeMatch = routePattern.exec(appJs)) !== null) {
    studentRoutes.push(routeMatch[0].substring(0, 200));
  }

  // Find all lazy-load chunk references for student modules
  const chunkPattern = /import\(["']\.\/[^"']+["']\)|resolves?\s*\(\s*require\s*\(["'][^"']+["']\)\s*\)/g;
  const chunks = [];
  let chunkMatch;
  while ((chunkMatch = chunkPattern.exec(appJs)) !== null) {
    chunks.push(chunkMatch[0]);
  }

  // Search for exact strings: timetable, my-timetable, my-schedule
  const searchTerms = ['timetable', 'my-timetable', 'my-schedule', 'studentTimetable', 'classSchedule'];
  for (const term of searchTerms) {
    const regex = new RegExp('.{0,100}' + term + '.{0,100}', 'gi');
    let m;
    while ((m = regex.exec(appJs)) !== null) {
      console.log('\n[FOUND] "' + term + '" in app bundle:');
      console.log('  Context:', m[0].substring(0, 300));
    }
  }

  // Also search for student-related API paths in the app JS
  const studentApis = appJs.match(/student[^"']*|attendance[^"']*/gi) || [];
  const uniqueStudentApis = [...new Set(studentApis)].filter(s => s.length > 5 && s.length < 80);
  console.log('\nStudent/attendance related strings:', uniqueStudentApis.length);
  uniqueStudentApis.forEach(s => {
    // Only show ones that look like API paths or function names
    if (s.includes('timetable') || s.includes('schedule') || s.includes('class') || s.includes('report')) {
      console.log('  ' + s);
    }
  });

  // Save the app bundle for offline analysis
  fs.writeFileSync(path.join(OUTPUT_DIR, 'app.bundle.js'), appJs);
  console.log('\n[✓] App bundle saved');

  // Now try to download and search the vendor bundle for route definitions
  console.log('[~] Searching vendor bundle...');
  const vendorRes = await api.get(BASE + '/ams/js/chunk-vendors.fb11e3e2.js', {
    responseType: 'text',
    headers: { 'Accept': '*/*' },
  });
  const vendorJs = vendorRes.data;

  // Search vendor for timetable references
  for (const term of searchTerms) {
    const regex = new RegExp('.{0,80}' + term + '.{0,80}', 'gi');
    let m;
    let count = 0;
    while ((m = regex.exec(vendorJs)) !== null && count < 3) {
      console.log('\n[VENDOR] "' + term + '":');
      console.log('  ' + m[0].substring(0, 200));
      count++;
    }
  }
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });

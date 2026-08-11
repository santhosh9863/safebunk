/**
 * Download and search Linways Vue.js bundles for:
 * 1. All Vue Router route definitions
 * 2. All API endpoint references
 * 3. Timetable/schedule-related code
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
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html',
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

async function downloadJs(pathname) {
  const url = BASE + pathname;
  try {
    const res = await api.get(url, {
      responseType: 'text',
      headers: { 'Accept': '*/*' },
    });
    return { status: res.status, data: res.data };
  } catch (err) {
    return { status: 0, data: null, error: err.message };
  }
}

async function main() {
  // Login
  console.log('[~] Logging in...');
  await api.post(API + '/auth/student-login-credentials', {
    username: USERNAME, password: PASSWORD, next: '', userType: 'STUDENT',
  });
  console.log('[✓] Logged in');

  // Read dashboard HTML to extract JS bundle paths
  const dashRes = await api.get(BASE + '/student/', {
    headers: { 'Accept': 'text/html' },
    responseType: 'text',
  });
  const html = dashRes.data;

  // Extract all JS paths from prefetch links and script tags
  const jsPaths = [];
  const prefetchPattern = /<link[^>]+href="(\/ams\/js\/[^"]+\.js)"[^>]*rel="prefetch"[^>]*>/g;
  let m;
  while ((m = prefetchPattern.exec(html)) !== null) jsPaths.push(m[1]);

  // Main app + vendor
  const mainApp = html.match(/\/ams\/js\/app\.[a-f0-9]+\.js/);
  const vendor = html.match(/\/ams\/js\/chunk-vendors\.[a-f0-9]+\.js/);
  if (mainApp) jsPaths.unshift(mainApp[0]);
  if (vendor) jsPaths.unshift(vendor[0]);

  console.log('[~] JS bundles to analyze:', jsPaths.length);

  // Download and analyze all JS bundles
  const apiEndpoints = new Set();
  const routePaths = new Set();
  const timetableCode = [];
  let totalSize = 0;

  for (let i = 0; i < jsPaths.length; i++) {
    const jsPath = jsPaths[i];
    const result = await downloadJs(jsPath);
    if (!result.data) continue;
    totalSize += result.data.length;

    // Extract API endpoint references
    const apis = result.data.match(/\/academics\/api\/v1\/[a-zA-Z0-9_\/-]+/g) || [];
    apis.forEach(a => apiEndpoints.add(a));

    // Extract route paths (Vue Router)
    const routes = result.data.match(/path:\s*["']([^"']+)["']/g) || [];
    routes.forEach(r => {
      const match = r.match(/path:\s*["']([^"']+)["']/);
      if (match) routePaths.add(match[1]);
    });

    // Also look for axios/fetch calls with URLs
    const urlCalls = result.data.match(/["']\/[a-zA-Z0-9_\/-]+["']\s*[,)]/g) || [];
    urlCalls.forEach(u => {
      const clean = u.replace(/["',\s]/g, '');
      if (clean.startsWith('/') && !clean.includes('.')) {
        apiEndpoints.add(clean);
      }
    });

    // Look for timetable-related code
    if (/timetable|schedule|class_schedule|weekly/i.test(result.data)) {
      const lines = result.data.split('\n');
      for (let li = 0; li < lines.length; li++) {
        if (/timetable|schedule/i.test(lines[li])) {
          timetableCode.push({ file: jsPath, line: li, code: lines[li].substring(0, 300).trim() });
        }
      }
    }

    if ((i + 1) % 50 === 0) {
      console.log(`  [${i + 1}/${jsPaths.length}] analyzed... (${apiEndpoints.size} endpoints found)`);
    }
  }

  console.log('\n[✓] Analysis complete');
  console.log('  Bundles analyzed:', jsPaths.length);
  console.log('  Total JS size:', (totalSize / 1024 / 1024).toFixed(2), 'MB');
  console.log('  Unique API endpoints:', apiEndpoints.size);
  console.log('  Unique route paths:', routePaths.size);
  console.log('  Timetable-related code fragments:', timetableCode.length);

  // Filter and sort endpoints
  const sortedEndpoints = [...apiEndpoints].sort();
  const sortedRoutes = [...routePaths].sort();

  console.log('\n═══ ALL API ENDPOINTS ═══════════════════════════\n');
  sortedEndpoints.forEach(e => console.log('  ' + e));

  console.log('\n═══ ALL VUE ROUTES ══════════════════════════════\n');
  sortedRoutes.forEach(r => console.log('  ' + r));

  console.log('\n═══ TIMETABLE CODE FRAGMENTS ════════════════════\n');
  timetableCode.forEach(t => {
    console.log('  [' + t.file + '] Line ' + t.line + ':');
    console.log('    ' + t.code);
    console.log('');
  });

  // Save results
  const output = {
    timestamp: new Date().toISOString(),
    summary: {
      bundlesAnalyzed: jsPaths.length,
      totalJsSizeMb: (totalSize / 1024 / 1024).toFixed(2),
      uniqueApiEndpoints: apiEndpoints.size,
      uniqueRoutePaths: routePaths.size,
      timetableCodeFragments: timetableCode.length,
    },
    apiEndpoints: sortedEndpoints,
    routePaths: sortedRoutes,
    timetableCode,
  };
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUTPUT_DIR, '09-js-bundle-analysis.json'), JSON.stringify(output, null, 2));
  console.log('\n[✓] Full analysis → probe-results/09-js-bundle-analysis.json');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });

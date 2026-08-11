/**
 * Linways Timetable API Endpoint Probe v2
 *
 * Authenticates with Linways, then probes candidate endpoints
 * using the EXACT same auth pattern as the Flutter app:
 *   - Cookie header with full session cookies
 *   - Authorization: Bearer <AUTH_SESSION>
 */

const axios = require('axios');
const https = require('https');
const fs = require('fs');
const path = require('path');

const BASE = 'https://sfcv4.linways.com';
const API = `${BASE}/academics/api/v1`;
const USERNAME = process.env.LINWAYS_USERNAME;
const PASSWORD = process.env.LINWAYS_PASSWORD;
const OUTPUT_FILE = path.join(__dirname, 'probe-results', '07-timetable-probe.json');

// ── Full axios client mirroring Flutter auth ──────────────────────────
let _rawCookies = '';       // full Cookie header value
let _bearerToken = '';      // AUTH_SESSION JWT value

const client = axios.create({
  timeout: 15000,
  validateStatus: () => true,
  headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Origin': BASE,
    'Referer': `${BASE}/ams/student/login`,
  },
});

// Auto-attach BOTH Cookie + Bearer on every request (like Flutter's _AuthInterceptor)
client.interceptors.request.use(config => {
  if (_rawCookies) config.headers['Cookie'] = _rawCookies;
  if (_bearerToken) config.headers['Authorization'] = `Bearer ${_bearerToken}`;
  return config;
});

// Capture set-cookie from responses (like Flutter's cookie extraction)
client.interceptors.response.use(r => {
  const sc = r.headers['set-cookie'];
  if (sc) {
    for (const c of (Array.isArray(sc) ? sc : [sc])) {
      const p = c.split(';')[0].trim();
      const k = p.split('=')[0];
      const existing = _rawCookies ? _rawCookies.split('; ').filter(Boolean).filter(e => e.split('=')[0] !== k) : [];
      existing.push(p);
      _rawCookies = existing.join('; ');
    }
    const authMatch = _rawCookies.match(/AUTH_SESSION=([^;]+)/);
    if (authMatch) _bearerToken = authMatch[1];
  }
  return r;
});

// ── Login ─────────────────────────────────────────────────────────────
async function login() {
  if (!USERNAME || !PASSWORD) {
    console.error('[!] Set LINWAYS_USERNAME and LINWAYS_PASSWORD');
    return false;
  }
  console.log(`[~] Logging in as ${USERNAME}...`);
  const res = await client.post(`${API}/auth/student-login-credentials`, {
    username: USERNAME, password: PASSWORD, next: '', userType: 'STUDENT',
  });
  console.log(`    Status: ${res.status}`);
  if (res.status === 200 && _bearerToken) {
    console.log(`[✓] Login OK — AUTH_SESSION length: ${_bearerToken.length}`);
    return true;
  }
  console.log(`[✗] Login failed. Body: ${JSON.stringify(res.data).slice(0, 200)}`);
  return false;
}

// ── Probe endpoints ───────────────────────────────────────────────────
const ENDPOINT_TEMPLATES = [
  // Direct timetable routes
  { m: 'GET',  p: '/timetable/student-timetable' },
  { m: 'GET',  p: '/timetable/weekly-timetable' },
  { m: 'GET',  p: '/timetable/list' },
  { m: 'GET',  p: '/timetable/my-timetable' },
  { m: 'GET',  p: '/student/timetable' },
  { m: 'GET',  p: '/student/weekly-schedule' },
  { m: 'GET',  p: '/student/my-schedule' },
  { m: 'GET',  p: '/student/get-student-timetable' },
  { m: 'GET',  p: '/student/get-weekly-timetable' },
  { m: 'GET',  p: '/student/get-schedule' },
  { m: 'GET',  p: '/student/get-class-schedule' },
  { m: 'GET',  p: '/schedule/student-schedule' },
  { m: 'GET',  p: '/schedule/weekly' },
  { m: 'GET',  p: '/class-schedule/student' },
  { m: 'GET',  p: '/class-schedule/student-wise-schedule' },
  { m: 'GET',  p: '/class-schedule/list' },
  { m: 'GET',  p: '/attendance/timetable' },
  { m: 'GET',  p: '/attendance/weekly-schedule' },
  { m: 'GET',  p: '/ams/student/timetable' },
  { m: 'GET',  p: '/ams/student/weekly-schedule' },
  { m: 'GET',  p: '/academics/student/timetable' },

  // POST variants
  { m: 'POST', p: '/timetable/student-timetable' },
  { m: 'POST', p: '/student/get-student-timetable' },
  { m: 'POST', p: '/student/timetable' },
  { m: 'POST', p: '/student/my-schedule' },

  // With query params (GET) — will be filled with student info
  { m: 'GET',  p: '/timetable/student-timetable',     q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/timetable/weekly-timetable',      q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/student/timetable',               q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/student/get-student-timetable',   q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/student/my-schedule',             q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/student/weekly-schedule',         q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/schedule/weekly',                 q: { studentId: '__SID__' } },
  { m: 'GET',  p: '/timetable/list',                  q: { studentId: '__SID__', semester: '__SEM__' } },
  { m: 'GET',  p: '/student/timetable',               q: { registerNo: '__REG__' } },
  { m: 'GET',  p: '/timetable/student-timetable',     q: { registerNo: '__REG__' } },
  { m: 'GET',  p: '/schedule/weekly',                 q: { semester: '__SEM__', department: '__DEPT__' } },
  { m: 'GET',  p: '/timetable/list',                  q: { semester: '__SEM__', batch: '__BATCH__' } },
];

// ── Probe a single endpoint ───────────────────────────────────────────
async function probe(ep, si) {
  const params = {};
  if (ep.q) {
    for (const [k, v] of Object.entries(ep.q)) {
      params[k] = v
        .replace('__SID__', si?.studentId || '')
        .replace('__REG__', si?.registerNo || '')
        .replace('__SEM__', si?.semester || '')
        .replace('__DEPT__', si?.department || '')
        .replace('__BATCH__', si?.batch || '');
    }
  }

  const url = `${API}${ep.p}`;
  try {
    const start = Date.now();
    let res;
    if (ep.m === 'GET') {
      res = await client.get(url, { params });
    } else {
      res = await client.post(url, Object.keys(params).length > 0 ? params : { studentId: si?.studentId || '' });
    }
    const elapsed = Date.now() - start;
    const bodyStr = typeof res.data === 'string' ? res.data : JSON.stringify(res.data);
    const keywords = /timetable|schedule|period|subject|faculty|room|class|day|hour|slot|time|lecture|lab|break/i;
    return {
      method: ep.m, endpoint: ep.p, params: Object.keys(params).length ? params : undefined,
      status: res.status, elapsed: elapsed,
      len: bodyStr.length,
      kw: keywords.test(bodyStr),
      preview: bodyStr.length > 500 ? bodyStr.slice(0, 500) : bodyStr,
    };
  } catch (err) {
    return { method: ep.m, endpoint: ep.p, status: 0, error: err.message };
  }
}

// ── Main ──────────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════');
  console.log('  Linways Timetable API Probe v2');
  console.log('═══════════════════════════════════════════════════════\n');

  if (!await login()) process.exit(1);

  // Fetch student info for param substitution
  let si = null;
  try {
    const infoRes = await client.get(`${API}/student/get-student-basic-details`);
    if (infoRes.status === 200 && infoRes.data?.data) {
      const d = infoRes.data.data;
      si = {
        studentId: d.studentId || d.id || '',
        registerNo: d.properties?.registerNumber || d.registerNo || '',
        semester: d.currentSem || '',
        department: d.department || '',
        batch: d.batchName || '',
      };
      console.log(`[✓] Student: ${d.name} (ID: ${si.studentId}, Sem: ${si.semester}, Dept: ${si.department})`);
    }
  } catch (_) {}

  // Also get known working URLs to confirm auth works
  console.log(`\n[~] Verifying auth with known endpoints...`);
  const known = ['/student/get-student-basic-details', '/attendance/daily-attendance'];
  for (const ep of known) {
    const r = await client.get(`${API}${ep}`, { params: { studentId: si?.studentId || USERNAME } });
    console.log(`    ${ep.padEnd(45)} ${r.status}`);
    if (r.status !== 200) {
      console.log(`\n[!] Auth verification FAILED — session may have expired.`);
      console.log(`    Response: ${JSON.stringify(r.data).slice(0, 200)}`);
    }
  }

  // Probe all timetable candidates
  console.log(`\n[~] Probing ${ENDPOINT_TEMPLATES.length} endpoint candidates...\n`);
  const results = [];
  for (const ep of ENDPOINT_TEMPLATES) {
    const r = await probe(ep, si);
    results.push(r);
    const status = r.status === 200 ? '✓' : r.status === 401 ? '🔒' : r.status === 0 ? '!' : '·';
    const extra = r.status === 200 ? `len=${r.len} kw=${r.kw}` : (r.error || `HTTP ${r.status}`);
    console.log(`  ${status} ${r.method} ${ep.p.padEnd(45)} ${extra}`);
  }

  // Sort: 200s first, with keyword matches on top
  results.sort((a, b) => {
    const sa = (a.status === 200 ? 10 : 0) + (a.kw ? 5 : 0);
    const sb = (b.status === 200 ? 10 : 0) + (b.kw ? 5 : 0);
    return sb - sa;
  });

  const output = {
    timestamp: new Date().toISOString(),
    student: si,
    config: { base: BASE, api: API, endpointsProbed: ENDPOINT_TEMPLATES.length },
    summary: {
      total: results.length,
      status200: results.filter(r => r.status === 200).length,
      status401: results.filter(r => r.status === 401).length,
      status404: results.filter(r => r.status === 404).length,
      status500: results.filter(r => r.status >= 500).length,
      errors: results.filter(r => r.status === 0).length,
      withKeywords: results.filter(r => r.kw).length,
    },
    promising: results.filter(r => r.status === 200).map(r => ({
      method: r.method,
      endpoint: r.endpoint,
      params: r.params,
      bodyLength: r.len,
      bodyPreview: r.preview,
    })),
    all: results,
  };

  fs.mkdirSync(path.dirname(OUTPUT_FILE), { recursive: true });
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
  console.log(`\n[✓] Full results → ${OUTPUT_FILE}`);

  console.log('\n═══ SUMMARY ═══════════════════════════════════════');
  console.log(`  200 OK:        ${output.summary.status200}`);
  console.log(`  401 Unauthorized: ${output.summary.status401}`);
  console.log(`  404 Not Found: ${output.summary.status404}`);
  console.log(`  5xx:           ${output.summary.status500}`);
  console.log(`  Has keywords:  ${output.summary.withKeywords}`);
  console.log('════════════════════════════════════════════════════\n');

  if (output.promising.length > 0) {
    console.log('ALL 200 endpoints with response previews:\n');
    for (const ep of output.promising) {
      console.log(`>>> ${ep.method} ${ep.endpoint}`);
      if (ep.params) console.log(`    Params: ${JSON.stringify(ep.params)}`);
      console.log(`    Response (${ep.bodyLength} chars):`);
      console.log(`    ${ep.bodyPreview.replace(/\n/g, '\n    ')}`);
      console.log('');
    }
  } else {
    console.log('No endpoint returned HTTP 200. All responses were 401.\n');
    console.log('This means the timetable endpoint uses a different path pattern.');
    console.log('Next step: Use puppeteer to navigate the Linways portal directly');
    console.log('and capture the actual API request made when loading the timetable page.');
  }
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });

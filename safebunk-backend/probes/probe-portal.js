/**
 * Linways Portal HTML Inspector
 * Logs in, fetches the student dashboard HTML, and extracts all
 * API endpoint references, navigation links, and timetable-related URLs
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
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Origin': BASE,
    'Referer': BASE + '/ams/student/login',
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
  console.log('[✓] Logged in. Bearer token length:', bearerToken.length);

  const findings = {};

  // ── 1. Fetch student dashboard HTML ──
  console.log('\n[1] Fetching student dashboard HTML...');
  const dash = await api.get(BASE + '/student/', {
    headers: { 'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9' },
    responseType: 'text',
  });
  console.log('   Status:', dash.status, 'HTML length:', dash.data.length);
  findings.dashboardHtml = {
    status: dash.status,
    length: dash.data.length,
    first2000: dash.data.substring(0, 2000),
  };

  // Save full HTML for inspection
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUTPUT_DIR, 'dashboard.html'), dash.data);

  // ── 2. Extract all API endpoints from HTML ──
  const apiMatches = dash.data.match(/\/academics\/api\/v1\/[a-zA-Z0-9_\/-]+/g) || [];
  const uniqueApis = [...new Set(apiMatches)];
  console.log('   API endpoints found in HTML:', uniqueApis.length);
  uniqueApis.forEach(a => console.log('     ' + a));
  findings.apiEndpointsInHtml = uniqueApis;

  // ── 3. Extract all links containing timetable/schedule/class ──
  const linkPattern = /<a[^>]+href\s*=\s*["']([^"']+)["'][^>]*>/gi;
  let linkMatch;
  const allLinks = [];
  while ((linkMatch = linkPattern.exec(dash.data)) !== null) {
    allLinks.push(linkMatch[1]);
  }
  const relevantLinks = allLinks.filter(l => /timetable|schedule|class|weekly|period|timetbl/i.test(l));
  console.log('\n   Navigation links with timetable/schedule keywords:', relevantLinks.length);
  relevantLinks.forEach(l => console.log('     ' + l));
  findings.timetableLinks = relevantLinks;

  // ── 4. Extract all script src URLs ──
  const scriptPattern = /<script[^>]+src\s*=\s*["']([^"']+)["'][^>]*>/gi;
  const scripts = [];
  while ((scriptMatch = scriptPattern.exec(dash.data)) !== null) {
    scripts.push(scriptMatch[1]);
  }
  console.log('\n   Scripts loaded:', scripts.length);
  findings.scripts = scripts.slice(0, 30);

  // ── 5. Extract AJAX/fetch/axios calls from inline scripts ──
  const xhrPattern = /(?:axios|fetch|\$\.ajax|\$\.get|\$\.post|XMLHttpRequest|http\.get|api\.get|api\.post)\s*[\(\.][^)]*["']([^"']+)["']/gi;
  const xhrCalls = [];
  let xhrMatch;
  while ((xhrMatch = xhrPattern.exec(dash.data)) !== null) {
    xhrCalls.push({ call: xhrMatch[0].substring(0, 150), url: xhrMatch[1] });
  }
  console.log('\n   AJAX/XHR calls in HTML:', xhrCalls.length);
  xhrCalls.forEach(x => console.log('     ' + x.url));
  findings.xhrCalls = xhrCalls;

  // ── 6. Try to fetch the login menus endpoint ──
  console.log('\n[2] Fetching login menus...');
  const menus = await api.get(API + '/student/get-student-login-menus/ENABLE_DYNAMIC_LINK_MENUS');
  console.log('   Status:', menus.status);
  const menuStr = JSON.stringify(menus.data);
  console.log('   Data:', menuStr.substring(0, 1500));
  findings.loginMenus = menus.status === 200 ? menus.data : null;

  // ── 7. Look for any Angular/React state that contains routes ──
  const angularState = dash.data.match(/window\.__INITIAL_STATE__\s*=\s*({.+?});/);
  const ngRoute = dash.data.match(/\.config\(\[['\"]\$routeProvider['\"],\s*function[^}]+/i);
  console.log('\n   Angular state found:', !!angularState);
  console.log('   Angular routes found:', !!ngRoute);

  // ── 8. Probe some paths found in the HTML ──
  console.log('\n[3] Probing paths found in HTML...');
  const pathsToProbe = uniqueApis
    .filter(p => !p.includes('login') && !p.includes('sso') && !p.includes('auth'))
    .slice(0, 20);
  for (const ep of pathsToProbe) {
    const fullUrl = BASE + ep;
    try {
      const start = Date.now();
      const res = await api.get(fullUrl);
      const elapsed = Date.now() - start;
      const bodyStr = JSON.stringify(res.data);
      const keywords = /timetable|schedule|period|subject|faculty|room|class|day|hour|slot|time|lecture|lab/i;
      const hasKw = keywords.test(bodyStr);
      console.log(`   ${res.status} ${ep.padEnd(55)} ${bodyStr.length}B kw=${hasKw} ${elapsed}ms`);
    } catch (e) {
      console.log(`   ERR ${ep} ${e.message}`);
    }
  }

  // ── 9. Save all findings ──
  const output = {
    timestamp: new Date().toISOString(),
    findings,
  };
  fs.writeFileSync(path.join(OUTPUT_DIR, '08-portal-inspection.json'), JSON.stringify(output, null, 2));
  console.log('\n[✓] Full report → probe-results/08-portal-inspection.json');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });

/**
 * Term Selection Probe — dumps the FULL studied-terms + basic-details responses
 * and reports exactly which term each field points at.
 *
 * Usage:
 *   set LINWAYS_USERNAME=... and LINWAYS_PASSWORD=...
 *   node probes/probe-term-selection.js [studentId]
 */

const axios = require('axios');
const https = require('https');

const BASE = 'https://sfcv4.linways.com';
const API = `${BASE}/academics/api/v1`;
const USERNAME = process.env.LINWAYS_USERNAME;
const PASSWORD = process.env.LINWAYS_PASSWORD;
const STUDENT_ID = process.argv[2] || null;

let _rawCookies = '';
let _bearerToken = '';

const client = axios.create({
  timeout: 20000,
  validateStatus: () => true,
  headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json',
    'Origin': BASE,
    'Referer': `${BASE}/academics/`,
  },
});

client.interceptors.request.use(config => {
  if (_rawCookies) config.headers['Cookie'] = _rawCookies;
  if (_bearerToken) config.headers['Authorization'] = `Bearer ${_bearerToken}`;
  return config;
});

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

async function login() {
  if (!USERNAME || !PASSWORD) {
    console.error('[!] Set LINWAYS_USERNAME and LINWAYS_PASSWORD');
    process.exit(1);
  }
  console.log(`[~] Logging in as ${USERNAME}...`);
  const res = await client.post(`${API}/auth/student-login-credentials`, {
    username: USERNAME, password: PASSWORD, next: '', userType: 'STUDENT',
  });
  console.log(`    Status: ${res.status}`);
  if (res.status === 200 && _bearerToken) {
    console.log(`[OK] Login OK — AUTH_SESSION length: ${_bearerToken.length}`);
    return true;
  }
  console.log(`[X] Login failed: ${JSON.stringify(res.data).slice(0, 300)}`);
  return false;
}

async function main() {
  if (!await login()) process.exit(1);

  // ── 1. get-student-basic-details (session-based, no params first) ──
  console.log('\n═══ 1. GET /student/get-student-basic-details (no params) ═══');
  let studentId = STUDENT_ID;
  let basicDetails = null;
  const bdRes = await client.get(`${API}/student/get-student-basic-details`);
  console.log(`Status: ${bdRes.status}`);
  if (bdRes.status === 200 && bdRes.data) {
    basicDetails = bdRes.data;
    console.log(JSON.stringify(bdRes.data, null, 2));
    const d = bdRes.data?.data;
    if (d) {
      const props = d.properties || {};
      console.log('\n── KEY FIELD EXTRACT ──');
      console.log(JSON.stringify({
        studentId: d.studentId ?? d.id ?? null,
        name: d.name ?? d.studentName ?? null,
        currentSem: d.currentSem ?? d.currentSemester ?? null,
        academicTermId: d.academicTermId ?? props.academicTermId ?? null,
        academicTermName: d.academicTermName ?? props.academicTermName ?? null,
        batchId: d.batchId ?? props.currentBatchId ?? null,
        batchName: d.batchName ?? d.batch ?? null,
        regNo: d.regNo ?? d.registerNo ?? props.registerNumber ?? null,
        allTopLevelKeys: Object.keys(d),
        allPropertyKeys: Object.keys(props),
      }, null, 2));
      studentId = studentId || (d.studentId ?? d.id);
    }
  } else {
    console.log(`Body: ${JSON.stringify(bdRes.data).slice(0, 500)}`);
  }

  if (!studentId) {
    console.log('[!] No studentId resolved. Pass it as argv[2] or check login.');
    process.exit(1);
  }
  console.log(`\n[~] Using studentId = ${studentId}`);

  // ── 2. fetch-student-studied-terms/{studentId} ──
  console.log(`\n═══ 2. GET /attendance/fetch-student-studied-terms/${studentId} ═══`);
  const termsRes = await client.get(`${API}/attendance/fetch-student-studied-terms/${studentId}`);
  console.log(`Status: ${termsRes.status}`);
  console.log(JSON.stringify(termsRes.data, null, 2));

  const termsData = termsRes.data?.data;
  const termList = Array.isArray(termsData?.termList) ? termsData.termList : [];
  const currentTermId = termsData?.currentTermId;

  console.log('\n── TERM LIST SUMMARY ──');
  for (const t of termList) {
    console.log(`  termId=${t.termId} | ${t.termName} | ${t.startDate ?? ''} → ${t.endDate ?? ''} | keys: ${Object.keys(t).join(',')}`);
  }

  // ── 3. basic-details again WITH studentId param ──
  if (basicDetails === null) {
    console.log(`\n═══ 3. GET /student/get-student-basic-details?studentId=${studentId} ═══`);
    const bd2 = await client.get(`${API}/student/get-student-basic-details`, { params: { studentId } });
    console.log(`Status: ${bd2.status}`);
    console.log(JSON.stringify(bd2.data, null, 2));
  }

  // ── 4. Cross-check: what termId would the report use for each candidate? ──
  const today = new Date();
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  console.log(`\n═══ 4. TERM SELECTION CROSS-CHECK (today=${todayStr}) ═══`);

  const acadTermId = basicDetails?.data?.academicTermId ?? basicDetails?.data?.properties?.academicTermId;

  const containingToday = termList.filter(t => t.startDate && t.endDate &&
    t.startDate <= todayStr && t.endDate >= todayStr);

  console.log(JSON.stringify({
    basicDetails_academicTermId: acadTermId ?? null,
    basicDetails_academicTermName: basicDetails?.data?.academicTermName ?? null,
    basicDetails_currentSem: basicDetails?.data?.currentSem ?? basicDetails?.data?.currentSemester ?? null,
    studiedTerms_currentTermId: currentTermId ?? null,
    studiedTerms_count: termList.length,
    studiedTerms_ids: termList.map(t => `${t.termId}(${t.termName})`),
    termsContainingToday: containingToday.map(t => `${t.termId}(${t.termName})`),
    lastTermInList: termList.length ? `${termList[termList.length - 1].termId}(${termList[termList.length - 1].termName})` : null,
  }, null, 2));

  // ── 5. Fire the subject-wise report for each candidate termId to see which returns NEW-semester subjects ──
  console.log(`\n═══ 5. subject-wise-attendance-report for each candidate term ═══`);
  const candidates = [];
  const seen = new Set();
  const add = id => { if (id && !seen.has(String(id))) { seen.add(String(id)); candidates.push(String(id)); } };
  add(acadTermId);
  add(currentTermId);
  for (const t of containingToday) add(t.termId);
  if (termList.length) add(termList[termList.length - 1].termId);
  for (const t of termList) add(t.termId);

  for (const termId of candidates) {
    const term = termList.find(t => String(t.termId) === termId);
    const filter = {
      firstTime: false,
      termId,
      startDate: term?.startDate ?? '',
      endDate: term?.endDate ?? '',
      studentId,
      academicStatus: 'ACTIVE',
      mapping: 'STUDENT-SUBJECT-WISE',
    };
    const r = await client.get(`${API}/attendance/subject-wise-attendance-report`, {
      params: { filter: JSON.stringify(filter) },
      headers: { 'X-Menu-Code': 'STUDENT_SUBJECT_WISE_ATTENDANCE_METHOD' },
    });
    let subjects = [];
    let success = false;
    if (r.data?.success && Array.isArray(r.data?.data?.termDetails)) {
      success = true;
      subjects = r.data.data.termDetails.map(s => s.courseName ?? s.subjectName ?? '?');
    }
    console.log(`  termId=${termId} (${term?.termName ?? '?'}) → status=${r.status} success=${success} subjects=${subjects.length} :: ${subjects.join(' | ')}`);
  }

  console.log('\n[DONE]');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });

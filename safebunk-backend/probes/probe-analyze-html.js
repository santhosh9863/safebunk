const fs = require('fs');
const html = fs.readFileSync('probe-results/dashboard.html', 'utf8');
console.log('Total length:', html.length);

// Find the app root element
const rootMatch = html.match(/<div[^>]*id="app"[^>]*>/);
console.log('App root element:', rootMatch ? rootMatch[0] : 'NOT FOUND');

// Find script tags
const scriptTags = [];
let idx = 0;
while (true) {
  const start = html.indexOf('<script', idx);
  if (start === -1) break;
  const end = html.indexOf('</script>', start);
  if (end === -1) break;
  const tag = html.substring(start, end + 9);
  scriptTags.push(tag);
  idx = end + 9;
}
console.log('\nScript tags found:', scriptTags.length);
scriptTags.forEach((t, i) => {
  const src = t.match(/src="([^"]*)"/);
  if (src) {
    console.log('  [' + i + '] External:', src[1]);
  } else {
    const content = t.replace(/<\/?script[^>]*>/g, '').trim();
    console.log('  [' + i + '] Inline (' + content.length + ' chars):', content.substring(0, 300));
  }
});

// Find all API paths
const apiPaths = html.match(/\/academics\/api\/v1\/[a-zA-Z0-9_\/-]+/g) || [];
console.log('\nAPI paths referenced:', apiPaths.length);
const uniqueApis = [...new Set(apiPaths)];
uniqueApis.forEach(p => console.log('  ' + p));

// Find all /ams/ paths (css, js chunks, routes)
const amsPaths = html.match(/\/ams\/[a-zA-Z0-9_\/.-]+/g) || [];
const uniqueAms = [...new Set(amsPaths)];
console.log('\nAMS paths (' + uniqueAms.length + ' unique, showing all):');
uniqueAms.forEach(p => {
  if (!p.endsWith('.css') && !p.endsWith('.ico') && !p.endsWith('.png') && !p.endsWith('.jpg')) {
    console.log('  ' + p);
  }
});

// Show CSS chunks
const cssChunks = html.match(/\/ams\/css\/chunk-[a-f0-9]+\.([a-f0-9]+)\.css/g) || [];
console.log('\nCSS chunks:', cssChunks.length);
const jsChunks = html.match(/\/ams\/js\/chunk-[a-f0-9]+\.([a-f0-9]+)\.js/g) || [];
console.log('JS chunks (prefetch):', jsChunks.length);

// Look for Vue app config
const vueConfig = html.match(/new\s+Vue\s*\(/);
const vueRouter = html.match(/VueRouter|vue-router/);
const axiosRef = html.match(/axios/);
console.log('\nVue detected:', !!vueConfig);
console.log('VueRouter detected:', !!vueRouter);
console.log('Axios detected:', !!axiosRef);

// Check for any JSON config/data embedded
const jsonConfig = html.match(/window\.\w+\s*=\s*\{[^;]+\};/g);
console.log('\nWindow configs found:', jsonConfig ? jsonConfig.length : 0);
if (jsonConfig) jsonConfig.forEach(c => console.log('  ' + c.substring(0, 200)));

// Does the page reference timetable anywhere?
const timetableAnywhere = html.match(/[Tt]imetable/g);
console.log('\n"Timetable" text in HTML:', timetableAnywhere ? timetableAnywhere.length : 0);
const scheduleAnywhere = html.match(/[Ss]chedule/g);
console.log('"Schedule" text in HTML:', scheduleAnywhere ? scheduleAnywhere.length : 0);
const classAnywhere = html.match(/[Cc]lass/g);
console.log('"Class" text in HTML:', classAnywhere ? classAnywhere.length : 0);

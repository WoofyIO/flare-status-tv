// Regenerates the invented test fixtures in
// FlareStatusKit/Tests/FlareStatusKitTests/Fixtures.
//
//   node scripts/make-fixtures.mjs
//
// The shapes follow UptimeFlare's own code (pages/index.tsx, pages/api/data.ts,
// worker/src/store.ts). The content is made up: no fixture describes a real
// deployment.
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'FlareStatusKit', 'Tests', 'FlareStatusKitTests', 'Fixtures')
mkdirSync(out, { recursive: true })

const NOW = 1780000000 // fixed "now" used by the tests
const DAY = 86400

const hex = (typed) => Buffer.from(typed.buffer).toString('hex')
const rle = (locs) => {
  const v = [], c = []
  for (const l of locs) {
    if (v[v.length - 1] === l) c[c.length - 1]++
    else { v.push(l); c.push(1) }
  }
  return { v, c }
}

const monitors = [
  { id: 'web', name: 'Website', tooltip: 'Checks the home page', statusPageLink: 'https://example.com' },
  { id: 'api', name: 'Public API' },
  { id: 'db', name: 'Database', hideLatencyChart: true },
  { id: 'fresh', name: 'Brand new monitor' },
]

// Uncompacted truth, oldest first.
const incidents = {
  web: [
    { start: [NOW - 90 * DAY], end: NOW - 90 * DAY, error: ['dummy'] },
    { start: [NOW - 10 * DAY, NOW - 10 * DAY + 600], end: NOW - 10 * DAY + 3600, error: ['HTTP 502', 'Timeout after 10000ms'] },
  ],
  api: [
    { start: [NOW - 30 * DAY], end: NOW - 30 * DAY, error: ['dummy'] },
    { start: [NOW - 1800, NOW - 600], end: null, error: ['HTTP 503', 'Connection refused'] },
  ],
  db: [{ start: [NOW - 90 * DAY], end: NOW - 90 * DAY, error: ['dummy'] }],
}
const latency = {
  web: [[NOW - 720, 120, 'SEA'], [NOW - 540, 131, 'SEA'], [NOW - 360, 118, 'SEA'], [NOW - 180, 400, 'FRA'], [NOW - 60, 125, 'SEA']],
  api: [[NOW - 360, 70000 - 65536 + 300, 'NRT'], [NOW - 180, 65535, 'NRT'], [NOW - 60, 0, 'NRT']],
  db: [[NOW - 60, 9, 'push']],
}

const compacted = { lastUpdate: NOW - 30, overallUp: 2, overallDown: 1, incident: {}, latency: {} }
for (const [id, list] of Object.entries(incidents)) {
  compacted.incident[id] = { start: list.map((i) => i.start), end: list.map((i) => i.end), error: list.map((i) => i.error) }
}
for (const [id, list] of Object.entries(latency)) {
  compacted.latency[id] = {
    loc: rle(list.map((p) => p[2])),
    ping: hex(new Uint16Array(list.map((p) => p[1]))),
    time: hex(new Uint32Array(list.map((p) => p[0]))),
  }
}

const legacy = { lastUpdate: NOW - 30, overallUp: 2, overallDown: 1, incident: {}, latency: {} }
for (const [id, list] of Object.entries(incidents)) {
  // The KV releases left `end` undefined for an open incident, so the key is absent.
  legacy.incident[id] = list.map((i) => (i.end === null ? { start: i.start, error: i.error } : i))
}
for (const [id, list] of Object.entries(latency)) {
  const records = list.map(([time, ping, loc]) => ({ loc, ping, time }))
  legacy.latency[id] = { recent: records, all: records.slice(0, 1) }
}

const page = (pageProps, buildId = 'fixtureBuild01') => `<!DOCTYPE html><html><head><meta charSet="utf-8"/><meta name="viewport" content="width=device-width"/><meta name="next-head-count" content="2"/><link rel="preload" href="/_next/static/css/aaaa.css" as="style"/><script defer="" nomodule="" src="/_next/static/chunks/polyfills-0000.js"></script><script src="/_next/static/chunks/webpack-1111.js" defer=""></script><script src="/_next/static/chunks/framework-2222.js" defer=""></script><script src="/_next/static/chunks/main-3333.js" defer=""></script><script src="/_next/static/chunks/pages/_app-4444.js" defer=""></script><script src="/_next/static/chunks/469-5555.js" defer=""></script><script src="/_next/static/chunks/pages/index-6666.js" defer=""></script><script src="/_next/static/${buildId}/_buildManifest.js" defer=""></script></head><body><div id="__next"></div><script id="__NEXT_DATA__" type="application/json">${JSON.stringify({ props: { pageProps, __N_SSP: true }, page: '/', query: {}, buildId, isFallback: false, gssp: true, scriptLoader: [] })}</script></body></html>\n`

const write = (name, text) => writeFileSync(join(out, name), text)

write('page-d1.html', page({ compactedStateStr: JSON.stringify(compacted), monitors }))
write('page-kv-legacy.html', page({ state: JSON.stringify(legacy), monitors }, 'fixtureLegacy01'))
write('page-no-state.html', page({ compactedStateStr: null, monitors }))

const corrupt = structuredClone(compacted)
corrupt.latency.web.ping = corrupt.latency.web.ping.slice(4)
write('page-d1-corrupt.html', page({ compactedStateStr: JSON.stringify(corrupt), monitors }))

write('page-other-nextjs.html', page({ posts: [{ title: 'Hello' }] }))
write('page-not-nextjs.html', '<!DOCTYPE html><html><head><title>Example Domain</title></head><body><h1>Example Domain</h1><script src="/app.js"></script></body></html>\n')

// What `pageConfig` looks like after minification, inside a webpack chunk.
write(
  'config-chunk.js',
  '"use strict";(self.webpackChunk_N_E=self.webpackChunk_N_E||[]).push([[469],{3469:function(t,e,n){n.d(e,{Gs:function(){return i},MP:function(){return r}});' +
    'let o={group:"not this one"},r={title:"Example \\u2014 Status",links:[{link:"mailto:hello@example.com",label:"Contact",highlight:!0}],' +
    'group:{Website:["web"],"APIs & data":["api","db"],\'Caf\\xe9\':["fresh"]},maintenances:{upcomingColor:"gray"}},' +
    'i=[{monitors:["db"],title:"Upgrade",body:"Planned work",start:"2026-05-28T10:00:00+00:00",end:1780010000000}]}}]);\n'
)
write(
  'config-chunk-ungrouped.js',
  '"use strict";(self.webpackChunk_N_E=self.webpackChunk_N_E||[]).push([[469],{3469:function(t,e,n){let r={title:"Plain page",links:[{link:"https://example.com",label:"Home"}]},i=[]}}]);\n'
)

const live = {
  up: 2,
  down: 1,
  updatedAt: NOW,
  monitors: {
    web: { up: true, latency: 125, location: 'SEA', message: 'OK' },
    api: { up: false, latency: 0, location: 'NRT', message: 'Connection refused' },
    db: { up: true, latency: 9, location: 'push', message: 'OK' },
  },
  maintenances: [
    { monitors: ['db'], title: 'Upgrade', body: 'Planned work', start: '2026-05-28T10:00:00+00:00', end: 1780010000000 },
    { body: 'Open-ended notice', start: NOW - 3600 },
    { title: 'Broken entry', body: 'No usable start', start: 'whenever' },
  ],
}
write('api-data.json', JSON.stringify(live))
const { maintenances, ...liveLegacy } = live
write('api-data-legacy.json', JSON.stringify(liveLegacy))
write('api-no-data.json', JSON.stringify({ error: 'No data available' }))
console.log('fixtures written to', out)

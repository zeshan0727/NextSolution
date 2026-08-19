'use strict';

// Safe read-only SpringBoard attribution sampler for NextLock investigation.
// No Interceptor hooks, no ObjC enumeration, no memory writes.

const CPU_WINDOW_MS = 8000;
const SAMPLE_WINDOW_MS = 20000;
const SAMPLE_INTERVAL_MS = 100;
const TOP_CPU_THREADS = 5;
const TOP_MODULES = 20;
const TOP_FRAMES = 30;

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function hex(n) {
  return '0x' + Number(n).toString(16).toUpperCase();
}

function stripPtr(p) {
  try { return p.strip(); } catch (_) { return p; }
}

function safeModuleByAddress(p) {
  try { return Process.findModuleByAddress(stripPtr(p)); } catch (_) { return null; }
}

function safeSymbolByAddress(p) {
  try {
    const s = DebugSymbol.fromAddress(stripPtr(p));
    return s && s.name ? s.name : '-';
  } catch (_) {
    return '-';
  }
}

function snapshotThread(tid) {
  try {
    return Process.enumerateThreads().find(t => t.id === tid) || null;
  } catch (_) {
    return null;
  }
}

function bump(map, key, by = 1) {
  map.set(key, (map.get(key) || 0) + by);
}

function topEntries(map, limit) {
  return Array.from(map.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, count]) => ({ name, count }));
}

async function rankCpuThreads() {
  const selfTid = Process.getCurrentThreadId();
  const threads = Process.enumerateThreads().filter(t => t.id !== selfTid);
  const samplers = [];

  for (const t of threads) {
    try {
      samplers.push({ tid: t.id, state: t.state, sampler: new UserTimeSampler(t.id), before: 0, after: 0 });
    } catch (_) {}
  }

  for (const s of samplers) {
    try { s.before = s.sampler.sample(); } catch (_) { s.before = 0; }
  }

  await sleep(CPU_WINDOW_MS);

  for (const s of samplers) {
    try { s.after = s.sampler.sample(); } catch (_) { s.after = s.before; }
  }

  return samplers.map(s => ({
    tid: s.tid,
    tidHex: hex(s.tid),
    state: s.state,
    delta: Math.max(0, Number(s.after) - Number(s.before))
  })).sort((a, b) => b.delta - a.delta);
}

async function sampleThread(tid) {
  const moduleCounts = new Map();
  const frameCounts = new Map();
  const lockGlyphFrames = new Map();
  const perfFixFrames = new Map();
  let samples = 0;
  let backtraceFailures = 0;

  const start = Date.now();
  while (Date.now() - start < SAMPLE_WINDOW_MS) {
    const t = snapshotThread(tid);
    if (!t) {
      backtraceFailures++;
      await sleep(SAMPLE_INTERVAL_MS);
      continue;
    }

    let bt = [];
    try {
      bt = Thread.backtrace(t.context, Backtracer.ACCURATE);
      if (!bt || bt.length === 0) bt = Thread.backtrace(t.context, Backtracer.FUZZY);
    } catch (_) {
      try { bt = Thread.backtrace(t.context, Backtracer.FUZZY); } catch (_) { bt = []; }
    }

    if (!bt || bt.length === 0) {
      backtraceFailures++;
      await sleep(SAMPLE_INTERVAL_MS);
      continue;
    }

    samples++;
    for (const raw of bt) {
      const p = stripPtr(raw);
      const m = safeModuleByAddress(p);
      const moduleName = m ? m.name : 'UNKNOWN';
      bump(moduleCounts, moduleName);

      let offset = '-';
      if (m) {
        try { offset = p.sub(m.base).toString(); } catch (_) {}
      }
      const sym = safeSymbolByAddress(p);
      const frameKey = `${moduleName}!${sym} @ ${offset}`;
      bump(frameCounts, frameKey);

      if (moduleName === 'LockGlyphTime.dylib') bump(lockGlyphFrames, frameKey);
      if (moduleName === 'NextLockPerfFix.dylib') bump(perfFixFrames, frameKey);
    }

    await sleep(SAMPLE_INTERVAL_MS);
  }

  return {
    samples,
    backtraceFailures,
    modules: topEntries(moduleCounts, TOP_MODULES),
    frames: topEntries(frameCounts, TOP_FRAMES),
    lockGlyphFrames: topEntries(lockGlyphFrames, TOP_FRAMES),
    perfFixFrames: topEntries(perfFixFrames, TOP_FRAMES)
  };
}

async function main() {
  console.log('[*] SAFE LIVE ATTRIBUTION: read-only CPU/backtrace sampling; no Interceptor hooks.');
  console.log(`[*] SpringBoard PID: ${Process.id}`);

  const lg = Process.findModuleByName('LockGlyphTime.dylib');
  const pf = Process.findModuleByName('NextLockPerfFix.dylib');
  console.log(`[module] LockGlyphTime.dylib = ${lg ? lg.path : 'NOT LOADED'}`);
  console.log(`[module] NextLockPerfFix.dylib = ${pf ? pf.path : 'NOT LOADED'}`);

  console.log(`[*] Ranking SpringBoard threads for ${CPU_WINDOW_MS / 1000}s...`);
  const ranked = await rankCpuThreads();
  const topCpu = ranked.slice(0, TOP_CPU_THREADS);
  for (let i = 0; i < topCpu.length; i++) {
    const r = topCpu[i];
    console.log(`[cpu ${i + 1}] TID ${r.tidHex} delta=${r.delta} state=${r.state}`);
  }

  if (ranked.length === 0 || ranked[0].delta <= 0) {
    console.log('[!] No measurable hot thread found. Leave the CPU issue active and rerun once.');
    return;
  }

  const hotTid = ranked[0].tid;
  console.log(`[*] Sampling hottest thread ${hex(hotTid)} for ${SAMPLE_WINDOW_MS / 1000}s...`);
  const hot = await sampleThread(hotTid);

  console.log('\n=== TOP MODULES ON HOT THREAD ===');
  for (const x of hot.modules) console.log(`${x.count}\t${x.name}`);

  console.log('\n=== TOP FRAMES ON HOT THREAD ===');
  for (const x of hot.frames) console.log(`${x.count}\t${x.name}`);

  console.log('\n=== LOCKGLYPHTIME FRAMES ===');
  if (hot.lockGlyphFrames.length === 0) console.log('0\t(no LockGlyphTime frames captured)');
  else for (const x of hot.lockGlyphFrames) console.log(`${x.count}\t${x.name}`);

  console.log('\n=== NEXTLOCKPERFFIX FRAMES ===');
  if (hot.perfFixFrames.length === 0) console.log('0\t(no NextLockPerfFix frames captured)');
  else for (const x of hot.perfFixFrames) console.log(`${x.count}\t${x.name}`);

  const report = {
    kind: 'springboard-live-attribution-v1',
    pid: Process.id,
    modules: {
      LockGlyphTime: lg ? lg.path : null,
      NextLockPerfFix: pf ? pf.path : null
    },
    cpuWindowMs: CPU_WINDOW_MS,
    cpuRanking: topCpu,
    hotThread: hex(hotTid),
    sampleWindowMs: SAMPLE_WINDOW_MS,
    sampleIntervalMs: SAMPLE_INTERVAL_MS,
    hot
  };

  console.log('\n=== JSON REPORT ===');
  console.log(JSON.stringify(report));
  console.log('\n[+] DONE. Upload the Tee-Object TXT file through NS Transfer Upload.');
}

main().catch(e => console.log('[fatal] ' + (e && e.stack ? e.stack : e)));

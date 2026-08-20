'use strict';

// Read-only SpringBoard CPU check after NextLock Test 4.
// Samples user CPU time for all SpringBoard threads and reports total + hottest threads.
// No Interceptor hooks, no ObjC enumeration, no memory writes.

const WINDOW_MS = 15000;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function sampleNumber(s) { try { return Number(s.sample()); } catch (_) { return 0; } }

async function main() {
  console.log('[*] SpringBoard PID: ' + Process.id);
  const lock = Process.findModuleByName('LockGlyphTime.dylib');
  const fix = Process.findModuleByName('NextLockPerfFix.dylib');
  console.log('[module] LockGlyphTime.dylib = ' + (lock ? 'LOADED' : 'NOT LOADED'));
  console.log('[module] NextLockPerfFix.dylib = ' + (fix ? 'LOADED' : 'NOT LOADED'));

  const selfTid = Process.getCurrentThreadId();
  const rows = [];
  for (const t of Process.enumerateThreads()) {
    if (t.id === selfTid) continue;
    try {
      const s = new UserTimeSampler(t.id);
      rows.push({ tid: t.id, state: t.state, sampler: s, before: sampleNumber(s), after: 0, delta: 0 });
    } catch (_) {}
  }

  console.log('[*] Sampling total SpringBoard user CPU for ' + (WINDOW_MS / 1000) + 's...');
  await sleep(WINDOW_MS);

  let total = 0;
  for (const r of rows) {
    r.after = sampleNumber(r.sampler);
    r.delta = Math.max(0, r.after - r.before);
    total += r.delta;
  }

  rows.sort((a,b) => b.delta - a.delta);
  const seconds = WINDOW_MS / 1000;
  const totalPct = (total / (seconds * 1000000)) * 100;

  console.log('\n=== POST-TEST4 SPRINGBOARD CPU ===');
  console.log('window_ms=' + WINDOW_MS);
  console.log('total_user_cpu_delta_us=' + total);
  console.log('approx_total_user_cpu_percent=' + totalPct.toFixed(2) + '%');
  console.log('\n=== TOP THREADS ===');
  rows.slice(0,8).forEach((r,i) => {
    const pct = (r.delta / (seconds * 1000000)) * 100;
    console.log(`${i+1}\tTID 0x${r.tid.toString(16).toUpperCase()}\tdelta=${r.delta}\t~${pct.toFixed(2)}%\tstate=${r.state}`);
  });
  console.log('\n[+] DONE');
}

setImmediate(() => { main().catch(e => console.log('[!] fatal: ' + e.stack)); });

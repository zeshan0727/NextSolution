'use strict';

// Burst-aware, read-only SpringBoard CPU sampler.
// No Interceptor hooks, no ObjC enumeration, no memory writes.

const RANK_MS = 5000;
const WATCH_MS = 35000;
const POLL_MS = 25;
const CPU_BURST_DELTA = 1000; // user-time units are microseconds on this target
const TOP_STACKS = 12;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function stripPtr(p) { try { return p.strip(); } catch (_) { return p; } }
function modFor(p) { try { return Process.findModuleByAddress(stripPtr(p)); } catch (_) { return null; } }
function symFor(p) { try { return DebugSymbol.fromAddress(stripPtr(p)); } catch (_) { return null; } }
function sampleNumber(sampler) {
  // Frida 17 may return BigInt from UserTimeSampler.sample(). Convert at the
  // boundary so sorting, subtraction, comparisons, and JSON/string output use
  // ordinary Numbers consistently.
  try { return Number(sampler.sample()); } catch (_) { return 0; }
}
function fmtFrame(p) {
  const q = stripPtr(p), m = modFor(q), s = symFor(q);
  const off = m ? q.sub(m.base) : null;
  const mn = m ? m.name : 'UNKNOWN';
  const sn = s && s.name ? s.name : q.toString();
  return `${mn}!${sn}${off !== null ? ' @ +' + off.toString() : ''}`;
}
function getThread(tid) {
  const ts = Process.enumerateThreads();
  for (const t of ts) if (t.id === tid) return t;
  return null;
}
function add(map, key, n = 1) { map.set(key, (map.get(key) || 0) + n); }

async function rankThreads() {
  const all = Process.enumerateThreads();
  const agentTid = Process.getCurrentThreadId();
  const samplers = [];
  for (const t of all) {
    if (t.id === agentTid) continue;
    try { samplers.push({tid:t.id, sampler:new UserTimeSampler(t.id), before:0}); } catch (_) {}
  }
  for (const x of samplers) x.before = sampleNumber(x.sampler);
  await sleep(RANK_MS);
  const rows = [];
  for (const x of samplers) {
    const after = sampleNumber(x.sampler);
    rows.push({tid:x.tid, delta:Math.max(0, after - x.before)});
  }
  rows.sort((a,b)=>b.delta-a.delta);
  return rows;
}

async function main() {
  console.log('[*] SAFE BURST ATTRIBUTION: read-only; no Interceptor hooks.');
  console.log('[*] SpringBoard PID: ' + Process.id);
  const lock = Process.findModuleByName('LockGlyphTime.dylib');
  const fix = Process.findModuleByName('NextLockPerfFix.dylib');
  console.log('[module] LockGlyphTime.dylib = ' + (lock ? lock.path : 'NOT LOADED'));
  console.log('[module] NextLockPerfFix.dylib = ' + (fix ? fix.path : 'NOT LOADED'));

  console.log('[*] Ranking threads for ' + (RANK_MS/1000) + 's...');
  const ranked = await rankThreads();
  ranked.slice(0,5).forEach((r,i)=>console.log(`[cpu ${i+1}] TID 0x${r.tid.toString(16).toUpperCase()} delta=${r.delta}`));
  if (!ranked.length) { console.log('[!] No threads sampled'); return; }

  const tid = ranked[0].tid;
  console.log(`[*] Watching hottest TID 0x${tid.toString(16).toUpperCase()} for ${WATCH_MS/1000}s and capturing only CPU bursts...`);
  let sampler;
  try { sampler = new UserTimeSampler(tid); } catch (e) { console.log('[!] sampler failed: ' + e); return; }
  let last = sampleNumber(sampler);
  const stacks = new Map();
  const modules = new Map();
  const lockOffsets = new Map();
  let burstCaptures = 0, totalCpuDelta = 0, failures = 0;
  const burstTimeline = [];
  const start = Date.now();

  while (Date.now() - start < WATCH_MS) {
    await sleep(POLL_MS);
    const now = sampleNumber(sampler);
    const d = Math.max(0, now - last);
    last = now;
    if (d <= 0) continue;
    totalCpuDelta += d;

    const t = getThread(tid);
    if (!t) continue;
    if (d < CPU_BURST_DELTA && t.state === 'waiting') continue;

    let bt;
    try { bt = Thread.backtrace(t.context, Backtracer.ACCURATE); }
    catch (_) {
      try { bt = Thread.backtrace(t.context, Backtracer.FUZZY); }
      catch (_) { failures++; continue; }
    }
    burstCaptures++;
    burstTimeline.push({ms:Date.now()-start, cpuDelta:d, state:t.state});

    const frames = bt.map(fmtFrame);
    add(stacks, frames.slice(0,14).join(' <- '));
    for (const p of bt) {
      const q = stripPtr(p), m = modFor(q);
      if (!m) continue;
      add(modules, m.name);
      if (lock && m.name === 'LockGlyphTime.dylib') add(lockOffsets, q.sub(lock.base).toString());
    }
  }

  function printMap(title, map, limit) {
    console.log('\n=== ' + title + ' ===');
    [...map.entries()].sort((a,b)=>b[1]-a[1]).slice(0,limit).forEach(([k,v])=>console.log(v + '\t' + k));
    if (!map.size) console.log('0\t(none)');
  }

  console.log(`\n[+] total CPU delta during watch = ${totalCpuDelta}`);
  console.log(`[+] burst captures = ${burstCaptures}, backtrace failures = ${failures}`);
  printMap('TOP MODULES DURING CPU BURSTS', modules, 20);
  printMap('LOCKGLYPHTIME OFFSETS DURING CPU BURSTS', lockOffsets, 30);
  printMap('TOP COMPLETE BURST STACKS', stacks, TOP_STACKS);
  console.log('\n=== BURST TIMELINE ===');
  burstTimeline.slice(0,200).forEach(x=>console.log(`${x.ms}ms\tcpuDelta=${x.cpuDelta}\tstate=${x.state}`));
  console.log('\n[+] DONE.');
}

setImmediate(() => { main().catch(e => console.log('[!] fatal: ' + e.stack)); });

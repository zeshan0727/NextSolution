'use strict';

// Targeted NextLock renderer caller counter for the verified 1.1.4 arm64 slice.
// This attaches to exactly ONE internal function (the full renderer at +0x896c),
// increments counters only, and prints aggregated caller counts once per second.
// No ObjC enumeration, no mass hooks, no per-call logging.

const m = Process.findModuleByName('LockGlyphTime.dylib');
if (!m) {
  console.log('[!] LockGlyphTime.dylib not loaded');
} else {
  const target = m.base.add(0x896c);
  console.log('[*] LockGlyphTime base = ' + m.base);
  console.log('[*] Renderer target    = ' + target + ' (+0x896c)');

  const labels = {
    '0x6680': 'layoutSubviews hook (+0x6510 -> renderer)',
    '0x99b0': 'deferred duplicate block (+0x998c -> renderer)',
    '0xb3bc': 'global refresh path (+0xafa4 -> renderer)',
    '0xbcb0': 'callback block (+0xbc30 -> renderer)'
  };

  const totals = new Map();
  const lastTotals = new Map();
  let total = 0;
  let lastTotal = 0;

  function add(k) { totals.set(k, (totals.get(k) || 0) + 1); }
  function keyForReturnAddress(ra) {
    try {
      const q = ra.strip ? ra.strip() : ra;
      const mod = Process.findModuleByAddress(q);
      if (mod && mod.name === 'LockGlyphTime.dylib') {
        return q.sub(m.base).toString();
      }
      return (mod ? mod.name : 'UNKNOWN') + '@' + q;
    } catch (_) {
      return 'UNKNOWN';
    }
  }

  const listener = Interceptor.attach(target, {
    onEnter() {
      total++;
      add(keyForReturnAddress(this.returnAddress));
    }
  });

  let sec = 0;
  const timer = setInterval(() => {
    sec++;
    const rate = total - lastTotal;
    lastTotal = total;

    const deltas = [];
    for (const [k, v] of totals.entries()) {
      const prev = lastTotals.get(k) || 0;
      const d = v - prev;
      lastTotals.set(k, v);
      if (d > 0) deltas.push([k, d]);
    }
    deltas.sort((a, b) => b[1] - a[1]);

    const detail = deltas.slice(0, 8).map(([k, d]) => {
      const label = labels[k] ? ' ' + labels[k] : '';
      return `${k}=${d}/s${label}`;
    }).join(' | ');

    console.log(`[${sec}s] renderer calls=${rate}/s total=${total}${detail ? ' | ' + detail : ''}`);

    if (sec >= 15) {
      clearInterval(timer);
      listener.detach();
      console.log('\n=== FINAL RENDERER CALLERS (15s) ===');
      [...totals.entries()].sort((a, b) => b[1] - a[1]).forEach(([k, v]) => {
        const label = labels[k] ? ' ' + labels[k] : '';
        console.log(`${v}\t${k}${label}`);
      });
      console.log(`[+] total renderer calls = ${total}`);
      console.log('[+] DONE');
    }
  }, 1000);
}

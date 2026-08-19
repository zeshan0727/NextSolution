'use strict';

// Corrected NextLock 1.1.4 caller counter for the active arm64e slice.
// Hooks exactly three verified update/render function ENTRIES and only counts
// calls + return addresses. No ObjC enumeration, no mass hooks, no memory writes.
//
// Active arm64e UUID: 7BE1428A-C4B0-38F8-8120-7BACBF220731
//   clock/date update A  +0x8388
//   clock/date update B  +0x86b8
//   four-photo renderer  +0x8a58
// Verified direct return-address labels from static BL decoding:
//   +0x66d4 / +0x66e0 / +0x66e8 = layoutSubviews hook
//   +0xb488 / +0xb508 / +0xb520 = global refresh path
//   +0xbe50 / +0xbe58           = callback/update path
//   +0x9aa4                    = deferred photo duplicate path

const m = Process.findModuleByName('LockGlyphTime.dylib');
if (!m) {
  console.log('[!] LockGlyphTime.dylib not loaded');
} else {
  const entries = [
    {name:'updateA', off:0x8388},
    {name:'updateB', off:0x86b8},
    {name:'photos',  off:0x8a58}
  ];
  const labels = {
    '0x66d4':'layoutSubviews -> updateA',
    '0x66e0':'layoutSubviews -> updateB',
    '0x66e8':'layoutSubviews -> photos',
    '0xb488':'global refresh -> updateA',
    '0xb508':'global refresh -> updateB',
    '0xb520':'global refresh -> photos',
    '0xbe50':'callback/update -> updateA',
    '0xbe58':'callback/update -> photos',
    '0x9aa4':'deferred duplicate -> photos'
  };

  console.log('[*] LockGlyphTime base = ' + m.base);
  console.log('[*] Correct active-slice entries: +0x8388, +0x86b8, +0x8a58');

  const totals = new Map();
  const lastTotals = new Map();
  const listeners = [];

  function keyFor(name, ra) {
    try {
      const q = ra.strip ? ra.strip() : ra;
      const mod = Process.findModuleByAddress(q);
      const where = mod && mod.name === 'LockGlyphTime.dylib'
        ? q.sub(m.base).toString()
        : ((mod ? mod.name : 'UNKNOWN') + '@' + q);
      return name + '|' + where;
    } catch (_) { return name + '|UNKNOWN'; }
  }

  for (const e of entries) {
    const target = m.base.add(e.off);
    listeners.push(Interceptor.attach(target, {
      onEnter() {
        const k = keyFor(e.name, this.returnAddress);
        totals.set(k, (totals.get(k) || 0) + 1);
      }
    }));
  }

  let sec = 0;
  const timer = setInterval(() => {
    sec++;
    const deltas = [];
    for (const [k,v] of totals.entries()) {
      const prev = lastTotals.get(k) || 0;
      const d = v - prev;
      lastTotals.set(k, v);
      if (d > 0) deltas.push([k,d]);
    }
    deltas.sort((a,b)=>b[1]-a[1]);
    const detail = deltas.slice(0,12).map(([k,d])=>{
      const [name,where] = k.split('|');
      const label = labels[where] ? ' ('+labels[where]+')' : '';
      return `${name}@${where}=${d}/s${label}`;
    }).join(' | ');
    console.log(`[${sec}s] ${detail || 'no calls'}`);

    if (sec >= 10) {
      clearInterval(timer);
      for (const l of listeners) l.detach();
      console.log('\n=== FINAL CORRECTED CALLERS (10s) ===');
      [...totals.entries()].sort((a,b)=>b[1]-a[1]).forEach(([k,v])=>{
        const [name,where] = k.split('|');
        const label = labels[where] ? ' ('+labels[where]+')' : '';
        console.log(`${v}\t${name}\t${where}${label}`);
      });
      console.log('[+] DONE');
    }
  }, 1000);
}

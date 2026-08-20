#!/usr/bin/env python3
import json
import pathlib
import threading
import frida

OUT_DIR = pathlib.Path.cwd() / "nextlock_lockglyphtime_capture"
OUT_DIR.mkdir(parents=True, exist_ok=True)
RUNTIME_OUT = OUT_DIR / "lockglyphtime_runtime.json"

finished = threading.Event()
state = {"runtime": None, "error": None}

AGENT = r'''
"use strict";

const module = Process.getModuleByName("LockGlyphTime.dylib");
const exactMap = new ModuleMap(m => m.path === module.path);
const agentTid = Process.getCurrentThreadId();

function stripPtr(p) {
    try { return p.strip(); } catch (_) { return p; }
}

function offsetInModule(p) {
    p = stripPtr(p);
    try {
        const owner = Process.findModuleByAddress(p);
        if (!owner || owner.path !== module.path) return null;
        return p.sub(module.base).toString();
    } catch (_) {
        return null;
    }
}

function symbolRecord(p) {
    p = stripPtr(p);
    let owner = null;
    let sym = null;
    try { owner = Process.findModuleByAddress(p); } catch (_) {}
    try { sym = DebugSymbol.fromAddress(p); } catch (_) {}

    return {
        address: p.toString(),
        module: owner ? owner.name : null,
        path: owner ? owner.path : null,
        symbol: (sym && sym.name) ? sym.name : null,
        lockGlyphOffset: owner && owner.path === module.path
            ? p.sub(module.base).toString()
            : null
    };
}

function enumerateOwnedMethods() {
    const result = {
        module: {
            name: module.name,
            path: module.path,
            base: module.base.toString(),
            size: module.size
        },
        classes: [],
        hotThread: null,
        samples: [],
        lockGlyphFrames: {},
        durationSeconds: 15,
        samplingIntervalMs: 150
    };

    if (typeof ObjC !== "undefined" && ObjC.available) {
        try {
            const loaded = ObjC.enumerateLoadedClassesSync({ ownedBy: exactMap });
            const classNames = loaded[module.path] || [];

            classNames.forEach(name => {
                const cls = ObjC.classes[name];
                if (!cls) return;

                const methods = [];
                (cls.$ownMethods || []).forEach(sel => {
                    try {
                        const method = cls[sel];
                        if (!method || !method.implementation) return;
                        let impl = stripPtr(method.implementation);
                        const owner = Process.findModuleByAddress(impl);
                        if (!owner || owner.path !== module.path) return;

                        methods.push({
                            selector: sel,
                            implementation: impl.toString(),
                            offset: impl.sub(module.base).toString()
                        });
                    } catch (_) {}
                });

                if (methods.length > 0)
                    result.classes.push({ name, methods });
            });
        } catch (e) {
            result.objcEnumerationError = String(e);
        }
    }

    send({
        type: "profile-start",
        classCount: result.classes.length,
        message: "Read-only sampling; no Interceptor hooks will be installed."
    });

    // Phase 1: identify the actual CPU-heavy SpringBoard thread using read-only samplers.
    const initialThreads = Process.enumerateThreads();
    const samplers = [];

    initialThreads.forEach(t => {
        if (t.id === agentTid) return;
        try {
            const sampler = new UserTimeSampler(t.id);
            samplers.push({
                id: t.id,
                name: t.name || "",
                sampler,
                start: sampler.sample()
            });
        } catch (_) {}
    });

    setTimeout(() => {
        const ranking = [];

        samplers.forEach(x => {
            try {
                const end = x.sampler.sample();
                ranking.push({
                    id: x.id,
                    name: x.name,
                    delta: (end - x.start).toString()
                });
            } catch (_) {}
        });

        ranking.sort((a, b) => {
            const aa = BigInt(a.delta);
            const bb = BigInt(b.delta);
            return aa > bb ? -1 : (aa < bb ? 1 : 0);
        });

        result.threadRanking = ranking.slice(0, 20);

        if (ranking.length === 0) {
            send({type: "fatal", stage: "thread-ranking", error: "No usable thread samplers"});
            return;
        }

        const hotTid = ranking[0].id;
        result.hotThread = {
            id: hotTid,
            idHex: "0x" + hotTid.toString(16).toUpperCase(),
            name: ranking[0].name,
            cpuDelta: ranking[0].delta
        };

        send({
            type: "hot-thread",
            id: hotTid,
            idHex: result.hotThread.idHex,
            cpuDelta: ranking[0].delta
        });

        let polls = 0;
        const maxPolls = Math.ceil((result.durationSeconds * 1000) / result.samplingIntervalMs);

        const timer = setInterval(() => {
            polls++;

            let thread = null;
            try {
                const threads = Process.enumerateThreads();
                for (let i = 0; i < threads.length; i++) {
                    if (threads[i].id === hotTid) {
                        thread = threads[i];
                        break;
                    }
                }
            } catch (_) {}

            if (thread && thread.state === "running") {
                const rec = {
                    poll: polls,
                    state: thread.state,
                    pc: symbolRecord(thread.context.pc),
                    lr: thread.context.lr ? symbolRecord(thread.context.lr) : null,
                    backtrace: []
                };

                let frames = [];
                try {
                    frames = Thread.backtrace(thread.context, Backtracer.ACCURATE);
                } catch (_) {
                    try { frames = Thread.backtrace(thread.context, Backtracer.FUZZY); } catch (_) {}
                }

                rec.backtrace = frames.slice(0, 32).map(symbolRecord);
                result.samples.push(rec);

                rec.backtrace.forEach(f => {
                    if (!f.lockGlyphOffset) return;
                    const key = f.lockGlyphOffset;
                    if (!result.lockGlyphFrames[key]) {
                        result.lockGlyphFrames[key] = {
                            count: 0,
                            symbol: f.symbol,
                            address: f.address
                        };
                    }
                    result.lockGlyphFrames[key].count++;
                });
            }

            if (polls >= maxPolls) {
                clearInterval(timer);

                result.lockGlyphFrameRanking = Object.entries(result.lockGlyphFrames)
                    .map(([offset, v]) => ({offset, count: v.count, symbol: v.symbol, address: v.address}))
                    .sort((a, b) => b.count - a.count)
                    .slice(0, 100);

                send({type: "runtime", payload: result});
                send({type: "done"});
            }
        }, result.samplingIntervalMs);

    }, 5000);
}

enumerateOwnedMethods();
'''


def on_message(message, data):
    payload = message.get("payload", {}) if isinstance(message, dict) else {}

    if message.get("type") == "error":
        state["error"] = message
        print("[!] Frida script error:", message)
        finished.set()
        return

    kind = payload.get("type") if isinstance(payload, dict) else None

    if kind == "profile-start":
        print(f"[+] Enumerated {payload.get('classCount')} LockGlyphTime Objective-C classes")
        print("[+] SAFE MODE: read-only CPU/backtrace sampling; no Interceptor hooks.")
        print("[+] Leave the phone idle on the Lock Screen.")

    elif kind == "hot-thread":
        print(f"[+] Hot thread: {payload.get('idHex')} CPU delta={payload.get('cpuDelta')}")
        print("[+] Sampling its native stack for 15 seconds...")

    elif kind == "runtime":
        state["runtime"] = payload.get("payload")
        RUNTIME_OUT.write_text(json.dumps(state["runtime"], indent=2), encoding="utf-8")
        print(f"[+] Saved {RUNTIME_OUT}")

        rows = (state["runtime"] or {}).get("lockGlyphFrameRanking", [])[:20]
        print("\nTop LockGlyphTime frames seen in the hot-thread backtrace:")
        if not rows:
            print("    (none captured in this sampling window)")
        for row in rows:
            print(f"{row['count']:>6}  offset={row['offset']}  symbol={row.get('symbol') or '-'}")

    elif kind == "fatal":
        state["error"] = payload
        print("[!] Agent failure:", payload)
        finished.set()

    elif kind == "done":
        finished.set()


def main():
    print("[*] Connecting to USB iPhone through Frida...")
    device = frida.get_usb_device(timeout=10)
    params = device.query_system_parameters()
    print("[*] Access:", params.get("access"))

    if params.get("access") != "full":
        raise SystemExit("Frida access is not FULL. Start the jailbreak-side frida-server first.")

    proc = next((p for p in device.enumerate_processes() if p.name == "SpringBoard"), None)
    if proc is None:
        raise SystemExit("SpringBoard was not found.")

    print(f"[*] Attaching to SpringBoard PID {proc.pid}...")
    session = device.attach(proc.pid)
    script = session.create_script(AGENT)
    script.on("message", on_message)
    script.load()

    if not finished.wait(35):
        raise SystemExit("Timed out waiting for LockGlyphTime read-only capture.")

    try:
        script.unload()
    except Exception:
        pass
    try:
        session.detach()
    except Exception:
        pass

    if state["error"]:
        raise SystemExit(f"Capture failed: {state['error']}")
    if not RUNTIME_OUT.exists():
        raise SystemExit("Capture completed but runtime profile was not written.")

    print("\n[+] COMPLETE")
    print(f"    Runtime: {RUNTIME_OUT}")
    print("    This profiler does not patch or hook SpringBoard code.")


if __name__ == "__main__":
    main()

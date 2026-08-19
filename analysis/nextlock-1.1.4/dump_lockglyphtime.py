#!/usr/bin/env python3
import json
import pathlib
import threading
import time
import frida

OUT_DIR = pathlib.Path.cwd() / "nextlock_lockglyphtime_capture"
OUT_DIR.mkdir(parents=True, exist_ok=True)
DYLIB_OUT = OUT_DIR / "LockGlyphTime.dylib"
RUNTIME_OUT = OUT_DIR / "lockglyphtime_runtime.json"

finished = threading.Event()
state = {"meta": None, "runtime": None, "error": None}

AGENT = r'''
"use strict";

const module = Process.getModuleByName("LockGlyphTime.dylib");
const exactMap = new ModuleMap(m => m.path === module.path);

function ptrOffset(p) {
    try { p = p.strip(); } catch (_) {}
    return p.sub(module.base).toString();
}

function sendBinary() {
    try {
        const bytes = File.readAllBytes(module.path);
        send({
            type: "binary",
            module: module.name,
            path: module.path,
            base: module.base.toString(),
            size: bytes.byteLength
        }, bytes);
    } catch (e) {
        send({type: "fatal", stage: "binary", error: String(e)});
    }
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
        hooks: [],
        durationSeconds: 15
    };

    if (typeof ObjC === "undefined" || !ObjC.available) {
        send({type: "fatal", stage: "objc", error: "ObjC bridge unavailable"});
        return;
    }

    const loaded = ObjC.enumerateLoadedClassesSync({ ownedBy: exactMap });
    const classNames = loaded[module.path] || [];
    const hookByAddress = new Map();

    classNames.forEach(name => {
        const cls = ObjC.classes[name];
        if (!cls) return;

        const methods = [];
        (cls.$ownMethods || []).forEach(sel => {
            try {
                const method = cls[sel];
                if (!method || !method.implementation) return;
                let impl = method.implementation;
                try { impl = impl.strip(); } catch (_) {}
                const owner = Process.findModuleByAddress(impl);
                if (!owner || owner.path !== module.path) return;

                const rec = {
                    className: name,
                    selector: sel,
                    implementation: impl.toString(),
                    offset: ptrOffset(impl),
                    calls: 0
                };
                methods.push(rec);

                const key = impl.toString();
                if (!hookByAddress.has(key)) hookByAddress.set(key, []);
                hookByAddress.get(key).push(rec);
            } catch (_) {}
        });

        if (methods.length !== 0)
            result.classes.push({name, methods});
    });

    for (const [address, records] of hookByAddress.entries()) {
        try {
            Interceptor.attach(ptr(address), {
                onEnter() {
                    records.forEach(r => r.calls++);
                }
            });
        } catch (e) {
            result.hooks.push({address, error: String(e)});
        }
    }

    send({
        type: "profile-start",
        classCount: result.classes.length,
        implementationCount: hookByAddress.size,
        seconds: result.durationSeconds
    });

    setTimeout(() => {
        const flat = [];
        result.classes.forEach(c => c.methods.forEach(m => {
            if (m.calls > 0) flat.push(m);
        }));
        flat.sort((a, b) => b.calls - a.calls);
        result.hottestMethods = flat.slice(0, 100);
        send({type: "runtime", payload: result});
        send({type: "done"});
    }, result.durationSeconds * 1000);
}

sendBinary();
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
    if kind == "binary":
        if data is None:
            state["error"] = "binary message contained no data"
            finished.set()
            return
        DYLIB_OUT.write_bytes(bytes(data))
        state["meta"] = payload
        print(f"[+] Saved {DYLIB_OUT} ({len(data)} bytes)")
    elif kind == "profile-start":
        print(f"[+] Profiling {payload.get('implementationCount')} LockGlyphTime implementations for {payload.get('seconds')} seconds")
        print("[+] Leave the phone idle on the Lock Screen during this interval.")
    elif kind == "runtime":
        state["runtime"] = payload.get("payload")
        RUNTIME_OUT.write_text(json.dumps(state["runtime"], indent=2), encoding="utf-8")
        print(f"[+] Saved {RUNTIME_OUT}")
        hot = (state["runtime"] or {}).get("hottestMethods", [])[:20]
        print("\nTop LockGlyphTime methods by calls:")
        for row in hot:
            print(f"{row['calls']:>8}  {row['className']}  {row['selector']}  offset={row['offset']}")
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

    if not finished.wait(30):
        raise SystemExit("Timed out waiting for LockGlyphTime capture.")

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
    if not DYLIB_OUT.exists():
        raise SystemExit("Capture completed but LockGlyphTime.dylib was not written.")
    if not RUNTIME_OUT.exists():
        raise SystemExit("Capture completed but runtime profile was not written.")

    print("\n[+] COMPLETE")
    print(f"    Binary : {DYLIB_OUT}")
    print(f"    Runtime: {RUNTIME_OUT}")
    print("    Upload both files for binary/source-level repair analysis.")


if __name__ == "__main__":
    main()

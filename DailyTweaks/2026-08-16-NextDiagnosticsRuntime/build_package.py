#!/usr/bin/env python3
import argparse
import datetime
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(*args, **kwargs):
    return subprocess.check_call([str(x) for x in args], **kwargs)


def output(*args):
    return subprocess.check_output([str(x) for x in args], text=True, stderr=subprocess.DEVNULL)


def control(path: Path):
    try:
        text = output('dpkg-deb', '-f', path)
    except Exception:
        return {}
    fields = {}
    current = None
    for line in text.splitlines():
        if line[:1].isspace() and current:
            fields[current] += ' ' + line.strip()
            continue
        if ':' not in line:
            continue
        k, v = line.split(':', 1)
        current = k.strip()
        fields[current] = v.strip()
    return fields


def newer(a, b):
    if not b:
        return True
    return subprocess.run(['dpkg', '--compare-versions', a, 'gt', b]).returncode == 0


def ours(c):
    joined = ' '.join([c.get('Package', ''), c.get('Maintainer', ''), c.get('Author', '')]).lower()
    return (
        c.get('Package', '').startswith(('com.nextsolution.', 'com.zeshan.'))
        or 'next solution' in joined
        or 'nextsolution' in joined
        or 'zeshan' in joined
    )


def dependencies(c):
    result = []
    rx = re.compile(r'^\s*([A-Za-z0-9.+_-]+)')
    for group in c.get('Depends', '').split(','):
        m = rx.match(group.split('|', 1)[0])
        if m:
            result.append(m.group(1))
    return result


def slugify(name, pkg):
    value = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    return value or re.sub(r'[^a-z0-9]+', '-', pkg.lower()).strip('-')


def build_manifest(repo_main: Path, work: Path, version: str):
    debs = sorted((repo_main / 'debfiles').glob('*.deb'))
    latest = {}
    for deb in debs:
        c = control(deb)
        pkg = c.get('Package', '')
        if not pkg or c.get('Architecture', '') not in ('iphoneos-arm64e', 'all'):
            continue
        old = latest.get(pkg)
        if old is None or newer(c.get('Version', '0'), old[0].get('Version', '0')):
            latest[pkg] = (c, deb)

    cache = {}

    def inspect(pkg):
        if pkg in cache:
            return cache[pkg]
        result = {'dylibs': set(), 'bundles': set(), 'executables': set(), 'classes': set()}
        item = latest.get(pkg)
        if not item:
            cache[pkg] = result
            return result
        _, deb = item
        root = Path(tempfile.mkdtemp(prefix='nextdiag-deb-'))
        try:
            run('dpkg-deb', '-x', deb, root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for p in root.rglob('*'):
                s = str(p).replace('\\', '/')
                if '/MobileSubstrate/DynamicLibraries/' not in s or not p.is_file():
                    continue
                if p.suffix == '.dylib':
                    result['dylibs'].add(p.name)
                elif p.suffix == '.plist':
                    try:
                        data = plistlib.load(open(p, 'rb'))
                    except Exception:
                        continue
                    filt = data.get('Filter', {}) if isinstance(data, dict) else {}
                    if not isinstance(filt, dict):
                        continue
                    for key, dest in [('Bundles', 'bundles'), ('Executables', 'executables'), ('Classes', 'classes')]:
                        values = filt.get(key, [])
                        if isinstance(values, str):
                            values = [values]
                        if isinstance(values, list):
                            result[dest].update(v for v in values if isinstance(v, str) and v)
        finally:
            shutil.rmtree(root, ignore_errors=True)
        cache[pkg] = result
        return result

    def collect(pkg, depth=0, seen=None):
        seen = set() if seen is None else seen
        result = {'dylibs': set(), 'bundles': set(), 'executables': set(), 'classes': set()}
        if pkg in seen or depth > 3:
            return result
        seen.add(pkg)
        own = inspect(pkg)
        for key in result:
            result[key].update(own[key])
        c = latest.get(pkg, ({}, None))[0]
        for dep in dependencies(c):
            if dep not in latest:
                continue
            dc = latest[dep][0]
            if not ours(dc):
                continue
            if dc.get('Section', '').lower() in ('system', 'libraries', 'library') or '.runtime.' in dep:
                sub = collect(dep, depth + 1, seen)
                for key in result:
                    result[key].update(sub[key])
        return result

    entries = []
    used = {}
    all_bundles = set()
    all_exec = set()
    for pkg, (c, _) in sorted(latest.items(), key=lambda kv: (kv[1][0].get('Name', '').lower(), kv[0])):
        if c.get('Section', '').lower() != 'tweaks' or not ours(c):
            continue
        name = c.get('Name') or pkg
        gathered = collect(pkg)
        if gathered['classes'] and not gathered['bundles'] and not gathered['executables']:
            gathered['bundles'].add('com.apple.springboard')
        if not gathered['bundles'] and not gathered['executables'] and gathered['dylibs']:
            gathered['bundles'].add('com.apple.springboard')

        slug = slugify(name, pkg)
        if slug in used and used[slug] != pkg:
            suffix = re.sub(r'[^a-z0-9]+', '-', pkg.split('.')[-1].lower()).strip('-')
            slug = f'{slug}-{suffix}'
        used[slug] = pkg
        log_file = f'{slug}.log'
        if name.strip().lower() == 'module glass':
            slug = 'module-glass'
            log_file = 'module-glass.log'

        entry = {
            'slug': slug,
            'name': name,
            'packageID': pkg,
            'version': c.get('Version', ''),
            'logFile': log_file,
            'aliases': sorted(set([name, pkg, pkg.split('.')[-1], slug])),
            'dylibs': sorted(gathered['dylibs']),
            'bundles': sorted(gathered['bundles']),
            'executables': sorted(gathered['executables']),
        }
        entries.append(entry)
        all_bundles.update(gathered['bundles'])
        all_exec.update(gathered['executables'])

    all_bundles.add('com.apple.springboard')
    if len(entries) < 5:
        raise RuntimeError(f'Only {len(entries)} tweak packages discovered; refusing incomplete manifest')

    manifest = {
        'schemaVersion': 1,
        'runtimeVersion': version,
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'tweakCount': len(entries),
        'tweaks': entries,
    }
    manifest_path = work / 'manifest.plist'
    with open(manifest_path, 'wb') as f:
        plistlib.dump(manifest, f, sort_keys=False)
    with open(work / 'bundles.plist', 'wb') as f:
        plistlib.dump({'Filter': {'Bundles': sorted(all_bundles)}}, f, sort_keys=False)
    if all_exec:
        with open(work / 'executables.plist', 'wb') as f:
            plistlib.dump({'Filter': {'Executables': sorted(all_exec)}}, f, sort_keys=False)

    with open(work / 'manifest.txt', 'w') as f:
        f.write(f'Next Diagnostics Runtime {version}\nTweaks discovered: {len(entries)}\n\n')
        for e in entries:
            f.write(
                f"{e['name']} {e['version']}\n  {e['packageID']}\n"
                f"  slug={e['slug']} log={e['logFile']}\n"
                f"  dylibs={', '.join(e['dylibs']) or '<none>'}\n"
                f"  bundles={', '.join(e['bundles']) or '<none>'}\n"
                f"  executables={', '.join(e['executables']) or '<none>'}\n\n"
            )
    return manifest, sorted(all_bundles), sorted(all_exec)


def package(repo_main: Path, dylib: Path, out: Path, version: str):
    work = Path(tempfile.mkdtemp(prefix='nextdiag-generate-'))
    stage = Path(tempfile.mkdtemp(prefix='nextdiag-stage-'))
    try:
        manifest, bundles, executables = build_manifest(repo_main, work, version)
        dyn = stage / 'Library' / 'MobileSubstrate' / 'DynamicLibraries'
        app_support = stage / 'Library' / 'Application Support' / 'NextDiagnostics'
        debian = stage / 'DEBIAN'
        dyn.mkdir(parents=True, exist_ok=True)
        app_support.mkdir(parents=True, exist_ok=True)
        debian.mkdir(parents=True, exist_ok=True)
        out.mkdir(parents=True, exist_ok=True)

        shutil.copy2(dylib, dyn / 'NextDiagnosticsBundles.dylib')
        shutil.copy2(work / 'bundles.plist', dyn / 'NextDiagnosticsBundles.plist')
        if (work / 'executables.plist').exists():
            shutil.copy2(dylib, dyn / 'NextDiagnosticsExecutables.dylib')
            shutil.copy2(work / 'executables.plist', dyn / 'NextDiagnosticsExecutables.plist')
        shutil.copy2(work / 'manifest.plist', app_support / 'manifest.plist')

        (debian / 'control').write_text(f'''Package: com.nextsolution.nextdiagnostics.runtime\nName: Next Diagnostics Runtime\nVersion: {version}\nArchitecture: iphoneos-arm64e\nDescription: Shared RootHide diagnostic runtime for Next Solution tweaks. Idle until Next Log starts a focused capture, then reports target-process injection and loaded tweak dylibs.\nMaintainer: Next Solution\nAuthor: Next Solution - zeshan0727\nSection: System\nDepends: firmware (>= 15.0), mobilesubstrate\nPriority: optional\nHomepage: https://nextsolution.cc/\nTag: role::cydia\n''')
        postinst = debian / 'postinst'
        postinst.write_text('''#!/bin/sh\nset +e\nDST="/var/mobile/Library/Preferences/com.nextsolution.nextdiagnostics.manifest.plist"\nmkdir -p "/var/mobile/Library/Preferences"\nSRC=""\nfor P in "/Library/Application Support/NextDiagnostics/manifest.plist" "/var/jb/Library/Application Support/NextDiagnostics/manifest.plist"; do\n  if [ -f "$P" ]; then SRC="$P"; break; fi\ndone\nif [ -z "$SRC" ] && [ -d /var/containers/Bundle/tweaksupport ]; then\n  SRC="$(find /var/containers/Bundle/tweaksupport -path '*/Library/Application Support/NextDiagnostics/manifest.plist' -type f 2>/dev/null | head -1)"\nfi\nif [ -n "$SRC" ] && [ -f "$SRC" ]; then\n  cp "$SRC" "$DST"\n  chmod 0644 "$DST"\n  chown mobile:mobile "$DST" 2>/dev/null || true\nfi\nkillall -9 SpringBoard 2>/dev/null || true\nexit 0\n''')
        os.chmod(postinst, 0o755)

        deb = out / f'NextDiagnosticsRuntime_{version}_RootHide.deb'
        run('dpkg-deb', '--root-owner-group', '-Zxz', '-b', stage, deb)
        shutil.copy2(work / 'manifest.plist', out / 'NextDiagnostics-manifest.plist')
        shutil.copy2(work / 'manifest.txt', out / 'NextDiagnostics-manifest.txt')
        sha = output('shasum', '-a', '256', deb)
        (out / 'SHA256.txt').write_text(sha)
        print(f"Built {deb.name}: {manifest['tweakCount']} tweak profiles, {len(bundles)} bundle targets, {len(executables)} executable targets")
        return deb
    finally:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(stage, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo-main', required=True)
    ap.add_argument('--dylib', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--version', required=True)
    args = ap.parse_args()
    package(Path(args.repo_main), Path(args.dylib), Path(args.output), args.version)


if __name__ == '__main__':
    main()

from pathlib import Path

p = Path('source/ModuleGlass/Tweak.m')
s = p.read_text()

old = '        shell.backgroundColor=[UIColor colorWithWhite:0.0 alpha:0.26];'
new = '        shell.backgroundColor=UIColor.clearColor;'
if s.count(old) != 1:
    raise SystemExit(f'expected exactly one slider shell background line, found {s.count(old)}')
s = s.replace(old, new, 1)

old_marker = 'ModuleGlassRuntime 1.1.9 Unified Slider Shell Renderer loaded'
new_marker = 'ModuleGlassRuntime 1.1.10 Transparent Slider Shell Renderer loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f'expected exactly one 1.1.9 runtime marker, found {s.count(old_marker)}')
s = s.replace(old_marker, new_marker, 1)

p.write_text(s)

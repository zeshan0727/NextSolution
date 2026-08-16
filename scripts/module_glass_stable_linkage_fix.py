from pathlib import Path

p = Path('source/ModuleGlass/Tweak.mm')
if not p.exists():
    raise SystemExit('Tweak.mm missing; run stable migration first')

t = p.read_text()
old = 'extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);'
new = 'extern "C" void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);'

if new in t:
    print('MSHookMessageEx already has C linkage')
elif old in t:
    t = t.replace(old, new, 1)
    p.write_text(t)
    print('fixed MSHookMessageEx C linkage')
else:
    raise SystemExit('MSHookMessageEx declaration not found')

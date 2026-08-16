from pathlib import Path

# First apply the reviewed 1.1.1 renderer transformation.
base = Path('scripts/module_glass_clean_static_renderer_1_1_1.py')
ns = {'__name__': '__main__'}
exec(compile(base.read_text(), str(base), 'exec'), ns, ns)

p = Path('source/ModuleGlass/Tweak.mm')
t = p.read_text()

# Remove state keys that existed only for the old recursive alpha/layer suppression system.
t = t.replace('static char MGVolumeOriginalAlphaKey;\n', '')
t = t.replace('static char MGBrightnessOriginalLayerOpacityKey;\n', '')

# Remove the complete legacy image-first suppression subsystem.  Do not silence warnings;
# make it impossible for future edits to accidentally call these destructive routines.
start = t.find('// Image-first helpers validated on Volume and now shared by all mapped compact modules.')
end = t.find('static UIColor *MGVolumeColorFromHex', start)
if start < 0 or end < 0:
    raise SystemExit('legacy suppression subsystem anchors missing')
t = t[:start] + t[end:]

# The old value-reader/clamp existed only to crop Volume artwork by slider value.
start = t.find('static CGFloat MGClamp01(')
end = t.find('static BOOL MGViewTreeContainsForeground', start)
if start < 0 or end < 0:
    raise SystemExit('legacy value-mask helpers anchors missing')
t = t[:start] + t[end:]

# Hard assertions: none of the legacy mutators may remain in source.
for forbidden in (
    'MGRestoreVolumeVisuals',
    'MGApplyVolumeImageMode',
    'MGBrightnessObscuringVisual',
    'MGApplyBrightnessImageMode',
    'MGRestoreBrightnessLayers',
    'MGBrightnessObscuringLayer',
    'MGApplyBrightnessLayerMode',
    'MGStableSliderValueFraction',
    'MGApplyStableVolumeValueMask',
    'MGVolumeValueSizedFrame',
):
    if forbidden in t:
        raise SystemExit(f'forbidden legacy renderer remains: {forbidden}')

p.write_text(t)
print('cleaned legacy suppression/value-mask subsystem from Module Glass 1.1.1')

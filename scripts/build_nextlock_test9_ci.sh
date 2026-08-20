#!/bin/bash
set -euo pipefail

ROOT="$PWD"
P="$RUNNER_TEMP/nextlock-feature/source/NextLockPerfFix"
T="$RUNNER_TEMP/theos-rh"
STAGE="$RUNNER_TEMP/nextlock-stage"
FIXSTAGE="$RUNNER_TEMP/fix-stage"
OUT="$RUNNER_TEMP/out"
mkdir -p "$OUT"

git fetch origin feature/nextlock-photo-content-modes
git worktree add "$RUNNER_TEMP/nextlock-feature" FETCH_HEAD
cp "$P/TweakTest7.m" "$P/TweakTest9.m"

python3 - "$P/TweakTest9.m" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text()

t=t.replace('NextLockPerfFix 1.1.5-test7 refined-full-photo 2048px test5-cpu auto-stretch-full-cutcrop','NextLockPerfFix 1.1.5-test9 preserve-all-style free-photo-position refined-full-picker')
t=t.replace('static const uintptr_t kArm64CallbackBlockOffset   = 0xBC30;\n','')
t=t.replace('static const uintptr_t kArm64eCallbackBlockOffset  = 0xBDD4;\n','')
t=t.replace('static void (*NLOriginalHotCallbackBlock)(void *blockObject) = NULL;\n','')
t=t.replace('static void NLSuppressHotCallback(void *blockObject) {\n    (void)blockObject;\n}\n\n','')
t=t.replace('static BOOL NLInstalled = NO;\n','static BOOL NLInstalled = NO;\nstatic volatile uint8_t *NLHotCallbackFlag = NULL;\n',1)
fn='static void NLPhotosWithContentModes(id host) {\n    if (NLOriginalPhotos == NULL) return;\n'
if fn not in t: raise SystemExit('photo function anchor missing')
t=t.replace(fn,fn+'\n    if (NLHotCallbackFlag != NULL && *NLHotCallbackFlag != 0) return;\n',1)
t=t.replace('    uintptr_t callbackOffset = isArm64e ? kArm64eCallbackBlockOffset : kArm64CallbackBlockOffset;\n','')
hook='    MSHookFunction((void *)((uintptr_t)mh + callbackOffset),\n                   (void *)&NLSuppressHotCallback,\n                   (void **)&NLOriginalHotCallbackBlock);\n'
if hook not in t: raise SystemExit('callback hook anchor missing')
t=t.replace(hook,'')
a='    uintptr_t contentModeStub = isArm64e ? kArm64eSetContentModeStub : kArm64SetContentModeStub;\n'
if a not in t: raise SystemExit('contentMode anchor missing')
t=t.replace(a,a+'\n    if (isArm64e) NLHotCallbackFlag = (volatile uint8_t *)((uintptr_t)mh + 0x18EF4);\n',1)
t=t.replace('        NLOriginalHotCallbackBlock != NULL &&\n','')
t=t.replace('Test7 SpringBoard hooks installed (%s): Test5 CPU fix + refined photo modes','Test9 SpringBoard hooks installed (%s): full styling + free photo positioning')
t=t.replace('Test7 refined full-photo picker installed','Test9 full-photo no-crop picker installed')

a='static BOOL NLFrameHasPhoto[4] = {NO, NO, NO, NO};\n'
if a not in t: raise SystemExit('frame arrays missing')
t=t.replace(a,a+'static CGFloat NLFreeXPercent[4] = {50,50,50,50};\nstatic CGFloat NLFreeYPercent[4] = {30,30,30,30};\n',1)

a='    BOOL hasPhoto[4] = {NO, NO, NO, NO};\n\n    for (NSUInteger i = 0; i < 4; i++) {'
if a not in t: raise SystemExit('reload locals missing')
t=t.replace(a,'    BOOL hasPhoto[4] = {NO, NO, NO, NO};\n    NSInteger freeX[4] = {50,50,50,50};\n    NSInteger freeY[4] = {30,30,30,30};\n\n    for (NSUInteger i = 0; i < 4; i++) {',1)

a='        hasPhoto[i] = NLPhotoDataExistsForFrame(i);\n        CFRelease(modeKey);\n        CFRelease(enabledKey);'
if a not in t: raise SystemExit('reload loop missing')
r='        hasPhoto[i] = NLPhotoDataExistsForFrame(i);\n        CFStringRef xKey=CFStringCreateWithFormat(kCFAllocatorDefault,NULL,CFSTR("photoFrame%luFreeXPercent"),(unsigned long)(i+1));\n        CFStringRef yKey=CFStringCreateWithFormat(kCFAllocatorDefault,NULL,CFSTR("photoFrame%luFreeYPercent"),(unsigned long)(i+1));\n        freeX[i]=MAX(0,MIN(100,NLCopyIntegerPref(xKey,50)));\n        freeY[i]=MAX(0,MIN(100,NLCopyIntegerPref(yKey,30)));\n        CFRelease(xKey); CFRelease(yKey);\n        CFRelease(modeKey);\n        CFRelease(enabledKey);'
t=t.replace(a,r,1)

a='        NLFrameHasPhoto[i] = hasPhoto[i];\n'
if a not in t: raise SystemExit('mode store missing')
t=t.replace(a,a+'        NLFreeXPercent[i]=(CGFloat)freeX[i];\n        NLFreeYPercent[i]=(CGFloat)freeY[i];\n',1)

helper='''static void NLApplyFreeScreenPosition(UIImageView *view, CGFloat xPercent, CGFloat yPercent) {
    if (view == nil || view.superview == nil) return;
    CGFloat xp=MAX(0.0,MIN(100.0,xPercent))/100.0;
    CGFloat yp=MAX(0.0,MIN(100.0,yPercent))/100.0;
    UIWindow *window=view.window;
    UIView *superview=view.superview;
    if (window != nil) {
        CGRect b=window.bounds;
        CGPoint q=CGPointMake(CGRectGetMinX(b)+CGRectGetWidth(b)*xp,
                              CGRectGetMinY(b)+CGRectGetHeight(b)*yp);
        view.center=[superview convertPoint:q fromView:window];
    } else {
        CGRect b=superview.bounds;
        view.center=CGPointMake(CGRectGetMinX(b)+CGRectGetWidth(b)*xp,
                                CGRectGetMinY(b)+CGRectGetHeight(b)*yp);
    }
}

'''
if 'static void NLPhotosWithContentModes(id host) {' not in t: raise SystemExit('helper insertion missing')
t=t.replace('static void NLPhotosWithContentModes(id host) {',helper+'static void NLPhotosWithContentModes(id host) {',1)

a='    BOOL hasPhoto[4] = {NO, NO, NO, NO};\n\n    os_unfair_lock_lock(&NLModeLock);'
if a not in t: raise SystemExit('photo local arrays missing')
t=t.replace(a,'    BOOL hasPhoto[4] = {NO, NO, NO, NO};\n    CGFloat freeX[4] = {50,50,50,50};\n    CGFloat freeY[4] = {30,30,30,30};\n\n    os_unfair_lock_lock(&NLModeLock);',1)

a='        hasPhoto[i] = NLFrameHasPhoto[i];\n'
if a not in t: raise SystemExit('photo cache copy missing')
t=t.replace(a,a+'        freeX[i]=NLFreeXPercent[i];\n        freeY[i]=NLFreeYPercent[i];\n',1)

a='            NLApplyPhotoModeToView(NLCapturedViews[i], modes[i]);\n'
if a not in t: raise SystemExit('photo apply missing')
t=t.replace(a,a+'            NLApplyFreeScreenPosition(NLCapturedViews[i], freeX[i], freeY[i]);\n',1)

if 'NLSuppressHotCallback' in t or 'NLOriginalHotCallbackBlock' in t: raise SystemExit('old callback suppress remains')
if 'NLApplyFreeScreenPosition' not in t or 'photoFrame%luFreeXPercent' not in t: raise SystemExit('free position code missing')
p.write_text(t)
PY

sed -i '' 's/NextLockPerfFix_FILES = TweakTest7.m/NextLockPerfFix_FILES = TweakTest9.m/' "$P/Makefile"
grep -q 'INSTALL_TARGET_PROCESSES = SpringBoard Preferences' "$P/Makefile"
grep -q 'com.apple.Preferences' "$P/NextLockPerfFix.plist"

git init "$T"
git -C "$T" remote add origin https://github.com/roothide/theos.git
git -C "$T" fetch --depth 1 origin 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" checkout --detach 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" submodule update --init --recursive --depth 1
sed -i '' 's/^Architecture: iphoneos-arm64$/Architecture: iphoneos-arm64e/' "$P/control"
export THEOS="$T"
export THEOS_PACKAGE_SCHEME=roothide
rm -rf "$P/.theos" "$P/packages"
make -C "$P" clean package FINALPACKAGE=1
FIX_DEB=$(find "$P/packages" -type f -name '*.deb' -print -quit)
test -n "$FIX_DEB"

dpkg-deb -R "$ROOT/transfer/files/NextLock/1.1.4/NextLock_1.1.4_RootHide.deb" "$STAGE"
dpkg-deb -x "$FIX_DEB" "$FIXSTAGE"
LOCK=$(find "$STAGE" -name LockGlyphTime.dylib -print -quit)
SHIM=$(find "$FIXSTAGE" -name NextLockPerfFix.dylib -print -quit)
SHIMPLIST=$(find "$FIXSTAGE" -name NextLockPerfFix.plist -print -quit)
ORIGINAL_SHA=$(shasum -a 256 "$LOCK" | awk '{print $1}')
cp "$SHIM" "$(dirname "$LOCK")/NextLockPerfFix.dylib"
cp "$SHIMPLIST" "$(dirname "$LOCK")/NextLockPerfFix.plist"
test "$ORIGINAL_SHA" = "$(shasum -a 256 "$LOCK" | awk '{print $1}')"

python3 - "$STAGE" <<'PY'
from pathlib import Path
import plistlib,sys,re
stage=Path(sys.argv[1]); b=stage/'Library/PreferenceBundles/LockGlyphTimePrefs.bundle'
for i in range(1,5):
    p=b/f'PhotoFrame{i}.plist'
    with p.open('rb') as f: d=plistlib.load(f)
    remove={f'photoFrame{i}AnchorTarget',f'photoFrame{i}Position',f'photoFrame{i}OffsetX',f'photoFrame{i}OffsetY',f'photoFrame{i}ContentMode',f'photoFrame{i}FreeXPercent',f'photoFrame{i}FreeYPercent'}
    items=[]; pos=None
    for x in d['items']:
        if x.get('key') in remove: continue
        if x.get('label')=='POSITION' and x.get('cell')=='PSGroupCell':
            x=dict(x); x['footerText']='Free screen position. The frame is not anchored to Time or Date. X moves left-to-right; Y moves top-to-bottom.'; pos=len(items)+1
        items.append(x)
    mode={'PostNotification':'com.nextsolution.lockglyphtime/ReloadPrefs','cell':'PSLinkListCell','default':0,'defaults':'com.nextsolution.lockglyphtime','detail':'PSListItemsController','key':f'photoFrame{i}ContentMode','label':'Photo Display','validTitles':['Auto (Recommended)','Stretch','Full Photo','Cut / Crop'],'validValues':[0,1,2,3]}
    items.insert(4 if len(items)>=4 else len(items),mode)
    if pos is None: pos=len(items)
    if pos>=4: pos+=1
    def slider(k,l,dv):
        return {'PostNotification':'com.nextsolution.lockglyphtime/ReloadPrefs','cell':'PSSliderCell','default':dv,'defaults':'com.nextsolution.lockglyphtime','key':k,'label':l,'min':0,'max':100,'showValue':True}
    items.insert(pos,slider(f'photoFrame{i}FreeXPercent','Horizontal Position',50))
    items.insert(pos+1,slider(f'photoFrame{i}FreeYPercent','Vertical Position',30))
    d['items']=items
    with p.open('wb') as f: plistlib.dump(d,f,fmt=plistlib.FMT_XML,sort_keys=False)

c=stage/'DEBIAN/control'; t=c.read_text()
t=re.sub(r'^Version: .*$', 'Version: 1.1.5~cpu9', t, flags=re.M)
desc='Description: NextLock 1.1.5 CPU-fix Test 9. Keeps Test 8 time/date styling, targeted CPU fix and uncropped photo picker. Removes Time/Date anchor and placement controls from all four photo frames and adds independent whole-screen X/Y positioning.'
t=re.sub(r'^Description: .*$',desc,t,flags=re.M) if re.search(r'^Description: .*$',t,re.M) else t+'\n'+desc+'\n'
c.write_text(t)
PY

OUTDEB="$OUT/NextLock_1.1.5_CPUFix_Test9_FreePosition_RootHide.deb"
dpkg-deb -b "$STAGE" "$OUTDEB"
test "$(dpkg-deb -f "$OUTDEB" Package)" = 'com.nextsolution.lockglyphtime'
test "$(dpkg-deb -f "$OUTDEB" Version)" = '1.1.5~cpu9'
X=$(mktemp -d); dpkg-deb -x "$OUTDEB" "$X"
LOCK2=$(find "$X" -name LockGlyphTime.dylib -print -quit)
FIX2=$(find "$X" -name NextLockPerfFix.dylib -print -quit)
test "$(shasum -a 256 "$LOCK2" | awk '{print $1}')" = "$ORIGINAL_SHA"
strings -a "$FIX2" | grep -q '1.1.5-test9 preserve-all-style free-photo-position'
for i in 1 2 3 4; do
  Q="$X/Library/PreferenceBundles/LockGlyphTimePrefs.bundle/PhotoFrame${i}.plist"
  plutil -p "$Q" | grep -q "photoFrame${i}FreeXPercent"
  plutil -p "$Q" | grep -q "photoFrame${i}FreeYPercent"
  ! plutil -p "$Q" | grep -q "photoFrame${i}AnchorTarget"
  ! plutil -p "$Q" | grep -q "photoFrame${i}Position"
done
shasum -a 256 "$OUTDEB" > "$OUT/SHA256SUMS.txt"
echo "OUTDEB=$OUTDEB" >> "$GITHUB_ENV"
echo "OUT_SHA=$(awk '{print $1}' "$OUT/SHA256SUMS.txt")" >> "$GITHUB_ENV"
echo "SHA_FILE=$OUT/SHA256SUMS.txt" >> "$GITHUB_ENV"

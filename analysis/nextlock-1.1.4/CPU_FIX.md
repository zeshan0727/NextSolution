# NextLock 1.1.4 SpringBoard CPU fix

## Confirmed device-side cause

Frida profiling on the affected iOS 16.0 RootHide device identified one dominant SpringBoard CPU thread. Its repeated execution path was CoreGraphics/vImage bitmap conversion, and synchronous interception showed `LockGlyphTime.dylib` in the injected caller chain. Disabling only `LockGlyphTime.dylib` immediately returned SpringBoard CPU to normal.

## Binary-level root cause

The 1.1.4 `LockGlyphTime.dylib` transparency classifier converts each custom `UIImage` to a maximum 32x32 RGBA bitmap using `CGBitmapContextCreate`, `CGContextDrawImage` and interpolation quality 2, then scans alpha bytes to decide whether the photo contains transparency. The same classifier is reached repeatedly during lock-screen frame layout/update, so the same immutable image is rendered and scanned over and over. This matches the device trace repeatedly landing in `vImageCopyBuffer`, `vImageConverterConvert`, `vImageDebug_CheckDestBuffer` and related CoreGraphics/vImage functions.

## Fix

The original classifier semantics are preserved, but its result is memoized per immutable `UIImage` instance with non-retaining Objective-C associated-object markers. The first use of a photo executes the same 32x32 transparency classification. Later layout passes return the cached boolean in O(1) and do not re-render the same image through CoreGraphics/vImage.

The temporary bitmap is also moved from `calloc/free` to a bounded 4096-byte stack buffer (`32 * 32 * 4`) while keeping `CGContextClearRect`, the original pixel format (`0x4001`), interpolation quality, and alpha threshold (`< 250`).

No NextLock feature is removed. The four simultaneous photo/sticker frames remain intact, including per-frame image, width, height, anchor target, placement, and X/Y offsets. Transparent sticker detection and opaque-photo rounded-square behavior remain enabled.

## Patch safety

Both arm64 and arm64e slices are patched in-place inside the original classifier's code window. The one-instruction veneer immediately following the function is preserved byte-for-byte. The existing Mach-O layout, imports, load commands, preference bundle, frame plists, and package identifier are unchanged. SHA-1 and SHA-256 CodeDirectory page hashes are recomputed after patching.

The test package version is 1.1.5. It should not be published until device validation confirms normal SpringBoard CPU and all four frame/transparency behaviors.
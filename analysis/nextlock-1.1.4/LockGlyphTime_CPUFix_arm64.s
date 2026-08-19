.text
.org 0xae18
.p2align 2
L_func_start:
L_key_true:
    stp x29, x30, [sp, #-0x40]!
L_key_false:
    stp x19, x20, [sp, #0x10]
    stp x21, x22, [sp, #0x20]
    stp x23, x24, [sp, #0x30]
    mov x29, sp
    sub sp, sp, #1, lsl #12
    mov x19, x0

    mov x0, x19
    adr x1, L_key_true
    bl L_objc_getAssociatedObject
    cbnz x0, L_return_true

    mov x0, x19
    adr x1, L_key_false
    bl L_objc_getAssociatedObject
    cbnz x0, L_return_false

    mov x0, x19
    bl L_objc_CGImage
    mov x20, x0
    cbz x20, L_cache_false

    mov x0, x20
    bl L_CGImageGetAlphaInfo
    sub w8, w0, #1
    cmp w8, #3
    b.hi L_cache_false

    mov x0, x20
    bl L_CGImageGetWidth
    cmp x0, #32
    mov x8, #32
    csel x21, x0, x8, lo

    mov x0, x20
    bl L_CGImageGetHeight
    cmp x0, #32
    mov x8, #32
    csel x22, x0, x8, lo

    bl L_CGColorSpaceCreateDeviceRGB
    mov x23, x0
    mov x0, sp
    mov x1, x21
    mov x2, x22
    mov w3, #8
    lsl x4, x21, #2
    mov x5, x23
    mov w6, #0x4001
    bl L_CGBitmapContextCreate
    mov x24, x0
    mov x0, x23
    bl L_CGColorSpaceRelease
    cbz x24, L_cache_false

    fmov d0, xzr
    fmov d1, xzr
    ucvtf d2, x21
    ucvtf d3, x22
    mov x0, x24
    bl L_CGContextClearRect

    mov x0, x24
    mov w1, #2
    bl L_CGContextSetInterpolationQuality

    fmov d0, xzr
    fmov d1, xzr
    ucvtf d2, x21
    ucvtf d3, x22
    mov x0, x24
    mov x1, x20
    bl L_CGContextDrawImage

    mul x8, x22, x21
    mov x9, sp
    add x8, x9, x8, lsl #2
    add x9, x9, #3
L_scan:
    cmp x9, x8
    b.hs L_opaque
    ldrb w10, [x9], #4
    cmp w10, #250
    b.hs L_scan
    mov w20, #1
    b L_release_context
L_opaque:
    mov w20, #0
L_release_context:
    mov x0, x24
    bl L_CGContextRelease
    b L_cache_result

L_cache_false:
    mov w20, #0
L_cache_result:
    adr x1, L_key_false
    cbz w20, L_have_key
    adr x1, L_key_true
L_have_key:
    mov x0, x19
    mov x2, x19
    mov x3, #0
    bl L_objc_setAssociatedObject
    mov w0, w20
    b L_epilogue

L_return_true:
    mov w0, #1
    b L_epilogue
L_return_false:
    mov w0, #0
L_epilogue:
    add sp, sp, #1, lsl #12
    ldp x23, x24, [sp, #0x30]
    ldp x21, x22, [sp, #0x20]
    ldp x19, x20, [sp, #0x10]
    ldp x29, x30, [sp], #0x40
    ret
L_func_end:

.org 0xc820
L_CGBitmapContextCreate:
.org 0xc82c
L_CGColorSpaceCreateDeviceRGB:
.org 0xc838
L_CGColorSpaceRelease:
.org 0xc844
L_CGContextClearRect:
.org 0xc850
L_CGContextDrawImage:
.org 0xc85c
L_CGContextRelease:
.org 0xc868
L_CGContextSetInterpolationQuality:
.org 0xc874
L_CGImageGetAlphaInfo:
.org 0xc880
L_CGImageGetHeight:
.org 0xc88c
L_CGImageGetWidth:
.org 0xc9e8
L_objc_getAssociatedObject:
.org 0xca6c
L_objc_setAssociatedObject:
.org 0xcac0
L_objc_CGImage:
    nop

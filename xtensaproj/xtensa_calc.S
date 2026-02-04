    .text
    .align 4
    .global emu8086_xtensa
    .type   emu8086_xtensa, @function

/*void emu8086_xtensa(
 * uint32_t w,// a2
  *uint32_t h,// a3
  *uint32_t bpp,// a4
  *uint32_t apb_khz,// a5
  *uint32_t scl_khz,// a6
  *ComputeOut* out// a7
*);
 *
 *ComputeOut layout (C):
 *out->frame_bytes  [0]
 *out->total_cycles [4]
 *out->high_cycles  [8]
 *out->low_cycles   [12]
 */

emu8086_xtensa:
    entry   a1, 32
/* things we need after division call */
    mov     a8, a2 /*w */
    mov     a9, a3 /*h */
    mov     a10, a4 /*bpp */
    mov     a11, a7 /*out ptr */

/* frame_bytes = w * h * bpp */
/* we compute 64-bit frame bytes split into lowhigh to match C struct
       ComputeOut:
         [0]  frame_bytes_lo (u32)
         [4]  frame_bytes_hi (u32) 
         [8]  total_cycles   (u16)
         [10] high_cycles    (u16)
         [12] low_cycles     (u16)
    */

    /*64-bit WH = w*h */
    mull    a12, a8, a9     /* a12 = lo32(w*h) */
    muluh   a13, a8, a9     /* a13 = hi32(w*h) */

    /*64-bit FB = (WH) * bpp
          fb_lo = lo32( a12*bpp )
          fb_hi = hi32(a12*bpp) + lo32(a13*bpp)
    */
    mull    a14, a12, a10  /* a14 = fb_lo */
    muluh   a15, a12, a10  /* a15 = hi32(a12*bpp) */
    mull    a2,  a13, a10 /* a2  = lo32(a13*bpp) */
    add     a15, a15, a2 /*a15 = fb_hi */

    s32i    a14, a11, 0 /* out frame_bytes_lo */
    s32i    a15, a11, 4 /* out frame_bytes_hi */

    /* total_cycles = apb_khz / scl_khz
       Use libgcc unsigned divide helper to avoid relying on optional div ISA.
       __udivsi3(uint32_t, uint32_t) -> uint32_t result in a2
    */
    beqz    a6, 1f  /* if scl_khz == 0, total = 0 */

    mov     a2, a5 /* num*/
    mov     a3, a6 /*denominator*/
    call8   __udivsi3
    mov     a13, a2 /* total_cycles (u32) */
    j       2f

1:
    movi    a13, 0

2:
    /*total_cycles to 0xFFFF cuz C stores it as uint16_t */
    movi    a14, -1
    extui   a14, a14, 0, 16     /* a14 = 0x0000FFFF */
    bltu    a13, a14, 3f
    mov     a13, a14
3:
/* high_cycles = total_cycles >> 1 */
    srli    a15, a13, 1
/* low_cycles = total_cycles - high_cycles */
    sub     a2, a13, a15
/*store as 16-bit fields */
    s16i    a13, a11, 8 /*out total_cycles */
    s16i    a15, a11, 10 /* out high_cycles  */
    s16i    a2,  a11, 12 /* out low_cycles   */

    retw

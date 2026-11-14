/*
 * asm-libp2p for ARM64 (AAPCS64): libp2p over TCP for an Ethereum consensus
 * client: Noise, multistream-select, yamux, mplex, streams and gossipsub.
 * Requirements: docs/reference/. Layouts: include/libp2p.inc, include/state.inc.
 *
 * One object: this file includes the other parts of the core. Hashes,
 * ciphers and keys go through asm-crypto.
 */
.set ISA_ARM64, 1
.include "crypto.inc"
.include "hmac.inc"
.include "chacha20.inc"
.include "secp256k1.inc"
.include "sha512.inc"
.include "ed25519.inc"
.include "libp2p.inc"
.include "state.inc"
.include "platform.inc"
.include "frame.inc"

/* ---------------------------------------------------------------- Byte helpers */

/* libp2p_copy(dst, src, n) -> dst + n. dst is below src, or the regions do not overlap. */
LOCAL_FUNCTION libp2p_copy
    UNWIND_END_PROLOGUE
1:  cmp     x2, #8
    b.lo    2f
    ldr     x3, [x1], #8
    str     x3, [x0], #8
    sub     x2, x2, #8
    b       1b
2:  cbz     x2, 3f
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       2b
3:  ret
END_FUNCTION libp2p_copy

/* libp2p_zero(dst, n) -> dst + n. */
LOCAL_FUNCTION libp2p_zero
    UNWIND_END_PROLOGUE
1:  cmp     x1, #8
    b.lo    2f
    str     xzr, [x0], #8
    sub     x1, x1, #8
    b       1b
2:  cbz     x1, 3f
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       2b
3:  ret
END_FUNCTION libp2p_zero

/* libp2p_equal(a, b, n) -> 1 when the n bytes at a and b are equal, else 0. */
LOCAL_FUNCTION libp2p_equal
    UNWIND_END_PROLOGUE
    mov     x4, #0
1:  cbz     x2, 2f
    ldrb    w3, [x0], #1
    ldrb    w5, [x1], #1
    eor     w3, w3, w5
    orr     x4, x4, x3
    sub     x2, x2, #1
    b       1b
2:  cmp     x4, #0
    cset    x0, eq
    ret
END_FUNCTION libp2p_equal

/* libp2p_compare(a, alen, b, blen) -> 1 when the byte strings are equal (same length and bytes), else 0. */
LOCAL_FUNCTION libp2p_compare
    UNWIND_END_PROLOGUE
    mov     x4, x0
    mov     x0, #0
    cmp     x1, x3
    b.ne    9f
    mov     x5, #0
1:  cbz     x1, 2f
    ldrb    w6, [x4], #1
    ldrb    w7, [x2], #1
    eor     w6, w6, w7
    orr     x5, x5, x6
    sub     x1, x1, #1
    b       1b
2:  cmp     x5, #0
    cset    x0, eq
9:  ret
END_FUNCTION libp2p_compare

/* libp2p_hash(p, n) -> the FNV-1a hash of the n bytes at p. */
LOCAL_FUNCTION libp2p_hash
    UNWIND_END_PROLOGUE
    MOV64   x2, 0xCBF29CE484222325
    MOV64   x3, 0x100000001B3
1:  cbz     x1, 2f
    ldrb    w4, [x0], #1
    eor     x2, x2, x4
    mul     x2, x2, x3
    sub     x1, x1, #1
    b       1b
2:  mov     x0, x2
    ret
END_FUNCTION libp2p_hash

/* ---------------------------------------------------------------- Heap: a buddy allocator over the heap part */

/*
 * libp2p_heap_alloc(n) -> the state offset of n usable bytes, or 0 when no
 * block is free. Blocks are 2^order bytes with a 16-byte header; free
 * blocks sit on one doubly linked list for each order. A leaf.
 * x8 heap base, x9 order, x10 top order, x11 order found, x12 block.
 */
LOCAL_FUNCTION libp2p_heap_alloc
    UNWIND_END_PROLOGUE
    ldr     x8, [x27, #ST_HEAP_OFF]
    add     x8, x27, x8
    ldr     x10, [x27, #ST_HEAP_SIZE]
    rbit    x10, x10
    clz     x10, x10                        /* the top order */
    add     x0, x0, #HB_HEADER
    sub     x1, x0, #1
    clz     x1, x1
    mov     x9, #64
    sub     x9, x9, x1                      /* the order that holds n + 16 */
    cmp     x9, #HEAP_MIN_ORDER
    mov     x1, #HEAP_MIN_ORDER
    csel    x9, x1, x9, lo
    mov     x0, #0
    cmp     x9, x10
    b.hi    9f
    mov     x11, x9
    add     x13, x27, #ST_HEAP_FREE
1:  cmp     x11, x10
    b.hi    9f
    ldr     x12, [x13, x11, lsl #3]
    cmn     x12, #1
    b.ne    2f
    add     x11, x11, #1
    b       1b
2:  add     x14, x8, x12                    /* take the block off its list */
    ldr     x15, [x14, #HB_NEXT]
    str     x15, [x13, x11, lsl #3]
    cmn     x15, #1
    b.eq    3f
    add     x16, x8, x15
    mov     x17, #NONE
    str     x17, [x16, #HB_PREV]
3:  cmp     x11, x9                         /* split down to the order asked for */
    b.ls    4f
    sub     x11, x11, #1
    mov     x15, #1
    lsl     x15, x15, x11
    add     x15, x12, x15                   /* the upper half becomes free */
    add     x16, x8, x15
    str     w11, [x16, #HB_ORDER]
    mov     w17, #1
    str     w17, [x16, #HB_FREE]
    ldr     x17, [x13, x11, lsl #3]
    str     x17, [x16, #HB_NEXT]
    mov     x1, #NONE
    str     x1, [x16, #HB_PREV]
    cmn     x17, #1
    b.eq    31f
    add     x1, x8, x17
    str     x15, [x1, #HB_PREV]
31: str     x15, [x13, x11, lsl #3]
    b       3b
4:  str     w9, [x14, #HB_ORDER]
    str     wzr, [x14, #HB_FREE]
    mov     x15, #1
    lsl     x15, x15, x9
    ldr     x16, [x27, #ST_HEAP_USED]
    add     x16, x16, x15
    str     x16, [x27, #ST_HEAP_USED]
    sub     x0, x14, x27
    add     x0, x0, #HB_HEADER
9:  ret
END_FUNCTION libp2p_heap_alloc

/*
 * libp2p_heap_free(offset): returns a block from libp2p_heap_alloc, joining it with
 * its free buddies. Offset 0 does nothing. A leaf.
 * x8 heap base, x9 order, x10 top order, x12 block, x13 lists.
 */
LOCAL_FUNCTION libp2p_heap_free
    UNWIND_END_PROLOGUE
    cbz     x0, 9f
    ldr     x8, [x27, #ST_HEAP_OFF]
    sub     x12, x0, x8
    sub     x12, x12, #HB_HEADER
    add     x8, x27, x8
    ldr     x10, [x27, #ST_HEAP_SIZE]
    rbit    x10, x10
    clz     x10, x10
    add     x13, x27, #ST_HEAP_FREE
    add     x14, x8, x12
    ldr     w9, [x14, #HB_ORDER]
    mov     x15, #1
    lsl     x15, x15, x9
    ldr     x16, [x27, #ST_HEAP_USED]
    sub     x16, x16, x15
    str     x16, [x27, #ST_HEAP_USED]
1:  cmp     x9, x10
    b.hs    3f
    mov     x15, #1
    lsl     x15, x15, x9
    eor     x15, x12, x15                   /* the buddy */
    add     x16, x8, x15
    ldr     w17, [x16, #HB_FREE]
    cbz     w17, 3f
    ldr     w17, [x16, #HB_ORDER]
    cmp     x17, x9
    b.ne    3f
    ldr     x1, [x16, #HB_NEXT]             /* take the buddy off its list */
    ldr     x2, [x16, #HB_PREV]
    cmn     x2, #1
    b.eq    11f
    add     x3, x8, x2
    str     x1, [x3, #HB_NEXT]
    b       12f
11: str     x1, [x13, x9, lsl #3]
12: cmn     x1, #1
    b.eq    13f
    add     x3, x8, x1
    str     x2, [x3, #HB_PREV]
13: str     wzr, [x16, #HB_FREE]
    cmp     x15, x12
    csel    x12, x15, x12, lo
    add     x9, x9, #1
    b       1b
3:  add     x14, x8, x12                    /* push the joined block */
    str     w9, [x14, #HB_ORDER]
    mov     w17, #1
    str     w17, [x14, #HB_FREE]
    ldr     x17, [x13, x9, lsl #3]
    str     x17, [x14, #HB_NEXT]
    mov     x1, #NONE
    str     x1, [x14, #HB_PREV]
    cmn     x17, #1
    b.eq    4f
    add     x1, x8, x17
    str     x12, [x1, #HB_PREV]
4:  str     x12, [x13, x9, lsl #3]
9:  ret
END_FUNCTION libp2p_heap_free

/* ---------------------------------------------------------------- Random bytes */

/*
 * libp2p_random(dst, n): n bytes from the DRBG: SHA-256(key || counter) blocks,
 * the counter going up by one for each block.
 */
LOCAL_FUNCTION libp2p_random
    ENTER   0, 96
    mov     x20, x0
    mov     x21, x1
1:  cbz     x21, 9f
    mov     x9, #64
    str     x9, [sp]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [sp, #8]
    mov     x9, #40
    str     x9, [sp, #16]
    ldp     x9, x10, [x27, #ST_DRBG_KEY]
    stp     x9, x10, [sp, #24]
    ldp     x9, x10, [x27, #ST_DRBG_KEY + 16]
    stp     x9, x10, [sp, #40]
    ldr     x9, [x27, #ST_DRBG_COUNT]
    str     x9, [sp, #56]
    add     x9, x9, #1
    str     x9, [x27, #ST_DRBG_COUNT]
    mov     x0, sp
    add     x1, sp, #64
    CALL_GLOBAL crypto_sha256
    mov     x2, #32
    cmp     x21, x2
    csel    x2, x21, x2, lo
    sub     x21, x21, x2
    mov     x0, x20
    add     x1, sp, #64
    bl      libp2p_copy
    mov     x20, x0
    b       1b
9:  LEAVE   0, 96
END_FUNCTION libp2p_random

/* libp2p_random_below(n) -> a random number below n, for n of 1 or more. */
LOCAL_FUNCTION libp2p_random_below
    ENTER   0, 16
    mov     x19, x0
    mov     x0, sp
    mov     x1, #8
    bl      libp2p_random
    ldr     x9, [sp]
    udiv    x10, x9, x19
    msub    x0, x10, x19, x9
    LEAVE   0, 16
END_FUNCTION libp2p_random_below

/* libp2p_reseed(entropy): the DRBG key becomes SHA-256(key || the 32 entropy bytes). */
LOCAL_FUNCTION libp2p_reseed
    ENTER   0, 96
    mov     x9, #88
    str     x9, [sp]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [sp, #8]
    mov     x9, #64
    str     x9, [sp, #16]
    ldp     x9, x10, [x27, #ST_DRBG_KEY]
    stp     x9, x10, [sp, #24]
    ldp     x9, x10, [x27, #ST_DRBG_KEY + 16]
    stp     x9, x10, [sp, #40]
    ldp     x9, x10, [x0]
    stp     x9, x10, [sp, #56]
    ldp     x9, x10, [x0, #16]
    stp     x9, x10, [sp, #72]
    mov     x0, sp
    add     x1, x27, #ST_DRBG_KEY
    CALL_GLOBAL crypto_sha256
    LEAVE   0, 96
END_FUNCTION libp2p_reseed

/* ---------------------------------------------------------------- Actions and time */

/*
 * libp2p_action(kind, size) -> the new action, zeroed, with size and kind set;
 * 0 when the action list has no room. size is a multiple of 8.
 */
LOCAL_FUNCTION libp2p_action
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x28, #SC_ACTIONS]
    ldr     x9, [x21, #LIBP2P_BL_COUNT]
    ldr     x10, [x21, #LIBP2P_BL_SIZE]
    sub     x10, x10, #LIBP2P_BL_FIXED
    sub     x10, x10, x9
    mov     x0, #0
    cmp     x10, x20
    b.lo    9f
    add     x22, x21, #LIBP2P_BL_FIXED
    add     x22, x22, x9
    add     x9, x9, x20
    str     x9, [x21, #LIBP2P_BL_COUNT]
    mov     x0, x22
    mov     x1, x20
    bl      libp2p_zero
    str     x20, [x22, #LIBP2P_ACT_SIZE]
    str     x19, [x22, #LIBP2P_ACT_KIND]
    mov     x0, x22
9:  LEAVE   0
END_FUNCTION libp2p_action

/* libp2p_room() -> the action bytes left, beyond the reserve of the step. A leaf. */
LOCAL_FUNCTION libp2p_room
    UNWIND_END_PROLOGUE
    ldr     x1, [x28, #SC_ACTIONS]
    ldr     x2, [x1, #LIBP2P_BL_SIZE]
    sub     x2, x2, #LIBP2P_BL_FIXED
    ldr     x3, [x1, #LIBP2P_BL_COUNT]
    sub     x2, x2, x3
    ldr     x3, [x28, #SC_RESERVE]
    subs    x0, x2, x3
    csel    x0, xzr, x0, lo
    ret
END_FUNCTION libp2p_room

/*
 * libp2p_action_shrink(action, size): makes the last action size bytes long
 * (a multiple of 8, at most its size). A leaf.
 */
LOCAL_FUNCTION libp2p_action_shrink
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #LIBP2P_ACT_SIZE]
    str     x1, [x0, #LIBP2P_ACT_SIZE]
    sub     x2, x2, x1
    ldr     x3, [x28, #SC_ACTIONS]
    ldr     x4, [x3, #LIBP2P_BL_COUNT]
    sub     x4, x4, x2
    str     x4, [x3, #LIBP2P_BL_COUNT]
    ret
END_FUNCTION libp2p_action_shrink

/* libp2p_wake_at(time): the next step is due by time at the latest. A leaf. */
LOCAL_FUNCTION libp2p_wake_at
    UNWIND_END_PROLOGUE
    ldr     x1, [x28, #SC_WAKE]
    cmp     x0, x1
    b.hs    1f
    str     x0, [x28, #SC_WAKE]
1:  ret
END_FUNCTION libp2p_wake_at

/* ---------------------------------------------------------------- Slots and handles */

/*
 * libp2p_slot(table field, count field, stride, handle) -> the slot of a live
 * handle, or 0: the index is below the count, the generation matches and
 * the slot is in use (a nonzero u32 at offset 4). A leaf.
 */
LOCAL_FUNCTION libp2p_slot
    UNWIND_END_PROLOGUE
    ldr     x4, [x27, x1]
    mov     w5, w3
    cmp     x5, x4
    b.hs    8f
    ldr     x4, [x27, x0]
    add     x4, x27, x4
    madd    x4, x5, x2, x4
    ldr     w6, [x4]
    cmp     x6, x3, lsr #32
    b.ne    8f
    ldr     w6, [x4, #4]
    cbz     w6, 8f
    mov     x0, x4
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_slot

/* libp2p_conn(handle) -> the connection slot, or 0. */
LOCAL_FUNCTION libp2p_conn
    ENTER   0
    mov     x3, x0
    mov     x0, #ST_CONN_OFF
    mov     x1, #ST_CONN_COUNT
    mov     x2, #C_SIZE
    bl      libp2p_slot
    LEAVE   0
END_FUNCTION libp2p_conn

/* libp2p_stream(handle) -> the stream slot, or 0. */
LOCAL_FUNCTION libp2p_stream
    ENTER   0
    mov     x3, x0
    mov     x0, #ST_STREAM_OFF
    mov     x1, #ST_STREAM_COUNT
    mov     x2, #S_SIZE
    bl      libp2p_slot
    LEAVE   0
END_FUNCTION libp2p_stream

/* libp2p_peer(handle) -> the peer slot of a connected peer, or 0. */
LOCAL_FUNCTION libp2p_peer
    ENTER   0
    mov     x3, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #ST_PEER_COUNT
    mov     x2, #P_SIZE
    bl      libp2p_slot
    cbz     x0, 9f
    ldr     w9, [x0, #P_STATE]
    cmp     w9, #PS_CONNECTED
    csel    x0, x0, xzr, eq
9:  LEAVE   0
END_FUNCTION libp2p_peer

/*
 * libp2p_handle(table field, stride, slot) -> the handle of a slot: its index,
 * and its generation in the high 32 bits. A leaf.
 */
LOCAL_FUNCTION libp2p_handle
    UNWIND_END_PROLOGUE
    ldr     x3, [x27, x0]
    add     x3, x27, x3
    sub     x3, x2, x3
    udiv    x3, x3, x1
    ldr     w4, [x2]
    orr     x0, x3, x4, lsl #32
    ret
END_FUNCTION libp2p_handle

/*
 * libp2p_alloc_slot(table field, count field, stride) -> a free slot, zeroed
 * after its generation, with the generation one higher and the in-use word
 * set to 1; 0 when every slot is in use.
 */
LOCAL_FUNCTION libp2p_alloc_slot
    ENTER   0
    ldr     x19, [x27, x0]
    add     x19, x27, x19
    ldr     x20, [x27, x1]
    mov     x21, x2
1:  cbz     x20, 8f
    ldr     w9, [x19, #4]
    cbz     w9, 2f
    add     x19, x19, x21
    sub     x20, x20, #1
    b       1b
2:  ldr     w22, [x19]
    add     x0, x19, #8
    sub     x1, x21, #8
    bl      libp2p_zero
    add     w22, w22, #1
    str     w22, [x19]
    mov     w9, #1
    str     w9, [x19, #4]
    mov     x0, x19
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_alloc_slot

.include "wire.s"
.include "noise.s"
.include "node.s"
.include "conn.s"
.include "stream.s"
.include "mux.s"
.include "gossip.s"

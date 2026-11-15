/*
 * asm-libp2p for RISC-V (RISC-V ELF psABI, LP64D): libp2p over TCP and QUIC
 * for an Ethereum consensus client: Noise, multistream-select, yamux, mplex,
 * the glue to asm-quic, streams and gossipsub.
 * Requirements: docs/reference/. Layouts: include/libp2p.inc, include/state.inc.
 *
 * One object: this file includes the other parts of the core. Hashes,
 * ciphers and keys go through asm-crypto; QUIC goes through asm-quic.
 * Baseline RV64GC instructions
 * only. The functions and their steps follow the ARM64 core one for one;
 * frame.inc maps its registers. 8-byte loads and stores only touch 8-byte
 * aligned addresses.
 */
.set ISA_RISCV64, 1
.include "crypto.inc"
.include "hmac.inc"
.include "chacha20.inc"
.include "secp256k1.inc"
.include "sha512.inc"
.include "ed25519.inc"
.include "libp2p.inc"
.include "quic.inc"
.include "state.inc"
.include "platform.inc"
.include "frame.inc"

/* ---------------------------------------------------------------- Byte helpers */

/* libp2p_copy(dst, src, n) -> dst + n. dst is below src, or the regions do not overlap. */
LOCAL_FUNCTION libp2p_copy
    UNWIND_END_PROLOGUE
    or      t0, a0, a1
    andi    t0, t0, 7
    bnez    t0, 2f
    li      t1, 8
1:  bltu    a2, t1, 2f
    ld      t2, 0(a1)
    sd      t2, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, 8
    addi    a2, a2, -8
    j       1b
2:  beqz    a2, 3f
    lbu     t2, 0(a1)
    sb      t2, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       2b
3:  ret
END_FUNCTION libp2p_copy

/* libp2p_zero(dst, n) -> dst + n. */
LOCAL_FUNCTION libp2p_zero
    UNWIND_END_PROLOGUE
    andi    t0, a0, 7
    bnez    t0, 2f
    li      t1, 8
1:  bltu    a1, t1, 2f
    sd      zero, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, -8
    j       1b
2:  beqz    a1, 3f
    sb      zero, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    j       2b
3:  ret
END_FUNCTION libp2p_zero

/* libp2p_equal(a, b, n) -> 1 when the n bytes at a and b are equal, else 0. */
LOCAL_FUNCTION libp2p_equal
    UNWIND_END_PROLOGUE
    li      a4, 0
1:  beqz    a2, 2f
    lbu     a3, 0(a0)
    lbu     a5, 0(a1)
    xor     a3, a3, a5
    or      a4, a4, a3
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       1b
2:  seqz    a0, a4
    ret
END_FUNCTION libp2p_equal

/* libp2p_compare(a, alen, b, blen) -> 1 when the byte strings are equal (same length and bytes), else 0. */
LOCAL_FUNCTION libp2p_compare
    UNWIND_END_PROLOGUE
    mv      a4, a0
    li      a0, 0
    bne     a1, a3, 9f
    li      a5, 0
1:  beqz    a1, 2f
    lbu     a6, 0(a4)
    lbu     a7, 0(a2)
    xor     a6, a6, a7
    or      a5, a5, a6
    addi    a4, a4, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    j       1b
2:  seqz    a0, a5
9:  ret
END_FUNCTION libp2p_compare

/* libp2p_hash(p, n) -> the FNV-1a hash of the n bytes at p. */
LOCAL_FUNCTION libp2p_hash
    UNWIND_END_PROLOGUE
    li      a2, 0xCBF29CE484222325
    li      a3, 0x100000001B3
1:  beqz    a1, 2f
    lbu     a4, 0(a0)
    xor     a2, a2, a4
    mul     a2, a2, a3
    addi    a0, a0, 1
    addi    a1, a1, -1
    j       1b
2:  mv      a0, a2
    ret
END_FUNCTION libp2p_hash

/* ---------------------------------------------------------------- Heap: a buddy allocator over the heap part */

/*
 * libp2p_heap_alloc(n) -> the state offset of n usable bytes, or 0 when no
 * block is free. Blocks are 2^order bytes with a 16-byte header; free
 * blocks sit on one doubly linked list for each order. A leaf.
 * a7 heap base, t0 order, t1 top order, t2 order found, t3 block, t4
 * lists, t5 the block's address, t6 a6 a5 a1 temporaries.
 */
LOCAL_FUNCTION libp2p_heap_alloc
    UNWIND_END_PROLOGUE
    ld      a7, ST_HEAP_OFF(s9)
    add     a7, s9, a7
    ld      t6, ST_HEAP_SIZE(s9)            # the top order: the size is a power of 2
    li      t1, 0
1:  andi    a6, t6, 1
    bnez    a6, 2f
    srli    t6, t6, 1
    addi    t1, t1, 1
    j       1b
2:  addi    t6, a0, (HB_HEADER - 1)         # the order that holds n + 16: the bit length of n + 15
    li      t0, 0
3:  beqz    t6, 4f
    srli    t6, t6, 1
    addi    t0, t0, 1
    j       3b
4:  li      a6, HEAP_MIN_ORDER
    bgeu    t0, a6, 5f
    mv      t0, a6
5:  li      a0, 0
    bltu    t1, t0, 9f
    mv      t2, t0
    addi    t4, s9, ST_HEAP_FREE
6:  bltu    t1, t2, 9f
    slli    a6, t2, 3
    add     a6, t4, a6
    ld      t3, 0(a6)
    li      a5, NONE
    bne     t3, a5, 7f
    addi    t2, t2, 1
    j       6b
7:  add     t5, a7, t3                      # take the block off its list
    ld      t6, HB_NEXT(t5)
    sd      t6, 0(a6)
    beq     t6, a5, 8f
    add     a6, a7, t6
    sd      a5, HB_PREV(a6)
8:  bgeu    t0, t2, 10f                     # split down to the order asked for
    addi    t2, t2, -1
    li      t6, 1
    sll     t6, t6, t2
    add     t6, t3, t6                      # the upper half becomes free
    add     a6, a7, t6
    sw      t2, HB_ORDER(a6)
    li      a5, 1
    sw      a5, HB_FREE(a6)
    slli    a1, t2, 3
    add     a1, t4, a1
    ld      a5, 0(a1)
    sd      a5, HB_NEXT(a6)
    li      a0, NONE
    sd      a0, HB_PREV(a6)
    beq     a5, a0, 81f
    add     a5, a7, a5
    sd      t6, HB_PREV(a5)
81: sd      t6, 0(a1)
    j       8b
10: sw      t0, HB_ORDER(t5)
    sw      zero, HB_FREE(t5)
    li      t6, 1
    sll     t6, t6, t0
    ld      a6, ST_HEAP_USED(s9)
    add     a6, a6, t6
    sd      a6, ST_HEAP_USED(s9)
    sub     a0, t5, s9
    addi    a0, a0, HB_HEADER
9:  ret
END_FUNCTION libp2p_heap_alloc

/*
 * libp2p_heap_free(offset): returns a block from libp2p_heap_alloc, joining it with
 * its free buddies. Offset 0 does nothing. A leaf.
 * a7 heap base, t0 order, t1 top order, t3 block, t4 lists, t5 address,
 * t6 buddy, a6 its address.
 */
LOCAL_FUNCTION libp2p_heap_free
    UNWIND_END_PROLOGUE
    beqz    a0, 9f
    ld      a7, ST_HEAP_OFF(s9)
    sub     t3, a0, a7
    addi    t3, t3, -HB_HEADER
    add     a7, s9, a7
    ld      t6, ST_HEAP_SIZE(s9)
    li      t1, 0
1:  andi    a6, t6, 1
    bnez    a6, 2f
    srli    t6, t6, 1
    addi    t1, t1, 1
    j       1b
2:  addi    t4, s9, ST_HEAP_FREE
    add     t5, a7, t3
    lwu     t0, HB_ORDER(t5)
    li      t6, 1
    sll     t6, t6, t0
    ld      a6, ST_HEAP_USED(s9)
    sub     a6, a6, t6
    sd      a6, ST_HEAP_USED(s9)
3:  bgeu    t0, t1, 5f
    li      t6, 1
    sll     t6, t6, t0
    xor     t6, t3, t6                      # the buddy
    add     a6, a7, t6
    lwu     a5, HB_FREE(a6)
    beqz    a5, 5f
    lwu     a5, HB_ORDER(a6)
    bne     a5, t0, 5f
    ld      a1, HB_NEXT(a6)                 # take the buddy off its list
    ld      a2, HB_PREV(a6)
    li      a4, NONE
    beq     a2, a4, 31f
    add     a3, a7, a2
    sd      a1, HB_NEXT(a3)
    j       32f
31: slli    a3, t0, 3
    add     a3, t4, a3
    sd      a1, 0(a3)
32: beq     a1, a4, 33f
    add     a3, a7, a1
    sd      a2, HB_PREV(a3)
33: sw      zero, HB_FREE(a6)
    bgeu    t6, t3, 34f
    mv      t3, t6
34: addi    t0, t0, 1
    j       3b
5:  add     t5, a7, t3                      # push the joined block
    sw      t0, HB_ORDER(t5)
    li      a5, 1
    sw      a5, HB_FREE(t5)
    slli    a3, t0, 3
    add     a3, t4, a3
    ld      a5, 0(a3)
    sd      a5, HB_NEXT(t5)
    li      a1, NONE
    sd      a1, HB_PREV(t5)
    beq     a5, a1, 6f
    add     a1, a7, a5
    sd      t3, HB_PREV(a1)
6:  sd      t3, 0(a3)
9:  ret
END_FUNCTION libp2p_heap_free

/* ---------------------------------------------------------------- Random bytes */

/*
 * libp2p_random(dst, n): n bytes from the DRBG: SHA-256(key || counter) blocks,
 * the counter going up by one for each block.
 * Extra: sp + FL the ByteList (64 bytes), sp + FL + 64 the block.
 */
LOCAL_FUNCTION libp2p_random
    ENTER   0, 96
    mv      s2, a0
    mv      s3, a1
1:  beqz    s3, 9f
    li      t0, 64
    sd      t0, FL(sp)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (FL + 8)(sp)
    li      t0, 40
    sd      t0, (FL + 16)(sp)
    ld      t0, ST_DRBG_KEY(s9)
    sd      t0, (FL + 24)(sp)
    ld      t0, (ST_DRBG_KEY + 8)(s9)
    sd      t0, (FL + 32)(sp)
    ld      t0, (ST_DRBG_KEY + 16)(s9)
    sd      t0, (FL + 40)(sp)
    ld      t0, (ST_DRBG_KEY + 24)(s9)
    sd      t0, (FL + 48)(sp)
    ld      t0, ST_DRBG_COUNT(s9)
    sd      t0, (FL + 56)(sp)
    addi    t0, t0, 1
    sd      t0, ST_DRBG_COUNT(s9)
    addi    a0, sp, FL
    addi    a1, sp, (FL + 64)
    CALL_GLOBAL crypto_sha256
    li      a2, 32
    bgeu    s3, a2, 2f
    mv      a2, s3
2:  sub     s3, s3, a2
    mv      a0, s2
    addi    a1, sp, (FL + 64)
    call    libp2p_copy
    mv      s2, a0
    j       1b
9:  LEAVE   0, 96
END_FUNCTION libp2p_random

/* libp2p_random_below(n) -> a random number below n, for n of 1 or more. */
LOCAL_FUNCTION libp2p_random_below
    ENTER   0, 16
    mv      s1, a0
    addi    a0, sp, FL
    li      a1, 8
    call    libp2p_random
    ld      t0, FL(sp)
    remu    a0, t0, s1
    LEAVE   0, 16
END_FUNCTION libp2p_random_below

/* libp2p_reseed(entropy): the DRBG key becomes SHA-256(key || the 32 entropy bytes). */
LOCAL_FUNCTION libp2p_reseed
    ENTER   0, 96
    li      t0, 88
    sd      t0, FL(sp)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (FL + 8)(sp)
    li      t0, 64
    sd      t0, (FL + 16)(sp)
    ld      t0, ST_DRBG_KEY(s9)
    sd      t0, (FL + 24)(sp)
    ld      t0, (ST_DRBG_KEY + 8)(s9)
    sd      t0, (FL + 32)(sp)
    ld      t0, (ST_DRBG_KEY + 16)(s9)
    sd      t0, (FL + 40)(sp)
    ld      t0, (ST_DRBG_KEY + 24)(s9)
    sd      t0, (FL + 48)(sp)
    ld      t0, 0(a0)
    sd      t0, (FL + 56)(sp)
    ld      t0, 8(a0)
    sd      t0, (FL + 64)(sp)
    ld      t0, 16(a0)
    sd      t0, (FL + 72)(sp)
    ld      t0, 24(a0)
    sd      t0, (FL + 80)(sp)
    addi    a0, sp, FL
    addi    a1, s9, ST_DRBG_KEY
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
    mv      s1, a0
    mv      s2, a1
    ld      s3, SC_ACTIONS(s10)
    ld      t0, LIBP2P_BL_COUNT(s3)
    ld      t1, LIBP2P_BL_SIZE(s3)
    addi    t1, t1, -LIBP2P_BL_FIXED
    sub     t1, t1, t0
    li      a0, 0
    bltu    t1, s2, 9f
    addi    s4, s3, LIBP2P_BL_FIXED
    add     s4, s4, t0
    add     t0, t0, s2
    sd      t0, LIBP2P_BL_COUNT(s3)
    mv      a0, s4
    mv      a1, s2
    call    libp2p_zero
    sd      s2, LIBP2P_ACT_SIZE(s4)
    sd      s1, LIBP2P_ACT_KIND(s4)
    mv      a0, s4
9:  LEAVE   0
END_FUNCTION libp2p_action

/* libp2p_room() -> the action bytes left, beyond the reserve of the step. A leaf. */
LOCAL_FUNCTION libp2p_room
    UNWIND_END_PROLOGUE
    ld      a1, SC_ACTIONS(s10)
    ld      a2, LIBP2P_BL_SIZE(a1)
    addi    a2, a2, -LIBP2P_BL_FIXED
    ld      a3, LIBP2P_BL_COUNT(a1)
    sub     a2, a2, a3
    ld      a3, SC_RESERVE(s10)
    li      a0, 0
    bltu    a2, a3, 1f
    sub     a0, a2, a3
1:  ret
END_FUNCTION libp2p_room

/*
 * libp2p_action_shrink(action, size): makes the last action size bytes long
 * (a multiple of 8, at most its size). A leaf.
 */
LOCAL_FUNCTION libp2p_action_shrink
    UNWIND_END_PROLOGUE
    ld      a2, LIBP2P_ACT_SIZE(a0)
    sd      a1, LIBP2P_ACT_SIZE(a0)
    sub     a2, a2, a1
    ld      a3, SC_ACTIONS(s10)
    ld      a4, LIBP2P_BL_COUNT(a3)
    sub     a4, a4, a2
    sd      a4, LIBP2P_BL_COUNT(a3)
    ret
END_FUNCTION libp2p_action_shrink

/* libp2p_wake_at(time): the next step is due by time at the latest. A leaf. */
LOCAL_FUNCTION libp2p_wake_at
    UNWIND_END_PROLOGUE
    ld      a1, SC_WAKE(s10)
    bgeu    a0, a1, 1f
    sd      a0, SC_WAKE(s10)
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
    add     a4, s9, a1
    ld      a4, 0(a4)
    slli    a5, a3, 32
    srli    a5, a5, 32
    bgeu    a5, a4, 8f
    add     a4, s9, a0
    ld      a4, 0(a4)
    add     a4, s9, a4
    mul     a5, a5, a2
    add     a4, a4, a5
    lwu     a6, 0(a4)
    srli    a7, a3, 32
    bne     a6, a7, 8f
    lwu     a6, 4(a4)
    beqz    a6, 8f
    mv      a0, a4
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_slot

/* libp2p_conn(handle) -> the connection slot, or 0. */
LOCAL_FUNCTION libp2p_conn
    FRAME
    mv      a3, a0
    li      a0, ST_CONN_OFF
    li      a1, ST_CONN_COUNT
    li      a2, C_SIZE
    call    libp2p_slot
    UNFRAME
END_FUNCTION libp2p_conn

/* libp2p_stream(handle) -> the stream slot, or 0. */
LOCAL_FUNCTION libp2p_stream
    FRAME
    mv      a3, a0
    li      a0, ST_STREAM_OFF
    li      a1, ST_STREAM_COUNT
    li      a2, S_SIZE
    call    libp2p_slot
    UNFRAME
END_FUNCTION libp2p_stream

/* libp2p_peer(handle) -> the peer slot of a connected peer, or 0. */
LOCAL_FUNCTION libp2p_peer
    FRAME
    mv      a3, a0
    li      a0, ST_PEER_OFF
    li      a1, ST_PEER_COUNT
    li      a2, P_SIZE
    call    libp2p_slot
    beqz    a0, 9f
    lw      t0, P_STATE(a0)
    li      t1, PS_CONNECTED
    beq     t0, t1, 9f
    li      a0, 0
9:  UNFRAME
END_FUNCTION libp2p_peer

/*
 * libp2p_handle(table field, stride, slot) -> the handle of a slot: its index,
 * and its generation in the high 32 bits. A leaf.
 */
LOCAL_FUNCTION libp2p_handle
    UNWIND_END_PROLOGUE
    add     a3, s9, a0
    ld      a3, 0(a3)
    add     a3, s9, a3
    sub     a3, a2, a3
    divu    a3, a3, a1
    lwu     a4, 0(a2)
    slli    a4, a4, 32
    or      a0, a3, a4
    ret
END_FUNCTION libp2p_handle

/*
 * libp2p_alloc_slot(table field, count field, stride) -> a free slot, zeroed
 * after its generation, with the generation one higher and the in-use word
 * set to 1; 0 when every slot is in use.
 */
LOCAL_FUNCTION libp2p_alloc_slot
    ENTER   0
    add     t0, s9, a0
    ld      s1, 0(t0)
    add     s1, s9, s1
    add     t0, s9, a1
    ld      s2, 0(t0)
    mv      s3, a2
1:  beqz    s2, 8f
    lwu     t0, 4(s1)
    beqz    t0, 2f
    add     s1, s1, s3
    addi    s2, s2, -1
    j       1b
2:  lwu     s4, 0(s1)
    addi    a0, s1, 8
    addi    a1, s3, -8
    call    libp2p_zero
    addiw   s4, s4, 1
    sw      s4, 0(s1)
    li      t0, 1
    sw      t0, 4(s1)
    mv      a0, s1
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_alloc_slot

.include "wire.s"
.include "noise.s"
.include "node.s"
.include "conn.s"
.include "stream.s"
.include "mux.s"
.include "gossip.s"
.include "quic.s"

/*
 * asm-libp2p for x86-64 (System V AMD64 psABI), AT&T syntax: libp2p over
 * TCP and QUIC for an Ethereum consensus client: Noise, multistream-select,
 * yamux, mplex, the glue to asm-quic, streams and gossipsub.
 * Requirements: docs/reference/. Layouts: include/libp2p.inc, include/state.inc.
 *
 * One object: this file includes the other parts of the core. Hashes,
 * ciphers and keys go through asm-crypto; QUIC goes through asm-quic. Baseline x86-64 instructions only.
 * The functions and their steps follow the ARM64 core one for one; frame.inc
 * maps its registers. Every call may change rax, rcx, rdx, rsi, rdi, r8-r11
 * and the xmm registers.
 */
.set ISA_X86_64, 1
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
    mov     %rdx, %rcx
    rep movsb
    mov     %rdi, %rax
    ret
END_FUNCTION libp2p_copy

/* libp2p_zero(dst, n) -> dst + n. */
LOCAL_FUNCTION libp2p_zero
    UNWIND_END_PROLOGUE
    mov     %rsi, %rcx
    xor     %eax, %eax
    rep stosb
    mov     %rdi, %rax
    ret
END_FUNCTION libp2p_zero

/* libp2p_equal(a, b, n) -> 1 when the n bytes at a and b are equal, else 0. */
LOCAL_FUNCTION libp2p_equal
    UNWIND_END_PROLOGUE
    xor     %r8d, %r8d
1:  test    %rdx, %rdx
    jz      2f
    movzbl  (%rdi), %ecx
    xorb    (%rsi), %cl
    or      %rcx, %r8
    inc     %rdi
    inc     %rsi
    dec     %rdx
    jmp     1b
2:  xor     %eax, %eax
    test    %r8, %r8
    sete    %al
    ret
END_FUNCTION libp2p_equal

/* libp2p_compare(a, alen, b, blen) -> 1 when the byte strings are equal (same length and bytes), else 0. */
LOCAL_FUNCTION libp2p_compare
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    cmp     %rcx, %rsi
    jne     9f
    xor     %r8d, %r8d
1:  test    %rsi, %rsi
    jz      2f
    movzbl  (%rdi), %ecx
    xorb    (%rdx), %cl
    or      %rcx, %r8
    inc     %rdi
    inc     %rdx
    dec     %rsi
    jmp     1b
2:  test    %r8, %r8
    sete    %al
9:  ret
END_FUNCTION libp2p_compare

/* libp2p_hash(p, n) -> the FNV-1a hash of the n bytes at p. */
LOCAL_FUNCTION libp2p_hash
    UNWIND_END_PROLOGUE
    movabs  $0xCBF29CE484222325, %rax
    movabs  $0x100000001B3, %rdx
    mov     %rdx, %r8
1:  test    %rsi, %rsi
    jz      2f
    movzbl  (%rdi), %ecx
    xor     %rcx, %rax
    imul    %r8, %rax
    inc     %rdi
    dec     %rsi
    jmp     1b
2:  ret
END_FUNCTION libp2p_hash

/* ---------------------------------------------------------------- Heap: a buddy allocator over the heap part */

/*
 * libp2p_heap_alloc(n) -> the state offset of n usable bytes, or 0 when no
 * block is free. Blocks are 2^order bytes with a 16-byte header; free
 * blocks sit on one doubly linked list for each order. A leaf.
 * r8 heap base, r9 order, r10 top order, r11 order found, rdx block,
 * rsi lists, rdi the block's address.
 */
LOCAL_FUNCTION libp2p_heap_alloc
    UNWIND_END_PROLOGUE
    mov     ST_HEAP_OFF(%r15), %r8
    add     %r15, %r8
    bsf     ST_HEAP_SIZE(%r15), %r10        /* the top order */
    lea     (HB_HEADER - 1)(%rdi), %rcx
    bsr     %rcx, %r9
    inc     %r9                             /* the order that holds n + 16 */
    mov     $HEAP_MIN_ORDER, %ecx
    cmp     %rcx, %r9
    cmovb   %rcx, %r9
    xor     %eax, %eax
    cmp     %r10, %r9
    ja      9f
    mov     %r9, %r11
    lea     ST_HEAP_FREE(%r15), %rsi
1:  cmp     %r10, %r11
    ja      9f
    mov     (%rsi,%r11,8), %rdx
    cmp     $NONE, %rdx
    jne     2f
    inc     %r11
    jmp     1b
2:  lea     (%r8,%rdx), %rdi                /* take the block off its list */
    mov     HB_NEXT(%rdi), %rcx
    mov     %rcx, (%rsi,%r11,8)
    cmp     $NONE, %rcx
    je      3f
    movq    $NONE, HB_PREV(%r8,%rcx)
3:  cmp     %r9, %r11                       /* split down to the order asked for */
    jbe     4f
    dec     %r11
    mov     %r11, %rcx
    mov     $1, %eax
    shl     %cl, %rax
    add     %rdx, %rax                      /* the upper half becomes free */
    movl    %r11d, HB_ORDER(%r8,%rax)
    movl    $1, HB_FREE(%r8,%rax)
    mov     (%rsi,%r11,8), %rcx
    mov     %rcx, HB_NEXT(%r8,%rax)
    movq    $NONE, HB_PREV(%r8,%rax)
    cmp     $NONE, %rcx
    je      31f
    mov     %rax, HB_PREV(%r8,%rcx)
31: mov     %rax, (%rsi,%r11,8)
    jmp     3b
4:  movl    %r9d, HB_ORDER(%rdi)
    movl    $0, HB_FREE(%rdi)
    mov     %r9, %rcx
    mov     $1, %eax
    shl     %cl, %rax
    add     %rax, ST_HEAP_USED(%r15)
    mov     %rdi, %rax
    sub     %r15, %rax
    add     $HB_HEADER, %rax
9:  ret
END_FUNCTION libp2p_heap_alloc

/*
 * libp2p_heap_free(offset): returns a block from libp2p_heap_alloc, joining it with
 * its free buddies. Offset 0 does nothing. A leaf.
 * r8 heap base, r9 order, r10 top order, rdx block, rsi lists, rax buddy,
 * r11 the buddy's address.
 */
LOCAL_FUNCTION libp2p_heap_free
    UNWIND_END_PROLOGUE
    test    %rdi, %rdi
    jz      9f
    mov     ST_HEAP_OFF(%r15), %r8
    mov     %rdi, %rdx
    sub     %r8, %rdx
    sub     $HB_HEADER, %rdx
    add     %r15, %r8
    bsf     ST_HEAP_SIZE(%r15), %r10
    lea     ST_HEAP_FREE(%r15), %rsi
    movl    HB_ORDER(%r8,%rdx), %r9d
    mov     %r9, %rcx
    mov     $1, %eax
    shl     %cl, %rax
    sub     %rax, ST_HEAP_USED(%r15)
1:  cmp     %r10, %r9
    jae     3f
    mov     %r9, %rcx
    mov     $1, %eax
    shl     %cl, %rax
    xor     %rdx, %rax                      /* the buddy */
    lea     (%r8,%rax), %r11
    cmpl    $0, HB_FREE(%r11)
    je      3f
    movl    HB_ORDER(%r11), %ecx
    cmp     %r9, %rcx
    jne     3f
    mov     HB_NEXT(%r11), %rcx             /* take the buddy off its list */
    mov     HB_PREV(%r11), %rdi
    cmp     $NONE, %rdi
    je      11f
    mov     %rcx, HB_NEXT(%r8,%rdi)
    jmp     12f
11: mov     %rcx, (%rsi,%r9,8)
12: cmp     $NONE, %rcx
    je      13f
    mov     %rdi, HB_PREV(%r8,%rcx)
13: movl    $0, HB_FREE(%r11)
    cmp     %rdx, %rax
    cmovb   %rax, %rdx
    inc     %r9
    jmp     1b
3:  lea     (%r8,%rdx), %rdi                /* push the joined block */
    movl    %r9d, HB_ORDER(%rdi)
    movl    $1, HB_FREE(%rdi)
    mov     (%rsi,%r9,8), %rcx
    mov     %rcx, HB_NEXT(%rdi)
    movq    $NONE, HB_PREV(%rdi)
    cmp     $NONE, %rcx
    je      4f
    mov     %rdx, HB_PREV(%r8,%rcx)
4:  mov     %rdx, (%rsi,%r9,8)
9:  ret
END_FUNCTION libp2p_heap_free

/* ---------------------------------------------------------------- Random bytes */

/*
 * libp2p_random(dst, n): n bytes from the DRBG: SHA-256(key || counter) blocks,
 * the counter going up by one for each block.
 * Extra: 32(%rsp) the ByteList (64 bytes), 96(%rsp) the block.
 */
LOCAL_FUNCTION libp2p_random
    ENTER   0, 96
    mov     %rdi, %rbp
    mov     %rsi, %r12
1:  test    %r12, %r12
    jz      9f
    movq    $64, 32(%rsp)
    movq    $LIBP2P_BL_FIXED, 40(%rsp)
    movq    $40, 48(%rsp)
    mov     ST_DRBG_KEY(%r15), %rax
    mov     %rax, 56(%rsp)
    mov     (ST_DRBG_KEY + 8)(%r15), %rax
    mov     %rax, 64(%rsp)
    mov     (ST_DRBG_KEY + 16)(%r15), %rax
    mov     %rax, 72(%rsp)
    mov     (ST_DRBG_KEY + 24)(%r15), %rax
    mov     %rax, 80(%rsp)
    mov     ST_DRBG_COUNT(%r15), %rax
    mov     %rax, 88(%rsp)
    inc     %rax
    mov     %rax, ST_DRBG_COUNT(%r15)
    lea     32(%rsp), %rdi
    lea     96(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    mov     $32, %edx
    cmp     %rdx, %r12
    cmovb   %r12, %rdx
    sub     %rdx, %r12
    mov     %rbp, %rdi
    lea     96(%rsp), %rsi
    call    libp2p_copy
    mov     %rax, %rbp
    jmp     1b
9:  LEAVE   0, 96
END_FUNCTION libp2p_random

/* libp2p_random_below(n) -> a random number below n, for n of 1 or more. */
LOCAL_FUNCTION libp2p_random_below
    ENTER   0, 16
    mov     %rdi, %rbx
    lea     32(%rsp), %rdi
    mov     $8, %esi
    call    libp2p_random
    mov     32(%rsp), %rax
    xor     %edx, %edx
    div     %rbx
    mov     %rdx, %rax
    LEAVE   0, 16
END_FUNCTION libp2p_random_below

/* libp2p_reseed(entropy): the DRBG key becomes SHA-256(key || the 32 entropy bytes). */
LOCAL_FUNCTION libp2p_reseed
    ENTER   0, 96
    movq    $88, 32(%rsp)
    movq    $LIBP2P_BL_FIXED, 40(%rsp)
    movq    $64, 48(%rsp)
    mov     ST_DRBG_KEY(%r15), %rax
    mov     %rax, 56(%rsp)
    mov     (ST_DRBG_KEY + 8)(%r15), %rax
    mov     %rax, 64(%rsp)
    mov     (ST_DRBG_KEY + 16)(%r15), %rax
    mov     %rax, 72(%rsp)
    mov     (ST_DRBG_KEY + 24)(%r15), %rax
    mov     %rax, 80(%rsp)
    mov     (%rdi), %rax
    mov     %rax, 88(%rsp)
    mov     8(%rdi), %rax
    mov     %rax, 96(%rsp)
    mov     16(%rdi), %rax
    mov     %rax, 104(%rsp)
    mov     24(%rdi), %rax
    mov     %rax, 112(%rsp)
    lea     32(%rsp), %rdi
    lea     ST_DRBG_KEY(%r15), %rsi
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     SC_ACTIONS(%r14), %r12
    mov     LIBP2P_BL_COUNT(%r12), %rax
    mov     LIBP2P_BL_SIZE(%r12), %rcx
    sub     $LIBP2P_BL_FIXED, %rcx
    sub     %rax, %rcx
    cmp     %rbp, %rcx
    jb      8f
    lea     LIBP2P_BL_FIXED(%r12,%rax), %r13
    add     %rbp, %rax
    mov     %rax, LIBP2P_BL_COUNT(%r12)
    mov     %r13, %rdi
    mov     %rbp, %rsi
    call    libp2p_zero
    mov     %rbp, LIBP2P_ACT_SIZE(%r13)
    mov     %rbx, LIBP2P_ACT_KIND(%r13)
    mov     %r13, %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_action

/* libp2p_room() -> the action bytes left, beyond the reserve of the step. A leaf. */
LOCAL_FUNCTION libp2p_room
    UNWIND_END_PROLOGUE
    mov     SC_ACTIONS(%r14), %rcx
    mov     LIBP2P_BL_SIZE(%rcx), %rax
    sub     $LIBP2P_BL_FIXED, %rax
    sub     LIBP2P_BL_COUNT(%rcx), %rax
    xor     %edx, %edx
    sub     SC_RESERVE(%r14), %rax
    cmovb   %rdx, %rax
    ret
END_FUNCTION libp2p_room

/*
 * libp2p_action_shrink(action, size): makes the last action size bytes long
 * (a multiple of 8, at most its size). A leaf.
 */
LOCAL_FUNCTION libp2p_action_shrink
    UNWIND_END_PROLOGUE
    mov     LIBP2P_ACT_SIZE(%rdi), %rdx
    mov     %rsi, LIBP2P_ACT_SIZE(%rdi)
    sub     %rsi, %rdx
    mov     SC_ACTIONS(%r14), %rcx
    sub     %rdx, LIBP2P_BL_COUNT(%rcx)
    ret
END_FUNCTION libp2p_action_shrink

/* libp2p_wake_at(time): the next step is due by time at the latest. A leaf. */
LOCAL_FUNCTION libp2p_wake_at
    UNWIND_END_PROLOGUE
    cmp     SC_WAKE(%r14), %rdi
    jae     1f
    mov     %rdi, SC_WAKE(%r14)
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
    mov     %ecx, %r9d
    cmp     (%r15,%rsi), %r9
    jae     8f
    mov     (%r15,%rdi), %rax
    add     %r15, %rax
    imul    %rdx, %r9
    add     %r9, %rax
    movl    (%rax), %r8d
    shr     $32, %rcx
    cmp     %rcx, %r8
    jne     8f
    cmpl    $0, 4(%rax)
    je      8f
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_slot

/* libp2p_conn(handle) -> the connection slot, or 0. */
LOCAL_FUNCTION libp2p_conn
    FRAME
    mov     %rdi, %rcx
    mov     $ST_CONN_OFF, %edi
    mov     $ST_CONN_COUNT, %esi
    mov     $C_SIZE, %edx
    call    libp2p_slot
    UNFRAME
END_FUNCTION libp2p_conn

/* libp2p_stream(handle) -> the stream slot, or 0. */
LOCAL_FUNCTION libp2p_stream
    FRAME
    mov     %rdi, %rcx
    mov     $ST_STREAM_OFF, %edi
    mov     $ST_STREAM_COUNT, %esi
    mov     $S_SIZE, %edx
    call    libp2p_slot
    UNFRAME
END_FUNCTION libp2p_stream

/* libp2p_peer(handle) -> the peer slot of a connected peer, or 0. */
LOCAL_FUNCTION libp2p_peer
    FRAME
    mov     %rdi, %rcx
    mov     $ST_PEER_OFF, %edi
    mov     $ST_PEER_COUNT, %esi
    mov     $P_SIZE, %edx
    call    libp2p_slot
    test    %rax, %rax
    jz      9f
    xor     %ecx, %ecx
    cmpl    $PS_CONNECTED, P_STATE(%rax)
    cmovne  %rcx, %rax
9:  UNFRAME
END_FUNCTION libp2p_peer

/*
 * libp2p_handle(table field, stride, slot) -> the handle of a slot: its index,
 * and its generation in the high 32 bits. A leaf.
 */
LOCAL_FUNCTION libp2p_handle
    UNWIND_END_PROLOGUE
    mov     %rdx, %rcx
    mov     (%r15,%rdi), %r8
    add     %r15, %r8
    mov     %rcx, %rax
    sub     %r8, %rax
    xor     %edx, %edx
    div     %rsi
    movl    (%rcx), %edx
    shl     $32, %rdx
    or      %rdx, %rax
    ret
END_FUNCTION libp2p_handle

/*
 * libp2p_alloc_slot(table field, count field, stride) -> a free slot, zeroed
 * after its generation, with the generation one higher and the in-use word
 * set to 1; 0 when every slot is in use.
 */
LOCAL_FUNCTION libp2p_alloc_slot
    ENTER   0
    mov     (%r15,%rdi), %rbx
    add     %r15, %rbx
    mov     (%r15,%rsi), %rbp
    mov     %rdx, %r12
1:  test    %rbp, %rbp
    jz      8f
    cmpl    $0, 4(%rbx)
    je      2f
    add     %r12, %rbx
    dec     %rbp
    jmp     1b
2:  movl    (%rbx), %r13d
    lea     8(%rbx), %rdi
    lea     -8(%r12), %rsi
    call    libp2p_zero
    inc     %r13d
    movl    %r13d, (%rbx)
    movl    $1, 4(%rbx)
    mov     %rbx, %rax
    jmp     9f
8:  xor     %eax, %eax
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

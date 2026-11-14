/*
 * gossipsub of the x86-64 core (/meshsub/1.1.0 with StrictNoSign, the
 * IDONTWANT of /meshsub/1.2.0, the Extensions control message of
 * /meshsub/1.3.0 and the Partial Messages extension): topics, the seen
 * cache, the message cache, messages waiting for the application, IWANT
 * promises, RPCs in and out, and the events of the application. The
 * heartbeat and scores are in heartbeat.s and score.s. Included by
 * libp2p.s.
 */

/* ---------------------------------------------------------------- Tables */

/* libp2p_peer_at(index) -> the peer slot. A leaf. */
LOCAL_FUNCTION libp2p_peer_at
    UNWIND_END_PROLOGUE
    imul    $P_SIZE, %rdi, %rax
    add     ST_PEER_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_peer_at

/* libp2p_peer_idx(peer) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_peer_idx
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    ret
END_FUNCTION libp2p_peer_idx

/* libp2p_topic_at(index) -> the topic slot. A leaf. */
LOCAL_FUNCTION libp2p_topic_at
    UNWIND_END_PROLOGUE
    imul    $T_SIZE, %rdi, %rax
    add     ST_TOPIC_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_topic_at

/* libp2p_topic_idx(topic) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_topic_idx
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    sub     ST_TOPIC_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $T_SIZE, %ecx
    div     %rcx
    ret
END_FUNCTION libp2p_topic_idx

/* libp2p_pt(peer index, topic index) -> the peer x topic entry. A leaf. */
LOCAL_FUNCTION libp2p_pt
    UNWIND_END_PROLOGUE
    mov     ST_TOPIC_COUNT(%r15), %rax
    imul    %rdi, %rax
    add     %rsi, %rax
    imul    $PT_SIZE, %rax, %rax
    add     ST_PT_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_pt

/*
 * libp2p_topic_find(name, n) -> the topic slot with the name, or 0.
 * rbx name, rbp n, r12 hash, r13 slot, X23 slots left.
 */
LOCAL_FUNCTION libp2p_topic_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_hash
    mov     %rax, %r12
    TABLE   %r13, ST_TOPIC_OFF
    mov     ST_TOPIC_COUNT(%r15), %rax
    mov     %rax, X23(%rsp)
1:  cmpq    $0, X23(%rsp)
    je      8f
    cmpq    $0, T_USED(%r13)
    je      2f
    cmp     T_HASH(%r13), %r12
    jne     2f
    lea     T_NAME(%r13), %rdi
    mov     T_LEN(%r13), %rsi
    mov     %rbx, %rdx
    mov     %rbp, %rcx
    call    libp2p_compare
    test    %rax, %rax
    jz      2f
    mov     %r13, %rax
    jmp     9f
2:  add     $T_SIZE, %r13
    decq    X23(%rsp)
    jmp     1b
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_topic_find

/* libp2p_topic_get(name, n) -> the topic slot with the name, a new one when there is none; 0 when the table is full. */
LOCAL_FUNCTION libp2p_topic_get
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_topic_find
    test    %rax, %rax
    jnz     9f
    TABLE   %r13, ST_TOPIC_OFF
    mov     ST_TOPIC_COUNT(%r15), %r12
1:  test    %r12, %r12
    jz      8f
    cmpq    $0, T_USED(%r13)
    je      2f
    add     $T_SIZE, %r13
    dec     %r12
    jmp     1b
2:  mov     %r13, %rdi
    mov     $T_SIZE, %esi
    call    libp2p_zero
    movq    $1, T_USED(%r13)
    mov     %rbp, T_LEN(%r13)
    lea     T_NAME(%r13), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_hash
    mov     %rax, T_HASH(%r13)
    mov     %r13, %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_topic_get

/* libp2p_topic_tidy(topic): a topic nobody uses and without score parameters becomes free. A leaf. */
LOCAL_FUNCTION libp2p_topic_tidy
    UNWIND_END_PROLOGUE
    mov     T_FLAGS(%rdi), %rax
    or      T_PEERS(%rdi), %rax
    or      T_MESH(%rdi), %rax
    or      T_FANOUT(%rdi), %rax
    jnz     9f
    movq    $0, T_USED(%rdi)
9:  ret
END_FUNCTION libp2p_topic_tidy

/* libp2p_gs_ready(peer) -> 1 when the peer is connected and our gossipsub stream to it is open. A leaf. */
LOCAL_FUNCTION libp2p_gs_ready
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    cmpl    $PS_CONNECTED, P_STATE(%rdi)
    jne     9f
    testq   $PF_GOSSIP, P_FLAGS(%rdi)
    jz      9f
    cmpq    $NONE, P_GS_OUT(%rdi)
    je      9f
    mov     $1, %eax
9:  ret
END_FUNCTION libp2p_gs_ready

/* ---------------------------------------------------------------- Hash indexes of message IDs */

/*
 * libp2p_idx_find(index, slots, entries, stride, id, n) -> the entry index of
 * the message ID, or NONE. The index is open addressing with linear
 * probing; a slot holds an entry index + 1, or 0. Entries hold the ID
 * length at 0 and the ID at 8.
 * rbx index, rbp slots, r12 entries, r13 stride, X23 id, X24 n, X25 slot,
 * X26 entry.
 */
LOCAL_FUNCTION libp2p_idx_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, X23(%rsp)
    mov     %r9, X24(%rsp)
    mov     %r8, %rdi
    mov     %r9, %rsi
    call    libp2p_hash
    xor     %edx, %edx
    div     %rbp
    mov     %rdx, X25(%rsp)
1:  mov     X25(%rsp), %rax
    movl    (%rbx,%rax,4), %ecx
    test    %ecx, %ecx
    jz      8f
    dec     %rcx
    mov     %rcx, X26(%rsp)
    imul    %r13, %rcx
    add     %r12, %rcx
    mov     (%rcx), %rsi
    lea     8(%rcx), %rdi
    mov     X23(%rsp), %rdx
    mov     X24(%rsp), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jnz     7f
    mov     X25(%rsp), %rax
    inc     %rax
    cmp     %rbp, %rax
    jb      2f
    xor     %eax, %eax
2:  mov     %rax, X25(%rsp)
    jmp     1b
7:  mov     X26(%rsp), %rax
    jmp     9f
8:  mov     $NONE, %rax
9:  LEAVE   0
END_FUNCTION libp2p_idx_find

/* libp2p_idx_add(index, slots, entry, hash): puts entry + 1 in the first empty slot from hash mod slots. A leaf. */
LOCAL_FUNCTION libp2p_idx_add
    UNWIND_END_PROLOGUE
    mov     %rdx, %r8
    mov     %rcx, %rax
    xor     %edx, %edx
    div     %rsi
    inc     %r8d
1:  cmpl    $0, (%rdi,%rdx,4)
    je      2f
    inc     %rdx
    cmp     %rsi, %rdx
    jb      1b
    xor     %edx, %edx
    jmp     1b
2:  movl    %r8d, (%rdi,%rdx,4)
    ret
END_FUNCTION libp2p_idx_add

/*
 * libp2p_idx_del(index, slots, entries, stride, entry): takes entry out of the
 * index and moves later entries of the probe run back, so every lookup
 * still finds its entry.
 * rbx index, rbp slots, r12 entries, r13 stride, X23 hole, X24 position,
 * X25 the slot value at the position, X26 the slot value of the entry.
 */
LOCAL_FUNCTION libp2p_idx_del
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    lea     1(%r8), %rax                    /* find the slot that holds it */
    mov     %rax, X26(%rsp)
    imul    %r13, %r8
    add     %r12, %r8
    lea     8(%r8), %rdi
    mov     (%r8), %rsi
    call    libp2p_hash
    xor     %edx, %edx
    div     %rbp
    mov     %rdx, X23(%rsp)
1:  mov     X23(%rsp), %rax
    movl    (%rbx,%rax,4), %ecx
    test    %ecx, %ecx
    jz      9f
    cmp     X26(%rsp), %rcx
    je      2f
    inc     %rax
    cmp     %rbp, %rax
    jb      11f
    xor     %eax, %eax
11: mov     %rax, X23(%rsp)
    jmp     1b
2:  mov     X23(%rsp), %rax                 /* the hole at X23 */
    mov     %rax, X24(%rsp)
3:  mov     X24(%rsp), %rax
    inc     %rax
    cmp     %rbp, %rax
    jb      31f
    xor     %eax, %eax
31: mov     %rax, X24(%rsp)
    movl    (%rbx,%rax,4), %ecx
    test    %ecx, %ecx
    jz      8f
    mov     %rcx, X25(%rsp)
    dec     %rcx                            /* the home slot of the entry at X24 */
    imul    %r13, %rcx
    add     %r12, %rcx
    lea     8(%rcx), %rdi
    mov     (%rcx), %rsi
    call    libp2p_hash
    xor     %edx, %edx
    div     %rbp
    /* move it into the hole unless its home lies cyclically in (hole, position] */
    mov     X23(%rsp), %rax
    mov     X24(%rsp), %rcx
    cmp     %rcx, %rax
    ja      4f
    cmp     %rax, %rdx
    jbe     5f
    cmp     %rcx, %rdx
    ja      5f
    jmp     3b
4:  cmp     %rax, %rdx
    ja      3b
    cmp     %rcx, %rdx
    jbe     3b
5:  mov     X25(%rsp), %rdx
    mov     X23(%rsp), %rax
    movl    %edx, (%rbx,%rax,4)
    mov     X24(%rsp), %rax
    mov     %rax, X23(%rsp)
    jmp     3b
8:  mov     X23(%rsp), %rax
    movl    $0, (%rbx,%rax,4)
9:  LEAVE   0
END_FUNCTION libp2p_idx_del

/* ---------------------------------------------------------------- Seen cache */

/* libp2p_seen_args(): rdi index, rsi slots, rdx entries, rcx stride of the seen cache. A leaf. */
LOCAL_FUNCTION libp2p_seen_args
    UNWIND_END_PROLOGUE
    mov     ST_SEEN_INDEX_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     ST_SEEN_COUNT(%r15), %rsi
    shl     $1, %rsi
    mov     ST_SEEN_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     $SN_SIZE, %ecx
    ret
END_FUNCTION libp2p_seen_args

/* libp2p_seen_find(id, n) -> the seen entry of the message ID, or 0. */
LOCAL_FUNCTION libp2p_seen_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_seen_args
    mov     %rbx, %r8
    mov     %rbp, %r9
    mov     %rdx, %r12
    call    libp2p_idx_find
    cmp     $NONE, %rax
    je      8f
    imul    $SN_SIZE, %rax, %rax
    add     %r12, %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_seen_find

/* libp2p_seen_drop_tail(): the oldest seen entry leaves the ring and the index. rbx used, rbp tail. */
LOCAL_FUNCTION libp2p_seen_drop_tail
    ENTER   0
    mov     ST_SEEN_USED(%r15), %rbx
    test    %rbx, %rbx
    jz      9f
    mov     ST_SEEN_HEAD(%r15), %rax
    mov     ST_SEEN_COUNT(%r15), %rcx
    add     %rcx, %rax                      /* tail = (head - used) mod count */
    sub     %rbx, %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rdx, %rbp
    call    libp2p_seen_args
    mov     %rbp, %r8
    call    libp2p_idx_del
    dec     %rbx
    mov     %rbx, ST_SEEN_USED(%r15)
9:  LEAVE   0
END_FUNCTION libp2p_seen_drop_tail

/* libp2p_seen_tail() -> the oldest seen entry, or 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_tail
    UNWIND_END_PROLOGUE
    mov     ST_SEEN_USED(%r15), %rcx
    test    %rcx, %rcx
    jz      8f
    mov     ST_SEEN_HEAD(%r15), %rax
    mov     ST_SEEN_COUNT(%r15), %r8
    add     %r8, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    div     %r8
    imul    $SN_SIZE, %rdx, %rax
    add     ST_SEEN_OFF(%r15), %rax
    add     %r15, %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_seen_tail

/*
 * libp2p_seen_add(id, n, topic, status) -> the new seen entry, first seen now,
 * with no deliverers. When the ring is full the oldest entry goes first.
 * rbx id, rbp n, r12 topic, r13 status, X23 head, X24 entry.
 */
LOCAL_FUNCTION libp2p_seen_add
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     ST_SEEN_USED(%r15), %rax
    cmp     ST_SEEN_COUNT(%r15), %rax
    jb      1f
    call    libp2p_seen_drop_tail
1:  mov     ST_SEEN_HEAD(%r15), %rax
    mov     %rax, X23(%rsp)
    imul    $SN_SIZE, %rax, %rax
    add     ST_SEEN_OFF(%r15), %rax
    add     %r15, %rax
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    mov     $SN_SIZE, %esi
    call    libp2p_zero
    mov     X24(%rsp), %rax
    mov     %rbp, SN_ID_LEN(%rax)
    lea     SN_ID(%rax), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    mov     X24(%rsp), %rax
    mov     SC_NOW(%r14), %rcx
    mov     %rcx, SN_TIME(%rax)
    mov     %r13, SN_STATUS(%rax)
    movl    %r12d, SN_TOPIC(%rax)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_hash
    mov     %rax, %rcx
    call    libp2p_seen_args_keep
    mov     X23(%rsp), %rdx
    call    libp2p_idx_add
    mov     ST_SEEN_HEAD(%r15), %rax
    inc     %rax
    cmp     ST_SEEN_COUNT(%r15), %rax
    jb      2f
    xor     %eax, %eax
2:  mov     %rax, ST_SEEN_HEAD(%r15)
    incq    ST_SEEN_USED(%r15)
    mov     X24(%rsp), %rax
    LEAVE   0
END_FUNCTION libp2p_seen_add

/* libp2p_seen_args_keep(): rdi the seen index and rsi its slots, leaving rdx and rcx as they are. A leaf. */
LOCAL_FUNCTION libp2p_seen_args_keep
    UNWIND_END_PROLOGUE
    mov     ST_SEEN_INDEX_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     ST_SEEN_COUNT(%r15), %rsi
    shl     $1, %rsi
    ret
END_FUNCTION libp2p_seen_args_keep

/* libp2p_seen_expire(): seen entries older than seen_ttl leave. rbx now, rbp seen_ttl. */
LOCAL_FUNCTION libp2p_seen_expire
    ENTER   0
    mov     SC_NOW(%r14), %rbx
    CFG     %rbp, LIBP2P_CFG_SEEN_TTL_MS
1:  call    libp2p_seen_tail
    test    %rax, %rax
    jz      9f
    mov     SN_TIME(%rax), %rcx
    add     %rbp, %rcx
    cmp     %rbx, %rcx
    ja      9f
    call    libp2p_seen_drop_tail
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_seen_expire

/* ---------------------------------------------------------------- Message cache */

/* libp2p_mc_args(): rdi index, rsi slots, rdx entries, rcx stride of the message cache. A leaf. */
LOCAL_FUNCTION libp2p_mc_args
    UNWIND_END_PROLOGUE
    mov     ST_MC_INDEX_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     ST_MC_COUNT(%r15), %rsi
    shl     $1, %rsi
    mov     ST_MC_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     ST_MC_STRIDE(%r15), %rcx
    ret
END_FUNCTION libp2p_mc_args

/* libp2p_mc_find(id, n) -> the message cache entry of the message ID, or 0. rbx id, rbp n, r12 entries, r13 stride. */
LOCAL_FUNCTION libp2p_mc_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_mc_args
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %rbx, %r8
    mov     %rbp, %r9
    call    libp2p_idx_find
    cmp     $NONE, %rax
    je      8f
    imul    %r13, %rax
    add     %r12, %rax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_mc_find

/* libp2p_mc_tail() -> rax the oldest message cache entry or 0, rdx its index. A leaf. */
LOCAL_FUNCTION libp2p_mc_tail
    UNWIND_END_PROLOGUE
    mov     ST_MC_USED(%r15), %rcx
    test    %rcx, %rcx
    jz      8f
    mov     ST_MC_HEAD(%r15), %rax
    mov     ST_MC_COUNT(%r15), %r8
    add     %r8, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    div     %r8
    mov     ST_MC_STRIDE(%r15), %rax
    imul    %rdx, %rax
    add     ST_MC_OFF(%r15), %rax
    add     %r15, %rax
    ret
8:  xor     %eax, %eax
    xor     %edx, %edx
    ret
END_FUNCTION libp2p_mc_tail

/* libp2p_mc_drop_tail(): the oldest message cache entry leaves, with its data. rbx entry, rbp index. */
LOCAL_FUNCTION libp2p_mc_drop_tail
    ENTER   0
    call    libp2p_mc_tail
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    mov     %rdx, %rbp
    mov     MC_DATA(%rbx), %rdi
    call    libp2p_heap_free
    movq    $0, MC_USED(%rbx)
    call    libp2p_mc_args
    mov     %rbp, %r8
    call    libp2p_idx_del
    decq    ST_MC_USED(%r15)
9:  LEAVE   0
END_FUNCTION libp2p_mc_drop_tail

/*
 * libp2p_mc_put(id, n, topic, data, length): a message in the current window of
 * the cache, which now owns the heap block of its data. When the cache is
 * full the oldest entry goes first.
 * rbx id, rbp n, r12 topic, r13 data, X23 length, X24 head, X25 entry.
 */
LOCAL_FUNCTION libp2p_mc_put
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, X23(%rsp)
    mov     ST_MC_USED(%r15), %rax
    cmp     ST_MC_COUNT(%r15), %rax
    jb      1f
    call    libp2p_mc_drop_tail
1:  mov     ST_MC_HEAD(%r15), %rax
    mov     %rax, X24(%rsp)
    call    libp2p_mc_args
    mov     X24(%rsp), %rax
    imul    %rcx, %rax
    add     %rdx, %rax
    mov     %rax, X25(%rsp)
    mov     %rax, %rdi
    mov     %rcx, %rsi
    call    libp2p_zero
    mov     X25(%rsp), %rax
    mov     %rbp, MC_ID_LEN(%rax)
    lea     MC_ID(%rax), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    mov     X25(%rsp), %rax
    mov     %r12, MC_TOPIC(%rax)
    mov     %r13, MC_DATA(%rax)
    mov     X23(%rsp), %rcx
    mov     %rcx, MC_DATA_LEN(%rax)
    mov     ST_HEARTBEATS(%r15), %rcx
    mov     %rcx, MC_WINDOW(%rax)
    movq    $1, MC_USED(%rax)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_hash
    mov     %rax, %rcx
    mov     ST_MC_INDEX_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     ST_MC_COUNT(%r15), %rsi
    shl     $1, %rsi
    mov     X24(%rsp), %rdx
    call    libp2p_idx_add
    mov     ST_MC_HEAD(%r15), %rax
    inc     %rax
    cmp     ST_MC_COUNT(%r15), %rax
    jb      2f
    xor     %eax, %eax
2:  mov     %rax, ST_MC_HEAD(%r15)
    incq    ST_MC_USED(%r15)
    LEAVE   0
END_FUNCTION libp2p_mc_put

/* libp2p_mc_shift(): entries of windows mcache_len or more heartbeats old leave. rbx heartbeats, rbp mcache_len. */
LOCAL_FUNCTION libp2p_mc_shift
    ENTER   0
    mov     ST_HEARTBEATS(%r15), %rbx
    CFG     %rbp, LIBP2P_CFG_MCACHE_LEN
1:  call    libp2p_mc_tail
    test    %rax, %rax
    jz      9f
    mov     MC_WINDOW(%rax), %rcx
    add     %rbp, %rcx
    cmp     %rbx, %rcx
    ja      9f
    call    libp2p_mc_drop_tail
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_mc_shift

/*
 * libp2p_mc_sent(entry, peer index) -> 1 when the message may go to the peer
 * for an IWANT once more (fewer than retransmission sends), counting it;
 * else 0. Two bits for each peer. A leaf.
 */
LOCAL_FUNCTION libp2p_mc_sent
    UNWIND_END_PROLOGUE
    mov     %rsi, %rdx
    shr     $5, %rdx                        /* word */
    mov     %rsi, %rcx
    and     $31, %rcx
    shl     $1, %rcx                        /* bit */
    mov     MC_TX(%rdi,%rdx,8), %r8
    mov     %r8, %r9
    shr     %cl, %r9
    and     $3, %r9
    mov     (ST_CONFIG + LIBP2P_CFG_RETRANSMISSION)(%r15), %r10
    mov     $3, %r11d
    cmp     %r11, %r10
    cmovae  %r11, %r10
    cmp     %r10, %r9
    jae     8f
    mov     $1, %eax
    shl     %cl, %rax
    add     %rax, %r8
    mov     %r8, MC_TX(%rdi,%rdx,8)
    mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_mc_sent

/* ---------------------------------------------------------------- Messages waiting for the application */

/* libp2p_pend(handle) -> the pending message of a handle, or 0. */
LOCAL_FUNCTION libp2p_pend
    FRAME
    mov     %rdi, %rcx
    mov     $ST_PEND_OFF, %edi
    mov     $ST_PEND_COUNT, %esi
    mov     $PD_SIZE, %edx
    call    libp2p_slot
    UNFRAME
END_FUNCTION libp2p_pend

/* libp2p_pend_free(pending): frees its data block (when it still owns one) and the slot. */
LOCAL_FUNCTION libp2p_pend_free
    ENTER   0
    mov     %rdi, %rbx
    mov     PD_DATA(%rbx), %rdi
    call    libp2p_heap_free
    movq    $0, PD_DATA(%rbx)
    movl    $0, PD_STATE(%rbx)
    LEAVE   0
END_FUNCTION libp2p_pend_free

/* libp2p_pend_status(pending, status): MESSAGE_STATUS for the application. */
LOCAL_FUNCTION libp2p_pend_status
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $LIBP2P_ACTION_MESSAGE_STATUS, %edi
    mov     $LIBP2P_ACT_STATUS_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, %r12
    mov     $ST_PEND_OFF, %edi
    mov     $PD_SIZE, %esi
    mov     %rbx, %rdx
    call    libp2p_handle
    mov     %rax, LIBP2P_ACT_HANDLE(%r12)
    mov     %rbp, LIBP2P_ACT_STATUS(%r12)
9:  LEAVE   0
END_FUNCTION libp2p_pend_status

/* ---------------------------------------------------------------- IWANT promises */

/*
 * libp2p_promise_add(peer index, id, n): a promise of the peer to send the
 * message within iwant_followup. Full: nothing.
 * rbx peer index, rbp id, r12 n, r13 promise, X23 promises left.
 */
LOCAL_FUNCTION libp2p_promise_add
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    TABLE   %r13, ST_PROMISE_OFF
    movq    $LIBP2P_PROMISES, X23(%rsp)
1:  cmpq    $0, X23(%rsp)
    je      9f
    cmpq    $NONE, PR_PEER(%r13)
    je      2f
    add     $PR_SIZE, %r13
    decq    X23(%rsp)
    jmp     1b
2:  mov     %rbx, PR_PEER(%r13)
    mov     SC_NOW(%r14), %rax
    add     (ST_CONFIG + LIBP2P_CFG_IWANT_FOLLOWUP_MS)(%r15), %rax
    mov     %rax, PR_DEADLINE(%r13)
    mov     %r12, PR_ID_LEN(%r13)
    lea     PR_ID(%r13), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_promise_add

/* libp2p_promise_keep(id, n): the message came: every promise of it is kept. rbx id, rbp n, r12 promise, r13 left. */
LOCAL_FUNCTION libp2p_promise_keep
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    TABLE   %r12, ST_PROMISE_OFF
    mov     $LIBP2P_PROMISES, %r13d
1:  test    %r13, %r13
    jz      9f
    cmpq    $NONE, PR_PEER(%r12)
    je      2f
    lea     PR_ID(%r12), %rdi
    mov     PR_ID_LEN(%r12), %rsi
    mov     %rbx, %rdx
    mov     %rbp, %rcx
    call    libp2p_compare
    test    %rax, %rax
    jz      2f
    movq    $NONE, PR_PEER(%r12)
2:  add     $PR_SIZE, %r12
    dec     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_promise_keep

/* libp2p_promise_drop_peer(peer index): the promises of a peer that left are forgotten. A leaf. */
LOCAL_FUNCTION libp2p_promise_drop_peer
    UNWIND_END_PROLOGUE
    mov     ST_PROMISE_OFF(%r15), %rax
    add     %r15, %rax
    mov     $LIBP2P_PROMISES, %ecx
1:  test    %rcx, %rcx
    jz      9f
    cmp     PR_PEER(%rax), %rdi
    jne     2f
    movq    $NONE, PR_PEER(%rax)
2:  add     $PR_SIZE, %rax
    dec     %rcx
    jmp     1b
9:  ret
END_FUNCTION libp2p_promise_drop_peer

/* ---------------------------------------------------------------- IDONTWANT */

/* libp2p_dw_ring(peer index) -> the first entry of the peer's IDONTWANT ring. A leaf. */
LOCAL_FUNCTION libp2p_dw_ring
    UNWIND_END_PROLOGUE
    imul    $DW_SIZE, (ST_CONFIG + LIBP2P_CFG_DONTWANT_SLOTS)(%r15), %rax
    imul    %rdi, %rax
    add     ST_DW_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_dw_ring

/*
 * libp2p_dontwant(peer index, id, n) -> 1 when the peer sent IDONTWANT for
 * the message ID within the last dontwant_ttl heartbeats, else 0.
 * rbx id, rbp n, r12 entry, r13 entries left.
 */
LOCAL_FUNCTION libp2p_dontwant
    ENTER   0
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     (ST_CONFIG + LIBP2P_CFG_DONTWANT_SLOTS)(%r15), %r13
    test    %r13, %r13
    jz      8f
    call    libp2p_dw_ring
    mov     %rax, %r12
1:  cmp     DW_ID_LEN(%r12), %rbp
    jne     2f
    mov     ST_HEARTBEATS(%r15), %rax
    sub     DW_HB(%r12), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_DONTWANT_TTL)(%r15), %rax
    jae     2f
    lea     DW_ID(%r12), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_equal
    test    %rax, %rax
    jnz     7f
2:  add     $DW_SIZE, %r12
    dec     %r13
    jnz     1b
8:  xor     %eax, %eax
    jmp     9f
7:  mov     $1, %eax
9:  LEAVE   0
END_FUNCTION libp2p_dontwant

/* ---------------------------------------------------------------- RPCs out */

/*
 * libp2p_gs_alloc(n) -> rax the place for n bytes of a send chunk, rdx the
 * chunk (a state offset, for libp2p_gs_push); rax = 0 when the heap is full.
 */
LOCAL_FUNCTION libp2p_gs_alloc
    ENTER   0
    mov     %rdi, %rbx
    lea     (CH_DATA - HB_HEADER)(%rdi), %rdi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdx
    lea     -HB_HEADER(%r15,%rax), %rcx
    movq    $NONE, CH_NEXT(%rcx)
    mov     %rbx, CH_LEN(%rcx)
    movq    $0, CH_DONE(%rcx)
    lea     CH_DATA(%rcx), %rax
9:  LEAVE   0
END_FUNCTION libp2p_gs_alloc

/*
 * libp2p_gs_push(peer, chunk) -> 1 when the chunk is queued on our gossipsub
 * stream to the peer; 0 when the peer is not ready or its queue is past
 * stream_queue (the chunk is then freed).
 * rbx peer, rbp chunk, r12 stream, r13 the chunk's block.
 */
LOCAL_FUNCTION libp2p_gs_push
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_gs_ready
    test    %rax, %rax
    jz      8f
    mov     P_GS_OUT(%rbx), %rdi
    call    libp2p_stream_at
    mov     %rax, %r12
    mov     S_Q_BYTES(%r12), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_STREAM_QUEUE)(%r15), %rax
    ja      8f
    lea     -HB_HEADER(%r15,%rbp), %r13
    mov     S_Q_TAIL(%r12), %rax
    cmp     $NONE, %rax
    jne     1f
    mov     %rbp, S_Q_HEAD(%r12)
    jmp     2f
1:  mov     %rbp, (CH_NEXT - HB_HEADER)(%r15,%rax)
2:  mov     %rbp, S_Q_TAIL(%r12)
    mov     CH_LEN(%r13), %rax
    add     %rax, S_Q_BYTES(%r12)
    mov     $1, %eax
    jmp     9f
8:  mov     %rbp, %rdi
    call    libp2p_heap_free
    xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_gs_push

/* libp2p_pb_head(dst, field, n) -> dst after the key of a type 2 field and the length n. */
LOCAL_FUNCTION libp2p_pb_head
    ENTER   0
    mov     %rdx, %rbx
    shl     $3, %rsi
    or      $2, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_head

/*
 * libp2p_gs_rpc(peer, inner, inner size, field) -> rax the place for inner size
 * bytes, after the varint length of the RPC and the head of its field; rdx
 * the chunk (libp2p_gs_push sends it). rax = 0 when the heap is full.
 * The RPC is one field (subscriptions 1, publish 2, control 3 or partial
 * 10) of inner size bytes.
 * rbx peer, r12 inner size, r13 field, X23 the RPC size, X24 the chunk.
 */
LOCAL_FUNCTION libp2p_gs_rpc
    ENTER   0
    mov     %rdi, %rbx
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r13, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_size                      /* the RPC */
    mov     %rax, X23(%rsp)
    mov     %rax, %rdi
    call    libp2p_varint_len
    add     X23(%rsp), %rax
    mov     %rax, %rdi
    call    libp2p_gs_alloc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X24(%rsp)
    mov     %rax, %rdi
    mov     X23(%rsp), %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %r13, %rsi
    mov     %r12, %rdx
    call    libp2p_pb_head
    mov     X24(%rsp), %rdx
9:  LEAVE   0
END_FUNCTION libp2p_gs_rpc

/*
 * libp2p_gs_send_sub(peer, topic, subscribe): an RPC with one SubOpts:
 * subscribe (1) and topicid (2); for a subscription, requestsPartial (3) and
 * supportsSendingPartial (4) when our partial flags of the topic have them.
 * rbx peer, rbp topic, r12 subscribe, r13 flags, X23 chunk.
 */
LOCAL_FUNCTION libp2p_gs_send_sub
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    xor     %r13d, %r13d
    test    %r12, %r12
    jz      1f
    mov     T_FLAGS(%rbp), %r13
    shr     $2, %r13
    and     $3, %r13d                       /* LIBP2P_PARTIAL_* */
1:  mov     $2, %edi
    mov     T_LEN(%rbp), %rsi
    call    libp2p_pb_size
    lea     2(%rax), %rdx                   /* subscribe (field 1, a varint 0 or 1), topicid (field 2) */
    mov     %r13, %rax                      /* 2 bytes for each partial field */
    and     $1, %eax
    lea     (%rdx,%rax,2), %rdx
    mov     %r13, %rax
    shr     $1, %rax
    lea     (%rdx,%rax,2), %rdx
    mov     %rbx, %rdi
    mov     $1, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X23(%rsp)
    movb    $0x08, (%rax)
    movb    %r12b, 1(%rax)
    lea     2(%rax), %rdi
    mov     $2, %esi
    lea     T_NAME(%rbp), %rdx
    mov     T_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    test    $1, %r13
    jz      2f
    movw    $0x0118, (%rax)                 /* requestsPartial: true */
    add     $2, %rax
2:  test    $2, %r13
    jz      3f
    movw    $0x0120, (%rax)                 /* supportsSendingPartial: true */
3:  mov     %rbx, %rdi
    mov     X23(%rsp), %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_sub

/*
 * libp2p_gs_send_ext(peer): with partial_messages on, an RPC whose control
 * holds our Extensions control message (field 6): partialMessages (field
 * 10) set.
 * rbx peer.
 */
LOCAL_FUNCTION libp2p_gs_send_ext
    ENTER   0
    mov     %rdi, %rbx
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)(%r15)
    je      9f
    mov     $4, %edx                        /* ControlMessage: extensions of 2 bytes */
    mov     $3, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    movl    $0x01500232, (%rax)             /* field 6, type 2, length 2; field 10, type 0: true */
    mov     %rbx, %rdi
    mov     %rdx, %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_ext

/*
 * libp2p_gs_send_partial(peer, event, with message): an RPC with one
 * PartialMessagesExtension (field 10) from a PARTIAL_SEND event: topicID
 * (1), groupID (2), partialMessage (3) when with message is 1 and it has
 * bytes, partsMetadata (4) when it has bytes.
 * rbx peer, rbp event, r12 with message, r13 inner size, X23 chunk,
 * X24 topic, X25 group, X26 metadata.
 */
LOCAL_FUNCTION libp2p_gs_send_partial
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmpq    $0, LIBP2P_EV_PSEND_MSG_LEN(%rbp)
    jne     1f
    xor     %r12d, %r12d
1:  lea     LIBP2P_EV_PSEND_BYTES(%rbp), %rax /* each part at a multiple of 8 */
    mov     %rax, X24(%rsp)
    mov     LIBP2P_EV_PSEND_TOPIC_LEN(%rbp), %rcx
    add     $7, %rcx
    and     $~7, %rcx
    add     %rcx, %rax
    mov     %rax, X25(%rsp)
    mov     LIBP2P_EV_PSEND_GROUP_LEN(%rbp), %rcx
    add     $7, %rcx
    and     $~7, %rcx
    add     %rcx, %rax
    mov     %rax, X26(%rsp)
    mov     $1, %edi                        /* the inner size */
    mov     LIBP2P_EV_PSEND_TOPIC_LEN(%rbp), %rsi
    call    libp2p_pb_size
    mov     %rax, %r13
    mov     $2, %edi
    mov     LIBP2P_EV_PSEND_GROUP_LEN(%rbp), %rsi
    call    libp2p_pb_size
    add     %rax, %r13
    mov     LIBP2P_EV_PSEND_META_LEN(%rbp), %rsi
    test    %rsi, %rsi
    jz      2f
    mov     $4, %edi
    call    libp2p_pb_size
    add     %rax, %r13
2:  test    %r12, %r12
    jz      3f
    mov     $3, %edi
    mov     LIBP2P_EV_PSEND_MSG_LEN(%rbp), %rsi
    call    libp2p_pb_size
    add     %rax, %r13
3:  mov     %rbx, %rdi
    mov     %r13, %rdx
    mov     $10, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X23(%rsp)
    mov     %rax, %rdi
    mov     $1, %esi
    mov     X24(%rsp), %rdx
    mov     LIBP2P_EV_PSEND_TOPIC_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    mov     $2, %esi
    mov     X25(%rsp), %rdx
    mov     LIBP2P_EV_PSEND_GROUP_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    test    %r12, %r12
    jz      4f
    mov     %rax, %rdi
    mov     LIBP2P_EV_PSEND_META_LEN(%rbp), %rdx
    add     $7, %rdx
    and     $~7, %rdx
    add     X26(%rsp), %rdx                 /* the message */
    mov     $3, %esi
    mov     LIBP2P_EV_PSEND_MSG_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
4:  mov     LIBP2P_EV_PSEND_META_LEN(%rbp), %rcx
    test    %rcx, %rcx
    jz      5f
    mov     %rax, %rdi
    mov     $4, %esi
    mov     X26(%rsp), %rdx
    call    libp2p_pb_bytes
5:  mov     %rbx, %rdi
    mov     X23(%rsp), %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_partial

/*
 * libp2p_gs_send_msg(peer, topic, data, n): an RPC that publishes one message:
 * data (field 2) and topic (field 4).
 * rbx peer, rbp topic, r12 data, r13 n, X23 inner size, X24 chunk.
 */
LOCAL_FUNCTION libp2p_gs_send_msg
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     $2, %edi
    mov     %r13, %rsi
    call    libp2p_pb_size
    mov     %rax, X23(%rsp)
    mov     $4, %edi
    mov     T_LEN(%rbp), %rsi
    call    libp2p_pb_size
    add     X23(%rsp), %rax
    mov     %rax, %rdx
    mov     %rbx, %rdi
    mov     $2, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X24(%rsp)
    mov     %rax, %rdi
    mov     $2, %esi
    mov     %r12, %rdx
    mov     %r13, %rcx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    mov     $4, %esi
    lea     T_NAME(%rbp), %rdx
    mov     T_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    mov     %rbx, %rdi
    mov     X24(%rsp), %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_msg

/* libp2p_gs_send_graft(peer, topic): control with one GRAFT. rbx peer, rbp topic, r12 the ControlGraft size, r13 chunk. */
LOCAL_FUNCTION libp2p_gs_send_graft
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $1, %edi
    mov     T_LEN(%rbp), %rsi
    call    libp2p_pb_size
    mov     %rax, %r12                      /* ControlGraft */
    mov     $3, %edi
    mov     %r12, %rsi
    call    libp2p_pb_size
    mov     %rax, %rdx                      /* ControlMessage */
    mov     %rbx, %rdi
    mov     $3, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, %r13
    mov     %rax, %rdi
    mov     $3, %esi
    mov     %r12, %rdx
    call    libp2p_pb_head
    mov     %rax, %rdi
    mov     $1, %esi
    lea     T_NAME(%rbp), %rdx
    mov     T_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_graft

/*
 * libp2p_gs_send_prune(peer, topic, backoff seconds): control with one PRUNE:
 * topicID (1), backoff (3). rbx peer, rbp topic, r12 the ControlPrune size,
 * r13 chunk, X23 backoff.
 */
LOCAL_FUNCTION libp2p_gs_send_prune
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, X23(%rsp)
    mov     $1, %edi
    mov     T_LEN(%rbp), %rsi
    call    libp2p_pb_size
    mov     %rax, %r12
    mov     X23(%rsp), %rdi
    call    libp2p_varint_len
    add     %rax, %r12
    inc     %r12                            /* ControlPrune */
    mov     $4, %edi
    mov     %r12, %rsi
    call    libp2p_pb_size
    mov     %rax, %rdx
    mov     %rbx, %rdi
    mov     $3, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, %r13
    mov     %rax, %rdi
    mov     $4, %esi
    mov     %r12, %rdx
    call    libp2p_pb_head
    mov     %rax, %rdi
    mov     $1, %esi
    lea     T_NAME(%rbp), %rdx
    mov     T_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    mov     $3, %esi
    mov     X23(%rsp), %rdx
    call    libp2p_pb_varint
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_prune

/*
 * libp2p_gs_send_ids(peer, topic, list, count, kind): control with one IHAVE
 * (kind 1: topicID, then messageIDs as field 2), one IWANT (kind 2) or one
 * IDONTWANT (kind 5): messageIDs as field 1, no topic. The kind is the
 * field of the ControlMessage. list holds count pairs: the address of an
 * ID, then its length.
 * rbx peer, rbp topic, r12 list, r13 count, X23 kind, X24 inner size,
 * X25 i, X26 chunk; 32(%rsp) the position.
 */
LOCAL_FUNCTION libp2p_gs_send_ids
    ENTER   16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, X23(%rsp)
    movq    $0, X24(%rsp)
    cmp     $1, %r8
    jne     1f
    mov     $1, %edi
    mov     T_LEN(%rbp), %rsi
    call    libp2p_pb_size
    mov     %rax, X24(%rsp)
1:  movq    $0, X25(%rsp)
2:  mov     X25(%rsp), %rax
    cmp     %r13, %rax
    jae     3f
    shl     $4, %rax
    mov     8(%r12,%rax), %rsi
    mov     $1, %edi
    mov     $2, %ecx
    cmpq    $1, X23(%rsp)
    cmove   %rcx, %rdi
    call    libp2p_pb_size
    add     %rax, X24(%rsp)
    incq    X25(%rsp)
    jmp     2b
3:  mov     X23(%rsp), %rdi
    mov     X24(%rsp), %rsi
    call    libp2p_pb_size
    mov     %rax, %rdx
    mov     %rbx, %rdi
    mov     $3, %ecx
    call    libp2p_gs_rpc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X26(%rsp)
    mov     %rax, %rdi
    mov     X23(%rsp), %rsi
    mov     X24(%rsp), %rdx
    call    libp2p_pb_head
    mov     %rax, 32(%rsp)
    cmpq    $1, X23(%rsp)
    jne     4f
    mov     %rax, %rdi
    mov     $1, %esi
    lea     T_NAME(%rbp), %rdx
    mov     T_LEN(%rbp), %rcx
    call    libp2p_pb_bytes
    mov     %rax, 32(%rsp)
4:  movq    $0, X25(%rsp)
5:  mov     X25(%rsp), %rax
    cmp     %r13, %rax
    jae     6f
    shl     $4, %rax
    mov     (%r12,%rax), %rdx
    mov     8(%r12,%rax), %rcx
    mov     $1, %esi
    mov     $2, %eax
    cmpq    $1, X23(%rsp)
    cmove   %rax, %rsi
    mov     32(%rsp), %rdi
    call    libp2p_pb_bytes
    mov     %rax, 32(%rsp)
    incq    X25(%rsp)
    jmp     5b
6:  mov     %rbx, %rdi
    mov     X26(%rsp), %rsi
    call    libp2p_gs_push
9:  LEAVE   16
END_FUNCTION libp2p_gs_send_ids

/*
 * libp2p_gs_idontwant(pending): a new message of idontwant_threshold bytes
 * or more: IDONTWANT with its ID, at once, to each mesh peer of its topic
 * that speaks /meshsub/1.2.0, except the peer that sent it and the peers
 * that send us partial messages of the topic (libp2p_sends_partial).
 * rbx pending, rbp list, r12 count, r13 i.
 */
LOCAL_FUNCTION libp2p_gs_idontwant
    ENTER   0
    mov     %rdi, %rbx
    mov     (ST_CONFIG + LIBP2P_CFG_IDONTWANT_THRESHOLD)(%r15), %rax
    test    %rax, %rax
    jz      9f
    cmp     %rax, PD_DATA_LEN(%rbx)
    jb      9f
    SCR     %rcx, SC_IDS                    /* the one ID */
    lea     PD_ID(%rbx), %rax
    mov     %rax, (%rcx)
    mov     PD_ID_LEN(%rbx), %rax
    mov     %rax, 8(%rcx)
    movabs  $0xFFF0000000000000, %rax       /* the mesh, at any score: -infinity */
    movq    %rax, %xmm0
    mov     PD_TOPIC(%rbx), %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, %r12
    SCR     %rbp, SC_LIST
    xor     %r13d, %r13d
1:  cmp     %r12, %r13
    jae     9f
    movl    (%rbp,%r13,4), %edi
    cmp     PD_PEER(%rbx), %rdi
    je      2f
    mov     PD_TOPIC(%rbx), %rsi
    call    libp2p_sends_partial
    test    %rax, %rax
    jnz     2f
    movl    (%rbp,%r13,4), %edi
    call    libp2p_peer_at
    testq   $PF_IDONTWANT, P_FLAGS(%rax)
    jz      2f
    mov     %rax, %rdi
    xor     %esi, %esi
    SCR     %rdx, SC_IDS
    mov     $1, %ecx
    mov     $5, %r8d
    call    libp2p_gs_send_ids
2:  inc     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_idontwant

/* libp2p_gs_announce(topic, subscribe): our subscription change, to every gossipsub peer. rbx topic, rbp subscribe, r12 peer, r13 left. */
LOCAL_FUNCTION libp2p_gs_announce
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    TABLE   %r12, ST_PEER_OFF
    mov     ST_PEER_COUNT(%r15), %r13
1:  test    %r13, %r13
    jz      9f
    mov     %r12, %rdi
    call    libp2p_gs_ready
    test    %rax, %rax
    jz      2f
    mov     %r12, %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_gs_send_sub
2:  add     $P_SIZE, %r12
    dec     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_announce

.include "gossip_in.s"
.include "heartbeat.s"
.include "score.s"

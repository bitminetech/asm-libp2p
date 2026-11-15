/*
 * The node of the x86-64 core: the state layout, libp2p_state_size,
 * libp2p_init, libp2p_step, event checks and timers. Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Layout */

/* Branch to fail unless lo <= reg <= hi. Uses r11; reg is not r11. */
.macro RANGE reg, lo, hi, fail
    movabs  $\lo, %r11
    cmp     %r11, \reg
    jb      \fail
    movabs  $\hi, %r11
    cmp     %r11, \reg
    ja      \fail
.endm

/* reg = reg aligned up to a multiple of 8. */
.macro ALIGN8 reg
    add     $7, \reg
    and     $-8, \reg
.endm

/*
 * libp2p_layout(config, tables) -> rax status, rdx the state size. Checks the
 * config and writes the table offsets and counts at tables (the ST_TABLES
 * fields), in this order: connections, streams, peers, topics, peer x
 * topic, seen, seen index, message cache, its index, pending, promises,
 * protocols, IDONTWANT rings, heap; with QUIC on, then the asm-quic stream
 * and connection maps, the asm-quic event and action lists, and the
 * asm-quic state, whose config quic_state_size checks.
 * rbx config, rbp tables, r12 offset, r13 connections then other counts;
 * X23 streams, X24 peers, X25 topics, X26 protocols. The asm-quic Config at
 * 32(%rsp), its state size at 32 + QUIC_CFG_SIZE.
 */
LOCAL_FUNCTION libp2p_layout
    ENTER   0, (QUIC_CFG_SIZE + 16)
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    cmpq    $LIBP2P_CFG_FIXED, LIBP2P_CFG_SIZE(%rbx)
    jb      80f
    mov     LIBP2P_CFG_KEY_TYPE(%rbx), %rax
    RANGE   %rax, 1, 2, 80f
    mov     LIBP2P_CFG_MUXERS(%rbx), %rax
    RANGE   %rax, 1, 3, 80f
    mov     LIBP2P_CFG_MAX_CONNECTIONS(%rbx), %r13
    RANGE   %r13, 1, 65536, 80f
    mov     LIBP2P_CFG_MAX_STREAMS(%rbx), %rax
    RANGE   %rax, 1, 1048576, 80f
    mov     %rax, X23(%rsp)
    mov     LIBP2P_CFG_MAX_PEERS(%rbx), %rax
    cmp     %r13, %rax
    jb      80f
    RANGE   %rax, 1, 65535, 80f
    mov     %rax, X24(%rsp)
    mov     LIBP2P_CFG_MAX_TOPICS(%rbx), %rax
    RANGE   %rax, 1, 4096, 80f
    mov     %rax, X25(%rsp)
    mov     LIBP2P_CFG_HEAP_SIZE(%rbx), %rax
    RANGE   %rax, 65536, 0x10000000000, 80f
    lea     -1(%rax), %rcx
    test    %rcx, %rax
    jnz     80f
    mov     LIBP2P_CFG_SEEN_CAPACITY(%rbx), %rax
    RANGE   %rax, 1, 16777216, 80f
    mov     LIBP2P_CFG_MCACHE_CAPACITY(%rbx), %rax
    RANGE   %rax, 1, 1048576, 80f
    mov     LIBP2P_CFG_PENDING_CAPACITY(%rbx), %rax
    RANGE   %rax, 1, 1048576, 80f
    mov     LIBP2P_CFG_SEND_WINDOW(%rbx), %rax
    RANGE   %rax, 131072, 0x40000000, 80f
    mov     LIBP2P_CFG_MAX_RPC(%rbx), %rax
    RANGE   %rax, 1024, 0x40000000, 80f
    mov     LIBP2P_CFG_MAX_DATA(%rbx), %rcx
    cmp     %rax, %rcx
    ja      80f
    mov     LIBP2P_CFG_STREAM_QUEUE(%rbx), %rax
    RANGE   %rax, 65536, 0x40000000, 80f
    cmpq    $0, LIBP2P_CFG_HANDSHAKE_MS(%rbx)
    je      80f
    cmpq    $0, LIBP2P_CFG_VALIDATION_MS(%rbx)
    je      80f
    mov     LIBP2P_CFG_D(%rbx), %rax        /* gossipsub degrees */
    RANGE   %rax, 1, 64, 80f
    mov     LIBP2P_CFG_D_LOW(%rbx), %rcx
    cmp     %rax, %rcx
    ja      80f
    mov     LIBP2P_CFG_D_HIGH(%rbx), %rdx
    cmp     %rax, %rdx
    jb      80f
    RANGE   %rdx, 1, 64, 80f
    mov     LIBP2P_CFG_D_LAZY(%rbx), %r8
    RANGE   %r8, 0, 64, 80f
    mov     LIBP2P_CFG_D_SCORE(%rbx), %r8
    cmp     %rdx, %r8
    ja      80f
    mov     LIBP2P_CFG_D_OUT(%rbx), %r8
    cmp     %rcx, %r8
    ja      80f
    cmpq    $0, LIBP2P_CFG_HEARTBEAT_MS(%rbx)
    je      80f
    mov     LIBP2P_CFG_MCACHE_LEN(%rbx), %rax
    RANGE   %rax, 1, 64, 80f
    mov     LIBP2P_CFG_MCACHE_GOSSIP(%rbx), %rcx
    cmp     %rax, %rcx
    ja      80f
    cmpq    $0, LIBP2P_CFG_SEEN_TTL_MS(%rbx)
    je      80f
    mov     LIBP2P_CFG_MAX_IHAVE_LENGTH(%rbx), %rax
    RANGE   %rax, 0, 8192, 80f
    mov     LIBP2P_CFG_AGENT_LEN(%rbx), %rax
    RANGE   %rax, 0, 64, 80f
    mov     LIBP2P_CFG_PV_LEN(%rbx), %rax
    RANGE   %rax, 0, 32, 80f
    mov     LIBP2P_CFG_SCORING(%rbx), %rax
    RANGE   %rax, 0, 1, 80f
    test    %rax, %rax
    jz      1f
    cmpq    $0, LIBP2P_CFG_DECAY_INTERVAL_MS(%rbx)
    je      80f
1:  mov     LIBP2P_CFG_GOSSIPSUB_V12(%rbx), %rax    /* gossipsub v1.2 */
    RANGE   %rax, 0, 1, 80f
    mov     LIBP2P_CFG_DONTWANT_SLOTS(%rbx), %rax
    RANGE   %rax, 0, 4096, 80f
    test    %rax, %rax
    jz      11f
    cmpq    $0, LIBP2P_CFG_DONTWANT_TTL(%rbx)
    je      80f
11: mov     LIBP2P_CFG_GOSSIPSUB_V13(%rbx), %rax    /* gossipsub v1.3: needs v1.2 */
    RANGE   %rax, 0, 1, 80f
    test    %rax, %rax
    jz      12f
    cmpq    $0, LIBP2P_CFG_GOSSIPSUB_V12(%rbx)
    je      80f
12: mov     LIBP2P_CFG_PARTIAL_MESSAGES(%rbx), %rcx /* partial messages: need v1.3 */
    RANGE   %rcx, 0, 1, 80f
    cmp     %rax, %rcx
    ja      80f
    mov     LIBP2P_CFG_QUIC(%rbx), %rax     /* QUIC: off, on, or on and accepting */
    cmp     $(LIBP2P_QUIC_ON | LIBP2P_QUIC_ACCEPT), %rax
    ja      80f
    cmp     $LIBP2P_QUIC_ACCEPT, %rax
    je      80f
    test    %rax, %rax
    jz      13f
    mov     LIBP2P_CFG_QUIC_WINDOW(%rbx), %rax
    RANGE   %rax, 65536, 0x40000000, 80f
13:

    /* The protocols part. */
    mov     LIBP2P_CFG_PROTOCOLS_COUNT(%rbx), %r9
    RANGE   %r9, 0, 64, 80f
    mov     %r9, X26(%rsp)
    test    %r9, %r9
    jz      3f
    mov     LIBP2P_CFG_PROTOCOLS(%rbx), %rax
    test    $7, %rax
    jnz     80f
    cmp     $LIBP2P_CFG_FIXED, %rax
    jb      80f
    imul    $LIBP2P_PROTO_SIZE, %r9, %rcx
    add     %rax, %rcx
    cmp     LIBP2P_CFG_SIZE(%rbx), %rcx
    ja      80f
    add     %rbx, %rax
2:  mov     LIBP2P_PROTO_LEN(%rax), %rcx
    RANGE   %rcx, 1, LIBP2P_MAX_PROTOCOL, 80f
    lea     LIBP2P_PROTO_BYTES(%rax), %rdx
21: movzbl  (%rdx), %r8d
    inc     %rdx
    cmp     $10, %r8d
    je      80f
    dec     %rcx
    jnz     21b
    add     $LIBP2P_PROTO_SIZE, %rax
    dec     %r9
    jnz     2b

    /* The tables. */
3:  mov     $ST_FIXED, %r12d
    ALIGN8  %r12
    mov     %r12, (ST_CONN_OFF - ST_TABLES)(%rbp)
    mov     %r13, (ST_CONN_COUNT - ST_TABLES)(%rbp)
    imul    $C_SIZE, %r13, %rax
    add     %rax, %r12
    mov     %r12, (ST_STREAM_OFF - ST_TABLES)(%rbp)
    mov     X23(%rsp), %rax
    mov     %rax, (ST_STREAM_COUNT - ST_TABLES)(%rbp)
    imul    $S_SIZE, %rax, %rax
    add     %rax, %r12
    mov     %r12, (ST_PEER_OFF - ST_TABLES)(%rbp)
    mov     X24(%rsp), %rax
    mov     %rax, (ST_PEER_COUNT - ST_TABLES)(%rbp)
    imul    $P_SIZE, %rax, %rax
    add     %rax, %r12
    mov     %r12, (ST_TOPIC_OFF - ST_TABLES)(%rbp)
    mov     X25(%rsp), %rax
    mov     %rax, (ST_TOPIC_COUNT - ST_TABLES)(%rbp)
    imul    $T_SIZE, %rax, %rax
    add     %rax, %r12
    mov     %r12, (ST_PT_OFF - ST_TABLES)(%rbp)
    mov     X24(%rsp), %rax
    imul    X25(%rsp), %rax
    imul    $PT_SIZE, %rax, %rax
    add     %rax, %r12
    mov     LIBP2P_CFG_SEEN_CAPACITY(%rbx), %r13
    mov     %r12, (ST_SEEN_OFF - ST_TABLES)(%rbp)
    mov     %r13, (ST_SEEN_COUNT - ST_TABLES)(%rbp)
    imul    $SN_SIZE, %r13, %rax
    add     %rax, %r12
    mov     %r12, (ST_SEEN_INDEX_OFF - ST_TABLES)(%rbp)
    lea     (%r12,%r13,8), %r12             /* 2 x capacity u32 */
    mov     LIBP2P_CFG_MCACHE_CAPACITY(%rbx), %r13
    mov     %r12, (ST_MC_OFF - ST_TABLES)(%rbp)
    mov     %r13, (ST_MC_COUNT - ST_TABLES)(%rbp)
    mov     X24(%rsp), %rax                 /* 2 bits for each peer, in u64 words */
    add     $31, %rax
    shr     $5, %rax
    shl     $3, %rax
    add     $MC_TX, %rax
    mov     %rax, (ST_MC_STRIDE - ST_TABLES)(%rbp)
    imul    %r13, %rax
    add     %rax, %r12
    mov     %r12, (ST_MC_INDEX_OFF - ST_TABLES)(%rbp)
    lea     (%r12,%r13,8), %r12
    mov     LIBP2P_CFG_PENDING_CAPACITY(%rbx), %r13
    mov     %r12, (ST_PEND_OFF - ST_TABLES)(%rbp)
    mov     %r13, (ST_PEND_COUNT - ST_TABLES)(%rbp)
    imul    $PD_SIZE, %r13, %rax
    add     %rax, %r12
    mov     %r12, (ST_PROMISE_OFF - ST_TABLES)(%rbp)
    add     $(LIBP2P_PROMISES * PR_SIZE), %r12
    mov     %r12, (ST_PROTO_OFF - ST_TABLES)(%rbp)
    mov     X26(%rsp), %rax
    mov     %rax, (ST_PROTO_COUNT - ST_TABLES)(%rbp)
    imul    $LIBP2P_PROTO_SIZE, %rax, %rax
    add     %rax, %r12
    mov     %r12, (ST_DW_OFF - ST_TABLES)(%rbp)
    mov     LIBP2P_CFG_DONTWANT_SLOTS(%rbx), %rax
    imul    X24(%rsp), %rax
    imul    $DW_SIZE, %rax, %rax
    add     %rax, %r12
    add     $63, %r12                       /* the heap, at a multiple of 64 */
    and     $-64, %r12
    mov     LIBP2P_CFG_HEAP_SIZE(%rbx), %rax
    mov     %r12, (ST_HEAP_OFF - ST_TABLES)(%rbp)
    mov     %rax, (ST_HEAP_SIZE - ST_TABLES)(%rbp)
    add     %rax, %r12
    mov     %r12, (ST_QMAP_OFF - ST_TABLES)(%rbp)
    cmpq    $0, LIBP2P_CFG_QUIC(%rbx)
    jne     4f
    mov     %r12, (ST_QCMAP_OFF - ST_TABLES)(%rbp)  /* QUIC off: the parts are empty */
    mov     %r12, (ST_QEV_OFF - ST_TABLES)(%rbp)
    mov     %r12, (ST_QACT_OFF - ST_TABLES)(%rbp)
    movq    $0, (ST_QUIC_OFF - ST_TABLES)(%rbp)
    mov     %r12, %rdx
    jmp     5f
4:  mov     LIBP2P_CFG_MAX_STREAMS(%rbx), %rax  /* the asm-quic stream map: u32 each */
    lea     (%r12,%rax,4), %r12
    ALIGN8  %r12
    mov     %r12, (ST_QCMAP_OFF - ST_TABLES)(%rbp)
    mov     LIBP2P_CFG_MAX_CONNECTIONS(%rbx), %rax
    lea     (%r12,%rax,4), %r12
    ALIGN8  %r12
    mov     %r12, (ST_QEV_OFF - ST_TABLES)(%rbp)
    add     $(LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS), %r12
    mov     %r12, (ST_QACT_OFF - ST_TABLES)(%rbp)
    add     $(LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS), %r12
    add     $63, %r12                       /* the asm-quic state, at a multiple of 64 */
    and     $-64, %r12
    mov     %r12, (ST_QUIC_OFF - ST_TABLES)(%rbp)
    mov     %rbx, %rdi
    lea     32(%rsp), %rsi
    call    libp2p_quic_config
    lea     32(%rsp), %rdi
    lea     (32 + QUIC_CFG_SIZE)(%rsp), %rsi
    CALL_GLOBAL quic_state_size
    test    %rax, %rax
    jnz     80f
    mov     (32 + QUIC_CFG_SIZE)(%rsp), %rdx
    add     %r12, %rdx
5:  mov     $LIBP2P_OK, %eax
    jmp     99f
80: mov     $LIBP2P_INVALID_CONFIG, %eax
    xor     %edx, %edx
99: LEAVE   0, (QUIC_CFG_SIZE + 16)
END_FUNCTION libp2p_layout

/* ---------------------------------------------------------------- libp2p_state_size */

/* libp2p_state_size(config, size) -> status: the bytes of the state for the config. */
FUNCTION libp2p_state_size
    ENTER   0, TABLES_ROOM
    mov     %rsi, %rbx
    lea     32(%rsp), %rsi
    call    libp2p_layout
    test    %rax, %rax
    jnz     9f
    mov     %rdx, (%rbx)
9:  LEAVE   0, TABLES_ROOM
END_FUNCTION libp2p_state_size

/* ---------------------------------------------------------------- libp2p_init */

/*
 * libp2p_init(config, state) -> status. Checks the config, the state size
 * and the private key; then builds the state: keys, peer ID, the static
 * Noise key and its signature, empty tables, one free heap block, timers;
 * with QUIC on, the asm-quic maps and lists, and the asm-quic state with a
 * seed from the DRBG.
 * rbx config, rbp state, r12 the state size needed, r13 the public key
 * length, X23 the heap offset. Extra: 32(%rsp) the tables (then the
 * asm-quic Config), 32 + IN_KEY the public key, 32 + IN_BL the entropy
 * ByteList.
 */
.set IN_KEY, TABLES_ROOM
.set IN_BL, IN_KEY + 48
.set IN_FRAME, IN_BL + 64
FUNCTION libp2p_init
    ENTER   0, IN_FRAME
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rsi, %r15
    lea     32(%rsp), %rsi
    call    libp2p_layout
    test    %rax, %rax
    jnz     99f
    mov     %rdx, %r12
    mov     $LIBP2P_BUFFER_TOO_SMALL, %eax
    cmp     %r12, ST_SIZE(%rbp)
    jb      99f
    cmpq    $LIBP2P_KEY_SECP256K1, LIBP2P_CFG_KEY_TYPE(%rbx)    /* the public key, on the stack first */
    jne     1f
    lea     LIBP2P_CFG_PRIVATE_KEY(%rbx), %rdi
    lea     (32 + IN_KEY)(%rsp), %rsi
    CALL_GLOBAL crypto_secp256k1_public_key
    mov     %rax, %rcx
    mov     $LIBP2P_INVALID_KEY, %eax
    test    %rcx, %rcx
    jnz     99f
    mov     $33, %r13d
    jmp     2f
1:  lea     LIBP2P_CFG_PRIVATE_KEY(%rbx), %rdi
    lea     (32 + IN_KEY)(%rsp), %rsi
    CALL_GLOBAL crypto_ed25519_public_key
    mov     $32, %r13d

    /* Commit: zero all but the heap, then fill in. */
2:  mov     (32 + ST_HEAP_OFF - ST_TABLES)(%rsp), %rax
    mov     %rax, X23(%rsp)
    lea     8(%rbp), %rdi
    lea     -8(%rax), %rsi
    call    libp2p_zero
    movq    $LIBP2P_STATE_VERSION, ST_VERSION(%rbp)
    lea     ST_TABLES(%rbp), %rdi
    lea     32(%rsp), %rsi
    mov     $(ST_TABLES_END - ST_TABLES), %edx
    call    libp2p_copy
    lea     ST_CONFIG(%rbp), %rdi
    mov     %rbx, %rsi
    mov     $LIBP2P_CFG_FIXED, %edx
    call    libp2p_copy
    mov     LIBP2P_CFG_NOW(%rbx), %rax
    mov     %rax, ST_NOW(%rbp)
    mov     ST_PROTO_COUNT(%rbp), %rdx          /* the protocols */
    imul    $LIBP2P_PROTO_SIZE, %rdx, %rdx
    mov     ST_PROTO_OFF(%rbp), %rdi
    add     %rbp, %rdi
    mov     LIBP2P_CFG_PROTOCOLS(%rbx), %rsi
    add     %rbx, %rsi
    call    libp2p_copy
    movq    $56, (32 + IN_BL)(%rsp)             /* DRBG key = SHA-256(entropy) */
    movq    $LIBP2P_BL_FIXED, (32 + IN_BL + 8)(%rsp)
    movq    $32, (32 + IN_BL + 16)(%rsp)
    lea     (32 + IN_BL + 24)(%rsp), %rdi
    lea     LIBP2P_CFG_ENTROPY(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     (32 + IN_BL)(%rsp), %rdi
    lea     ST_DRBG_KEY(%rbp), %rsi
    CALL_GLOBAL crypto_sha256
    mov     LIBP2P_CFG_KEY_TYPE(%rbx), %rax
    mov     %rax, ST_KEY_TYPE(%rbp)
    lea     ST_PRIVATE_KEY(%rbp), %rdi
    lea     LIBP2P_CFG_PRIVATE_KEY(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    lea     ST_PUBLIC_KEY(%rbp), %rdi
    lea     (32 + IN_KEY)(%rsp), %rsi
    mov     %r13, %rdx
    call    libp2p_copy
    mov     %r13, ST_PUBLIC_LEN(%rbp)
    lea     ST_PEER_ID(%rbp), %rdi
    mov     ST_KEY_TYPE(%rbp), %rsi
    lea     ST_PUBLIC_KEY(%rbp), %rdx
    mov     %r13, %rcx
    call    libp2p_peer_id
    mov     %rax, ST_PEER_ID_LEN(%rbp)
    lea     ST_NOISE_PRIV(%rbp), %rdi           /* the static Noise key */
    mov     $32, %esi
    call    libp2p_random
    lea     ST_NOISE_PRIV(%rbp), %rdi
    lea     421b(%rip), %rsi
    lea     ST_NOISE_PUB(%rbp), %rdx
    CALL_GLOBAL crypto_x25519
    call    libp2p_sign_static
    mov     ST_PROMISE_OFF(%rbp), %rax          /* promises: no peer */
    add     %rbp, %rax
    mov     $LIBP2P_PROMISES, %ecx
3:  movq    $NONE, PR_PEER(%rax)
    add     $PR_SIZE, %rax
    dec     %rcx
    jnz     3b
    lea     ST_HEAP_FREE(%rbp), %rax            /* the heap: one free block */
    mov     $ST_HEAP_ORDERS, %ecx
4:  movq    $NONE, (%rax)
    add     $8, %rax
    dec     %rcx
    jnz     4b
    bsf     ST_HEAP_SIZE(%rbp), %rcx
    mov     X23(%rsp), %rdx
    add     %rbp, %rdx
    movl    %ecx, HB_ORDER(%rdx)
    movl    $1, HB_FREE(%rdx)
    movq    $NONE, HB_NEXT(%rdx)
    movq    $NONE, HB_PREV(%rdx)
    movq    $0, ST_HEAP_FREE(%rbp,%rcx,8)
    mov     ST_NOW(%rbp), %rax                  /* timers */
    mov     (ST_CONFIG + LIBP2P_CFG_HEARTBEAT_MS)(%rbp), %rcx
    add     %rax, %rcx
    mov     %rcx, ST_HEARTBEAT_AT(%rbp)
    mov     (ST_CONFIG + LIBP2P_CFG_DECAY_INTERVAL_MS)(%rbp), %rcx
    add     %rax, %rcx
    mov     %rcx, ST_DECAY_AT(%rbp)
    cmpq    $0, ST_QUIC_OFF(%rbp)               /* QUIC: maps, lists, the asm-quic state */
    je      6f
    mov     ST_QMAP_OFF(%rbp), %rax
    add     %rbp, %rax
    mov     ST_QEV_OFF(%rbp), %rcx
    add     %rbp, %rcx
5:  cmp     %rcx, %rax
    jae     51f
    movq    $NONE, (%rax)
    add     $8, %rax
    jmp     5b
51: mov     ST_QEV_OFF(%rbp), %rax
    add     %rbp, %rax
    movq    $(LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS), LIBP2P_BL_SIZE(%rax)
    movq    $LIBP2P_BL_FIXED, LIBP2P_BL_OFFSET(%rax)
    movq    $0, LIBP2P_BL_COUNT(%rax)
    mov     ST_QACT_OFF(%rbp), %rax
    add     %rbp, %rax
    movq    $(LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS), LIBP2P_BL_SIZE(%rax)
    movq    $LIBP2P_BL_FIXED, LIBP2P_BL_OFFSET(%rax)
    movq    $0, LIBP2P_BL_COUNT(%rax)
    mov     ST_QUIC_OFF(%rbp), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    mov     %rcx, (%rbp,%rax)                   /* the size of the asm-quic state */
    mov     %rbx, %rdi
    lea     32(%rsp), %rsi
    call    libp2p_quic_config
    lea     (32 + QUIC_CFG_SEED)(%rsp), %rdi
    mov     $32, %esi
    call    libp2p_random
    lea     32(%rsp), %rdi
    mov     ST_QUIC_OFF(%rbp), %rsi
    add     %rbp, %rsi
    CALL_GLOBAL quic_init
6:  mov     $LIBP2P_OK, %eax
99: LEAVE   0, IN_FRAME
END_FUNCTION libp2p_init

/* ---------------------------------------------------------------- Event checks */

/*
 * libp2p_check_event(event, end) -> 0 when the event is well formed and fits
 * before end; 1 otherwise. rbx event, rbp size, r12 kind, r13 a count.
 */
LOCAL_FUNCTION libp2p_check_event
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rax
    sub     %rdi, %rax
    cmp     $16, %rax
    jb      80f
    mov     LIBP2P_EV_SIZE(%rbx), %rbp
    cmp     $16, %rbp
    jb      80f
    test    $7, %rbp
    jnz     80f
    cmp     %rax, %rbp
    ja      80f
    mov     LIBP2P_EV_KIND(%rbx), %r12
    RANGE   %r12, 1, LIBP2P_EVENT_LAST, 80f
    lea     300f(%rip), %rax                /* the minimum size of the kind */
    movzwl  (%rax,%r12,2), %eax
    cmp     %rax, %rbp
    jb      80f
    cmp     $LIBP2P_EVENT_ACCEPTED, %r12
    jne     1f
    lea     LIBP2P_EV_ACCEPTED_ADDR(%rbx), %rdi
    call    libp2p_check_addr
    jmp     99f
1:  cmp     $LIBP2P_EVENT_RECEIVED, %r12
    jne     2f
    mov     LIBP2P_EV_COUNT(%rbx), %rax
    RANGE   %rax, 0, LIBP2P_RECEIVE_MAX, 80f
    lea     -LIBP2P_EV_DATA(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
2:  cmp     $LIBP2P_EVENT_DIAL, %r12
    jne     3f
    mov     LIBP2P_EV_DIAL_ID_LEN(%rbx), %rax
    RANGE   %rax, 0, LIBP2P_MAX_PEER_ID, 80f
    mov     LIBP2P_EV_DIAL_TRANSPORT(%rbx), %rax
    cmp     $LIBP2P_QUIC, %rax
    ja      80f
    jne     21f
    cmpq    $0, ST_QUIC_OFF(%r15)           /* QUIC needs QUIC on */
    je      80f
21: lea     LIBP2P_EV_DIAL_ADDR(%rbx), %rdi
    call    libp2p_check_addr
    jmp     99f
3:  cmp     $LIBP2P_EVENT_OPEN_STREAM, %r12
    jne     4f
    mov     LIBP2P_EV_OPEN_COUNT(%rbx), %r13
    RANGE   %r13, 1, LIBP2P_MAX_PROPOSALS, 80f
    imul    $LIBP2P_PROTO_SIZE, %r13, %rax
    add     $LIBP2P_EV_OPEN_PROTOCOLS, %rax
    cmp     %rax, %rbp
    jb      80f
    lea     LIBP2P_EV_OPEN_PROTOCOLS(%rbx), %r8
31: mov     LIBP2P_PROTO_LEN(%r8), %rcx
    RANGE   %rcx, 1, LIBP2P_MAX_PROTOCOL, 80f
    lea     LIBP2P_PROTO_BYTES(%r8), %rdx
32: movzbl  (%rdx), %eax
    inc     %rdx
    cmp     $10, %eax
    je      80f
    dec     %rcx
    jnz     32b
    add     $LIBP2P_PROTO_SIZE, %r8
    dec     %r13
    jnz     31b
    jmp     70f
4:  cmp     $LIBP2P_EVENT_STREAM_WRITE, %r12
    jne     5f
    mov     LIBP2P_EV_STREAM_COUNT(%rbx), %rax
    lea     -LIBP2P_EV_STREAM_DATA(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
5:  cmp     $LIBP2P_EVENT_SUBSCRIBE, %r12
    je      51f
    cmp     $LIBP2P_EVENT_UNSUBSCRIBE, %r12
    jne     6f
51: mov     LIBP2P_EV_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    lea     -LIBP2P_EV_TOPIC(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
6:  cmp     $LIBP2P_EVENT_PUBLISH, %r12
    jne     7f
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_MSG_ID, 80f
    mov     LIBP2P_EV_PUB_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  %rax
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %rcx
    cmp     (ST_CONFIG + LIBP2P_CFG_MAX_DATA)(%r15), %rcx
    ja      80f
    add     %rcx, %rax
    add     $LIBP2P_EV_PUB_TOPIC, %rax
    cmp     %rbp, %rax
    ja      80f
    jmp     70f
7:  cmp     $LIBP2P_EVENT_MESSAGE_ID, %r12
    jne     8f
    mov     LIBP2P_EV_MSG_ID_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_MSG_ID, 80f
    jmp     70f
8:  cmp     $LIBP2P_EVENT_VALIDATION, %r12
    jne     9f
    mov     LIBP2P_EV_RESULT(%rbx), %rax
    RANGE   %rax, 1, 3, 80f
    jmp     70f
9:  cmp     $LIBP2P_EVENT_TOPIC_PARAMS, %r12
    jne     10f
    mov     LIBP2P_EV_TP_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    lea     -(LIBP2P_EV_TP_TOPIC)(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
10: cmp     $LIBP2P_EVENT_PARTIAL_SUBSCRIBE, %r12
    jne     11f
    mov     LIBP2P_EV_PS_FLAGS(%rbx), %rax
    RANGE   %rax, 0, 3, 80f
    test    %rax, %rax
    jz      101f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)(%r15)
    je      80f
101: mov    LIBP2P_EV_PS_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    lea     -LIBP2P_EV_PS_TOPIC(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
11: cmp     $LIBP2P_EVENT_PARTIAL_PEERS, %r12
    jne     12f
    mov     LIBP2P_EV_PP_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    lea     -LIBP2P_EV_PP_TOPIC(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
12: cmp     $LIBP2P_EVENT_PARTIAL_SEND, %r12
    jne     13f
    mov     LIBP2P_EV_PSEND_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  %rax
    mov     (ST_CONFIG + LIBP2P_CFG_MAX_RPC)(%r15), %rdx
    mov     LIBP2P_EV_PSEND_GROUP_LEN(%rbx), %rcx
    cmp     %rdx, %rcx
    ja      80f
    ALIGN8  %rcx
    add     %rcx, %rax
    mov     LIBP2P_EV_PSEND_META_LEN(%rbx), %rcx
    cmp     %rdx, %rcx
    ja      80f
    ALIGN8  %rcx
    add     %rcx, %rax
    mov     LIBP2P_EV_PSEND_MSG_LEN(%rbx), %rcx
    cmp     %rdx, %rcx
    ja      80f
    add     %rcx, %rax
    add     $LIBP2P_EV_PSEND_BYTES, %rax
    cmp     %rbp, %rax
    ja      80f
    jmp     70f
13: cmp     $LIBP2P_EVENT_PARTIAL_SCORE, %r12
    jne     14f
    mov     LIBP2P_EV_PSCORE_RESULT(%rbx), %rax
    RANGE   %rax, 1, 2, 80f
    mov     LIBP2P_EV_PSCORE_TOPIC_LEN(%rbx), %rax
    RANGE   %rax, 1, LIBP2P_MAX_TOPIC, 80f
    lea     -LIBP2P_EV_PSCORE_TOPIC(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    jmp     70f
14: cmp     $LIBP2P_EVENT_DATAGRAM, %r12
    jne     70f
    cmpq    $0, ST_QUIC_OFF(%r15)           /* QUIC on */
    je      80f
    RANGE   %rbp, LIBP2P_EV_DG_DATA, (LIBP2P_EV_DG_DATA + LIBP2P_DATAGRAM_MAX + 1), 80f
    mov     LIBP2P_EV_DG_COUNT(%rbx), %rax
    RANGE   %rax, 0, LIBP2P_DATAGRAM_MAX, 80f
    lea     -LIBP2P_EV_DG_DATA(%rbp), %rcx
    cmp     %rcx, %rax
    ja      80f
    lea     LIBP2P_EV_DG_ADDR(%rbx), %rdi
    call    libp2p_check_addr
    jmp     99f
70: xor     %eax, %eax
    jmp     99f
80: mov     $1, %eax
99: LEAVE   0
END_FUNCTION libp2p_check_event

    .p2align 1
/* The minimum size of each event kind, from kind 0. */
300:
    .short  0, LIBP2P_EV_ACCEPTED_SIZE, 24, LIBP2P_EV_CONN_SIZE, LIBP2P_EV_DATA, LIBP2P_EV_CONN_SIZE
    .short  LIBP2P_EV_CONN_SIZE, LIBP2P_EV_DIAL_SIZE, LIBP2P_EV_PEER_SIZE, LIBP2P_EV_OPEN_PROTOCOLS
    .short  LIBP2P_EV_STREAM_DATA, LIBP2P_EV_STREAM_SIZE, LIBP2P_EV_STREAM_SIZE, LIBP2P_EV_TOPIC
    .short  LIBP2P_EV_TOPIC, LIBP2P_EV_PUB_TOPIC, LIBP2P_EV_MSG_ID_SIZE, LIBP2P_EV_VALIDATION_SIZE
    .short  LIBP2P_EV_SCORE_SIZE, LIBP2P_EV_TP_TOPIC, LIBP2P_EV_PS_TOPIC, LIBP2P_EV_PP_TOPIC
    .short  LIBP2P_EV_PSEND_BYTES, LIBP2P_EV_PSCORE_TOPIC, LIBP2P_EV_DG_DATA
    .p2align 2

/* libp2p_check_addr(addr) -> 0 when the family is 4 or 6 and the port below 65536, else 1. A leaf. */
LOCAL_FUNCTION libp2p_check_addr
    UNWIND_END_PROLOGUE
    mov     LIBP2P_ADDR_FAMILY(%rdi), %rcx
    mov     LIBP2P_ADDR_PORT(%rdi), %rdx
    mov     $1, %eax
    cmp     $4, %rcx
    je      1f
    cmp     $6, %rcx
    jne     9f
1:  cmp     $0x10000, %rdx
    jae     9f
    xor     %eax, %eax
9:  ret
END_FUNCTION libp2p_check_addr

/*
 * libp2p_event_room(event) -> the action bytes handling the event may need:
 * 64 + 16 for each received byte, 16384 for an event that can end a
 * connection, LIBP2P_ACT_PL_TOPIC + LIBP2P_MAX_TOPIC + 16 for each peer
 * slot for PARTIAL_PEERS, 0 for DATAGRAM (all ones when the event list for
 * asm-quic has no room for it), else 1024. A leaf.
 */
LOCAL_FUNCTION libp2p_event_room
    UNWIND_END_PROLOGUE
    mov     LIBP2P_EV_KIND(%rdi), %rcx
    cmp     $LIBP2P_EVENT_DATAGRAM, %rcx
    jne     7f
    mov     ST_QEV_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     LIBP2P_BL_SIZE(%rdx), %rsi
    sub     $LIBP2P_BL_FIXED, %rsi
    sub     LIBP2P_BL_COUNT(%rdx), %rsi
    xor     %eax, %eax
    mov     $-1, %rcx
    cmp     LIBP2P_EV_SIZE(%rdi), %rsi
    cmovb   %rcx, %rax
    ret
7:  cmp     $LIBP2P_EVENT_RECEIVED, %rcx
    jne     1f
    mov     LIBP2P_EV_COUNT(%rdi), %rax
    shl     $4, %rax
    add     $64, %rax
    ret
1:  cmp     $LIBP2P_EVENT_PARTIAL_PEERS, %rcx
    jne     11f
    mov     ST_PEER_COUNT(%r15), %rax
    shl     $4, %rax
    add     $(LIBP2P_ACT_PL_TOPIC + LIBP2P_MAX_TOPIC), %rax
    ret
11: cmp     $LIBP2P_EVENT_CLOSED, %rcx
    je      2f
    cmp     $LIBP2P_EVENT_DIAL_FAILED, %rcx
    je      2f
    cmp     $LIBP2P_EVENT_DISCONNECT, %rcx
    je      2f
    mov     $1024, %eax
    ret
2:  mov     $16384, %eax
    ret
END_FUNCTION libp2p_event_room

/* ---------------------------------------------------------------- libp2p_step */

/*
 * libp2p_step(state, tick, events, scratch, actions, result) -> status.
 * Checks the scratch size, the action room and every event first; on error
 * nothing changes. Then takes the time (never below the last), reseeds the
 * DRBG, frees the RPC blocks of the last step's PARTIAL actions, and
 * handles events in order while the room for their actions lasts;
 * result gets the count handled. Then the timers, the drain of queued
 * bytes into SEND actions, and WAKEUP last.
 * r15 state, r14 scratch, rbx tick, rbp events, r12 actions, r13 result,
 * X23 event position, X24 events end, X25 events handled, X26 room needed.
 */
FUNCTION libp2p_step
    ENTER   0
    mov     %rdi, %r15
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r14
    mov     %r8, %r12
    mov     %r9, %r13
    mov     $LIBP2P_BUFFER_TOO_SMALL, %eax
    movabs  $SC_TOTAL, %rcx
    cmp     %rcx, SC_SIZE(%r14)
    jb      99f
    movabs  $(LIBP2P_ACTIONS_MIN + LIBP2P_BL_FIXED), %rcx
    cmp     %rcx, LIBP2P_BL_SIZE(%r12)
    jb      99f
    mov     LIBP2P_BL_OFFSET(%rbp), %rax
    add     %rbp, %rax
    mov     %rax, X23(%rsp)
    add     LIBP2P_BL_COUNT(%rbp), %rax
    mov     %rax, X24(%rsp)
1:  mov     X23(%rsp), %rdi
    cmp     X24(%rsp), %rdi
    jae     2f
    mov     X24(%rsp), %rsi
    call    libp2p_check_event
    mov     %rax, %rcx
    mov     $LIBP2P_INVALID_EVENT, %eax
    test    %rcx, %rcx
    jnz     99f
    mov     X23(%rsp), %rax
    add     LIBP2P_EV_SIZE(%rax), %rax
    mov     %rax, X23(%rsp)
    jmp     1b

    /* Commit. */
2:  mov     LIBP2P_TICK_NOW(%rbx), %rax
    mov     ST_NOW(%r15), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, ST_NOW(%r15)
    mov     %rax, SC_NOW(%r14)
    add     $60000, %rax
    mov     %rax, SC_WAKE(%r14)
    mov     %r12, SC_ACTIONS(%r14)
    movq    $ACTIONS_RESERVE, SC_RESERVE(%r14)
    movq    $LIBP2P_BL_FIXED, LIBP2P_BL_OFFSET(%r12)
    movq    $0, LIBP2P_BL_COUNT(%r12)
    lea     LIBP2P_TICK_ENTROPY(%rbx), %rdi
    call    libp2p_reseed
    call    libp2p_free_kept
    cmpq    $0, ST_QUIC_OFF(%r15)           /* QUIC: the tick of asm-quic, then the actions it gave */
    je      21f
    SCR     %rdi, SC_QTICK
    mov     LIBP2P_TICK_US(%rbx), %rax
    mov     %rax, QUIC_TICK_NOW(%rdi)
    mov     LIBP2P_TICK_UNIX(%rbx), %rax
    mov     %rax, QUIC_TICK_UNIX(%rdi)
    add     $QUIC_TICK_ENTROPY, %rdi
    mov     $32, %esi
    call    libp2p_random
    call    libp2p_quic_actions
21:

    /* The events, while their room lasts. */
    mov     LIBP2P_BL_OFFSET(%rbp), %rax
    add     %rbp, %rax
    mov     %rax, X23(%rsp)
    movq    $0, X25(%rsp)
3:  mov     X23(%rsp), %rdi
    cmp     X24(%rsp), %rdi
    jae     5f
    call    libp2p_event_room
    mov     %rax, X26(%rsp)
    call    libp2p_room
    cmp     X26(%rsp), %rax
    jb      4f
    mov     X23(%rsp), %rdi
    call    libp2p_event
    mov     X23(%rsp), %rax
    add     LIBP2P_EV_SIZE(%rax), %rax
    mov     %rax, X23(%rsp)
    incq    X25(%rsp)
    jmp     3b
4:  mov     SC_NOW(%r14), %rdi              /* events left: the next step is due now */
    call    libp2p_wake_at

    /* Timers, the drain, WAKEUP. */
5:  mov     X25(%rsp), %rax
    mov     %rax, LIBP2P_RESULT_ACCEPTED(%r13)
    call    libp2p_timers
    cmpq    $0, ST_QUIC_OFF(%r15)
    je      51f
    call    libp2p_quic_pump
51: call    libp2p_drain
    movq    $0, SC_RESERVE(%r14)
    mov     $LIBP2P_ACTION_WAKEUP, %edi
    mov     $LIBP2P_ACT_WAKEUP_SIZE, %esi
    call    libp2p_action
    mov     SC_WAKE(%r14), %rcx
    mov     %rcx, LIBP2P_ACT_TIME(%rax)
    mov     $LIBP2P_OK, %eax
99: LEAVE   0
END_FUNCTION libp2p_step

/* libp2p_event(event): handles one checked event: a direct call for each kind. */
LOCAL_FUNCTION libp2p_event
    FRAME
    mov     LIBP2P_EV_KIND(%rdi), %rax
    cmp     $1, %rax
    jne     1f
    call    libp2p_on_accepted
    jmp     99f
1:  cmp     $2, %rax
    jne     2f
    call    libp2p_on_connected
    jmp     99f
2:  cmp     $3, %rax
    jne     3f
    call    libp2p_on_dial_failed
    jmp     99f
3:  cmp     $4, %rax
    jne     4f
    call    libp2p_on_received
    jmp     99f
4:  cmp     $5, %rax
    jne     5f
    call    libp2p_on_sent
    jmp     99f
5:  cmp     $6, %rax
    jne     6f
    call    libp2p_on_closed
    jmp     99f
6:  cmp     $7, %rax
    jne     7f
    call    libp2p_on_dial
    jmp     99f
7:  cmp     $8, %rax
    jne     8f
    call    libp2p_on_disconnect
    jmp     99f
8:  cmp     $9, %rax
    jne     9f
    call    libp2p_on_open_stream
    jmp     99f
9:  cmp     $10, %rax
    jne     10f
    call    libp2p_on_stream_write
    jmp     99f
10: cmp     $11, %rax
    jne     11f
    call    libp2p_on_stream_close
    jmp     99f
11: cmp     $12, %rax
    jne     12f
    call    libp2p_on_stream_reset
    jmp     99f
12: cmp     $13, %rax
    jne     13f
    call    libp2p_on_subscribe
    jmp     99f
13: cmp     $14, %rax
    jne     14f
    call    libp2p_on_unsubscribe
    jmp     99f
14: cmp     $15, %rax
    jne     15f
    call    libp2p_on_publish
    jmp     99f
15: cmp     $16, %rax
    jne     16f
    call    libp2p_on_message_id
    jmp     99f
16: cmp     $17, %rax
    jne     17f
    call    libp2p_on_validation
    jmp     99f
17: cmp     $18, %rax
    jne     18f
    call    libp2p_on_app_score
    jmp     99f
18: cmp     $19, %rax
    jne     19f
    call    libp2p_on_topic_params
    jmp     99f
19: cmp     $20, %rax
    jne     20f
    call    libp2p_on_partial_subscribe
    jmp     99f
20: cmp     $21, %rax
    jne     21f
    call    libp2p_on_partial_peers
    jmp     99f
21: cmp     $22, %rax
    jne     22f
    call    libp2p_on_partial_send
    jmp     99f
22: cmp     $23, %rax
    jne     23f
    call    libp2p_on_partial_score
    jmp     99f
23: cmp     $24, %rax
    jne     99f
    call    libp2p_on_datagram
99: UNFRAME
END_FUNCTION libp2p_event

/* libp2p_free_kept(): the RPC blocks on the ST_KEPT_RPC list are freed, and the list is empty. rbx block, rbp next. */
LOCAL_FUNCTION libp2p_free_kept
    ENTER   0
    mov     ST_KEPT_RPC(%r15), %rbx
    movq    $0, ST_KEPT_RPC(%r15)
1:  test    %rbx, %rbx
    jz      9f
    mov     (HB_NEXT - HB_HEADER)(%r15,%rbx), %rbp
    mov     %rbx, %rdi
    call    libp2p_heap_free
    mov     %rbp, %rbx
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_free_kept

/* ---------------------------------------------------------------- Timers */

/*
 * libp2p_timers(): ends TCP connections whose upgrade ran out of time, runs the
 * gossipsub heartbeat and score decay when due, and asks for a wakeup at
 * the next deadline.
 * rbx connection, rbp connections left, r12 now.
 */
LOCAL_FUNCTION libp2p_timers
    ENTER   0
    mov     SC_NOW(%r14), %r12
    TABLE   %rbx, ST_CONN_OFF
    mov     ST_CONN_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      3f
    testq   $CF_QUIC, C_FLAGS(%rbx)         /* asm-quic times QUIC handshakes */
    jnz     2f
    movl    C_PHASE(%rbx), %eax
    cmp     $PH_DIALING, %eax
    jb      2f
    cmp     $PH_OPEN, %eax
    jae     2f
    mov     C_DEADLINE(%rbx), %rdi
    cmp     %rdi, %r12
    jb      11f
    mov     $LIBP2P_REASON_HANDSHAKE, %esi  /* no TCP connection yet: CONNECT */
    mov     $LIBP2P_REASON_CONNECT, %ecx
    cmp     $PH_DIALING, %eax
    cmove   %rcx, %rsi
    mov     %rbx, %rdi
    call    libp2p_conn_close
    jmp     2f
11: call    libp2p_wake_at
2:  add     $C_SIZE, %rbx
    dec     %rbp
    jmp     1b
3:  call    libp2p_gossip_timers
    LEAVE   0
END_FUNCTION libp2p_timers

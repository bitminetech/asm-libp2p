/*
 * The node of the ARM64 core: the state layout, libp2p_state_size,
 * libp2p_init, libp2p_step, event checks and timers. Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Layout */

/* Branch to fail unless lo <= reg <= hi. Uses x17; reg is not x17. */
.macro RANGE reg, lo, hi, fail
    MOV64   x17, \lo
    cmp     \reg, x17
    b.lo    \fail
    MOV64   x17, \hi
    cmp     \reg, x17
    b.hi    \fail
.endm

/* x0 = align up of x0 to a multiple of 8. */
.macro ALIGN8 reg
    add     \reg, \reg, #7
    and     \reg, \reg, #~7
.endm

/*
 * libp2p_layout(config, tables) -> x0 status, x1 the state size. Checks the
 * config and writes the table offsets and counts at tables (the ST_TABLES
 * fields), in this order: connections, streams, peers, topics, peer x
 * topic, seen, seen index, message cache, its index, pending, promises,
 * protocols, IDONTWANT rings, heap; with QUIC on, then the asm-quic stream
 * and connection maps, the asm-quic event and action lists, and the
 * asm-quic state, whose config quic_state_size checks.
 * x19 config, x20 tables, x21 offset, x22 to x26 counts. The asm-quic
 * Config at sp, its state size at sp + QUIC_CFG_SIZE.
 */
LOCAL_FUNCTION libp2p_layout
    ENTER   0, (QUIC_CFG_SIZE + 16)
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x19, #LIBP2P_CFG_SIZE]
    cmp     x9, #LIBP2P_CFG_FIXED
    b.lo    80f
    ldr     x10, [x19, #LIBP2P_CFG_KEY_TYPE]
    RANGE   x10, 1, 2, 80f
    ldr     x10, [x19, #LIBP2P_CFG_MUXERS]
    RANGE   x10, 1, 3, 80f
    ldr     x22, [x19, #LIBP2P_CFG_MAX_CONNECTIONS]
    RANGE   x22, 1, 65536, 80f
    ldr     x23, [x19, #LIBP2P_CFG_MAX_STREAMS]
    RANGE   x23, 1, 1048576, 80f
    ldr     x24, [x19, #LIBP2P_CFG_MAX_PEERS]
    cmp     x24, x22
    b.lo    80f
    RANGE   x24, 1, 65535, 80f
    ldr     x25, [x19, #LIBP2P_CFG_MAX_TOPICS]
    RANGE   x25, 1, 4096, 80f
    ldr     x10, [x19, #LIBP2P_CFG_HEAP_SIZE]
    RANGE   x10, 65536, 0x10000000000, 80f
    sub     x11, x10, #1
    tst     x10, x11
    b.ne    80f
    ldr     x10, [x19, #LIBP2P_CFG_SEEN_CAPACITY]
    RANGE   x10, 1, 16777216, 80f
    ldr     x10, [x19, #LIBP2P_CFG_MCACHE_CAPACITY]
    RANGE   x10, 1, 1048576, 80f
    ldr     x10, [x19, #LIBP2P_CFG_PENDING_CAPACITY]
    RANGE   x10, 1, 1048576, 80f
    ldr     x10, [x19, #LIBP2P_CFG_SEND_WINDOW]
    RANGE   x10, 131072, 0x40000000, 80f
    ldr     x10, [x19, #LIBP2P_CFG_MAX_RPC]
    RANGE   x10, 1024, 0x40000000, 80f
    ldr     x11, [x19, #LIBP2P_CFG_MAX_DATA]
    cmp     x11, x10
    b.hi    80f
    ldr     x10, [x19, #LIBP2P_CFG_STREAM_QUEUE]
    RANGE   x10, 65536, 0x40000000, 80f
    ldr     x10, [x19, #LIBP2P_CFG_HANDSHAKE_MS]
    cbz     x10, 80f
    ldr     x10, [x19, #LIBP2P_CFG_VALIDATION_MS]
    cbz     x10, 80f
    ldr     x10, [x19, #LIBP2P_CFG_D]           /* gossipsub degrees */
    RANGE   x10, 1, 64, 80f
    ldr     x11, [x19, #LIBP2P_CFG_D_LOW]
    cmp     x11, x10
    b.hi    80f
    ldr     x12, [x19, #LIBP2P_CFG_D_HIGH]
    cmp     x12, x10
    b.lo    80f
    RANGE   x12, 1, 64, 80f
    ldr     x13, [x19, #LIBP2P_CFG_D_LAZY]
    RANGE   x13, 0, 64, 80f
    ldr     x13, [x19, #LIBP2P_CFG_D_SCORE]
    cmp     x13, x12
    b.hi    80f
    ldr     x13, [x19, #LIBP2P_CFG_D_OUT]
    cmp     x13, x11
    b.hi    80f
    ldr     x10, [x19, #LIBP2P_CFG_HEARTBEAT_MS]
    cbz     x10, 80f
    ldr     x10, [x19, #LIBP2P_CFG_MCACHE_LEN]
    RANGE   x10, 1, 64, 80f
    ldr     x11, [x19, #LIBP2P_CFG_MCACHE_GOSSIP]
    cmp     x11, x10
    b.hi    80f
    ldr     x10, [x19, #LIBP2P_CFG_SEEN_TTL_MS]
    cbz     x10, 80f
    ldr     x10, [x19, #LIBP2P_CFG_MAX_IHAVE_LENGTH]
    RANGE   x10, 0, 8192, 80f
    ldr     x10, [x19, #LIBP2P_CFG_AGENT_LEN]
    RANGE   x10, 0, 64, 80f
    ldr     x10, [x19, #LIBP2P_CFG_PV_LEN]
    RANGE   x10, 0, 32, 80f
    ldr     x10, [x19, #LIBP2P_CFG_SCORING]
    RANGE   x10, 0, 1, 80f
    cbz     x10, 1f
    ldr     x10, [x19, #LIBP2P_CFG_DECAY_INTERVAL_MS]
    cbz     x10, 80f
1:  ldr     x10, [x19, #LIBP2P_CFG_GOSSIPSUB_V12]   /* gossipsub v1.2 */
    RANGE   x10, 0, 1, 80f
    ldr     x10, [x19, #LIBP2P_CFG_DONTWANT_SLOTS]
    RANGE   x10, 0, 4096, 80f
    cbz     x10, 11f
    ldr     x10, [x19, #LIBP2P_CFG_DONTWANT_TTL]
    cbz     x10, 80f
11: ldr     x10, [x19, #LIBP2P_CFG_GOSSIPSUB_V13]   /* gossipsub v1.3: needs v1.2 */
    RANGE   x10, 0, 1, 80f
    cbz     x10, 12f
    ldr     x11, [x19, #LIBP2P_CFG_GOSSIPSUB_V12]
    cbz     x11, 80f
12: ldr     x11, [x19, #LIBP2P_CFG_PARTIAL_MESSAGES] /* partial messages: need v1.3 */
    RANGE   x11, 0, 1, 80f
    cmp     x11, x10
    b.hi    80f
    ldr     x10, [x19, #LIBP2P_CFG_QUIC]           /* QUIC: off, on, or on and accepting */
    cmp     x10, #(LIBP2P_QUIC_ON | LIBP2P_QUIC_ACCEPT)
    b.hi    80f
    cmp     x10, #LIBP2P_QUIC_ACCEPT
    b.eq    80f
    cbz     x10, 13f
    ldr     x10, [x19, #LIBP2P_CFG_QUIC_WINDOW]
    RANGE   x10, 65536, 0x40000000, 80f
13:

    /* The protocols part. */
    ldr     x26, [x19, #LIBP2P_CFG_PROTOCOLS_COUNT]
    RANGE   x26, 0, 64, 80f
    cbz     x26, 3f
    ldr     x10, [x19, #LIBP2P_CFG_PROTOCOLS]
    tst     x10, #7
    b.ne    80f
    cmp     x10, #LIBP2P_CFG_FIXED
    b.lo    80f
    mov     x11, #LIBP2P_PROTO_SIZE
    madd    x11, x26, x11, x10
    ldr     x12, [x19, #LIBP2P_CFG_SIZE]
    cmp     x11, x12
    b.hi    80f
    add     x10, x19, x10
    mov     x11, x26
2:  ldr     x12, [x10, #LIBP2P_PROTO_LEN]
    RANGE   x12, 1, LIBP2P_MAX_PROTOCOL, 80f
    add     x13, x10, #LIBP2P_PROTO_BYTES
21: ldrb    w14, [x13], #1
    cmp     w14, #10
    b.eq    80f
    subs    x12, x12, #1
    b.ne    21b
    add     x10, x10, #LIBP2P_PROTO_SIZE
    subs    x11, x11, #1
    b.ne    2b

    /* The tables. */
3:  mov     x21, #ST_FIXED
    ALIGN8  x21
    str     x21, [x20, #(ST_CONN_OFF - ST_TABLES)]
    str     x22, [x20, #(ST_CONN_COUNT - ST_TABLES)]
    mov     x9, #C_SIZE
    madd    x21, x22, x9, x21
    str     x21, [x20, #(ST_STREAM_OFF - ST_TABLES)]
    str     x23, [x20, #(ST_STREAM_COUNT - ST_TABLES)]
    mov     x9, #S_SIZE
    madd    x21, x23, x9, x21
    str     x21, [x20, #(ST_PEER_OFF - ST_TABLES)]
    str     x24, [x20, #(ST_PEER_COUNT - ST_TABLES)]
    mov     x9, #P_SIZE
    madd    x21, x24, x9, x21
    str     x21, [x20, #(ST_TOPIC_OFF - ST_TABLES)]
    str     x25, [x20, #(ST_TOPIC_COUNT - ST_TABLES)]
    mov     x9, #T_SIZE
    madd    x21, x25, x9, x21
    str     x21, [x20, #(ST_PT_OFF - ST_TABLES)]
    mul     x9, x24, x25
    mov     x10, #PT_SIZE
    madd    x21, x9, x10, x21
    ldr     x22, [x19, #LIBP2P_CFG_SEEN_CAPACITY]
    str     x21, [x20, #(ST_SEEN_OFF - ST_TABLES)]
    str     x22, [x20, #(ST_SEEN_COUNT - ST_TABLES)]
    mov     x9, #SN_SIZE
    madd    x21, x22, x9, x21
    str     x21, [x20, #(ST_SEEN_INDEX_OFF - ST_TABLES)]
    add     x21, x21, x22, lsl #3           /* 2 x capacity u32 */
    ldr     x22, [x19, #LIBP2P_CFG_MCACHE_CAPACITY]
    str     x21, [x20, #(ST_MC_OFF - ST_TABLES)]
    str     x22, [x20, #(ST_MC_COUNT - ST_TABLES)]
    add     x9, x24, #31                    /* 2 bits for each peer, in u64 words */
    lsr     x9, x9, #5
    lsl     x9, x9, #3
    add     x9, x9, #MC_TX
    str     x9, [x20, #(ST_MC_STRIDE - ST_TABLES)]
    madd    x21, x22, x9, x21
    str     x21, [x20, #(ST_MC_INDEX_OFF - ST_TABLES)]
    add     x21, x21, x22, lsl #3
    ldr     x22, [x19, #LIBP2P_CFG_PENDING_CAPACITY]
    str     x21, [x20, #(ST_PEND_OFF - ST_TABLES)]
    str     x22, [x20, #(ST_PEND_COUNT - ST_TABLES)]
    mov     x9, #PD_SIZE
    madd    x21, x22, x9, x21
    str     x21, [x20, #(ST_PROMISE_OFF - ST_TABLES)]
    MOV64   x9, (LIBP2P_PROMISES * PR_SIZE)
    add     x21, x21, x9
    str     x21, [x20, #(ST_PROTO_OFF - ST_TABLES)]
    str     x26, [x20, #(ST_PROTO_COUNT - ST_TABLES)]
    mov     x9, #LIBP2P_PROTO_SIZE
    madd    x21, x26, x9, x21
    str     x21, [x20, #(ST_DW_OFF - ST_TABLES)]
    ldr     x9, [x19, #LIBP2P_CFG_DONTWANT_SLOTS]
    mul     x9, x9, x24
    mov     x10, #DW_SIZE
    madd    x21, x9, x10, x21
    add     x21, x21, #63                   /* the heap, at a multiple of 64 */
    and     x21, x21, #~63
    ldr     x9, [x19, #LIBP2P_CFG_HEAP_SIZE]
    str     x21, [x20, #(ST_HEAP_OFF - ST_TABLES)]
    str     x9, [x20, #(ST_HEAP_SIZE - ST_TABLES)]
    add     x21, x21, x9
    str     x21, [x20, #(ST_QMAP_OFF - ST_TABLES)]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC]
    cbnz    x9, 4f
    str     x21, [x20, #(ST_QCMAP_OFF - ST_TABLES)]     /* QUIC off: the parts are empty */
    str     x21, [x20, #(ST_QEV_OFF - ST_TABLES)]
    str     x21, [x20, #(ST_QACT_OFF - ST_TABLES)]
    str     xzr, [x20, #(ST_QUIC_OFF - ST_TABLES)]
    mov     x1, x21
    b       5f
4:  ldr     x9, [x19, #LIBP2P_CFG_MAX_STREAMS]  /* the asm-quic stream map: u32 each */
    add     x21, x21, x9, lsl #2
    ALIGN8  x21
    str     x21, [x20, #(ST_QCMAP_OFF - ST_TABLES)]
    ldr     x9, [x19, #LIBP2P_CFG_MAX_CONNECTIONS]
    add     x21, x21, x9, lsl #2
    ALIGN8  x21
    str     x21, [x20, #(ST_QEV_OFF - ST_TABLES)]
    MOV64   x9, (LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS)
    add     x21, x21, x9
    str     x21, [x20, #(ST_QACT_OFF - ST_TABLES)]
    MOV64   x9, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    add     x21, x21, x9
    add     x21, x21, #63                   /* the asm-quic state, at a multiple of 64 */
    and     x21, x21, #~63
    str     x21, [x20, #(ST_QUIC_OFF - ST_TABLES)]
    mov     x0, x19
    mov     x1, sp
    bl      libp2p_quic_config
    mov     x0, sp
    add     x1, sp, #QUIC_CFG_SIZE
    CALL_GLOBAL quic_state_size
    cbnz    x0, 80f
    ldr     x9, [sp, #QUIC_CFG_SIZE]
    add     x1, x21, x9
5:  mov     x0, #LIBP2P_OK
    b       99f
80: mov     x0, #LIBP2P_INVALID_CONFIG
    mov     x1, #0
99: LEAVE   0, (QUIC_CFG_SIZE + 16)
END_FUNCTION libp2p_layout

/* ---------------------------------------------------------------- libp2p_state_size */

/* libp2p_state_size(config, size) -> status: the bytes of the state for the config. */
FUNCTION libp2p_state_size
    ENTER   0, TABLES_ROOM
    mov     x19, x1
    mov     x1, sp
    bl      libp2p_layout
    cbnz    x0, 9f
    str     x1, [x19]
9:  LEAVE   0, TABLES_ROOM
END_FUNCTION libp2p_state_size

/* ---------------------------------------------------------------- libp2p_init */

/*
 * libp2p_init(config, state) -> status. Checks the config, the state size
 * and the private key; then builds the state: keys, peer ID, the static
 * Noise key and its signature, empty tables, one free heap block, timers;
 * with QUIC on, the asm-quic maps and lists, and the asm-quic state with a
 * seed from the DRBG.
 * x19 config, x20 state, x21 the state size needed. The table fields at
 * sp (then the asm-quic Config), the public key at sp + IN_KEY, a ByteList
 * at sp + IN_BL.
 */
.set IN_KEY, TABLES_ROOM
.set IN_BL, IN_KEY + 48
.set IN_FRAME, IN_BL + 64
FUNCTION libp2p_init
    ENTER   0, IN_FRAME
    mov     x19, x0
    mov     x20, x1
    mov     x27, x1
    mov     x1, sp
    bl      libp2p_layout
    cbnz    x0, 99f
    mov     x21, x1
    mov     x0, #LIBP2P_BUFFER_TOO_SMALL
    ldr     x9, [x20, #ST_SIZE]
    cmp     x9, x21
    b.lo    99f
    ldr     x9, [x19, #LIBP2P_CFG_KEY_TYPE]     /* the public key, on the stack first */
    cmp     x9, #LIBP2P_KEY_SECP256K1
    b.ne    1f
    add     x0, x19, #LIBP2P_CFG_PRIVATE_KEY
    add     x1, sp, #IN_KEY
    CALL_GLOBAL crypto_secp256k1_public_key
    mov     x9, x0
    mov     x0, #LIBP2P_INVALID_KEY
    cbnz    x9, 99f
    mov     x22, #33
    b       2f
1:  add     x0, x19, #LIBP2P_CFG_PRIVATE_KEY
    add     x1, sp, #IN_KEY
    CALL_GLOBAL crypto_ed25519_public_key
    mov     x22, #32

    /* Commit: zero all but the heap, then fill in. */
2:  ldr     x23, [sp, #(ST_HEAP_OFF - ST_TABLES)]
    add     x0, x20, #8
    sub     x1, x23, #8
    bl      libp2p_zero
    mov     x9, #LIBP2P_STATE_VERSION
    str     x9, [x20, #ST_VERSION]
    add     x0, x20, #ST_TABLES
    mov     x1, sp
    mov     x2, #(ST_TABLES_END - ST_TABLES)
    bl      libp2p_copy
    add     x0, x20, #ST_CONFIG
    mov     x1, x19
    mov     x2, #LIBP2P_CFG_FIXED
    bl      libp2p_copy
    ldr     x9, [x19, #LIBP2P_CFG_NOW]
    str     x9, [x20, #ST_NOW]
    ldr     x2, [x20, #ST_PROTO_COUNT]          /* the protocols */
    mov     x9, #LIBP2P_PROTO_SIZE
    mul     x2, x2, x9
    ldr     x0, [x20, #ST_PROTO_OFF]
    add     x0, x20, x0
    ldr     x1, [x19, #LIBP2P_CFG_PROTOCOLS]
    add     x1, x19, x1
    bl      libp2p_copy
    mov     x9, #56                             /* DRBG key = SHA-256(entropy) */
    str     x9, [sp, #IN_BL]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [sp, #(IN_BL + 8)]
    mov     x9, #32
    str     x9, [sp, #(IN_BL + 16)]
    add     x0, sp, #(IN_BL + 24)
    add     x1, x19, #LIBP2P_CFG_ENTROPY
    mov     x2, #32
    bl      libp2p_copy
    add     x0, sp, #IN_BL
    add     x1, x20, #ST_DRBG_KEY
    CALL_GLOBAL crypto_sha256
    ldr     x9, [x19, #LIBP2P_CFG_KEY_TYPE]
    str     x9, [x20, #ST_KEY_TYPE]
    add     x0, x20, #ST_PRIVATE_KEY
    add     x1, x19, #LIBP2P_CFG_PRIVATE_KEY
    mov     x2, #32
    bl      libp2p_copy
    add     x0, x20, #ST_PUBLIC_KEY
    add     x1, sp, #IN_KEY
    mov     x2, x22
    bl      libp2p_copy
    str     x22, [x20, #ST_PUBLIC_LEN]
    add     x0, x20, #ST_PEER_ID
    ldr     x1, [x20, #ST_KEY_TYPE]
    add     x2, x20, #ST_PUBLIC_KEY
    mov     x3, x22
    bl      libp2p_peer_id
    str     x0, [x20, #ST_PEER_ID_LEN]
    add     x0, x20, #ST_NOISE_PRIV             /* the static Noise key */
    mov     x1, #32
    bl      libp2p_random
    add     x0, x20, #ST_NOISE_PRIV
    adr     x1, 421b
    add     x2, x20, #ST_NOISE_PUB
    CALL_GLOBAL crypto_x25519
    bl      libp2p_sign_static
    ldr     x9, [x20, #ST_PROMISE_OFF]          /* promises: no peer */
    add     x9, x20, x9
    mov     x10, #LIBP2P_PROMISES
    mov     x11, #NONE
3:  str     x11, [x9, #PR_PEER]
    add     x9, x9, #PR_SIZE
    subs    x10, x10, #1
    b.ne    3b
    add     x9, x20, #ST_HEAP_FREE              /* the heap: one free block */
    mov     x10, #ST_HEAP_ORDERS
4:  str     x11, [x9], #8
    subs    x10, x10, #1
    b.ne    4b
    ldr     x9, [x20, #ST_HEAP_SIZE]
    rbit    x10, x9
    clz     x10, x10
    add     x12, x20, x23
    str     w10, [x12, #HB_ORDER]
    mov     w13, #1
    str     w13, [x12, #HB_FREE]
    str     x11, [x12, #HB_NEXT]
    str     x11, [x12, #HB_PREV]
    add     x9, x20, #ST_HEAP_FREE
    str     xzr, [x9, x10, lsl #3]
    ldr     x9, [x20, #ST_NOW]                  /* timers */
    ldr     x10, [x20, #(ST_CONFIG + LIBP2P_CFG_HEARTBEAT_MS)]
    add     x10, x9, x10
    str     x10, [x20, #ST_HEARTBEAT_AT]
    ldr     x10, [x20, #(ST_CONFIG + LIBP2P_CFG_DECAY_INTERVAL_MS)]
    add     x10, x9, x10
    str     x10, [x20, #ST_DECAY_AT]
    ldr     x9, [x20, #ST_QUIC_OFF]             /* QUIC: maps, lists, the asm-quic state */
    cbz     x9, 6f
    ldr     x0, [x20, #ST_QMAP_OFF]
    add     x0, x20, x0
    ldr     x1, [x20, #ST_QEV_OFF]
    add     x1, x20, x1
    mov     x9, #NONE
5:  cmp     x0, x1
    b.hs    51f
    str     x9, [x0], #8
    b       5b
51: ldr     x0, [x20, #ST_QEV_OFF]
    add     x0, x20, x0
    MOV64   x9, (LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS)
    str     x9, [x0, #LIBP2P_BL_SIZE]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x0, #LIBP2P_BL_OFFSET]
    str     xzr, [x0, #LIBP2P_BL_COUNT]
    ldr     x0, [x20, #ST_QACT_OFF]
    add     x0, x20, x0
    MOV64   x9, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    str     x9, [x0, #LIBP2P_BL_SIZE]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x0, #LIBP2P_BL_OFFSET]
    str     xzr, [x0, #LIBP2P_BL_COUNT]
    ldr     x9, [x20, #ST_QUIC_OFF]
    sub     x10, x21, x9
    str     x10, [x20, x9]                      /* the size of the asm-quic state */
    mov     x0, x19
    mov     x1, sp
    bl      libp2p_quic_config
    add     x0, sp, #QUIC_CFG_SEED
    mov     x1, #32
    bl      libp2p_random
    mov     x0, sp
    ldr     x1, [x20, #ST_QUIC_OFF]
    add     x1, x20, x1
    CALL_GLOBAL quic_init
6:  mov     x0, #LIBP2P_OK
99: LEAVE   0, IN_FRAME
END_FUNCTION libp2p_init

/* ---------------------------------------------------------------- Event checks */

/*
 * libp2p_check_event(event, end) -> 0 when the event is well formed and fits
 * before end; 1 otherwise. x19 event, x20 size, x21 kind.
 */
LOCAL_FUNCTION libp2p_check_event
    ENTER   0
    mov     x19, x0
    sub     x9, x1, x0
    cmp     x9, #16
    b.lo    80f
    ldr     x20, [x19, #LIBP2P_EV_SIZE]
    cmp     x20, #16
    b.lo    80f
    tst     x20, #7
    b.ne    80f
    cmp     x20, x9
    b.hi    80f
    ldr     x21, [x19, #LIBP2P_EV_KIND]
    RANGE   x21, 1, LIBP2P_EVENT_LAST, 80f
    adr     x9, 300f                        /* the minimum size of the kind */
    ldrh    w9, [x9, x21, lsl #1]
    cmp     x20, x9
    b.lo    80f
    cmp     x21, #LIBP2P_EVENT_ACCEPTED
    b.ne    1f
    add     x0, x19, #LIBP2P_EV_ACCEPTED_ADDR
    bl      libp2p_check_addr
    b       99f
1:  cmp     x21, #LIBP2P_EVENT_RECEIVED
    b.ne    2f
    ldr     x9, [x19, #LIBP2P_EV_COUNT]
    RANGE   x9, 0, LIBP2P_RECEIVE_MAX, 80f
    sub     x10, x20, #LIBP2P_EV_DATA
    cmp     x9, x10
    b.hi    80f
    b       70f
2:  cmp     x21, #LIBP2P_EVENT_DIAL
    b.ne    3f
    ldr     x9, [x19, #LIBP2P_EV_DIAL_ID_LEN]
    RANGE   x9, 0, LIBP2P_MAX_PEER_ID, 80f
    ldr     x9, [x19, #LIBP2P_EV_DIAL_TRANSPORT]
    cmp     x9, #LIBP2P_QUIC
    b.hi    80f
    b.ne    21f
    ldr     x9, [x27, #ST_QUIC_OFF]         /* QUIC needs QUIC on */
    cbz     x9, 80f
21: add     x0, x19, #LIBP2P_EV_DIAL_ADDR
    bl      libp2p_check_addr
    b       99f
3:  cmp     x21, #LIBP2P_EVENT_OPEN_STREAM
    b.ne    4f
    ldr     x22, [x19, #LIBP2P_EV_OPEN_COUNT]
    RANGE   x22, 1, LIBP2P_MAX_PROPOSALS, 80f
    mov     x9, #LIBP2P_PROTO_SIZE
    mov     x10, #LIBP2P_EV_OPEN_PROTOCOLS
    madd    x9, x22, x9, x10
    cmp     x20, x9
    b.lo    80f
    add     x23, x19, #LIBP2P_EV_OPEN_PROTOCOLS
31: ldr     x12, [x23, #LIBP2P_PROTO_LEN]
    RANGE   x12, 1, LIBP2P_MAX_PROTOCOL, 80f
    add     x13, x23, #LIBP2P_PROTO_BYTES
32: ldrb    w14, [x13], #1
    cmp     w14, #10
    b.eq    80f
    subs    x12, x12, #1
    b.ne    32b
    add     x23, x23, #LIBP2P_PROTO_SIZE
    subs    x22, x22, #1
    b.ne    31b
    b       70f
4:  cmp     x21, #LIBP2P_EVENT_STREAM_WRITE
    b.ne    5f
    ldr     x9, [x19, #LIBP2P_EV_STREAM_COUNT]
    sub     x10, x20, #LIBP2P_EV_STREAM_DATA
    cmp     x9, x10
    b.hi    80f
    b       70f
5:  cmp     x21, #LIBP2P_EVENT_SUBSCRIBE
    b.eq    51f
    cmp     x21, #LIBP2P_EVENT_UNSUBSCRIBE
    b.ne    6f
51: ldr     x9, [x19, #LIBP2P_EV_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    sub     x10, x20, #LIBP2P_EV_TOPIC
    cmp     x9, x10
    b.hi    80f
    b       70f
6:  cmp     x21, #LIBP2P_EVENT_PUBLISH
    b.ne    7f
    ldr     x9, [x19, #LIBP2P_EV_PUB_ID_LEN]
    RANGE   x9, 1, LIBP2P_MAX_MSG_ID, 80f
    ldr     x9, [x19, #LIBP2P_EV_PUB_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  x9
    ldr     x10, [x19, #LIBP2P_EV_PUB_DATA_LEN]
    ldr     x11, [x27, #(ST_CONFIG + LIBP2P_CFG_MAX_DATA)]
    cmp     x10, x11
    b.hi    80f
    add     x9, x9, x10
    add     x9, x9, #LIBP2P_EV_PUB_TOPIC
    cmp     x9, x20
    b.hi    80f
    b       70f
7:  cmp     x21, #LIBP2P_EVENT_MESSAGE_ID
    b.ne    8f
    ldr     x9, [x19, #LIBP2P_EV_MSG_ID_LEN]
    RANGE   x9, 1, LIBP2P_MAX_MSG_ID, 80f
    b       70f
8:  cmp     x21, #LIBP2P_EVENT_VALIDATION
    b.ne    9f
    ldr     x9, [x19, #LIBP2P_EV_RESULT]
    RANGE   x9, 1, 3, 80f
    b       70f
9:  cmp     x21, #LIBP2P_EVENT_TOPIC_PARAMS
    b.ne    10f
    ldr     x9, [x19, #LIBP2P_EV_TP_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    sub     x10, x20, #LIBP2P_EV_TP_TOPIC
    cmp     x9, x10
    b.hi    80f
    b       70f
10: cmp     x21, #LIBP2P_EVENT_PARTIAL_SUBSCRIBE
    b.ne    11f
    ldr     x9, [x19, #LIBP2P_EV_PS_FLAGS]
    RANGE   x9, 0, 3, 80f
    cbz     x9, 101f
    ldr     x10, [x27, #(ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)]
    cbz     x10, 80f
101: ldr    x9, [x19, #LIBP2P_EV_PS_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    sub     x10, x20, #LIBP2P_EV_PS_TOPIC
    cmp     x9, x10
    b.hi    80f
    b       70f
11: cmp     x21, #LIBP2P_EVENT_PARTIAL_PEERS
    b.ne    12f
    ldr     x9, [x19, #LIBP2P_EV_PP_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    sub     x10, x20, #LIBP2P_EV_PP_TOPIC
    cmp     x9, x10
    b.hi    80f
    b       70f
12: cmp     x21, #LIBP2P_EVENT_PARTIAL_SEND
    b.ne    13f
    ldr     x9, [x19, #LIBP2P_EV_PSEND_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  x9
    ldr     x11, [x27, #(ST_CONFIG + LIBP2P_CFG_MAX_RPC)]
    ldr     x10, [x19, #LIBP2P_EV_PSEND_GROUP_LEN]
    cmp     x10, x11
    b.hi    80f
    ALIGN8  x10
    add     x9, x9, x10
    ldr     x10, [x19, #LIBP2P_EV_PSEND_META_LEN]
    cmp     x10, x11
    b.hi    80f
    ALIGN8  x10
    add     x9, x9, x10
    ldr     x10, [x19, #LIBP2P_EV_PSEND_MSG_LEN]
    cmp     x10, x11
    b.hi    80f
    add     x9, x9, x10
    add     x9, x9, #LIBP2P_EV_PSEND_BYTES
    cmp     x9, x20
    b.hi    80f
    b       70f
13: cmp     x21, #LIBP2P_EVENT_PARTIAL_SCORE
    b.ne    14f
    ldr     x9, [x19, #LIBP2P_EV_PSCORE_RESULT]
    RANGE   x9, 1, 2, 80f
    ldr     x9, [x19, #LIBP2P_EV_PSCORE_TOPIC_LEN]
    RANGE   x9, 1, LIBP2P_MAX_TOPIC, 80f
    sub     x10, x20, #LIBP2P_EV_PSCORE_TOPIC
    cmp     x9, x10
    b.hi    80f
    b       70f
14: cmp     x21, #LIBP2P_EVENT_DATAGRAM
    b.ne    70f
    ldr     x9, [x27, #ST_QUIC_OFF]         /* QUIC on */
    cbz     x9, 80f
    RANGE   x20, LIBP2P_EV_DG_DATA, (LIBP2P_EV_DG_DATA + LIBP2P_DATAGRAM_MAX + 1), 80f
    ldr     x9, [x19, #LIBP2P_EV_DG_COUNT]
    RANGE   x9, 0, LIBP2P_DATAGRAM_MAX, 80f
    sub     x10, x20, #LIBP2P_EV_DG_DATA
    cmp     x9, x10
    b.hi    80f
    add     x0, x19, #LIBP2P_EV_DG_ADDR
    bl      libp2p_check_addr
    b       99f
70: mov     x0, #0
    b       99f
80: mov     x0, #1
99: LEAVE   0
END_FUNCTION libp2p_check_event

    .p2align 1
/* The minimum size of each event kind, from kind 0. */
300:
    .hword  0, LIBP2P_EV_ACCEPTED_SIZE, 24, LIBP2P_EV_CONN_SIZE, LIBP2P_EV_DATA, LIBP2P_EV_CONN_SIZE
    .hword  LIBP2P_EV_CONN_SIZE, LIBP2P_EV_DIAL_SIZE, LIBP2P_EV_PEER_SIZE, LIBP2P_EV_OPEN_PROTOCOLS
    .hword  LIBP2P_EV_STREAM_DATA, LIBP2P_EV_STREAM_SIZE, LIBP2P_EV_STREAM_SIZE, LIBP2P_EV_TOPIC
    .hword  LIBP2P_EV_TOPIC, LIBP2P_EV_PUB_TOPIC, LIBP2P_EV_MSG_ID_SIZE, LIBP2P_EV_VALIDATION_SIZE
    .hword  LIBP2P_EV_SCORE_SIZE, LIBP2P_EV_TP_TOPIC, LIBP2P_EV_PS_TOPIC, LIBP2P_EV_PP_TOPIC
    .hword  LIBP2P_EV_PSEND_BYTES, LIBP2P_EV_PSCORE_TOPIC, LIBP2P_EV_DG_DATA
    .p2align 2

/* libp2p_check_addr(addr) -> 0 when the family is 4 or 6 and the port below 65536, else 1. A leaf. */
LOCAL_FUNCTION libp2p_check_addr
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #LIBP2P_ADDR_FAMILY]
    ldr     x2, [x0, #LIBP2P_ADDR_PORT]
    mov     x0, #1
    cmp     x1, #4
    b.eq    1f
    cmp     x1, #6
    b.ne    9f
1:  cmp     x2, #0x10000
    b.hs    9f
    mov     x0, #0
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
    ldr     x1, [x0, #LIBP2P_EV_KIND]
    cmp     x1, #LIBP2P_EVENT_DATAGRAM
    b.ne    7f
    ldr     x2, [x0, #LIBP2P_EV_SIZE]
    ldr     x3, [x27, #ST_QEV_OFF]
    add     x3, x27, x3
    ldr     x4, [x3, #LIBP2P_BL_SIZE]
    sub     x4, x4, #LIBP2P_BL_FIXED
    ldr     x5, [x3, #LIBP2P_BL_COUNT]
    sub     x4, x4, x5
    mov     x0, #0
    cmp     x4, x2
    csinv   x0, x0, xzr, hs
    ret
7:  cmp     x1, #LIBP2P_EVENT_RECEIVED
    b.ne    1f
    ldr     x2, [x0, #LIBP2P_EV_COUNT]
    lsl     x2, x2, #4
    add     x0, x2, #64
    ret
1:  cmp     x1, #LIBP2P_EVENT_PARTIAL_PEERS
    b.ne    11f
    ldr     x2, [x27, #ST_PEER_COUNT]
    lsl     x2, x2, #4
    add     x0, x2, #(LIBP2P_ACT_PL_TOPIC + LIBP2P_MAX_TOPIC)
    ret
11: cmp     x1, #LIBP2P_EVENT_CLOSED
    b.eq    2f
    cmp     x1, #LIBP2P_EVENT_DIAL_FAILED
    b.eq    2f
    cmp     x1, #LIBP2P_EVENT_DISCONNECT
    b.eq    2f
    mov     x0, #1024
    ret
2:  mov     x0, #16384
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
 * x27 state, x28 scratch, x19 tick, x20 events, x21 actions, x22 result,
 * x23 event position, x24 events end, x25 events handled.
 */
FUNCTION libp2p_step
    ENTER   0
    mov     x27, x0
    mov     x19, x1
    mov     x20, x2
    mov     x28, x3
    mov     x21, x4
    mov     x22, x5
    mov     x0, #LIBP2P_BUFFER_TOO_SMALL
    ldr     x9, [x28, #SC_SIZE]
    MOV64   x10, SC_TOTAL
    cmp     x9, x10
    b.lo    99f
    ldr     x9, [x21, #LIBP2P_BL_SIZE]
    MOV64   x10, (LIBP2P_ACTIONS_MIN + LIBP2P_BL_FIXED)
    cmp     x9, x10
    b.lo    99f
    ldr     x9, [x20, #LIBP2P_BL_OFFSET]
    add     x23, x20, x9
    ldr     x9, [x20, #LIBP2P_BL_COUNT]
    add     x24, x23, x9
1:  cmp     x23, x24
    b.hs    2f
    mov     x0, x23
    mov     x1, x24
    bl      libp2p_check_event
    mov     x9, x0
    mov     x0, #LIBP2P_INVALID_EVENT
    cbnz    x9, 99f
    ldr     x9, [x23, #LIBP2P_EV_SIZE]
    add     x23, x23, x9
    b       1b

    /* Commit. */
2:  ldr     x9, [x19, #LIBP2P_TICK_NOW]
    ldr     x10, [x27, #ST_NOW]
    cmp     x9, x10
    csel    x9, x9, x10, hs
    str     x9, [x27, #ST_NOW]
    str     x9, [x28, #SC_NOW]
    MOV64   x10, 60000
    add     x10, x9, x10
    str     x10, [x28, #SC_WAKE]
    str     x21, [x28, #SC_ACTIONS]
    mov     x9, #ACTIONS_RESERVE
    str     x9, [x28, #SC_RESERVE]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [x21, #LIBP2P_BL_OFFSET]
    str     xzr, [x21, #LIBP2P_BL_COUNT]
    add     x0, x19, #LIBP2P_TICK_ENTROPY
    bl      libp2p_reseed
    bl      libp2p_free_kept
    ldr     x9, [x27, #ST_QUIC_OFF]         /* QUIC: the tick of asm-quic, then the actions it gave */
    cbz     x9, 21f
    SCR     x26, SC_QTICK
    ldr     x9, [x19, #LIBP2P_TICK_US]
    str     x9, [x26, #QUIC_TICK_NOW]
    ldr     x9, [x19, #LIBP2P_TICK_UNIX]
    str     x9, [x26, #QUIC_TICK_UNIX]
    add     x0, x26, #QUIC_TICK_ENTROPY
    mov     x1, #32
    bl      libp2p_random
    bl      libp2p_quic_actions
21:

    /* The events, while their room lasts. */
    ldr     x9, [x20, #LIBP2P_BL_OFFSET]
    add     x23, x20, x9
    mov     x25, #0
3:  cmp     x23, x24
    b.hs    5f
    mov     x0, x23
    bl      libp2p_event_room
    mov     x26, x0
    bl      libp2p_room
    cmp     x0, x26
    b.lo    4f
    mov     x0, x23
    bl      libp2p_event
    ldr     x9, [x23, #LIBP2P_EV_SIZE]
    add     x23, x23, x9
    add     x25, x25, #1
    b       3b
4:  ldr     x0, [x28, #SC_NOW]              /* events left: the next step is due now */
    bl      libp2p_wake_at

    /* Timers, the drain, WAKEUP. */
5:  str     x25, [x22, #LIBP2P_RESULT_ACCEPTED]
    bl      libp2p_timers
    ldr     x9, [x27, #ST_QUIC_OFF]
    cbz     x9, 51f
    bl      libp2p_quic_pump
51: bl      libp2p_drain
    str     xzr, [x28, #SC_RESERVE]
    mov     x0, #LIBP2P_ACTION_WAKEUP
    mov     x1, #LIBP2P_ACT_WAKEUP_SIZE
    bl      libp2p_action
    ldr     x9, [x28, #SC_WAKE]
    str     x9, [x0, #LIBP2P_ACT_TIME]
    mov     x0, #LIBP2P_OK
99: LEAVE   0
END_FUNCTION libp2p_step

/* libp2p_event(event): handles one checked event: a direct call for each kind. */
LOCAL_FUNCTION libp2p_event
    ENTER   0
    ldr     x9, [x0, #LIBP2P_EV_KIND]
    cmp     x9, #1
    b.ne    1f
    bl      libp2p_on_accepted
    b       99f
1:
    cmp     x9, #2
    b.ne    2f
    bl      libp2p_on_connected
    b       99f
2:
    cmp     x9, #3
    b.ne    3f
    bl      libp2p_on_dial_failed
    b       99f
3:
    cmp     x9, #4
    b.ne    4f
    bl      libp2p_on_received
    b       99f
4:
    cmp     x9, #5
    b.ne    5f
    bl      libp2p_on_sent
    b       99f
5:
    cmp     x9, #6
    b.ne    6f
    bl      libp2p_on_closed
    b       99f
6:
    cmp     x9, #7
    b.ne    7f
    bl      libp2p_on_dial
    b       99f
7:
    cmp     x9, #8
    b.ne    8f
    bl      libp2p_on_disconnect
    b       99f
8:
    cmp     x9, #9
    b.ne    9f
    bl      libp2p_on_open_stream
    b       99f
9:
    cmp     x9, #10
    b.ne    10f
    bl      libp2p_on_stream_write
    b       99f
10:
    cmp     x9, #11
    b.ne    11f
    bl      libp2p_on_stream_close
    b       99f
11:
    cmp     x9, #12
    b.ne    12f
    bl      libp2p_on_stream_reset
    b       99f
12:
    cmp     x9, #13
    b.ne    13f
    bl      libp2p_on_subscribe
    b       99f
13:
    cmp     x9, #14
    b.ne    14f
    bl      libp2p_on_unsubscribe
    b       99f
14:
    cmp     x9, #15
    b.ne    15f
    bl      libp2p_on_publish
    b       99f
15:
    cmp     x9, #16
    b.ne    16f
    bl      libp2p_on_message_id
    b       99f
16:
    cmp     x9, #17
    b.ne    17f
    bl      libp2p_on_validation
    b       99f
17:
    cmp     x9, #18
    b.ne    18f
    bl      libp2p_on_app_score
    b       99f
18:
    cmp     x9, #19
    b.ne    19f
    bl      libp2p_on_topic_params
    b       99f
19:
    cmp     x9, #20
    b.ne    20f
    bl      libp2p_on_partial_subscribe
    b       99f
20:
    cmp     x9, #21
    b.ne    21f
    bl      libp2p_on_partial_peers
    b       99f
21:
    cmp     x9, #22
    b.ne    22f
    bl      libp2p_on_partial_send
    b       99f
22:
    cmp     x9, #23
    b.ne    23f
    bl      libp2p_on_partial_score
    b       99f
23:
    cmp     x9, #24
    b.ne    24f
    bl      libp2p_on_datagram
    b       99f
24:
99: LEAVE   0
END_FUNCTION libp2p_event

/* libp2p_free_kept(): the RPC blocks on the ST_KEPT_RPC list are freed, and the list is empty. */
LOCAL_FUNCTION libp2p_free_kept
    ENTER   0
    ldr     x19, [x27, #ST_KEPT_RPC]
    str     xzr, [x27, #ST_KEPT_RPC]
1:  cbz     x19, 9f
    sub     x9, x19, #HB_HEADER
    add     x9, x27, x9
    ldr     x20, [x9, #HB_NEXT]
    mov     x0, x19
    bl      libp2p_heap_free
    mov     x19, x20
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_free_kept

/* ---------------------------------------------------------------- Timers */

/*
 * libp2p_timers(): ends TCP connections whose upgrade ran out of time, runs the
 * gossipsub heartbeat and score decay when due, and asks for a wakeup at
 * the next deadline.
 * x19 connection, x20 connections left, x21 now.
 */
LOCAL_FUNCTION libp2p_timers
    ENTER   0
    ldr     x21, [x28, #SC_NOW]
    TABLE   x19, ST_CONN_OFF
    ldr     x20, [x27, #ST_CONN_COUNT]
1:  cbz     x20, 3f
    ldr     x9, [x19, #C_FLAGS]             /* asm-quic times QUIC handshakes */
    tst     x9, #CF_QUIC
    b.ne    2f
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_DIALING
    b.lo    2f
    cmp     w9, #PH_OPEN
    b.hs    2f
    ldr     x0, [x19, #C_DEADLINE]
    cmp     x21, x0
    b.lo    11f
    cmp     w9, #PH_DIALING                 /* no TCP connection yet: CONNECT */
    mov     x1, #LIBP2P_REASON_HANDSHAKE
    mov     x10, #LIBP2P_REASON_CONNECT
    csel    x1, x10, x1, eq
    mov     x0, x19
    bl      libp2p_conn_close
    b       2f
11: bl      libp2p_wake_at
2:  add     x19, x19, #C_SIZE
    sub     x20, x20, #1
    b       1b
3:  bl      libp2p_gossip_timers
    LEAVE   0
END_FUNCTION libp2p_timers

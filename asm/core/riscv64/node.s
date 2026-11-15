/*
 * The node of the RISC-V core: the state layout, libp2p_state_size,
 * libp2p_init, libp2p_step, event checks and timers. Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Layout */

/* Branch to fail unless lo <= reg <= hi (unsigned). Uses t6; reg is not t6. */
.macro RANGE reg, lo, hi, fail
    li      t6, \lo
    bltu    \reg, t6, \fail
    li      t6, \hi
    bltu    t6, \reg, \fail
.endm

/* reg = align up of reg to a multiple of 8. */
.macro ALIGN8 reg
    addi    \reg, \reg, 7
    andi    \reg, \reg, -8
.endm

/*
 * libp2p_layout(config, tables) -> a0 status, a1 the state size. Checks the
 * config and writes the table offsets and counts at tables (the ST_TABLES
 * fields), in this order: connections, streams, peers, topics, peer x
 * topic, seen, seen index, message cache, its index, pending, promises,
 * protocols, IDONTWANT rings, heap; with QUIC on, then the asm-quic stream
 * and connection maps, the asm-quic event and action lists, and the
 * asm-quic state, whose config quic_state_size checks.
 * s1 config, s2 tables, s3 offset, s4 to s8 counts. The asm-quic Config at
 * sp + FL, its state size at sp + FL + QUIC_CFG_SIZE.
 */
LOCAL_FUNCTION libp2p_layout
    ENTER   0, (QUIC_CFG_SIZE + 16)
    mv      s1, a0
    mv      s2, a1
    ld      t0, LIBP2P_CFG_SIZE(s1)
    li      t1, LIBP2P_CFG_FIXED
    bltu    t0, t1, 80f
    ld      t1, LIBP2P_CFG_KEY_TYPE(s1)
    RANGE   t1, 1, 2, 80f
    ld      t1, LIBP2P_CFG_MUXERS(s1)
    RANGE   t1, 1, 3, 80f
    ld      s4, LIBP2P_CFG_MAX_CONNECTIONS(s1)
    RANGE   s4, 1, 65536, 80f
    ld      s5, LIBP2P_CFG_MAX_STREAMS(s1)
    RANGE   s5, 1, 1048576, 80f
    ld      s6, LIBP2P_CFG_MAX_PEERS(s1)
    bltu    s6, s4, 80f
    RANGE   s6, 1, 65535, 80f
    ld      s7, LIBP2P_CFG_MAX_TOPICS(s1)
    RANGE   s7, 1, 4096, 80f
    ld      t1, LIBP2P_CFG_HEAP_SIZE(s1)
    RANGE   t1, 65536, 0x10000000000, 80f
    addi    t2, t1, -1
    and     t2, t1, t2
    bnez    t2, 80f
    ld      t1, LIBP2P_CFG_SEEN_CAPACITY(s1)
    RANGE   t1, 1, 16777216, 80f
    ld      t1, LIBP2P_CFG_MCACHE_CAPACITY(s1)
    RANGE   t1, 1, 1048576, 80f
    ld      t1, LIBP2P_CFG_PENDING_CAPACITY(s1)
    RANGE   t1, 1, 1048576, 80f
    ld      t1, LIBP2P_CFG_SEND_WINDOW(s1)
    RANGE   t1, 131072, 0x40000000, 80f
    ld      t1, LIBP2P_CFG_MAX_RPC(s1)
    RANGE   t1, 1024, 0x40000000, 80f
    ld      t2, LIBP2P_CFG_MAX_DATA(s1)
    bltu    t1, t2, 80f
    ld      t1, LIBP2P_CFG_STREAM_QUEUE(s1)
    RANGE   t1, 65536, 0x40000000, 80f
    ld      t1, LIBP2P_CFG_HANDSHAKE_MS(s1)
    beqz    t1, 80f
    ld      t1, LIBP2P_CFG_VALIDATION_MS(s1)
    beqz    t1, 80f
    ld      t1, LIBP2P_CFG_D(s1)            # gossipsub degrees
    RANGE   t1, 1, 64, 80f
    ld      t2, LIBP2P_CFG_D_LOW(s1)
    bltu    t1, t2, 80f
    ld      t3, LIBP2P_CFG_D_HIGH(s1)
    bltu    t3, t1, 80f
    RANGE   t3, 1, 64, 80f
    ld      t4, LIBP2P_CFG_D_LAZY(s1)
    RANGE   t4, 0, 64, 80f
    ld      t4, LIBP2P_CFG_D_SCORE(s1)
    bltu    t3, t4, 80f
    ld      t4, LIBP2P_CFG_D_OUT(s1)
    bltu    t2, t4, 80f
    ld      t1, LIBP2P_CFG_HEARTBEAT_MS(s1)
    beqz    t1, 80f
    ld      t1, LIBP2P_CFG_MCACHE_LEN(s1)
    RANGE   t1, 1, 64, 80f
    ld      t2, LIBP2P_CFG_MCACHE_GOSSIP(s1)
    bltu    t1, t2, 80f
    ld      t1, LIBP2P_CFG_SEEN_TTL_MS(s1)
    beqz    t1, 80f
    ld      t1, LIBP2P_CFG_MAX_IHAVE_LENGTH(s1)
    RANGE   t1, 0, 8192, 80f
    ld      t1, LIBP2P_CFG_AGENT_LEN(s1)
    RANGE   t1, 0, 64, 80f
    ld      t1, LIBP2P_CFG_PV_LEN(s1)
    RANGE   t1, 0, 32, 80f
    ld      t1, LIBP2P_CFG_SCORING(s1)
    RANGE   t1, 0, 1, 80f
    beqz    t1, 1f
    ld      t1, LIBP2P_CFG_DECAY_INTERVAL_MS(s1)
    beqz    t1, 80f
1:  ld      t1, LIBP2P_CFG_GOSSIPSUB_V12(s1)   # gossipsub v1.2
    RANGE   t1, 0, 1, 80f
    ld      t1, LIBP2P_CFG_DONTWANT_SLOTS(s1)
    RANGE   t1, 0, 4096, 80f
    beqz    t1, 11f
    ld      t1, LIBP2P_CFG_DONTWANT_TTL(s1)
    beqz    t1, 80f
11: ld      t1, LIBP2P_CFG_GOSSIPSUB_V13(s1)   # gossipsub v1.3: needs v1.2
    RANGE   t1, 0, 1, 80f
    beqz    t1, 12f
    ld      t2, LIBP2P_CFG_GOSSIPSUB_V12(s1)
    beqz    t2, 80f
12: ld      t2, LIBP2P_CFG_PARTIAL_MESSAGES(s1) # partial messages: need v1.3
    RANGE   t2, 0, 1, 80f
    bltu    t1, t2, 80f
    ld      t1, LIBP2P_CFG_QUIC(s1)            # QUIC: off, on, or on and accepting
    RANGE   t1, 0, (LIBP2P_QUIC_ON | LIBP2P_QUIC_ACCEPT), 80f
    li      t2, LIBP2P_QUIC_ACCEPT
    beq     t1, t2, 80f
    beqz    t1, 13f
    ld      t1, LIBP2P_CFG_QUIC_WINDOW(s1)
    RANGE   t1, 65536, 0x40000000, 80f
13:

    /* The protocols part. */
    ld      s8, LIBP2P_CFG_PROTOCOLS_COUNT(s1)
    RANGE   s8, 0, 64, 80f
    beqz    s8, 3f
    ld      t1, LIBP2P_CFG_PROTOCOLS(s1)
    andi    t2, t1, 7
    bnez    t2, 80f
    li      t2, LIBP2P_CFG_FIXED
    bltu    t1, t2, 80f
    li      t2, LIBP2P_PROTO_SIZE
    mul     t2, s8, t2
    add     t2, t2, t1
    ld      t3, LIBP2P_CFG_SIZE(s1)
    bltu    t3, t2, 80f
    add     t1, s1, t1
    mv      t2, s8
2:  ld      t3, LIBP2P_PROTO_LEN(t1)
    RANGE   t3, 1, LIBP2P_MAX_PROTOCOL, 80f
    addi    t4, t1, LIBP2P_PROTO_BYTES
    li      t0, 10
21: lbu     t5, 0(t4)
    addi    t4, t4, 1
    beq     t5, t0, 80f
    addi    t3, t3, -1
    bnez    t3, 21b
    addi    t1, t1, LIBP2P_PROTO_SIZE
    addi    t2, t2, -1
    bnez    t2, 2b

    /* The tables. */
3:  li      s3, ST_FIXED
    ALIGN8  s3
    sd      s3, (ST_CONN_OFF - ST_TABLES)(s2)
    sd      s4, (ST_CONN_COUNT - ST_TABLES)(s2)
    li      t0, C_SIZE
    mul     t0, s4, t0
    add     s3, s3, t0
    sd      s3, (ST_STREAM_OFF - ST_TABLES)(s2)
    sd      s5, (ST_STREAM_COUNT - ST_TABLES)(s2)
    li      t0, S_SIZE
    mul     t0, s5, t0
    add     s3, s3, t0
    sd      s3, (ST_PEER_OFF - ST_TABLES)(s2)
    sd      s6, (ST_PEER_COUNT - ST_TABLES)(s2)
    li      t0, P_SIZE
    mul     t0, s6, t0
    add     s3, s3, t0
    sd      s3, (ST_TOPIC_OFF - ST_TABLES)(s2)
    sd      s7, (ST_TOPIC_COUNT - ST_TABLES)(s2)
    li      t0, T_SIZE
    mul     t0, s7, t0
    add     s3, s3, t0
    sd      s3, (ST_PT_OFF - ST_TABLES)(s2)
    mul     t0, s6, s7
    li      t1, PT_SIZE
    mul     t0, t0, t1
    add     s3, s3, t0
    ld      s4, LIBP2P_CFG_SEEN_CAPACITY(s1)
    sd      s3, (ST_SEEN_OFF - ST_TABLES)(s2)
    sd      s4, (ST_SEEN_COUNT - ST_TABLES)(s2)
    li      t0, SN_SIZE
    mul     t0, s4, t0
    add     s3, s3, t0
    sd      s3, (ST_SEEN_INDEX_OFF - ST_TABLES)(s2)
    slli    t0, s4, 3                       # 2 x capacity u32
    add     s3, s3, t0
    ld      s4, LIBP2P_CFG_MCACHE_CAPACITY(s1)
    sd      s3, (ST_MC_OFF - ST_TABLES)(s2)
    sd      s4, (ST_MC_COUNT - ST_TABLES)(s2)
    addi    t0, s6, 31                      # 2 bits for each peer, in u64 words
    srli    t0, t0, 5
    slli    t0, t0, 3
    addi    t0, t0, MC_TX
    sd      t0, (ST_MC_STRIDE - ST_TABLES)(s2)
    mul     t0, s4, t0
    add     s3, s3, t0
    sd      s3, (ST_MC_INDEX_OFF - ST_TABLES)(s2)
    slli    t0, s4, 3
    add     s3, s3, t0
    ld      s4, LIBP2P_CFG_PENDING_CAPACITY(s1)
    sd      s3, (ST_PEND_OFF - ST_TABLES)(s2)
    sd      s4, (ST_PEND_COUNT - ST_TABLES)(s2)
    li      t0, PD_SIZE
    mul     t0, s4, t0
    add     s3, s3, t0
    sd      s3, (ST_PROMISE_OFF - ST_TABLES)(s2)
    li      t0, (LIBP2P_PROMISES * PR_SIZE)
    add     s3, s3, t0
    sd      s3, (ST_PROTO_OFF - ST_TABLES)(s2)
    sd      s8, (ST_PROTO_COUNT - ST_TABLES)(s2)
    li      t0, LIBP2P_PROTO_SIZE
    mul     t0, s8, t0
    add     s3, s3, t0
    sd      s3, (ST_DW_OFF - ST_TABLES)(s2)
    ld      t0, LIBP2P_CFG_DONTWANT_SLOTS(s1)
    mul     t0, t0, s6
    li      t1, DW_SIZE
    mul     t0, t0, t1
    add     s3, s3, t0
    addi    s3, s3, 63                      # the heap, at a multiple of 64
    andi    s3, s3, -64
    ld      t0, LIBP2P_CFG_HEAP_SIZE(s1)
    sd      s3, (ST_HEAP_OFF - ST_TABLES)(s2)
    sd      t0, (ST_HEAP_SIZE - ST_TABLES)(s2)
    add     s3, s3, t0
    sd      s3, (ST_QMAP_OFF - ST_TABLES)(s2)
    ld      t0, LIBP2P_CFG_QUIC(s1)
    bnez    t0, 4f
    sd      s3, (ST_QCMAP_OFF - ST_TABLES)(s2)  # QUIC off: the parts are empty
    sd      s3, (ST_QEV_OFF - ST_TABLES)(s2)
    sd      s3, (ST_QACT_OFF - ST_TABLES)(s2)
    sd      zero, (ST_QUIC_OFF - ST_TABLES)(s2)
    mv      a1, s3
    j       5f
4:  ld      t0, LIBP2P_CFG_MAX_STREAMS(s1)  # the asm-quic stream map: u32 each
    slli    t0, t0, 2
    add     s3, s3, t0
    ALIGN8  s3
    sd      s3, (ST_QCMAP_OFF - ST_TABLES)(s2)
    ld      t0, LIBP2P_CFG_MAX_CONNECTIONS(s1)
    slli    t0, t0, 2
    add     s3, s3, t0
    ALIGN8  s3
    sd      s3, (ST_QEV_OFF - ST_TABLES)(s2)
    li      t0, (LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS)
    add     s3, s3, t0
    sd      s3, (ST_QACT_OFF - ST_TABLES)(s2)
    li      t0, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    add     s3, s3, t0
    addi    s3, s3, 63                      # the asm-quic state, at a multiple of 64
    andi    s3, s3, -64
    sd      s3, (ST_QUIC_OFF - ST_TABLES)(s2)
    mv      a0, s1
    addi    a1, sp, FL
    call    libp2p_quic_config
    addi    a0, sp, FL
    addi    a1, sp, (FL + QUIC_CFG_SIZE)
    CALL_GLOBAL quic_state_size
    bnez    a0, 80f
    ld      t0, (FL + QUIC_CFG_SIZE)(sp)
    add     a1, s3, t0
5:  li      a0, LIBP2P_OK
    j       99f
80: li      a0, LIBP2P_INVALID_CONFIG
    li      a1, 0
99: LEAVE   0, (QUIC_CFG_SIZE + 16)
END_FUNCTION libp2p_layout

/* ---------------------------------------------------------------- libp2p_state_size */

/* libp2p_state_size(config, size) -> status: the bytes of the state for the config. */
FUNCTION libp2p_state_size
    ENTER   0, TABLES_ROOM
    mv      s1, a1
    addi    a1, sp, FL
    call    libp2p_layout
    bnez    a0, 9f
    sd      a1, 0(s1)
9:  LEAVE   0, TABLES_ROOM
END_FUNCTION libp2p_state_size

/* ---------------------------------------------------------------- libp2p_init */

/*
 * libp2p_init(config, state) -> status. Checks the config, the state size
 * and the private key; then builds the state: keys, peer ID, the static
 * Noise key and its signature, empty tables, one free heap block, timers;
 * with QUIC on, the asm-quic maps and lists, and the asm-quic state with a
 * seed from the DRBG.
 * s1 config, s2 state, s3 the state size needed. Extra: the tables at
 * sp + FL (then the asm-quic Config), the public key at sp + FL + IN_KEY,
 * the entropy ByteList at sp + FL + IN_BL.
 */
.set IN_KEY, TABLES_ROOM
.set IN_BL, IN_KEY + 48
.set IN_FRAME, IN_BL + 64
FUNCTION libp2p_init
    ENTER   0, IN_FRAME
    mv      s1, a0
    mv      s2, a1
    mv      s9, a1
    addi    a1, sp, FL
    call    libp2p_layout
    bnez    a0, 99f
    mv      s3, a1
    li      a0, LIBP2P_BUFFER_TOO_SMALL
    ld      t0, ST_SIZE(s2)
    bltu    t0, s3, 99f
    ld      t0, LIBP2P_CFG_KEY_TYPE(s1)     # the public key, on the stack first
    li      t1, LIBP2P_KEY_SECP256K1
    bne     t0, t1, 1f
    addi    a0, s1, LIBP2P_CFG_PRIVATE_KEY
    addi    a1, sp, (FL + IN_KEY)
    CALL_GLOBAL crypto_secp256k1_public_key
    mv      t0, a0
    li      a0, LIBP2P_INVALID_KEY
    bnez    t0, 99f
    li      s4, 33
    j       2f
1:  addi    a0, s1, LIBP2P_CFG_PRIVATE_KEY
    addi    a1, sp, (FL + IN_KEY)
    CALL_GLOBAL crypto_ed25519_public_key
    li      s4, 32

    /* Commit: zero all but the heap, then fill in. */
2:  ld      s5, (FL + ST_HEAP_OFF - ST_TABLES)(sp)
    addi    a0, s2, 8
    addi    a1, s5, -8
    call    libp2p_zero
    li      t0, LIBP2P_STATE_VERSION
    sd      t0, ST_VERSION(s2)
    addi    a0, s2, ST_TABLES
    addi    a1, sp, FL
    li      a2, (ST_TABLES_END - ST_TABLES)
    call    libp2p_copy
    addi    a0, s2, ST_CONFIG
    mv      a1, s1
    li      a2, LIBP2P_CFG_FIXED
    call    libp2p_copy
    ld      t0, LIBP2P_CFG_NOW(s1)
    sd      t0, ST_NOW(s2)
    ld      a2, ST_PROTO_COUNT(s2)          # the protocols
    li      t0, LIBP2P_PROTO_SIZE
    mul     a2, a2, t0
    ld      a0, ST_PROTO_OFF(s2)
    add     a0, s2, a0
    ld      a1, LIBP2P_CFG_PROTOCOLS(s1)
    add     a1, s1, a1
    call    libp2p_copy
    li      t0, 56                          # DRBG key = SHA-256(entropy)
    sd      t0, (FL + IN_BL)(sp)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (FL + IN_BL + 8)(sp)
    li      t0, 32
    sd      t0, (FL + IN_BL + 16)(sp)
    addi    a0, sp, (FL + IN_BL + 24)
    addi    a1, s1, LIBP2P_CFG_ENTROPY
    li      a2, 32
    call    libp2p_copy
    addi    a0, sp, (FL + IN_BL)
    addi    a1, s2, ST_DRBG_KEY
    CALL_GLOBAL crypto_sha256
    ld      t0, LIBP2P_CFG_KEY_TYPE(s1)
    sd      t0, ST_KEY_TYPE(s2)
    addi    a0, s2, ST_PRIVATE_KEY
    addi    a1, s1, LIBP2P_CFG_PRIVATE_KEY
    li      a2, 32
    call    libp2p_copy
    addi    a0, s2, ST_PUBLIC_KEY
    addi    a1, sp, (FL + IN_KEY)
    mv      a2, s4
    call    libp2p_copy
    sd      s4, ST_PUBLIC_LEN(s2)
    addi    a0, s2, ST_PEER_ID
    ld      a1, ST_KEY_TYPE(s2)
    addi    a2, s2, ST_PUBLIC_KEY
    mv      a3, s4
    call    libp2p_peer_id
    sd      a0, ST_PEER_ID_LEN(s2)
    addi    a0, s2, ST_NOISE_PRIV           # the static Noise key
    li      a1, 32
    call    libp2p_random
    addi    a0, s2, ST_NOISE_PRIV
    lla     a1, 421b
    addi    a2, s2, ST_NOISE_PUB
    CALL_GLOBAL crypto_x25519
    call    libp2p_sign_static
    ld      t0, ST_PROMISE_OFF(s2)          # promises: no peer
    add     t0, s2, t0
    li      t1, LIBP2P_PROMISES
    li      t2, NONE
3:  sd      t2, PR_PEER(t0)
    addi    t0, t0, PR_SIZE
    addi    t1, t1, -1
    bnez    t1, 3b
    addi    t0, s2, ST_HEAP_FREE            # the heap: one free block
    li      t1, ST_HEAP_ORDERS
4:  sd      t2, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bnez    t1, 4b
    ld      t0, ST_HEAP_SIZE(s2)            # its order: the size is a power of 2
    li      t1, 0
5:  andi    t3, t0, 1
    bnez    t3, 6f
    srli    t0, t0, 1
    addi    t1, t1, 1
    j       5b
6:  add     t3, s2, s5
    sw      t1, HB_ORDER(t3)
    li      t4, 1
    sw      t4, HB_FREE(t3)
    sd      t2, HB_NEXT(t3)
    sd      t2, HB_PREV(t3)
    addi    t0, s2, ST_HEAP_FREE
    slli    t1, t1, 3
    add     t0, t0, t1
    sd      zero, 0(t0)
    ld      t0, ST_NOW(s2)                  # timers
    ld      t1, (ST_CONFIG + LIBP2P_CFG_HEARTBEAT_MS)(s2)
    add     t1, t0, t1
    sd      t1, ST_HEARTBEAT_AT(s2)
    ld      t1, (ST_CONFIG + LIBP2P_CFG_DECAY_INTERVAL_MS)(s2)
    add     t1, t0, t1
    sd      t1, ST_DECAY_AT(s2)
    ld      t0, ST_QUIC_OFF(s2)             # QUIC: maps, lists, the asm-quic state
    beqz    t0, 8f
    ld      t0, ST_QMAP_OFF(s2)
    add     t0, s2, t0
    ld      t1, ST_QEV_OFF(s2)
    add     t1, s2, t1
    li      t2, NONE
7:  bgeu    t0, t1, 71f
    sd      t2, 0(t0)
    addi    t0, t0, 8
    j       7b
71: ld      t0, ST_QEV_OFF(s2)
    add     t0, s2, t0
    li      t1, (LIBP2P_BL_FIXED + LIBP2P_QUIC_EVENTS)
    sd      t1, LIBP2P_BL_SIZE(t0)
    li      t1, LIBP2P_BL_FIXED
    sd      t1, LIBP2P_BL_OFFSET(t0)
    sd      zero, LIBP2P_BL_COUNT(t0)
    ld      t0, ST_QACT_OFF(s2)
    add     t0, s2, t0
    li      t1, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    sd      t1, LIBP2P_BL_SIZE(t0)
    li      t1, LIBP2P_BL_FIXED
    sd      t1, LIBP2P_BL_OFFSET(t0)
    sd      zero, LIBP2P_BL_COUNT(t0)
    ld      t0, ST_QUIC_OFF(s2)
    sub     t1, s3, t0
    add     t0, s2, t0
    sd      t1, 0(t0)                       # the size of the asm-quic state
    mv      a0, s1
    addi    a1, sp, FL
    call    libp2p_quic_config
    addi    a0, sp, (FL + QUIC_CFG_SEED)
    li      a1, 32
    call    libp2p_random
    addi    a0, sp, FL
    ld      a1, ST_QUIC_OFF(s2)
    add     a1, s2, a1
    CALL_GLOBAL quic_init
8:  li      a0, LIBP2P_OK
99: LEAVE   0, IN_FRAME
END_FUNCTION libp2p_init

/* ---------------------------------------------------------------- Event checks */

/*
 * libp2p_check_event(event, end) -> 0 when the event is well formed and fits
 * before end; 1 otherwise. s1 event, s2 size, s3 kind.
 */
LOCAL_FUNCTION libp2p_check_event
    ENTER   0
    mv      s1, a0
    sub     t0, a1, a0
    li      t1, 16
    bltu    t0, t1, 80f
    ld      s2, LIBP2P_EV_SIZE(s1)
    bltu    s2, t1, 80f
    andi    t1, s2, 7
    bnez    t1, 80f
    bltu    t0, s2, 80f
    ld      s3, LIBP2P_EV_KIND(s1)
    RANGE   s3, 1, LIBP2P_EVENT_LAST, 80f
    lla     t0, 300f                        # the minimum size of the kind
    slli    t1, s3, 1
    add     t0, t0, t1
    lhu     t0, 0(t0)
    bltu    s2, t0, 80f
    li      t0, LIBP2P_EVENT_ACCEPTED
    bne     s3, t0, 1f
    addi    a0, s1, LIBP2P_EV_ACCEPTED_ADDR
    call    libp2p_check_addr
    j       99f
1:  li      t0, LIBP2P_EVENT_RECEIVED
    bne     s3, t0, 2f
    ld      t0, LIBP2P_EV_COUNT(s1)
    RANGE   t0, 0, LIBP2P_RECEIVE_MAX, 80f
    addi    t1, s2, -LIBP2P_EV_DATA
    bltu    t1, t0, 80f
    j       70f
2:  li      t0, LIBP2P_EVENT_DIAL
    bne     s3, t0, 3f
    ld      t0, LIBP2P_EV_DIAL_ID_LEN(s1)
    RANGE   t0, 0, LIBP2P_MAX_PEER_ID, 80f
    ld      t0, LIBP2P_EV_DIAL_TRANSPORT(s1)
    RANGE   t0, 0, LIBP2P_QUIC, 80f
    beqz    t0, 21f
    ld      t0, ST_QUIC_OFF(s9)             # QUIC needs QUIC on
    beqz    t0, 80f
21: addi    a0, s1, LIBP2P_EV_DIAL_ADDR
    call    libp2p_check_addr
    j       99f
3:  li      t0, LIBP2P_EVENT_OPEN_STREAM
    bne     s3, t0, 4f
    ld      s4, LIBP2P_EV_OPEN_COUNT(s1)
    RANGE   s4, 1, LIBP2P_MAX_PROPOSALS, 80f
    li      t0, LIBP2P_PROTO_SIZE
    mul     t0, s4, t0
    addi    t0, t0, LIBP2P_EV_OPEN_PROTOCOLS
    bltu    s2, t0, 80f
    addi    s5, s1, LIBP2P_EV_OPEN_PROTOCOLS
31: ld      t2, LIBP2P_PROTO_LEN(s5)
    RANGE   t2, 1, LIBP2P_MAX_PROTOCOL, 80f
    addi    t3, s5, LIBP2P_PROTO_BYTES
    li      t0, 10
32: lbu     t4, 0(t3)
    addi    t3, t3, 1
    beq     t4, t0, 80f
    addi    t2, t2, -1
    bnez    t2, 32b
    addi    s5, s5, LIBP2P_PROTO_SIZE
    addi    s4, s4, -1
    bnez    s4, 31b
    j       70f
4:  li      t0, LIBP2P_EVENT_STREAM_WRITE
    bne     s3, t0, 5f
    ld      t0, LIBP2P_EV_STREAM_COUNT(s1)
    addi    t1, s2, -LIBP2P_EV_STREAM_DATA
    bltu    t1, t0, 80f
    j       70f
5:  li      t0, LIBP2P_EVENT_SUBSCRIBE
    beq     s3, t0, 51f
    li      t0, LIBP2P_EVENT_UNSUBSCRIBE
    bne     s3, t0, 6f
51: ld      t0, LIBP2P_EV_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    addi    t1, s2, -LIBP2P_EV_TOPIC
    bltu    t1, t0, 80f
    j       70f
6:  li      t0, LIBP2P_EVENT_PUBLISH
    bne     s3, t0, 7f
    ld      t0, LIBP2P_EV_PUB_ID_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_MSG_ID, 80f
    ld      t0, LIBP2P_EV_PUB_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  t0
    ld      t1, LIBP2P_EV_PUB_DATA_LEN(s1)
    CFG     t2, LIBP2P_CFG_MAX_DATA
    bltu    t2, t1, 80f
    add     t0, t0, t1
    addi    t0, t0, LIBP2P_EV_PUB_TOPIC
    bltu    s2, t0, 80f
    j       70f
7:  li      t0, LIBP2P_EVENT_MESSAGE_ID
    bne     s3, t0, 8f
    ld      t0, LIBP2P_EV_MSG_ID_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_MSG_ID, 80f
    j       70f
8:  li      t0, LIBP2P_EVENT_VALIDATION
    bne     s3, t0, 9f
    ld      t0, LIBP2P_EV_RESULT(s1)
    RANGE   t0, 1, 3, 80f
    j       70f
9:  li      t0, LIBP2P_EVENT_TOPIC_PARAMS
    bne     s3, t0, 10f
    ld      t0, LIBP2P_EV_TP_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    addi    t1, s2, -LIBP2P_EV_TP_TOPIC
    bltu    t1, t0, 80f
    j       70f
10: li      t0, LIBP2P_EVENT_PARTIAL_SUBSCRIBE
    bne     s3, t0, 11f
    ld      t0, LIBP2P_EV_PS_FLAGS(s1)
    RANGE   t0, 0, 3, 80f
    beqz    t0, 101f
    CFG     t1, LIBP2P_CFG_PARTIAL_MESSAGES
    beqz    t1, 80f
101: ld     t0, LIBP2P_EV_PS_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    addi    t1, s2, -LIBP2P_EV_PS_TOPIC
    bltu    t1, t0, 80f
    j       70f
11: li      t0, LIBP2P_EVENT_PARTIAL_PEERS
    bne     s3, t0, 12f
    ld      t0, LIBP2P_EV_PP_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    addi    t1, s2, -LIBP2P_EV_PP_TOPIC
    bltu    t1, t0, 80f
    j       70f
12: li      t0, LIBP2P_EVENT_PARTIAL_SEND
    bne     s3, t0, 13f
    ld      t0, LIBP2P_EV_PSEND_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    ALIGN8  t0
    CFG     t2, LIBP2P_CFG_MAX_RPC
    ld      t1, LIBP2P_EV_PSEND_GROUP_LEN(s1)
    bltu    t2, t1, 80f
    ALIGN8  t1
    add     t0, t0, t1
    ld      t1, LIBP2P_EV_PSEND_META_LEN(s1)
    bltu    t2, t1, 80f
    ALIGN8  t1
    add     t0, t0, t1
    ld      t1, LIBP2P_EV_PSEND_MSG_LEN(s1)
    bltu    t2, t1, 80f
    add     t0, t0, t1
    addi    t0, t0, LIBP2P_EV_PSEND_BYTES
    bltu    s2, t0, 80f
    j       70f
13: li      t0, LIBP2P_EVENT_PARTIAL_SCORE
    bne     s3, t0, 14f
    ld      t0, LIBP2P_EV_PSCORE_RESULT(s1)
    RANGE   t0, 1, 2, 80f
    ld      t0, LIBP2P_EV_PSCORE_TOPIC_LEN(s1)
    RANGE   t0, 1, LIBP2P_MAX_TOPIC, 80f
    addi    t1, s2, -LIBP2P_EV_PSCORE_TOPIC
    bltu    t1, t0, 80f
    j       70f
14: li      t0, LIBP2P_EVENT_DATAGRAM
    bne     s3, t0, 70f
    ld      t0, ST_QUIC_OFF(s9)             # QUIC on
    beqz    t0, 80f
    RANGE   s2, LIBP2P_EV_DG_DATA, (LIBP2P_EV_DG_DATA + LIBP2P_DATAGRAM_MAX + 1), 80f
    ld      t0, LIBP2P_EV_DG_COUNT(s1)
    RANGE   t0, 0, LIBP2P_DATAGRAM_MAX, 80f
    addi    t1, s2, -LIBP2P_EV_DG_DATA
    bltu    t1, t0, 80f
    addi    a0, s1, LIBP2P_EV_DG_ADDR
    call    libp2p_check_addr
    j       99f
70: li      a0, 0
    j       99f
80: li      a0, 1
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
    ld      a1, LIBP2P_ADDR_FAMILY(a0)
    ld      a2, LIBP2P_ADDR_PORT(a0)
    li      a0, 1
    li      a3, 4
    beq     a1, a3, 1f
    li      a3, 6
    bne     a1, a3, 9f
1:  li      a3, 0x10000
    bgeu    a2, a3, 9f
    li      a0, 0
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
    ld      a1, LIBP2P_EV_KIND(a0)
    li      a3, LIBP2P_EVENT_DATAGRAM
    bne     a1, a3, 7f
    ld      a2, LIBP2P_EV_SIZE(a0)
    ld      a3, ST_QEV_OFF(s9)
    add     a3, s9, a3
    ld      a4, LIBP2P_BL_SIZE(a3)
    addi    a4, a4, -LIBP2P_BL_FIXED
    ld      a5, LIBP2P_BL_COUNT(a3)
    sub     a4, a4, a5
    li      a0, 0
    bgeu    a4, a2, 71f
    li      a0, -1
71: ret
7:  li      a3, LIBP2P_EVENT_RECEIVED
    bne     a1, a3, 1f
    ld      a2, LIBP2P_EV_COUNT(a0)
    slli    a2, a2, 4
    addi    a0, a2, 64
    ret
1:  li      a3, LIBP2P_EVENT_PARTIAL_PEERS
    bne     a1, a3, 11f
    ld      a2, ST_PEER_COUNT(s9)
    slli    a2, a2, 4
    addi    a0, a2, (LIBP2P_ACT_PL_TOPIC + LIBP2P_MAX_TOPIC)
    ret
11: li      a3, LIBP2P_EVENT_CLOSED
    beq     a1, a3, 2f
    li      a3, LIBP2P_EVENT_DIAL_FAILED
    beq     a1, a3, 2f
    li      a3, LIBP2P_EVENT_DISCONNECT
    beq     a1, a3, 2f
    li      a0, 1024
    ret
2:  li      a0, 16384
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
 * s9 state, s10 scratch, s1 tick, s2 events, s3 actions, s4 result,
 * s5 event position, s6 events end, s7 events handled.
 */
FUNCTION libp2p_step
    ENTER   0
    mv      s9, a0
    mv      s1, a1
    mv      s2, a2
    mv      s10, a3
    mv      s3, a4
    mv      s4, a5
    li      a0, LIBP2P_BUFFER_TOO_SMALL
    ld      t0, SC_SIZE(s10)
    li      t1, SC_TOTAL
    bltu    t0, t1, 99f
    ld      t0, LIBP2P_BL_SIZE(s3)
    li      t1, (LIBP2P_ACTIONS_MIN + LIBP2P_BL_FIXED)
    bltu    t0, t1, 99f
    ld      t0, LIBP2P_BL_OFFSET(s2)
    add     s5, s2, t0
    ld      t0, LIBP2P_BL_COUNT(s2)
    add     s6, s5, t0
1:  bgeu    s5, s6, 2f
    mv      a0, s5
    mv      a1, s6
    call    libp2p_check_event
    mv      t0, a0
    li      a0, LIBP2P_INVALID_EVENT
    bnez    t0, 99f
    ld      t0, LIBP2P_EV_SIZE(s5)
    add     s5, s5, t0
    j       1b

    /* Commit. */
2:  ld      t0, LIBP2P_TICK_NOW(s1)
    ld      t1, ST_NOW(s9)
    bgeu    t0, t1, 21f
    mv      t0, t1
21: sd      t0, ST_NOW(s9)
    sd      t0, SC_NOW(s10)
    li      t1, 60000
    add     t1, t0, t1
    sd      t1, SC_WAKE(s10)
    sd      s3, SC_ACTIONS(s10)
    li      t0, ACTIONS_RESERVE
    sd      t0, SC_RESERVE(s10)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, LIBP2P_BL_OFFSET(s3)
    sd      zero, LIBP2P_BL_COUNT(s3)
    addi    a0, s1, LIBP2P_TICK_ENTROPY
    call    libp2p_reseed
    call    libp2p_free_kept
    ld      t0, ST_QUIC_OFF(s9)             # QUIC: the tick of asm-quic, then the actions it gave
    beqz    t0, 22f
    SCR     s8, SC_QTICK
    ld      t0, LIBP2P_TICK_US(s1)
    sd      t0, QUIC_TICK_NOW(s8)
    ld      t0, LIBP2P_TICK_UNIX(s1)
    sd      t0, QUIC_TICK_UNIX(s8)
    addi    a0, s8, QUIC_TICK_ENTROPY
    li      a1, 32
    call    libp2p_random
    call    libp2p_quic_actions
22:

    /* The events, while their room lasts. */
    ld      t0, LIBP2P_BL_OFFSET(s2)
    add     s5, s2, t0
    li      s7, 0
3:  bgeu    s5, s6, 5f
    mv      a0, s5
    call    libp2p_event_room
    mv      s8, a0
    call    libp2p_room
    bltu    a0, s8, 4f
    mv      a0, s5
    call    libp2p_event
    ld      t0, LIBP2P_EV_SIZE(s5)
    add     s5, s5, t0
    addi    s7, s7, 1
    j       3b
4:  ld      a0, SC_NOW(s10)                 # events left: the next step is due now
    call    libp2p_wake_at

    /* Timers, the drain, WAKEUP. */
5:  sd      s7, LIBP2P_RESULT_ACCEPTED(s4)
    call    libp2p_timers
    ld      t0, ST_QUIC_OFF(s9)
    beqz    t0, 51f
    call    libp2p_quic_pump
51: call    libp2p_drain
    sd      zero, SC_RESERVE(s10)
    li      a0, LIBP2P_ACTION_WAKEUP
    li      a1, LIBP2P_ACT_WAKEUP_SIZE
    call    libp2p_action
    ld      t0, SC_WAKE(s10)
    sd      t0, LIBP2P_ACT_TIME(a0)
    li      a0, LIBP2P_OK
99: LEAVE   0
END_FUNCTION libp2p_step

/* libp2p_event(event): handles one checked event: a direct call for each kind. */
LOCAL_FUNCTION libp2p_event
    ENTER   0
    ld      t0, LIBP2P_EV_KIND(a0)
    li      t1, 1
    bne     t0, t1, 1f
    call    libp2p_on_accepted
    j       99f
1:  li      t1, 2
    bne     t0, t1, 2f
    call    libp2p_on_connected
    j       99f
2:  li      t1, 3
    bne     t0, t1, 3f
    call    libp2p_on_dial_failed
    j       99f
3:  li      t1, 4
    bne     t0, t1, 4f
    call    libp2p_on_received
    j       99f
4:  li      t1, 5
    bne     t0, t1, 5f
    call    libp2p_on_sent
    j       99f
5:  li      t1, 6
    bne     t0, t1, 6f
    call    libp2p_on_closed
    j       99f
6:  li      t1, 7
    bne     t0, t1, 7f
    call    libp2p_on_dial
    j       99f
7:  li      t1, 8
    bne     t0, t1, 8f
    call    libp2p_on_disconnect
    j       99f
8:  li      t1, 9
    bne     t0, t1, 9f
    call    libp2p_on_open_stream
    j       99f
9:  li      t1, 10
    bne     t0, t1, 10f
    call    libp2p_on_stream_write
    j       99f
10: li      t1, 11
    bne     t0, t1, 11f
    call    libp2p_on_stream_close
    j       99f
11: li      t1, 12
    bne     t0, t1, 12f
    call    libp2p_on_stream_reset
    j       99f
12: li      t1, 13
    bne     t0, t1, 13f
    call    libp2p_on_subscribe
    j       99f
13: li      t1, 14
    bne     t0, t1, 14f
    call    libp2p_on_unsubscribe
    j       99f
14: li      t1, 15
    bne     t0, t1, 15f
    call    libp2p_on_publish
    j       99f
15: li      t1, 16
    bne     t0, t1, 16f
    call    libp2p_on_message_id
    j       99f
16: li      t1, 17
    bne     t0, t1, 17f
    call    libp2p_on_validation
    j       99f
17: li      t1, 18
    bne     t0, t1, 18f
    call    libp2p_on_app_score
    j       99f
18: li      t1, 19
    bne     t0, t1, 19f
    call    libp2p_on_topic_params
    j       99f
19: li      t1, 20
    bne     t0, t1, 20f
    call    libp2p_on_partial_subscribe
    j       99f
20: li      t1, 21
    bne     t0, t1, 21f
    call    libp2p_on_partial_peers
    j       99f
21: li      t1, 22
    bne     t0, t1, 22f
    call    libp2p_on_partial_send
    j       99f
22: li      t1, 23
    bne     t0, t1, 23f
    call    libp2p_on_partial_score
    j       99f
23: li      t1, 24
    bne     t0, t1, 99f
    call    libp2p_on_datagram
99: LEAVE   0
END_FUNCTION libp2p_event

/* libp2p_free_kept(): the RPC blocks on the ST_KEPT_RPC list are freed, and the list is empty. s1 block, s2 next. */
LOCAL_FUNCTION libp2p_free_kept
    ENTER   0
    ld      s1, ST_KEPT_RPC(s9)
    sd      zero, ST_KEPT_RPC(s9)
1:  beqz    s1, 9f
    add     t0, s9, s1
    ld      s2, (HB_NEXT - HB_HEADER)(t0)
    mv      a0, s1
    call    libp2p_heap_free
    mv      s1, s2
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_free_kept

/* ---------------------------------------------------------------- Timers */

/*
 * libp2p_timers(): ends TCP connections whose upgrade ran out of time, runs the
 * gossipsub heartbeat and score decay when due, and asks for a wakeup at
 * the next deadline.
 * s1 connection, s2 connections left, s3 now.
 */
LOCAL_FUNCTION libp2p_timers
    ENTER   0
    ld      s3, SC_NOW(s10)
    TABLE   s1, ST_CONN_OFF
    ld      s2, ST_CONN_COUNT(s9)
1:  beqz    s2, 3f
    ld      t0, C_FLAGS(s1)                 # asm-quic times QUIC handshakes
    andi    t0, t0, CF_QUIC
    bnez    t0, 2f
    lwu     t0, C_PHASE(s1)
    li      t1, PH_DIALING
    bltu    t0, t1, 2f
    li      t1, PH_OPEN
    bgeu    t0, t1, 2f
    ld      a0, C_DEADLINE(s1)
    bltu    s3, a0, 11f
    li      a1, LIBP2P_REASON_HANDSHAKE
    li      t1, PH_DIALING                  # no TCP connection yet: CONNECT
    bne     t0, t1, 12f
    li      a1, LIBP2P_REASON_CONNECT
12: mv      a0, s1
    call    libp2p_conn_close
    j       2f
11: call    libp2p_wake_at
2:  addi    s1, s1, C_SIZE
    addi    s2, s2, -1
    j       1b
3:  call    libp2p_gossip_timers
    LEAVE   0
END_FUNCTION libp2p_timers

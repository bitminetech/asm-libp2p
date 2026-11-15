/*
 * QUIC of the RISC-V core: the glue between libp2p and asm-quic. asm-quic does
 * QUIC v1 and TLS 1.3 with the libp2p certificate, and gives connections and
 * streams; multistream-select, identify and gossipsub run on those streams
 * as they run on yamux. Included by libp2p.s.
 *
 * The state holds the asm-quic state, a list of events for it and the list
 * of actions its last quic_step gave. Each step hands the actions on while
 * the action room lasts, writes events from the connections and streams,
 * and runs quic_step again until nothing is left to do or due.
 */

/* ---------------------------------------------------------------- Setup */

/*
 * libp2p_quic_config(config, dst): the asm-quic Config of the node: the host
 * key and limits of the config, and its QUIC fields; the seed is zero. The
 * stream queue of asm-quic is quic_window + LIBP2P_QUIC_WRITE: asm-quic
 * counts a chunk until all of it is acknowledged, and a chunk of ours is at
 * most LIBP2P_QUIC_WRITE bytes.
 * s1 config, s2 dst.
 */
LOCAL_FUNCTION libp2p_quic_config
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      a0, s2
    li      a1, QUIC_CFG_SIZE
    call    libp2p_zero
    li      t0, QUIC_CFG_SIZE
    sd      t0, QUIC_CFG_SIZE_FIELD(s2)
    li      t0, QUIC_VERSION
    sd      t0, QUIC_CFG_VERSION(s2)
    ld      t0, LIBP2P_CFG_KEY_TYPE(s1)
    sd      t0, QUIC_CFG_KEY_TYPE(s2)
    addi    a0, s2, QUIC_CFG_KEY
    addi    a1, s1, LIBP2P_CFG_PRIVATE_KEY
    li      a2, 32
    call    libp2p_copy
    ld      t0, LIBP2P_CFG_MAX_CONNECTIONS(s1)
    sd      t0, QUIC_CFG_CONNS(s2)
    ld      t0, LIBP2P_CFG_MAX_STREAMS(s1)
    sd      t0, QUIC_CFG_STREAMS(s2)
    ld      t0, LIBP2P_CFG_QUIC_HEAP(s1)
    sd      t0, QUIC_CFG_HEAP(s2)
    ld      t0, LIBP2P_CFG_QUIC_IDLE_MS(s1)
    sd      t0, QUIC_CFG_IDLE(s2)
    ld      t0, LIBP2P_CFG_HANDSHAKE_MS(s1)
    sd      t0, QUIC_CFG_HANDSHAKE(s2)
    ld      t0, LIBP2P_CFG_QUIC_KEEP_ALIVE_MS(s1)
    sd      t0, QUIC_CFG_KEEP_ALIVE(s2)
    ld      t0, LIBP2P_CFG_QUIC_MAX_DATA(s1)
    sd      t0, QUIC_CFG_MAX_DATA(s2)
    ld      t0, LIBP2P_CFG_QUIC_STREAM_DATA(s1)
    sd      t0, QUIC_CFG_STREAM_DATA(s2)
    ld      t0, LIBP2P_CFG_QUIC_MAX_STREAMS(s1)
    sd      t0, QUIC_CFG_MAX_STREAMS(s2)
    ld      t0, LIBP2P_CFG_QUIC_WINDOW(s1)  # asm-quic keeps a chunk until all of it is acknowledged
    li      t1, LIBP2P_QUIC_WRITE
    add     t0, t0, t1
    sd      t0, QUIC_CFG_STREAM_QUEUE(s2)
    ld      t0, LIBP2P_CFG_QUIC(s1)
    srli    t0, t0, 1                       # LIBP2P_QUIC_ACCEPT: QUIC_CFG_ACCEPT
    andi    t0, t0, 1
    sd      t0, QUIC_CFG_FLAGS(s2)
    ld      t0, LIBP2P_CFG_QUIC_SENT(s1)
    sd      t0, QUIC_CFG_SENT(s2)
    LEAVE   0
END_FUNCTION libp2p_quic_config

/*
 * libp2p_peer_id_proto(dst, proto, n) -> the length of the peer ID of a
 * PublicKey protobuf of n bytes (at most 128): the identity multihash when n
 * is at most 42, else the SHA-256 multihash.
 * s1 dst, s2 proto, s3 n. A ByteList of 24 + 128 bytes at sp + FL.
 */
LOCAL_FUNCTION libp2p_peer_id_proto
    ENTER   0, 160
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      t0, 42
    bltu    t0, s3, 1f
    sb      zero, 0(s1)
    sb      s3, 1(s1)
    addi    a0, s1, 2
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    addi    a0, s3, 2
    j       9f
1:  li      t0, 152
    sd      t0, (FL + LIBP2P_BL_SIZE)(sp)
    li      t0, LIBP2P_BL_FIXED
    sd      t0, (FL + LIBP2P_BL_OFFSET)(sp)
    sd      s3, (FL + LIBP2P_BL_COUNT)(sp)
    addi    a0, sp, (FL + LIBP2P_BL_FIXED)
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    li      t0, 0x12
    sb      t0, 0(s1)
    li      t0, 0x20
    sb      t0, 1(s1)
    addi    a0, sp, FL
    addi    a1, s1, 2
    CALL_GLOBAL crypto_sha256
    li      a0, 34
9:  LEAVE   0, 160
END_FUNCTION libp2p_peer_id_proto

/* ---------------------------------------------------------------- Events for asm-quic */

/* libp2p_qroom() -> the bytes left in the event list for asm-quic. A leaf. */
LOCAL_FUNCTION libp2p_qroom
    UNWIND_END_PROLOGUE
    ld      a1, ST_QEV_OFF(s9)
    add     a1, s9, a1
    ld      a0, LIBP2P_BL_SIZE(a1)
    addi    a0, a0, -LIBP2P_BL_FIXED
    ld      a2, LIBP2P_BL_COUNT(a1)
    sub     a0, a0, a2
    ret
END_FUNCTION libp2p_qroom

/*
 * libp2p_qevent(kind, size) -> a new event at the end of the event list for
 * asm-quic, with its size and kind set and its last word zero; 0 when the
 * list has no room. size is a multiple of 8, at least 24. A leaf.
 */
LOCAL_FUNCTION libp2p_qevent
    UNWIND_END_PROLOGUE
    ld      a2, ST_QEV_OFF(s9)
    add     a2, s9, a2
    ld      a3, LIBP2P_BL_SIZE(a2)
    addi    a3, a3, -LIBP2P_BL_FIXED
    ld      a4, LIBP2P_BL_COUNT(a2)
    sub     a3, a3, a4
    bltu    a3, a1, 8f
    addi    a5, a2, LIBP2P_BL_FIXED
    add     a5, a5, a4
    add     a4, a4, a1
    sd      a4, LIBP2P_BL_COUNT(a2)
    add     a6, a5, a1
    sd      zero, -8(a6)
    sd      a1, QUIC_EV_SIZE(a5)
    sd      a0, QUIC_EV_KIND(a5)
    mv      a0, a5
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_qevent

/* libp2p_qclose(conn) -> the event, or 0: an asm-quic CLOSE of a connection handle, code 0. */
LOCAL_FUNCTION libp2p_qclose
    ENTER   0
    mv      s1, a0
    li      a0, QUIC_EVENT_CLOSE
    li      a1, QUIC_EV_CLOSE_SIZE
    call    libp2p_qevent
    beqz    a0, 9f
    sd      s1, QUIC_EV_CONN(a0)
    sd      zero, QUIC_EV_CODE(a0)
9:  LEAVE   0
END_FUNCTION libp2p_qclose

/* libp2p_qreset(stream) -> the event, or 0: an asm-quic STREAM_RESET of a stream handle, code 0. */
LOCAL_FUNCTION libp2p_qreset
    ENTER   0
    mv      s1, a0
    li      a0, QUIC_EVENT_STREAM_RESET
    li      a1, QUIC_EV_RESET_SIZE
    call    libp2p_qevent
    beqz    a0, 9f
    sd      s1, QUIC_EV_STREAM(a0)
    sd      zero, QUIC_EV_CODE(a0)
9:  LEAVE   0
END_FUNCTION libp2p_qreset

/*
 * libp2p_qev_drop(n): the first n events of the list for asm-quic go; the
 * rest moves to the front.
 * s1 list, s2 first event, s3 bytes dropped, s4 bytes in the list.
 */
LOCAL_FUNCTION libp2p_qev_drop
    ENTER   0
    ld      s1, ST_QEV_OFF(s9)
    add     s1, s9, s1
    addi    s2, s1, LIBP2P_BL_FIXED
    li      s3, 0
    ld      s4, LIBP2P_BL_COUNT(s1)
1:  beqz    a0, 2f
    bgeu    s3, s4, 2f
    add     t0, s2, s3
    ld      t0, 0(t0)
    add     s3, s3, t0
    addi    a0, a0, -1
    j       1b
2:  sub     a2, s4, s3
    sd      a2, LIBP2P_BL_COUNT(s1)
    mv      a0, s2
    add     a1, s2, s3
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_qev_drop

/*
 * libp2p_on_datagram(event): a UDP datagram: it joins the event list for
 * asm-quic as a DATAGRAM event of the same fields.
 */
LOCAL_FUNCTION libp2p_on_datagram
    ENTER   0
    mv      s1, a0
    li      a0, QUIC_EVENT_DATAGRAM
    ld      a1, LIBP2P_EV_SIZE(s1)
    call    libp2p_qevent
    beqz    a0, 9f
    addi    a0, a0, 16
    addi    a1, s1, 16
    ld      a2, LIBP2P_EV_SIZE(s1)
    addi    a2, a2, -16
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_on_datagram

/* ---------------------------------------------------------------- Handles of asm-quic */

/* libp2p_qconn_of(handle) -> the QUIC connection of an asm-quic connection handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qconn_of
    UNWIND_END_PROLOGUE
    slli    a1, a0, 32
    srli    a1, a1, 32
    ld      a2, ST_CONN_COUNT(s9)
    bgeu    a1, a2, 8f
    ld      a3, ST_QCMAP_OFF(s9)
    add     a3, s9, a3
    slli    a4, a1, 2
    add     a3, a3, a4
    lwu     a4, 0(a3)
    bgeu    a4, a2, 8f
    ld      a5, ST_CONN_OFF(s9)
    add     a5, s9, a5
    li      a6, C_SIZE
    mul     a6, a4, a6
    add     a5, a5, a6
    lwu     a6, C_PHASE(a5)
    beqz    a6, 8f
    ld      a6, C_FLAGS(a5)
    andi    a6, a6, CF_QUIC
    beqz    a6, 8f
    ld      a6, C_QUIC(a5)
    bne     a6, a0, 8f
    mv      a0, a5
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_qconn_of

/* libp2p_qconn_bind(handle, conn): the connection gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qconn_bind
    UNWIND_END_PROLOGUE
    sd      a0, C_QUIC(a1)
    ld      a2, ST_CONN_OFF(s9)
    add     a2, s9, a2
    sub     a2, a1, a2
    li      a3, C_SIZE
    divu    a2, a2, a3
    slli    a4, a0, 32
    srli    a4, a4, 32
    ld      a5, ST_CONN_COUNT(s9)
    bgeu    a4, a5, 9f
    ld      a3, ST_QCMAP_OFF(s9)
    add     a3, s9, a3
    slli    a4, a4, 2
    add     a3, a3, a4
    sw      a2, 0(a3)
9:  ret
END_FUNCTION libp2p_qconn_bind

/* libp2p_qstream_of(handle) -> the stream of an asm-quic stream handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qstream_of
    UNWIND_END_PROLOGUE
    slli    a1, a0, 32
    srli    a1, a1, 32
    ld      a2, ST_STREAM_COUNT(s9)
    bgeu    a1, a2, 8f
    ld      a3, ST_QMAP_OFF(s9)
    add     a3, s9, a3
    slli    a4, a1, 2
    add     a3, a3, a4
    lwu     a4, 0(a3)
    bgeu    a4, a2, 8f
    ld      a5, ST_STREAM_OFF(s9)
    add     a5, s9, a5
    li      a6, S_SIZE
    mul     a6, a4, a6
    add     a5, a5, a6
    lwu     a6, S_USED(a5)
    beqz    a6, 8f
    ld      a6, S_ID(a5)
    bne     a6, a0, 8f
    mv      a0, a5
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_qstream_of

/* libp2p_qstream_bind(handle, stream): the stream gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qstream_bind
    UNWIND_END_PROLOGUE
    sd      a0, S_ID(a1)
    ld      a2, ST_STREAM_OFF(s9)
    add     a2, s9, a2
    sub     a2, a1, a2
    li      a3, S_SIZE
    divu    a2, a2, a3
    slli    a4, a0, 32
    srli    a4, a4, 32
    ld      a5, ST_STREAM_COUNT(s9)
    bgeu    a4, a5, 9f
    ld      a3, ST_QMAP_OFF(s9)
    add     a3, s9, a3
    slli    a4, a4, 2
    add     a3, a3, a4
    sw      a2, 0(a3)
9:  ret
END_FUNCTION libp2p_qstream_bind

/* libp2p_qreason(reason) -> the libp2p reason of a QUIC_ERR_* reason of DIAL_FAILED. A leaf. */
LOCAL_FUNCTION libp2p_qreason
    UNWIND_END_PROLOGUE
    mv      a1, a0
    li      a0, LIBP2P_REASON_PEER_ID
    li      a2, QUIC_ERR_PEER_ID
    beq     a1, a2, 9f
    li      a0, LIBP2P_REASON_LIMIT
    li      a2, QUIC_ERR_LIMIT
    beq     a1, a2, 9f
    li      a0, LIBP2P_REASON_CONNECT
    li      a2, QUIC_ERR_HANDSHAKE_TIMEOUT
    beq     a1, a2, 9f
    li      a0, LIBP2P_REASON_HANDSHAKE
9:  ret
END_FUNCTION libp2p_qreason

/* ---------------------------------------------------------------- Actions of asm-quic */

/*
 * libp2p_quic_need(action) -> the action bytes handling an asm-quic action
 * may need: its size for SEND, 64 + 16 for each byte of STREAM_DATA, 16384
 * for CONNECTED, DIAL_FAILED and CLOSED, 0 for WAKEUP, else 1024. A leaf.
 */
LOCAL_FUNCTION libp2p_quic_need
    UNWIND_END_PROLOGUE
    ld      a1, QUIC_ACT_KIND(a0)
    li      a2, QUIC_ACTION_SEND
    bne     a1, a2, 1f
    ld      a0, QUIC_ACT_SIZE(a0)
    ret
1:  li      a2, QUIC_ACTION_STREAM_DATA
    bne     a1, a2, 2f
    ld      a2, QUIC_ACT_S_COUNT(a0)
    slli    a2, a2, 4
    addi    a0, a2, 64
    ret
2:  li      a2, QUIC_ACTION_WAKEUP
    bne     a1, a2, 3f
    li      a0, 0
    ret
3:  li      a2, QUIC_ACTION_CONNECTED
    beq     a1, a2, 4f
    li      a2, QUIC_ACTION_DIAL_FAILED
    beq     a1, a2, 4f
    li      a2, QUIC_ACTION_CLOSED
    beq     a1, a2, 4f
    li      a0, 1024
    ret
4:  li      a0, 16384
    ret
END_FUNCTION libp2p_quic_need

/*
 * libp2p_quic_actions() -> 1 when every action of the last quic_step is
 * handled, 0 when the action room ran out first (the next step is then due
 * now, and starts with the rest).
 * s1 the action list, s2 bytes handled, s3 action, s4 room it needs.
 */
LOCAL_FUNCTION libp2p_quic_actions
    ENTER   0
    ld      s1, ST_QACT_OFF(s9)
    add     s1, s9, s1
    ld      s2, ST_QACT_DONE(s9)
1:  ld      t0, LIBP2P_BL_COUNT(s1)
    bgeu    s2, t0, 7f
    ld      t0, LIBP2P_BL_OFFSET(s1)
    add     s3, s1, t0
    add     s3, s3, s2
    mv      a0, s3
    call    libp2p_quic_need
    mv      s4, a0
    call    libp2p_room
    bltu    a0, s4, 8f
    mv      a0, s3
    call    libp2p_quic_action
    ld      t0, QUIC_ACT_SIZE(s3)
    add     s2, s2, t0
    sd      s2, ST_QACT_DONE(s9)
    j       1b
7:  sd      zero, LIBP2P_BL_COUNT(s1)
    sd      zero, ST_QACT_DONE(s9)
    li      a0, 1
    j       9f
8:  ld      a0, SC_NOW(s10)
    call    libp2p_wake_at
    li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_quic_actions

/* libp2p_quic_action(action): one action of asm-quic: a direct call for each kind. */
LOCAL_FUNCTION libp2p_quic_action
    ENTER   0
    ld      t0, QUIC_ACT_KIND(a0)
    li      t1, QUIC_ACTION_SEND
    bne     t0, t1, 1f
    call    libp2p_q_send
    j       9f
1:  li      t1, QUIC_ACTION_WAKEUP
    bne     t0, t1, 2f
    ld      t2, QUIC_ACT_TIME(a0)
    sd      t2, ST_QUIC_WAKE(s9)
    j       9f
2:  li      t1, QUIC_ACTION_CONNECTED
    bne     t0, t1, 3f
    call    libp2p_q_connected
    j       9f
3:  li      t1, QUIC_ACTION_DIAL_FAILED
    bne     t0, t1, 4f
    call    libp2p_q_dial_failed
    j       9f
4:  li      t1, QUIC_ACTION_CLOSED
    bne     t0, t1, 5f
    call    libp2p_q_closed
    j       9f
5:  li      t1, QUIC_ACTION_STREAM_OPENED
    bne     t0, t1, 6f
    call    libp2p_q_opened
    j       9f
6:  li      t1, QUIC_ACTION_STREAM_DATA
    bne     t0, t1, 7f
    call    libp2p_q_data
    j       9f
7:  li      t1, QUIC_ACTION_STREAM_FIN
    bne     t0, t1, 8f
    call    libp2p_q_fin
    j       9f
8:  li      t1, QUIC_ACTION_STREAM_RESET
    bne     t0, t1, 10f
    call    libp2p_q_reset
    j       9f
10: li      t1, QUIC_ACTION_STREAM_ACKED
    bne     t0, t1, 9f
    call    libp2p_q_acked
9:  LEAVE   0
END_FUNCTION libp2p_quic_action

/* libp2p_q_send(action): an asm-quic SEND becomes a SEND_DATAGRAM action of the same fields. */
LOCAL_FUNCTION libp2p_q_send
    ENTER   0
    mv      s1, a0
    li      a0, LIBP2P_ACTION_SEND_DATAGRAM
    ld      a1, QUIC_ACT_SIZE(s1)
    call    libp2p_action
    beqz    a0, 9f
    addi    a0, a0, 16
    addi    a1, s1, 16
    ld      a2, QUIC_ACT_SIZE(s1)
    addi    a2, a2, -16
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_q_send

/*
 * libp2p_q_connected(action): a QUIC connection is up: our dial (the tag is
 * the connection handle) or a peer's (tag 0, a new slot). The peer ID comes
 * from the host key; then the connection is open and bound to its peer. A
 * connection nobody waits for, or with no slot, is closed.
 * s1 action, s2 conn.
 */
LOCAL_FUNCTION libp2p_q_connected
    ENTER   0
    mv      s1, a0
    ld      a0, QUIC_ACT_TAG(s1)
    beqz    a0, 1f
    call    libp2p_conn
    mv      s2, a0
    beqz    s2, 8f
    ld      t0, C_FLAGS(s2)
    andi    t0, t0, CF_QUIC
    beqz    t0, 8f
    lwu     t0, C_PHASE(s2)
    li      t1, PH_DIALING
    bne     t0, t1, 8f
    j       2f
1:  li      a0, 2                           # a peer's: QUIC, inbound
    call    libp2p_conn_new
    mv      s2, a0
    beqz    s2, 8f
    addi    a0, s2, C_ADDR
    addi    a1, s1, QUIC_ACT_C_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    ld      t0, QUIC_ACT_C_SOCKET(s1)
    sd      t0, C_QSOCK(s2)
2:  ld      a0, QUIC_ACT_CONN(s1)
    mv      a1, s2
    call    libp2p_qconn_bind
    addi    a0, s2, C_RID
    addi    a1, s1, QUIC_ACT_KEY
    ld      a2, QUIC_ACT_KEY_LEN(s1)
    call    libp2p_peer_id_proto
    sd      a0, C_RID_LEN(s2)
    mv      a0, s2
    call    libp2p_conn_opened
    j       9f
8:  ld      a0, QUIC_ACT_CONN(s1)
    call    libp2p_qclose
9:  LEAVE   0
END_FUNCTION libp2p_q_connected

/* libp2p_q_dial_failed(action): our QUIC dial failed: DIAL_FAILED with its reason, and the slot is free. */
LOCAL_FUNCTION libp2p_q_dial_failed
    ENTER   0
    mv      s1, a0
    ld      a0, QUIC_ACT_TAG(s1)
    call    libp2p_conn
    beqz    a0, 9f
    mv      s2, a0
    ld      t0, C_FLAGS(s2)
    andi    t0, t0, CF_QUIC
    beqz    t0, 9f
    lwu     t0, C_PHASE(s2)
    li      t1, PH_DIALING
    bne     t0, t1, 9f
    ld      a0, QUIC_ACT_REASON(s1)
    call    libp2p_qreason
    mv      a1, a0
    mv      a0, s2
    call    libp2p_conn_teardown
    mv      a0, s2
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_dial_failed

/* libp2p_q_closed(action): a QUIC connection is over: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_q_closed
    ENTER   0
    ld      a0, QUIC_ACT_CONN(a0)
    call    libp2p_qconn_of
    beqz    a0, 9f
    mv      s1, a0
    lwu     t0, C_PHASE(s1)
    li      t1, PH_CLOSING
    beq     t0, t1, 1f
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_teardown
1:  mv      a0, s1
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_closed

/*
 * libp2p_q_opened(action): an asm-quic stream is open. Ours (the tag is the
 * stream handle) gets its asm-quic handle, or fails with LIMIT when asm-quic
 * had none; a peer's (tag 0) gets a new stream slot. A stream nobody waits
 * for, or with no slot, is reset.
 * s1 action, s2 stream, s3 the asm-quic stream.
 */
LOCAL_FUNCTION libp2p_q_opened
    ENTER   0
    mv      s1, a0
    ld      s3, QUIC_ACT_STREAM(s1)
    ld      a0, QUIC_ACT_S_TAG(s1)
    beqz    a0, 1f
    call    libp2p_stream
    mv      s2, a0
    beqz    s2, 7f
    ld      t0, S_ID(s2)
    bnez    t0, 7f
    call    libp2p_stream_conn
    ld      t0, C_FLAGS(a0)
    andi    t0, t0, CF_QUIC
    beqz    t0, 7f
    ld      t0, C_QUIC(a0)
    ld      t1, QUIC_ACT_S_CONN(s1)
    bne     t0, t1, 7f
    beqz    s3, 6f
    mv      a0, s3
    mv      a1, s2
    call    libp2p_qstream_bind
    j       9f
1:  ld      a0, QUIC_ACT_S_CONN(s1)         # the peer's
    call    libp2p_qconn_of
    beqz    a0, 7f
    lwu     t0, C_PHASE(a0)
    li      t1, PH_OPEN
    bne     t0, t1, 7f
    beqz    s3, 9f
    mv      a1, s3
    li      a2, 0
    call    libp2p_stream_new
    beqz    a0, 7f
    mv      a1, a0
    mv      a0, s3
    call    libp2p_qstream_bind
    j       9f
6:  mv      a0, s2
    li      a1, LIBP2P_REASON_LIMIT
    call    libp2p_stream_abort
    j       9f
7:  beqz    s3, 9f
    mv      a0, s3
    call    libp2p_qreset
9:  LEAVE   0
END_FUNCTION libp2p_q_opened

/* libp2p_q_data(action): bytes of an asm-quic stream go to its stream. */
LOCAL_FUNCTION libp2p_q_data
    ENTER   0
    mv      s1, a0
    ld      a0, QUIC_ACT_STREAM(s1)
    call    libp2p_qstream_of
    beqz    a0, 9f
    addi    a1, s1, QUIC_ACT_S_DATA
    ld      a2, QUIC_ACT_S_COUNT(s1)
    call    libp2p_stream_data
9:  LEAVE   0
END_FUNCTION libp2p_q_data

/* libp2p_q_fin(action): the peer closed its side of an asm-quic stream. */
LOCAL_FUNCTION libp2p_q_fin
    ENTER   0
    ld      a0, QUIC_ACT_STREAM(a0)
    call    libp2p_qstream_of
    beqz    a0, 9f
    call    libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_q_fin

/* libp2p_q_reset(action): the peer reset an asm-quic stream: our side is reset too, and the stream ends. */
LOCAL_FUNCTION libp2p_q_reset
    ENTER   0
    ld      s1, QUIC_ACT_STREAM(a0)
    mv      a0, s1
    call    libp2p_qstream_of
    beqz    a0, 9f
    mv      s2, a0
    mv      a0, s1
    call    libp2p_qreset
    mv      a0, s2
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_stream_kill
9:  LEAVE   0
END_FUNCTION libp2p_q_reset

/* libp2p_q_acked(action): the peer has bytes of a stream: they leave the bytes in flight. */
LOCAL_FUNCTION libp2p_q_acked
    ENTER   0
    mv      s1, a0
    ld      a0, QUIC_ACT_STREAM(s1)
    call    libp2p_qstream_of
    beqz    a0, 9f
    ld      t0, S_QFLIGHT(a0)
    ld      t1, QUIC_ACT_S_COUNT(s1)
    bltu    t1, t0, 1f
    mv      t1, t0
1:  sub     t0, t0, t1
    sd      t0, S_QFLIGHT(a0)
9:  LEAVE   0
END_FUNCTION libp2p_q_acked

/* ---------------------------------------------------------------- From libp2p to asm-quic */

/*
 * libp2p_quic_emit(conn, stream) -> 0, or 1 when the event list is full:
 * the events of one stream of a QUIC connection: STREAM_RESET for RST (the
 * stream is then dead); OPEN_STREAM for SYN; once asm-quic gave its handle,
 * STREAM_WRITE of queued bytes while the bytes in flight stay within
 * quic_window, then STREAM_CLOSE after the queue. A stream closed both ways
 * is dead.
 * s1 conn, s2 stream, s3 event, s5 flags, s6 asm-quic stream, s7 bytes.
 */
LOCAL_FUNCTION libp2p_quic_emit
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    ld      s5, S_FLAGS(s2)
    ld      s6, S_ID(s2)
    andi    t0, s5, SF_RST
    beqz    t0, 1f
    beqz    s6, 11f                         # asm-quic never had it
    mv      a0, s6
    call    libp2p_qreset
    beqz    a0, 80f
11: ori     s5, s5, SF_DEAD
    j       90f
1:  andi    t0, s5, SF_SYN
    beqz    t0, 2f
    li      a0, QUIC_EVENT_OPEN_STREAM
    li      a1, QUIC_EV_OPEN_SIZE
    call    libp2p_qevent
    beqz    a0, 80f
    mv      s3, a0
    ld      t0, C_QUIC(s1)
    sd      t0, QUIC_EV_CONN(s3)
    mv      a0, s2
    call    libp2p_stream_handle
    sd      a0, QUIC_EV_OPEN_TAG(s3)
    andi    s5, s5, ~SF_SYN
2:  beqz    s6, 90f                         # waiting for STREAM_OPENED
3:  ld      t0, S_Q_HEAD(s2)                # data, within the window
    li      t1, NONE
    beq     t0, t1, 4f
    CFG     t1, LIBP2P_CFG_QUIC_WINDOW
    ld      t2, S_QFLIGHT(s2)
    bgeu    t2, t1, 90f
    sub     s7, t1, t2
    addi    t0, t0, -HB_HEADER
    add     t0, s9, t0
    ld      t1, CH_LEN(t0)
    ld      t2, CH_DONE(t0)
    sub     t1, t1, t2
    bgeu    t1, s7, 31f
    mv      s7, t1
31: li      t1, LIBP2P_QUIC_WRITE
    bgeu    t1, s7, 32f
    mv      s7, t1
32: call    libp2p_qroom
    li      t0, (QUIC_EV_WRITE_DATA + 8)
    bgeu    t0, a0, 80f
    sub     a0, a0, t0
    bgeu    a0, s7, 33f
    mv      s7, a0
33: addi    a1, s7, (QUIC_EV_WRITE_DATA + 7)
    andi    a1, a1, -8
    li      a0, QUIC_EVENT_STREAM_WRITE
    call    libp2p_qevent
    beqz    a0, 80f
    mv      s3, a0
    sd      s6, QUIC_EV_STREAM(s3)
    sd      s7, QUIC_EV_WRITE_COUNT(s3)
    mv      a0, s2
    addi    a1, s3, QUIC_EV_WRITE_DATA
    mv      a2, s7
    call    libp2p_chunk_take
    ld      t0, S_QFLIGHT(s2)
    add     t0, t0, s7
    sd      t0, S_QFLIGHT(s2)
    j       3b
4:  andi    t0, s5, SF_FIN                  # FIN after the queue
    beqz    t0, 5f
    andi    t0, s5, SF_FIN_SENT
    bnez    t0, 5f
    li      a0, QUIC_EVENT_STREAM_CLOSE
    li      a1, QUIC_EV_STREAM_SIZE
    call    libp2p_qevent
    beqz    a0, 80f
    sd      s6, QUIC_EV_STREAM(a0)
    ori     s5, s5, SF_FIN_SENT
5:  andi    t0, s5, (SF_FIN_SENT | SF_REMOTE_FIN)
    li      t1, (SF_FIN_SENT | SF_REMOTE_FIN)
    bne     t0, t1, 90f
    ori     s5, s5, SF_DEAD
90: sd      s5, S_FLAGS(s2)
    li      a0, 0
    j       99f
80: sd      s5, S_FLAGS(s2)
    li      a0, 1
99: LEAVE   0
END_FUNCTION libp2p_quic_emit

/*
 * libp2p_quic_gather() -> 0, or 1 when the event list is full: the events
 * of each QUIC connection for asm-quic: DIAL for a new dial, CLOSE for a
 * connection that ends, then the events of each stream of an open one;
 * dead streams are freed.
 * s1 conn, s2 connections left, s3 stream index, s4 stream, s5 result, s6 event.
 */
LOCAL_FUNCTION libp2p_quic_gather
    ENTER   0
    TABLE   s1, ST_CONN_OFF
    ld      s2, ST_CONN_COUNT(s9)
1:  beqz    s2, 8f
    lwu     t0, C_PHASE(s1)
    beqz    t0, 5f
    ld      t0, C_FLAGS(s1)
    andi    t1, t0, CF_QUIC
    beqz    t1, 5f
    li      t1, CF_QDIAL
    and     t1, t0, t1
    beqz    t1, 2f
    li      a0, QUIC_EVENT_DIAL
    li      a1, QUIC_EV_DIAL_SIZE
    call    libp2p_qevent
    beqz    a0, 7f
    mv      s6, a0
    mv      a0, s1
    call    libp2p_conn_handle
    sd      a0, QUIC_EV_TAG(s6)
    ld      t0, C_QSOCK(s1)
    sd      t0, QUIC_EV_DIAL_SOCKET(s6)
    addi    a0, s6, QUIC_EV_DIAL_ADDR
    addi    a1, s1, C_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    addi    a0, s6, QUIC_EV_PEER
    li      a1, QUIC_PEER_MAX
    call    libp2p_zero
    ld      a2, C_EXP_ID_LEN(s1)
    sd      a2, QUIC_EV_PEER_LEN(s6)
    addi    a0, s6, QUIC_EV_PEER
    addi    a1, s1, C_EXP_ID
    call    libp2p_copy
    ld      t0, C_FLAGS(s1)
    li      t1, ~CF_QDIAL
    and     t0, t0, t1
    sd      t0, C_FLAGS(s1)
2:  ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_NEED_CLOSE
    beqz    t0, 3f
    ld      a0, C_QUIC(s1)
    beqz    a0, 3f
    call    libp2p_qclose
    beqz    a0, 7f
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, ~CF_NEED_CLOSE
    sd      t0, C_FLAGS(s1)
3:  lwu     t0, C_PHASE(s1)
    li      t1, PH_OPEN
    bne     t0, t1, 5f
    ld      s3, C_STREAM_HEAD(s1)
4:  li      t0, NONE
    beq     s3, t0, 5f
    mv      a0, s3
    call    libp2p_stream_at
    mv      s4, a0
    ld      s3, S_NEXT(s4)
    mv      a0, s1
    mv      a1, s4
    call    libp2p_quic_emit
    mv      s5, a0
    ld      t0, S_FLAGS(s4)
    andi    t0, t0, SF_DEAD
    beqz    t0, 41f
    mv      a0, s4
    call    libp2p_stream_free
41: bnez    s5, 7f
    j       4b
5:  li      t0, C_SIZE
    add     s1, s1, t0
    addi    s2, s2, -1
    j       1b
7:  li      a0, 1
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_quic_gather

/*
 * libp2p_quic_pump(): runs asm-quic for the step. Each round hands on the
 * actions of the last quic_step, writes the events of the connections and
 * streams, and runs quic_step when it has events or a deadline is due; at
 * most 16 rounds. Then the next step is due at the deadline of asm-quic,
 * rounded up to a millisecond, or now while events or actions wait.
 * s1 rounds left, s2 the event list.
 */
LOCAL_FUNCTION libp2p_quic_pump
    ENTER   0
    ld      s2, ST_QEV_OFF(s9)
    add     s2, s9, s2
    li      s1, 16
1:  call    libp2p_quic_actions
    beqz    a0, 9f                          # the action room ran out: the rest waits
    call    libp2p_quic_gather
    ld      t0, LIBP2P_BL_COUNT(s2)
    bnez    t0, 2f
    LDSC    t0, (SC_QTICK + QUIC_TICK_NOW)
    ld      t1, ST_QUIC_WAKE(s9)
    bltu    t0, t1, 7f                      # nothing to do or due
2:  beqz    s1, 6f
    addi    s1, s1, -1
    ld      a0, ST_QUIC_OFF(s9)
    add     a0, s9, a0
    SCR     a1, SC_QTICK
    mv      a2, s2
    SCR     a3, SC_QSCRATCH
    li      t0, QUIC_SCRATCH_SIZE
    sd      t0, 0(a3)
    ld      a4, ST_QACT_OFF(s9)
    add     a4, s9, a4
    li      t0, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    sd      t0, LIBP2P_BL_SIZE(a4)
    SCR     a5, SC_QRESULT
    sd      zero, 0(a5)
    CALL_GLOBAL quic_step
    sd      zero, ST_QACT_DONE(s9)
    LDSC    a0, SC_QRESULT
    call    libp2p_qev_drop
    j       1b
6:  ld      a0, SC_NOW(s10)                 # rounds used up
    call    libp2p_wake_at
7:  ld      t0, LIBP2P_BL_COUNT(s2)
    beqz    t0, 71f
    ld      a0, SC_NOW(s10)
    call    libp2p_wake_at
    j       9f
71: ld      t0, ST_QUIC_WAKE(s9)
    addi    t0, t0, 999
    li      t1, 1000
    divu    a0, t0, t1
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_quic_pump

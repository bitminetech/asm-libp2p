/*
 * QUIC of the ARM64 core: the glue between libp2p and asm-quic. asm-quic does
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
 * x19 config, x20 dst.
 */
LOCAL_FUNCTION libp2p_quic_config
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, x20
    mov     x1, #QUIC_CFG_SIZE
    bl      libp2p_zero
    mov     x9, #QUIC_CFG_SIZE
    str     x9, [x20, #QUIC_CFG_SIZE_FIELD]
    mov     x9, #QUIC_VERSION
    str     x9, [x20, #QUIC_CFG_VERSION]
    ldr     x9, [x19, #LIBP2P_CFG_KEY_TYPE]
    str     x9, [x20, #QUIC_CFG_KEY_TYPE]
    add     x0, x20, #QUIC_CFG_KEY
    add     x1, x19, #LIBP2P_CFG_PRIVATE_KEY
    mov     x2, #32
    bl      libp2p_copy
    ldr     x9, [x19, #LIBP2P_CFG_MAX_CONNECTIONS]
    str     x9, [x20, #QUIC_CFG_CONNS]
    ldr     x9, [x19, #LIBP2P_CFG_MAX_STREAMS]
    str     x9, [x20, #QUIC_CFG_STREAMS]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_HEAP]
    str     x9, [x20, #QUIC_CFG_HEAP]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_IDLE_MS]
    str     x9, [x20, #QUIC_CFG_IDLE]
    ldr     x9, [x19, #LIBP2P_CFG_HANDSHAKE_MS]
    str     x9, [x20, #QUIC_CFG_HANDSHAKE]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_KEEP_ALIVE_MS]
    str     x9, [x20, #QUIC_CFG_KEEP_ALIVE]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_MAX_DATA]
    str     x9, [x20, #QUIC_CFG_MAX_DATA]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_STREAM_DATA]
    str     x9, [x20, #QUIC_CFG_STREAM_DATA]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_MAX_STREAMS]
    str     x9, [x20, #QUIC_CFG_MAX_STREAMS]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_WINDOW]     /* asm-quic keeps a chunk until all of it is acknowledged */
    add     x9, x9, #LIBP2P_QUIC_WRITE
    str     x9, [x20, #QUIC_CFG_STREAM_QUEUE]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC]
    ubfx    x9, x9, #1, #1                  /* LIBP2P_QUIC_ACCEPT: QUIC_CFG_ACCEPT */
    str     x9, [x20, #QUIC_CFG_FLAGS]
    ldr     x9, [x19, #LIBP2P_CFG_QUIC_SENT]
    str     x9, [x20, #QUIC_CFG_SENT]
    LEAVE   0
END_FUNCTION libp2p_quic_config

/*
 * libp2p_peer_id_proto(dst, proto, n) -> the length of the peer ID of a
 * PublicKey protobuf of n bytes (at most 128): the identity multihash when n
 * is at most 42, else the SHA-256 multihash.
 * x19 dst, x20 proto, x21 n. A ByteList of 24 + 128 bytes at sp.
 */
LOCAL_FUNCTION libp2p_peer_id_proto
    ENTER   0, 160
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    cmp     x21, #42
    b.hi    1f
    strb    wzr, [x19]
    strb    w21, [x19, #1]
    add     x0, x19, #2
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    add     x0, x21, #2
    b       9f
1:  mov     x9, #152
    str     x9, [sp, #LIBP2P_BL_SIZE]
    mov     x9, #LIBP2P_BL_FIXED
    str     x9, [sp, #LIBP2P_BL_OFFSET]
    str     x21, [sp, #LIBP2P_BL_COUNT]
    add     x0, sp, #LIBP2P_BL_FIXED
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    mov     w9, #0x12
    strb    w9, [x19]
    mov     w9, #0x20
    strb    w9, [x19, #1]
    mov     x0, sp
    add     x1, x19, #2
    CALL_GLOBAL crypto_sha256
    mov     x0, #34
9:  LEAVE   0, 160
END_FUNCTION libp2p_peer_id_proto

/* ---------------------------------------------------------------- Events for asm-quic */

/* libp2p_qroom() -> the bytes left in the event list for asm-quic. A leaf. */
LOCAL_FUNCTION libp2p_qroom
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_QEV_OFF]
    add     x1, x27, x1
    ldr     x0, [x1, #LIBP2P_BL_SIZE]
    sub     x0, x0, #LIBP2P_BL_FIXED
    ldr     x2, [x1, #LIBP2P_BL_COUNT]
    sub     x0, x0, x2
    ret
END_FUNCTION libp2p_qroom

/*
 * libp2p_qevent(kind, size) -> a new event at the end of the event list for
 * asm-quic, with its size and kind set and its last word zero; 0 when the
 * list has no room. size is a multiple of 8, at least 24. A leaf.
 */
LOCAL_FUNCTION libp2p_qevent
    UNWIND_END_PROLOGUE
    ldr     x2, [x27, #ST_QEV_OFF]
    add     x2, x27, x2
    ldr     x3, [x2, #LIBP2P_BL_SIZE]
    sub     x3, x3, #LIBP2P_BL_FIXED
    ldr     x4, [x2, #LIBP2P_BL_COUNT]
    sub     x3, x3, x4
    cmp     x3, x1
    b.lo    8f
    add     x5, x2, #LIBP2P_BL_FIXED
    add     x5, x5, x4
    add     x4, x4, x1
    str     x4, [x2, #LIBP2P_BL_COUNT]
    add     x6, x5, x1
    stur    xzr, [x6, #-8]
    str     x1, [x5, #QUIC_EV_SIZE]
    str     x0, [x5, #QUIC_EV_KIND]
    mov     x0, x5
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_qevent

/* libp2p_qclose(conn) -> the event, or 0: an asm-quic CLOSE of a connection handle, code 0. */
LOCAL_FUNCTION libp2p_qclose
    ENTER   0
    mov     x19, x0
    mov     x0, #QUIC_EVENT_CLOSE
    mov     x1, #QUIC_EV_CLOSE_SIZE
    bl      libp2p_qevent
    cbz     x0, 9f
    str     x19, [x0, #QUIC_EV_CONN]
    str     xzr, [x0, #QUIC_EV_CODE]
9:  LEAVE   0
END_FUNCTION libp2p_qclose

/* libp2p_qreset(stream) -> the event, or 0: an asm-quic STREAM_RESET of a stream handle, code 0. */
LOCAL_FUNCTION libp2p_qreset
    ENTER   0
    mov     x19, x0
    mov     x0, #QUIC_EVENT_STREAM_RESET
    mov     x1, #QUIC_EV_RESET_SIZE
    bl      libp2p_qevent
    cbz     x0, 9f
    str     x19, [x0, #QUIC_EV_STREAM]
    str     xzr, [x0, #QUIC_EV_CODE]
9:  LEAVE   0
END_FUNCTION libp2p_qreset

/*
 * libp2p_qev_drop(n): the first n events of the list for asm-quic go; the
 * rest moves to the front.
 * x19 list, x20 first event, x21 bytes dropped, x22 bytes in the list.
 */
LOCAL_FUNCTION libp2p_qev_drop
    ENTER   0
    ldr     x19, [x27, #ST_QEV_OFF]
    add     x19, x27, x19
    add     x20, x19, #LIBP2P_BL_FIXED
    mov     x21, #0
    ldr     x22, [x19, #LIBP2P_BL_COUNT]
1:  cbz     x0, 2f
    cmp     x21, x22
    b.hs    2f
    ldr     x9, [x20, x21]
    add     x21, x21, x9
    sub     x0, x0, #1
    b       1b
2:  sub     x2, x22, x21
    str     x2, [x19, #LIBP2P_BL_COUNT]
    mov     x0, x20
    add     x1, x20, x21
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_qev_drop

/*
 * libp2p_on_datagram(event): a UDP datagram: it joins the event list for
 * asm-quic as a DATAGRAM event of the same fields.
 */
LOCAL_FUNCTION libp2p_on_datagram
    ENTER   0
    mov     x19, x0
    mov     x0, #QUIC_EVENT_DATAGRAM
    ldr     x1, [x19, #LIBP2P_EV_SIZE]
    bl      libp2p_qevent
    cbz     x0, 9f
    add     x0, x0, #16
    add     x1, x19, #16
    ldr     x2, [x19, #LIBP2P_EV_SIZE]
    sub     x2, x2, #16
    bl      libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_on_datagram

/* ---------------------------------------------------------------- Handles of asm-quic */

/* libp2p_qconn_of(handle) -> the QUIC connection of an asm-quic connection handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qconn_of
    UNWIND_END_PROLOGUE
    mov     w1, w0
    ldr     x2, [x27, #ST_CONN_COUNT]
    cmp     x1, x2
    b.hs    8f
    ldr     x3, [x27, #ST_QCMAP_OFF]
    add     x3, x27, x3
    ldr     w4, [x3, x1, lsl #2]
    cmp     x4, x2
    b.hs    8f
    ldr     x5, [x27, #ST_CONN_OFF]
    add     x5, x27, x5
    mov     x6, #C_SIZE
    madd    x5, x4, x6, x5
    ldr     w6, [x5, #C_PHASE]
    cbz     w6, 8f
    ldr     x6, [x5, #C_FLAGS]
    tst     x6, #CF_QUIC
    b.eq    8f
    ldr     x6, [x5, #C_QUIC]
    cmp     x6, x0
    b.ne    8f
    mov     x0, x5
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_qconn_of

/* libp2p_qconn_bind(handle, conn): the connection gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qconn_bind
    UNWIND_END_PROLOGUE
    str     x0, [x1, #C_QUIC]
    ldr     x2, [x27, #ST_CONN_OFF]
    add     x2, x27, x2
    sub     x2, x1, x2
    mov     x3, #C_SIZE
    udiv    x2, x2, x3
    mov     w4, w0
    ldr     x5, [x27, #ST_CONN_COUNT]
    cmp     x4, x5
    b.hs    9f
    ldr     x3, [x27, #ST_QCMAP_OFF]
    add     x3, x27, x3
    str     w2, [x3, x4, lsl #2]
9:  ret
END_FUNCTION libp2p_qconn_bind

/* libp2p_qstream_of(handle) -> the stream of an asm-quic stream handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qstream_of
    UNWIND_END_PROLOGUE
    mov     w1, w0
    ldr     x2, [x27, #ST_STREAM_COUNT]
    cmp     x1, x2
    b.hs    8f
    ldr     x3, [x27, #ST_QMAP_OFF]
    add     x3, x27, x3
    ldr     w4, [x3, x1, lsl #2]
    cmp     x4, x2
    b.hs    8f
    ldr     x5, [x27, #ST_STREAM_OFF]
    add     x5, x27, x5
    mov     x6, #S_SIZE
    madd    x5, x4, x6, x5
    ldr     w6, [x5, #S_USED]
    cbz     w6, 8f
    ldr     x6, [x5, #S_ID]
    cmp     x6, x0
    b.ne    8f
    mov     x0, x5
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_qstream_of

/* libp2p_qstream_bind(handle, stream): the stream gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qstream_bind
    UNWIND_END_PROLOGUE
    str     x0, [x1, #S_ID]
    ldr     x2, [x27, #ST_STREAM_OFF]
    add     x2, x27, x2
    sub     x2, x1, x2
    mov     x3, #S_SIZE
    udiv    x2, x2, x3
    mov     w4, w0
    ldr     x5, [x27, #ST_STREAM_COUNT]
    cmp     x4, x5
    b.hs    9f
    ldr     x3, [x27, #ST_QMAP_OFF]
    add     x3, x27, x3
    str     w2, [x3, x4, lsl #2]
9:  ret
END_FUNCTION libp2p_qstream_bind

/* libp2p_qreason(reason) -> the libp2p reason of a QUIC_ERR_* reason of DIAL_FAILED. A leaf. */
LOCAL_FUNCTION libp2p_qreason
    UNWIND_END_PROLOGUE
    mov     x1, x0
    mov     x0, #LIBP2P_REASON_PEER_ID
    cmp     x1, #QUIC_ERR_PEER_ID
    b.eq    9f
    mov     x0, #LIBP2P_REASON_LIMIT
    cmp     x1, #QUIC_ERR_LIMIT
    b.eq    9f
    mov     x0, #LIBP2P_REASON_CONNECT
    cmp     x1, #QUIC_ERR_HANDSHAKE_TIMEOUT
    b.eq    9f
    mov     x0, #LIBP2P_REASON_HANDSHAKE
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
    ldr     x1, [x0, #QUIC_ACT_KIND]
    cmp     x1, #QUIC_ACTION_SEND
    b.ne    1f
    ldr     x0, [x0, #QUIC_ACT_SIZE]
    ret
1:  cmp     x1, #QUIC_ACTION_STREAM_DATA
    b.ne    2f
    ldr     x2, [x0, #QUIC_ACT_S_COUNT]
    lsl     x2, x2, #4
    add     x0, x2, #64
    ret
2:  cmp     x1, #QUIC_ACTION_WAKEUP
    b.ne    3f
    mov     x0, #0
    ret
3:  cmp     x1, #QUIC_ACTION_CONNECTED
    b.eq    4f
    cmp     x1, #QUIC_ACTION_DIAL_FAILED
    b.eq    4f
    cmp     x1, #QUIC_ACTION_CLOSED
    b.eq    4f
    mov     x0, #1024
    ret
4:  mov     x0, #16384
    ret
END_FUNCTION libp2p_quic_need

/*
 * libp2p_quic_actions() -> 1 when every action of the last quic_step is
 * handled, 0 when the action room ran out first (the next step is then due
 * now, and starts with the rest).
 * x19 the action list, x20 bytes handled, x21 action, x22 room it needs.
 */
LOCAL_FUNCTION libp2p_quic_actions
    ENTER   0
    ldr     x19, [x27, #ST_QACT_OFF]
    add     x19, x27, x19
    ldr     x20, [x27, #ST_QACT_DONE]
1:  ldr     x9, [x19, #LIBP2P_BL_COUNT]
    cmp     x20, x9
    b.hs    7f
    ldr     x9, [x19, #LIBP2P_BL_OFFSET]
    add     x21, x19, x9
    add     x21, x21, x20
    mov     x0, x21
    bl      libp2p_quic_need
    mov     x22, x0
    bl      libp2p_room
    cmp     x0, x22
    b.lo    8f
    mov     x0, x21
    bl      libp2p_quic_action
    ldr     x9, [x21, #QUIC_ACT_SIZE]
    add     x20, x20, x9
    str     x20, [x27, #ST_QACT_DONE]
    b       1b
7:  str     xzr, [x19, #LIBP2P_BL_COUNT]
    str     xzr, [x27, #ST_QACT_DONE]
    mov     x0, #1
    b       9f
8:  ldr     x0, [x28, #SC_NOW]
    bl      libp2p_wake_at
    mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_quic_actions

/* libp2p_quic_action(action): one action of asm-quic: a direct call for each kind. */
LOCAL_FUNCTION libp2p_quic_action
    ENTER   0
    ldr     x9, [x0, #QUIC_ACT_KIND]
    cmp     x9, #QUIC_ACTION_SEND
    b.ne    1f
    bl      libp2p_q_send
    b       9f
1:  cmp     x9, #QUIC_ACTION_WAKEUP
    b.ne    2f
    ldr     x9, [x0, #QUIC_ACT_TIME]
    str     x9, [x27, #ST_QUIC_WAKE]
    b       9f
2:  cmp     x9, #QUIC_ACTION_CONNECTED
    b.ne    3f
    bl      libp2p_q_connected
    b       9f
3:  cmp     x9, #QUIC_ACTION_DIAL_FAILED
    b.ne    4f
    bl      libp2p_q_dial_failed
    b       9f
4:  cmp     x9, #QUIC_ACTION_CLOSED
    b.ne    5f
    bl      libp2p_q_closed
    b       9f
5:  cmp     x9, #QUIC_ACTION_STREAM_OPENED
    b.ne    6f
    bl      libp2p_q_opened
    b       9f
6:  cmp     x9, #QUIC_ACTION_STREAM_DATA
    b.ne    7f
    bl      libp2p_q_data
    b       9f
7:  cmp     x9, #QUIC_ACTION_STREAM_FIN
    b.ne    8f
    bl      libp2p_q_fin
    b       9f
8:  cmp     x9, #QUIC_ACTION_STREAM_RESET
    b.ne    10f
    bl      libp2p_q_reset
    b       9f
10: cmp     x9, #QUIC_ACTION_STREAM_ACKED
    b.ne    9f
    bl      libp2p_q_acked
9:  LEAVE   0
END_FUNCTION libp2p_quic_action

/* libp2p_q_send(action): an asm-quic SEND becomes a SEND_DATAGRAM action of the same fields. */
LOCAL_FUNCTION libp2p_q_send
    ENTER   0
    mov     x19, x0
    mov     x0, #LIBP2P_ACTION_SEND_DATAGRAM
    ldr     x1, [x19, #QUIC_ACT_SIZE]
    bl      libp2p_action
    cbz     x0, 9f
    add     x0, x0, #16
    add     x1, x19, #16
    ldr     x2, [x19, #QUIC_ACT_SIZE]
    sub     x2, x2, #16
    bl      libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_q_send

/*
 * libp2p_q_connected(action): a QUIC connection is up: our dial (the tag is
 * the connection handle) or a peer's (tag 0, a new slot). The peer ID comes
 * from the host key; then the connection is open and bound to its peer. A
 * connection nobody waits for, or with no slot, is closed.
 * x19 action, x20 conn.
 */
LOCAL_FUNCTION libp2p_q_connected
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #QUIC_ACT_TAG]
    cbz     x0, 1f
    bl      libp2p_conn
    mov     x20, x0
    cbz     x20, 8f
    ldr     x9, [x20, #C_FLAGS]
    tst     x9, #CF_QUIC
    b.eq    8f
    ldr     w9, [x20, #C_PHASE]
    cmp     w9, #PH_DIALING
    b.ne    8f
    b       2f
1:  mov     x0, #2                          /* a peer's: QUIC, inbound */
    bl      libp2p_conn_new
    mov     x20, x0
    cbz     x20, 8f
    add     x0, x20, #C_ADDR
    add     x1, x19, #QUIC_ACT_C_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    ldr     x9, [x19, #QUIC_ACT_C_SOCKET]
    str     x9, [x20, #C_QSOCK]
2:  ldr     x0, [x19, #QUIC_ACT_CONN]
    mov     x1, x20
    bl      libp2p_qconn_bind
    add     x0, x20, #C_RID
    add     x1, x19, #QUIC_ACT_KEY
    ldr     x2, [x19, #QUIC_ACT_KEY_LEN]
    bl      libp2p_peer_id_proto
    str     x0, [x20, #C_RID_LEN]
    mov     x0, x20
    bl      libp2p_conn_opened
    b       9f
8:  ldr     x0, [x19, #QUIC_ACT_CONN]
    bl      libp2p_qclose
9:  LEAVE   0
END_FUNCTION libp2p_q_connected

/* libp2p_q_dial_failed(action): our QUIC dial failed: DIAL_FAILED with its reason, and the slot is free. */
LOCAL_FUNCTION libp2p_q_dial_failed
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #QUIC_ACT_TAG]
    bl      libp2p_conn
    cbz     x0, 9f
    mov     x20, x0
    ldr     x9, [x20, #C_FLAGS]
    tst     x9, #CF_QUIC
    b.eq    9f
    ldr     w9, [x20, #C_PHASE]
    cmp     w9, #PH_DIALING
    b.ne    9f
    ldr     x0, [x19, #QUIC_ACT_REASON]
    bl      libp2p_qreason
    mov     x1, x0
    mov     x0, x20
    bl      libp2p_conn_teardown
    mov     x0, x20
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_dial_failed

/* libp2p_q_closed(action): a QUIC connection is over: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_q_closed
    ENTER   0
    ldr     x0, [x0, #QUIC_ACT_CONN]
    bl      libp2p_qconn_of
    cbz     x0, 9f
    mov     x19, x0
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_CLOSING
    b.eq    1f
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_teardown
1:  mov     x0, x19
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_closed

/*
 * libp2p_q_opened(action): an asm-quic stream is open. Ours (the tag is the
 * stream handle) gets its asm-quic handle, or fails with LIMIT when asm-quic
 * had none; a peer's (tag 0) gets a new stream slot. A stream nobody waits
 * for, or with no slot, is reset.
 * x19 action, x20 stream, x21 the asm-quic stream.
 */
LOCAL_FUNCTION libp2p_q_opened
    ENTER   0
    mov     x19, x0
    ldr     x21, [x19, #QUIC_ACT_STREAM]
    ldr     x0, [x19, #QUIC_ACT_S_TAG]
    cbz     x0, 1f
    bl      libp2p_stream
    mov     x20, x0
    cbz     x20, 7f
    ldr     x9, [x20, #S_ID]
    cbnz    x9, 7f
    bl      libp2p_stream_conn
    ldr     x9, [x0, #C_FLAGS]
    tst     x9, #CF_QUIC
    b.eq    7f
    ldr     x9, [x0, #C_QUIC]
    ldr     x10, [x19, #QUIC_ACT_S_CONN]
    cmp     x9, x10
    b.ne    7f
    cbz     x21, 6f
    mov     x0, x21
    mov     x1, x20
    bl      libp2p_qstream_bind
    b       9f
1:  ldr     x0, [x19, #QUIC_ACT_S_CONN]     /* the peer's */
    bl      libp2p_qconn_of
    cbz     x0, 7f
    ldr     w9, [x0, #C_PHASE]
    cmp     w9, #PH_OPEN
    b.ne    7f
    cbz     x21, 9f
    mov     x1, x21
    mov     x2, #0
    bl      libp2p_stream_new
    cbz     x0, 7f
    mov     x1, x0
    mov     x0, x21
    bl      libp2p_qstream_bind
    b       9f
6:  mov     x0, x20
    mov     x1, #LIBP2P_REASON_LIMIT
    bl      libp2p_stream_abort
    b       9f
7:  cbz     x21, 9f
    mov     x0, x21
    bl      libp2p_qreset
9:  LEAVE   0
END_FUNCTION libp2p_q_opened

/* libp2p_q_data(action): bytes of an asm-quic stream go to its stream. */
LOCAL_FUNCTION libp2p_q_data
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #QUIC_ACT_STREAM]
    bl      libp2p_qstream_of
    cbz     x0, 9f
    add     x1, x19, #QUIC_ACT_S_DATA
    ldr     x2, [x19, #QUIC_ACT_S_COUNT]
    bl      libp2p_stream_data
9:  LEAVE   0
END_FUNCTION libp2p_q_data

/* libp2p_q_fin(action): the peer closed its side of an asm-quic stream. */
LOCAL_FUNCTION libp2p_q_fin
    ENTER   0
    ldr     x0, [x0, #QUIC_ACT_STREAM]
    bl      libp2p_qstream_of
    cbz     x0, 9f
    bl      libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_q_fin

/* libp2p_q_reset(action): the peer reset an asm-quic stream: our side is reset too, and the stream ends. */
LOCAL_FUNCTION libp2p_q_reset
    ENTER   0
    ldr     x19, [x0, #QUIC_ACT_STREAM]
    mov     x0, x19
    bl      libp2p_qstream_of
    cbz     x0, 9f
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_qreset
    mov     x0, x20
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_stream_kill
9:  LEAVE   0
END_FUNCTION libp2p_q_reset

/* libp2p_q_acked(action): the peer has bytes of a stream: they leave the bytes in flight. */
LOCAL_FUNCTION libp2p_q_acked
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #QUIC_ACT_STREAM]
    bl      libp2p_qstream_of
    cbz     x0, 9f
    ldr     x9, [x0, #S_QFLIGHT]
    ldr     x10, [x19, #QUIC_ACT_S_COUNT]
    cmp     x10, x9
    csel    x10, x10, x9, lo
    sub     x9, x9, x10
    str     x9, [x0, #S_QFLIGHT]
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
 * x19 conn, x20 stream, x21 event, x23 flags, x24 asm-quic stream, x25 bytes.
 */
LOCAL_FUNCTION libp2p_quic_emit
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x23, [x20, #S_FLAGS]
    ldr     x24, [x20, #S_ID]
    tst     x23, #SF_RST
    b.eq    1f
    cbz     x24, 11f                        /* asm-quic never had it */
    mov     x0, x24
    bl      libp2p_qreset
    cbz     x0, 80f
11: orr     x23, x23, #SF_DEAD
    b       90f
1:  tst     x23, #SF_SYN
    b.eq    2f
    mov     x0, #QUIC_EVENT_OPEN_STREAM
    mov     x1, #QUIC_EV_OPEN_SIZE
    bl      libp2p_qevent
    cbz     x0, 80f
    mov     x21, x0
    ldr     x9, [x19, #C_QUIC]
    str     x9, [x21, #QUIC_EV_CONN]
    mov     x0, x20
    bl      libp2p_stream_handle
    str     x0, [x21, #QUIC_EV_OPEN_TAG]
    and     x23, x23, #~SF_SYN
2:  cbz     x24, 90f                        /* waiting for STREAM_OPENED */
3:  ldr     x9, [x20, #S_Q_HEAD]            /* data, within the window */
    cmn     x9, #1
    b.eq    4f
    CFG     x10, LIBP2P_CFG_QUIC_WINDOW
    ldr     x11, [x20, #S_QFLIGHT]
    subs    x25, x10, x11
    b.ls    90f
    sub     x9, x9, #HB_HEADER
    add     x9, x27, x9
    ldr     x10, [x9, #CH_LEN]
    ldr     x11, [x9, #CH_DONE]
    sub     x10, x10, x11
    cmp     x25, x10
    csel    x25, x25, x10, lo
    mov     x10, #LIBP2P_QUIC_WRITE
    cmp     x25, x10
    csel    x25, x25, x10, lo
    bl      libp2p_qroom
    cmp     x0, #(QUIC_EV_WRITE_DATA + 8)
    b.ls    80f
    sub     x0, x0, #(QUIC_EV_WRITE_DATA + 8)
    cmp     x25, x0
    csel    x25, x25, x0, lo
    add     x1, x25, #(QUIC_EV_WRITE_DATA + 7)
    and     x1, x1, #~7
    mov     x0, #QUIC_EVENT_STREAM_WRITE
    bl      libp2p_qevent
    cbz     x0, 80f
    mov     x21, x0
    str     x24, [x21, #QUIC_EV_STREAM]
    str     x25, [x21, #QUIC_EV_WRITE_COUNT]
    mov     x0, x20
    add     x1, x21, #QUIC_EV_WRITE_DATA
    mov     x2, x25
    bl      libp2p_chunk_take
    ldr     x9, [x20, #S_QFLIGHT]
    add     x9, x9, x25
    str     x9, [x20, #S_QFLIGHT]
    b       3b
4:  tst     x23, #SF_FIN                    /* FIN after the queue */
    b.eq    5f
    tst     x23, #SF_FIN_SENT
    b.ne    5f
    mov     x0, #QUIC_EVENT_STREAM_CLOSE
    mov     x1, #QUIC_EV_STREAM_SIZE
    bl      libp2p_qevent
    cbz     x0, 80f
    str     x24, [x0, #QUIC_EV_STREAM]
    orr     x23, x23, #SF_FIN_SENT
5:  mov     x10, #(SF_FIN_SENT | SF_REMOTE_FIN)
    and     x9, x23, x10
    cmp     x9, x10
    b.ne    90f
    orr     x23, x23, #SF_DEAD
90: str     x23, [x20, #S_FLAGS]
    mov     x0, #0
    b       99f
80: str     x23, [x20, #S_FLAGS]
    mov     x0, #1
99: LEAVE   0
END_FUNCTION libp2p_quic_emit

/*
 * libp2p_quic_gather() -> 0, or 1 when the event list is full: the events
 * of each QUIC connection for asm-quic: DIAL for a new dial, CLOSE for a
 * connection that ends, then the events of each stream of an open one;
 * dead streams are freed.
 * x19 conn, x20 connections left, x21 stream index, x22 stream, x23 result.
 */
LOCAL_FUNCTION libp2p_quic_gather
    ENTER   0
    TABLE   x19, ST_CONN_OFF
    ldr     x20, [x27, #ST_CONN_COUNT]
1:  cbz     x20, 8f
    ldr     w9, [x19, #C_PHASE]
    cbz     w9, 5f
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_QUIC
    b.eq    5f
    tst     x9, #CF_QDIAL
    b.eq    2f
    mov     x0, #QUIC_EVENT_DIAL
    mov     x1, #QUIC_EV_DIAL_SIZE
    bl      libp2p_qevent
    cbz     x0, 7f
    mov     x21, x0
    mov     x0, x19
    bl      libp2p_conn_handle
    str     x0, [x21, #QUIC_EV_TAG]
    ldr     x9, [x19, #C_QSOCK]
    str     x9, [x21, #QUIC_EV_DIAL_SOCKET]
    add     x0, x21, #QUIC_EV_DIAL_ADDR
    add     x1, x19, #C_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    add     x0, x21, #QUIC_EV_PEER
    mov     x1, #QUIC_PEER_MAX
    bl      libp2p_zero
    ldr     x2, [x19, #C_EXP_ID_LEN]
    str     x2, [x21, #QUIC_EV_PEER_LEN]
    add     x0, x21, #QUIC_EV_PEER
    add     x1, x19, #C_EXP_ID
    bl      libp2p_copy
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #~CF_QDIAL
    str     x9, [x19, #C_FLAGS]
2:  ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_NEED_CLOSE
    b.eq    3f
    ldr     x0, [x19, #C_QUIC]
    cbz     x0, 3f
    bl      libp2p_qclose
    cbz     x0, 7f
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #~CF_NEED_CLOSE
    str     x9, [x19, #C_FLAGS]
3:  ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_OPEN
    b.ne    5f
    ldr     x21, [x19, #C_STREAM_HEAD]
4:  cmn     x21, #1
    b.eq    5f
    mov     x0, x21
    bl      libp2p_stream_at
    mov     x22, x0
    ldr     x21, [x22, #S_NEXT]
    mov     x0, x19
    mov     x1, x22
    bl      libp2p_quic_emit
    mov     x23, x0
    ldr     x9, [x22, #S_FLAGS]
    tst     x9, #SF_DEAD
    b.eq    41f
    mov     x0, x22
    bl      libp2p_stream_free
41: cbnz    x23, 7f
    b       4b
5:  add     x19, x19, #C_SIZE
    sub     x20, x20, #1
    b       1b
7:  mov     x0, #1
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_quic_gather

/*
 * libp2p_quic_pump(): runs asm-quic for the step. Each round hands on the
 * actions of the last quic_step, writes the events of the connections and
 * streams, and runs quic_step when it has events or a deadline is due; at
 * most 16 rounds. Then the next step is due at the deadline of asm-quic,
 * rounded up to a millisecond, or now while events or actions wait.
 * x19 rounds left, x20 the event list.
 */
LOCAL_FUNCTION libp2p_quic_pump
    ENTER   0
    ldr     x20, [x27, #ST_QEV_OFF]
    add     x20, x27, x20
    mov     x19, #16
1:  bl      libp2p_quic_actions
    cbz     x0, 9f                          /* the action room ran out: the rest waits */
    bl      libp2p_quic_gather
    ldr     x9, [x20, #LIBP2P_BL_COUNT]
    cbnz    x9, 2f
    SCR     x9, (SC_QTICK + QUIC_TICK_NOW)
    ldr     x9, [x9]
    ldr     x10, [x27, #ST_QUIC_WAKE]
    cmp     x9, x10
    b.lo    7f                              /* nothing to do or due */
2:  cbz     x19, 6f
    sub     x19, x19, #1
    ldr     x0, [x27, #ST_QUIC_OFF]
    add     x0, x27, x0
    SCR     x1, SC_QTICK
    mov     x2, x20
    SCR     x3, SC_QSCRATCH
    MOV64   x9, QUIC_SCRATCH_SIZE
    str     x9, [x3]
    ldr     x4, [x27, #ST_QACT_OFF]
    add     x4, x27, x4
    MOV64   x9, (LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS)
    str     x9, [x4, #LIBP2P_BL_SIZE]
    SCR     x5, SC_QRESULT
    str     xzr, [x5]
    CALL_GLOBAL quic_step
    str     xzr, [x27, #ST_QACT_DONE]
    SCR     x9, SC_QRESULT
    ldr     x0, [x9]
    bl      libp2p_qev_drop
    b       1b
6:  ldr     x0, [x28, #SC_NOW]              /* rounds used up */
    bl      libp2p_wake_at
7:  ldr     x9, [x20, #LIBP2P_BL_COUNT]
    cbz     x9, 71f
    ldr     x0, [x28, #SC_NOW]
    bl      libp2p_wake_at
    b       9f
71: ldr     x9, [x27, #ST_QUIC_WAKE]
    add     x9, x9, #999
    mov     x10, #1000
    udiv    x0, x9, x10
    bl      libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_quic_pump

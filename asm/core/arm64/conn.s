/*
 * Connections of the ARM64 core: the shell events of a TCP connection,
 * multistream-select 1.0, the upgrade (multistream for /noise, Noise,
 * multistream for the muxer) and the binding of a connection to a peer.
 * Included by libp2p.s.
 */

/* ---------------------------------------------------------------- multistream-select 1.0 */

    .p2align 3
430:
    .ascii  "/multistream/1.0.0\n"
.set MS_HEADER_LEN, 19
431:
    .ascii  "na\n"
432:
    .ascii  "/noise\n"
433:
    .ascii  "/yamux/1.0.0\n"
434:
    .ascii  "/mplex/6.7.0\n"
435:
    .ascii  "/meshsub/1.1.0\n"
436:
    .ascii  "/ipfs/id/1.0.0\n"
437:
    .ascii  "/meshsub/1.2.0\n"
    .p2align 2

/* libp2p_ms_put(dst, str, n) -> dst after one multistream message: varint(n), then the n bytes (the newline included). */
LOCAL_FUNCTION libp2p_ms_put
    ENTER   0
    mov     x19, x1
    mov     x20, x2
    mov     x1, x20
    bl      libp2p_varint_put
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ms_put

/* libp2p_ms_put_proto(dst, bytes, n) -> dst after the message of a protocol ID: varint(n + 1), the bytes, a newline. */
LOCAL_FUNCTION libp2p_ms_put_proto
    ENTER   0
    mov     x19, x1
    mov     x20, x2
    add     x1, x20, #1
    bl      libp2p_varint_put
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    mov     w9, #10
    strb    w9, [x0], #1
    LEAVE   0
END_FUNCTION libp2p_ms_put_proto

/*
 * libp2p_ms_take(ms, cap, src, n) -> x0 the bytes taken from src, x1 the
 * result: 0 when more bytes are needed, 1 when one whole message is in the
 * buffer, 2 when the bytes are not a message that fits. ms holds the
 * negotiation state, the bytes held, the varint length of the message,
 * then cap bytes of buffer. The message (its newline last) is at buffer +
 * varint length. Bytes after the message stay in src.
 * x19 ms, x20 cap, x21 src, x22 n, x23 taken.
 */
.set MS_STATE, 0
.set MS_LEN, 8
.set MS_NEED, 16
.set MS_BUF, 24
LOCAL_FUNCTION libp2p_ms_take
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, #0
1:  cmp     x23, x22
    b.hs    7f
    ldr     x24, [x19, #MS_LEN]
    cmp     x24, x20
    b.hs    8f
    ldrb    w9, [x21, x23]
    add     x10, x19, #MS_BUF
    strb    w9, [x10, x24]
    add     x24, x24, #1
    str     x24, [x19, #MS_LEN]
    add     x23, x23, #1
    add     x0, x19, #MS_BUF
    add     x1, x0, x24
    bl      libp2p_varint_get
    cmn     x1, #1
    b.eq    8f
    cbz     x1, 1b
    cbz     x0, 8f
    sub     x9, x20, x1
    cmp     x0, x9
    b.hi    8f
    add     x9, x0, x1
    cmp     x24, x9
    b.lo    1b
    str     x1, [x19, #MS_NEED]
    add     x10, x19, #MS_BUF
    sub     x11, x24, #1
    ldrb    w12, [x10, x11]
    cmp     w12, #10
    b.ne    8f
    mov     x0, x23
    mov     x1, #1
    b       9f
7:  mov     x0, x23
    mov     x1, #0
    b       9f
8:  mov     x0, x23
    mov     x1, #2
9:  LEAVE   0
END_FUNCTION libp2p_ms_take

/* libp2p_ms_is(ms, str, n) -> 1 when the message in ms is the n bytes at str, else 0. */
LOCAL_FUNCTION libp2p_ms_is
    ENTER   0
    mov     x19, x1
    mov     x20, x2
    ldr     x9, [x0, #MS_NEED]
    ldr     x10, [x0, #MS_LEN]
    add     x11, x0, #MS_BUF
    add     x0, x11, x9
    sub     x1, x10, x9
    mov     x2, x19
    mov     x3, x20
    bl      libp2p_compare
    LEAVE   0
END_FUNCTION libp2p_ms_is

/* ---------------------------------------------------------------- Connection slots */

/*
 * libp2p_conn_new(outbound) -> a new connection slot with its receive buffer,
 * in phase PH_DIALING, or 0 when no slot or heap block is free.
 */
LOCAL_FUNCTION libp2p_conn_new
    ENTER   0
    mov     x19, x0
    mov     x0, #ST_CONN_OFF
    mov     x1, #ST_CONN_COUNT
    mov     x2, #C_SIZE
    bl      libp2p_alloc_slot
    cbz     x0, 9f
    mov     x20, x0
    MOV64   x0, LIBP2P_RX_SIZE
    bl      libp2p_heap_alloc
    cbnz    x0, 1f
    str     wzr, [x20, #C_PHASE]
    mov     x0, #0
    b       9f
1:  str     x0, [x20, #C_RX]
    mov     x9, #NONE
    str     x9, [x20, #C_PEER]
    str     x9, [x20, #C_STREAM_HEAD]
    str     x9, [x20, #C_MX_STREAM]
    str     x9, [x20, #C_CURSOR]
    mov     x9, #CF_OUTBOUND
    cmp     x19, #0
    csel    x9, x9, xzr, ne
    str     x9, [x20, #C_FLAGS]
    ldr     x9, [x28, #SC_NOW]
    CFG     x10, LIBP2P_CFG_HANDSHAKE_MS
    add     x9, x9, x10
    str     x9, [x20, #C_DEADLINE]
    mov     w9, #PH_DIALING
    str     w9, [x20, #C_PHASE]
    ldr     x9, [x27, #ST_CONN_LIVE]
    add     x9, x9, #1
    str     x9, [x27, #ST_CONN_LIVE]
    mov     x0, x20
9:  LEAVE   0
END_FUNCTION libp2p_conn_new

/* libp2p_conn_handle(conn) -> its handle. */
LOCAL_FUNCTION libp2p_conn_handle
    ENTER   0
    mov     x2, x0
    mov     x0, #ST_CONN_OFF
    mov     x1, #C_SIZE
    bl      libp2p_handle
    LEAVE   0
END_FUNCTION libp2p_conn_handle

/* libp2p_conn_free(conn): the slot becomes free. */
LOCAL_FUNCTION libp2p_conn_free
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #C_RX]
    bl      libp2p_heap_free
    str     xzr, [x19, #C_RX]
    str     wzr, [x19, #C_PHASE]
    ldr     x9, [x27, #ST_CONN_LIVE]
    sub     x9, x9, #1
    str     x9, [x27, #ST_CONN_LIVE]
    LEAVE   0
END_FUNCTION libp2p_conn_free

/* libp2p_conn_out(conn, str, n): queues one multistream message (str holds n bytes, the newline included). */
LOCAL_FUNCTION libp2p_conn_out
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x1, x21, #1
    bl      libp2p_noise_out
    cbz     x0, 9f
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_ms_put
9:  LEAVE   0
END_FUNCTION libp2p_conn_out

/*
 * libp2p_conn_teardown(conn, reason): ends everything above the socket: the
 * streams (the application hears of its own); then the peer
 * (PEER_DISCONNECTED) when this was its connection and no other is open,
 * else another connection of the peer takes over; or, for a dial not yet
 * reported, DIAL_FAILED; then the receive buffer.
 * x19 conn, x20 reason, x21 peer index, x22 peer.
 */
LOCAL_FUNCTION libp2p_conn_teardown
    ENTER   0
    mov     x19, x0
    mov     x20, x1
1:  ldr     x9, [x19, #C_STREAM_HEAD]        /* the streams */
    cmn     x9, #1
    b.eq    2f
    TABLE   x10, ST_STREAM_OFF
    mov     x11, #S_SIZE
    madd    x0, x9, x11, x10
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_stream_kill
    b       1b
2:  ldr     x21, [x19, #C_PEER]
    cmn     x21, #1
    b.eq    3f
    mov     x9, #NONE                       /* this connection no longer counts for the peer */
    str     x9, [x19, #C_PEER]
    TABLE   x10, ST_PEER_OFF
    mov     x11, #P_SIZE
    madd    x22, x21, x11, x10              /* the peer */
    TABLE   x10, ST_CONN_OFF
    sub     x9, x19, x10
    mov     x11, #C_SIZE
    udiv    x9, x9, x11
    ldr     x10, [x22, #P_CONN]
    cmp     x9, x10
    b.ne    4f                              /* a secondary connection: the peer stays */
    mov     x0, x21
    mov     x1, x19
    bl      libp2p_peer_other
    cbz     x0, 21f
    TABLE   x10, ST_CONN_OFF                /* another connection of the peer takes over */
    sub     x9, x0, x10
    mov     x11, #C_SIZE
    udiv    x9, x9, x11
    str     x9, [x22, #P_CONN]
    ldr     x9, [x0, #C_FLAGS]
    and     x9, x9, #CF_OUTBOUND
    ldr     x10, [x22, #P_FLAGS]
    and     x10, x10, #~PF_OUTBOUND
    orr     x10, x10, x9
    str     x10, [x22, #P_FLAGS]
    ldp     x9, x10, [x0, #(C_ADDR + LIBP2P_ADDR_IP)]
    stp     x9, x10, [x22, #P_IP]
    ldr     x9, [x0, #(C_ADDR + LIBP2P_ADDR_FAMILY)]
    str     x9, [x22, #P_IP_FAMILY]
    mov     x0, x22
    bl      libp2p_gossip_peer_up               /* our gossipsub stream again, on that connection */
    b       4f
21: mov     x0, x22
    bl      libp2p_peer_down
    b       4f
3:  ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_OUTBOUND
    b.eq    4f
    tst     x9, #CF_REPORTED
    b.ne    4f
    orr     x9, x9, #CF_REPORTED
    str     x9, [x19, #C_FLAGS]
    mov     x0, #LIBP2P_ACTION_DIAL_FAILED
    mov     x1, #LIBP2P_ACT_FAILED_SIZE
    bl      libp2p_action
    cbz     x0, 4f
    ldr     x9, [x19, #C_TAG]
    str     x9, [x0, #LIBP2P_ACT_TAG]
    str     x20, [x0, #LIBP2P_ACT_REASON]
4:  ldr     x0, [x19, #C_RX]
    bl      libp2p_heap_free
    str     xzr, [x19, #C_RX]
    str     xzr, [x19, #C_RX_LEN]
    str     xzr, [x19, #C_OUT_LEN]
    str     xzr, [x19, #C_OUT_RAW]
    LEAVE   0
END_FUNCTION libp2p_conn_teardown

/*
 * libp2p_conn_close(conn, reason): ends a live connection: teardown, then a
 * CLOSE action (kept as a flag for the drain when the list is full); the
 * slot waits in PH_CLOSING for the CLOSED event.
 */
LOCAL_FUNCTION libp2p_conn_close
    ENTER   0
    mov     x19, x0
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_DIALING
    b.lo    9f
    cmp     w9, #PH_CLOSING
    b.hs    9f
    bl      libp2p_conn_teardown
    mov     w9, #PH_CLOSING
    str     w9, [x19, #C_PHASE]
    mov     x0, x19
    bl      libp2p_conn_send_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_close

/* libp2p_conn_send_close(conn): a CLOSE action for the connection, or the flag that asks the drain for one. */
LOCAL_FUNCTION libp2p_conn_send_close
    ENTER   0
    mov     x19, x0
    mov     x0, #LIBP2P_ACTION_CLOSE
    mov     x1, #LIBP2P_ACT_CLOSE_SIZE
    bl      libp2p_action
    ldr     x9, [x19, #C_FLAGS]
    cbnz    x0, 1f
    orr     x9, x9, #CF_NEED_CLOSE
    str     x9, [x19, #C_FLAGS]
    b       9f
1:  and     x9, x9, #~CF_NEED_CLOSE
    str     x9, [x19, #C_FLAGS]
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_conn_handle
    str     x0, [x20, #LIBP2P_ACT_CONN]
9:  LEAVE   0
END_FUNCTION libp2p_conn_send_close

/* ---------------------------------------------------------------- Shell events */

/* libp2p_on_accepted(event): a new inbound connection: ADOPT it, or REFUSE it when no slot is free. */
LOCAL_FUNCTION libp2p_on_accepted
    ENTER   0
    mov     x19, x0
    mov     x0, #0
    bl      libp2p_conn_new
    cbnz    x0, 1f
    mov     x0, #LIBP2P_ACTION_REFUSE
    mov     x1, #LIBP2P_ACT_REFUSE_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    ldr     x9, [x19, #LIBP2P_EV_TOKEN]
    str     x9, [x0, #LIBP2P_ACT_TOKEN]
    b       9f
1:  mov     x20, x0
    add     x0, x20, #C_ADDR
    add     x1, x19, #LIBP2P_EV_ACCEPTED_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    mov     w9, #PH_SECURITY
    str     w9, [x20, #C_PHASE]
    mov     x0, #LIBP2P_ACTION_ADOPT
    mov     x1, #LIBP2P_ACT_ADOPT_SIZE
    bl      libp2p_action
    mov     x21, x0
    cbz     x21, 8f
    ldr     x9, [x19, #LIBP2P_EV_TOKEN]
    str     x9, [x21, #LIBP2P_ACT_TOKEN]
    mov     x0, x20
    bl      libp2p_conn_handle
    str     x0, [x21, #LIBP2P_ACT_ADOPT_CONN]
    b       9f
8:  mov     x0, x20                         /* no room: give the slot back */
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_accepted

/* libp2p_on_dial(event): the application asks for a connection: a DIAL action, or DIAL_FAILED when no slot is free. */
LOCAL_FUNCTION libp2p_on_dial
    ENTER   0
    mov     x19, x0
    mov     x0, #1
    bl      libp2p_conn_new
    cbnz    x0, 1f
    mov     x0, #LIBP2P_ACTION_DIAL_FAILED
    mov     x1, #LIBP2P_ACT_FAILED_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    ldr     x9, [x19, #LIBP2P_EV_TAG]
    str     x9, [x0, #LIBP2P_ACT_TAG]
    mov     x9, #LIBP2P_REASON_LIMIT
    str     x9, [x0, #LIBP2P_ACT_REASON]
    b       9f
1:  mov     x20, x0
    ldr     x9, [x19, #LIBP2P_EV_TAG]
    str     x9, [x20, #C_TAG]
    add     x0, x20, #C_ADDR
    add     x1, x19, #LIBP2P_EV_DIAL_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    ldr     x9, [x19, #LIBP2P_EV_DIAL_ID_LEN]
    str     x9, [x20, #C_EXP_ID_LEN]
    add     x0, x20, #C_EXP_ID
    add     x1, x19, #LIBP2P_EV_DIAL_ID
    mov     x2, x9
    bl      libp2p_copy
    mov     x0, #LIBP2P_ACTION_DIAL
    mov     x1, #LIBP2P_ACT_DIAL_SIZE
    bl      libp2p_action
    mov     x21, x0
    cbz     x21, 8f
    mov     x0, x20
    bl      libp2p_conn_handle
    str     x0, [x21, #LIBP2P_ACT_CONN]
    add     x0, x21, #LIBP2P_ACT_DIAL_ADDR
    add     x1, x20, #C_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    b       9f
8:  mov     x0, x20
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial

/* libp2p_on_connected(event): the dial worked: propose /noise. */
LOCAL_FUNCTION libp2p_on_connected
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_CONN]
    bl      libp2p_conn
    cbz     x0, 9f
    mov     x19, x0
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_DIALING
    b.ne    9f
    mov     w9, #PH_SECURITY
    str     w9, [x19, #C_PHASE]
    ldr     x9, [x19, #C_FLAGS]
    orr     x9, x9, #CF_SENT_HEADER
    str     x9, [x19, #C_FLAGS]
    mov     x0, x19
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_conn_out
    mov     x0, x19
    adr     x1, 432b
    mov     x2, #7
    bl      libp2p_conn_out
9:  LEAVE   0
END_FUNCTION libp2p_on_connected

/* libp2p_on_dial_failed(event): the dial failed: DIAL_FAILED, and the slot is free. */
LOCAL_FUNCTION libp2p_on_dial_failed
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_CONN]
    bl      libp2p_conn
    cbz     x0, 9f
    mov     x19, x0
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_CLOSING
    b.eq    1f
    cmp     w9, #PH_DIALING
    b.ne    9f
    mov     x0, x19
    mov     x1, #LIBP2P_REASON_CONNECT
    bl      libp2p_conn_teardown
1:  mov     x0, x19
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial_failed

/* libp2p_on_closed(event): the shell closed the socket: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_on_closed
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_CONN]
    bl      libp2p_conn
    cbz     x0, 9f
    mov     x19, x0
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_CLOSING
    b.eq    1f
    mov     x0, x19
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_teardown
1:  mov     x0, x19
    bl      libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_closed

/* libp2p_on_sent(event): the shell wrote count bytes of the connection. */
LOCAL_FUNCTION libp2p_on_sent
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_CONN]
    bl      libp2p_conn
    cbz     x0, 9f
    ldr     x9, [x0, #C_INFLIGHT]
    ldr     x10, [x19, #LIBP2P_EV_COUNT]
    cmp     x10, x9
    csel    x10, x10, x9, lo
    sub     x9, x9, x10
    str     x9, [x0, #C_INFLIGHT]
9:  LEAVE   0
END_FUNCTION libp2p_on_sent

/*
 * libp2p_on_disconnect(event): the application ends the connections of a peer:
 * its secondary connections, then the first.
 * x19 peer, x20 peer index.
 */
LOCAL_FUNCTION libp2p_on_disconnect
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_PEER]
    bl      libp2p_peer
    cbz     x0, 9f
    mov     x19, x0
    TABLE   x9, ST_PEER_OFF
    sub     x20, x19, x9
    mov     x10, #P_SIZE
    udiv    x20, x20, x10
1:  mov     x0, x20
    ldr     x9, [x19, #P_CONN]
    TABLE   x10, ST_CONN_OFF
    mov     x11, #C_SIZE
    madd    x1, x9, x11, x10
    bl      libp2p_peer_other
    cbz     x0, 2f
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_close
    b       1b
2:  ldr     x9, [x19, #P_CONN]
    TABLE   x10, ST_CONN_OFF
    mov     x11, #C_SIZE
    madd    x0, x9, x11, x10
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_disconnect

/* ---------------------------------------------------------------- Receiving */

/*
 * libp2p_on_received(event): bytes of a connection: into its receive buffer,
 * which is handled each time it fills or the bytes end.
 * x19 conn, x20 data, x21 bytes left.
 */
LOCAL_FUNCTION libp2p_on_received
    ENTER   0
    mov     x19, x0
    add     x20, x19, #LIBP2P_EV_DATA
    ldr     x21, [x19, #LIBP2P_EV_COUNT]
    ldr     x0, [x19, #LIBP2P_EV_CONN]
    bl      libp2p_conn
    cbz     x0, 9f
    mov     x19, x0
1:  cbz     x21, 9f
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_SECURITY
    b.lo    9f
    cmp     w9, #PH_OPEN
    b.hi    9f
    ldr     x9, [x19, #C_RX_LEN]
    MOV64   x10, LIBP2P_RX_SIZE
    sub     x10, x10, x9
    cbz     x10, 8f                         /* full, and nothing could be taken */
    cmp     x21, x10
    csel    x22, x21, x10, lo
    ldr     x0, [x19, #C_RX]
    add     x0, x27, x0
    add     x0, x0, x9
    mov     x1, x20
    mov     x2, x22
    bl      libp2p_copy
    ldr     x9, [x19, #C_RX_LEN]
    add     x9, x9, x22
    str     x9, [x19, #C_RX_LEN]
    add     x20, x20, x22
    sub     x21, x21, x22
    mov     x0, x19
    bl      libp2p_conn_process
    b       1b
8:  mov     x0, x19
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_received

/* libp2p_conn_live(conn) -> 1 while the connection is in an upgrade phase or open, else 0. A leaf. */
LOCAL_FUNCTION libp2p_conn_live
    UNWIND_END_PROLOGUE
    ldr     w1, [x0, #C_PHASE]
    cmp     w1, #PH_SECURITY
    cset    x2, hs
    cmp     w1, #PH_OPEN
    cset    x3, ls
    and     x0, x2, x3
    ret
END_FUNCTION libp2p_conn_live

/*
 * libp2p_conn_process(conn): handles what the receive buffer holds: multistream
 * messages before Noise, Noise handshake messages, then transport messages,
 * whose plaintext goes on to the muxer. Moves what is left to the front.
 * x19 conn, x20 position, x21 the buffer, x22 bytes in it.
 */
LOCAL_FUNCTION libp2p_conn_process
    ENTER   0
    mov     x19, x0
    mov     x20, #0
1:  mov     x0, x19
    bl      libp2p_conn_live
    cbz     x0, 99f
    ldr     x21, [x19, #C_RX]
    add     x21, x27, x21
    ldr     x22, [x19, #C_RX_LEN]
    sub     x23, x22, x20                   /* bytes available */
    add     x24, x21, x20                   /* their start */
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_SECURITY
    b.ne    2f
    cbz     x23, 80f
    add     x0, x19, #C_MS_STATE
    mov     x1, #C_MS_CAP
    mov     x2, x24
    mov     x3, x23
    bl      libp2p_ms_take
    add     x20, x20, x0
    cmp     x1, #2
    b.eq    90f
    cbz     x1, 80f
    mov     x0, x19
    bl      libp2p_conn_ms
    b       1b
2:  cmp     x23, #2                         /* a Noise message: 2-byte length first */
    b.lo    80f
    ldrb    w9, [x24]
    ldrb    w10, [x24, #1]
    orr     x25, x10, x9, lsl #8
    add     x9, x25, #2
    cmp     x23, x9
    b.lo    80f
    add     x20, x20, x9
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_NOISE
    b.ne    3f
    mov     x0, x19
    add     x1, x24, #2
    mov     x2, x25
    bl      libp2p_noise_message
    cmp     x0, #2
    b.eq    91f
    cbnz    x0, 90f
    ldr     x9, [x19, #C_NS_STEP]
    cmp     x9, #2
    b.ne    1b
    mov     w9, #PH_MUXER                   /* the transport keys are ready */
    str     w9, [x19, #C_PHASE]
    str     xzr, [x19, #C_MS_LEN]
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #~(CF_SENT_HEADER | CF_GOT_HEADER)
    str     x9, [x19, #C_FLAGS]
    tst     x9, #CF_OUTBOUND
    b.eq    1b
    mov     x0, x19
    bl      libp2p_conn_propose_muxer
    b       1b
3:  mov     x0, x19
    add     x1, x24, #2
    mov     x2, x25
    bl      libp2p_noise_open
    cbnz    x0, 90f
    mov     x0, x19
    SCR     x1, (SC_PLAIN + LIBP2P_BL_FIXED)
    ldr     x2, [x28, #SC_PLAIN + LIBP2P_BL_COUNT]
    bl      libp2p_conn_plain
    b       1b
80: mov     x0, x19                         /* keep the rest at the front */
    bl      libp2p_conn_live
    cbz     x0, 99f
    ldr     x21, [x19, #C_RX]
    add     x21, x27, x21
    ldr     x22, [x19, #C_RX_LEN]
    mov     x0, x21
    add     x1, x21, x20
    sub     x2, x22, x20
    str     x2, [x19, #C_RX_LEN]
    bl      libp2p_copy
    b       99f
90: mov     x0, x19
    mov     x1, #LIBP2P_REASON_HANDSHAKE
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_OPEN
    mov     x9, #LIBP2P_REASON_CLOSED
    csel    x1, x9, x1, eq
    b       92f
91: mov     x0, x19
    mov     x1, #LIBP2P_REASON_PEER_ID
92: bl      libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_conn_process

/*
 * libp2p_conn_plain(conn, p, n): plaintext of a transport message: multistream
 * messages for the muxer first, then muxer frames.
 */
LOCAL_FUNCTION libp2p_conn_plain
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x21, 9f
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_MUXER
    b.ne    2f
    add     x0, x19, #C_MS_STATE
    mov     x1, #C_MS_CAP
    mov     x2, x20
    mov     x3, x21
    bl      libp2p_ms_take
    add     x20, x20, x0
    sub     x21, x21, x0
    cmp     x1, #2
    b.eq    8f
    cbz     x1, 9f
    mov     x0, x19
    bl      libp2p_conn_ms
    b       1b
2:  cmp     w9, #PH_OPEN
    b.ne    9f
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_mux_feed
    add     x20, x20, x0
    sub     x21, x21, x0
    b       1b
8:  mov     x0, x19
    mov     x1, #LIBP2P_REASON_HANDSHAKE
    bl      libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_plain

/* libp2p_conn_propose_muxer(conn): the dialer's multistream header and first muxer: yamux when it is on, else mplex. */
LOCAL_FUNCTION libp2p_conn_propose_muxer
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #C_FLAGS]
    orr     x9, x9, #CF_SENT_HEADER
    CFG     x10, LIBP2P_CFG_MUXERS
    tst     x10, #1
    b.ne    1f
    orr     x9, x9, #CF_MPLEX_TRIED
1:  str     x9, [x19, #C_FLAGS]
    mov     x0, x19
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_conn_out
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_MPLEX_TRIED
    adr     x1, 433b
    adr     x10, 434b
    csel    x1, x10, x1, ne
    mov     x0, x19
    mov     x2, #13
    bl      libp2p_conn_out
    LEAVE   0
END_FUNCTION libp2p_conn_propose_muxer

/*
 * libp2p_conn_ms(conn): one multistream message of the connection, before Noise
 * (for /noise) or after it (for the muxer). The header comes first; then
 * the listener answers proposals and the dialer reads answers.
 * x19 conn, x20 flags, x21 phase.
 */
LOCAL_FUNCTION libp2p_conn_ms
    ENTER   0
    mov     x19, x0
    ldr     x20, [x19, #C_FLAGS]
    ldr     w21, [x19, #C_PHASE]
    tst     x20, #CF_GOT_HEADER
    b.ne    2f
    add     x0, x19, #C_MS_STATE            /* the header */
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_ms_is
    cbz     x0, 80f
    orr     x20, x20, #CF_GOT_HEADER
    str     x20, [x19, #C_FLAGS]
    tst     x20, #CF_SENT_HEADER
    b.ne    70f
    orr     x20, x20, #CF_SENT_HEADER
    str     x20, [x19, #C_FLAGS]
    mov     x0, x19
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_conn_out
    b       70f
2:  tst     x20, #CF_OUTBOUND
    b.ne    40f
    cmp     w21, #PH_SECURITY               /* listener */
    b.ne    20f
    add     x0, x19, #C_MS_STATE
    adr     x1, 432b
    mov     x2, #7
    bl      libp2p_ms_is
    cbz     x0, 60f
    mov     x0, x19
    adr     x1, 432b
    mov     x2, #7
    bl      libp2p_conn_out
    b       30f
20: CFG     x22, LIBP2P_CFG_MUXERS
    tst     x22, #1
    b.eq    21f
    add     x0, x19, #C_MS_STATE
    adr     x1, 433b
    mov     x2, #13
    bl      libp2p_ms_is
    cbz     x0, 21f
    orr     x20, x20, #CF_YAMUX
    adr     x23, 433b
    b       22f
21: tst     x22, #2
    b.eq    60f
    add     x0, x19, #C_MS_STATE
    adr     x1, 434b
    mov     x2, #13
    bl      libp2p_ms_is
    cbz     x0, 60f
    orr     x20, x20, #CF_MPLEX
    adr     x23, 434b
22: str     x20, [x19, #C_FLAGS]
    mov     x0, x19
    mov     x1, x23
    mov     x2, #13
    bl      libp2p_conn_out
    str     xzr, [x19, #C_MS_LEN]
    mov     x0, x19
    bl      libp2p_conn_opened
    b       99f
30: str     xzr, [x19, #C_MS_LEN]           /* /noise selected */
    mov     w9, #PH_NOISE
    str     w9, [x19, #C_PHASE]
    mov     x0, x19
    bl      libp2p_noise_begin
    b       99f
40: cmp     w21, #PH_SECURITY               /* dialer */
    b.ne    41f
    add     x0, x19, #C_MS_STATE
    adr     x1, 432b
    mov     x2, #7
    bl      libp2p_ms_is
    cbz     x0, 80f
    b       30b
41: tst     x20, #CF_MPLEX_TRIED
    adr     x23, 433b
    adr     x9, 434b
    csel    x23, x9, x23, ne
    add     x0, x19, #C_MS_STATE
    mov     x1, x23
    mov     x2, #13
    bl      libp2p_ms_is
    cbz     x0, 42f
    tst     x20, #CF_MPLEX_TRIED
    mov     x9, #CF_YAMUX
    mov     x10, #CF_MPLEX
    csel    x9, x10, x9, ne
    orr     x20, x20, x9
    str     x20, [x19, #C_FLAGS]
    str     xzr, [x19, #C_MS_LEN]
    mov     x0, x19
    bl      libp2p_conn_opened
    b       99f
42: add     x0, x19, #C_MS_STATE            /* na: mplex next, when yamux was refused and mplex is on */
    adr     x1, 431b
    mov     x2, #3
    bl      libp2p_ms_is
    cbz     x0, 80f
    tst     x20, #CF_MPLEX_TRIED
    b.ne    80f
    CFG     x9, LIBP2P_CFG_MUXERS
    tst     x9, #2
    b.eq    80f
    orr     x20, x20, #CF_MPLEX_TRIED
    str     x20, [x19, #C_FLAGS]
    mov     x0, x19
    adr     x1, 434b
    mov     x2, #13
    bl      libp2p_conn_out
    b       70f
60: mov     x0, x19                         /* not supported */
    adr     x1, 431b
    mov     x2, #3
    bl      libp2p_conn_out
70: str     xzr, [x19, #C_MS_LEN]
    b       99f
80: mov     x0, x19
    mov     x1, #LIBP2P_REASON_HANDSHAKE
    bl      libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_conn_ms

/* ---------------------------------------------------------------- Peers */

/*
 * libp2p_conn_opened(conn): the muxer is chosen: phase PH_OPEN, the first
 * stream ID of this side (yamux: odd for the dialer, even for the
 * listener), then the peer.
 */
LOCAL_FUNCTION libp2p_conn_opened
    ENTER   0
    mov     x19, x0
    mov     w9, #PH_OPEN
    str     w9, [x19, #C_PHASE]
    ldr     x9, [x19, #C_FLAGS]
    mov     x10, #0
    tst     x9, #CF_YAMUX
    b.eq    1f
    tst     x9, #CF_OUTBOUND
    mov     x10, #1
    mov     x11, #2
    csel    x10, x10, x11, ne
1:  str     x10, [x19, #C_MX_NEXT_ID]
    str     xzr, [x19, #C_MX_HLEN]
    str     xzr, [x19, #C_MX_REMAIN]
    mov     x0, x19
    bl      libp2p_peer_bind
    LEAVE   0
END_FUNCTION libp2p_conn_opened

/* libp2p_peer_find(id, n) -> the peer slot (connected or retained) with the peer ID, or 0. */
LOCAL_FUNCTION libp2p_peer_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    TABLE   x21, ST_PEER_OFF
    ldr     x22, [x27, #ST_PEER_COUNT]
1:  cbz     x22, 8f
    ldr     w9, [x21, #P_STATE]
    cbz     w9, 2f
    add     x0, x21, #P_ID
    ldr     x1, [x21, #P_ID_LEN]
    mov     x2, x19
    mov     x3, x20
    bl      libp2p_compare
    cbz     x0, 2f
    mov     x0, x21
    b       9f
2:  add     x21, x21, #P_SIZE
    sub     x22, x22, #1
    b       1b
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_peer_find

/* libp2p_id_less(a, alen, b, blen) -> 1 when byte string a sorts before b, else 0. A leaf. */
LOCAL_FUNCTION libp2p_id_less
    UNWIND_END_PROLOGUE
    cmp     x1, x3
    csel    x4, x1, x3, lo
1:  cbz     x4, 2f
    ldrb    w5, [x0], #1
    ldrb    w6, [x2], #1
    cmp     w5, w6
    b.lo    7f
    b.hi    8f
    sub     x4, x4, #1
    b       1b
2:  cmp     x1, x3
    b.lo    7f
8:  mov     x0, #0
    ret
7:  mov     x0, #1
    ret
END_FUNCTION libp2p_id_less

/* libp2p_peer_conns(peer) -> the open connections bound to the peer. A leaf. */
LOCAL_FUNCTION libp2p_peer_conns
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_PEER_OFF]
    add     x1, x27, x1
    sub     x1, x0, x1
    mov     x2, #P_SIZE
    udiv    x1, x1, x2
    ldr     x2, [x27, #ST_CONN_OFF]
    add     x2, x27, x2
    ldr     x3, [x27, #ST_CONN_COUNT]
    mov     x0, #0
1:  cbz     x3, 9f
    ldr     w4, [x2, #C_PHASE]
    cmp     w4, #PH_OPEN
    b.ne    2f
    ldr     x4, [x2, #C_PEER]
    cmp     x4, x1
    b.ne    2f
    add     x0, x0, #1
2:  add     x2, x2, #C_SIZE
    sub     x3, x3, #1
    b       1b
9:  ret
END_FUNCTION libp2p_peer_conns

/* libp2p_peer_other(peer index, conn) -> another open connection bound to the peer, or 0. A leaf. */
LOCAL_FUNCTION libp2p_peer_other
    UNWIND_END_PROLOGUE
    ldr     x2, [x27, #ST_CONN_OFF]
    add     x2, x27, x2
    ldr     x3, [x27, #ST_CONN_COUNT]
1:  cbz     x3, 8f
    cmp     x2, x1
    b.eq    2f
    ldr     w4, [x2, #C_PHASE]
    cmp     w4, #PH_OPEN
    b.ne    2f
    ldr     x4, [x2, #C_PEER]
    cmp     x4, x0
    b.ne    2f
    mov     x0, x2
    ret
2:  add     x2, x2, #C_SIZE
    sub     x3, x3, #1
    b       1b
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_peer_other

/*
 * libp2p_peer_bind(conn): binds the open connection to its peer. A dial that
 * reached another peer, or ourselves, ends. With an open connection to the
 * peer already: when each side dialled one, the one dialled by the peer
 * with the smaller ID stays; when the peer dialled again, the new one is a
 * secondary connection (up to LIBP2P_PEER_CONNS), which takes over if the
 * first ends; when we dialled again, the new one ends. A retained score
 * comes back. Then PEER_CONNECTED, and gossipsub learns of the peer.
 * x19 conn, x20 peer, x21 other conn, x22 peer index.
 */
LOCAL_FUNCTION libp2p_peer_bind
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #C_EXP_ID_LEN]
    cbz     x9, 1f
    add     x0, x19, #C_EXP_ID
    mov     x1, x9
    add     x2, x19, #C_RID
    ldr     x3, [x19, #C_RID_LEN]
    bl      libp2p_compare
    cbz     x0, 81f
1:  add     x0, x27, #ST_PEER_ID
    ldr     x1, [x27, #ST_PEER_ID_LEN]
    add     x2, x19, #C_RID
    ldr     x3, [x19, #C_RID_LEN]
    bl      libp2p_compare
    cbnz    x0, 81f
    add     x0, x19, #C_RID
    ldr     x1, [x19, #C_RID_LEN]
    bl      libp2p_peer_find
    mov     x20, x0
    cbz     x20, 4f
    ldr     w9, [x20, #P_STATE]
    cmp     w9, #PS_CONNECTED
    b.ne    3f
    ldr     x9, [x20, #P_CONN]              /* a second connection to the peer */
    TABLE   x10, ST_CONN_OFF
    mov     x11, #C_SIZE
    madd    x21, x9, x11, x10
    ldr     x9, [x19, #C_FLAGS]
    ldr     x10, [x21, #C_FLAGS]
    eor     x11, x9, x10
    tst     x11, #CF_OUTBOUND
    b.eq    84f                             /* same dialer */
    add     x0, x27, #ST_PEER_ID            /* is our ID the smaller? */
    ldr     x1, [x27, #ST_PEER_ID_LEN]
    add     x2, x19, #C_RID
    ldr     x3, [x19, #C_RID_LEN]
    bl      libp2p_id_less
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #CF_OUTBOUND            /* 1 when we dialled the new one */
    cmp     x0, x9
    b.ne    82f                             /* the old one has the smaller dialer */
    TABLE   x9, ST_PEER_OFF                 /* the new one stays: the old one ends, with any secondary connections */
    sub     x22, x20, x9
    mov     x10, #P_SIZE
    udiv    x22, x22, x10
85: mov     x0, x22
    mov     x1, x21
    bl      libp2p_peer_other
    cbz     x0, 86f
    mov     x1, #LIBP2P_REASON_DUPLICATE
    bl      libp2p_conn_close
    b       85b
86: mov     x0, x21
    mov     x1, #LIBP2P_REASON_DUPLICATE
    bl      libp2p_conn_close
    add     x0, x19, #C_RID
    ldr     x1, [x19, #C_RID_LEN]
    bl      libp2p_peer_find
    mov     x20, x0
    cbz     x20, 4f
3:  ldr     w9, [x20, #P_GEN]               /* a retained peer comes back */
    add     w9, w9, #1
    str     w9, [x20, #P_GEN]
    mov     w9, #PS_CONNECTED
    str     w9, [x20, #P_STATE]
    b       5f
4:  mov     x0, #ST_PEER_OFF
    mov     x1, #ST_PEER_COUNT
    mov     x2, #P_SIZE
    bl      libp2p_alloc_slot
    mov     x20, x0
    cbnz    x20, 41f
    bl      libp2p_peer_evict
    cbz     x0, 83f
    mov     x0, #ST_PEER_OFF
    mov     x1, #ST_PEER_COUNT
    mov     x2, #P_SIZE
    bl      libp2p_alloc_slot
    mov     x20, x0
    cbz     x20, 83f
41: add     x0, x20, #P_ID
    add     x1, x19, #C_RID
    ldr     x2, [x19, #C_RID_LEN]
    str     x2, [x20, #P_ID_LEN]
    bl      libp2p_copy
5:  TABLE   x9, ST_CONN_OFF                 /* fill in the peer */
    sub     x9, x19, x9
    mov     x10, #C_SIZE
    udiv    x9, x9, x10
    str     x9, [x20, #P_CONN]
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #CF_OUTBOUND
    str     x9, [x20, #P_FLAGS]
    mov     x9, #NONE
    str     x9, [x20, #P_GS_OUT]
    str     x9, [x20, #P_GS_IN]
    add     x0, x20, #P_IP
    add     x1, x19, #C_ADDR + LIBP2P_ADDR_IP
    mov     x2, #16
    bl      libp2p_copy
    ldr     x9, [x19, #C_ADDR + LIBP2P_ADDR_FAMILY]
    str     x9, [x20, #P_IP_FAMILY]
    TABLE   x9, ST_PEER_OFF
    sub     x9, x20, x9
    mov     x10, #P_SIZE
    udiv    x9, x9, x10
    str     x9, [x19, #C_PEER]
    ldr     x9, [x19, #C_FLAGS]
    orr     x9, x9, #CF_REPORTED
    str     x9, [x19, #C_FLAGS]
    mov     x0, #LIBP2P_ACTION_PEER_CONNECTED
    mov     x1, #LIBP2P_ACT_PC_SIZE
    bl      libp2p_action
    cbz     x0, 6f
    mov     x21, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    mov     x2, x20
    bl      libp2p_handle
    str     x0, [x21, #LIBP2P_ACT_PEER]
    ldr     x9, [x19, #C_TAG]
    str     x9, [x21, #LIBP2P_ACT_PC_TAG]
    ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #CF_OUTBOUND
    str     x9, [x21, #LIBP2P_ACT_PC_DIRECTION]
    add     x0, x21, #LIBP2P_ACT_PC_ADDR
    add     x1, x19, #C_ADDR
    mov     x2, #LIBP2P_ADDR_SIZE
    bl      libp2p_copy
    ldr     x2, [x20, #P_ID_LEN]
    str     x2, [x21, #LIBP2P_ACT_PC_ID_LEN]
    add     x0, x21, #LIBP2P_ACT_PC_ID
    add     x1, x20, #P_ID
    bl      libp2p_copy
6:  mov     x0, x20
    bl      libp2p_gossip_peer_up
    b       99f
84: tst     x9, #CF_OUTBOUND                /* we dialled the peer again: the new one ends */
    b.ne    82f
    mov     x0, x20                         /* the peer dialled us again: a secondary connection */
    bl      libp2p_peer_conns
    cmp     x0, #LIBP2P_PEER_CONNS
    b.hs    82f
    TABLE   x9, ST_PEER_OFF
    sub     x9, x20, x9
    mov     x10, #P_SIZE
    udiv    x9, x9, x10
    str     x9, [x19, #C_PEER]
    ldr     x9, [x19, #C_FLAGS]
    orr     x9, x9, #CF_REPORTED
    str     x9, [x19, #C_FLAGS]
    b       99f
81: mov     x0, x19
    mov     x1, #LIBP2P_REASON_PEER_ID
    bl      libp2p_conn_close
    b       99f
82: mov     x0, x19
    mov     x1, #LIBP2P_REASON_DUPLICATE
    bl      libp2p_conn_close
    b       99f
83: mov     x0, x19
    mov     x1, #LIBP2P_REASON_LIMIT
    bl      libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_peer_bind

/*
 * libp2p_peer_evict() -> 1 when it freed the retained peer whose score ends
 * first, 0 when no peer is retained.
 */
LOCAL_FUNCTION libp2p_peer_evict
    ENTER   0
    TABLE   x19, ST_PEER_OFF
    ldr     x20, [x27, #ST_PEER_COUNT]
    mov     x21, #0
    mov     x22, #NONE
1:  cbz     x20, 2f
    ldr     w9, [x19, #P_STATE]
    cmp     w9, #PS_RETAINED
    b.ne    11f
    ldr     x9, [x19, #P_EXPIRE]
    cmp     x9, x22
    b.hs    11f
    mov     x22, x9
    mov     x21, x19
11: add     x19, x19, #P_SIZE
    sub     x20, x20, #1
    b       1b
2:  mov     x0, #0
    cbz     x21, 9f
    mov     x0, x21
    bl      libp2p_peer_release
    mov     x0, #1
9:  LEAVE   0
END_FUNCTION libp2p_peer_evict

/* libp2p_peer_release(peer): the slot becomes free, and so do its peer x topic entries. */
LOCAL_FUNCTION libp2p_peer_release
    ENTER   0
    mov     x19, x0
    str     wzr, [x19, #P_STATE]
    TABLE   x9, ST_PEER_OFF
    sub     x9, x19, x9
    mov     x10, #P_SIZE
    udiv    x9, x9, x10
    ldr     x10, [x27, #ST_TOPIC_COUNT]
    mul     x9, x9, x10
    mov     x11, #PT_SIZE
    mul     x9, x9, x11
    TABLE   x0, ST_PT_OFF
    add     x0, x0, x9
    mul     x1, x10, x11
    bl      libp2p_zero
    LEAVE   0
END_FUNCTION libp2p_peer_release

/*
 * libp2p_peer_down(peer): its connection ended: gossipsub forgets it,
 * PEER_DISCONNECTED, then the slot is retained for its score, or freed.
 */
LOCAL_FUNCTION libp2p_peer_down
    ENTER   0
    mov     x19, x0
    bl      libp2p_gossip_peer_down
    mov     x0, #LIBP2P_ACTION_PEER_DISCONNECTED
    mov     x1, #LIBP2P_ACT_PD_SIZE
    bl      libp2p_action
    cbz     x0, 1f
    mov     x20, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    mov     x2, x19
    bl      libp2p_handle
    str     x0, [x20, #LIBP2P_ACT_PEER]
    ldr     x2, [x19, #P_ID_LEN]
    str     x2, [x20, #LIBP2P_ACT_PD_ID_LEN]
    add     x0, x20, #LIBP2P_ACT_PD_ID
    add     x1, x19, #P_ID
    bl      libp2p_copy
1:  mov     x9, #NONE
    str     x9, [x19, #P_CONN]
    str     x9, [x19, #P_GS_OUT]
    str     x9, [x19, #P_GS_IN]
    CFG     x9, LIBP2P_CFG_SCORING
    CFG     x10, LIBP2P_CFG_RETAIN_SCORE_MS
    cbz     x9, 2f
    cbz     x10, 2f
    ldr     x11, [x28, #SC_NOW]
    add     x11, x11, x10
    str     x11, [x19, #P_EXPIRE]
    mov     w9, #PS_RETAINED
    str     w9, [x19, #P_STATE]
    ldr     w9, [x19, #P_GEN]               /* old handles no longer work */
    add     w9, w9, #1
    str     w9, [x19, #P_GEN]
    b       9f
2:  mov     x0, x19
    bl      libp2p_peer_release
9:  LEAVE   0
END_FUNCTION libp2p_peer_down

/*
 * Connections of the RISC-V core: the shell events of a TCP connection,
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
438:
    .ascii  "/meshsub/1.3.0\n"
    .zero   5                           /* 120 bytes in all: code after it needs no padding */
    .p2align 3

/* libp2p_ms_put(dst, str, n) -> dst after one multistream message: varint(n), then the n bytes (the newline included). */
LOCAL_FUNCTION libp2p_ms_put
    ENTER   0
    mv      s1, a1
    mv      s2, a2
    mv      a1, s2
    call    libp2p_varint_put
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ms_put

/* libp2p_ms_put_proto(dst, bytes, n) -> dst after the message of a protocol ID: varint(n + 1), the bytes, a newline. */
LOCAL_FUNCTION libp2p_ms_put_proto
    ENTER   0
    mv      s1, a1
    mv      s2, a2
    addi    a1, s2, 1
    call    libp2p_varint_put
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    li      t0, 10
    sb      t0, 0(a0)
    addi    a0, a0, 1
    LEAVE   0
END_FUNCTION libp2p_ms_put_proto

/*
 * libp2p_ms_take(ms, cap, src, n) -> a0 the bytes taken from src, a1 the
 * result: 0 when more bytes are needed, 1 when one whole message is in the
 * buffer, 2 when the bytes are not a message that fits. ms holds the
 * negotiation state, the bytes held, the varint length of the message,
 * then cap bytes of buffer. The message (its newline last) is at buffer +
 * varint length. Bytes after the message stay in src.
 * s1 ms, s2 cap, s3 src, s4 n, s5 taken, s6 bytes held.
 */
.set MS_STATE, 0
.set MS_LEN, 8
.set MS_NEED, 16
.set MS_BUF, 24
LOCAL_FUNCTION libp2p_ms_take
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      s5, 0
1:  bgeu    s5, s4, 7f
    ld      s6, MS_LEN(s1)
    bgeu    s6, s2, 8f
    add     t0, s3, s5
    lbu     t0, 0(t0)
    addi    t1, s1, MS_BUF
    add     t1, t1, s6
    sb      t0, 0(t1)
    addi    s6, s6, 1
    sd      s6, MS_LEN(s1)
    addi    s5, s5, 1
    addi    a0, s1, MS_BUF
    add     a1, a0, s6
    call    libp2p_varint_get
    li      t0, NONE
    beq     a1, t0, 8f
    beqz    a1, 1b
    beqz    a0, 8f
    sub     t0, s2, a1
    bltu    t0, a0, 8f
    add     t0, a0, a1
    bltu    s6, t0, 1b
    sd      a1, MS_NEED(s1)
    addi    t1, s1, MS_BUF
    add     t1, t1, s6
    lbu     t2, -1(t1)
    li      t0, 10
    bne     t2, t0, 8f
    mv      a0, s5
    li      a1, 1
    j       9f
7:  mv      a0, s5
    li      a1, 0
    j       9f
8:  mv      a0, s5
    li      a1, 2
9:  LEAVE   0
END_FUNCTION libp2p_ms_take

/* libp2p_ms_is(ms, str, n) -> 1 when the message in ms is the n bytes at str, else 0. */
LOCAL_FUNCTION libp2p_ms_is
    ENTER   0
    mv      s1, a1
    mv      s2, a2
    ld      t0, MS_NEED(a0)
    ld      t1, MS_LEN(a0)
    addi    t2, a0, MS_BUF
    add     a0, t2, t0
    sub     a1, t1, t0
    mv      a2, s1
    mv      a3, s2
    call    libp2p_compare
    LEAVE   0
END_FUNCTION libp2p_ms_is

/* ---------------------------------------------------------------- Connection slots */

/*
 * libp2p_conn_new(outbound) -> a new connection slot with its receive buffer,
 * in phase PH_DIALING, or 0 when no slot or heap block is free.
 */
LOCAL_FUNCTION libp2p_conn_new
    ENTER   0
    mv      s1, a0
    li      a0, ST_CONN_OFF
    li      a1, ST_CONN_COUNT
    li      a2, C_SIZE
    call    libp2p_alloc_slot
    beqz    a0, 9f
    mv      s2, a0
    li      a0, LIBP2P_RX_SIZE
    call    libp2p_heap_alloc
    bnez    a0, 1f
    sw      zero, C_PHASE(s2)
    li      a0, 0
    j       9f
1:  sd      a0, C_RX(s2)
    li      t0, NONE
    sd      t0, C_PEER(s2)
    sd      t0, C_STREAM_HEAD(s2)
    sd      t0, C_MX_STREAM(s2)
    sd      t0, C_CURSOR(s2)
    li      t0, 0
    beqz    s1, 2f
    li      t0, CF_OUTBOUND
2:  sd      t0, C_FLAGS(s2)
    ld      t0, SC_NOW(s10)
    CFG     t1, LIBP2P_CFG_HANDSHAKE_MS
    add     t0, t0, t1
    sd      t0, C_DEADLINE(s2)
    li      t0, PH_DIALING
    sw      t0, C_PHASE(s2)
    ld      t0, ST_CONN_LIVE(s9)
    addi    t0, t0, 1
    sd      t0, ST_CONN_LIVE(s9)
    mv      a0, s2
9:  LEAVE   0
END_FUNCTION libp2p_conn_new

/* libp2p_conn_handle(conn) -> its handle. */
LOCAL_FUNCTION libp2p_conn_handle
    ENTER   0
    mv      a2, a0
    li      a0, ST_CONN_OFF
    li      a1, C_SIZE
    call    libp2p_handle
    LEAVE   0
END_FUNCTION libp2p_conn_handle

/* libp2p_conn_free(conn): the slot becomes free. */
LOCAL_FUNCTION libp2p_conn_free
    ENTER   0
    mv      s1, a0
    ld      a0, C_RX(s1)
    call    libp2p_heap_free
    sd      zero, C_RX(s1)
    sw      zero, C_PHASE(s1)
    ld      t0, ST_CONN_LIVE(s9)
    addi    t0, t0, -1
    sd      t0, ST_CONN_LIVE(s9)
    LEAVE   0
END_FUNCTION libp2p_conn_free

/* libp2p_conn_out(conn, str, n): queues one multistream message (str holds n bytes, the newline included). */
LOCAL_FUNCTION libp2p_conn_out
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    a1, s3, 1
    call    libp2p_noise_out
    beqz    a0, 9f
    mv      a1, s2
    mv      a2, s3
    call    libp2p_ms_put
9:  LEAVE   0
END_FUNCTION libp2p_conn_out

/*
 * libp2p_conn_teardown(conn, reason): ends everything above the socket: the
 * streams (the application hears of its own); then the peer
 * (PEER_DISCONNECTED) when this was its connection and no other is open,
 * else another connection of the peer takes over; or, for a dial not yet
 * reported, DIAL_FAILED; then the receive buffer.
 * s1 conn, s2 reason, s3 peer index, s4 peer.
 */
LOCAL_FUNCTION libp2p_conn_teardown
    ENTER   0
    mv      s1, a0
    mv      s2, a1
1:  ld      t0, C_STREAM_HEAD(s1)           # the streams
    li      t1, NONE
    beq     t0, t1, 2f
    TABLE   t1, ST_STREAM_OFF
    li      t2, S_SIZE
    mul     t0, t0, t2
    add     a0, t1, t0
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_stream_kill
    j       1b
2:  ld      s3, C_PEER(s1)
    li      t0, NONE
    beq     s3, t0, 3f
    sd      t0, C_PEER(s1)                  # this connection no longer counts for the peer
    TABLE   t1, ST_PEER_OFF
    li      t2, P_SIZE
    mul     t2, s3, t2
    add     s4, t1, t2                      # the peer
    TABLE   t1, ST_CONN_OFF
    sub     t0, s1, t1
    li      t2, C_SIZE
    divu    t0, t0, t2
    ld      t1, P_CONN(s4)
    bne     t0, t1, 4f                      # a secondary connection: the peer stays
    mv      a0, s3
    mv      a1, s1
    call    libp2p_peer_other
    beqz    a0, 21f
    TABLE   t1, ST_CONN_OFF                 # another connection of the peer takes over
    sub     t0, a0, t1
    li      t2, C_SIZE
    divu    t0, t0, t2
    sd      t0, P_CONN(s4)
    ld      t0, C_FLAGS(a0)
    andi    t0, t0, CF_OUTBOUND
    ld      t1, P_FLAGS(s4)
    andi    t1, t1, ~PF_OUTBOUND
    or      t1, t1, t0
    sd      t1, P_FLAGS(s4)
    ld      t0, (C_ADDR + LIBP2P_ADDR_IP)(a0)
    ld      t1, (C_ADDR + LIBP2P_ADDR_IP + 8)(a0)
    sd      t0, P_IP(s4)
    sd      t1, (P_IP + 8)(s4)
    ld      t0, (C_ADDR + LIBP2P_ADDR_FAMILY)(a0)
    sd      t0, P_IP_FAMILY(s4)
    mv      a0, s4
    call    libp2p_gossip_peer_up               # our gossipsub stream again, on that connection
    j       4f
21: mv      a0, s4
    call    libp2p_peer_down
    j       4f
3:  ld      t0, C_FLAGS(s1)
    andi    t1, t0, CF_OUTBOUND
    beqz    t1, 4f
    andi    t1, t0, CF_REPORTED
    bnez    t1, 4f
    ori     t0, t0, CF_REPORTED
    sd      t0, C_FLAGS(s1)
    li      a0, LIBP2P_ACTION_DIAL_FAILED
    li      a1, LIBP2P_ACT_FAILED_SIZE
    call    libp2p_action
    beqz    a0, 4f
    ld      t0, C_TAG(s1)
    sd      t0, LIBP2P_ACT_TAG(a0)
    sd      s2, LIBP2P_ACT_REASON(a0)
4:  ld      a0, C_RX(s1)
    call    libp2p_heap_free
    sd      zero, C_RX(s1)
    sd      zero, C_RX_LEN(s1)
    sd      zero, C_OUT_LEN(s1)
    sd      zero, C_OUT_RAW(s1)
    LEAVE   0
END_FUNCTION libp2p_conn_teardown

/*
 * libp2p_conn_close(conn, reason): ends a live connection: teardown, then a
 * CLOSE action (kept as a flag for the drain when the list is full); the
 * slot waits in PH_CLOSING for the CLOSED event.
 */
LOCAL_FUNCTION libp2p_conn_close
    ENTER   0
    mv      s1, a0
    lwu     t0, C_PHASE(s1)
    li      t1, PH_DIALING
    bltu    t0, t1, 9f
    li      t1, PH_CLOSING
    bgeu    t0, t1, 9f
    call    libp2p_conn_teardown
    li      t0, PH_CLOSING
    sw      t0, C_PHASE(s1)
    mv      a0, s1
    call    libp2p_conn_send_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_close

/* libp2p_conn_send_close(conn): a CLOSE action for the connection, or the flag that asks the drain for one. */
LOCAL_FUNCTION libp2p_conn_send_close
    ENTER   0
    mv      s1, a0
    li      a0, LIBP2P_ACTION_CLOSE
    li      a1, LIBP2P_ACT_CLOSE_SIZE
    call    libp2p_action
    ld      t0, C_FLAGS(s1)
    bnez    a0, 1f
    ori     t0, t0, CF_NEED_CLOSE
    sd      t0, C_FLAGS(s1)
    j       9f
1:  andi    t0, t0, ~CF_NEED_CLOSE
    sd      t0, C_FLAGS(s1)
    mv      s2, a0
    mv      a0, s1
    call    libp2p_conn_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
9:  LEAVE   0
END_FUNCTION libp2p_conn_send_close

/* ---------------------------------------------------------------- Shell events */

/* libp2p_on_accepted(event): a new inbound connection: ADOPT it, or REFUSE it when no slot is free. */
LOCAL_FUNCTION libp2p_on_accepted
    ENTER   0
    mv      s1, a0
    li      a0, 0
    call    libp2p_conn_new
    bnez    a0, 1f
    li      a0, LIBP2P_ACTION_REFUSE
    li      a1, LIBP2P_ACT_REFUSE_SIZE
    call    libp2p_action
    beqz    a0, 9f
    ld      t0, LIBP2P_EV_TOKEN(s1)
    sd      t0, LIBP2P_ACT_TOKEN(a0)
    j       9f
1:  mv      s2, a0
    addi    a0, s2, C_ADDR
    addi    a1, s1, LIBP2P_EV_ACCEPTED_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    li      t0, PH_SECURITY
    sw      t0, C_PHASE(s2)
    li      a0, LIBP2P_ACTION_ADOPT
    li      a1, LIBP2P_ACT_ADOPT_SIZE
    call    libp2p_action
    mv      s3, a0
    beqz    s3, 8f
    ld      t0, LIBP2P_EV_TOKEN(s1)
    sd      t0, LIBP2P_ACT_TOKEN(s3)
    mv      a0, s2
    call    libp2p_conn_handle
    sd      a0, LIBP2P_ACT_ADOPT_CONN(s3)
    j       9f
8:  mv      a0, s2                          # no room: give the slot back
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_accepted

/* libp2p_on_dial(event): the application asks for a connection: a DIAL action, or DIAL_FAILED when no slot is free. */
LOCAL_FUNCTION libp2p_on_dial
    ENTER   0
    mv      s1, a0
    li      a0, 1
    call    libp2p_conn_new
    bnez    a0, 1f
    li      a0, LIBP2P_ACTION_DIAL_FAILED
    li      a1, LIBP2P_ACT_FAILED_SIZE
    call    libp2p_action
    beqz    a0, 9f
    ld      t0, LIBP2P_EV_TAG(s1)
    sd      t0, LIBP2P_ACT_TAG(a0)
    li      t0, LIBP2P_REASON_LIMIT
    sd      t0, LIBP2P_ACT_REASON(a0)
    j       9f
1:  mv      s2, a0
    ld      t0, LIBP2P_EV_TAG(s1)
    sd      t0, C_TAG(s2)
    addi    a0, s2, C_ADDR
    addi    a1, s1, LIBP2P_EV_DIAL_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    ld      a2, LIBP2P_EV_DIAL_ID_LEN(s1)
    sd      a2, C_EXP_ID_LEN(s2)
    addi    a0, s2, C_EXP_ID
    addi    a1, s1, LIBP2P_EV_DIAL_ID
    call    libp2p_copy
    li      a0, LIBP2P_ACTION_DIAL
    li      a1, LIBP2P_ACT_DIAL_SIZE
    call    libp2p_action
    mv      s3, a0
    beqz    s3, 8f
    mv      a0, s2
    call    libp2p_conn_handle
    sd      a0, LIBP2P_ACT_CONN(s3)
    addi    a0, s3, LIBP2P_ACT_DIAL_ADDR
    addi    a1, s2, C_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    j       9f
8:  mv      a0, s2
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial

/* libp2p_on_connected(event): the dial worked: propose /noise. */
LOCAL_FUNCTION libp2p_on_connected
    ENTER   0
    ld      a0, LIBP2P_EV_CONN(a0)
    call    libp2p_conn
    beqz    a0, 9f
    mv      s1, a0
    lwu     t0, C_PHASE(s1)
    li      t1, PH_DIALING
    bne     t0, t1, 9f
    li      t0, PH_SECURITY
    sw      t0, C_PHASE(s1)
    ld      t0, C_FLAGS(s1)
    ori     t0, t0, CF_SENT_HEADER
    sd      t0, C_FLAGS(s1)
    mv      a0, s1
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_conn_out
    mv      a0, s1
    lla     a1, 432b
    li      a2, 7
    call    libp2p_conn_out
9:  LEAVE   0
END_FUNCTION libp2p_on_connected

/* libp2p_on_dial_failed(event): the dial failed: DIAL_FAILED, and the slot is free. */
LOCAL_FUNCTION libp2p_on_dial_failed
    ENTER   0
    ld      a0, LIBP2P_EV_CONN(a0)
    call    libp2p_conn
    beqz    a0, 9f
    mv      s1, a0
    lwu     t0, C_PHASE(s1)
    li      t1, PH_CLOSING
    beq     t0, t1, 1f
    li      t1, PH_DIALING
    bne     t0, t1, 9f
    mv      a0, s1
    li      a1, LIBP2P_REASON_CONNECT
    call    libp2p_conn_teardown
1:  mv      a0, s1
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial_failed

/* libp2p_on_closed(event): the shell closed the socket: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_on_closed
    ENTER   0
    ld      a0, LIBP2P_EV_CONN(a0)
    call    libp2p_conn
    beqz    a0, 9f
    mv      s1, a0
    lwu     t0, C_PHASE(s1)
    li      t1, PH_CLOSING
    beq     t0, t1, 1f
    mv      a0, s1
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_teardown
1:  mv      a0, s1
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_closed

/* libp2p_on_sent(event): the shell wrote count bytes of the connection. */
LOCAL_FUNCTION libp2p_on_sent
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_CONN(s1)
    call    libp2p_conn
    beqz    a0, 9f
    ld      t0, C_INFLIGHT(a0)
    ld      t1, LIBP2P_EV_COUNT(s1)
    bltu    t1, t0, 1f
    mv      t1, t0
1:  sub     t0, t0, t1
    sd      t0, C_INFLIGHT(a0)
9:  LEAVE   0
END_FUNCTION libp2p_on_sent

/*
 * libp2p_on_disconnect(event): the application ends the connections of a peer:
 * its secondary connections, then the first.
 * s1 peer, s2 peer index.
 */
LOCAL_FUNCTION libp2p_on_disconnect
    ENTER   0
    ld      a0, LIBP2P_EV_PEER(a0)
    call    libp2p_peer
    beqz    a0, 9f
    mv      s1, a0
    TABLE   t0, ST_PEER_OFF
    sub     s2, s1, t0
    li      t1, P_SIZE
    divu    s2, s2, t1
1:  mv      a0, s2
    ld      t0, P_CONN(s1)
    TABLE   t1, ST_CONN_OFF
    li      t2, C_SIZE
    mul     t0, t0, t2
    add     a1, t1, t0
    call    libp2p_peer_other
    beqz    a0, 2f
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_close
    j       1b
2:  ld      t0, P_CONN(s1)
    TABLE   t1, ST_CONN_OFF
    li      t2, C_SIZE
    mul     t0, t0, t2
    add     a0, t1, t0
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_disconnect

/* ---------------------------------------------------------------- Receiving */

/*
 * libp2p_on_received(event): bytes of a connection: into its receive buffer,
 * which is handled each time it fills or the bytes end.
 * s1 conn, s2 data, s3 bytes left, s4 bytes this round.
 */
LOCAL_FUNCTION libp2p_on_received
    ENTER   0
    mv      s1, a0
    addi    s2, s1, LIBP2P_EV_DATA
    ld      s3, LIBP2P_EV_COUNT(s1)
    ld      a0, LIBP2P_EV_CONN(s1)
    call    libp2p_conn
    beqz    a0, 9f
    mv      s1, a0
1:  beqz    s3, 9f
    lwu     t0, C_PHASE(s1)
    li      t1, PH_SECURITY
    bltu    t0, t1, 9f
    li      t1, PH_OPEN
    bltu    t1, t0, 9f
    ld      t0, C_RX_LEN(s1)
    li      t1, LIBP2P_RX_SIZE
    sub     t1, t1, t0
    beqz    t1, 8f                          # full, and nothing could be taken
    mv      s4, s3
    bltu    s3, t1, 2f
    mv      s4, t1
2:  ld      a0, C_RX(s1)
    add     a0, s9, a0
    add     a0, a0, t0
    mv      a1, s2
    mv      a2, s4
    call    libp2p_copy
    ld      t0, C_RX_LEN(s1)
    add     t0, t0, s4
    sd      t0, C_RX_LEN(s1)
    add     s2, s2, s4
    sub     s3, s3, s4
    mv      a0, s1
    call    libp2p_conn_process
    j       1b
8:  mv      a0, s1
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_received

/* libp2p_conn_live(conn) -> 1 while the connection is in an upgrade phase or open, else 0. A leaf. */
LOCAL_FUNCTION libp2p_conn_live
    UNWIND_END_PROLOGUE
    lwu     a1, C_PHASE(a0)
    li      a0, 0
    li      a2, PH_SECURITY
    bltu    a1, a2, 9f
    li      a2, PH_OPEN
    bltu    a2, a1, 9f
    li      a0, 1
9:  ret
END_FUNCTION libp2p_conn_live

/*
 * libp2p_conn_process(conn): handles what the receive buffer holds: multistream
 * messages before Noise, Noise handshake messages, then transport messages,
 * whose plaintext goes on to the muxer. Moves what is left to the front.
 * s1 conn, s2 position, s3 the buffer, s4 bytes in it, s5 bytes available,
 * s6 their start, s7 the message length.
 */
LOCAL_FUNCTION libp2p_conn_process
    ENTER   0
    mv      s1, a0
    li      s2, 0
1:  mv      a0, s1
    call    libp2p_conn_live
    beqz    a0, 99f
    ld      s3, C_RX(s1)
    add     s3, s9, s3
    ld      s4, C_RX_LEN(s1)
    sub     s5, s4, s2                      # bytes available
    add     s6, s3, s2                      # their start
    lwu     t0, C_PHASE(s1)
    li      t1, PH_SECURITY
    bne     t0, t1, 2f
    beqz    s5, 80f
    addi    a0, s1, C_MS_STATE
    li      a1, C_MS_CAP
    mv      a2, s6
    mv      a3, s5
    call    libp2p_ms_take
    add     s2, s2, a0
    li      t0, 2
    beq     a1, t0, 90f
    beqz    a1, 80f
    mv      a0, s1
    call    libp2p_conn_ms
    j       1b
2:  li      t1, 2                           # a Noise message: 2-byte length first
    bltu    s5, t1, 80f
    lbu     t1, 0(s6)
    lbu     t2, 1(s6)
    slli    t1, t1, 8
    or      s7, t1, t2
    addi    t1, s7, 2
    bltu    s5, t1, 80f
    add     s2, s2, t1
    li      t1, PH_NOISE
    bne     t0, t1, 3f
    mv      a0, s1
    addi    a1, s6, 2
    mv      a2, s7
    call    libp2p_noise_message
    li      t0, 2
    beq     a0, t0, 91f
    bnez    a0, 90f
    ld      t0, C_NS_STEP(s1)
    li      t1, 2
    bne     t0, t1, 1b
    li      t0, PH_MUXER                    # the transport keys are ready
    sw      t0, C_PHASE(s1)
    sd      zero, C_MS_LEN(s1)
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, ~(CF_SENT_HEADER | CF_GOT_HEADER)
    sd      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND
    beqz    t0, 1b
    mv      a0, s1
    call    libp2p_conn_propose_muxer
    j       1b
3:  mv      a0, s1
    addi    a1, s6, 2
    mv      a2, s7
    call    libp2p_noise_open
    bnez    a0, 90f
    mv      a0, s1
    SCR     a1, (SC_PLAIN + LIBP2P_BL_FIXED)
    LDSC    a2, (SC_PLAIN + LIBP2P_BL_COUNT)
    call    libp2p_conn_plain
    j       1b
80: mv      a0, s1                          # keep the rest at the front
    call    libp2p_conn_live
    beqz    a0, 99f
    ld      s3, C_RX(s1)
    add     s3, s9, s3
    ld      s4, C_RX_LEN(s1)
    mv      a0, s3
    add     a1, s3, s2
    sub     a2, s4, s2
    sd      a2, C_RX_LEN(s1)
    call    libp2p_copy
    j       99f
90: mv      a0, s1
    li      a1, LIBP2P_REASON_HANDSHAKE
    lwu     t0, C_PHASE(s1)
    li      t1, PH_OPEN
    bne     t0, t1, 92f
    li      a1, LIBP2P_REASON_CLOSED
    j       92f
91: mv      a0, s1
    li      a1, LIBP2P_REASON_PEER_ID
92: call    libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_conn_process

/*
 * libp2p_conn_plain(conn, p, n): plaintext of a transport message: multistream
 * messages for the muxer first, then muxer frames.
 */
LOCAL_FUNCTION libp2p_conn_plain
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
1:  beqz    s3, 9f
    lwu     t0, C_PHASE(s1)
    li      t1, PH_MUXER
    bne     t0, t1, 2f
    addi    a0, s1, C_MS_STATE
    li      a1, C_MS_CAP
    mv      a2, s2
    mv      a3, s3
    call    libp2p_ms_take
    add     s2, s2, a0
    sub     s3, s3, a0
    li      t0, 2
    beq     a1, t0, 8f
    beqz    a1, 9f
    mv      a0, s1
    call    libp2p_conn_ms
    j       1b
2:  li      t1, PH_OPEN
    bne     t0, t1, 9f
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    call    libp2p_mux_feed
    add     s2, s2, a0
    sub     s3, s3, a0
    j       1b
8:  mv      a0, s1
    li      a1, LIBP2P_REASON_HANDSHAKE
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_plain

/* libp2p_conn_propose_muxer(conn): the dialer's multistream header and first muxer: yamux when it is on, else mplex. */
LOCAL_FUNCTION libp2p_conn_propose_muxer
    ENTER   0
    mv      s1, a0
    ld      t0, C_FLAGS(s1)
    ori     t0, t0, CF_SENT_HEADER
    CFG     t1, LIBP2P_CFG_MUXERS
    andi    t1, t1, 1
    bnez    t1, 1f
    ori     t0, t0, CF_MPLEX_TRIED
1:  sd      t0, C_FLAGS(s1)
    mv      a0, s1
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_conn_out
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_MPLEX_TRIED
    lla     a1, 433b
    beqz    t0, 2f
    lla     a1, 434b
2:  mv      a0, s1
    li      a2, 13
    call    libp2p_conn_out
    LEAVE   0
END_FUNCTION libp2p_conn_propose_muxer

/*
 * libp2p_conn_ms(conn): one multistream message of the connection, before Noise
 * (for /noise) or after it (for the muxer). The header comes first; then
 * the listener answers proposals and the dialer reads answers.
 * s1 conn, s2 flags, s3 phase, s4 muxers, s5 the muxer answered.
 */
LOCAL_FUNCTION libp2p_conn_ms
    ENTER   0
    mv      s1, a0
    ld      s2, C_FLAGS(s1)
    lwu     s3, C_PHASE(s1)
    andi    t0, s2, CF_GOT_HEADER
    bnez    t0, 2f
    addi    a0, s1, C_MS_STATE              # the header
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_ms_is
    beqz    a0, 80f
    ori     s2, s2, CF_GOT_HEADER
    sd      s2, C_FLAGS(s1)
    andi    t0, s2, CF_SENT_HEADER
    bnez    t0, 70f
    ori     s2, s2, CF_SENT_HEADER
    sd      s2, C_FLAGS(s1)
    mv      a0, s1
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_conn_out
    j       70f
2:  andi    t0, s2, CF_OUTBOUND
    bnez    t0, 40f
    li      t0, PH_SECURITY                 # listener
    bne     s3, t0, 20f
    addi    a0, s1, C_MS_STATE
    lla     a1, 432b
    li      a2, 7
    call    libp2p_ms_is
    beqz    a0, 60f
    mv      a0, s1
    lla     a1, 432b
    li      a2, 7
    call    libp2p_conn_out
    j       30f
20: CFG     s4, LIBP2P_CFG_MUXERS
    andi    t0, s4, 1
    beqz    t0, 21f
    addi    a0, s1, C_MS_STATE
    lla     a1, 433b
    li      a2, 13
    call    libp2p_ms_is
    beqz    a0, 21f
    ori     s2, s2, CF_YAMUX
    lla     s5, 433b
    j       22f
21: andi    t0, s4, 2
    beqz    t0, 60f
    addi    a0, s1, C_MS_STATE
    lla     a1, 434b
    li      a2, 13
    call    libp2p_ms_is
    beqz    a0, 60f
    ori     s2, s2, CF_MPLEX
    lla     s5, 434b
22: sd      s2, C_FLAGS(s1)
    mv      a0, s1
    mv      a1, s5
    li      a2, 13
    call    libp2p_conn_out
    sd      zero, C_MS_LEN(s1)
    mv      a0, s1
    call    libp2p_conn_opened
    j       99f
30: sd      zero, C_MS_LEN(s1)              # /noise selected
    li      t0, PH_NOISE
    sw      t0, C_PHASE(s1)
    mv      a0, s1
    call    libp2p_noise_begin
    j       99f
40: li      t0, PH_SECURITY                 # dialer
    bne     s3, t0, 41f
    addi    a0, s1, C_MS_STATE
    lla     a1, 432b
    li      a2, 7
    call    libp2p_ms_is
    beqz    a0, 80f
    j       30b
41: andi    t0, s2, CF_MPLEX_TRIED
    lla     s5, 433b
    beqz    t0, 43f
    lla     s5, 434b
43: addi    a0, s1, C_MS_STATE
    mv      a1, s5
    li      a2, 13
    call    libp2p_ms_is
    beqz    a0, 42f
    andi    t0, s2, CF_MPLEX_TRIED
    li      t1, CF_YAMUX
    beqz    t0, 44f
    li      t1, CF_MPLEX
44: or      s2, s2, t1
    sd      s2, C_FLAGS(s1)
    sd      zero, C_MS_LEN(s1)
    mv      a0, s1
    call    libp2p_conn_opened
    j       99f
42: addi    a0, s1, C_MS_STATE              # na: mplex next, when yamux was refused and mplex is on
    lla     a1, 431b
    li      a2, 3
    call    libp2p_ms_is
    beqz    a0, 80f
    andi    t0, s2, CF_MPLEX_TRIED
    bnez    t0, 80f
    CFG     t0, LIBP2P_CFG_MUXERS
    andi    t0, t0, 2
    beqz    t0, 80f
    ori     s2, s2, CF_MPLEX_TRIED
    sd      s2, C_FLAGS(s1)
    mv      a0, s1
    lla     a1, 434b
    li      a2, 13
    call    libp2p_conn_out
    j       70f
60: mv      a0, s1                          # not supported
    lla     a1, 431b
    li      a2, 3
    call    libp2p_conn_out
70: sd      zero, C_MS_LEN(s1)
    j       99f
80: mv      a0, s1
    li      a1, LIBP2P_REASON_HANDSHAKE
    call    libp2p_conn_close
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
    mv      s1, a0
    li      t0, PH_OPEN
    sw      t0, C_PHASE(s1)
    ld      t0, C_FLAGS(s1)
    li      t1, 0
    andi    t2, t0, CF_YAMUX
    beqz    t2, 1f
    li      t1, 1
    andi    t2, t0, CF_OUTBOUND
    bnez    t2, 1f
    li      t1, 2
1:  sd      t1, C_MX_NEXT_ID(s1)
    sd      zero, C_MX_HLEN(s1)
    sd      zero, C_MX_REMAIN(s1)
    mv      a0, s1
    call    libp2p_peer_bind
    LEAVE   0
END_FUNCTION libp2p_conn_opened

/* libp2p_peer_find(id, n) -> the peer slot (connected or retained) with the peer ID, or 0. */
LOCAL_FUNCTION libp2p_peer_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    TABLE   s3, ST_PEER_OFF
    ld      s4, ST_PEER_COUNT(s9)
1:  beqz    s4, 8f
    lwu     t0, P_STATE(s3)
    beqz    t0, 2f
    addi    a0, s3, P_ID
    ld      a1, P_ID_LEN(s3)
    mv      a2, s1
    mv      a3, s2
    call    libp2p_compare
    beqz    a0, 2f
    mv      a0, s3
    j       9f
2:  addi    s3, s3, P_SIZE
    addi    s4, s4, -1
    j       1b
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_peer_find

/* libp2p_id_less(a, alen, b, blen) -> 1 when byte string a sorts before b, else 0. A leaf. */
LOCAL_FUNCTION libp2p_id_less
    UNWIND_END_PROLOGUE
    mv      a4, a1
    bltu    a1, a3, 1f
    mv      a4, a3
1:  beqz    a4, 2f
    lbu     a5, 0(a0)
    lbu     a6, 0(a2)
    addi    a0, a0, 1
    addi    a2, a2, 1
    bltu    a5, a6, 7f
    bltu    a6, a5, 8f
    addi    a4, a4, -1
    j       1b
2:  bltu    a1, a3, 7f
8:  li      a0, 0
    ret
7:  li      a0, 1
    ret
END_FUNCTION libp2p_id_less

/* libp2p_peer_conns(peer) -> the open connections bound to the peer. A leaf. */
LOCAL_FUNCTION libp2p_peer_conns
    UNWIND_END_PROLOGUE
    ld      a1, ST_PEER_OFF(s9)
    add     a1, s9, a1
    sub     a1, a0, a1
    li      a2, P_SIZE
    divu    a1, a1, a2
    ld      a2, ST_CONN_OFF(s9)
    add     a2, s9, a2
    ld      a3, ST_CONN_COUNT(s9)
    li      a0, 0
    li      a5, PH_OPEN
1:  beqz    a3, 9f
    lwu     a4, C_PHASE(a2)
    bne     a4, a5, 2f
    ld      a4, C_PEER(a2)
    bne     a4, a1, 2f
    addi    a0, a0, 1
2:  addi    a2, a2, C_SIZE
    addi    a3, a3, -1
    j       1b
9:  ret
END_FUNCTION libp2p_peer_conns

/* libp2p_peer_other(peer index, conn) -> another open connection bound to the peer, or 0. A leaf. */
LOCAL_FUNCTION libp2p_peer_other
    UNWIND_END_PROLOGUE
    ld      a2, ST_CONN_OFF(s9)
    add     a2, s9, a2
    ld      a3, ST_CONN_COUNT(s9)
    li      a5, PH_OPEN
1:  beqz    a3, 8f
    beq     a2, a1, 2f
    lwu     a4, C_PHASE(a2)
    bne     a4, a5, 2f
    ld      a4, C_PEER(a2)
    bne     a4, a0, 2f
    mv      a0, a2
    ret
2:  addi    a2, a2, C_SIZE
    addi    a3, a3, -1
    j       1b
8:  li      a0, 0
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
 * s1 conn, s2 peer, s3 other conn, s4 peer index.
 */
LOCAL_FUNCTION libp2p_peer_bind
    ENTER   0
    mv      s1, a0
    ld      a1, C_EXP_ID_LEN(s1)
    beqz    a1, 1f
    addi    a0, s1, C_EXP_ID
    addi    a2, s1, C_RID
    ld      a3, C_RID_LEN(s1)
    call    libp2p_compare
    beqz    a0, 81f
1:  addi    a0, s9, ST_PEER_ID
    ld      a1, ST_PEER_ID_LEN(s9)
    addi    a2, s1, C_RID
    ld      a3, C_RID_LEN(s1)
    call    libp2p_compare
    bnez    a0, 81f
    addi    a0, s1, C_RID
    ld      a1, C_RID_LEN(s1)
    call    libp2p_peer_find
    mv      s2, a0
    beqz    s2, 4f
    lwu     t0, P_STATE(s2)
    li      t1, PS_CONNECTED
    bne     t0, t1, 3f
    ld      t0, P_CONN(s2)                  # a second connection to the peer
    TABLE   t1, ST_CONN_OFF
    li      t2, C_SIZE
    mul     t0, t0, t2
    add     s3, t1, t0
    ld      t0, C_FLAGS(s1)
    ld      t1, C_FLAGS(s3)
    xor     t2, t0, t1
    andi    t2, t2, CF_OUTBOUND
    beqz    t2, 84f                         # same dialer
    addi    a0, s9, ST_PEER_ID              # is our ID the smaller?
    ld      a1, ST_PEER_ID_LEN(s9)
    addi    a2, s1, C_RID
    ld      a3, C_RID_LEN(s1)
    call    libp2p_id_less
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND             # 1 when we dialled the new one
    bne     a0, t0, 82f                     # the old one has the smaller dialer
    TABLE   t0, ST_PEER_OFF                 # the new one stays: the old one ends, with any secondary connections
    sub     s4, s2, t0
    li      t1, P_SIZE
    divu    s4, s4, t1
85: mv      a0, s4
    mv      a1, s3
    call    libp2p_peer_other
    beqz    a0, 86f
    li      a1, LIBP2P_REASON_DUPLICATE
    call    libp2p_conn_close
    j       85b
86: mv      a0, s3
    li      a1, LIBP2P_REASON_DUPLICATE
    call    libp2p_conn_close
    addi    a0, s1, C_RID
    ld      a1, C_RID_LEN(s1)
    call    libp2p_peer_find
    mv      s2, a0
    beqz    s2, 4f
3:  lwu     t0, P_GEN(s2)                   # a retained peer comes back
    addiw   t0, t0, 1
    sw      t0, P_GEN(s2)
    li      t0, PS_CONNECTED
    sw      t0, P_STATE(s2)
    j       5f
4:  li      a0, ST_PEER_OFF
    li      a1, ST_PEER_COUNT
    li      a2, P_SIZE
    call    libp2p_alloc_slot
    mv      s2, a0
    bnez    s2, 41f
    call    libp2p_peer_evict
    beqz    a0, 83f
    li      a0, ST_PEER_OFF
    li      a1, ST_PEER_COUNT
    li      a2, P_SIZE
    call    libp2p_alloc_slot
    mv      s2, a0
    beqz    s2, 83f
41: addi    a0, s2, P_ID
    addi    a1, s1, C_RID
    ld      a2, C_RID_LEN(s1)
    sd      a2, P_ID_LEN(s2)
    call    libp2p_copy
5:  TABLE   t0, ST_CONN_OFF                 # fill in the peer
    sub     t0, s1, t0
    li      t1, C_SIZE
    divu    t0, t0, t1
    sd      t0, P_CONN(s2)
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND
    sd      t0, P_FLAGS(s2)
    li      t0, NONE
    sd      t0, P_GS_OUT(s2)
    sd      t0, P_GS_IN(s2)
    addi    a0, s2, P_IP
    addi    a1, s1, (C_ADDR + LIBP2P_ADDR_IP)
    li      a2, 16
    call    libp2p_copy
    ld      t0, (C_ADDR + LIBP2P_ADDR_FAMILY)(s1)
    sd      t0, P_IP_FAMILY(s2)
    TABLE   t0, ST_PEER_OFF
    sub     t0, s2, t0
    li      t1, P_SIZE
    divu    t0, t0, t1
    sd      t0, C_PEER(s1)
    ld      t0, C_FLAGS(s1)
    ori     t0, t0, CF_REPORTED
    sd      t0, C_FLAGS(s1)
    li      a0, LIBP2P_ACTION_PEER_CONNECTED
    li      a1, LIBP2P_ACT_PC_SIZE
    call    libp2p_action
    beqz    a0, 6f
    mv      s3, a0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    mv      a2, s2
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_PEER(s3)
    ld      t0, C_TAG(s1)
    sd      t0, LIBP2P_ACT_PC_TAG(s3)
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND
    sd      t0, LIBP2P_ACT_PC_DIRECTION(s3)
    addi    a0, s3, LIBP2P_ACT_PC_ADDR
    addi    a1, s1, C_ADDR
    li      a2, LIBP2P_ADDR_SIZE
    call    libp2p_copy
    ld      a2, P_ID_LEN(s2)
    sd      a2, LIBP2P_ACT_PC_ID_LEN(s3)
    addi    a0, s3, LIBP2P_ACT_PC_ID
    addi    a1, s2, P_ID
    call    libp2p_copy
6:  mv      a0, s2
    call    libp2p_gossip_peer_up
    j       99f
84: ld      t0, C_FLAGS(s1)                 # we dialled the peer again: the new one ends
    andi    t0, t0, CF_OUTBOUND
    bnez    t0, 82f
    mv      a0, s2                          # the peer dialled us again: a secondary connection
    call    libp2p_peer_conns
    li      t0, LIBP2P_PEER_CONNS
    bgeu    a0, t0, 82f
    TABLE   t0, ST_PEER_OFF
    sub     t0, s2, t0
    li      t1, P_SIZE
    divu    t0, t0, t1
    sd      t0, C_PEER(s1)
    ld      t0, C_FLAGS(s1)
    ori     t0, t0, CF_REPORTED
    sd      t0, C_FLAGS(s1)
    j       99f
81: mv      a0, s1
    li      a1, LIBP2P_REASON_PEER_ID
    call    libp2p_conn_close
    j       99f
82: mv      a0, s1
    li      a1, LIBP2P_REASON_DUPLICATE
    call    libp2p_conn_close
    j       99f
83: mv      a0, s1
    li      a1, LIBP2P_REASON_LIMIT
    call    libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_peer_bind

/*
 * libp2p_peer_evict() -> 1 when it freed the retained peer whose score ends
 * first, 0 when no peer is retained.
 */
LOCAL_FUNCTION libp2p_peer_evict
    ENTER   0
    TABLE   s1, ST_PEER_OFF
    ld      s2, ST_PEER_COUNT(s9)
    li      s3, 0
    li      s4, NONE
1:  beqz    s2, 2f
    lwu     t0, P_STATE(s1)
    li      t1, PS_RETAINED
    bne     t0, t1, 11f
    ld      t0, P_EXPIRE(s1)
    bgeu    t0, s4, 11f
    mv      s4, t0
    mv      s3, s1
11: addi    s1, s1, P_SIZE
    addi    s2, s2, -1
    j       1b
2:  li      a0, 0
    beqz    s3, 9f
    mv      a0, s3
    call    libp2p_peer_release
    li      a0, 1
9:  LEAVE   0
END_FUNCTION libp2p_peer_evict

/* libp2p_peer_release(peer): the slot becomes free, and so do its peer x topic entries. */
LOCAL_FUNCTION libp2p_peer_release
    ENTER   0
    mv      s1, a0
    sw      zero, P_STATE(s1)
    TABLE   t0, ST_PEER_OFF
    sub     t0, s1, t0
    li      t1, P_SIZE
    divu    t0, t0, t1
    ld      t1, ST_TOPIC_COUNT(s9)
    mul     t0, t0, t1
    li      t2, PT_SIZE
    mul     t0, t0, t2
    TABLE   a0, ST_PT_OFF
    add     a0, a0, t0
    mul     a1, t1, t2
    call    libp2p_zero
    LEAVE   0
END_FUNCTION libp2p_peer_release

/*
 * libp2p_peer_down(peer): its connection ended: gossipsub forgets it,
 * PEER_DISCONNECTED, then the slot is retained for its score, or freed.
 */
LOCAL_FUNCTION libp2p_peer_down
    ENTER   0
    mv      s1, a0
    call    libp2p_gossip_peer_down
    li      a0, LIBP2P_ACTION_PEER_DISCONNECTED
    li      a1, LIBP2P_ACT_PD_SIZE
    call    libp2p_action
    beqz    a0, 1f
    mv      s2, a0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    mv      a2, s1
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_PEER(s2)
    ld      a2, P_ID_LEN(s1)
    sd      a2, LIBP2P_ACT_PD_ID_LEN(s2)
    addi    a0, s2, LIBP2P_ACT_PD_ID
    addi    a1, s1, P_ID
    call    libp2p_copy
1:  li      t0, NONE
    sd      t0, P_CONN(s1)
    sd      t0, P_GS_OUT(s1)
    sd      t0, P_GS_IN(s1)
    CFG     t0, LIBP2P_CFG_SCORING
    CFG     t1, LIBP2P_CFG_RETAIN_SCORE_MS
    beqz    t0, 2f
    beqz    t1, 2f
    ld      t2, SC_NOW(s10)
    add     t2, t2, t1
    sd      t2, P_EXPIRE(s1)
    li      t0, PS_RETAINED
    sw      t0, P_STATE(s1)
    lwu     t0, P_GEN(s1)                   # old handles no longer work
    addiw   t0, t0, 1
    sw      t0, P_GEN(s1)
    j       9f
2:  mv      a0, s1
    call    libp2p_peer_release
9:  LEAVE   0
END_FUNCTION libp2p_peer_down

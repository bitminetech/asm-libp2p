/*
 * Streams of the RISC-V core: stream slots and queues, multistream-select
 * on each stream, and the stream events of the application. Included by
 * libp2p.s.
 */

/* ---------------------------------------------------------------- Stream slots */

/* libp2p_stream_index(stream) -> its slot index. A leaf. */
LOCAL_FUNCTION libp2p_stream_index
    UNWIND_END_PROLOGUE
    ld      a1, ST_STREAM_OFF(s9)
    add     a1, s9, a1
    sub     a0, a0, a1
    li      a1, S_SIZE
    divu    a0, a0, a1
    ret
END_FUNCTION libp2p_stream_index

/* libp2p_stream_at(index) -> the stream slot of an index. A leaf. */
LOCAL_FUNCTION libp2p_stream_at
    UNWIND_END_PROLOGUE
    ld      a1, ST_STREAM_OFF(s9)
    add     a1, s9, a1
    li      a2, S_SIZE
    mul     a0, a0, a2
    add     a0, a0, a1
    ret
END_FUNCTION libp2p_stream_at

/* libp2p_stream_conn(stream) -> its connection slot. A leaf. */
LOCAL_FUNCTION libp2p_stream_conn
    UNWIND_END_PROLOGUE
    ld      a1, S_CONN(a0)
    ld      a2, ST_CONN_OFF(s9)
    add     a2, s9, a2
    li      a3, C_SIZE
    mul     a0, a1, a3
    add     a0, a0, a2
    ret
END_FUNCTION libp2p_stream_conn

/* libp2p_stream_handle(stream) -> its handle. */
LOCAL_FUNCTION libp2p_stream_handle
    ENTER   0
    mv      a2, a0
    li      a0, ST_STREAM_OFF
    li      a1, S_SIZE
    call    libp2p_handle
    LEAVE   0
END_FUNCTION libp2p_stream_handle

/*
 * libp2p_stream_new(conn, id, local) -> a new stream of the connection with the
 * muxer stream ID, negotiating, with full yamux windows; 0 when the
 * connection has LIBP2P_CONN_STREAMS streams or no slot is free.
 */
LOCAL_FUNCTION libp2p_stream_new
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a0, 0
    ld      t0, C_STREAMS(s1)
    li      t1, LIBP2P_CONN_STREAMS
    bgeu    t0, t1, 9f
    li      a0, ST_STREAM_OFF
    li      a1, ST_STREAM_COUNT
    li      a2, S_SIZE
    call    libp2p_alloc_slot
    beqz    a0, 9f
    mv      s4, a0
    TABLE   t0, ST_CONN_OFF
    sub     t0, s1, t0
    li      t1, C_SIZE
    divu    t0, t0, t1
    sd      t0, S_CONN(s4)
    sd      s2, S_ID(s4)
    li      t0, 0
    beqz    s3, 1f
    li      t0, SF_LOCAL
1:  sd      t0, S_FLAGS(s4)
    ld      t0, C_PEER(s1)
    sd      t0, S_PEER(s4)
    li      t0, LIBP2P_YAMUX_WINDOW
    sd      t0, S_SEND_WIN(s4)
    sd      t0, S_RECV_WIN(s4)
    li      t0, NONE
    sd      t0, S_Q_HEAD(s4)
    sd      t0, S_Q_TAIL(s4)
    sd      t0, S_PREV(s4)
    ld      s6, C_STREAM_HEAD(s1)           # link at the head of the connection's list
    sd      s6, S_NEXT(s4)
    mv      a0, s4
    call    libp2p_stream_index
    mv      s5, a0
    li      t0, NONE
    beq     s6, t0, 2f
    mv      a0, s6
    call    libp2p_stream_at
    sd      s5, S_PREV(a0)
2:  sd      s5, C_STREAM_HEAD(s1)
    ld      t0, C_STREAMS(s1)
    addi    t0, t0, 1
    sd      t0, C_STREAMS(s1)
    mv      a0, s4
9:  LEAVE   0
END_FUNCTION libp2p_stream_new

/*
 * libp2p_stream_free(stream): unlinks the stream from its connection and frees
 * its queue, its RPC buffer and its proposals. A gossipsub stream is taken
 * off its peer.
 * s1 stream, s2 conn, s3 index, s5 next, s6 previous.
 */
LOCAL_FUNCTION libp2p_stream_free
    ENTER   0
    mv      s1, a0
    call    libp2p_stream_conn
    mv      s2, a0
    mv      a0, s1
    call    libp2p_stream_index
    mv      s3, a0
    ld      s5, S_NEXT(s1)
    ld      s6, S_PREV(s1)
    li      t0, NONE
    beq     s6, t0, 1f
    mv      a0, s6
    call    libp2p_stream_at
    sd      s5, S_NEXT(a0)
    j       2f
1:  sd      s5, C_STREAM_HEAD(s2)
2:  li      t0, NONE
    beq     s5, t0, 3f
    mv      a0, s5
    call    libp2p_stream_at
    sd      s6, S_PREV(a0)
3:  ld      t0, C_STREAMS(s2)
    addi    t0, t0, -1
    sd      t0, C_STREAMS(s2)
    li      t1, NONE
    ld      t0, C_CURSOR(s2)
    bne     t0, s3, 4f
    sd      t1, C_CURSOR(s2)
4:  ld      t0, C_MX_STREAM(s2)
    bne     t0, s3, 5f
    sd      t1, C_MX_STREAM(s2)
5:  ld      a0, S_Q_HEAD(s1)                # the queue
    li      t0, NONE
    beq     a0, t0, 6f
    add     t0, s9, a0
    ld      s4, (CH_NEXT - HB_HEADER)(t0)
    call    libp2p_heap_free
    sd      s4, S_Q_HEAD(s1)
    j       5b
6:  ld      a0, S_RPC_BUF(s1)
    call    libp2p_heap_free
    ld      a0, S_PROPOSALS(s1)
    call    libp2p_heap_free
    ld      t0, S_KIND(s1)                  # a gossipsub stream leaves its peer
    li      t1, SK_GOSSIP_IN
    bltu    t0, t1, 8f
    li      t1, SK_GOSSIP_OUT
    bltu    t1, t0, 8f
    ld      t1, S_PEER(s1)
    li      t2, NONE
    beq     t1, t2, 8f
    TABLE   t3, ST_PEER_OFF
    li      t4, P_SIZE
    mul     t1, t1, t4
    add     t3, t3, t1
    ld      t4, P_GS_OUT(t3)
    bne     t4, s3, 7f
    sd      t2, P_GS_OUT(t3)
    ld      t4, P_FLAGS(t3)
    andi    t4, t4, ~(PF_GOSSIP | PF_HELLO | PF_IDONTWANT)
    sd      t4, P_FLAGS(t3)
7:  ld      t4, P_GS_IN(t3)
    bne     t4, s3, 8f
    sd      t2, P_GS_IN(t3)
8:  sw      zero, S_USED(s1)
    LEAVE   0
END_FUNCTION libp2p_stream_free

/*
 * libp2p_stream_kill(stream, reason): the stream ends at once: an application
 * stream gives STREAM_RESET (not when it was closed both ways, as nothing
 * was lost), an application stream still negotiating gives STREAM_FAILED;
 * then the slot is free.
 */
LOCAL_FUNCTION libp2p_stream_kill
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    ld      t0, S_FLAGS(s1)
    ld      t1, S_KIND(s1)
    li      t2, SK_APP
    bne     t1, t2, 1f
    andi    t2, t0, SF_REPORTED
    beqz    t2, 8f
    andi    t2, t0, (SF_FIN_SENT | SF_REMOTE_FIN)   # closed both ways: nothing was lost
    li      t3, (SF_FIN_SENT | SF_REMOTE_FIN)
    beq     t2, t3, 8f
    li      a0, LIBP2P_ACTION_STREAM_RESET
    li      a1, LIBP2P_ACT_STREAM_SIZE
    call    libp2p_action
    beqz    a0, 8f
    mv      s3, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s3)
    j       8f
1:  li      t2, SK_NEGOTIATING
    bne     t1, t2, 8f
    ld      t2, S_TARGET(s1)
    li      t3, SK_APP
    bne     t2, t3, 8f
    andi    t2, t0, SF_LOCAL
    beqz    t2, 8f
    mv      a0, s1
    mv      a1, s2
    call    libp2p_stream_failed
8:  mv      a0, s1
    call    libp2p_stream_free
    LEAVE   0
END_FUNCTION libp2p_stream_kill

/* libp2p_stream_failed(stream, reason): STREAM_FAILED with the tag of an outbound application stream. */
LOCAL_FUNCTION libp2p_stream_failed
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    li      a0, LIBP2P_ACTION_STREAM_FAILED
    li      a1, LIBP2P_ACT_FAILED_SIZE
    call    libp2p_action
    beqz    a0, 9f
    ld      t0, S_TAG(s1)
    sd      t0, LIBP2P_ACT_TAG(a0)
    sd      s2, LIBP2P_ACT_REASON(a0)
9:  LEAVE   0
END_FUNCTION libp2p_stream_failed

/*
 * libp2p_stream_queue(stream, src, n) -> 1 when the n bytes are queued on the
 * stream (one heap chunk), 0 when the heap has no block for them.
 */
LOCAL_FUNCTION libp2p_stream_queue
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a0, 1
    beqz    s3, 9f
    addi    a0, s3, (CH_DATA - HB_HEADER)
    call    libp2p_heap_alloc
    beqz    a0, 9f
    mv      s4, a0                          # the chunk, as a state offset of its payload
    addi    s5, s4, -HB_HEADER
    add     s5, s9, s5                      # the block
    li      t0, NONE
    sd      t0, CH_NEXT(s5)
    sd      s3, CH_LEN(s5)
    sd      zero, CH_DONE(s5)
    addi    a0, s5, CH_DATA
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    ld      t0, S_Q_TAIL(s1)
    li      t1, NONE
    bne     t0, t1, 1f
    sd      s4, S_Q_HEAD(s1)
    j       2f
1:  addi    t0, t0, -HB_HEADER
    add     t0, s9, t0
    sd      s4, CH_NEXT(t0)
2:  sd      s4, S_Q_TAIL(s1)
    ld      t0, S_Q_BYTES(s1)
    add     t0, t0, s3
    sd      t0, S_Q_BYTES(s1)
    li      a0, 1
9:  LEAVE   0
END_FUNCTION libp2p_stream_queue

/* libp2p_stream_ms_out(stream, str, n) -> 1 when the multistream message is queued: varint(n), then the n bytes. */
LOCAL_FUNCTION libp2p_stream_ms_out
    ENTER   0, 160
    mv      s1, a0
    addi    a0, sp, FL
    call    libp2p_ms_put
    addi    a1, sp, FL
    sub     a2, a0, a1
    mv      a0, s1
    call    libp2p_stream_queue
    LEAVE   0, 160
END_FUNCTION libp2p_stream_ms_out

/* libp2p_stream_ms_proto(stream, bytes, n) -> 1 when the message of a protocol ID (n bytes, no newline) is queued. */
LOCAL_FUNCTION libp2p_stream_ms_proto
    ENTER   0, 160
    mv      s1, a0
    addi    a0, sp, FL
    call    libp2p_ms_put_proto
    addi    a1, sp, FL
    sub     a2, a0, a1
    mv      a0, s1
    call    libp2p_stream_queue
    LEAVE   0, 160
END_FUNCTION libp2p_stream_ms_proto

/*
 * libp2p_stream_open(conn, target, tag, proposals, count) -> a new outbound
 * stream that proposes the protocols: its ID is the next of this side, it
 * will send SYN or NewStream, and the multistream header and the first
 * proposal are queued. proposals is a heap block of ProtocolEntry values
 * the stream now owns, or 0 for gossipsub. 0 when it cannot be opened.
 */
LOCAL_FUNCTION libp2p_stream_open
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      a1, C_MX_NEXT_ID(s1)
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_YAMUX
    li      t1, 1
    beqz    t0, 1f
    li      t1, 2
1:  add     t0, a1, t1
    sd      t0, C_MX_NEXT_ID(s1)
    li      a2, 1
    call    libp2p_stream_new
    beqz    a0, 8f
    mv      s6, a0
    ld      t0, S_FLAGS(s6)
    ori     t0, t0, SF_SYN
    sd      t0, S_FLAGS(s6)
    sd      s2, S_TARGET(s6)
    sd      s3, S_TAG(s6)
    sd      s4, S_PROPOSALS(s6)
    sd      s5, S_PROP_COUNT(s6)
    mv      a0, s6
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_stream_ms_out
    beqz    a0, 7f
    mv      a0, s6
    call    libp2p_stream_propose
    beqz    a0, 7f
    mv      a0, s6
    j       9f
7:  mv      a0, s6                          # no heap: the stream goes
    call    libp2p_stream_free
    li      a0, 0
    j       9f
8:  mv      a0, s4
    call    libp2p_heap_free
    li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_stream_open

/*
 * libp2p_gs_proposal(stream) -> the multistream message of the gossipsub
 * proposal at S_PROP_INDEX: /meshsub/1.2.0 first when gossipsub_v12 is on,
 * then /meshsub/1.1.0. Each is 15 bytes. A leaf.
 */
LOCAL_FUNCTION libp2p_gs_proposal
    UNWIND_END_PROLOGUE
    ld      t0, S_PROP_INDEX(a0)
    CFG     t1, LIBP2P_CFG_GOSSIPSUB_V12
    lla     a0, 435b
    bnez    t0, 1f
    beqz    t1, 1f
    lla     a0, 437b
1:  ret
END_FUNCTION libp2p_gs_proposal

/* libp2p_stream_propose(stream) -> 1 when the proposal at S_PROP_INDEX is queued. */
LOCAL_FUNCTION libp2p_stream_propose
    ENTER   0
    mv      s1, a0
    ld      t0, S_PROPOSALS(s1)
    bnez    t0, 1f
    call    libp2p_gs_proposal              # gossipsub
    mv      a1, a0
    mv      a0, s1
    li      a2, 15
    call    libp2p_stream_ms_out
    j       9f
1:  ld      t1, S_PROP_INDEX(s1)
    li      t2, LIBP2P_PROTO_SIZE
    mul     t1, t1, t2
    add     t0, t0, t1
    add     t0, s9, t0
    addi    a1, t0, LIBP2P_PROTO_BYTES
    ld      a2, LIBP2P_PROTO_LEN(t0)
    call    libp2p_stream_ms_proto
9:  LEAVE   0
END_FUNCTION libp2p_stream_propose

/* libp2p_stream_is_proposal(stream) -> 1 when the multistream message of the stream is its current proposal. */
LOCAL_FUNCTION libp2p_stream_is_proposal
    ENTER   0
    mv      s1, a0
    ld      t0, S_PROPOSALS(s1)
    bnez    t0, 1f
    call    libp2p_gs_proposal
    mv      a1, a0
    addi    a0, s1, S_MS_STATE
    li      a2, 15
    call    libp2p_ms_is
    j       9f
1:  ld      t1, S_PROP_INDEX(s1)            # the message is the bytes and a newline
    li      t2, LIBP2P_PROTO_SIZE
    mul     t1, t1, t2
    add     t0, t0, t1
    add     s2, s9, t0
    ld      s3, LIBP2P_PROTO_LEN(s2)
    ld      t0, S_MS_NEED(s1)
    ld      t1, S_MS_LEN(s1)
    sub     t1, t1, t0
    addi    t0, t0, S_MS_BUF
    add     s4, s1, t0                      # the message
    li      a0, 0
    addi    t2, s3, 1
    bne     t1, t2, 9f
    mv      a0, s4
    addi    a1, s2, LIBP2P_PROTO_BYTES
    mv      a2, s3
    call    libp2p_equal
9:  LEAVE   0
END_FUNCTION libp2p_stream_is_proposal

/* libp2p_stream_find_proto(stream) -> the index of the application protocol the message names, or NONE. */
LOCAL_FUNCTION libp2p_stream_find_proto
    ENTER   0
    ld      t0, S_MS_NEED(a0)
    ld      t1, S_MS_LEN(a0)
    sub     s2, t1, t0
    addi    s2, s2, -1                      # without the newline
    addi    t0, t0, S_MS_BUF
    add     s1, a0, t0
    TABLE   s3, ST_PROTO_OFF
    ld      s4, ST_PROTO_COUNT(s9)
    li      s5, 0
1:  bgeu    s5, s4, 8f
    mv      a0, s1
    mv      a1, s2
    addi    a2, s3, LIBP2P_PROTO_BYTES
    ld      a3, LIBP2P_PROTO_LEN(s3)
    call    libp2p_compare
    bnez    a0, 2f
    addi    s3, s3, LIBP2P_PROTO_SIZE
    addi    s5, s5, 1
    j       1b
2:  mv      a0, s5
    j       9f
8:  li      a0, NONE
9:  LEAVE   0
END_FUNCTION libp2p_stream_find_proto

/* ---------------------------------------------------------------- Stream input */

/*
 * libp2p_stream_data(stream, p, n): bytes of the stream from the muxer:
 * multistream messages while it negotiates, then the bytes of its kind:
 * STREAM_DATA for the application, RPCs for gossipsub.
 */
LOCAL_FUNCTION libp2p_stream_data
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
1:  beqz    s3, 9f
    lwu     t0, S_USED(s1)
    beqz    t0, 9f
    ld      t0, S_FLAGS(s1)
    andi    t0, t0, (SF_RST | SF_DEAD)
    bnez    t0, 9f
    ld      t0, S_KIND(s1)
    li      t1, SK_NEGOTIATING
    bne     t0, t1, 2f
    addi    a0, s1, S_MS_STATE
    li      a1, S_MS_CAP
    mv      a2, s2
    mv      a3, s3
    call    libp2p_ms_take
    add     s2, s2, a0
    sub     s3, s3, a0
    li      t0, 2
    beq     a1, t0, 8f
    beqz    a1, 9f
    mv      a0, s1
    call    libp2p_stream_ms
    j       1b
2:  li      t1, SK_APP
    bne     t0, t1, 3f
    addi    a1, s3, (LIBP2P_ACT_SD_DATA + 7)
    andi    a1, a1, -8
    li      a0, LIBP2P_ACTION_STREAM_DATA
    call    libp2p_action
    beqz    a0, 9f
    mv      s4, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s4)
    sd      s3, LIBP2P_ACT_SD_COUNT(s4)
    addi    a0, s4, LIBP2P_ACT_SD_DATA
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
    j       9f
3:  li      t1, SK_GOSSIP_IN
    bne     t0, t1, 9f
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    call    libp2p_gossip_rx
    j       9f
8:  mv      a0, s1                          # not multistream: reset the stream
    li      a1, LIBP2P_REASON_PROTOCOL
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_stream_data

/*
 * libp2p_stream_abort(stream, reason): this side resets the stream: the
 * application hears of it (as libp2p_stream_kill), and RST goes out before the
 * slot is free.
 */
LOCAL_FUNCTION libp2p_stream_abort
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    ld      t0, S_FLAGS(s1)
    ld      t1, S_KIND(s1)
    li      t2, SK_APP
    bne     t1, t2, 1f
    andi    t2, t0, SF_REPORTED
    beqz    t2, 3f
    li      a0, LIBP2P_ACTION_STREAM_RESET
    li      a1, LIBP2P_ACT_STREAM_SIZE
    call    libp2p_action
    beqz    a0, 3f
    mv      s3, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s3)
    j       3f
1:  li      t2, SK_NEGOTIATING
    bne     t1, t2, 3f
    ld      t2, S_TARGET(s1)
    li      t3, SK_APP
    bne     t2, t3, 3f
    andi    t2, t0, SF_LOCAL
    beqz    t2, 3f
    mv      a0, s1
    mv      a1, s2
    call    libp2p_stream_failed
3:  mv      a0, s1
    call    libp2p_stream_reset
    LEAVE   0
END_FUNCTION libp2p_stream_abort

/* libp2p_stream_reset(stream): RST goes out with the next drain, then the slot is free; the queue is dropped. */
LOCAL_FUNCTION libp2p_stream_reset
    ENTER   0
    mv      s1, a0
1:  ld      a0, S_Q_HEAD(s1)
    li      t0, NONE
    beq     a0, t0, 2f
    addi    t0, a0, -HB_HEADER
    add     t0, s9, t0
    ld      s2, CH_NEXT(t0)
    call    libp2p_heap_free
    sd      s2, S_Q_HEAD(s1)
    j       1b
2:  li      t0, NONE
    sd      t0, S_Q_TAIL(s1)
    sd      zero, S_Q_BYTES(s1)
    ld      t0, S_FLAGS(s1)
    ori     t0, t0, SF_RST
    andi    t0, t0, ~SF_REPORTED
    sd      t0, S_FLAGS(s1)
    LEAVE   0
END_FUNCTION libp2p_stream_reset

/*
 * libp2p_stream_ms(stream): one multistream message of a stream. The header
 * comes first (a remote stream answers it with ours). Our stream then reads
 * the answer to its proposal: the same protocol selects it, na moves to the
 * next proposal or fails. A remote stream answers proposals: gossipsub or
 * an application protocol is selected, anything else gets na.
 * s1 stream, s2 flags.
 */
LOCAL_FUNCTION libp2p_stream_ms
    ENTER   0
    mv      s1, a0
    ld      s2, S_FLAGS(s1)
    andi    t0, s2, SF_GOT_HEADER
    bnez    t0, 2f
    addi    a0, s1, S_MS_STATE
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_ms_is
    beqz    a0, 80f
    ori     s2, s2, SF_GOT_HEADER
    sd      s2, S_FLAGS(s1)
    andi    t0, s2, SF_LOCAL
    bnez    t0, 70f
    mv      a0, s1
    lla     a1, 430b
    li      a2, MS_HEADER_LEN
    call    libp2p_stream_ms_out
    j       70f
2:  andi    t0, s2, SF_LOCAL
    beqz    t0, 40f
    mv      a0, s1                          # our stream: the answer
    call    libp2p_stream_is_proposal
    beqz    a0, 30f
    sd      zero, S_MS_LEN(s1)
    ld      t0, S_TARGET(s1)
    sd      t0, S_KIND(s1)
    ld      t1, S_PROP_INDEX(s1)
    sd      t1, S_PROTO(s1)
    li      t2, SK_APP
    bne     t0, t2, 20f
    ori     s2, s2, SF_REPORTED
    sd      s2, S_FLAGS(s1)
    li      a0, LIBP2P_ACTION_STREAM_OPENED
    li      a1, LIBP2P_ACT_SO_SIZE
    call    libp2p_action
    beqz    a0, 99f
    mv      s3, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s3)
    ld      t0, S_TAG(s1)
    sd      t0, LIBP2P_ACT_SO_TAG(s3)
    ld      t0, S_PROTO(s1)
    sd      t0, LIBP2P_ACT_SO_INDEX(s3)
    j       99f
20: mv      a0, s1                          # our gossipsub stream
    call    libp2p_gossip_out_ready
    j       99f
30: addi    a0, s1, S_MS_STATE              # na: the next proposal
    lla     a1, 431b
    li      a2, 3
    call    libp2p_ms_is
    beqz    a0, 80f
    ld      t0, S_PROP_INDEX(s1)
    addi    t0, t0, 1
    ld      t1, S_PROP_COUNT(s1)
    bgeu    t0, t1, 31f
    sd      t0, S_PROP_INDEX(s1)
    mv      a0, s1
    call    libp2p_stream_propose
    j       70f
31: sd      zero, S_MS_LEN(s1)
    mv      a0, s1
    li      a1, LIBP2P_REASON_PROTOCOL
    call    libp2p_stream_abort
    j       99f
40: addi    a0, s1, S_MS_STATE              # a remote stream: a proposal
    lla     a1, 435b
    li      a2, 15
    call    libp2p_ms_is
    lla     s3, 435b
    bnez    a0, 41f
    CFG     t0, LIBP2P_CFG_GOSSIPSUB_V12
    beqz    t0, 50f
    addi    a0, s1, S_MS_STATE
    lla     a1, 437b
    li      a2, 15
    call    libp2p_ms_is
    lla     s3, 437b
    beqz    a0, 50f
41: mv      a0, s1                          # gossipsub: echo the version
    mv      a1, s3
    li      a2, 15
    call    libp2p_stream_ms_out
    sd      zero, S_MS_LEN(s1)
    li      t0, SK_GOSSIP_IN
    sd      t0, S_KIND(s1)
    mv      a0, s1
    call    libp2p_gossip_in_ready
    j       99f
50: addi    a0, s1, S_MS_STATE              # identify
    lla     a1, 436b
    li      a2, 15
    call    libp2p_ms_is
    beqz    a0, 51f
    mv      a0, s1
    lla     a1, 436b
    li      a2, 15
    call    libp2p_stream_ms_out
    sd      zero, S_MS_LEN(s1)
    li      t0, SK_IDENTIFY
    sd      t0, S_KIND(s1)
    mv      a0, s1
    call    libp2p_identify
    j       99f
51: mv      a0, s1
    call    libp2p_stream_find_proto
    li      t0, NONE
    beq     a0, t0, 60f
    mv      s3, a0
    ld      t0, S_MS_NEED(s1)               # echo the message
    addi    t1, t0, S_MS_BUF
    add     a1, s1, t1
    ld      t1, S_MS_LEN(s1)
    sub     a2, t1, t0
    mv      a0, s1
    call    libp2p_stream_ms_out
    sd      zero, S_MS_LEN(s1)
    li      t0, SK_APP
    sd      t0, S_KIND(s1)
    sd      s3, S_PROTO(s1)
    ori     s2, s2, SF_REPORTED
    sd      s2, S_FLAGS(s1)
    li      a0, LIBP2P_ACTION_STREAM_INBOUND
    li      a1, LIBP2P_ACT_SI_SIZE
    call    libp2p_action
    beqz    a0, 99f
    mv      s4, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s4)
    ld      t0, S_PEER(s1)
    TABLE   t1, ST_PEER_OFF
    li      t2, P_SIZE
    mul     t0, t0, t2
    add     a2, t1, t0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_SI_PEER(s4)
    sd      s3, LIBP2P_ACT_SI_PROTOCOL(s4)
    j       99f
60: mv      a0, s1                          # na
    lla     a1, 431b
    li      a2, 3
    call    libp2p_stream_ms_out
70: sd      zero, S_MS_LEN(s1)
    j       99f
80: sd      zero, S_MS_LEN(s1)
    mv      a0, s1
    li      a1, LIBP2P_REASON_PROTOCOL
    call    libp2p_stream_abort
99: LEAVE   0
END_FUNCTION libp2p_stream_ms

/*
 * libp2p_stream_remote_fin(stream): the peer closed its side: STREAM_EOF for the
 * application. A stream whose FIN already went out is closed both ways: it
 * is dead, and the next drain frees it.
 */
LOCAL_FUNCTION libp2p_stream_remote_fin
    ENTER   0
    mv      s1, a0
    ld      t0, S_FLAGS(s1)
    andi    t1, t0, SF_REMOTE_FIN
    bnez    t1, 9f
    ori     t0, t0, SF_REMOTE_FIN
    andi    t1, t0, SF_FIN_SENT             # closed both ways: the drain frees it
    beqz    t1, 3f
    ori     t0, t0, SF_DEAD
3:  sd      t0, S_FLAGS(s1)
    ld      t1, S_KIND(s1)
    li      t2, SK_APP
    bne     t1, t2, 1f
    andi    t2, t0, SF_REPORTED
    beqz    t2, 9f
    li      a0, LIBP2P_ACTION_STREAM_EOF
    li      a1, LIBP2P_ACT_STREAM_SIZE
    call    libp2p_action
    beqz    a0, 9f
    mv      s2, a0
    mv      a0, s1
    call    libp2p_stream_handle
    sd      a0, LIBP2P_ACT_STREAM(s2)
    j       9f
1:  li      t2, SK_GOSSIP_IN                # the peer closed its gossipsub stream: close ours of it too
    beq     t1, t2, 2f
    li      t2, SK_NEGOTIATING
    bne     t1, t2, 9f
2:  ori     t0, t0, SF_FIN
    sd      t0, S_FLAGS(s1)
9:  LEAVE   0
END_FUNCTION libp2p_stream_remote_fin

/* ---------------------------------------------------------------- Application stream events */

/*
 * libp2p_on_open_stream(event): an outbound application stream to a connected
 * peer, proposing the protocols in order; STREAM_FAILED when the peer is
 * not connected or no slot or heap block is free.
 * s1 event, s2 conn, s3 reason, s4 count, s5 proposals.
 */
LOCAL_FUNCTION libp2p_on_open_stream
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_PEER(s1)
    call    libp2p_peer
    li      s3, LIBP2P_REASON_NO_PEER
    beqz    a0, 8f
    ld      t0, P_CONN(a0)
    TABLE   t1, ST_CONN_OFF
    li      t2, C_SIZE
    mul     t0, t0, t2
    add     s2, t1, t0
    lwu     t0, C_PHASE(s2)
    li      t1, PH_OPEN
    bne     t0, t1, 8f
    li      s3, LIBP2P_REASON_LIMIT
    ld      s4, LIBP2P_EV_OPEN_COUNT(s1)
    li      t0, LIBP2P_PROTO_SIZE
    mul     a0, s4, t0
    call    libp2p_heap_alloc
    beqz    a0, 8f
    mv      s5, a0
    add     a0, s9, s5
    addi    a1, s1, LIBP2P_EV_OPEN_PROTOCOLS
    li      t0, LIBP2P_PROTO_SIZE
    mul     a2, s4, t0
    call    libp2p_copy
    mv      a0, s2
    li      a1, SK_APP
    ld      a2, LIBP2P_EV_OPEN_TAG(s1)
    mv      a3, s5
    mv      a4, s4
    call    libp2p_stream_open
    bnez    a0, 9f
8:  li      a0, LIBP2P_ACTION_STREAM_FAILED
    li      a1, LIBP2P_ACT_FAILED_SIZE
    call    libp2p_action
    beqz    a0, 9f
    ld      t0, LIBP2P_EV_OPEN_TAG(s1)
    sd      t0, LIBP2P_ACT_TAG(a0)
    sd      s3, LIBP2P_ACT_REASON(a0)
9:  LEAVE   0
END_FUNCTION libp2p_on_open_stream

/* libp2p_app_stream(handle) -> the application stream of a handle that may still send, or 0. */
LOCAL_FUNCTION libp2p_app_stream
    ENTER   0
    call    libp2p_stream
    beqz    a0, 9f
    ld      t0, S_KIND(a0)
    li      t1, SK_APP
    bne     t0, t1, 8f
    ld      t0, S_FLAGS(a0)
    andi    t0, t0, SF_REPORTED
    bnez    t0, 9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_app_stream

/*
 * libp2p_on_stream_write(event): bytes for an application stream, queued; a
 * stream whose queue would pass the limit, or that the heap cannot hold,
 * is reset (STREAM_RESET).
 */
LOCAL_FUNCTION libp2p_on_stream_write
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_STREAM(s1)
    call    libp2p_app_stream
    beqz    a0, 9f
    mv      s2, a0
    ld      t0, S_FLAGS(s2)
    andi    t0, t0, (SF_FIN | SF_RST)
    bnez    t0, 9f
    ld      s3, LIBP2P_EV_STREAM_COUNT(s1)
    ld      t0, S_Q_BYTES(s2)
    add     t0, t0, s3
    CFG     t1, LIBP2P_CFG_STREAM_QUEUE
    bltu    t1, t0, 8f
    mv      a0, s2
    addi    a1, s1, LIBP2P_EV_STREAM_DATA
    mv      a2, s3
    call    libp2p_stream_queue
    bnez    a0, 9f
8:  mv      a0, s2
    li      a1, LIBP2P_REASON_LIMIT
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_write

/* libp2p_on_stream_close(event): the application closes its side of a stream: FIN after the queue. */
LOCAL_FUNCTION libp2p_on_stream_close
    ENTER   0
    ld      a0, LIBP2P_EV_STREAM(a0)
    call    libp2p_app_stream
    beqz    a0, 9f
    ld      t0, S_FLAGS(a0)
    ori     t0, t0, SF_FIN
    sd      t0, S_FLAGS(a0)
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_close

/* libp2p_on_stream_reset(event): the application resets a stream: RST goes out, nothing comes back. */
LOCAL_FUNCTION libp2p_on_stream_reset
    ENTER   0
    ld      a0, LIBP2P_EV_STREAM(a0)
    call    libp2p_app_stream
    beqz    a0, 9f
    call    libp2p_stream_reset
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_reset

/* ---------------------------------------------------------------- identify (/ipfs/id/1.0.0) */

/* libp2p_stream_append(stream, chunk): a send chunk (a state offset, its length set) goes on the queue of the stream. A leaf. */
LOCAL_FUNCTION libp2p_stream_append
    UNWIND_END_PROLOGUE
    addi    a2, a1, -HB_HEADER
    add     a2, s9, a2
    ld      a3, S_Q_TAIL(a0)
    li      a4, NONE
    bne     a3, a4, 1f
    sd      a1, S_Q_HEAD(a0)
    j       2f
1:  addi    a3, a3, -HB_HEADER
    add     a3, s9, a3
    sd      a1, CH_NEXT(a3)
2:  sd      a1, S_Q_TAIL(a0)
    ld      a3, S_Q_BYTES(a0)
    ld      a4, CH_LEN(a2)
    add     a3, a3, a4
    sd      a3, S_Q_BYTES(a0)
    ret
END_FUNCTION libp2p_stream_append

/*
 * libp2p_observed(dst, addr) -> the length of the binary multiaddr of the
 * address: /ip4 (code 4, 4 bytes) or /ip6 (code 41, 16 bytes), then /tcp
 * (code 6, the port big endian). A leaf. dst may be unaligned: bytes only.
 */
LOCAL_FUNCTION libp2p_observed
    UNWIND_END_PROLOGUE
    mv      a2, a0
    ld      a3, LIBP2P_ADDR_FAMILY(a1)
    li      a4, 4                           # /ip4: 4 bytes
    li      a5, 4
    li      a6, 6
    bne     a3, a6, 1f
    li      a4, 41                          # /ip6: 16 bytes
    li      a5, 16
1:  sb      a4, 0(a2)
    addi    a2, a2, 1
    addi    a3, a1, LIBP2P_ADDR_IP
2:  lbu     a4, 0(a3)
    sb      a4, 0(a2)
    addi    a3, a3, 1
    addi    a2, a2, 1
    addi    a5, a5, -1
    bnez    a5, 2b
    li      a4, 6
    sb      a4, 0(a2)
    ld      a4, LIBP2P_ADDR_PORT(a1)
    srli    a5, a4, 8
    sb      a5, 1(a2)
    sb      a4, 2(a2)
    addi    a2, a2, 3
    sub     a0, a2, a0
    ret
END_FUNCTION libp2p_observed

/*
 * libp2p_identify(stream): the Identify message on a stream the peer opened
 * with /ipfs/id/1.0.0, varint-length prefixed, then FIN: publicKey (1),
 * observedAddr (4), protocols (3): identify, gossipsub (/meshsub/1.2.0 too
 * when gossipsub_v12 is on) and the application protocols, then
 * protocolVersion (5) and agentVersion (6) when the config has them.
 * s1 stream, s2 size, s3 key length, s4 observed length, s6 chunk,
 * s7 protocol, s8 protocols left. Key at sp + FL, observed at sp + FL + 48.
 */
LOCAL_FUNCTION libp2p_identify
    ENTER   0, 80
    mv      s1, a0
    addi    a0, sp, FL
    ld      a1, ST_KEY_TYPE(s9)
    addi    a2, s9, ST_PUBLIC_KEY
    ld      a3, ST_PUBLIC_LEN(s9)
    call    libp2p_key_proto
    addi    t0, sp, FL
    sub     s3, a0, t0
    mv      a0, s1
    call    libp2p_stream_conn
    addi    a1, a0, C_ADDR
    addi    a0, sp, (FL + 48)
    call    libp2p_observed
    mv      s4, a0
    li      a0, 1                           # the size
    mv      a1, s3
    call    libp2p_pb_size
    mv      s2, a0
    li      a0, 4
    mv      a1, s4
    call    libp2p_pb_size
    add     s2, s2, a0
    li      a0, 3
    li      a1, 14
    call    libp2p_pb_size
    CFG     t0, LIBP2P_CFG_GOSSIPSUB_V12    # and /meshsub/1.2.0
    mul     t0, a0, t0
    add     s2, s2, t0
    slli    a0, a0, 1                       # identify and gossipsub: 14 bytes each
    add     s2, s2, a0
    TABLE   s7, ST_PROTO_OFF
    ld      s8, ST_PROTO_COUNT(s9)
1:  beqz    s8, 2f
    li      a0, 3
    ld      a1, LIBP2P_PROTO_LEN(s7)
    call    libp2p_pb_size
    add     s2, s2, a0
    addi    s7, s7, LIBP2P_PROTO_SIZE
    addi    s8, s8, -1
    j       1b
2:  CFG     a1, LIBP2P_CFG_PV_LEN
    beqz    a1, 3f
    li      a0, 5
    call    libp2p_pb_size
    add     s2, s2, a0
3:  CFG     a1, LIBP2P_CFG_AGENT_LEN
    beqz    a1, 4f
    li      a0, 6
    call    libp2p_pb_size
    add     s2, s2, a0
4:  mv      a0, s2
    call    libp2p_varint_len
    add     a0, a0, s2
    call    libp2p_gs_alloc
    beqz    a0, 9f
    mv      s6, a1
    mv      a1, s2
    call    libp2p_varint_put
    li      a1, 1
    addi    a2, sp, FL
    mv      a3, s3
    call    libp2p_pb_bytes
    li      a1, 4
    addi    a2, sp, (FL + 48)
    mv      a3, s4
    call    libp2p_pb_bytes
    li      a1, 3
    lla     a2, 436b
    li      a3, 14
    call    libp2p_pb_bytes
    CFG     t0, LIBP2P_CFG_GOSSIPSUB_V12
    beqz    t0, 41f
    li      a1, 3
    lla     a2, 437b
    li      a3, 14
    call    libp2p_pb_bytes
41: li      a1, 3
    lla     a2, 435b
    li      a3, 14
    call    libp2p_pb_bytes
    TABLE   s7, ST_PROTO_OFF
    ld      s8, ST_PROTO_COUNT(s9)
5:  beqz    s8, 6f
    li      a1, 3
    addi    a2, s7, LIBP2P_PROTO_BYTES
    ld      a3, LIBP2P_PROTO_LEN(s7)
    call    libp2p_pb_bytes
    addi    s7, s7, LIBP2P_PROTO_SIZE
    addi    s8, s8, -1
    j       5b
6:  CFG     a3, LIBP2P_CFG_PV_LEN
    beqz    a3, 7f
    li      a1, 5
    addi    a2, s9, (ST_CONFIG + LIBP2P_CFG_PV)
    call    libp2p_pb_bytes
7:  CFG     a3, LIBP2P_CFG_AGENT_LEN
    beqz    a3, 8f
    li      a1, 6
    addi    a2, s9, (ST_CONFIG + LIBP2P_CFG_AGENT)
    call    libp2p_pb_bytes
8:  mv      a0, s1
    mv      a1, s6
    call    libp2p_stream_append
9:  ld      t0, S_FLAGS(s1)                 # then FIN
    ori     t0, t0, SF_FIN
    sd      t0, S_FLAGS(s1)
    LEAVE   0, 80
END_FUNCTION libp2p_identify

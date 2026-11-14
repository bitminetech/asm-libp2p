/*
 * Streams of the ARM64 core: stream slots and queues, multistream-select on
 * each stream, and the stream events of the application. Included by
 * libp2p.s.
 */

/* ---------------------------------------------------------------- Stream slots */

/* libp2p_stream_index(stream) -> its slot index. A leaf. */
LOCAL_FUNCTION libp2p_stream_index
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_STREAM_OFF]
    add     x1, x27, x1
    sub     x0, x0, x1
    mov     x1, #S_SIZE
    udiv    x0, x0, x1
    ret
END_FUNCTION libp2p_stream_index

/* libp2p_stream_at(index) -> the stream slot of an index. A leaf. */
LOCAL_FUNCTION libp2p_stream_at
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_STREAM_OFF]
    add     x1, x27, x1
    mov     x2, #S_SIZE
    madd    x0, x0, x2, x1
    ret
END_FUNCTION libp2p_stream_at

/* libp2p_stream_conn(stream) -> its connection slot. A leaf. */
LOCAL_FUNCTION libp2p_stream_conn
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #S_CONN]
    ldr     x2, [x27, #ST_CONN_OFF]
    add     x2, x27, x2
    mov     x3, #C_SIZE
    madd    x0, x1, x3, x2
    ret
END_FUNCTION libp2p_stream_conn

/* libp2p_stream_handle(stream) -> its handle. */
LOCAL_FUNCTION libp2p_stream_handle
    ENTER   0
    mov     x2, x0
    mov     x0, #ST_STREAM_OFF
    mov     x1, #S_SIZE
    bl      libp2p_handle
    LEAVE   0
END_FUNCTION libp2p_stream_handle

/*
 * libp2p_stream_new(conn, id, local) -> a new stream of the connection with the
 * muxer stream ID, negotiating, with full yamux windows; 0 when the
 * connection has LIBP2P_CONN_STREAMS streams or no slot is free.
 */
LOCAL_FUNCTION libp2p_stream_new
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, #0
    ldr     x9, [x19, #C_STREAMS]
    cmp     x9, #LIBP2P_CONN_STREAMS
    b.hs    9f
    MOV64   x0, ST_STREAM_OFF
    MOV64   x1, ST_STREAM_COUNT
    mov     x2, #S_SIZE
    bl      libp2p_alloc_slot
    cbz     x0, 9f
    mov     x22, x0
    TABLE   x9, ST_CONN_OFF
    sub     x9, x19, x9
    mov     x10, #C_SIZE
    udiv    x9, x9, x10
    str     x9, [x22, #S_CONN]
    str     x20, [x22, #S_ID]
    mov     x9, #SF_LOCAL
    cmp     x21, #0
    csel    x9, x9, xzr, ne
    str     x9, [x22, #S_FLAGS]
    ldr     x9, [x19, #C_PEER]
    str     x9, [x22, #S_PEER]
    mov     x9, #LIBP2P_YAMUX_WINDOW
    str     x9, [x22, #S_SEND_WIN]
    str     x9, [x22, #S_RECV_WIN]
    mov     x9, #NONE
    str     x9, [x22, #S_Q_HEAD]
    str     x9, [x22, #S_Q_TAIL]
    str     x9, [x22, #S_PREV]
    ldr     x10, [x19, #C_STREAM_HEAD]      /* link at the head of the connection's list */
    str     x10, [x22, #S_NEXT]
    mov     x0, x22
    bl      libp2p_stream_index
    mov     x23, x0
    cmn     x10, #1
    b.eq    1f
    mov     x0, x10
    bl      libp2p_stream_at
    str     x23, [x0, #S_PREV]
1:  str     x23, [x19, #C_STREAM_HEAD]
    ldr     x9, [x19, #C_STREAMS]
    add     x9, x9, #1
    str     x9, [x19, #C_STREAMS]
    mov     x0, x22
9:  LEAVE   0
END_FUNCTION libp2p_stream_new

/*
 * libp2p_stream_free(stream): unlinks the stream from its connection and frees
 * its queue, its RPC buffer and its proposals. A gossipsub stream is taken
 * off its peer.
 */
LOCAL_FUNCTION libp2p_stream_free
    ENTER   0
    mov     x19, x0
    bl      libp2p_stream_conn
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_stream_index
    mov     x21, x0
    ldr     x9, [x19, #S_NEXT]
    ldr     x10, [x19, #S_PREV]
    cmn     x10, #1
    b.eq    1f
    mov     x0, x10
    bl      libp2p_stream_at
    str     x9, [x0, #S_NEXT]
    b       2f
1:  str     x9, [x20, #C_STREAM_HEAD]
2:  cmn     x9, #1
    b.eq    3f
    mov     x0, x9
    bl      libp2p_stream_at
    str     x10, [x0, #S_PREV]
3:  ldr     x9, [x20, #C_STREAMS]
    sub     x9, x9, #1
    str     x9, [x20, #C_STREAMS]
    ldr     x9, [x20, #C_CURSOR]
    cmp     x9, x21
    b.ne    4f
    mov     x9, #NONE
    str     x9, [x20, #C_CURSOR]
4:  ldr     x9, [x20, #C_MX_STREAM]
    cmp     x9, x21
    b.ne    5f
    mov     x9, #NONE
    str     x9, [x20, #C_MX_STREAM]
5:  ldr     x0, [x19, #S_Q_HEAD]            /* the queue */
    cmn     x0, #1
    b.eq    6f
    add     x9, x27, x0
    ldr     x22, [x9, #(CH_NEXT - HB_HEADER)]
    bl      libp2p_heap_free
    str     x22, [x19, #S_Q_HEAD]
    b       5b
6:  ldr     x0, [x19, #S_RPC_BUF]
    bl      libp2p_heap_free
    ldr     x0, [x19, #S_PROPOSALS]
    bl      libp2p_heap_free
    ldr     x9, [x19, #S_KIND]              /* a gossipsub stream leaves its peer */
    cmp     x9, #SK_GOSSIP_IN
    b.lo    8f
    cmp     x9, #SK_GOSSIP_OUT
    b.hi    8f
    ldr     x10, [x19, #S_PEER]
    cmn     x10, #1
    b.eq    8f
    TABLE   x11, ST_PEER_OFF
    mov     x12, #P_SIZE
    madd    x11, x10, x12, x11
    ldr     x12, [x11, #P_GS_OUT]
    cmp     x12, x21
    b.ne    7f
    mov     x12, #NONE
    str     x12, [x11, #P_GS_OUT]
    ldr     x12, [x11, #P_FLAGS]
    and     x12, x12, #~(PF_GOSSIP | PF_HELLO | PF_IDONTWANT)
    str     x12, [x11, #P_FLAGS]
7:  ldr     x12, [x11, #P_GS_IN]
    cmp     x12, x21
    b.ne    8f
    mov     x12, #NONE
    str     x12, [x11, #P_GS_IN]
8:  str     wzr, [x19, #S_USED]
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
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x19, #S_FLAGS]
    ldr     x10, [x19, #S_KIND]
    cmp     x10, #SK_APP
    b.ne    1f
    tst     x9, #SF_REPORTED
    b.eq    8f
    mov     x11, #(SF_FIN_SENT | SF_REMOTE_FIN)
    bics    xzr, x11, x9                    /* closed both ways: nothing was lost */
    b.eq    8f
    mov     x0, #LIBP2P_ACTION_STREAM_RESET
    mov     x1, #LIBP2P_ACT_STREAM_SIZE
    bl      libp2p_action
    cbz     x0, 8f
    mov     x21, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x21, #LIBP2P_ACT_STREAM]
    b       8f
1:  cmp     x10, #SK_NEGOTIATING
    b.ne    8f
    ldr     x11, [x19, #S_TARGET]
    cmp     x11, #SK_APP
    b.ne    8f
    tst     x9, #SF_LOCAL
    b.eq    8f
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_stream_failed
8:  mov     x0, x19
    bl      libp2p_stream_free
    LEAVE   0
END_FUNCTION libp2p_stream_kill

/* libp2p_stream_failed(stream, reason): STREAM_FAILED with the tag of an outbound application stream. */
LOCAL_FUNCTION libp2p_stream_failed
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, #LIBP2P_ACTION_STREAM_FAILED
    mov     x1, #LIBP2P_ACT_FAILED_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    ldr     x9, [x19, #S_TAG]
    str     x9, [x0, #LIBP2P_ACT_TAG]
    str     x20, [x0, #LIBP2P_ACT_REASON]
9:  LEAVE   0
END_FUNCTION libp2p_stream_failed

/*
 * libp2p_stream_queue(stream, src, n) -> 1 when the n bytes are queued on the
 * stream (one heap chunk), 0 when the heap has no block for them.
 */
LOCAL_FUNCTION libp2p_stream_queue
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, #1
    cbz     x21, 9f
    add     x0, x21, #(CH_DATA - HB_HEADER)
    bl      libp2p_heap_alloc
    cbz     x0, 9f
    mov     x22, x0                         /* the chunk, as a state offset of its payload */
    sub     x23, x22, #HB_HEADER
    add     x23, x27, x23                   /* the block */
    mov     x9, #NONE
    str     x9, [x23, #CH_NEXT]
    str     x21, [x23, #CH_LEN]
    str     xzr, [x23, #CH_DONE]
    add     x0, x23, #CH_DATA
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    ldr     x9, [x19, #S_Q_TAIL]
    cmn     x9, #1
    b.ne    1f
    str     x22, [x19, #S_Q_HEAD]
    b       2f
1:  sub     x9, x9, #HB_HEADER
    add     x9, x27, x9
    str     x22, [x9, #CH_NEXT]
2:  str     x22, [x19, #S_Q_TAIL]
    ldr     x9, [x19, #S_Q_BYTES]
    add     x9, x9, x21
    str     x9, [x19, #S_Q_BYTES]
    mov     x0, #1
9:  LEAVE   0
END_FUNCTION libp2p_stream_queue

/* libp2p_stream_ms_out(stream, str, n) -> 1 when the multistream message is queued: varint(n), then the n bytes. */
LOCAL_FUNCTION libp2p_stream_ms_out
    ENTER   0, 160
    mov     x19, x0
    mov     x20, x2
    mov     x9, x1
    mov     x0, sp
    mov     x1, x9
    bl      libp2p_ms_put
    mov     x2, sp
    sub     x2, x0, x2
    mov     x0, x19
    mov     x1, sp
    bl      libp2p_stream_queue
    LEAVE   0, 160
END_FUNCTION libp2p_stream_ms_out

/* libp2p_stream_ms_proto(stream, bytes, n) -> 1 when the message of a protocol ID (n bytes, no newline) is queued. */
LOCAL_FUNCTION libp2p_stream_ms_proto
    ENTER   0, 160
    mov     x19, x0
    mov     x9, x1
    mov     x0, sp
    mov     x1, x9
    bl      libp2p_ms_put_proto
    mov     x2, sp
    sub     x2, x0, x2
    mov     x0, x19
    mov     x1, sp
    bl      libp2p_stream_queue
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x1, [x19, #C_MX_NEXT_ID]
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_YAMUX
    mov     x10, #1
    mov     x11, #2
    csel    x10, x11, x10, ne
    add     x9, x1, x10
    str     x9, [x19, #C_MX_NEXT_ID]
    mov     x2, #1
    bl      libp2p_stream_new
    cbz     x0, 8f
    mov     x24, x0
    ldr     x9, [x24, #S_FLAGS]
    orr     x9, x9, #SF_SYN
    str     x9, [x24, #S_FLAGS]
    str     x20, [x24, #S_TARGET]
    str     x21, [x24, #S_TAG]
    str     x22, [x24, #S_PROPOSALS]
    str     x23, [x24, #S_PROP_COUNT]
    mov     x0, x24
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_stream_ms_out
    cbz     x0, 7f
    mov     x0, x24
    bl      libp2p_stream_propose
    cbz     x0, 7f
    mov     x0, x24
    b       9f
7:  mov     x0, x24                         /* no heap: the stream goes */
    bl      libp2p_stream_free
    mov     x0, #0
    b       9f
8:  mov     x0, x22
    bl      libp2p_heap_free
    mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_stream_open

/*
 * libp2p_gs_proposal(stream) -> the multistream message of the gossipsub
 * proposal at S_PROP_INDEX: /meshsub/1.3.0 first when gossipsub_v13 is on,
 * /meshsub/1.2.0 next when gossipsub_v12 is on, then /meshsub/1.1.0. Each
 * is 15 bytes. A leaf.
 */
LOCAL_FUNCTION libp2p_gs_proposal
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #S_PROP_INDEX]
    CFG     x10, LIBP2P_CFG_GOSSIPSUB_V12
    CFG     x11, LIBP2P_CFG_GOSSIPSUB_V13
    add     x12, x10, x11                   /* the index of /meshsub/1.1.0 */
    adr     x0, 435b
    cmp     x9, x12
    b.hs    1f
    adr     x0, 437b
    cbnz    x9, 1f
    cbz     x11, 1f
    adr     x0, 438b
1:  ret
END_FUNCTION libp2p_gs_proposal

/* libp2p_stream_propose(stream) -> 1 when the proposal at S_PROP_INDEX is queued. */
LOCAL_FUNCTION libp2p_stream_propose
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #S_PROPOSALS]
    cbnz    x9, 1f
    bl      libp2p_gs_proposal              /* gossipsub */
    mov     x1, x0
    mov     x0, x19
    mov     x2, #15
    bl      libp2p_stream_ms_out
    b       9f
1:  ldr     x10, [x19, #S_PROP_INDEX]
    mov     x11, #LIBP2P_PROTO_SIZE
    madd    x9, x10, x11, x9
    add     x9, x27, x9
    add     x1, x9, #LIBP2P_PROTO_BYTES
    ldr     x2, [x9, #LIBP2P_PROTO_LEN]
    bl      libp2p_stream_ms_proto
9:  LEAVE   0
END_FUNCTION libp2p_stream_propose

/* libp2p_stream_is_proposal(stream) -> 1 when the multistream message of the stream is its current proposal. */
LOCAL_FUNCTION libp2p_stream_is_proposal
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #S_PROPOSALS]
    cbnz    x9, 1f
    bl      libp2p_gs_proposal
    mov     x1, x0
    add     x0, x19, #S_MS_STATE
    mov     x2, #15
    bl      libp2p_ms_is
    b       9f
1:  ldr     x10, [x19, #S_PROP_INDEX]       /* the message is the bytes and a newline */
    mov     x11, #LIBP2P_PROTO_SIZE
    madd    x9, x10, x11, x9
    add     x20, x27, x9
    ldr     x21, [x20, #LIBP2P_PROTO_LEN]
    ldr     x9, [x19, #S_MS_NEED]
    ldr     x10, [x19, #S_MS_LEN]
    sub     x10, x10, x9
    add     x9, x9, #S_MS_BUF
    add     x22, x19, x9                    /* the message */
    mov     x0, #0
    add     x11, x21, #1
    cmp     x10, x11
    b.ne    9f
    mov     x0, x22
    add     x1, x20, #LIBP2P_PROTO_BYTES
    mov     x2, x21
    bl      libp2p_equal
9:  LEAVE   0
END_FUNCTION libp2p_stream_is_proposal

/* libp2p_stream_find_proto(stream) -> the index of the application protocol the message names, or NONE. */
LOCAL_FUNCTION libp2p_stream_find_proto
    ENTER   0
    ldr     x9, [x0, #S_MS_NEED]
    ldr     x10, [x0, #S_MS_LEN]
    sub     x20, x10, x9
    sub     x20, x20, #1                    /* without the newline */
    add     x9, x9, #S_MS_BUF
    add     x19, x0, x9
    TABLE   x21, ST_PROTO_OFF
    ldr     x22, [x27, #ST_PROTO_COUNT]
    mov     x23, #0
1:  cmp     x23, x22
    b.hs    8f
    mov     x0, x19
    mov     x1, x20
    add     x2, x21, #LIBP2P_PROTO_BYTES
    ldr     x3, [x21, #LIBP2P_PROTO_LEN]
    bl      libp2p_compare
    cbnz    x0, 2f
    add     x21, x21, #LIBP2P_PROTO_SIZE
    add     x23, x23, #1
    b       1b
2:  mov     x0, x23
    b       9f
8:  mov     x0, #NONE
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x21, 9f
    ldr     w9, [x19, #S_USED]
    cbz     w9, 9f
    ldr     x9, [x19, #S_FLAGS]
    mov     x10, #(SF_RST | SF_DEAD)
    tst     x9, x10
    b.ne    9f
    ldr     x9, [x19, #S_KIND]
    cmp     x9, #SK_NEGOTIATING
    b.ne    2f
    add     x0, x19, #S_MS_STATE
    mov     x1, #S_MS_CAP
    mov     x2, x20
    mov     x3, x21
    bl      libp2p_ms_take
    add     x20, x20, x0
    sub     x21, x21, x0
    cmp     x1, #2
    b.eq    8f
    cbz     x1, 9f
    mov     x0, x19
    bl      libp2p_stream_ms
    b       1b
2:  cmp     x9, #SK_APP
    b.ne    3f
    add     x1, x21, #(LIBP2P_ACT_SD_DATA + 7)
    and     x1, x1, #~7
    mov     x0, #LIBP2P_ACTION_STREAM_DATA
    bl      libp2p_action
    cbz     x0, 9f
    mov     x22, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x22, #LIBP2P_ACT_STREAM]
    str     x21, [x22, #LIBP2P_ACT_SD_COUNT]
    add     x0, x22, #LIBP2P_ACT_SD_DATA
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
    b       9f
3:  cmp     x9, #SK_GOSSIP_IN
    b.ne    9f
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_gossip_rx
    b       9f
8:  mov     x0, x19                         /* not multistream: reset the stream */
    mov     x1, #LIBP2P_REASON_PROTOCOL
    bl      libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_stream_data

/*
 * libp2p_stream_abort(stream, reason): this side resets the stream: the
 * application hears of it (as libp2p_stream_kill), and RST goes out before the
 * slot is free.
 */
LOCAL_FUNCTION libp2p_stream_abort
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x19, #S_FLAGS]
    ldr     x10, [x19, #S_KIND]
    cmp     x10, #SK_APP
    b.ne    1f
    tst     x9, #SF_REPORTED
    b.eq    3f
    mov     x0, #LIBP2P_ACTION_STREAM_RESET
    mov     x1, #LIBP2P_ACT_STREAM_SIZE
    bl      libp2p_action
    cbz     x0, 3f
    mov     x21, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x21, #LIBP2P_ACT_STREAM]
    b       3f
1:  cmp     x10, #SK_NEGOTIATING
    b.ne    3f
    ldr     x11, [x19, #S_TARGET]
    cmp     x11, #SK_APP
    b.ne    3f
    tst     x9, #SF_LOCAL
    b.eq    3f
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_stream_failed
3:  mov     x0, x19
    bl      libp2p_stream_reset
    LEAVE   0
END_FUNCTION libp2p_stream_abort

/* libp2p_stream_reset(stream): RST goes out with the next drain, then the slot is free; the queue is dropped. */
LOCAL_FUNCTION libp2p_stream_reset
    ENTER   0
    mov     x19, x0
1:  ldr     x0, [x19, #S_Q_HEAD]
    cmn     x0, #1
    b.eq    2f
    sub     x9, x0, #HB_HEADER
    add     x9, x27, x9
    ldr     x20, [x9, #CH_NEXT]
    bl      libp2p_heap_free
    str     x20, [x19, #S_Q_HEAD]
    b       1b
2:  mov     x9, #NONE
    str     x9, [x19, #S_Q_TAIL]
    str     xzr, [x19, #S_Q_BYTES]
    ldr     x9, [x19, #S_FLAGS]
    orr     x9, x9, #SF_RST
    and     x9, x9, #~SF_REPORTED
    str     x9, [x19, #S_FLAGS]
    LEAVE   0
END_FUNCTION libp2p_stream_reset

/*
 * libp2p_stream_ms(stream): one multistream message of a stream. The header
 * comes first (a remote stream answers it with ours). Our stream then reads
 * the answer to its proposal: the same protocol selects it, na moves to the
 * next proposal or fails. A remote stream answers proposals: gossipsub or
 * an application protocol is selected, anything else gets na.
 */
LOCAL_FUNCTION libp2p_stream_ms
    ENTER   0
    mov     x19, x0
    ldr     x20, [x19, #S_FLAGS]
    tst     x20, #SF_GOT_HEADER
    b.ne    2f
    add     x0, x19, #S_MS_STATE
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_ms_is
    cbz     x0, 80f
    orr     x20, x20, #SF_GOT_HEADER
    str     x20, [x19, #S_FLAGS]
    tst     x20, #SF_LOCAL
    b.ne    70f
    mov     x0, x19
    adr     x1, 430b
    mov     x2, #MS_HEADER_LEN
    bl      libp2p_stream_ms_out
    b       70f
2:  tst     x20, #SF_LOCAL
    b.eq    40f
    mov     x0, x19                         /* our stream: the answer */
    bl      libp2p_stream_is_proposal
    cbz     x0, 30f
    str     xzr, [x19, #S_MS_LEN]
    ldr     x9, [x19, #S_TARGET]
    str     x9, [x19, #S_KIND]
    ldr     x10, [x19, #S_PROP_INDEX]
    str     x10, [x19, #S_PROTO]
    cmp     x9, #SK_APP
    b.ne    20f
    orr     x20, x20, #SF_REPORTED
    str     x20, [x19, #S_FLAGS]
    mov     x0, #LIBP2P_ACTION_STREAM_OPENED
    mov     x1, #LIBP2P_ACT_SO_SIZE
    bl      libp2p_action
    cbz     x0, 99f
    mov     x21, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x21, #LIBP2P_ACT_STREAM]
    ldr     x9, [x19, #S_TAG]
    str     x9, [x21, #LIBP2P_ACT_SO_TAG]
    ldr     x9, [x19, #S_PROTO]
    str     x9, [x21, #LIBP2P_ACT_SO_INDEX]
    b       99f
20: mov     x0, x19                         /* our gossipsub stream */
    bl      libp2p_gossip_out_ready
    b       99f
30: add     x0, x19, #S_MS_STATE            /* na: the next proposal */
    adr     x1, 431b
    mov     x2, #3
    bl      libp2p_ms_is
    cbz     x0, 80f
    ldr     x9, [x19, #S_PROP_INDEX]
    add     x9, x9, #1
    ldr     x10, [x19, #S_PROP_COUNT]
    cmp     x9, x10
    b.hs    31f
    str     x9, [x19, #S_PROP_INDEX]
    mov     x0, x19
    bl      libp2p_stream_propose
    b       70f
31: str     xzr, [x19, #S_MS_LEN]
    mov     x0, x19
    mov     x1, #LIBP2P_REASON_PROTOCOL
    bl      libp2p_stream_abort
    b       99f
40: add     x0, x19, #S_MS_STATE            /* a remote stream: a proposal */
    adr     x1, 435b
    mov     x2, #15
    bl      libp2p_ms_is
    adr     x21, 435b
    cbnz    x0, 41f
    CFG     x9, LIBP2P_CFG_GOSSIPSUB_V12
    cbz     x9, 50f
    add     x0, x19, #S_MS_STATE
    adr     x1, 437b
    mov     x2, #15
    bl      libp2p_ms_is
    adr     x21, 437b
    cbnz    x0, 41f
    CFG     x9, LIBP2P_CFG_GOSSIPSUB_V13
    cbz     x9, 50f
    add     x0, x19, #S_MS_STATE
    adr     x1, 438b
    mov     x2, #15
    bl      libp2p_ms_is
    adr     x21, 438b
    cbz     x0, 50f
41: mov     x0, x19                         /* gossipsub: echo the version */
    mov     x1, x21
    mov     x2, #15
    bl      libp2p_stream_ms_out
    str     xzr, [x19, #S_MS_LEN]
    mov     x9, #SK_GOSSIP_IN
    str     x9, [x19, #S_KIND]
    mov     x0, x19
    bl      libp2p_gossip_in_ready
    b       99f
50: add     x0, x19, #S_MS_STATE            /* identify */
    adr     x1, 436b
    mov     x2, #15
    bl      libp2p_ms_is
    cbz     x0, 51f
    mov     x0, x19
    adr     x1, 436b
    mov     x2, #15
    bl      libp2p_stream_ms_out
    str     xzr, [x19, #S_MS_LEN]
    mov     x9, #SK_IDENTIFY
    str     x9, [x19, #S_KIND]
    mov     x0, x19
    bl      libp2p_identify
    b       99f
51: mov     x0, x19
    bl      libp2p_stream_find_proto
    cmn     x0, #1
    b.eq    60f
    mov     x21, x0
    ldr     x9, [x19, #S_MS_NEED]           /* echo the message */
    add     x9, x9, #S_MS_BUF
    add     x1, x19, x9
    ldr     x10, [x19, #S_MS_LEN]
    ldr     x11, [x19, #S_MS_NEED]
    sub     x2, x10, x11
    mov     x0, x19
    bl      libp2p_stream_ms_out
    str     xzr, [x19, #S_MS_LEN]
    mov     x9, #SK_APP
    str     x9, [x19, #S_KIND]
    str     x21, [x19, #S_PROTO]
    orr     x20, x20, #SF_REPORTED
    str     x20, [x19, #S_FLAGS]
    mov     x0, #LIBP2P_ACTION_STREAM_INBOUND
    mov     x1, #LIBP2P_ACT_SI_SIZE
    bl      libp2p_action
    cbz     x0, 99f
    mov     x22, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x22, #LIBP2P_ACT_STREAM]
    ldr     x0, [x19, #S_PEER]
    TABLE   x9, ST_PEER_OFF
    mov     x10, #P_SIZE
    madd    x2, x0, x10, x9
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x22, #LIBP2P_ACT_SI_PEER]
    str     x21, [x22, #LIBP2P_ACT_SI_PROTOCOL]
    b       99f
60: mov     x0, x19                         /* na */
    adr     x1, 431b
    mov     x2, #3
    bl      libp2p_stream_ms_out
70: str     xzr, [x19, #S_MS_LEN]
    b       99f
80: str     xzr, [x19, #S_MS_LEN]
    mov     x0, x19
    mov     x1, #LIBP2P_REASON_PROTOCOL
    bl      libp2p_stream_abort
99: LEAVE   0
END_FUNCTION libp2p_stream_ms

/*
 * libp2p_stream_remote_fin(stream): the peer closed its side: STREAM_EOF for the
 * application. A stream whose FIN already went out is closed both ways: it
 * is dead, and the next drain frees it.
 */
LOCAL_FUNCTION libp2p_stream_remote_fin
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #S_FLAGS]
    tst     x9, #SF_REMOTE_FIN
    b.ne    9f
    orr     x9, x9, #SF_REMOTE_FIN
    tst     x9, #SF_FIN_SENT                /* closed both ways: the drain frees it */
    b.eq    3f
    orr     x9, x9, #SF_DEAD
3:  str     x9, [x19, #S_FLAGS]
    ldr     x10, [x19, #S_KIND]
    cmp     x10, #SK_APP
    b.ne    1f
    tst     x9, #SF_REPORTED
    b.eq    9f
    mov     x0, #LIBP2P_ACTION_STREAM_EOF
    mov     x1, #LIBP2P_ACT_STREAM_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_stream_handle
    str     x0, [x20, #LIBP2P_ACT_STREAM]
    b       9f
1:  cmp     x10, #SK_GOSSIP_IN              /* the peer closed its gossipsub stream: close ours of it too */
    b.eq    2f
    cmp     x10, #SK_NEGOTIATING
    b.ne    9f
2:  orr     x9, x9, #SF_FIN
    str     x9, [x19, #S_FLAGS]
9:  LEAVE   0
END_FUNCTION libp2p_stream_remote_fin

/* ---------------------------------------------------------------- Application stream events */

/*
 * libp2p_on_open_stream(event): an outbound application stream to a connected
 * peer, proposing the protocols in order; STREAM_FAILED when the peer is
 * not connected or no slot or heap block is free.
 */
LOCAL_FUNCTION libp2p_on_open_stream
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_PEER]
    bl      libp2p_peer
    mov     x21, #LIBP2P_REASON_NO_PEER
    cbz     x0, 8f
    ldr     x9, [x0, #P_CONN]
    TABLE   x10, ST_CONN_OFF
    mov     x11, #C_SIZE
    madd    x20, x9, x11, x10
    ldr     w9, [x20, #C_PHASE]
    cmp     w9, #PH_OPEN
    b.ne    8f
    mov     x21, #LIBP2P_REASON_LIMIT
    ldr     x22, [x19, #LIBP2P_EV_OPEN_COUNT]
    mov     x9, #LIBP2P_PROTO_SIZE
    mul     x0, x22, x9
    bl      libp2p_heap_alloc
    cbz     x0, 8f
    mov     x23, x0
    add     x0, x27, x23
    add     x1, x19, #LIBP2P_EV_OPEN_PROTOCOLS
    mov     x9, #LIBP2P_PROTO_SIZE
    mul     x2, x22, x9
    bl      libp2p_copy
    mov     x0, x20
    mov     x1, #SK_APP
    ldr     x2, [x19, #LIBP2P_EV_OPEN_TAG]
    mov     x3, x23
    mov     x4, x22
    bl      libp2p_stream_open
    cbnz    x0, 9f
8:  mov     x0, #LIBP2P_ACTION_STREAM_FAILED
    mov     x1, #LIBP2P_ACT_FAILED_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    ldr     x9, [x19, #LIBP2P_EV_OPEN_TAG]
    str     x9, [x0, #LIBP2P_ACT_TAG]
    str     x21, [x0, #LIBP2P_ACT_REASON]
9:  LEAVE   0
END_FUNCTION libp2p_on_open_stream

/* libp2p_app_stream(handle) -> the application stream of a handle that may still send, or 0. */
LOCAL_FUNCTION libp2p_app_stream
    ENTER   0
    bl      libp2p_stream
    cbz     x0, 9f
    ldr     x9, [x0, #S_KIND]
    cmp     x9, #SK_APP
    b.ne    8f
    ldr     x9, [x0, #S_FLAGS]
    tst     x9, #SF_REPORTED
    b.ne    9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_app_stream

/*
 * libp2p_on_stream_write(event): bytes for an application stream, queued; a
 * stream whose queue would pass the limit, or that the heap cannot hold,
 * is reset (STREAM_RESET).
 */
LOCAL_FUNCTION libp2p_on_stream_write
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_STREAM]
    bl      libp2p_app_stream
    cbz     x0, 9f
    mov     x20, x0
    ldr     x9, [x20, #S_FLAGS]
    mov     x10, #(SF_FIN | SF_RST)
    tst     x9, x10
    b.ne    9f
    ldr     x21, [x19, #LIBP2P_EV_STREAM_COUNT]
    ldr     x9, [x20, #S_Q_BYTES]
    add     x9, x9, x21
    CFG     x10, LIBP2P_CFG_STREAM_QUEUE
    cmp     x9, x10
    b.hi    8f
    mov     x0, x20
    add     x1, x19, #LIBP2P_EV_STREAM_DATA
    mov     x2, x21
    bl      libp2p_stream_queue
    cbnz    x0, 9f
8:  mov     x0, x20
    mov     x1, #LIBP2P_REASON_LIMIT
    bl      libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_write

/* libp2p_on_stream_close(event): the application closes its side of a stream: FIN after the queue. */
LOCAL_FUNCTION libp2p_on_stream_close
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_STREAM]
    bl      libp2p_app_stream
    cbz     x0, 9f
    ldr     x9, [x0, #S_FLAGS]
    orr     x9, x9, #SF_FIN
    str     x9, [x0, #S_FLAGS]
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_close

/* libp2p_on_stream_reset(event): the application resets a stream: RST goes out, nothing comes back. */
LOCAL_FUNCTION libp2p_on_stream_reset
    ENTER   0
    ldr     x0, [x0, #LIBP2P_EV_STREAM]
    bl      libp2p_app_stream
    cbz     x0, 9f
    bl      libp2p_stream_reset
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_reset

/* ---------------------------------------------------------------- identify (/ipfs/id/1.0.0) */

/* libp2p_stream_append(stream, chunk): a send chunk (a state offset, its length set) goes on the queue of the stream. */
LOCAL_FUNCTION libp2p_stream_append
    UNWIND_END_PROLOGUE
    sub     x2, x1, #HB_HEADER
    add     x2, x27, x2
    ldr     x3, [x0, #S_Q_TAIL]
    cmn     x3, #1
    b.ne    1f
    str     x1, [x0, #S_Q_HEAD]
    b       2f
1:  sub     x3, x3, #HB_HEADER
    add     x3, x27, x3
    str     x1, [x3, #CH_NEXT]
2:  str     x1, [x0, #S_Q_TAIL]
    ldr     x3, [x0, #S_Q_BYTES]
    ldr     x4, [x2, #CH_LEN]
    add     x3, x3, x4
    str     x3, [x0, #S_Q_BYTES]
    ret
END_FUNCTION libp2p_stream_append

/*
 * libp2p_observed(dst, addr) -> the length of the binary multiaddr of the
 * address: /ip4 (code 4, 4 bytes) or /ip6 (code 41, 16 bytes), then /tcp
 * (code 6, the port big endian). A leaf.
 */
LOCAL_FUNCTION libp2p_observed
    UNWIND_END_PROLOGUE
    mov     x2, x0
    ldr     x3, [x1, #LIBP2P_ADDR_FAMILY]
    cmp     x3, #6
    b.eq    1f
    mov     w4, #4
    strb    w4, [x2], #1
    ldr     w4, [x1, #LIBP2P_ADDR_IP]
    str     w4, [x2], #4
    b       2f
1:  mov     w4, #41
    strb    w4, [x2], #1
    ldp     x4, x5, [x1, #LIBP2P_ADDR_IP]
    stp     x4, x5, [x2], #16
2:  mov     w4, #6
    strb    w4, [x2], #1
    ldr     x4, [x1, #LIBP2P_ADDR_PORT]
    lsr     x5, x4, #8
    strb    w5, [x2], #1
    strb    w4, [x2], #1
    sub     x0, x2, x0
    ret
END_FUNCTION libp2p_observed

/*
 * libp2p_identify(stream): the Identify message on a stream the peer opened
 * with /ipfs/id/1.0.0, varint-length prefixed, then FIN: publicKey (1),
 * observedAddr (4), protocols (3): identify, gossipsub (/meshsub/1.3.0 and
 * /meshsub/1.2.0 too when they are on) and the application protocols, then
 * protocolVersion (5) and agentVersion (6) when the config has them.
 * x19 stream, x20 size, x21 key length, x22 observed length, x23 position,
 * x24 chunk, x25 protocol, x26 protocols left. Key at sp, observed at sp + 48.
 */
LOCAL_FUNCTION libp2p_identify
    ENTER   0, 80
    mov     x19, x0
    mov     x0, sp
    ldr     x1, [x27, #ST_KEY_TYPE]
    add     x2, x27, #ST_PUBLIC_KEY
    ldr     x3, [x27, #ST_PUBLIC_LEN]
    bl      libp2p_key_proto
    mov     x9, sp
    sub     x21, x0, x9
    mov     x0, x19
    bl      libp2p_stream_conn
    add     x1, x0, #C_ADDR
    add     x0, sp, #48
    bl      libp2p_observed
    mov     x22, x0
    mov     x0, #1                          /* the size */
    mov     x1, x21
    bl      libp2p_pb_size
    mov     x20, x0
    mov     x0, #4
    mov     x1, x22
    bl      libp2p_pb_size
    add     x20, x20, x0
    mov     x0, #3
    mov     x1, #14
    bl      libp2p_pb_size
    add     x20, x20, x0, lsl #1            /* identify and gossipsub: 14 bytes each */
    CFG     x9, LIBP2P_CFG_GOSSIPSUB_V12    /* and /meshsub/1.2.0 */
    CFG     x10, LIBP2P_CFG_GOSSIPSUB_V13   /* and /meshsub/1.3.0 */
    add     x9, x9, x10
    madd    x20, x0, x9, x20
    TABLE   x25, ST_PROTO_OFF
    ldr     x26, [x27, #ST_PROTO_COUNT]
1:  cbz     x26, 2f
    mov     x0, #3
    ldr     x1, [x25, #LIBP2P_PROTO_LEN]
    bl      libp2p_pb_size
    add     x20, x20, x0
    add     x25, x25, #LIBP2P_PROTO_SIZE
    sub     x26, x26, #1
    b       1b
2:  CFG     x1, LIBP2P_CFG_PV_LEN
    cbz     x1, 3f
    mov     x0, #5
    bl      libp2p_pb_size
    add     x20, x20, x0
3:  CFG     x1, LIBP2P_CFG_AGENT_LEN
    cbz     x1, 4f
    mov     x0, #6
    bl      libp2p_pb_size
    add     x20, x20, x0
4:  mov     x0, x20
    bl      libp2p_varint_len
    add     x0, x0, x20
    bl      libp2p_gs_alloc
    cbz     x0, 9f
    mov     x24, x1
    mov     x1, x20
    bl      libp2p_varint_put
    mov     x1, #1
    mov     x2, sp
    mov     x3, x21
    bl      libp2p_pb_bytes
    mov     x1, #4
    add     x2, sp, #48
    mov     x3, x22
    bl      libp2p_pb_bytes
    mov     x1, #3
    adr     x2, 436b
    mov     x3, #14
    bl      libp2p_pb_bytes
    CFG     x9, LIBP2P_CFG_GOSSIPSUB_V13
    cbz     x9, 40f
    mov     x1, #3
    adr     x2, 438b
    mov     x3, #14
    bl      libp2p_pb_bytes
40: CFG     x9, LIBP2P_CFG_GOSSIPSUB_V12
    cbz     x9, 41f
    mov     x1, #3
    adr     x2, 437b
    mov     x3, #14
    bl      libp2p_pb_bytes
41: mov     x1, #3
    adr     x2, 435b
    mov     x3, #14
    bl      libp2p_pb_bytes
    TABLE   x25, ST_PROTO_OFF
    ldr     x26, [x27, #ST_PROTO_COUNT]
5:  cbz     x26, 6f
    mov     x1, #3
    add     x2, x25, #LIBP2P_PROTO_BYTES
    ldr     x3, [x25, #LIBP2P_PROTO_LEN]
    bl      libp2p_pb_bytes
    add     x25, x25, #LIBP2P_PROTO_SIZE
    sub     x26, x26, #1
    b       5b
6:  CFG     x3, LIBP2P_CFG_PV_LEN
    cbz     x3, 7f
    mov     x1, #5
    add     x2, x27, #(ST_CONFIG + LIBP2P_CFG_PV)
    bl      libp2p_pb_bytes
7:  CFG     x3, LIBP2P_CFG_AGENT_LEN
    cbz     x3, 8f
    mov     x1, #6
    add     x2, x27, #(ST_CONFIG + LIBP2P_CFG_AGENT)
    bl      libp2p_pb_bytes
8:  mov     x0, x19
    mov     x1, x24
    bl      libp2p_stream_append
9:  ldr     x9, [x19, #S_FLAGS]             /* then FIN */
    orr     x9, x9, #SF_FIN
    str     x9, [x19, #S_FLAGS]
    LEAVE   0, 80
END_FUNCTION libp2p_identify

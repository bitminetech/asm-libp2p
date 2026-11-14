/*
 * Muxers of the ARM64 core: yamux (/yamux/1.0.0) and mplex (/mplex/6.7.0)
 * frame parsing, frame output, and the drain of queued bytes into SEND
 * actions. Included by libp2p.s.
 */

/* yamux frame types and flags. */
.set YT_DATA, 0
.set YT_WINDOW, 1
.set YT_PING, 2
.set YT_GOAWAY, 3
.set YF_SYN, 1
.set YF_ACK, 2
.set YF_FIN, 4
.set YF_RST, 8

/* mplex flags. */
.set MP_NEW, 0
.set MP_MSG_RECEIVER, 1
.set MP_MSG_INITIATOR, 2
.set MP_CLOSE_RECEIVER, 3
.set MP_CLOSE_INITIATOR, 4
.set MP_RESET_RECEIVER, 5
.set MP_RESET_INITIATOR, 6

/* libp2p_mux_feed(conn, p, n) -> the bytes the muxer of the connection took. */
LOCAL_FUNCTION libp2p_mux_feed
    ENTER   0
    ldr     x9, [x0, #C_FLAGS]
    tst     x9, #CF_YAMUX
    b.eq    1f
    bl      libp2p_yamux_feed
    b       9f
1:  bl      libp2p_mplex_feed
9:  LEAVE   0
END_FUNCTION libp2p_mux_feed

/*
 * libp2p_mux_data(conn, p, n) -> n: data bytes of the current frame go to its
 * stream (with the yamux window counted); when the frame ends, its flags
 * act.
 */
LOCAL_FUNCTION libp2p_mux_data
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x19, #C_MX_REMAIN]
    cmp     x2, x9
    csel    x21, x2, x9, lo
    sub     x9, x9, x21
    str     x9, [x19, #C_MX_REMAIN]
    ldr     x9, [x19, #C_MX_STREAM]
    cmn     x9, #1
    b.eq    2f
    mov     x0, x9
    bl      libp2p_stream_at
    mov     x22, x0
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_YAMUX
    b.eq    1f
    ldr     x9, [x22, #S_RECV_WIN]
    sub     x9, x9, x21
    str     x9, [x22, #S_RECV_WIN]
    ldr     x9, [x22, #S_RECV_PEND]
    add     x9, x9, x21
    str     x9, [x22, #S_RECV_PEND]
1:  mov     x0, x22
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_stream_data
2:  ldr     x9, [x19, #C_MX_REMAIN]
    cbnz    x9, 9f
    mov     x0, x19
    bl      libp2p_mux_end_frame
9:  mov     x0, x21
    LEAVE   0
END_FUNCTION libp2p_mux_data

/* libp2p_mux_end_frame(conn): a frame ended: its FIN or RST acts on its stream. */
LOCAL_FUNCTION libp2p_mux_end_frame
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #C_MX_STREAM]
    mov     x10, #NONE
    str     x10, [x19, #C_MX_STREAM]
    cmn     x9, #1
    b.eq    9f
    mov     x0, x9
    bl      libp2p_stream_at
    mov     x20, x0
    ldr     w9, [x20, #S_USED]
    cbz     w9, 9f
    ldr     x21, [x19, #C_MX_FLAGS]
    tst     x21, #YF_RST
    b.eq    1f
    mov     x0, x20                         /* the peer reset the stream */
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_stream_kill
    b       9f
1:  tst     x21, #YF_FIN
    b.eq    9f
    mov     x0, x20
    bl      libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_mux_end_frame

/* libp2p_mux_find(conn, id, local) -> the stream of the connection with the muxer ID and side, or 0. */
LOCAL_FUNCTION libp2p_mux_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x19, #C_STREAM_HEAD]
1:  cmn     x22, #1
    b.eq    8f
    mov     x0, x22
    bl      libp2p_stream_at
    ldr     x9, [x0, #S_ID]
    cmp     x9, x20
    b.ne    2f
    ldr     x9, [x0, #S_FLAGS]
    and     x9, x9, #SF_LOCAL
    cmp     x9, x21
    b.eq    9f
2:  ldr     x22, [x0, #S_NEXT]
    b       1b
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_mux_find

/* libp2p_mux_rst(conn, id): a reset for a stream that has no slot, sent by the next drain. */
LOCAL_FUNCTION libp2p_mux_rst
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #C_RSTS]
    cmp     x2, #6
    b.hs    9f
    add     x3, x0, #C_RST_IDS
    str     w1, [x3, x2, lsl #2]
    add     x2, x2, #1
    str     x2, [x0, #C_RSTS]
9:  ret
END_FUNCTION libp2p_mux_rst

/* libp2p_mux_error(conn) -> 0: the peer broke the muxer protocol; the connection ends. */
LOCAL_FUNCTION libp2p_mux_error
    ENTER   0
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_close
    mov     x0, #0
    LEAVE   0
END_FUNCTION libp2p_mux_error

/* ---------------------------------------------------------------- yamux input */

/* libp2p_yamux_feed(conn, p, n) -> bytes taken: frame data, or header bytes; a whole header is handled. */
LOCAL_FUNCTION libp2p_yamux_feed
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x19, #C_MX_REMAIN]
    cbz     x9, 1f
    bl      libp2p_mux_data
    b       9f
1:  ldr     x22, [x19, #C_MX_HLEN]
    mov     x9, #12
    sub     x9, x9, x22
    cmp     x21, x9
    csel    x23, x21, x9, lo
    add     x0, x19, #C_MX_HDR
    add     x0, x0, x22
    mov     x1, x20
    mov     x2, x23
    bl      libp2p_copy
    add     x22, x22, x23
    str     x22, [x19, #C_MX_HLEN]
    cmp     x22, #12
    b.lo    8f
    str     xzr, [x19, #C_MX_HLEN]
    mov     x0, x19
    bl      libp2p_yamux_frame
8:  mov     x0, x23
9:  LEAVE   0
END_FUNCTION libp2p_yamux_feed

/*
 * libp2p_yamux_frame(conn): one 12-byte header: version 0, type, flags, stream
 * ID and length, big endian.
 * x19 conn, x20 type, x21 flags, x22 ID, x23 length, x24 stream.
 */
LOCAL_FUNCTION libp2p_yamux_frame
    ENTER   0
    mov     x19, x0
    add     x9, x19, #C_MX_HDR
    ldrb    w10, [x9]
    cbnz    w10, 80f
    ldrb    w20, [x9, #1]
    ldrh    w21, [x9, #2]
    rev16   w21, w21
    ldr     w22, [x9, #4]
    rev     w22, w22
    ldr     w23, [x9, #8]
    rev     w23, w23
    cmp     x20, #YT_PING
    b.ne    1f
    tst     x21, #YF_SYN                    /* a ping: answer it */
    b.eq    99f
    ldr     x9, [x19, #C_PING_COUNT]
    cmp     x9, #4
    b.hs    99f
    add     x10, x19, #C_PINGS
    str     w23, [x10, x9, lsl #2]
    add     x9, x9, #1
    str     x9, [x19, #C_PING_COUNT]
    b       99f
1:  cmp     x20, #YT_GOAWAY
    b.ne    2f
    mov     x0, x19
    mov     x1, #LIBP2P_REASON_CLOSED
    bl      libp2p_conn_close
    b       99f
2:  cmp     x20, #YT_WINDOW
    b.hi    80f
    cbz     x22, 80f
    mov     x0, x19
    mov     x1, x22
    mov     x2, x21
    bl      libp2p_yamux_stream
    cmn     x0, #1
    b.eq    80f
    mov     x24, x0
    str     x21, [x19, #C_MX_FLAGS]
    mov     x9, #NONE
    cbz     x24, 3f
    mov     x0, x24
    bl      libp2p_stream_index
    mov     x9, x0
3:  str     x9, [x19, #C_MX_STREAM]
    cmp     x20, #YT_DATA
    b.ne    4f
    cbz     x24, 31f                        /* data: within the window */
    ldr     x9, [x24, #S_RECV_WIN]
    cmp     x23, x9
    b.hi    80f
31: str     x23, [x19, #C_MX_REMAIN]
    cbnz    x23, 99f
    mov     x0, x19
    bl      libp2p_mux_end_frame
    b       99f
4:  cbz     x24, 41f                        /* a window update */
    ldr     x9, [x24, #S_SEND_WIN]
    add     x9, x9, x23
    str     x9, [x24, #S_SEND_WIN]
41: mov     x0, x19
    bl      libp2p_mux_end_frame
    b       99f
80: mov     x0, x19
    bl      libp2p_mux_error
99: LEAVE   0
END_FUNCTION libp2p_yamux_frame

/*
 * libp2p_yamux_stream(conn, id, flags) -> the stream of a frame, 0 when it has
 * none (its bytes are dropped), NONE for a protocol error. SYN opens a
 * stream of the peer (odd IDs for the dialer, even for the listener); with
 * no slot for it, or with 256 not acknowledged, it is reset.
 */
LOCAL_FUNCTION libp2p_yamux_stream
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    tst     x21, #YF_SYN
    b.ne    1f
    mov     x2, #SF_LOCAL                   /* ours, then the peer's */
    bl      libp2p_mux_find
    cbnz    x0, 9f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_mux_find
    b       9f
1:  ldr     x9, [x19, #C_FLAGS]
    and     x9, x9, #CF_OUTBOUND            /* the peer's IDs: even when we dialled */
    and     x10, x20, #1
    eor     x10, x10, #1
    cmp     x9, x10
    b.ne    8f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_mux_find
    cbnz    x0, 8f
    ldr     x9, [x19, #C_BACKLOG]
    cmp     x9, #LIBP2P_YAMUX_BACKLOG
    b.hs    7f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_stream_new
    cbz     x0, 7f
    ldr     x9, [x0, #S_FLAGS]
    orr     x9, x9, #SF_ACK
    str     x9, [x0, #S_FLAGS]
    ldr     x9, [x19, #C_BACKLOG]
    add     x9, x9, #1
    str     x9, [x19, #C_BACKLOG]
    b       9f
7:  mov     x0, x19
    mov     x1, x20
    bl      libp2p_mux_rst
    mov     x0, #0
    b       9f
8:  mov     x0, #NONE
9:  LEAVE   0
END_FUNCTION libp2p_yamux_stream

/* ---------------------------------------------------------------- mplex input */

/*
 * libp2p_mplex_feed(conn, p, n) -> bytes taken: message data, or header bytes
 * one at a time until both varints of the header are whole.
 */
LOCAL_FUNCTION libp2p_mplex_feed
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x19, #C_MX_REMAIN]
    cbz     x9, 1f
    bl      libp2p_mux_data
    b       9f
1:  ldr     x22, [x19, #C_MX_HLEN]
    mov     x23, #0
2:  cmp     x23, x21
    b.hs    8f
    cmp     x22, #20
    b.hs    80f
    ldrb    w9, [x20, x23]
    add     x10, x19, #C_MX_HDR
    strb    w9, [x10, x22]
    add     x22, x22, #1
    add     x23, x23, #1
    str     x22, [x19, #C_MX_HLEN]
    add     x0, x19, #C_MX_HDR
    add     x1, x0, x22
    bl      libp2p_varint_get
    cmn     x1, #1
    b.eq    80f
    cbz     x1, 2b
    mov     x24, x0
    add     x0, x19, #C_MX_HDR
    add     x0, x0, x1
    add     x1, x19, #C_MX_HDR
    add     x1, x1, x22
    bl      libp2p_varint_get
    cmn     x1, #1
    b.eq    80f
    cbz     x1, 2b
    str     xzr, [x19, #C_MX_HLEN]
    mov     x2, x0
    mov     x0, x19
    mov     x1, x24
    bl      libp2p_mplex_frame
    b       8f
80: mov     x0, x19
    bl      libp2p_mux_error
8:  mov     x0, x23
9:  LEAVE   0
END_FUNCTION libp2p_mplex_feed

/*
 * libp2p_mplex_frame(conn, header, length): one mplex header: the stream ID and
 * flag in the first varint, the data length in the second.
 * x19 conn, x20 ID, x21 flag, x22 length, x23 stream.
 */
LOCAL_FUNCTION libp2p_mplex_frame
    ENTER   0
    mov     x19, x0
    lsr     x20, x1, #3
    and     x21, x1, #7
    mov     x22, x2
    MOV64   x9, LIBP2P_MPLEX_MAX
    cmp     x22, x9
    b.hi    80f
    cmp     x21, #MP_RESET_INITIATOR
    b.hi    80f
    lsr     x9, x20, #28                    /* IDs below 2^28 */
    cbnz    x9, 80f
    str     x22, [x19, #C_MX_REMAIN]
    mov     x9, #NONE
    str     x9, [x19, #C_MX_STREAM]
    str     xzr, [x19, #C_MX_FLAGS]
    cbnz    x21, 1f
    mov     x0, x19                         /* NewStream: the data is a name, dropped */
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_mux_find
    cbnz    x0, 80f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_stream_new
    cbnz    x0, 9f
    mov     x0, x19
    lsl     x1, x20, #3
    add     x1, x1, #MP_RESET_RECEIVER
    bl      libp2p_mux_rst
    b       9f
1:  and     x9, x21, #1                     /* odd flags: from the receiver, so the stream is ours */
    mov     x2, #SF_LOCAL
    cmp     x9, #0
    csel    x2, x2, xzr, ne
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_mux_find
    mov     x23, x0
    cbz     x23, 9f                         /* no such stream: drop the data */
    mov     x0, x23
    bl      libp2p_stream_index
    str     x0, [x19, #C_MX_STREAM]
    cmp     x21, #MP_MSG_INITIATOR
    b.ls    9f
    mov     x9, #YF_FIN                     /* close, or reset */
    mov     x10, #YF_RST
    cmp     x21, #MP_CLOSE_INITIATOR
    csel    x9, x9, x10, ls
    str     x9, [x19, #C_MX_FLAGS]
9:  ldr     x9, [x19, #C_MX_REMAIN]
    cbnz    x9, 99f
    mov     x0, x19
    bl      libp2p_mux_end_frame
    b       99f
80: mov     x0, x19
    bl      libp2p_mux_error
99: LEAVE   0
END_FUNCTION libp2p_mplex_frame

/* ---------------------------------------------------------------- Frame output */

/* libp2p_yamux_header(dst, type, flags, id, length) -> dst + 12. A leaf. */
LOCAL_FUNCTION libp2p_yamux_header
    UNWIND_END_PROLOGUE
    strb    wzr, [x0]
    strb    w1, [x0, #1]
    rev16   w2, w2
    strh    w2, [x0, #2]
    rev     w3, w3
    str     w3, [x0, #4]
    rev     w4, w4
    str     w4, [x0, #8]
    add     x0, x0, #12
    ret
END_FUNCTION libp2p_yamux_header

/* libp2p_mplex_header(dst, header, length) -> dst after the two varints. */
LOCAL_FUNCTION libp2p_mplex_header
    ENTER   0
    mov     x19, x2
    bl      libp2p_varint_put
    mov     x1, x19
    bl      libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_mplex_header

/*
 * libp2p_chunk_take(stream, dst, max) -> the bytes copied to dst from the head
 * chunk of the queue, at most max; a chunk that is all sent is freed.
 */
LOCAL_FUNCTION libp2p_chunk_take
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x19, #S_Q_HEAD]
    sub     x22, x21, #HB_HEADER
    add     x22, x27, x22
    ldr     x9, [x22, #CH_LEN]
    ldr     x10, [x22, #CH_DONE]
    sub     x9, x9, x10
    cmp     x2, x9
    csel    x23, x2, x9, lo
    mov     x0, x20
    add     x1, x22, #CH_DATA
    add     x1, x1, x10
    mov     x2, x23
    bl      libp2p_copy
    ldr     x10, [x22, #CH_DONE]
    add     x10, x10, x23
    str     x10, [x22, #CH_DONE]
    ldr     x9, [x19, #S_Q_BYTES]
    sub     x9, x9, x23
    str     x9, [x19, #S_Q_BYTES]
    ldr     x9, [x22, #CH_LEN]
    cmp     x10, x9
    b.lo    9f
    ldr     x9, [x22, #CH_NEXT]
    str     x9, [x19, #S_Q_HEAD]
    cmn     x9, #1
    b.ne    1f
    str     x9, [x19, #S_Q_TAIL]
1:  mov     x0, x21
    bl      libp2p_heap_free
9:  mov     x0, x23
    LEAVE   0
END_FUNCTION libp2p_chunk_take

/*
 * libp2p_yamux_emit(conn, stream, dst, room) -> dst after what it wrote: RST; SYN; ACK;
 * a window update once 64 KiB were taken; data frames within the send
 * window; FIN after the queue. A stream with RST, or closed both ways and
 * empty, becomes dead.
 * x19 conn, x20 stream, x21 position, x22 end, x23 flags, x24 ID.
 */
LOCAL_FUNCTION libp2p_yamux_emit
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x22, x2, x3
    ldr     x23, [x20, #S_FLAGS]
    ldr     x24, [x20, #S_ID]
    tst     x23, #SF_RST
    b.eq    1f
    sub     x9, x22, x21
    cmp     x9, #12
    b.lo    90f
    mov     x0, x21
    mov     x1, #YT_WINDOW
    mov     x2, #YF_RST
    mov     x3, x24
    mov     x4, #0
    bl      libp2p_yamux_header
    mov     x21, x0
    orr     x23, x23, #SF_DEAD
    b       90f
1:  tst     x23, #(SF_SYN | SF_ACK)
    b.eq    2f
    sub     x9, x22, x21
    cmp     x9, #12
    b.lo    90f
    and     x2, x23, #SF_SYN                /* SF_SYN is 2: YF_ACK; SF_ACK is 4 */
    lsr     x2, x2, #1                      /* YF_SYN */
    tst     x23, #SF_ACK
    mov     x9, #YF_ACK
    csel    x2, x9, x2, ne
    mov     x0, x21
    mov     x1, #YT_WINDOW
    mov     x3, x24
    mov     x4, #0
    bl      libp2p_yamux_header
    mov     x21, x0
    tst     x23, #SF_ACK
    b.eq    11f
    ldr     x9, [x19, #C_BACKLOG]
    sub     x9, x9, #1
    str     x9, [x19, #C_BACKLOG]
11: and     x23, x23, #~(SF_SYN | SF_ACK)
2:  ldr     x9, [x20, #S_RECV_PEND]
    cmp     x9, #65536
    b.lo    3f
    sub     x10, x22, x21
    cmp     x10, #12
    b.lo    90f
    mov     x0, x21
    mov     x1, #YT_WINDOW
    mov     x2, #0
    mov     x3, x24
    mov     x4, x9
    bl      libp2p_yamux_header
    mov     x21, x0
    ldr     x9, [x20, #S_RECV_PEND]
    ldr     x10, [x20, #S_RECV_WIN]
    add     x10, x10, x9
    str     x10, [x20, #S_RECV_WIN]
    str     xzr, [x20, #S_RECV_PEND]
3:  ldr     x9, [x20, #S_Q_HEAD]            /* data */
    cmn     x9, #1
    b.eq    4f
    ldr     x10, [x20, #S_SEND_WIN]
    cbz     x10, 90f
    sub     x11, x22, x21
    cmp     x11, #13
    b.lo    90f
    sub     x11, x11, #12
    cmp     x10, x11
    csel    x2, x10, x11, lo
    mov     x0, x20
    add     x1, x21, #12
    bl      libp2p_chunk_take
    mov     x25, x0
    mov     x4, x0
    mov     x0, x21
    mov     x1, #YT_DATA
    mov     x2, #0
    mov     x3, x24
    bl      libp2p_yamux_header
    add     x21, x0, x25
    ldr     x9, [x20, #S_SEND_WIN]
    sub     x9, x9, x25
    str     x9, [x20, #S_SEND_WIN]
    b       3b
4:  tst     x23, #SF_FIN                    /* FIN after the queue */
    b.eq    5f
    tst     x23, #SF_FIN_SENT
    b.ne    5f
    sub     x9, x22, x21
    cmp     x9, #12
    b.lo    90f
    mov     x0, x21
    mov     x1, #YT_WINDOW
    mov     x2, #YF_FIN
    mov     x3, x24
    mov     x4, #0
    bl      libp2p_yamux_header
    mov     x21, x0
    orr     x23, x23, #SF_FIN_SENT
5:  mov     x10, #(SF_FIN_SENT | SF_REMOTE_FIN)
    and     x9, x23, x10
    cmp     x9, x10
    b.ne    90f
    orr     x23, x23, #SF_DEAD
90: str     x23, [x20, #S_FLAGS]
    mov     x0, x21
    LEAVE   0
END_FUNCTION libp2p_yamux_emit

/*
 * libp2p_mplex_emit(conn, stream, dst, room) -> dst after what it wrote: reset;
 * NewStream with the decimal ID as name; data messages; close after the
 * queue. The flags say which side opened the stream.
 * x19 conn, x20 stream, x21 position, x22 end, x23 flags, x24 ID << 3,
 * x25 1 when we opened it.
 */
LOCAL_FUNCTION libp2p_mplex_emit
    ENTER   0, 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x22, x2, x3
    ldr     x23, [x20, #S_FLAGS]
    ldr     x24, [x20, #S_ID]
    lsl     x24, x24, #3
    and     x25, x23, #SF_LOCAL
    tst     x23, #SF_RST
    b.eq    1f
    sub     x9, x22, x21
    cmp     x9, #16
    b.lo    90f
    mov     x9, #MP_RESET_RECEIVER
    mov     x10, #MP_RESET_INITIATOR
    cmp     x25, #0
    csel    x9, x10, x9, ne
    orr     x1, x24, x9
    mov     x0, x21
    mov     x2, #0
    bl      libp2p_mplex_header
    mov     x21, x0
    orr     x23, x23, #SF_DEAD
    b       90f
1:  tst     x23, #SF_SYN
    b.eq    3f
    sub     x9, x22, x21
    cmp     x9, #48
    b.lo    90f
    ldr     x9, [x20, #S_ID]                /* the name: the decimal ID, backwards on the stack */
    mov     x10, #0
    mov     x12, #10
2:  udiv    x11, x9, x12
    msub    x13, x11, x12, x9
    add     x13, x13, #'0'
    strb    w13, [sp, x10]
    add     x10, x10, #1
    mov     x9, x11
    cbnz    x9, 2b
    mov     x26, x10
    mov     x0, x21
    mov     x1, x24
    mov     x2, x26
    bl      libp2p_mplex_header
21: sub     x26, x26, #1
    ldrb    w9, [sp, x26]
    strb    w9, [x0], #1
    cbnz    x26, 21b
    mov     x21, x0
    and     x23, x23, #~SF_SYN
3:  ldr     x9, [x20, #S_Q_HEAD]            /* data */
    cmn     x9, #1
    b.eq    4f
    sub     x11, x22, x21
    cmp     x11, #17
    b.lo    90f
    sub     x2, x11, #16
    mov     x0, x20
    add     x1, x21, #16                    /* data after room for the header, moved down below */
    bl      libp2p_chunk_take
    mov     x26, x0
    mov     x9, #MP_MSG_RECEIVER
    mov     x10, #MP_MSG_INITIATOR
    cmp     x25, #0
    csel    x9, x10, x9, ne
    orr     x1, x24, x9
    mov     x0, x21
    mov     x2, x26
    bl      libp2p_mplex_header
    add     x1, x21, #16
    mov     x2, x26
    bl      libp2p_copy
    mov     x21, x0
    b       3b
4:  tst     x23, #SF_FIN
    b.eq    5f
    tst     x23, #SF_FIN_SENT
    b.ne    5f
    sub     x9, x22, x21
    cmp     x9, #16
    b.lo    90f
    mov     x9, #MP_CLOSE_RECEIVER
    mov     x10, #MP_CLOSE_INITIATOR
    cmp     x25, #0
    csel    x9, x10, x9, ne
    orr     x1, x24, x9
    mov     x0, x21
    mov     x2, #0
    bl      libp2p_mplex_header
    mov     x21, x0
    orr     x23, x23, #SF_FIN_SENT
5:  mov     x10, #(SF_FIN_SENT | SF_REMOTE_FIN)
    and     x9, x23, x10
    cmp     x9, x10
    b.ne    90f
    orr     x23, x23, #SF_DEAD
90: str     x23, [x20, #S_FLAGS]
    mov     x0, x21
    LEAVE   0, 32
END_FUNCTION libp2p_mplex_emit

/*
 * libp2p_mux_gather(conn, dst, room) -> bytes written: connection frames
 * (pongs, resets of streams without a slot), then the frames of each
 * stream in turn from the cursor; dead streams are freed.
 * x19 conn, x20 position, x21 end, x22 stream index, x23 streams visited.
 */
LOCAL_FUNCTION libp2p_mux_gather
    ENTER   0, 16
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    str     x1, [sp]
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_YAMUX
    b.eq    3f
1:  ldr     x9, [x19, #C_PING_COUNT]        /* yamux pongs */
    cbz     x9, 2f
    sub     x10, x21, x20
    cmp     x10, #12
    b.lo    9f
    sub     x9, x9, #1
    str     x9, [x19, #C_PING_COUNT]
    add     x10, x19, #C_PINGS
    ldr     w4, [x10, x9, lsl #2]
    mov     x0, x20
    mov     x1, #YT_PING
    mov     x2, #YF_ACK
    mov     x3, #0
    bl      libp2p_yamux_header
    mov     x20, x0
    b       1b
2:  ldr     x9, [x19, #C_RSTS]              /* yamux resets */
    cbz     x9, 5f
    sub     x10, x21, x20
    cmp     x10, #12
    b.lo    9f
    sub     x9, x9, #1
    str     x9, [x19, #C_RSTS]
    add     x10, x19, #C_RST_IDS
    ldr     w3, [x10, x9, lsl #2]
    mov     x0, x20
    mov     x1, #YT_WINDOW
    mov     x2, #YF_RST
    mov     x4, #0
    bl      libp2p_yamux_header
    mov     x20, x0
    b       2b
3:  ldr     x9, [x19, #C_RSTS]              /* mplex resets: the header is stored */
    cbz     x9, 5f
    sub     x10, x21, x20
    cmp     x10, #16
    b.lo    9f
    sub     x9, x9, #1
    str     x9, [x19, #C_RSTS]
    add     x10, x19, #C_RST_IDS
    ldr     w1, [x10, x9, lsl #2]
    mov     x0, x20
    mov     x2, #0
    bl      libp2p_mplex_header
    mov     x20, x0
    b       3b
5:  ldr     x22, [x19, #C_CURSOR]           /* the streams, from the cursor */
    cmn     x22, #1
    b.ne    51f
    ldr     x22, [x19, #C_STREAM_HEAD]
51: ldr     x23, [x19, #C_STREAMS]
6:  cbz     x23, 8f
    cmn     x22, #1
    b.ne    61f
    ldr     x22, [x19, #C_STREAM_HEAD]
    cmn     x22, #1
    b.eq    8f
61: mov     x0, x22
    bl      libp2p_stream_at
    mov     x24, x0
    ldr     x25, [x24, #S_NEXT]
    ldr     x9, [x24, #S_FLAGS]
    tst     x9, #SF_DEAD
    b.ne    63f
    mov     x0, x19
    mov     x1, x24
    mov     x2, x20
    sub     x3, x21, x20
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_YAMUX
    b.eq    62f
    bl      libp2p_yamux_emit
    b       621f
62: bl      libp2p_mplex_emit
621: mov    x20, x0
    sub     x9, x21, x20                    /* out of room: resume here next time */
    cmp     x9, #32
    b.hs    63f
    str     x22, [x19, #C_CURSOR]
    b       64f
63: ldr     x9, [x24, #S_FLAGS]
    tst     x9, #SF_DEAD
    b.eq    64f
    mov     x0, x24
    bl      libp2p_stream_free
64: sub     x9, x21, x20
    cmp     x9, #32
    b.lo    9f
    mov     x22, x25
    sub     x23, x23, #1
    b       6b
8:  mov     x9, #NONE
    str     x9, [x19, #C_CURSOR]
9:  ldr     x9, [sp]
    sub     x0, x20, x9
    LEAVE   0, 16
END_FUNCTION libp2p_mux_gather

/* ---------------------------------------------------------------- Drain */

/*
 * libp2p_drain(): for each connection, while the action list has room and the
 * connection has send window: pending CLOSE actions; bytes before the
 * transport keys as they are; then Noise transport messages of bytes
 * before the muxer and muxer frames, as many as fit in one SEND action.
 * Room that runs out asks for an immediate wakeup.
 * x19 connection, x20 connections left.
 */
LOCAL_FUNCTION libp2p_drain
    ENTER   0
    TABLE   x19, ST_CONN_OFF
    ldr     x20, [x27, #ST_CONN_COUNT]
1:  cbz     x20, 9f
    ldr     w9, [x19, #C_PHASE]
    cbz     w9, 3f
    ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_NEED_CLOSE
    b.eq    2f
    bl      libp2p_room
    cmp     x0, #64
    b.lo    8f
    mov     x0, x19
    bl      libp2p_conn_send_close
    b       3f
2:  mov     x0, x19
    bl      libp2p_conn_live
    cbz     x0, 3f
21: mov     x0, x19
    bl      libp2p_drain_conn
    cmp     x0, #2
    b.eq    8f                              /* the action list is full */
    cmp     x0, #1
    b.eq    21b                             /* it sent: try again */
3:  add     x19, x19, #C_SIZE
    sub     x20, x20, #1
    b       1b
8:  ldr     x0, [x28, #SC_NOW]
    bl      libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_drain

/*
 * libp2p_drain_conn(conn) -> 1 when it wrote one SEND action, 0 when the
 * connection has nothing to send or no send window, 2 when the action list
 * has no room.
 * x19 conn, x20 action, x21 data start, x22 bytes written, x23 capacity.
 */
LOCAL_FUNCTION libp2p_drain_conn
    ENTER   0
    mov     x19, x0
    CFG     x10, LIBP2P_CFG_SEND_WINDOW
    ldr     x11, [x19, #C_INFLIGHT]
    sub     x23, x10, x11                   /* send window left */
    mov     x0, #0
    cmp     x23, #4096
    b.lo    99f
    MOV64   x9, 262144                      /* at most 256 KiB in one action */
    cmp     x23, x9
    csel    x23, x23, x9, lo
    bl      libp2p_room
    sub     x9, x0, #(LIBP2P_ACT_SEND_DATA + 64)
    mov     x0, #2
    cmp     x9, #4096
    b.lt    99f
    cmp     x23, x9
    csel    x23, x23, x9, lo
    ldr     x9, [x19, #C_OUT_RAW]           /* anything to send? */
    ldr     x10, [x19, #C_OUT_LEN]
    orr     x9, x9, x10
    cbnz    x9, 1f
    ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_OPEN
    mov     x0, #0
    b.ne    99f
    mov     x0, x19
    bl      libp2p_conn_pending
    cbz     x0, 99f
1:  add     x1, x23, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x1, x1, #~7
    mov     x0, #LIBP2P_ACTION_SEND
    bl      libp2p_action
    mov     x20, x0
    mov     x0, #2
    cbz     x20, 99f
    add     x21, x20, #LIBP2P_ACT_SEND_DATA
    mov     x22, #0
    ldr     x24, [x19, #C_OUT_RAW]          /* bytes that go out as they are */
    cbz     x24, 2f
    mov     x0, x21
    add     x1, x19, #C_OUT
    mov     x2, x24
    bl      libp2p_copy
    mov     x22, x24
    mov     x0, x19
    mov     x1, x24
    bl      libp2p_out_drop
    str     xzr, [x19, #C_OUT_RAW]
2:  ldr     x9, [x19, #C_FLAGS]
    tst     x9, #CF_TRANSPORT
    b.eq    7f
3:  sub     x25, x23, x22                   /* one Noise message */
    cmp     x25, #(18 + 16)
    b.lo    7f
    sub     x25, x25, #18
    MOV64   x9, LIBP2P_NOISE_PLAIN
    cmp     x25, x9
    csel    x25, x25, x9, lo
    SCR     x26, (SC_PLAIN + LIBP2P_BL_FIXED)
    mov     x24, #0
    ldr     x9, [x19, #C_OUT_LEN]           /* bytes before the muxer */
    cbz     x9, 4f
    cmp     x9, x25
    csel    x24, x9, x25, lo
    mov     x0, x26
    add     x1, x19, #C_OUT
    mov     x2, x24
    bl      libp2p_copy
    mov     x0, x19
    mov     x1, x24
    bl      libp2p_out_drop
4:  ldr     w9, [x19, #C_PHASE]
    cmp     w9, #PH_OPEN
    b.ne    5f
    mov     x0, x19
    add     x1, x26, x24
    sub     x2, x25, x24
    bl      libp2p_mux_gather
    add     x24, x24, x0
5:  cbz     x24, 7f
    mov     x0, x19
    mov     x1, x26
    mov     x2, x24
    add     x3, x21, x22
    bl      libp2p_noise_seal
    add     x22, x22, x24
    add     x22, x22, #18
    b       3b
7:  cbz     x22, 8f
    str     x22, [x20, #LIBP2P_ACT_SEND_COUNT]
    mov     x0, x19
    bl      libp2p_conn_handle
    str     x0, [x20, #LIBP2P_ACT_CONN]
    add     x1, x22, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x1, x1, #~7
    mov     x0, x20
    bl      libp2p_action_shrink
    ldr     x9, [x19, #C_INFLIGHT]
    add     x9, x9, x22
    str     x9, [x19, #C_INFLIGHT]
    mov     x0, #1
    b       99f
8:  mov     x0, x20                         /* nothing after all: drop the action */
    mov     x1, #0
    bl      libp2p_action_shrink
    mov     x0, #0
99: LEAVE   0
END_FUNCTION libp2p_drain_conn

/* libp2p_out_drop(conn, n): drops the first n bytes of the output buffer. */
LOCAL_FUNCTION libp2p_out_drop
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #C_OUT_LEN]
    sub     x2, x9, x1
    str     x2, [x19, #C_OUT_LEN]
    add     x0, x19, #C_OUT
    add     x1, x0, x1
    bl      libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_out_drop

/*
 * libp2p_conn_pending(conn) -> 1 when an open connection has frames to send:
 * pongs, resets, or a stream with flags to send, data within its window,
 * or a window update due. A leaf-like walk over its streams.
 */
LOCAL_FUNCTION libp2p_conn_pending
    ENTER   0
    mov     x19, x0
    ldr     x9, [x19, #C_PING_COUNT]
    ldr     x10, [x19, #C_RSTS]
    orr     x9, x9, x10
    mov     x0, #1
    cbnz    x9, 9f
    ldr     x20, [x19, #C_STREAM_HEAD]
1:  cmn     x20, #1
    b.eq    8f
    mov     x0, x20
    bl      libp2p_stream_at
    ldr     x9, [x0, #S_FLAGS]
    mov     x10, #(SF_SYN | SF_ACK | SF_RST | SF_DEAD)
    tst     x9, x10
    b.ne    7f
    and     x10, x9, #(SF_FIN | SF_FIN_SENT)
    cmp     x10, #SF_FIN
    b.eq    7f
    ldr     x10, [x0, #S_RECV_PEND]
    cmp     x10, #65536
    b.hs    7f
    ldr     x10, [x0, #S_Q_HEAD]
    cmn     x10, #1
    b.eq    2f
    ldr     x11, [x19, #C_FLAGS]
    tst     x11, #CF_YAMUX
    b.eq    7f
    ldr     x10, [x0, #S_SEND_WIN]
    cbnz    x10, 7f
2:  ldr     x20, [x0, #S_NEXT]
    b       1b
7:  mov     x0, #1
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_conn_pending

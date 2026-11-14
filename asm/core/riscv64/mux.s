/*
 * Muxers of the RISC-V core: yamux (/yamux/1.0.0) and mplex (/mplex/6.7.0)
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
    ld      t0, C_FLAGS(a0)
    andi    t0, t0, CF_YAMUX
    beqz    t0, 1f
    call    libp2p_yamux_feed
    j       9f
1:  call    libp2p_mplex_feed
9:  LEAVE   0
END_FUNCTION libp2p_mux_feed

/*
 * libp2p_mux_data(conn, p, n) -> n: data bytes of the current frame go to its
 * stream (with the yamux window counted); when the frame ends, its flags
 * act.
 */
LOCAL_FUNCTION libp2p_mux_data
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    ld      t0, C_MX_REMAIN(s1)
    mv      s3, a2
    bltu    a2, t0, 1f
    mv      s3, t0
1:  sub     t0, t0, s3
    sd      t0, C_MX_REMAIN(s1)
    ld      t0, C_MX_STREAM(s1)
    li      t1, NONE
    beq     t0, t1, 3f
    mv      a0, t0
    call    libp2p_stream_at
    mv      s4, a0
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_YAMUX
    beqz    t0, 2f
    ld      t0, S_RECV_WIN(s4)
    sub     t0, t0, s3
    sd      t0, S_RECV_WIN(s4)
    ld      t0, S_RECV_PEND(s4)
    add     t0, t0, s3
    sd      t0, S_RECV_PEND(s4)
2:  mv      a0, s4
    mv      a1, s2
    mv      a2, s3
    call    libp2p_stream_data
3:  ld      t0, C_MX_REMAIN(s1)
    bnez    t0, 9f
    mv      a0, s1
    call    libp2p_mux_end_frame
9:  mv      a0, s3
    LEAVE   0
END_FUNCTION libp2p_mux_data

/* libp2p_mux_end_frame(conn): a frame ended: its FIN or RST acts on its stream. */
LOCAL_FUNCTION libp2p_mux_end_frame
    ENTER   0
    mv      s1, a0
    ld      t0, C_MX_STREAM(s1)
    li      t1, NONE
    sd      t1, C_MX_STREAM(s1)
    beq     t0, t1, 9f
    mv      a0, t0
    call    libp2p_stream_at
    mv      s2, a0
    lwu     t0, S_USED(s2)
    beqz    t0, 9f
    ld      s3, C_MX_FLAGS(s1)
    andi    t0, s3, YF_RST
    beqz    t0, 1f
    mv      a0, s2                          # the peer reset the stream
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_stream_kill
    j       9f
1:  andi    t0, s3, YF_FIN
    beqz    t0, 9f
    mv      a0, s2
    call    libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_mux_end_frame

/* libp2p_mux_find(conn, id, local) -> the stream of the connection with the muxer ID and side, or 0. */
LOCAL_FUNCTION libp2p_mux_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, C_STREAM_HEAD(s1)
1:  li      t0, NONE
    beq     s4, t0, 8f
    mv      a0, s4
    call    libp2p_stream_at
    ld      t0, S_ID(a0)
    bne     t0, s2, 2f
    ld      t0, S_FLAGS(a0)
    andi    t0, t0, SF_LOCAL
    beq     t0, s3, 9f
2:  ld      s4, S_NEXT(a0)
    j       1b
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_mux_find

/* libp2p_mux_rst(conn, id): a reset for a stream that has no slot, sent by the next drain. A leaf. */
LOCAL_FUNCTION libp2p_mux_rst
    UNWIND_END_PROLOGUE
    ld      a2, C_RSTS(a0)
    li      a3, 6
    bgeu    a2, a3, 9f
    addi    a3, a0, C_RST_IDS
    slli    a4, a2, 2
    add     a3, a3, a4
    sw      a1, 0(a3)
    addi    a2, a2, 1
    sd      a2, C_RSTS(a0)
9:  ret
END_FUNCTION libp2p_mux_rst

/* libp2p_mux_error(conn) -> 0: the peer broke the muxer protocol; the connection ends. */
LOCAL_FUNCTION libp2p_mux_error
    ENTER   0
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_close
    li      a0, 0
    LEAVE   0
END_FUNCTION libp2p_mux_error

/* ---------------------------------------------------------------- yamux input */

/* libp2p_yamux_feed(conn, p, n) -> bytes taken: frame data, or header bytes; a whole header is handled. */
LOCAL_FUNCTION libp2p_yamux_feed
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, C_MX_REMAIN(s1)
    beqz    t0, 1f
    call    libp2p_mux_data
    j       9f
1:  ld      s4, C_MX_HLEN(s1)
    li      t0, 12
    sub     t0, t0, s4
    mv      s5, s3
    bltu    s3, t0, 2f
    mv      s5, t0
2:  addi    a0, s1, C_MX_HDR
    add     a0, a0, s4
    mv      a1, s2
    mv      a2, s5
    call    libp2p_copy
    add     s4, s4, s5
    sd      s4, C_MX_HLEN(s1)
    li      t0, 12
    bltu    s4, t0, 8f
    sd      zero, C_MX_HLEN(s1)
    mv      a0, s1
    call    libp2p_yamux_frame
8:  mv      a0, s5
9:  LEAVE   0
END_FUNCTION libp2p_yamux_feed

/* rd = the n (2 or 4) bytes at base + off, big endian. Uses tmp. */
.macro BEN rd, base, off, n, tmp
    lbu     \rd, \off(\base)
    .irp i, 1, 2, 3
    .if \i < \n
    lbu     \tmp, (\off + \i)(\base)
    slli    \rd, \rd, 8
    or      \rd, \rd, \tmp
    .endif
    .endr
.endm

/*
 * libp2p_yamux_frame(conn): one 12-byte header: version 0, type, flags, stream
 * ID and length, big endian.
 * s1 conn, s2 type, s3 flags, s4 ID, s5 length, s6 stream.
 */
LOCAL_FUNCTION libp2p_yamux_frame
    ENTER   0
    mv      s1, a0
    addi    t0, s1, C_MX_HDR
    lbu     t1, 0(t0)
    bnez    t1, 80f
    lbu     s2, 1(t0)
    BEN     s3, t0, 2, 2, t1
    BEN     s4, t0, 4, 4, t1
    BEN     s5, t0, 8, 4, t1
    li      t1, YT_PING
    bne     s2, t1, 1f
    andi    t1, s3, YF_SYN                  # a ping: answer it
    beqz    t1, 99f
    ld      t0, C_PING_COUNT(s1)
    li      t1, 4
    bgeu    t0, t1, 99f
    addi    t1, s1, C_PINGS
    slli    t2, t0, 2
    add     t1, t1, t2
    sw      s5, 0(t1)
    addi    t0, t0, 1
    sd      t0, C_PING_COUNT(s1)
    j       99f
1:  li      t1, YT_GOAWAY
    bne     s2, t1, 2f
    mv      a0, s1
    li      a1, LIBP2P_REASON_CLOSED
    call    libp2p_conn_close
    j       99f
2:  li      t1, YT_WINDOW
    bltu    t1, s2, 80f
    beqz    s4, 80f
    mv      a0, s1
    mv      a1, s4
    mv      a2, s3
    call    libp2p_yamux_stream
    li      t0, NONE
    beq     a0, t0, 80f
    mv      s6, a0
    sd      s3, C_MX_FLAGS(s1)
    li      t0, NONE
    beqz    s6, 3f
    mv      a0, s6
    call    libp2p_stream_index
    mv      t0, a0
3:  sd      t0, C_MX_STREAM(s1)
    li      t1, YT_DATA
    bne     s2, t1, 4f
    beqz    s6, 31f                         # data: within the window
    ld      t0, S_RECV_WIN(s6)
    bltu    t0, s5, 80f
31: sd      s5, C_MX_REMAIN(s1)
    bnez    s5, 99f
    mv      a0, s1
    call    libp2p_mux_end_frame
    j       99f
4:  beqz    s6, 41f                         # a window update
    ld      t0, S_SEND_WIN(s6)
    add     t0, t0, s5
    sd      t0, S_SEND_WIN(s6)
41: mv      a0, s1
    call    libp2p_mux_end_frame
    j       99f
80: mv      a0, s1
    call    libp2p_mux_error
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
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    andi    t0, s3, YF_SYN
    bnez    t0, 1f
    li      a2, SF_LOCAL                    # ours, then the peer's
    call    libp2p_mux_find
    bnez    a0, 9f
    mv      a0, s1
    mv      a1, s2
    li      a2, 0
    call    libp2p_mux_find
    j       9f
1:  ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_OUTBOUND             # the peer's IDs: even when we dialled
    andi    t1, s2, 1
    xori    t1, t1, 1
    bne     t0, t1, 8f
    mv      a0, s1
    mv      a1, s2
    li      a2, 0
    call    libp2p_mux_find
    bnez    a0, 8f
    ld      t0, C_BACKLOG(s1)
    li      t1, LIBP2P_YAMUX_BACKLOG
    bgeu    t0, t1, 7f
    mv      a0, s1
    mv      a1, s2
    li      a2, 0
    call    libp2p_stream_new
    beqz    a0, 7f
    ld      t0, S_FLAGS(a0)
    ori     t0, t0, SF_ACK
    sd      t0, S_FLAGS(a0)
    ld      t0, C_BACKLOG(s1)
    addi    t0, t0, 1
    sd      t0, C_BACKLOG(s1)
    j       9f
7:  mv      a0, s1
    mv      a1, s2
    call    libp2p_mux_rst
    li      a0, 0
    j       9f
8:  li      a0, NONE
9:  LEAVE   0
END_FUNCTION libp2p_yamux_stream

/* ---------------------------------------------------------------- mplex input */

/*
 * libp2p_mplex_feed(conn, p, n) -> bytes taken: message data, or header bytes
 * one at a time until both varints of the header are whole.
 * s1 conn, s2 p, s3 n, s4 header bytes, s5 taken, s6 the first varint.
 */
LOCAL_FUNCTION libp2p_mplex_feed
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, C_MX_REMAIN(s1)
    beqz    t0, 1f
    call    libp2p_mux_data
    j       9f
1:  ld      s4, C_MX_HLEN(s1)
    li      s5, 0
2:  bgeu    s5, s3, 8f
    li      t0, 20
    bgeu    s4, t0, 80f
    add     t0, s2, s5
    lbu     t0, 0(t0)
    addi    t1, s1, C_MX_HDR
    add     t1, t1, s4
    sb      t0, 0(t1)
    addi    s4, s4, 1
    addi    s5, s5, 1
    sd      s4, C_MX_HLEN(s1)
    addi    a0, s1, C_MX_HDR
    add     a1, a0, s4
    call    libp2p_varint_get
    li      t0, NONE
    beq     a1, t0, 80f
    beqz    a1, 2b
    mv      s6, a0
    addi    a0, s1, C_MX_HDR
    add     a0, a0, a1
    addi    a1, s1, C_MX_HDR
    add     a1, a1, s4
    call    libp2p_varint_get
    li      t0, NONE
    beq     a1, t0, 80f
    beqz    a1, 2b
    sd      zero, C_MX_HLEN(s1)
    mv      a2, a0
    mv      a0, s1
    mv      a1, s6
    call    libp2p_mplex_frame
    j       8f
80: mv      a0, s1
    call    libp2p_mux_error
8:  mv      a0, s5
9:  LEAVE   0
END_FUNCTION libp2p_mplex_feed

/*
 * libp2p_mplex_frame(conn, header, length): one mplex header: the stream ID and
 * flag in the first varint, the data length in the second.
 * s1 conn, s2 ID, s3 flag, s4 length, s5 stream.
 */
LOCAL_FUNCTION libp2p_mplex_frame
    ENTER   0
    mv      s1, a0
    srli    s2, a1, 3
    andi    s3, a1, 7
    mv      s4, a2
    li      t0, LIBP2P_MPLEX_MAX
    bltu    t0, s4, 80f
    li      t0, MP_RESET_INITIATOR
    bltu    t0, s3, 80f
    srli    t0, s2, 28                      # IDs below 2^28
    bnez    t0, 80f
    sd      s4, C_MX_REMAIN(s1)
    li      t0, NONE
    sd      t0, C_MX_STREAM(s1)
    sd      zero, C_MX_FLAGS(s1)
    bnez    s3, 1f
    mv      a0, s1                          # NewStream: the data is a name, dropped
    mv      a1, s2
    li      a2, 0
    call    libp2p_mux_find
    bnez    a0, 80f
    mv      a0, s1
    mv      a1, s2
    li      a2, 0
    call    libp2p_stream_new
    bnez    a0, 9f
    mv      a0, s1
    slli    a1, s2, 3
    addi    a1, a1, MP_RESET_RECEIVER
    call    libp2p_mux_rst
    j       9f
1:  andi    t0, s3, 1                       # odd flags: from the receiver, so the stream is ours
    li      a2, 0
    beqz    t0, 2f
    li      a2, SF_LOCAL
2:  mv      a0, s1
    mv      a1, s2
    call    libp2p_mux_find
    mv      s5, a0
    beqz    s5, 9f                          # no such stream: drop the data
    mv      a0, s5
    call    libp2p_stream_index
    sd      a0, C_MX_STREAM(s1)
    li      t0, MP_MSG_INITIATOR
    bgeu    t0, s3, 9f
    li      t1, YF_FIN                      # close, or reset
    li      t0, MP_CLOSE_INITIATOR
    bgeu    t0, s3, 3f
    li      t1, YF_RST
3:  sd      t1, C_MX_FLAGS(s1)
9:  ld      t0, C_MX_REMAIN(s1)
    bnez    t0, 99f
    mv      a0, s1
    call    libp2p_mux_end_frame
    j       99f
80: mv      a0, s1
    call    libp2p_mux_error
99: LEAVE   0
END_FUNCTION libp2p_mplex_frame

/* ---------------------------------------------------------------- Frame output */

/* libp2p_yamux_header(dst, type, flags, id, length) -> dst + 12, big endian bytes (dst may be unaligned). A leaf. */
LOCAL_FUNCTION libp2p_yamux_header
    UNWIND_END_PROLOGUE
    sb      zero, 0(a0)
    sb      a1, 1(a0)
    srli    a5, a2, 8
    sb      a5, 2(a0)
    sb      a2, 3(a0)
    srli    a5, a3, 24
    sb      a5, 4(a0)
    srli    a5, a3, 16
    sb      a5, 5(a0)
    srli    a5, a3, 8
    sb      a5, 6(a0)
    sb      a3, 7(a0)
    srli    a5, a4, 24
    sb      a5, 8(a0)
    srli    a5, a4, 16
    sb      a5, 9(a0)
    srli    a5, a4, 8
    sb      a5, 10(a0)
    sb      a4, 11(a0)
    addi    a0, a0, 12
    ret
END_FUNCTION libp2p_yamux_header

/* libp2p_mplex_header(dst, header, length) -> dst after the two varints. */
LOCAL_FUNCTION libp2p_mplex_header
    ENTER   0
    mv      s1, a2
    call    libp2p_varint_put
    mv      a1, s1
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_mplex_header

/*
 * libp2p_chunk_take(stream, dst, max) -> the bytes copied to dst from the head
 * chunk of the queue, at most max; a chunk that is all sent is freed.
 * s1 stream, s2 dst, s3 the chunk, s4 its block, s5 bytes.
 */
LOCAL_FUNCTION libp2p_chunk_take
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    ld      s3, S_Q_HEAD(s1)
    addi    s4, s3, -HB_HEADER
    add     s4, s9, s4
    ld      t0, CH_LEN(s4)
    ld      t1, CH_DONE(s4)
    sub     t0, t0, t1
    mv      s5, a2
    bltu    a2, t0, 1f
    mv      s5, t0
1:  mv      a0, s2
    addi    a1, s4, CH_DATA
    add     a1, a1, t1
    mv      a2, s5
    call    libp2p_copy
    ld      t1, CH_DONE(s4)
    add     t1, t1, s5
    sd      t1, CH_DONE(s4)
    ld      t0, S_Q_BYTES(s1)
    sub     t0, t0, s5
    sd      t0, S_Q_BYTES(s1)
    ld      t0, CH_LEN(s4)
    bltu    t1, t0, 9f
    ld      t0, CH_NEXT(s4)
    sd      t0, S_Q_HEAD(s1)
    li      t1, NONE
    bne     t0, t1, 2f
    sd      t0, S_Q_TAIL(s1)
2:  mv      a0, s3
    call    libp2p_heap_free
9:  mv      a0, s5
    LEAVE   0
END_FUNCTION libp2p_chunk_take

/*
 * libp2p_yamux_emit(conn, stream, dst, room) -> dst after what it wrote: RST; SYN; ACK;
 * a window update once 64 KiB were taken; data frames within the send
 * window; FIN after the queue. A stream with RST, or closed both ways and
 * empty, becomes dead.
 * s1 conn, s2 stream, s3 position, s4 end, s5 flags, s6 ID, s7 bytes.
 */
LOCAL_FUNCTION libp2p_yamux_emit
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    add     s4, a2, a3
    ld      s5, S_FLAGS(s2)
    ld      s6, S_ID(s2)
    andi    t0, s5, SF_RST
    beqz    t0, 1f
    sub     t0, s4, s3
    li      t1, 12
    bltu    t0, t1, 90f
    mv      a0, s3
    li      a1, YT_WINDOW
    li      a2, YF_RST
    mv      a3, s6
    li      a4, 0
    call    libp2p_yamux_header
    mv      s3, a0
    ori     s5, s5, SF_DEAD
    j       90f
1:  andi    t0, s5, (SF_SYN | SF_ACK)
    beqz    t0, 2f
    sub     t0, s4, s3
    li      t1, 12
    bltu    t0, t1, 90f
    andi    a2, s5, SF_SYN                  # SF_SYN is 2: YF_SYN after the shift; SF_ACK is 4
    srli    a2, a2, 1
    andi    t0, s5, SF_ACK
    beqz    t0, 10f
    li      a2, YF_ACK
10: mv      a0, s3
    li      a1, YT_WINDOW
    mv      a3, s6
    li      a4, 0
    call    libp2p_yamux_header
    mv      s3, a0
    andi    t0, s5, SF_ACK
    beqz    t0, 11f
    ld      t0, C_BACKLOG(s1)
    addi    t0, t0, -1
    sd      t0, C_BACKLOG(s1)
11: andi    s5, s5, ~(SF_SYN | SF_ACK)
2:  ld      t0, S_RECV_PEND(s2)
    li      t1, 65536
    bltu    t0, t1, 3f
    sub     t1, s4, s3
    li      t2, 12
    bltu    t1, t2, 90f
    mv      a0, s3
    li      a1, YT_WINDOW
    li      a2, 0
    mv      a3, s6
    mv      a4, t0
    call    libp2p_yamux_header
    mv      s3, a0
    ld      t0, S_RECV_PEND(s2)
    ld      t1, S_RECV_WIN(s2)
    add     t1, t1, t0
    sd      t1, S_RECV_WIN(s2)
    sd      zero, S_RECV_PEND(s2)
3:  ld      t0, S_Q_HEAD(s2)                # data
    li      t1, NONE
    beq     t0, t1, 4f
    ld      t1, S_SEND_WIN(s2)
    beqz    t1, 90f
    sub     t2, s4, s3
    li      t3, 13
    bltu    t2, t3, 90f
    addi    t2, t2, -12
    mv      a2, t1
    bltu    t1, t2, 31f
    mv      a2, t2
31: mv      a0, s2
    addi    a1, s3, 12
    call    libp2p_chunk_take
    mv      s7, a0
    mv      a4, a0
    mv      a0, s3
    li      a1, YT_DATA
    li      a2, 0
    mv      a3, s6
    call    libp2p_yamux_header
    add     s3, a0, s7
    ld      t0, S_SEND_WIN(s2)
    sub     t0, t0, s7
    sd      t0, S_SEND_WIN(s2)
    j       3b
4:  andi    t0, s5, SF_FIN                  # FIN after the queue
    beqz    t0, 5f
    andi    t0, s5, SF_FIN_SENT
    bnez    t0, 5f
    sub     t0, s4, s3
    li      t1, 12
    bltu    t0, t1, 90f
    mv      a0, s3
    li      a1, YT_WINDOW
    li      a2, YF_FIN
    mv      a3, s6
    li      a4, 0
    call    libp2p_yamux_header
    mv      s3, a0
    ori     s5, s5, SF_FIN_SENT
5:  andi    t0, s5, (SF_FIN_SENT | SF_REMOTE_FIN)
    li      t1, (SF_FIN_SENT | SF_REMOTE_FIN)
    bne     t0, t1, 90f
    ori     s5, s5, SF_DEAD
90: sd      s5, S_FLAGS(s2)
    mv      a0, s3
    LEAVE   0
END_FUNCTION libp2p_yamux_emit

/*
 * libp2p_mplex_emit(conn, stream, dst, room) -> dst after what it wrote: reset;
 * NewStream with the decimal ID as name; data messages; close after the
 * queue. The flags say which side opened the stream.
 * s1 conn, s2 stream, s3 position, s4 end, s5 flags, s6 ID << 3,
 * s7 1 when we opened it, s8 bytes. The name: sp + FL, backwards.
 */
LOCAL_FUNCTION libp2p_mplex_emit
    ENTER   0, 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    add     s4, a2, a3
    ld      s5, S_FLAGS(s2)
    ld      s6, S_ID(s2)
    slli    s6, s6, 3
    andi    s7, s5, SF_LOCAL
    andi    t0, s5, SF_RST
    beqz    t0, 1f
    sub     t0, s4, s3
    li      t1, 16
    bltu    t0, t1, 90f
    li      t0, MP_RESET_RECEIVER
    beqz    s7, 10f
    li      t0, MP_RESET_INITIATOR
10: or      a1, s6, t0
    mv      a0, s3
    li      a2, 0
    call    libp2p_mplex_header
    mv      s3, a0
    ori     s5, s5, SF_DEAD
    j       90f
1:  andi    t0, s5, SF_SYN
    beqz    t0, 3f
    sub     t0, s4, s3
    li      t1, 48
    bltu    t0, t1, 90f
    ld      t0, S_ID(s2)                    # the name: the decimal ID, backwards on the stack
    li      t1, 0
    li      t2, 10
2:  divu    t3, t0, t2
    remu    t4, t0, t2
    addi    t4, t4, '0'
    addi    t5, sp, FL
    add     t5, t5, t1
    sb      t4, 0(t5)
    addi    t1, t1, 1
    mv      t0, t3
    bnez    t0, 2b
    mv      s8, t1
    mv      a0, s3
    mv      a1, s6
    mv      a2, s8
    call    libp2p_mplex_header
21: addi    s8, s8, -1
    addi    t5, sp, FL
    add     t5, t5, s8
    lbu     t0, 0(t5)
    sb      t0, 0(a0)
    addi    a0, a0, 1
    bnez    s8, 21b
    mv      s3, a0
    andi    s5, s5, ~SF_SYN
3:  ld      t0, S_Q_HEAD(s2)                # data
    li      t1, NONE
    beq     t0, t1, 4f
    sub     t2, s4, s3
    li      t1, 17
    bltu    t2, t1, 90f
    addi    a2, t2, -16
    mv      a0, s2
    addi    a1, s3, 16                      # data after room for the header, moved down below
    call    libp2p_chunk_take
    mv      s8, a0
    li      t0, MP_MSG_RECEIVER
    beqz    s7, 31f
    li      t0, MP_MSG_INITIATOR
31: or      a1, s6, t0
    mv      a0, s3
    mv      a2, s8
    call    libp2p_mplex_header
    addi    a1, s3, 16
    mv      a2, s8
    call    libp2p_copy
    mv      s3, a0
    j       3b
4:  andi    t0, s5, SF_FIN
    beqz    t0, 5f
    andi    t0, s5, SF_FIN_SENT
    bnez    t0, 5f
    sub     t0, s4, s3
    li      t1, 16
    bltu    t0, t1, 90f
    li      t0, MP_CLOSE_RECEIVER
    beqz    s7, 41f
    li      t0, MP_CLOSE_INITIATOR
41: or      a1, s6, t0
    mv      a0, s3
    li      a2, 0
    call    libp2p_mplex_header
    mv      s3, a0
    ori     s5, s5, SF_FIN_SENT
5:  andi    t0, s5, (SF_FIN_SENT | SF_REMOTE_FIN)
    li      t1, (SF_FIN_SENT | SF_REMOTE_FIN)
    bne     t0, t1, 90f
    ori     s5, s5, SF_DEAD
90: sd      s5, S_FLAGS(s2)
    mv      a0, s3
    LEAVE   0, 32
END_FUNCTION libp2p_mplex_emit

/*
 * libp2p_mux_gather(conn, dst, room) -> bytes written: connection frames
 * (pongs, resets of streams without a slot), then the frames of each
 * stream in turn from the cursor; dead streams are freed.
 * s1 conn, s2 position, s3 end, s4 stream index, s5 streams visited,
 * s6 stream, s7 next. The start at sp + FL.
 */
LOCAL_FUNCTION libp2p_mux_gather
    ENTER   0, 16
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    sd      a1, FL(sp)
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_YAMUX
    beqz    t0, 3f
1:  ld      t0, C_PING_COUNT(s1)            # yamux pongs
    beqz    t0, 2f
    sub     t1, s3, s2
    li      t2, 12
    bltu    t1, t2, 9f
    addi    t0, t0, -1
    sd      t0, C_PING_COUNT(s1)
    addi    t1, s1, C_PINGS
    slli    t2, t0, 2
    add     t1, t1, t2
    lwu     a4, 0(t1)
    mv      a0, s2
    li      a1, YT_PING
    li      a2, YF_ACK
    li      a3, 0
    call    libp2p_yamux_header
    mv      s2, a0
    j       1b
2:  ld      t0, C_RSTS(s1)                  # yamux resets
    beqz    t0, 5f
    sub     t1, s3, s2
    li      t2, 12
    bltu    t1, t2, 9f
    addi    t0, t0, -1
    sd      t0, C_RSTS(s1)
    addi    t1, s1, C_RST_IDS
    slli    t2, t0, 2
    add     t1, t1, t2
    lwu     a3, 0(t1)
    mv      a0, s2
    li      a1, YT_WINDOW
    li      a2, YF_RST
    li      a4, 0
    call    libp2p_yamux_header
    mv      s2, a0
    j       2b
3:  ld      t0, C_RSTS(s1)                  # mplex resets: the header is stored
    beqz    t0, 5f
    sub     t1, s3, s2
    li      t2, 16
    bltu    t1, t2, 9f
    addi    t0, t0, -1
    sd      t0, C_RSTS(s1)
    addi    t1, s1, C_RST_IDS
    slli    t2, t0, 2
    add     t1, t1, t2
    lwu     a1, 0(t1)
    mv      a0, s2
    li      a2, 0
    call    libp2p_mplex_header
    mv      s2, a0
    j       3b
5:  ld      s4, C_CURSOR(s1)                # the streams, from the cursor
    li      t0, NONE
    bne     s4, t0, 51f
    ld      s4, C_STREAM_HEAD(s1)
51: ld      s5, C_STREAMS(s1)
6:  beqz    s5, 8f
    li      t0, NONE
    bne     s4, t0, 61f
    ld      s4, C_STREAM_HEAD(s1)
    beq     s4, t0, 8f
61: mv      a0, s4
    call    libp2p_stream_at
    mv      s6, a0
    ld      s7, S_NEXT(s6)
    ld      t0, S_FLAGS(s6)
    andi    t0, t0, SF_DEAD
    bnez    t0, 63f
    mv      a0, s1
    mv      a1, s6
    mv      a2, s2
    sub     a3, s3, s2
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_YAMUX
    beqz    t0, 62f
    call    libp2p_yamux_emit
    j       621f
62: call    libp2p_mplex_emit
621: mv     s2, a0
    sub     t0, s3, s2                      # out of room: resume here next time
    li      t1, 32
    bgeu    t0, t1, 63f
    sd      s4, C_CURSOR(s1)
    j       64f
63: ld      t0, S_FLAGS(s6)
    andi    t0, t0, SF_DEAD
    beqz    t0, 64f
    mv      a0, s6
    call    libp2p_stream_free
64: sub     t0, s3, s2
    li      t1, 32
    bltu    t0, t1, 9f
    mv      s4, s7
    addi    s5, s5, -1
    j       6b
8:  li      t0, NONE
    sd      t0, C_CURSOR(s1)
9:  ld      t0, FL(sp)
    sub     a0, s2, t0
    LEAVE   0, 16
END_FUNCTION libp2p_mux_gather

/* ---------------------------------------------------------------- Drain */

/*
 * libp2p_drain(): for each connection, while the action list has room and the
 * connection has send window: pending CLOSE actions; bytes before the
 * transport keys as they are; then Noise transport messages of bytes
 * before the muxer and muxer frames, as many as fit in one SEND action.
 * Room that runs out asks for an immediate wakeup.
 * s1 connection, s2 connections left.
 */
LOCAL_FUNCTION libp2p_drain
    ENTER   0
    TABLE   s1, ST_CONN_OFF
    ld      s2, ST_CONN_COUNT(s9)
1:  beqz    s2, 9f
    lwu     t0, C_PHASE(s1)
    beqz    t0, 3f
    ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_NEED_CLOSE
    beqz    t0, 2f
    call    libp2p_room
    li      t0, 64
    bltu    a0, t0, 8f
    mv      a0, s1
    call    libp2p_conn_send_close
    j       3f
2:  mv      a0, s1
    call    libp2p_conn_live
    beqz    a0, 3f
21: mv      a0, s1
    call    libp2p_drain_conn
    li      t0, 2
    beq     a0, t0, 8f                      # the action list is full
    li      t0, 1
    beq     a0, t0, 21b                     # it sent: try again
3:  addi    s1, s1, C_SIZE
    addi    s2, s2, -1
    j       1b
8:  ld      a0, SC_NOW(s10)
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_drain

/*
 * libp2p_drain_conn(conn) -> 1 when it wrote one SEND action, 0 when the
 * connection has nothing to send or no send window, 2 when the action list
 * has no room.
 * s1 conn, s2 action, s3 data start, s4 bytes written, s5 capacity,
 * s6 bytes of one message, s7 the plaintext, s8 bytes in it.
 */
LOCAL_FUNCTION libp2p_drain_conn
    ENTER   0
    mv      s1, a0
    CFG     t1, LIBP2P_CFG_SEND_WINDOW
    ld      t2, C_INFLIGHT(s1)
    sub     s5, t1, t2                      # send window left
    li      a0, 0
    li      t0, 4096
    bltu    s5, t0, 99f
    li      t0, 262144                      # at most 256 KiB in one action
    bltu    s5, t0, 10f
    mv      s5, t0
10: call    libp2p_room
    addi    t0, a0, -(LIBP2P_ACT_SEND_DATA + 64)
    li      a0, 2
    li      t1, 4096
    blt     t0, t1, 99f
    bltu    s5, t0, 11f
    mv      s5, t0
11: ld      t0, C_OUT_RAW(s1)               # anything to send?
    ld      t1, C_OUT_LEN(s1)
    or      t0, t0, t1
    bnez    t0, 1f
    lwu     t0, C_PHASE(s1)
    li      t1, PH_OPEN
    li      a0, 0
    bne     t0, t1, 99f
    mv      a0, s1
    call    libp2p_conn_pending
    beqz    a0, 99f
1:  addi    a1, s5, (LIBP2P_ACT_SEND_DATA + 7)
    andi    a1, a1, -8
    li      a0, LIBP2P_ACTION_SEND
    call    libp2p_action
    mv      s2, a0
    li      a0, 2
    beqz    s2, 99f
    addi    s3, s2, LIBP2P_ACT_SEND_DATA
    li      s4, 0
    ld      s8, C_OUT_RAW(s1)               # bytes that go out as they are
    beqz    s8, 2f
    mv      a0, s3
    addi    a1, s1, C_OUT
    mv      a2, s8
    call    libp2p_copy
    mv      s4, s8
    mv      a0, s1
    mv      a1, s8
    call    libp2p_out_drop
    sd      zero, C_OUT_RAW(s1)
2:  ld      t0, C_FLAGS(s1)
    andi    t0, t0, CF_TRANSPORT
    beqz    t0, 7f
3:  sub     s6, s5, s4                      # one Noise message
    li      t0, (18 + 16)
    bltu    s6, t0, 7f
    addi    s6, s6, -18
    li      t0, LIBP2P_NOISE_PLAIN
    bltu    s6, t0, 31f
    mv      s6, t0
31: SCR     s7, (SC_PLAIN + LIBP2P_BL_FIXED)
    li      s8, 0
    ld      t0, C_OUT_LEN(s1)               # bytes before the muxer
    beqz    t0, 4f
    mv      s8, t0
    bltu    t0, s6, 32f
    mv      s8, s6
32: mv      a0, s7
    addi    a1, s1, C_OUT
    mv      a2, s8
    call    libp2p_copy
    mv      a0, s1
    mv      a1, s8
    call    libp2p_out_drop
4:  lwu     t0, C_PHASE(s1)
    li      t1, PH_OPEN
    bne     t0, t1, 5f
    mv      a0, s1
    add     a1, s7, s8
    sub     a2, s6, s8
    call    libp2p_mux_gather
    add     s8, s8, a0
5:  beqz    s8, 7f
    mv      a0, s1
    mv      a1, s7
    mv      a2, s8
    add     a3, s3, s4
    call    libp2p_noise_seal
    add     s4, s4, s8
    addi    s4, s4, 18
    j       3b
7:  beqz    s4, 8f
    sd      s4, LIBP2P_ACT_SEND_COUNT(s2)
    mv      a0, s1
    call    libp2p_conn_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    addi    a1, s4, (LIBP2P_ACT_SEND_DATA + 7)
    andi    a1, a1, -8
    mv      a0, s2
    call    libp2p_action_shrink
    ld      t0, C_INFLIGHT(s1)
    add     t0, t0, s4
    sd      t0, C_INFLIGHT(s1)
    li      a0, 1
    j       99f
8:  mv      a0, s2                          # nothing after all: drop the action
    li      a1, 0
    call    libp2p_action_shrink
    li      a0, 0
99: LEAVE   0
END_FUNCTION libp2p_drain_conn

/* libp2p_out_drop(conn, n): drops the first n bytes of the output buffer. */
LOCAL_FUNCTION libp2p_out_drop
    ENTER   0
    mv      s1, a0
    ld      t0, C_OUT_LEN(s1)
    sub     a2, t0, a1
    sd      a2, C_OUT_LEN(s1)
    addi    a0, s1, C_OUT
    add     a1, a0, a1
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_out_drop

/*
 * libp2p_conn_pending(conn) -> 1 when an open connection has frames to send:
 * pongs, resets, or a stream with flags to send, data within its window,
 * or a window update due. A leaf-like walk over its streams.
 */
LOCAL_FUNCTION libp2p_conn_pending
    ENTER   0
    mv      s1, a0
    ld      t0, C_PING_COUNT(s1)
    ld      t1, C_RSTS(s1)
    or      t0, t0, t1
    li      a0, 1
    bnez    t0, 9f
    ld      s2, C_STREAM_HEAD(s1)
1:  li      t0, NONE
    beq     s2, t0, 8f
    mv      a0, s2
    call    libp2p_stream_at
    ld      t0, S_FLAGS(a0)
    andi    t1, t0, (SF_SYN | SF_ACK | SF_RST | SF_DEAD)
    bnez    t1, 7f
    andi    t1, t0, (SF_FIN | SF_FIN_SENT)
    li      t2, SF_FIN
    beq     t1, t2, 7f
    ld      t1, S_RECV_PEND(a0)
    li      t2, 65536
    bgeu    t1, t2, 7f
    ld      t1, S_Q_HEAD(a0)
    li      t2, NONE
    beq     t1, t2, 2f
    ld      t2, C_FLAGS(s1)
    andi    t2, t2, CF_YAMUX
    beqz    t2, 7f
    ld      t1, S_SEND_WIN(a0)
    bnez    t1, 7f
2:  ld      s2, S_NEXT(a0)
    j       1b
7:  li      a0, 1
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_conn_pending

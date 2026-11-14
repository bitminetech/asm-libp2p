/*
 * Muxers of the x86-64 core: yamux (/yamux/1.0.0) and mplex (/mplex/6.7.0)
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
    FRAME
    testq   $CF_YAMUX, C_FLAGS(%rdi)
    jz      1f
    call    libp2p_yamux_feed
    jmp     9f
1:  call    libp2p_mplex_feed
9:  UNFRAME
END_FUNCTION libp2p_mux_feed

/*
 * libp2p_mux_data(conn, p, n) -> the bytes taken: data bytes of the current
 * frame go to its stream (with the yamux window counted); when the frame
 * ends, its flags act. rbx conn, rbp p, r12 taken, r13 stream.
 */
LOCAL_FUNCTION libp2p_mux_data
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     C_MX_REMAIN(%rbx), %rax
    mov     %rdx, %r12
    cmp     %rax, %r12
    cmova   %rax, %r12
    sub     %r12, %rax
    mov     %rax, C_MX_REMAIN(%rbx)
    mov     C_MX_STREAM(%rbx), %rdi
    cmp     $NONE, %rdi
    je      2f
    call    libp2p_stream_at
    mov     %rax, %r13
    testq   $CF_YAMUX, C_FLAGS(%rbx)
    jz      1f
    sub     %r12, S_RECV_WIN(%r13)
    add     %r12, S_RECV_PEND(%r13)
1:  mov     %r13, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_stream_data
2:  cmpq    $0, C_MX_REMAIN(%rbx)
    jne     9f
    mov     %rbx, %rdi
    call    libp2p_mux_end_frame
9:  mov     %r12, %rax
    LEAVE   0
END_FUNCTION libp2p_mux_data

/* libp2p_mux_end_frame(conn): a frame ended: its FIN or RST acts on its stream. */
LOCAL_FUNCTION libp2p_mux_end_frame
    ENTER   0
    mov     %rdi, %rbx
    mov     C_MX_STREAM(%rbx), %rdi
    movq    $NONE, C_MX_STREAM(%rbx)
    cmp     $NONE, %rdi
    je      9f
    call    libp2p_stream_at
    mov     %rax, %rbp
    cmpl    $0, S_USED(%rbp)
    je      9f
    mov     C_MX_FLAGS(%rbx), %r12
    test    $YF_RST, %r12
    jz      1f
    mov     %rbp, %rdi                      /* the peer reset the stream */
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_stream_kill
    jmp     9f
1:  test    $YF_FIN, %r12
    jz      9f
    mov     %rbp, %rdi
    call    libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_mux_end_frame

/* libp2p_mux_find(conn, id, local) -> the stream of the connection with the muxer ID and side, or 0. */
LOCAL_FUNCTION libp2p_mux_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     C_STREAM_HEAD(%rbx), %r13
1:  cmp     $NONE, %r13
    je      8f
    mov     %r13, %rdi
    call    libp2p_stream_at
    cmp     S_ID(%rax), %rbp
    jne     2f
    mov     S_FLAGS(%rax), %rcx
    and     $SF_LOCAL, %rcx
    cmp     %r12, %rcx
    je      9f
2:  mov     S_NEXT(%rax), %r13
    jmp     1b
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_mux_find

/* libp2p_mux_rst(conn, id): a reset for a stream that has no slot, sent by the next drain. A leaf. */
LOCAL_FUNCTION libp2p_mux_rst
    UNWIND_END_PROLOGUE
    mov     C_RSTS(%rdi), %rdx
    cmp     $6, %rdx
    jae     9f
    movl    %esi, C_RST_IDS(%rdi,%rdx,4)
    inc     %rdx
    mov     %rdx, C_RSTS(%rdi)
9:  ret
END_FUNCTION libp2p_mux_rst

/* libp2p_mux_error(conn) -> 0: the peer broke the muxer protocol; the connection ends. */
LOCAL_FUNCTION libp2p_mux_error
    FRAME
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_close
    xor     %eax, %eax
    UNFRAME
END_FUNCTION libp2p_mux_error

/* ---------------------------------------------------------------- yamux input */

/*
 * libp2p_yamux_feed(conn, p, n) -> bytes taken: frame data, or header bytes; a
 * whole header is handled. rbx conn, rbp p, r12 n, r13 header bytes held,
 * X23 taken.
 */
LOCAL_FUNCTION libp2p_yamux_feed
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmpq    $0, C_MX_REMAIN(%rbx)
    je      1f
    call    libp2p_mux_data
    jmp     9f
1:  mov     C_MX_HLEN(%rbx), %r13
    mov     $12, %eax
    sub     %r13, %rax
    mov     %r12, %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    mov     %rcx, X23(%rsp)
    lea     C_MX_HDR(%rbx,%r13), %rdi
    mov     %rbp, %rsi
    mov     %rcx, %rdx
    call    libp2p_copy
    add     X23(%rsp), %r13
    mov     %r13, C_MX_HLEN(%rbx)
    cmp     $12, %r13
    jb      8f
    movq    $0, C_MX_HLEN(%rbx)
    mov     %rbx, %rdi
    call    libp2p_yamux_frame
8:  mov     X23(%rsp), %rax
9:  LEAVE   0
END_FUNCTION libp2p_yamux_feed

/*
 * libp2p_yamux_frame(conn): one 12-byte header: version 0, type, flags, stream
 * ID and length, big endian.
 * rbx conn, rbp type, r12 flags, r13 ID, X23 length, X24 stream.
 */
LOCAL_FUNCTION libp2p_yamux_frame
    ENTER   0
    mov     %rdi, %rbx
    lea     C_MX_HDR(%rbx), %rax
    cmpb    $0, (%rax)
    jne     80f
    movzbl  1(%rax), %ebp
    movzbl  2(%rax), %r12d
    shl     $8, %r12d
    movzbl  3(%rax), %ecx
    or      %ecx, %r12d
    movl    4(%rax), %r13d
    bswap   %r13d
    movl    8(%rax), %ecx
    bswap   %ecx
    mov     %rcx, X23(%rsp)
    cmp     $YT_PING, %rbp
    jne     1f
    test    $YF_SYN, %r12                   /* a ping: answer it */
    jz      99f
    mov     C_PING_COUNT(%rbx), %rdx
    cmp     $4, %rdx
    jae     99f
    movl    %ecx, C_PINGS(%rbx,%rdx,4)
    inc     %rdx
    mov     %rdx, C_PING_COUNT(%rbx)
    jmp     99f
1:  cmp     $YT_GOAWAY, %rbp
    jne     2f
    mov     %rbx, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_close
    jmp     99f
2:  cmp     $YT_WINDOW, %rbp
    ja      80f
    test    %r13, %r13
    jz      80f
    mov     %rbx, %rdi
    mov     %r13, %rsi
    mov     %r12, %rdx
    call    libp2p_yamux_stream
    cmp     $NONE, %rax
    je      80f
    mov     %rax, X24(%rsp)
    mov     %r12, C_MX_FLAGS(%rbx)
    movq    $NONE, C_MX_STREAM(%rbx)
    test    %rax, %rax
    jz      3f
    mov     %rax, %rdi
    call    libp2p_stream_index
    mov     %rax, C_MX_STREAM(%rbx)
3:  cmp     $YT_DATA, %rbp
    jne     4f
    mov     X24(%rsp), %rax                 /* data: within the window */
    test    %rax, %rax
    jz      31f
    mov     X23(%rsp), %rcx
    cmp     S_RECV_WIN(%rax), %rcx
    ja      80f
31: mov     X23(%rsp), %rcx
    mov     %rcx, C_MX_REMAIN(%rbx)
    test    %rcx, %rcx
    jnz     99f
    mov     %rbx, %rdi
    call    libp2p_mux_end_frame
    jmp     99f
4:  mov     X24(%rsp), %rax                 /* a window update */
    test    %rax, %rax
    jz      41f
    mov     X23(%rsp), %rcx
    add     %rcx, S_SEND_WIN(%rax)
41: mov     %rbx, %rdi
    call    libp2p_mux_end_frame
    jmp     99f
80: mov     %rbx, %rdi
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    test    $YF_SYN, %r12
    jnz     1f
    mov     $SF_LOCAL, %edx                 /* ours, then the peer's */
    call    libp2p_mux_find
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_mux_find
    jmp     9f
1:  mov     C_FLAGS(%rbx), %rax
    and     $CF_OUTBOUND, %rax              /* the peer's IDs: even when we dialled */
    mov     %rbp, %rcx
    and     $1, %rcx
    xor     $1, %rcx
    cmp     %rcx, %rax
    jne     8f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_mux_find
    test    %rax, %rax
    jnz     8f
    cmpq    $LIBP2P_YAMUX_BACKLOG, C_BACKLOG(%rbx)
    jae     7f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_stream_new
    test    %rax, %rax
    jz      7f
    orq     $SF_ACK, S_FLAGS(%rax)
    incq    C_BACKLOG(%rbx)
    jmp     9f
7:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_mux_rst
    xor     %eax, %eax
    jmp     9f
8:  mov     $NONE, %rax
9:  LEAVE   0
END_FUNCTION libp2p_yamux_stream

/* ---------------------------------------------------------------- mplex input */

/*
 * libp2p_mplex_feed(conn, p, n) -> bytes taken: message data, or header bytes
 * one at a time until both varints of the header are whole.
 * rbx conn, rbp p, r12 n, r13 header bytes held, X23 taken, X24 the first
 * varint.
 */
LOCAL_FUNCTION libp2p_mplex_feed
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmpq    $0, C_MX_REMAIN(%rbx)
    je      1f
    call    libp2p_mux_data
    jmp     9f
1:  mov     C_MX_HLEN(%rbx), %r13
    movq    $0, X23(%rsp)
2:  mov     X23(%rsp), %rax
    cmp     %r12, %rax
    jae     8f
    cmp     $20, %r13
    jae     80f
    movzbl  (%rbp,%rax), %ecx
    movb    %cl, C_MX_HDR(%rbx,%r13)
    inc     %r13
    inc     %rax
    mov     %rax, X23(%rsp)
    mov     %r13, C_MX_HLEN(%rbx)
    lea     C_MX_HDR(%rbx), %rdi
    lea     (%rdi,%r13), %rsi
    call    libp2p_varint_get
    cmp     $NONE, %rdx
    je      80f
    test    %rdx, %rdx
    jz      2b
    mov     %rax, X24(%rsp)
    lea     C_MX_HDR(%rbx,%rdx), %rdi
    lea     C_MX_HDR(%rbx,%r13), %rsi
    call    libp2p_varint_get
    cmp     $NONE, %rdx
    je      80f
    test    %rdx, %rdx
    jz      2b
    movq    $0, C_MX_HLEN(%rbx)
    mov     %rax, %rdx
    mov     %rbx, %rdi
    mov     X24(%rsp), %rsi
    call    libp2p_mplex_frame
    jmp     8f
80: mov     %rbx, %rdi
    call    libp2p_mux_error
8:  mov     X23(%rsp), %rax
9:  LEAVE   0
END_FUNCTION libp2p_mplex_feed

/*
 * libp2p_mplex_frame(conn, header, length): one mplex header: the stream ID and
 * flag in the first varint, the data length in the second.
 * rbx conn, rbp ID, r12 flag, r13 length.
 */
LOCAL_FUNCTION libp2p_mplex_frame
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    shr     $3, %rbp
    mov     %rsi, %r12
    and     $7, %r12
    mov     %rdx, %r13
    cmp     $LIBP2P_MPLEX_MAX, %r13
    ja      80f
    cmp     $MP_RESET_INITIATOR, %r12
    ja      80f
    mov     %rbp, %rax                      /* IDs below 2^28 */
    shr     $28, %rax
    jnz     80f
    mov     %r13, C_MX_REMAIN(%rbx)
    movq    $NONE, C_MX_STREAM(%rbx)
    movq    $0, C_MX_FLAGS(%rbx)
    test    %r12, %r12
    jnz     1f
    mov     %rbx, %rdi                      /* NewStream: the data is a name, dropped */
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_mux_find
    test    %rax, %rax
    jnz     80f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_stream_new
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi
    lea     MP_RESET_RECEIVER(,%rbp,8), %rsi
    call    libp2p_mux_rst
    jmp     9f
1:  xor     %edx, %edx                      /* odd flags: from the receiver, so the stream is ours */
    mov     $SF_LOCAL, %ecx
    test    $1, %r12
    cmovnz  %rcx, %rdx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_mux_find
    test    %rax, %rax
    jz      9f                              /* no such stream: drop the data */
    mov     %rax, %rdi
    call    libp2p_stream_index
    mov     %rax, C_MX_STREAM(%rbx)
    cmp     $MP_MSG_INITIATOR, %r12
    jbe     9f
    mov     $YF_FIN, %eax                   /* close, or reset */
    mov     $YF_RST, %ecx
    cmp     $MP_CLOSE_INITIATOR, %r12
    cmova   %rcx, %rax
    mov     %rax, C_MX_FLAGS(%rbx)
9:  cmpq    $0, C_MX_REMAIN(%rbx)
    jne     99f
    mov     %rbx, %rdi
    call    libp2p_mux_end_frame
    jmp     99f
80: mov     %rbx, %rdi
    call    libp2p_mux_error
99: LEAVE   0
END_FUNCTION libp2p_mplex_frame

/* ---------------------------------------------------------------- Frame output */

/* libp2p_yamux_header(dst, type, flags, id, length) -> dst + 12. A leaf. */
LOCAL_FUNCTION libp2p_yamux_header
    UNWIND_END_PROLOGUE
    movb    $0, (%rdi)
    movb    %sil, 1(%rdi)
    mov     %edx, %eax
    rolw    $8, %ax
    movw    %ax, 2(%rdi)
    bswap   %ecx
    movl    %ecx, 4(%rdi)
    bswap   %r8d
    movl    %r8d, 8(%rdi)
    lea     12(%rdi), %rax
    ret
END_FUNCTION libp2p_yamux_header

/* libp2p_mplex_header(dst, header, length) -> dst after the two varints. */
LOCAL_FUNCTION libp2p_mplex_header
    ENTER   0
    mov     %rdx, %rbx
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_mplex_header

/*
 * libp2p_chunk_take(stream, dst, max) -> the bytes copied to dst from the head
 * chunk of the queue, at most max; a chunk that is all sent is freed.
 * rbx stream, rbp dst, r12 the chunk, r13 its block, X23 taken.
 */
LOCAL_FUNCTION libp2p_chunk_take
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     S_Q_HEAD(%rbx), %r12
    lea     -HB_HEADER(%r15,%r12), %r13
    mov     CH_LEN(%r13), %rax
    mov     CH_DONE(%r13), %rcx
    sub     %rcx, %rax
    cmp     %rax, %rdx
    cmova   %rax, %rdx
    mov     %rdx, X23(%rsp)
    mov     %rbp, %rdi
    lea     CH_DATA(%r13,%rcx), %rsi
    call    libp2p_copy
    mov     X23(%rsp), %rax
    add     %rax, CH_DONE(%r13)
    sub     %rax, S_Q_BYTES(%rbx)
    mov     CH_DONE(%r13), %rcx
    cmp     CH_LEN(%r13), %rcx
    jb      9f
    mov     CH_NEXT(%r13), %rcx
    mov     %rcx, S_Q_HEAD(%rbx)
    cmp     $NONE, %rcx
    jne     1f
    mov     %rcx, S_Q_TAIL(%rbx)
1:  mov     %r12, %rdi
    call    libp2p_heap_free
9:  mov     X23(%rsp), %rax
    LEAVE   0
END_FUNCTION libp2p_chunk_take

/*
 * libp2p_yamux_emit(conn, stream, dst, room) -> dst after what it wrote: RST;
 * SYN; ACK; a window update once 64 KiB were taken; data frames within the
 * send window; FIN after the queue. A stream with RST, or closed both ways
 * and empty, becomes dead.
 * rbx conn, rbp stream, r12 position, r13 end, X23 flags, X24 ID, X25 taken.
 */
LOCAL_FUNCTION libp2p_yamux_emit
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     (%rdx,%rcx), %r13
    mov     S_FLAGS(%rbp), %rax
    mov     %rax, X23(%rsp)
    mov     S_ID(%rbp), %rax
    mov     %rax, X24(%rsp)
    testq   $SF_RST, X23(%rsp)
    jz      1f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $12, %rax
    jb      90f
    mov     %r12, %rdi
    mov     $YT_WINDOW, %esi
    mov     $YF_RST, %edx
    mov     X24(%rsp), %rcx
    xor     %r8d, %r8d
    call    libp2p_yamux_header
    mov     %rax, %r12
    orq     $SF_DEAD, X23(%rsp)
    jmp     90f
1:  testq   $(SF_SYN | SF_ACK), X23(%rsp)
    jz      2f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $12, %rax
    jb      90f
    mov     X23(%rsp), %rax
    mov     %rax, %rdx
    and     $SF_SYN, %rdx                   /* SF_SYN is 2: YF_ACK; SF_ACK is 4 */
    shr     $1, %rdx                        /* YF_SYN */
    mov     $YF_ACK, %ecx
    test    $SF_ACK, %rax
    cmovnz  %rcx, %rdx
    mov     %r12, %rdi
    mov     $YT_WINDOW, %esi
    mov     X24(%rsp), %rcx
    xor     %r8d, %r8d
    call    libp2p_yamux_header
    mov     %rax, %r12
    testq   $SF_ACK, X23(%rsp)
    jz      11f
    decq    C_BACKLOG(%rbx)
11: andq    $~(SF_SYN | SF_ACK), X23(%rsp)
2:  mov     S_RECV_PEND(%rbp), %r8
    cmp     $65536, %r8
    jb      3f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $12, %rax
    jb      90f
    mov     %r12, %rdi
    mov     $YT_WINDOW, %esi
    xor     %edx, %edx
    mov     X24(%rsp), %rcx
    call    libp2p_yamux_header
    mov     %rax, %r12
    mov     S_RECV_PEND(%rbp), %rax
    add     %rax, S_RECV_WIN(%rbp)
    movq    $0, S_RECV_PEND(%rbp)
3:  cmpq    $NONE, S_Q_HEAD(%rbp)           /* data */
    je      4f
    mov     S_SEND_WIN(%rbp), %rax
    test    %rax, %rax
    jz      90f
    mov     %r13, %rcx
    sub     %r12, %rcx
    cmp     $13, %rcx
    jb      90f
    sub     $12, %rcx
    mov     %rax, %rdx
    cmp     %rcx, %rdx
    cmova   %rcx, %rdx
    mov     %rbp, %rdi
    lea     12(%r12), %rsi
    call    libp2p_chunk_take
    mov     %rax, X25(%rsp)
    mov     %rax, %r8
    mov     %r12, %rdi
    mov     $YT_DATA, %esi
    xor     %edx, %edx
    mov     X24(%rsp), %rcx
    call    libp2p_yamux_header
    add     X25(%rsp), %rax
    mov     %rax, %r12
    mov     X25(%rsp), %rax
    sub     %rax, S_SEND_WIN(%rbp)
    jmp     3b
4:  mov     X23(%rsp), %rax                 /* FIN after the queue */
    test    $SF_FIN, %rax
    jz      5f
    test    $SF_FIN_SENT, %rax
    jnz     5f
    mov     %r13, %rcx
    sub     %r12, %rcx
    cmp     $12, %rcx
    jb      90f
    mov     %r12, %rdi
    mov     $YT_WINDOW, %esi
    mov     $YF_FIN, %edx
    mov     X24(%rsp), %rcx
    xor     %r8d, %r8d
    call    libp2p_yamux_header
    mov     %rax, %r12
    orq     $SF_FIN_SENT, X23(%rsp)
5:  mov     X23(%rsp), %rax
    and     $(SF_FIN_SENT | SF_REMOTE_FIN), %rax
    cmp     $(SF_FIN_SENT | SF_REMOTE_FIN), %rax
    jne     90f
    orq     $SF_DEAD, X23(%rsp)
90: mov     X23(%rsp), %rax
    mov     %rax, S_FLAGS(%rbp)
    mov     %r12, %rax
    LEAVE   0
END_FUNCTION libp2p_yamux_emit

/*
 * libp2p_mplex_emit(conn, stream, dst, room) -> dst after what it wrote: reset;
 * NewStream with the decimal ID as name; data messages; close after the
 * queue. The flags say which side opened the stream.
 * rbx conn, rbp stream, r12 position, r13 end, X23 flags, X24 ID << 3,
 * X25 nonzero when we opened it, X26 a count. Extra: the name at 32(%rsp).
 */
LOCAL_FUNCTION libp2p_mplex_emit
    ENTER   0, 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     (%rdx,%rcx), %r13
    mov     S_FLAGS(%rbp), %rax
    mov     %rax, X23(%rsp)
    mov     S_ID(%rbp), %rcx
    shl     $3, %rcx
    mov     %rcx, X24(%rsp)
    and     $SF_LOCAL, %rax
    mov     %rax, X25(%rsp)
    testq   $SF_RST, X23(%rsp)
    jz      1f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $16, %rax
    jb      90f
    mov     $MP_RESET_RECEIVER, %eax
    mov     $MP_RESET_INITIATOR, %ecx
    cmpq    $0, X25(%rsp)
    cmovne  %rcx, %rax
    mov     X24(%rsp), %rsi
    or      %rax, %rsi
    mov     %r12, %rdi
    xor     %edx, %edx
    call    libp2p_mplex_header
    mov     %rax, %r12
    orq     $SF_DEAD, X23(%rsp)
    jmp     90f
1:  testq   $SF_SYN, X23(%rsp)
    jz      3f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $48, %rax
    jb      90f
    mov     S_ID(%rbp), %rax                /* the name: the decimal ID, backwards on the stack */
    xor     %r8d, %r8d
    mov     $10, %ecx
2:  xor     %edx, %edx
    div     %rcx
    add     $'0', %edx
    movb    %dl, 32(%rsp,%r8)
    inc     %r8
    test    %rax, %rax
    jnz     2b
    mov     %r8, X26(%rsp)
    mov     %r12, %rdi
    mov     X24(%rsp), %rsi
    mov     %r8, %rdx
    call    libp2p_mplex_header
21: decq    X26(%rsp)
    mov     X26(%rsp), %rcx
    movzbl  32(%rsp,%rcx), %edx
    movb    %dl, (%rax)
    inc     %rax
    test    %rcx, %rcx
    jnz     21b
    mov     %rax, %r12
    andq    $~SF_SYN, X23(%rsp)
3:  cmpq    $NONE, S_Q_HEAD(%rbp)           /* data */
    je      4f
    mov     %r13, %rax
    sub     %r12, %rax
    cmp     $17, %rax
    jb      90f
    lea     -16(%rax), %rdx
    mov     %rbp, %rdi
    lea     16(%r12), %rsi                  /* data after room for the header, moved down below */
    call    libp2p_chunk_take
    mov     %rax, X26(%rsp)
    mov     $MP_MSG_RECEIVER, %eax
    mov     $MP_MSG_INITIATOR, %ecx
    cmpq    $0, X25(%rsp)
    cmovne  %rcx, %rax
    mov     X24(%rsp), %rsi
    or      %rax, %rsi
    mov     %r12, %rdi
    mov     X26(%rsp), %rdx
    call    libp2p_mplex_header
    mov     %rax, %rdi
    lea     16(%r12), %rsi
    mov     X26(%rsp), %rdx
    call    libp2p_copy
    mov     %rax, %r12
    jmp     3b
4:  mov     X23(%rsp), %rax
    test    $SF_FIN, %rax
    jz      5f
    test    $SF_FIN_SENT, %rax
    jnz     5f
    mov     %r13, %rcx
    sub     %r12, %rcx
    cmp     $16, %rcx
    jb      90f
    mov     $MP_CLOSE_RECEIVER, %eax
    mov     $MP_CLOSE_INITIATOR, %ecx
    cmpq    $0, X25(%rsp)
    cmovne  %rcx, %rax
    mov     X24(%rsp), %rsi
    or      %rax, %rsi
    mov     %r12, %rdi
    xor     %edx, %edx
    call    libp2p_mplex_header
    mov     %rax, %r12
    orq     $SF_FIN_SENT, X23(%rsp)
5:  mov     X23(%rsp), %rax
    and     $(SF_FIN_SENT | SF_REMOTE_FIN), %rax
    cmp     $(SF_FIN_SENT | SF_REMOTE_FIN), %rax
    jne     90f
    orq     $SF_DEAD, X23(%rsp)
90: mov     X23(%rsp), %rax
    mov     %rax, S_FLAGS(%rbp)
    mov     %r12, %rax
    LEAVE   0, 32
END_FUNCTION libp2p_mplex_emit

/*
 * libp2p_mux_gather(conn, dst, room) -> bytes written: connection frames
 * (pongs, resets of streams without a slot), then the frames of each
 * stream in turn from the cursor; dead streams are freed.
 * rbx conn, rbp position, r12 end, r13 stream index, X23 streams left,
 * X24 stream, X25 next index. Extra: 32(%rsp) the start.
 */
LOCAL_FUNCTION libp2p_mux_gather
    ENTER   0, 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    mov     %rsi, 32(%rsp)
    testq   $CF_YAMUX, C_FLAGS(%rbx)
    jz      3f
1:  mov     C_PING_COUNT(%rbx), %rax        /* yamux pongs */
    test    %rax, %rax
    jz      2f
    mov     %r12, %rcx
    sub     %rbp, %rcx
    cmp     $12, %rcx
    jb      9f
    dec     %rax
    mov     %rax, C_PING_COUNT(%rbx)
    movl    C_PINGS(%rbx,%rax,4), %r8d
    mov     %rbp, %rdi
    mov     $YT_PING, %esi
    mov     $YF_ACK, %edx
    xor     %ecx, %ecx
    call    libp2p_yamux_header
    mov     %rax, %rbp
    jmp     1b
2:  mov     C_RSTS(%rbx), %rax              /* yamux resets */
    test    %rax, %rax
    jz      5f
    mov     %r12, %rcx
    sub     %rbp, %rcx
    cmp     $12, %rcx
    jb      9f
    dec     %rax
    mov     %rax, C_RSTS(%rbx)
    movl    C_RST_IDS(%rbx,%rax,4), %ecx
    mov     %rbp, %rdi
    mov     $YT_WINDOW, %esi
    mov     $YF_RST, %edx
    xor     %r8d, %r8d
    call    libp2p_yamux_header
    mov     %rax, %rbp
    jmp     2b
3:  mov     C_RSTS(%rbx), %rax              /* mplex resets: the header is stored */
    test    %rax, %rax
    jz      5f
    mov     %r12, %rcx
    sub     %rbp, %rcx
    cmp     $16, %rcx
    jb      9f
    dec     %rax
    mov     %rax, C_RSTS(%rbx)
    movl    C_RST_IDS(%rbx,%rax,4), %esi
    mov     %rbp, %rdi
    xor     %edx, %edx
    call    libp2p_mplex_header
    mov     %rax, %rbp
    jmp     3b
5:  mov     C_CURSOR(%rbx), %r13            /* the streams, from the cursor */
    cmp     $NONE, %r13
    jne     51f
    mov     C_STREAM_HEAD(%rbx), %r13
51: mov     C_STREAMS(%rbx), %rax
    mov     %rax, X23(%rsp)
6:  cmpq    $0, X23(%rsp)
    je      8f
    cmp     $NONE, %r13
    jne     61f
    mov     C_STREAM_HEAD(%rbx), %r13
    cmp     $NONE, %r13
    je      8f
61: mov     %r13, %rdi
    call    libp2p_stream_at
    mov     %rax, X24(%rsp)
    mov     S_NEXT(%rax), %rcx
    mov     %rcx, X25(%rsp)
    testq   $SF_DEAD, S_FLAGS(%rax)
    jnz     63f
    mov     %rbx, %rdi
    mov     %rax, %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    sub     %rbp, %rcx
    testq   $CF_YAMUX, C_FLAGS(%rbx)
    jz      62f
    call    libp2p_yamux_emit
    jmp     621f
62: call    libp2p_mplex_emit
621: mov    %rax, %rbp
    mov     %r12, %rax                      /* out of room: resume here next time */
    sub     %rbp, %rax
    cmp     $32, %rax
    jae     63f
    mov     %r13, C_CURSOR(%rbx)
    jmp     64f
63: mov     X24(%rsp), %rdi
    testq   $SF_DEAD, S_FLAGS(%rdi)
    jz      64f
    call    libp2p_stream_free
64: mov     %r12, %rax
    sub     %rbp, %rax
    cmp     $32, %rax
    jb      9f
    mov     X25(%rsp), %r13
    decq    X23(%rsp)
    jmp     6b
8:  movq    $NONE, C_CURSOR(%rbx)
9:  mov     %rbp, %rax
    sub     32(%rsp), %rax
    LEAVE   0, 16
END_FUNCTION libp2p_mux_gather

/* ---------------------------------------------------------------- Drain */

/*
 * libp2p_drain(): for each connection, while the action list has room and the
 * connection has send window: pending CLOSE actions; bytes before the
 * transport keys as they are; then Noise transport messages of bytes
 * before the muxer and muxer frames, as many as fit in one SEND action.
 * Room that runs out asks for an immediate wakeup.
 * rbx connection, rbp connections left.
 */
LOCAL_FUNCTION libp2p_drain
    ENTER   0
    TABLE   %rbx, ST_CONN_OFF
    mov     ST_CONN_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      9f
    cmpl    $0, C_PHASE(%rbx)
    je      3f
    testq   $CF_NEED_CLOSE, C_FLAGS(%rbx)
    jz      2f
    call    libp2p_room
    cmp     $64, %rax
    jb      8f
    mov     %rbx, %rdi
    call    libp2p_conn_send_close
    jmp     3f
2:  mov     %rbx, %rdi
    call    libp2p_conn_live
    test    %rax, %rax
    jz      3f
21: mov     %rbx, %rdi
    call    libp2p_drain_conn
    cmp     $2, %rax
    je      8f                              /* the action list is full */
    cmp     $1, %rax
    je      21b                             /* it sent: try again */
3:  add     $C_SIZE, %rbx
    dec     %rbp
    jmp     1b
8:  mov     SC_NOW(%r14), %rdi
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_drain

/*
 * libp2p_drain_conn(conn) -> 1 when it wrote one SEND action, 0 when the
 * connection has nothing to send or no send window, 2 when the action list
 * has no room.
 * rbx conn, rbp action, r12 data start, r13 bytes written, X23 capacity,
 * X24 the plaintext of one message, X25 its capacity, X26 the plaintext
 * buffer.
 */
LOCAL_FUNCTION libp2p_drain_conn
    ENTER   0
    mov     %rdi, %rbx
    mov     (ST_CONFIG + LIBP2P_CFG_SEND_WINDOW)(%r15), %rax
    sub     C_INFLIGHT(%rbx), %rax          /* send window left */
    cmp     $4096, %rax
    jb      98f
    mov     $262144, %ecx                   /* at most 256 KiB in one action */
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     %rax, X23(%rsp)
    call    libp2p_room
    sub     $(LIBP2P_ACT_SEND_DATA + 64), %rax
    cmp     $4096, %rax
    jl      97f
    mov     X23(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    mov     %rcx, X23(%rsp)
    mov     C_OUT_RAW(%rbx), %rax           /* anything to send? */
    or      C_OUT_LEN(%rbx), %rax
    jnz     1f
    cmpl    $PH_OPEN, C_PHASE(%rbx)
    jne     98f
    mov     %rbx, %rdi
    call    libp2p_conn_pending
    test    %rax, %rax
    jz      98f
1:  mov     X23(%rsp), %rsi
    add     $(LIBP2P_ACT_SEND_DATA + 7), %rsi
    and     $-8, %rsi
    mov     $LIBP2P_ACTION_SEND, %edi
    call    libp2p_action
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      97f
    lea     LIBP2P_ACT_SEND_DATA(%rbp), %r12
    xor     %r13d, %r13d
    mov     C_OUT_RAW(%rbx), %rax           /* bytes that go out as they are */
    mov     %rax, X24(%rsp)
    test    %rax, %rax
    jz      2f
    mov     %r12, %rdi
    lea     C_OUT(%rbx), %rsi
    mov     %rax, %rdx
    call    libp2p_copy
    mov     X24(%rsp), %r13
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    libp2p_out_drop
    movq    $0, C_OUT_RAW(%rbx)
2:  testq   $CF_TRANSPORT, C_FLAGS(%rbx)
    jz      7f
3:  mov     X23(%rsp), %rax                 /* one Noise message */
    sub     %r13, %rax
    cmp     $(18 + 16), %rax
    jb      7f
    sub     $18, %rax
    mov     $LIBP2P_NOISE_PLAIN, %ecx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     %rax, X25(%rsp)
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rax
    mov     %rax, X26(%rsp)
    movq    $0, X24(%rsp)
    mov     C_OUT_LEN(%rbx), %rax           /* bytes before the muxer */
    test    %rax, %rax
    jz      4f
    mov     X25(%rsp), %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    mov     %rax, X24(%rsp)
    mov     X26(%rsp), %rdi
    lea     C_OUT(%rbx), %rsi
    mov     %rax, %rdx
    call    libp2p_copy
    mov     %rbx, %rdi
    mov     X24(%rsp), %rsi
    call    libp2p_out_drop
4:  cmpl    $PH_OPEN, C_PHASE(%rbx)
    jne     5f
    mov     %rbx, %rdi
    mov     X26(%rsp), %rsi
    add     X24(%rsp), %rsi
    mov     X25(%rsp), %rdx
    sub     X24(%rsp), %rdx
    call    libp2p_mux_gather
    add     %rax, X24(%rsp)
5:  mov     X24(%rsp), %rdx
    test    %rdx, %rdx
    jz      7f
    mov     %rbx, %rdi
    mov     X26(%rsp), %rsi
    lea     (%r12,%r13), %rcx
    call    libp2p_noise_seal
    add     X24(%rsp), %r13
    add     $18, %r13
    jmp     3b
7:  test    %r13, %r13
    jz      8f
    mov     %r13, LIBP2P_ACT_SEND_COUNT(%rbp)
    mov     %rbx, %rdi
    call    libp2p_conn_handle
    mov     %rax, LIBP2P_ACT_CONN(%rbp)
    lea     (LIBP2P_ACT_SEND_DATA + 7)(%r13), %rsi
    and     $-8, %rsi
    mov     %rbp, %rdi
    call    libp2p_action_shrink
    add     %r13, C_INFLIGHT(%rbx)
    mov     $1, %eax
    jmp     99f
8:  mov     %rbp, %rdi                      /* nothing after all: drop the action */
    xor     %esi, %esi
    call    libp2p_action_shrink
98: xor     %eax, %eax
    jmp     99f
97: mov     $2, %eax
99: LEAVE   0
END_FUNCTION libp2p_drain_conn

/* libp2p_out_drop(conn, n): drops the first n bytes of the output buffer. */
LOCAL_FUNCTION libp2p_out_drop
    FRAME
    mov     C_OUT_LEN(%rdi), %rdx
    sub     %rsi, %rdx
    mov     %rdx, C_OUT_LEN(%rdi)
    lea     C_OUT(%rdi), %rdi
    add     %rdi, %rsi
    call    libp2p_copy
    UNFRAME
END_FUNCTION libp2p_out_drop

/*
 * libp2p_conn_pending(conn) -> 1 when an open connection has frames to send:
 * pongs, resets, or a stream with flags to send, data within its window,
 * or a window update due. rbx conn, rbp stream index.
 */
LOCAL_FUNCTION libp2p_conn_pending
    ENTER   0
    mov     %rdi, %rbx
    mov     C_PING_COUNT(%rbx), %rax
    or      C_RSTS(%rbx), %rax
    jnz     7f
    mov     C_STREAM_HEAD(%rbx), %rbp
1:  cmp     $NONE, %rbp
    je      8f
    mov     %rbp, %rdi
    call    libp2p_stream_at
    mov     S_FLAGS(%rax), %rcx
    test    $(SF_SYN | SF_ACK | SF_RST | SF_DEAD), %rcx
    jnz     7f
    mov     %rcx, %rdx
    and     $(SF_FIN | SF_FIN_SENT), %rdx
    cmp     $SF_FIN, %rdx
    je      7f
    cmpq    $65536, S_RECV_PEND(%rax)
    jae     7f
    cmpq    $NONE, S_Q_HEAD(%rax)
    je      2f
    testq   $CF_YAMUX, C_FLAGS(%rbx)
    jz      7f
    cmpq    $0, S_SEND_WIN(%rax)
    jne     7f
2:  mov     S_NEXT(%rax), %rbp
    jmp     1b
7:  mov     $1, %eax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_conn_pending

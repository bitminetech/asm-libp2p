/*
 * Streams of the x86-64 core: stream slots and queues, multistream-select
 * on each stream, and the stream events of the application. Included by
 * libp2p.s.
 */

/* ---------------------------------------------------------------- Stream slots */

/* libp2p_stream_index(stream) -> its slot index. A leaf. */
LOCAL_FUNCTION libp2p_stream_index
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    sub     ST_STREAM_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $S_SIZE, %ecx
    div     %rcx
    ret
END_FUNCTION libp2p_stream_index

/* libp2p_stream_at(index) -> the stream slot of an index. A leaf. */
LOCAL_FUNCTION libp2p_stream_at
    UNWIND_END_PROLOGUE
    imul    $S_SIZE, %rdi, %rax
    add     ST_STREAM_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_stream_at

/* libp2p_stream_conn(stream) -> its connection slot. A leaf. */
LOCAL_FUNCTION libp2p_stream_conn
    UNWIND_END_PROLOGUE
    imul    $C_SIZE, S_CONN(%rdi), %rax
    add     ST_CONN_OFF(%r15), %rax
    add     %r15, %rax
    ret
END_FUNCTION libp2p_stream_conn

/* libp2p_stream_handle(stream) -> its handle. */
LOCAL_FUNCTION libp2p_stream_handle
    FRAME
    mov     %rdi, %rdx
    mov     $ST_STREAM_OFF, %edi
    mov     $S_SIZE, %esi
    call    libp2p_handle
    UNFRAME
END_FUNCTION libp2p_stream_handle

/*
 * libp2p_stream_new(conn, id, local) -> a new stream of the connection with the
 * muxer stream ID, negotiating, with full yamux windows; 0 when the
 * connection has LIBP2P_CONN_STREAMS streams or no slot is free.
 * rbx conn, rbp id, r12 local, r13 stream, X23 its index, X24 the old head.
 */
LOCAL_FUNCTION libp2p_stream_new
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    xor     %eax, %eax
    cmpq    $LIBP2P_CONN_STREAMS, C_STREAMS(%rbx)
    jae     9f
    mov     $ST_STREAM_OFF, %edi
    mov     $ST_STREAM_COUNT, %esi
    mov     $S_SIZE, %edx
    call    libp2p_alloc_slot
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     %rbx, %rax
    sub     ST_CONN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $C_SIZE, %ecx
    div     %rcx
    mov     %rax, S_CONN(%r13)
    mov     %rbp, S_ID(%r13)
    xor     %eax, %eax
    test    %r12, %r12
    jz      1f
    mov     $SF_LOCAL, %eax
1:  mov     %rax, S_FLAGS(%r13)
    mov     C_PEER(%rbx), %rax
    mov     %rax, S_PEER(%r13)
    movq    $LIBP2P_YAMUX_WINDOW, S_SEND_WIN(%r13)
    movq    $LIBP2P_YAMUX_WINDOW, S_RECV_WIN(%r13)
    movq    $NONE, S_Q_HEAD(%r13)
    movq    $NONE, S_Q_TAIL(%r13)
    movq    $NONE, S_PREV(%r13)
    mov     C_STREAM_HEAD(%rbx), %rax       /* link at the head of the connection's list */
    mov     %rax, S_NEXT(%r13)
    mov     %rax, X24(%rsp)
    mov     %r13, %rdi
    call    libp2p_stream_index
    mov     %rax, X23(%rsp)
    mov     X24(%rsp), %rdi
    cmp     $NONE, %rdi
    je      2f
    call    libp2p_stream_at
    mov     X23(%rsp), %rcx
    mov     %rcx, S_PREV(%rax)
2:  mov     X23(%rsp), %rax
    mov     %rax, C_STREAM_HEAD(%rbx)
    incq    C_STREAMS(%rbx)
    mov     %r13, %rax
9:  LEAVE   0
END_FUNCTION libp2p_stream_new

/*
 * libp2p_stream_free(stream): unlinks the stream from its connection and frees
 * its queue, its RPC buffer and its proposals. A gossipsub stream is taken
 * off its peer.
 * rbx stream, rbp conn, r12 index, r13 next, X23 prev.
 */
LOCAL_FUNCTION libp2p_stream_free
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_stream_conn
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_stream_index
    mov     %rax, %r12
    mov     S_NEXT(%rbx), %r13
    mov     S_PREV(%rbx), %rax
    mov     %rax, X23(%rsp)
    cmp     $NONE, %rax
    je      1f
    mov     %rax, %rdi
    call    libp2p_stream_at
    mov     %r13, S_NEXT(%rax)
    jmp     2f
1:  mov     %r13, C_STREAM_HEAD(%rbp)
2:  cmp     $NONE, %r13
    je      3f
    mov     %r13, %rdi
    call    libp2p_stream_at
    mov     X23(%rsp), %rcx
    mov     %rcx, S_PREV(%rax)
3:  decq    C_STREAMS(%rbp)
    cmp     C_CURSOR(%rbp), %r12
    jne     4f
    movq    $NONE, C_CURSOR(%rbp)
4:  cmp     C_MX_STREAM(%rbp), %r12
    jne     5f
    movq    $NONE, C_MX_STREAM(%rbp)
5:  mov     S_Q_HEAD(%rbx), %rdi            /* the queue */
    cmp     $NONE, %rdi
    je      6f
    mov     (CH_NEXT - HB_HEADER)(%r15,%rdi), %r13
    call    libp2p_heap_free
    mov     %r13, S_Q_HEAD(%rbx)
    jmp     5b
6:  mov     S_RPC_BUF(%rbx), %rdi
    call    libp2p_heap_free
    mov     S_PROPOSALS(%rbx), %rdi
    call    libp2p_heap_free
    mov     S_KIND(%rbx), %rax              /* a gossipsub stream leaves its peer */
    cmp     $SK_GOSSIP_IN, %rax
    jb      8f
    cmp     $SK_GOSSIP_OUT, %rax
    ja      8f
    mov     S_PEER(%rbx), %rax
    cmp     $NONE, %rax
    je      8f
    imul    $P_SIZE, %rax, %rcx
    add     ST_PEER_OFF(%r15), %rcx
    add     %r15, %rcx
    cmp     P_GS_OUT(%rcx), %r12
    jne     7f
    movq    $NONE, P_GS_OUT(%rcx)
    andq    $~(PF_GOSSIP | PF_HELLO | PF_IDONTWANT), P_FLAGS(%rcx)
7:  cmp     P_GS_IN(%rcx), %r12
    jne     8f
    movq    $NONE, P_GS_IN(%rcx)
8:  movl    $0, S_USED(%rbx)
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     S_FLAGS(%rbx), %rax
    mov     S_KIND(%rbx), %rcx
    cmp     $SK_APP, %rcx
    jne     1f
    test    $SF_REPORTED, %rax
    jz      8f
    mov     %rax, %rdx
    not     %rdx
    test    $(SF_FIN_SENT | SF_REMOTE_FIN), %rdx    /* closed both ways: nothing was lost */
    jz      8f
    mov     $LIBP2P_ACTION_STREAM_RESET, %edi
    mov     $LIBP2P_ACT_STREAM_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      8f
    mov     %rax, %r12
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%r12)
    jmp     8f
1:  cmp     $SK_NEGOTIATING, %rcx
    jne     8f
    cmpq    $SK_APP, S_TARGET(%rbx)
    jne     8f
    test    $SF_LOCAL, %rax
    jz      8f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_stream_failed
8:  mov     %rbx, %rdi
    call    libp2p_stream_free
    LEAVE   0
END_FUNCTION libp2p_stream_kill

/* libp2p_stream_failed(stream, reason): STREAM_FAILED with the tag of an outbound application stream. */
LOCAL_FUNCTION libp2p_stream_failed
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $LIBP2P_ACTION_STREAM_FAILED, %edi
    mov     $LIBP2P_ACT_FAILED_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     S_TAG(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TAG(%rax)
    mov     %rbp, LIBP2P_ACT_REASON(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_stream_failed

/*
 * libp2p_stream_queue(stream, src, n) -> 1 when the n bytes are queued on the
 * stream (one heap chunk), 0 when the heap has no block for them.
 * rbx stream, rbp src, r12 n, r13 the chunk (a state offset of its payload).
 */
LOCAL_FUNCTION libp2p_stream_queue
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     $1, %eax
    test    %r12, %r12
    jz      9f
    lea     (CH_DATA - HB_HEADER)(%r12), %rdi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    lea     -HB_HEADER(%r15,%r13), %rax     /* the block */
    movq    $NONE, CH_NEXT(%rax)
    mov     %r12, CH_LEN(%rax)
    movq    $0, CH_DONE(%rax)
    lea     CH_DATA(%rax), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    mov     S_Q_TAIL(%rbx), %rax
    cmp     $NONE, %rax
    jne     1f
    mov     %r13, S_Q_HEAD(%rbx)
    jmp     2f
1:  mov     %r13, (CH_NEXT - HB_HEADER)(%r15,%rax)
2:  mov     %r13, S_Q_TAIL(%rbx)
    add     %r12, S_Q_BYTES(%rbx)
    mov     $1, %eax
9:  LEAVE   0
END_FUNCTION libp2p_stream_queue

/* libp2p_stream_ms_out(stream, str, n) -> 1 when the multistream message is queued: varint(n), then the n bytes. */
LOCAL_FUNCTION libp2p_stream_ms_out
    ENTER   0, 160
    mov     %rdi, %rbx
    lea     32(%rsp), %rdi
    call    libp2p_ms_put
    lea     32(%rsp), %rsi
    mov     %rax, %rdx
    sub     %rsi, %rdx
    mov     %rbx, %rdi
    call    libp2p_stream_queue
    LEAVE   0, 160
END_FUNCTION libp2p_stream_ms_out

/* libp2p_stream_ms_proto(stream, bytes, n) -> 1 when the message of a protocol ID (n bytes, no newline) is queued. */
LOCAL_FUNCTION libp2p_stream_ms_proto
    ENTER   0, 160
    mov     %rdi, %rbx
    lea     32(%rsp), %rdi
    call    libp2p_ms_put_proto
    lea     32(%rsp), %rsi
    mov     %rax, %rdx
    sub     %rsi, %rdx
    mov     %rbx, %rdi
    call    libp2p_stream_queue
    LEAVE   0, 160
END_FUNCTION libp2p_stream_ms_proto

/*
 * libp2p_stream_open(conn, target, tag, proposals, count) -> a new outbound
 * stream that proposes the protocols: its ID is the next of this side, it
 * will send SYN or NewStream, and the multistream header and the first
 * proposal are queued. proposals is a heap block of ProtocolEntry values
 * the stream now owns, or 0 for gossipsub. 0 when it cannot be opened.
 * rbx conn, rbp target, r12 tag, r13 proposals, X23 count, X24 stream.
 */
LOCAL_FUNCTION libp2p_stream_open
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, X23(%rsp)
    mov     C_MX_NEXT_ID(%rbx), %rsi
    mov     $1, %eax
    mov     $2, %ecx
    testq   $CF_YAMUX, C_FLAGS(%rbx)
    cmovnz  %rcx, %rax
    add     %rsi, %rax
    mov     %rax, C_MX_NEXT_ID(%rbx)
    mov     %rbx, %rdi
    mov     $1, %edx
    call    libp2p_stream_new
    test    %rax, %rax
    jz      8f
    mov     %rax, X24(%rsp)
    orq     $SF_SYN, S_FLAGS(%rax)
    mov     %rbp, S_TARGET(%rax)
    mov     %r12, S_TAG(%rax)
    mov     %r13, S_PROPOSALS(%rax)
    mov     X23(%rsp), %rcx
    mov     %rcx, S_PROP_COUNT(%rax)
    mov     %rax, %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_stream_ms_out
    test    %rax, %rax
    jz      7f
    mov     X24(%rsp), %rdi
    call    libp2p_stream_propose
    test    %rax, %rax
    jz      7f
    mov     X24(%rsp), %rax
    jmp     9f
7:  mov     X24(%rsp), %rdi                 /* no heap: the stream goes */
    call    libp2p_stream_free
    xor     %eax, %eax
    jmp     9f
8:  mov     %r13, %rdi
    call    libp2p_heap_free
    xor     %eax, %eax
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
    mov     S_PROP_INDEX(%rdi), %rcx
    mov     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15), %rdx
    add     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15), %rdx /* the index of /meshsub/1.1.0 */
    lea     435b(%rip), %rax
    cmp     %rdx, %rcx
    jae     1f
    lea     437b(%rip), %rax
    test    %rcx, %rcx
    jnz     1f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15)
    je      1f
    lea     438b(%rip), %rax
1:  ret
END_FUNCTION libp2p_gs_proposal

/* libp2p_stream_propose(stream) -> 1 when the proposal at S_PROP_INDEX is queued. */
LOCAL_FUNCTION libp2p_stream_propose
    ENTER   0
    mov     %rdi, %rbx
    mov     S_PROPOSALS(%rbx), %rax
    test    %rax, %rax
    jnz     1f
    call    libp2p_gs_proposal              /* gossipsub */
    mov     %rax, %rsi
    mov     %rbx, %rdi
    mov     $15, %edx
    call    libp2p_stream_ms_out
    jmp     9f
1:  imul    $LIBP2P_PROTO_SIZE, S_PROP_INDEX(%rbx), %rcx
    add     %rcx, %rax
    add     %r15, %rax
    lea     LIBP2P_PROTO_BYTES(%rax), %rsi
    mov     LIBP2P_PROTO_LEN(%rax), %rdx
    mov     %rbx, %rdi
    call    libp2p_stream_ms_proto
9:  LEAVE   0
END_FUNCTION libp2p_stream_propose

/*
 * libp2p_stream_is_proposal(stream) -> 1 when the multistream message of the
 * stream is its current proposal. rbx stream, rbp the proposal, r12 its
 * length.
 */
LOCAL_FUNCTION libp2p_stream_is_proposal
    ENTER   0
    mov     %rdi, %rbx
    mov     S_PROPOSALS(%rbx), %rax
    test    %rax, %rax
    jnz     1f
    call    libp2p_gs_proposal
    mov     %rax, %rsi
    lea     S_MS_STATE(%rbx), %rdi
    mov     $15, %edx
    call    libp2p_ms_is
    jmp     9f
1:  imul    $LIBP2P_PROTO_SIZE, S_PROP_INDEX(%rbx), %rcx    /* the message is the bytes and a newline */
    add     %rcx, %rax
    lea     (%r15,%rax), %rbp
    mov     LIBP2P_PROTO_LEN(%rbp), %r12
    mov     S_MS_NEED(%rbx), %rax
    mov     S_MS_LEN(%rbx), %rcx
    sub     %rax, %rcx
    lea     S_MS_BUF(%rbx,%rax), %rdi       /* the message */
    lea     1(%r12), %rdx
    cmp     %rdx, %rcx
    jne     8f
    lea     LIBP2P_PROTO_BYTES(%rbp), %rsi
    mov     %r12, %rdx
    call    libp2p_equal
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_stream_is_proposal

/*
 * libp2p_stream_find_proto(stream) -> the index of the application protocol the
 * message names, or NONE. rbx the message, rbp its length, r12 protocol,
 * r13 count, X23 index.
 */
LOCAL_FUNCTION libp2p_stream_find_proto
    ENTER   0
    mov     S_MS_NEED(%rdi), %rax
    mov     S_MS_LEN(%rdi), %rbp
    sub     %rax, %rbp
    dec     %rbp                            /* without the newline */
    lea     S_MS_BUF(%rdi,%rax), %rbx
    TABLE   %r12, ST_PROTO_OFF
    mov     ST_PROTO_COUNT(%r15), %r13
    movq    $0, X23(%rsp)
1:  mov     X23(%rsp), %rax
    cmp     %r13, %rax
    jae     8f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     LIBP2P_PROTO_BYTES(%r12), %rdx
    mov     LIBP2P_PROTO_LEN(%r12), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jnz     2f
    add     $LIBP2P_PROTO_SIZE, %r12
    incq    X23(%rsp)
    jmp     1b
2:  mov     X23(%rsp), %rax
    jmp     9f
8:  mov     $NONE, %rax
9:  LEAVE   0
END_FUNCTION libp2p_stream_find_proto

/* ---------------------------------------------------------------- Stream input */

/*
 * libp2p_stream_data(stream, p, n): bytes of the stream from the muxer:
 * multistream messages while it negotiates, then the bytes of its kind:
 * STREAM_DATA for the application, RPCs for gossipsub.
 * rbx stream, rbp p, r12 n, r13 the action.
 */
LOCAL_FUNCTION libp2p_stream_data
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
1:  test    %r12, %r12
    jz      9f
    cmpl    $0, S_USED(%rbx)
    je      9f
    testq   $(SF_RST | SF_DEAD), S_FLAGS(%rbx)
    jnz     9f
    mov     S_KIND(%rbx), %rax
    cmp     $SK_NEGOTIATING, %rax
    jne     2f
    lea     S_MS_STATE(%rbx), %rdi
    mov     $S_MS_CAP, %esi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    call    libp2p_ms_take
    add     %rax, %rbp
    sub     %rax, %r12
    cmp     $2, %rdx
    je      8f
    test    %rdx, %rdx
    jz      9f
    mov     %rbx, %rdi
    call    libp2p_stream_ms
    jmp     1b
2:  cmp     $SK_APP, %rax
    jne     3f
    lea     (LIBP2P_ACT_SD_DATA + 7)(%r12), %rsi
    and     $-8, %rsi
    mov     $LIBP2P_ACTION_STREAM_DATA, %edi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%r13)
    mov     %r12, LIBP2P_ACT_SD_COUNT(%r13)
    lea     LIBP2P_ACT_SD_DATA(%r13), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    jmp     9f
3:  cmp     $SK_GOSSIP_IN, %rax
    jne     9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_gossip_rx
    jmp     9f
8:  mov     %rbx, %rdi                      /* not multistream: reset the stream */
    mov     $LIBP2P_REASON_PROTOCOL, %esi
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
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     S_FLAGS(%rbx), %rax
    mov     S_KIND(%rbx), %rcx
    cmp     $SK_APP, %rcx
    jne     1f
    test    $SF_REPORTED, %rax
    jz      3f
    mov     $LIBP2P_ACTION_STREAM_RESET, %edi
    mov     $LIBP2P_ACT_STREAM_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      3f
    mov     %rax, %r12
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%r12)
    jmp     3f
1:  cmp     $SK_NEGOTIATING, %rcx
    jne     3f
    cmpq    $SK_APP, S_TARGET(%rbx)
    jne     3f
    test    $SF_LOCAL, %rax
    jz      3f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_stream_failed
3:  mov     %rbx, %rdi
    call    libp2p_stream_reset
    LEAVE   0
END_FUNCTION libp2p_stream_abort

/* libp2p_stream_reset(stream): RST goes out with the next drain, then the slot is free; the queue is dropped. */
LOCAL_FUNCTION libp2p_stream_reset
    ENTER   0
    mov     %rdi, %rbx
1:  mov     S_Q_HEAD(%rbx), %rdi
    cmp     $NONE, %rdi
    je      2f
    mov     (CH_NEXT - HB_HEADER)(%r15,%rdi), %rbp
    call    libp2p_heap_free
    mov     %rbp, S_Q_HEAD(%rbx)
    jmp     1b
2:  movq    $NONE, S_Q_TAIL(%rbx)
    movq    $0, S_Q_BYTES(%rbx)
    mov     S_FLAGS(%rbx), %rax
    or      $SF_RST, %rax
    and     $~SF_REPORTED, %rax
    mov     %rax, S_FLAGS(%rbx)
    LEAVE   0
END_FUNCTION libp2p_stream_reset

/*
 * libp2p_stream_ms(stream): one multistream message of a stream. The header
 * comes first (a remote stream answers it with ours). Our stream then reads
 * the answer to its proposal: the same protocol selects it, na moves to the
 * next proposal or fails. A remote stream answers proposals: gossipsub or
 * an application protocol is selected, anything else gets na.
 * rbx stream, rbp flags, r12 the protocol index or the gossipsub message,
 * r13 the action.
 */
LOCAL_FUNCTION libp2p_stream_ms
    ENTER   0
    mov     %rdi, %rbx
    mov     S_FLAGS(%rbx), %rbp
    test    $SF_GOT_HEADER, %rbp
    jnz     2f
    lea     S_MS_STATE(%rbx), %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      80f
    or      $SF_GOT_HEADER, %rbp
    mov     %rbp, S_FLAGS(%rbx)
    test    $SF_LOCAL, %rbp
    jnz     70f
    mov     %rbx, %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_stream_ms_out
    jmp     70f
2:  test    $SF_LOCAL, %rbp
    jz      40f
    mov     %rbx, %rdi                      /* our stream: the answer */
    call    libp2p_stream_is_proposal
    test    %rax, %rax
    jz      30f
    movq    $0, S_MS_LEN(%rbx)
    mov     S_TARGET(%rbx), %rax
    mov     %rax, S_KIND(%rbx)
    mov     S_PROP_INDEX(%rbx), %rcx
    mov     %rcx, S_PROTO(%rbx)
    cmp     $SK_APP, %rax
    jne     20f
    or      $SF_REPORTED, %rbp
    mov     %rbp, S_FLAGS(%rbx)
    mov     $LIBP2P_ACTION_STREAM_OPENED, %edi
    mov     $LIBP2P_ACT_SO_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      99f
    mov     %rax, %r13
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%r13)
    mov     S_TAG(%rbx), %rax
    mov     %rax, LIBP2P_ACT_SO_TAG(%r13)
    mov     S_PROTO(%rbx), %rax
    mov     %rax, LIBP2P_ACT_SO_INDEX(%r13)
    jmp     99f
20: mov     %rbx, %rdi                      /* our gossipsub stream */
    call    libp2p_gossip_out_ready
    jmp     99f
30: lea     S_MS_STATE(%rbx), %rdi          /* na: the next proposal */
    lea     431b(%rip), %rsi
    mov     $3, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      80f
    mov     S_PROP_INDEX(%rbx), %rax
    inc     %rax
    cmp     S_PROP_COUNT(%rbx), %rax
    jae     31f
    mov     %rax, S_PROP_INDEX(%rbx)
    mov     %rbx, %rdi
    call    libp2p_stream_propose
    jmp     70f
31: movq    $0, S_MS_LEN(%rbx)
    mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PROTOCOL, %esi
    call    libp2p_stream_abort
    jmp     99f
40: lea     S_MS_STATE(%rbx), %rdi          /* a remote stream: a proposal */
    lea     435b(%rip), %rsi
    mov     $15, %edx
    call    libp2p_ms_is
    lea     435b(%rip), %r12
    test    %rax, %rax
    jnz     41f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15)
    je      50f
    lea     S_MS_STATE(%rbx), %rdi
    lea     437b(%rip), %rsi
    mov     $15, %edx
    call    libp2p_ms_is
    lea     437b(%rip), %r12
    test    %rax, %rax
    jnz     41f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15)
    je      50f
    lea     S_MS_STATE(%rbx), %rdi
    lea     438b(%rip), %rsi
    mov     $15, %edx
    call    libp2p_ms_is
    lea     438b(%rip), %r12
    test    %rax, %rax
    jz      50f
41: mov     %rbx, %rdi                      /* gossipsub: echo the version */
    mov     %r12, %rsi
    mov     $15, %edx
    call    libp2p_stream_ms_out
    movq    $0, S_MS_LEN(%rbx)
    movq    $SK_GOSSIP_IN, S_KIND(%rbx)
    mov     %rbx, %rdi
    call    libp2p_gossip_in_ready
    jmp     99f
50: lea     S_MS_STATE(%rbx), %rdi          /* identify */
    lea     436b(%rip), %rsi
    mov     $15, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      51f
    mov     %rbx, %rdi
    lea     436b(%rip), %rsi
    mov     $15, %edx
    call    libp2p_stream_ms_out
    movq    $0, S_MS_LEN(%rbx)
    movq    $SK_IDENTIFY, S_KIND(%rbx)
    mov     %rbx, %rdi
    call    libp2p_identify
    jmp     99f
51: mov     %rbx, %rdi
    call    libp2p_stream_find_proto
    cmp     $NONE, %rax
    je      60f
    mov     %rax, %r12
    mov     S_MS_NEED(%rbx), %rax           /* echo the message */
    lea     S_MS_BUF(%rbx,%rax), %rsi
    mov     S_MS_LEN(%rbx), %rdx
    sub     %rax, %rdx
    mov     %rbx, %rdi
    call    libp2p_stream_ms_out
    movq    $0, S_MS_LEN(%rbx)
    movq    $SK_APP, S_KIND(%rbx)
    mov     %r12, S_PROTO(%rbx)
    or      $SF_REPORTED, %rbp
    mov     %rbp, S_FLAGS(%rbx)
    mov     $LIBP2P_ACTION_STREAM_INBOUND, %edi
    mov     $LIBP2P_ACT_SI_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      99f
    mov     %rax, %r13
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%r13)
    imul    $P_SIZE, S_PEER(%rbx), %rdx
    add     ST_PEER_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    call    libp2p_handle
    mov     %rax, LIBP2P_ACT_SI_PEER(%r13)
    mov     %r12, LIBP2P_ACT_SI_PROTOCOL(%r13)
    jmp     99f
60: mov     %rbx, %rdi                      /* na */
    lea     431b(%rip), %rsi
    mov     $3, %edx
    call    libp2p_stream_ms_out
70: movq    $0, S_MS_LEN(%rbx)
    jmp     99f
80: movq    $0, S_MS_LEN(%rbx)
    mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PROTOCOL, %esi
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
    mov     %rdi, %rbx
    mov     S_FLAGS(%rbx), %rax
    test    $SF_REMOTE_FIN, %rax
    jnz     9f
    or      $SF_REMOTE_FIN, %rax
    test    $SF_FIN_SENT, %rax              /* closed both ways: the drain frees it */
    jz      3f
    or      $SF_DEAD, %rax
3:  mov     %rax, S_FLAGS(%rbx)
    mov     S_KIND(%rbx), %rcx
    cmp     $SK_APP, %rcx
    jne     1f
    test    $SF_REPORTED, %rax
    jz      9f
    mov     $LIBP2P_ACTION_STREAM_EOF, %edi
    mov     $LIBP2P_ACT_STREAM_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_stream_handle
    mov     %rax, LIBP2P_ACT_STREAM(%rbp)
    jmp     9f
1:  cmp     $SK_GOSSIP_IN, %rcx             /* the peer closed its gossipsub stream: close ours of it too */
    je      2f
    cmp     $SK_NEGOTIATING, %rcx
    jne     9f
2:  or      $SF_FIN, %rax
    mov     %rax, S_FLAGS(%rbx)
9:  LEAVE   0
END_FUNCTION libp2p_stream_remote_fin

/* ---------------------------------------------------------------- Application stream events */

/*
 * libp2p_on_open_stream(event): an outbound application stream to a connected
 * peer, proposing the protocols in order; STREAM_FAILED when the peer is
 * not connected or no slot or heap block is free.
 * rbx event, rbp conn, r12 reason, r13 count, X23 the proposals.
 */
LOCAL_FUNCTION libp2p_on_open_stream
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_PEER(%rbx), %rdi
    call    libp2p_peer
    mov     $LIBP2P_REASON_NO_PEER, %r12d
    test    %rax, %rax
    jz      8f
    imul    $C_SIZE, P_CONN(%rax), %rbp
    add     ST_CONN_OFF(%r15), %rbp
    add     %r15, %rbp
    cmpl    $PH_OPEN, C_PHASE(%rbp)
    jne     8f
    mov     $LIBP2P_REASON_LIMIT, %r12d
    mov     LIBP2P_EV_OPEN_COUNT(%rbx), %r13
    imul    $LIBP2P_PROTO_SIZE, %r13, %rdi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jz      8f
    mov     %rax, X23(%rsp)
    lea     (%r15,%rax), %rdi
    lea     LIBP2P_EV_OPEN_PROTOCOLS(%rbx), %rsi
    imul    $LIBP2P_PROTO_SIZE, %r13, %rdx
    call    libp2p_copy
    mov     %rbp, %rdi
    mov     $SK_APP, %esi
    mov     LIBP2P_EV_OPEN_TAG(%rbx), %rdx
    mov     X23(%rsp), %rcx
    mov     %r13, %r8
    call    libp2p_stream_open
    test    %rax, %rax
    jnz     9f
8:  mov     $LIBP2P_ACTION_STREAM_FAILED, %edi
    mov     $LIBP2P_ACT_FAILED_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     LIBP2P_EV_OPEN_TAG(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TAG(%rax)
    mov     %r12, LIBP2P_ACT_REASON(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_on_open_stream

/* libp2p_app_stream(handle) -> the application stream of a handle that may still send, or 0. */
LOCAL_FUNCTION libp2p_app_stream
    FRAME
    call    libp2p_stream
    test    %rax, %rax
    jz      9f
    cmpq    $SK_APP, S_KIND(%rax)
    jne     8f
    testq   $SF_REPORTED, S_FLAGS(%rax)
    jnz     9f
8:  xor     %eax, %eax
9:  UNFRAME
END_FUNCTION libp2p_app_stream

/*
 * libp2p_on_stream_write(event): bytes for an application stream, queued; a
 * stream whose queue would pass the limit, or that the heap cannot hold,
 * is reset (STREAM_RESET). rbx event, rbp stream, r12 count.
 */
LOCAL_FUNCTION libp2p_on_stream_write
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_STREAM(%rbx), %rdi
    call    libp2p_app_stream
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    testq   $(SF_FIN | SF_RST), S_FLAGS(%rbp)
    jnz     9f
    mov     LIBP2P_EV_STREAM_COUNT(%rbx), %r12
    mov     S_Q_BYTES(%rbp), %rax
    add     %r12, %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_STREAM_QUEUE)(%r15), %rax
    ja      8f
    mov     %rbp, %rdi
    lea     LIBP2P_EV_STREAM_DATA(%rbx), %rsi
    mov     %r12, %rdx
    call    libp2p_stream_queue
    test    %rax, %rax
    jnz     9f
8:  mov     %rbp, %rdi
    mov     $LIBP2P_REASON_LIMIT, %esi
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_on_stream_write

/* libp2p_on_stream_close(event): the application closes its side of a stream: FIN after the queue. */
LOCAL_FUNCTION libp2p_on_stream_close
    FRAME
    mov     LIBP2P_EV_STREAM(%rdi), %rdi
    call    libp2p_app_stream
    test    %rax, %rax
    jz      9f
    orq     $SF_FIN, S_FLAGS(%rax)
9:  UNFRAME
END_FUNCTION libp2p_on_stream_close

/* libp2p_on_stream_reset(event): the application resets a stream: RST goes out, nothing comes back. */
LOCAL_FUNCTION libp2p_on_stream_reset
    FRAME
    mov     LIBP2P_EV_STREAM(%rdi), %rdi
    call    libp2p_app_stream
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_stream_reset
9:  UNFRAME
END_FUNCTION libp2p_on_stream_reset

/* ---------------------------------------------------------------- identify (/ipfs/id/1.0.0) */

/* libp2p_stream_append(stream, chunk): a send chunk (a state offset, its length set) goes on the queue of the stream. A leaf. */
LOCAL_FUNCTION libp2p_stream_append
    UNWIND_END_PROLOGUE
    lea     -HB_HEADER(%r15,%rsi), %rdx
    mov     S_Q_TAIL(%rdi), %rcx
    cmp     $NONE, %rcx
    jne     1f
    mov     %rsi, S_Q_HEAD(%rdi)
    jmp     2f
1:  mov     %rsi, (CH_NEXT - HB_HEADER)(%r15,%rcx)
2:  mov     %rsi, S_Q_TAIL(%rdi)
    mov     CH_LEN(%rdx), %rax
    add     %rax, S_Q_BYTES(%rdi)
    ret
END_FUNCTION libp2p_stream_append

/*
 * libp2p_observed(dst, addr) -> the length of the binary multiaddr of the
 * address: /ip4 (code 4, 4 bytes) or /ip6 (code 41, 16 bytes), then /tcp
 * (code 6, the port big endian). A leaf.
 */
LOCAL_FUNCTION libp2p_observed
    UNWIND_END_PROLOGUE
    mov     %rdi, %rdx
    cmpq    $6, LIBP2P_ADDR_FAMILY(%rsi)
    je      1f
    movb    $4, (%rdx)
    movl    LIBP2P_ADDR_IP(%rsi), %eax
    movl    %eax, 1(%rdx)
    add     $5, %rdx
    jmp     2f
1:  movb    $41, (%rdx)
    mov     LIBP2P_ADDR_IP(%rsi), %rax
    mov     %rax, 1(%rdx)
    mov     (LIBP2P_ADDR_IP + 8)(%rsi), %rax
    mov     %rax, 9(%rdx)
    add     $17, %rdx
2:  movb    $6, (%rdx)
    mov     LIBP2P_ADDR_PORT(%rsi), %rax
    mov     %eax, %ecx
    shr     $8, %ecx
    movb    %cl, 1(%rdx)
    movb    %al, 2(%rdx)
    add     $3, %rdx
    mov     %rdx, %rax
    sub     %rdi, %rax
    ret
END_FUNCTION libp2p_observed

/*
 * libp2p_identify(stream): the Identify message on a stream the peer opened
 * with /ipfs/id/1.0.0, varint-length prefixed, then FIN: publicKey (1),
 * observedAddr (4), protocols (3): identify, gossipsub (/meshsub/1.3.0 and
 * /meshsub/1.2.0 too when they are on) and the application protocols, then
 * protocolVersion (5) and agentVersion (6) when the config has them.
 * rbx stream, rbp size, r12 key length, r13 observed length, X23 position,
 * X24 chunk, X25 protocol, X26 protocols left. Key at 32(%rsp), observed
 * at 80(%rsp).
 */
LOCAL_FUNCTION libp2p_identify
    ENTER   0, 80
    mov     %rdi, %rbx
    lea     32(%rsp), %rdi
    mov     ST_KEY_TYPE(%r15), %rsi
    lea     ST_PUBLIC_KEY(%r15), %rdx
    mov     ST_PUBLIC_LEN(%r15), %rcx
    call    libp2p_key_proto
    lea     32(%rsp), %rcx
    sub     %rcx, %rax
    mov     %rax, %r12
    mov     %rbx, %rdi
    call    libp2p_stream_conn
    lea     C_ADDR(%rax), %rsi
    lea     80(%rsp), %rdi
    call    libp2p_observed
    mov     %rax, %r13
    mov     $1, %edi                        /* the size */
    mov     %r12, %rsi
    call    libp2p_pb_size
    mov     %rax, %rbp
    mov     $4, %edi
    mov     %r13, %rsi
    call    libp2p_pb_size
    add     %rax, %rbp
    mov     $3, %edi
    mov     $14, %esi
    call    libp2p_pb_size
    lea     (%rbp,%rax,2), %rbp             /* identify and gossipsub: 14 bytes each */
    mov     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15), %rcx    /* and /meshsub/1.2.0 */
    add     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15), %rcx    /* and /meshsub/1.3.0 */
    imul    %rcx, %rax
    add     %rax, %rbp
    TABLE   %rax, ST_PROTO_OFF
    mov     %rax, X25(%rsp)
    mov     ST_PROTO_COUNT(%r15), %rax
    mov     %rax, X26(%rsp)
1:  cmpq    $0, X26(%rsp)
    je      2f
    mov     $3, %edi
    mov     X25(%rsp), %rax
    mov     LIBP2P_PROTO_LEN(%rax), %rsi
    call    libp2p_pb_size
    add     %rax, %rbp
    addq    $LIBP2P_PROTO_SIZE, X25(%rsp)
    decq    X26(%rsp)
    jmp     1b
2:  mov     (ST_CONFIG + LIBP2P_CFG_PV_LEN)(%r15), %rsi
    test    %rsi, %rsi
    jz      3f
    mov     $5, %edi
    call    libp2p_pb_size
    add     %rax, %rbp
3:  mov     (ST_CONFIG + LIBP2P_CFG_AGENT_LEN)(%r15), %rsi
    test    %rsi, %rsi
    jz      4f
    mov     $6, %edi
    call    libp2p_pb_size
    add     %rax, %rbp
4:  mov     %rbp, %rdi
    call    libp2p_varint_len
    lea     (%rax,%rbp), %rdi
    call    libp2p_gs_alloc
    test    %rax, %rax
    jz      9f
    mov     %rdx, X24(%rsp)
    mov     %rax, %rdi
    mov     %rbp, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     $1, %esi
    lea     32(%rsp), %rdx
    mov     %r12, %rcx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    mov     $4, %esi
    lea     80(%rsp), %rdx
    mov     %r13, %rcx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    mov     $3, %esi
    lea     436b(%rip), %rdx
    mov     $14, %ecx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15)
    je      40f
    mov     $3, %esi
    lea     438b(%rip), %rdx
    mov     $14, %ecx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
40: cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15)
    je      41f
    mov     $3, %esi
    lea     437b(%rip), %rdx
    mov     $14, %ecx
    call    libp2p_pb_bytes
    mov     %rax, %rdi
41: mov     $3, %esi
    lea     435b(%rip), %rdx
    mov     $14, %ecx
    call    libp2p_pb_bytes
    mov     %rax, X23(%rsp)
    TABLE   %rax, ST_PROTO_OFF
    mov     %rax, X25(%rsp)
    mov     ST_PROTO_COUNT(%r15), %rax
    mov     %rax, X26(%rsp)
5:  cmpq    $0, X26(%rsp)
    je      6f
    mov     X23(%rsp), %rdi
    mov     $3, %esi
    mov     X25(%rsp), %rax
    lea     LIBP2P_PROTO_BYTES(%rax), %rdx
    mov     LIBP2P_PROTO_LEN(%rax), %rcx
    call    libp2p_pb_bytes
    mov     %rax, X23(%rsp)
    addq    $LIBP2P_PROTO_SIZE, X25(%rsp)
    decq    X26(%rsp)
    jmp     5b
6:  mov     (ST_CONFIG + LIBP2P_CFG_PV_LEN)(%r15), %rcx
    test    %rcx, %rcx
    jz      7f
    mov     X23(%rsp), %rdi
    mov     $5, %esi
    lea     (ST_CONFIG + LIBP2P_CFG_PV)(%r15), %rdx
    call    libp2p_pb_bytes
    mov     %rax, X23(%rsp)
7:  mov     (ST_CONFIG + LIBP2P_CFG_AGENT_LEN)(%r15), %rcx
    test    %rcx, %rcx
    jz      8f
    mov     X23(%rsp), %rdi
    mov     $6, %esi
    lea     (ST_CONFIG + LIBP2P_CFG_AGENT)(%r15), %rdx
    call    libp2p_pb_bytes
8:  mov     %rbx, %rdi
    mov     X24(%rsp), %rsi
    call    libp2p_stream_append
9:  orq     $SF_FIN, S_FLAGS(%rbx)          /* then FIN */
    LEAVE   0, 80
END_FUNCTION libp2p_identify

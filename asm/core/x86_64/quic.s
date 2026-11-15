/*
 * QUIC of the x86-64 core: the glue between libp2p and asm-quic. asm-quic does
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
 * rbx config, rbp dst.
 */
LOCAL_FUNCTION libp2p_quic_config
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rbp, %rdi
    mov     $QUIC_CFG_SIZE, %esi
    call    libp2p_zero
    movq    $QUIC_CFG_SIZE, QUIC_CFG_SIZE_FIELD(%rbp)
    movq    $QUIC_VERSION, QUIC_CFG_VERSION(%rbp)
    mov     LIBP2P_CFG_KEY_TYPE(%rbx), %rax
    mov     %rax, QUIC_CFG_KEY_TYPE(%rbp)
    lea     QUIC_CFG_KEY(%rbp), %rdi
    lea     LIBP2P_CFG_PRIVATE_KEY(%rbx), %rsi
    mov     $32, %edx
    call    libp2p_copy
    mov     LIBP2P_CFG_MAX_CONNECTIONS(%rbx), %rax
    mov     %rax, QUIC_CFG_CONNS(%rbp)
    mov     LIBP2P_CFG_MAX_STREAMS(%rbx), %rax
    mov     %rax, QUIC_CFG_STREAMS(%rbp)
    mov     LIBP2P_CFG_QUIC_HEAP(%rbx), %rax
    mov     %rax, QUIC_CFG_HEAP(%rbp)
    mov     LIBP2P_CFG_QUIC_IDLE_MS(%rbx), %rax
    mov     %rax, QUIC_CFG_IDLE(%rbp)
    mov     LIBP2P_CFG_HANDSHAKE_MS(%rbx), %rax
    mov     %rax, QUIC_CFG_HANDSHAKE(%rbp)
    mov     LIBP2P_CFG_QUIC_KEEP_ALIVE_MS(%rbx), %rax
    mov     %rax, QUIC_CFG_KEEP_ALIVE(%rbp)
    mov     LIBP2P_CFG_QUIC_MAX_DATA(%rbx), %rax
    mov     %rax, QUIC_CFG_MAX_DATA(%rbp)
    mov     LIBP2P_CFG_QUIC_STREAM_DATA(%rbx), %rax
    mov     %rax, QUIC_CFG_STREAM_DATA(%rbp)
    mov     LIBP2P_CFG_QUIC_MAX_STREAMS(%rbx), %rax
    mov     %rax, QUIC_CFG_MAX_STREAMS(%rbp)
    mov     LIBP2P_CFG_QUIC_WINDOW(%rbx), %rax  /* asm-quic keeps a chunk until all of it is acknowledged */
    add     $LIBP2P_QUIC_WRITE, %rax
    mov     %rax, QUIC_CFG_STREAM_QUEUE(%rbp)
    mov     LIBP2P_CFG_QUIC(%rbx), %rax
    shr     $1, %rax                        /* LIBP2P_QUIC_ACCEPT: QUIC_CFG_ACCEPT */
    and     $1, %eax
    mov     %rax, QUIC_CFG_FLAGS(%rbp)
    mov     LIBP2P_CFG_QUIC_SENT(%rbx), %rax
    mov     %rax, QUIC_CFG_SENT(%rbp)
    LEAVE   0
END_FUNCTION libp2p_quic_config

/*
 * libp2p_peer_id_proto(dst, proto, n) -> the length of the peer ID of a
 * PublicKey protobuf of n bytes (at most 128): the identity multihash when n
 * is at most 42, else the SHA-256 multihash.
 * rbx dst, rbp proto, r12 n. A ByteList of 24 + 128 bytes at 32(%rsp).
 */
LOCAL_FUNCTION libp2p_peer_id_proto
    ENTER   0, 160
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmp     $42, %r12
    ja      1f
    movb    $0, (%rbx)
    movb    %r12b, 1(%rbx)
    lea     2(%rbx), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    lea     2(%r12), %rax
    jmp     9f
1:  movq    $152, (32 + LIBP2P_BL_SIZE)(%rsp)
    movq    $LIBP2P_BL_FIXED, (32 + LIBP2P_BL_OFFSET)(%rsp)
    mov     %r12, (32 + LIBP2P_BL_COUNT)(%rsp)
    lea     (32 + LIBP2P_BL_FIXED)(%rsp), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_copy
    movb    $0x12, (%rbx)
    movb    $0x20, 1(%rbx)
    lea     32(%rsp), %rdi
    lea     2(%rbx), %rsi
    CALL_GLOBAL crypto_sha256
    mov     $34, %eax
9:  LEAVE   0, 160
END_FUNCTION libp2p_peer_id_proto

/* ---------------------------------------------------------------- Events for asm-quic */

/* libp2p_qroom() -> the bytes left in the event list for asm-quic. A leaf. */
LOCAL_FUNCTION libp2p_qroom
    UNWIND_END_PROLOGUE
    mov     ST_QEV_OFF(%r15), %rcx
    add     %r15, %rcx
    mov     LIBP2P_BL_SIZE(%rcx), %rax
    sub     $LIBP2P_BL_FIXED, %rax
    sub     LIBP2P_BL_COUNT(%rcx), %rax
    ret
END_FUNCTION libp2p_qroom

/*
 * libp2p_qevent(kind, size) -> a new event at the end of the event list for
 * asm-quic, with its size and kind set and its last word zero; 0 when the
 * list has no room. size is a multiple of 8, at least 24. A leaf.
 */
LOCAL_FUNCTION libp2p_qevent
    UNWIND_END_PROLOGUE
    mov     ST_QEV_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     LIBP2P_BL_SIZE(%rdx), %rcx
    sub     $LIBP2P_BL_FIXED, %rcx
    mov     LIBP2P_BL_COUNT(%rdx), %r8
    sub     %r8, %rcx
    cmp     %rsi, %rcx
    jb      8f
    lea     LIBP2P_BL_FIXED(%rdx,%r8), %rax
    add     %rsi, %r8
    mov     %r8, LIBP2P_BL_COUNT(%rdx)
    movq    $0, -8(%rax,%rsi)
    mov     %rsi, QUIC_EV_SIZE(%rax)
    mov     %rdi, QUIC_EV_KIND(%rax)
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_qevent

/* libp2p_qclose(conn) -> the event, or 0: an asm-quic CLOSE of a connection handle, code 0. */
LOCAL_FUNCTION libp2p_qclose
    ENTER   0
    mov     %rdi, %rbx
    mov     $QUIC_EVENT_CLOSE, %edi
    mov     $QUIC_EV_CLOSE_SIZE, %esi
    call    libp2p_qevent
    test    %rax, %rax
    jz      9f
    mov     %rbx, QUIC_EV_CONN(%rax)
    movq    $0, QUIC_EV_CODE(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_qclose

/* libp2p_qreset(stream) -> the event, or 0: an asm-quic STREAM_RESET of a stream handle, code 0. */
LOCAL_FUNCTION libp2p_qreset
    ENTER   0
    mov     %rdi, %rbx
    mov     $QUIC_EVENT_STREAM_RESET, %edi
    mov     $QUIC_EV_RESET_SIZE, %esi
    call    libp2p_qevent
    test    %rax, %rax
    jz      9f
    mov     %rbx, QUIC_EV_STREAM(%rax)
    movq    $0, QUIC_EV_CODE(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_qreset

/*
 * libp2p_qev_drop(n): the first n events of the list for asm-quic go; the
 * rest moves to the front.
 * rbx list, rbp first event, r12 bytes dropped, r13 bytes in the list.
 */
LOCAL_FUNCTION libp2p_qev_drop
    ENTER   0
    mov     ST_QEV_OFF(%r15), %rbx
    add     %r15, %rbx
    lea     LIBP2P_BL_FIXED(%rbx), %rbp
    xor     %r12d, %r12d
    mov     LIBP2P_BL_COUNT(%rbx), %r13
1:  test    %rdi, %rdi
    jz      2f
    cmp     %r13, %r12
    jae     2f
    add     (%rbp,%r12), %r12
    dec     %rdi
    jmp     1b
2:  mov     %r13, %rdx
    sub     %r12, %rdx
    mov     %rdx, LIBP2P_BL_COUNT(%rbx)
    mov     %rbp, %rdi
    lea     (%rbp,%r12), %rsi
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_qev_drop

/*
 * libp2p_on_datagram(event): a UDP datagram: it joins the event list for
 * asm-quic as a DATAGRAM event of the same fields.
 */
LOCAL_FUNCTION libp2p_on_datagram
    ENTER   0
    mov     %rdi, %rbx
    mov     $QUIC_EVENT_DATAGRAM, %edi
    mov     LIBP2P_EV_SIZE(%rbx), %rsi
    call    libp2p_qevent
    test    %rax, %rax
    jz      9f
    lea     16(%rax), %rdi
    lea     16(%rbx), %rsi
    mov     LIBP2P_EV_SIZE(%rbx), %rdx
    sub     $16, %rdx
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_on_datagram

/* ---------------------------------------------------------------- Handles of asm-quic */

/* libp2p_qconn_of(handle) -> the QUIC connection of an asm-quic connection handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qconn_of
    UNWIND_END_PROLOGUE
    mov     %edi, %ecx
    mov     ST_CONN_COUNT(%r15), %rdx
    cmp     %rdx, %rcx
    jae     8f
    mov     ST_QCMAP_OFF(%r15), %rsi
    add     %r15, %rsi
    movl    (%rsi,%rcx,4), %eax
    cmp     %rdx, %rax
    jae     8f
    imul    $C_SIZE, %rax, %rax
    add     ST_CONN_OFF(%r15), %rax
    add     %r15, %rax
    cmpl    $0, C_PHASE(%rax)
    je      8f
    testq   $CF_QUIC, C_FLAGS(%rax)
    jz      8f
    cmp     C_QUIC(%rax), %rdi
    jne     8f
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_qconn_of

/* libp2p_qconn_bind(handle, conn): the connection gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qconn_bind
    UNWIND_END_PROLOGUE
    mov     %rdi, C_QUIC(%rsi)
    mov     %rsi, %rax
    sub     ST_CONN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $C_SIZE, %ecx
    div     %rcx
    mov     %edi, %ecx
    cmp     ST_CONN_COUNT(%r15), %rcx
    jae     9f
    mov     ST_QCMAP_OFF(%r15), %rdx
    add     %r15, %rdx
    movl    %eax, (%rdx,%rcx,4)
9:  ret
END_FUNCTION libp2p_qconn_bind

/* libp2p_qstream_of(handle) -> the stream of an asm-quic stream handle, or 0. A leaf. */
LOCAL_FUNCTION libp2p_qstream_of
    UNWIND_END_PROLOGUE
    mov     %edi, %ecx
    mov     ST_STREAM_COUNT(%r15), %rdx
    cmp     %rdx, %rcx
    jae     8f
    mov     ST_QMAP_OFF(%r15), %rsi
    add     %r15, %rsi
    movl    (%rsi,%rcx,4), %eax
    cmp     %rdx, %rax
    jae     8f
    imul    $S_SIZE, %rax, %rax
    add     ST_STREAM_OFF(%r15), %rax
    add     %r15, %rax
    cmpl    $0, S_USED(%rax)
    je      8f
    cmp     S_ID(%rax), %rdi
    jne     8f
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_qstream_of

/* libp2p_qstream_bind(handle, stream): the stream gets the asm-quic handle, and the map its index. A leaf. */
LOCAL_FUNCTION libp2p_qstream_bind
    UNWIND_END_PROLOGUE
    mov     %rdi, S_ID(%rsi)
    mov     %rsi, %rax
    sub     ST_STREAM_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $S_SIZE, %ecx
    div     %rcx
    mov     %edi, %ecx
    cmp     ST_STREAM_COUNT(%r15), %rcx
    jae     9f
    mov     ST_QMAP_OFF(%r15), %rdx
    add     %r15, %rdx
    movl    %eax, (%rdx,%rcx,4)
9:  ret
END_FUNCTION libp2p_qstream_bind

/* libp2p_qreason(reason) -> the libp2p reason of a QUIC_ERR_* reason of DIAL_FAILED. A leaf. */
LOCAL_FUNCTION libp2p_qreason
    UNWIND_END_PROLOGUE
    mov     $LIBP2P_REASON_PEER_ID, %eax
    cmp     $QUIC_ERR_PEER_ID, %rdi
    je      9f
    mov     $LIBP2P_REASON_LIMIT, %eax
    cmp     $QUIC_ERR_LIMIT, %rdi
    je      9f
    mov     $LIBP2P_REASON_CONNECT, %eax
    cmp     $QUIC_ERR_HANDSHAKE_TIMEOUT, %rdi
    je      9f
    mov     $LIBP2P_REASON_HANDSHAKE, %eax
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
    mov     QUIC_ACT_KIND(%rdi), %rcx
    cmp     $QUIC_ACTION_SEND, %rcx
    jne     1f
    mov     QUIC_ACT_SIZE(%rdi), %rax
    ret
1:  cmp     $QUIC_ACTION_STREAM_DATA, %rcx
    jne     2f
    mov     QUIC_ACT_S_COUNT(%rdi), %rax
    shl     $4, %rax
    add     $64, %rax
    ret
2:  cmp     $QUIC_ACTION_WAKEUP, %rcx
    jne     3f
    xor     %eax, %eax
    ret
3:  cmp     $QUIC_ACTION_CONNECTED, %rcx
    je      4f
    cmp     $QUIC_ACTION_DIAL_FAILED, %rcx
    je      4f
    cmp     $QUIC_ACTION_CLOSED, %rcx
    je      4f
    mov     $1024, %eax
    ret
4:  mov     $16384, %eax
    ret
END_FUNCTION libp2p_quic_need

/*
 * libp2p_quic_actions() -> 1 when every action of the last quic_step is
 * handled, 0 when the action room ran out first (the next step is then due
 * now, and starts with the rest).
 * rbx the action list, rbp bytes handled, r12 action, r13 room it needs.
 */
LOCAL_FUNCTION libp2p_quic_actions
    ENTER   0
    mov     ST_QACT_OFF(%r15), %rbx
    add     %r15, %rbx
    mov     ST_QACT_DONE(%r15), %rbp
1:  cmp     LIBP2P_BL_COUNT(%rbx), %rbp
    jae     7f
    mov     LIBP2P_BL_OFFSET(%rbx), %r12
    add     %rbx, %r12
    add     %rbp, %r12
    mov     %r12, %rdi
    call    libp2p_quic_need
    mov     %rax, %r13
    call    libp2p_room
    cmp     %r13, %rax
    jb      8f
    mov     %r12, %rdi
    call    libp2p_quic_action
    add     QUIC_ACT_SIZE(%r12), %rbp
    mov     %rbp, ST_QACT_DONE(%r15)
    jmp     1b
7:  movq    $0, LIBP2P_BL_COUNT(%rbx)
    movq    $0, ST_QACT_DONE(%r15)
    mov     $1, %eax
    jmp     9f
8:  mov     SC_NOW(%r14), %rdi
    call    libp2p_wake_at
    xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_quic_actions

/* libp2p_quic_action(action): one action of asm-quic: a direct call for each kind. */
LOCAL_FUNCTION libp2p_quic_action
    ENTER   0
    mov     QUIC_ACT_KIND(%rdi), %rax
    cmp     $QUIC_ACTION_SEND, %rax
    jne     1f
    call    libp2p_q_send
    jmp     9f
1:  cmp     $QUIC_ACTION_WAKEUP, %rax
    jne     2f
    mov     QUIC_ACT_TIME(%rdi), %rax
    mov     %rax, ST_QUIC_WAKE(%r15)
    jmp     9f
2:  cmp     $QUIC_ACTION_CONNECTED, %rax
    jne     3f
    call    libp2p_q_connected
    jmp     9f
3:  cmp     $QUIC_ACTION_DIAL_FAILED, %rax
    jne     4f
    call    libp2p_q_dial_failed
    jmp     9f
4:  cmp     $QUIC_ACTION_CLOSED, %rax
    jne     5f
    call    libp2p_q_closed
    jmp     9f
5:  cmp     $QUIC_ACTION_STREAM_OPENED, %rax
    jne     6f
    call    libp2p_q_opened
    jmp     9f
6:  cmp     $QUIC_ACTION_STREAM_DATA, %rax
    jne     7f
    call    libp2p_q_data
    jmp     9f
7:  cmp     $QUIC_ACTION_STREAM_FIN, %rax
    jne     8f
    call    libp2p_q_fin
    jmp     9f
8:  cmp     $QUIC_ACTION_STREAM_RESET, %rax
    jne     10f
    call    libp2p_q_reset
    jmp     9f
10: cmp     $QUIC_ACTION_STREAM_ACKED, %rax
    jne     9f
    call    libp2p_q_acked
9:  LEAVE   0
END_FUNCTION libp2p_quic_action

/* libp2p_q_send(action): an asm-quic SEND becomes a SEND_DATAGRAM action of the same fields. */
LOCAL_FUNCTION libp2p_q_send
    ENTER   0
    mov     %rdi, %rbx
    mov     $LIBP2P_ACTION_SEND_DATAGRAM, %edi
    mov     QUIC_ACT_SIZE(%rbx), %rsi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    lea     16(%rax), %rdi
    lea     16(%rbx), %rsi
    mov     QUIC_ACT_SIZE(%rbx), %rdx
    sub     $16, %rdx
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_q_send

/*
 * libp2p_q_connected(action): a QUIC connection is up: our dial (the tag is
 * the connection handle) or a peer's (tag 0, a new slot). The peer ID comes
 * from the host key; then the connection is open and bound to its peer. A
 * connection nobody waits for, or with no slot, is closed.
 * rbx action, rbp conn.
 */
LOCAL_FUNCTION libp2p_q_connected
    ENTER   0
    mov     %rdi, %rbx
    mov     QUIC_ACT_TAG(%rbx), %rdi
    test    %rdi, %rdi
    jz      1f
    call    libp2p_conn
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      8f
    testq   $CF_QUIC, C_FLAGS(%rbp)
    jz      8f
    cmpl    $PH_DIALING, C_PHASE(%rbp)
    jne     8f
    jmp     2f
1:  mov     $2, %edi                        /* a peer's: QUIC, inbound */
    call    libp2p_conn_new
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      8f
    lea     C_ADDR(%rbp), %rdi
    lea     QUIC_ACT_C_ADDR(%rbx), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    mov     QUIC_ACT_C_SOCKET(%rbx), %rax
    mov     %rax, C_QSOCK(%rbp)
2:  mov     QUIC_ACT_CONN(%rbx), %rdi
    mov     %rbp, %rsi
    call    libp2p_qconn_bind
    lea     C_RID(%rbp), %rdi
    lea     QUIC_ACT_KEY(%rbx), %rsi
    mov     QUIC_ACT_KEY_LEN(%rbx), %rdx
    call    libp2p_peer_id_proto
    mov     %rax, C_RID_LEN(%rbp)
    mov     %rbp, %rdi
    call    libp2p_conn_opened
    jmp     9f
8:  mov     QUIC_ACT_CONN(%rbx), %rdi
    call    libp2p_qclose
9:  LEAVE   0
END_FUNCTION libp2p_q_connected

/* libp2p_q_dial_failed(action): our QUIC dial failed: DIAL_FAILED with its reason, and the slot is free. */
LOCAL_FUNCTION libp2p_q_dial_failed
    ENTER   0
    mov     %rdi, %rbx
    mov     QUIC_ACT_TAG(%rbx), %rdi
    call    libp2p_conn
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    testq   $CF_QUIC, C_FLAGS(%rbp)
    jz      9f
    cmpl    $PH_DIALING, C_PHASE(%rbp)
    jne     9f
    mov     QUIC_ACT_REASON(%rbx), %rdi
    call    libp2p_qreason
    mov     %rax, %rsi
    mov     %rbp, %rdi
    call    libp2p_conn_teardown
    mov     %rbp, %rdi
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_dial_failed

/* libp2p_q_closed(action): a QUIC connection is over: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_q_closed
    ENTER   0
    mov     QUIC_ACT_CONN(%rdi), %rdi
    call    libp2p_qconn_of
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    cmpl    $PH_CLOSING, C_PHASE(%rbx)
    je      1f
    mov     %rbx, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_teardown
1:  mov     %rbx, %rdi
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_q_closed

/*
 * libp2p_q_opened(action): an asm-quic stream is open. Ours (the tag is the
 * stream handle) gets its asm-quic handle, or fails with LIMIT when asm-quic
 * had none; a peer's (tag 0) gets a new stream slot. A stream nobody waits
 * for, or with no slot, is reset.
 * rbx action, rbp stream, r12 the asm-quic stream.
 */
LOCAL_FUNCTION libp2p_q_opened
    ENTER   0
    mov     %rdi, %rbx
    mov     QUIC_ACT_STREAM(%rbx), %r12
    mov     QUIC_ACT_S_TAG(%rbx), %rdi
    test    %rdi, %rdi
    jz      1f
    call    libp2p_stream
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      7f
    cmpq    $0, S_ID(%rbp)
    jne     7f
    mov     %rbp, %rdi
    call    libp2p_stream_conn
    testq   $CF_QUIC, C_FLAGS(%rax)
    jz      7f
    mov     C_QUIC(%rax), %rcx
    cmp     QUIC_ACT_S_CONN(%rbx), %rcx
    jne     7f
    test    %r12, %r12
    jz      6f
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    libp2p_qstream_bind
    jmp     9f
1:  mov     QUIC_ACT_S_CONN(%rbx), %rdi     /* the peer's */
    call    libp2p_qconn_of
    test    %rax, %rax
    jz      7f
    cmpl    $PH_OPEN, C_PHASE(%rax)
    jne     7f
    test    %r12, %r12
    jz      9f
    mov     %rax, %rdi
    mov     %r12, %rsi
    xor     %edx, %edx
    call    libp2p_stream_new
    test    %rax, %rax
    jz      7f
    mov     %rax, %rsi
    mov     %r12, %rdi
    call    libp2p_qstream_bind
    jmp     9f
6:  mov     %rbp, %rdi
    mov     $LIBP2P_REASON_LIMIT, %esi
    call    libp2p_stream_abort
    jmp     9f
7:  test    %r12, %r12
    jz      9f
    mov     %r12, %rdi
    call    libp2p_qreset
9:  LEAVE   0
END_FUNCTION libp2p_q_opened

/* libp2p_q_data(action): bytes of an asm-quic stream go to its stream. */
LOCAL_FUNCTION libp2p_q_data
    ENTER   0
    mov     %rdi, %rbx
    mov     QUIC_ACT_STREAM(%rbx), %rdi
    call    libp2p_qstream_of
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    lea     QUIC_ACT_S_DATA(%rbx), %rsi
    mov     QUIC_ACT_S_COUNT(%rbx), %rdx
    call    libp2p_stream_data
9:  LEAVE   0
END_FUNCTION libp2p_q_data

/* libp2p_q_fin(action): the peer closed its side of an asm-quic stream. */
LOCAL_FUNCTION libp2p_q_fin
    ENTER   0
    mov     QUIC_ACT_STREAM(%rdi), %rdi
    call    libp2p_qstream_of
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_stream_remote_fin
9:  LEAVE   0
END_FUNCTION libp2p_q_fin

/* libp2p_q_reset(action): the peer reset an asm-quic stream: our side is reset too, and the stream ends. */
LOCAL_FUNCTION libp2p_q_reset
    ENTER   0
    mov     QUIC_ACT_STREAM(%rdi), %rbx
    mov     %rbx, %rdi
    call    libp2p_qstream_of
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_qreset
    mov     %rbp, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_stream_kill
9:  LEAVE   0
END_FUNCTION libp2p_q_reset

/* libp2p_q_acked(action): the peer has bytes of a stream: they leave the bytes in flight. */
LOCAL_FUNCTION libp2p_q_acked
    ENTER   0
    mov     %rdi, %rbx
    mov     QUIC_ACT_STREAM(%rbx), %rdi
    call    libp2p_qstream_of
    test    %rax, %rax
    jz      9f
    mov     S_QFLIGHT(%rax), %rcx
    mov     QUIC_ACT_S_COUNT(%rbx), %rdx
    cmp     %rcx, %rdx
    cmova   %rcx, %rdx
    sub     %rdx, %rcx
    mov     %rcx, S_QFLIGHT(%rax)
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
 * rbx conn, rbp stream, r12 event, X23 flags, X24 asm-quic stream, X25 bytes.
 */
LOCAL_FUNCTION libp2p_quic_emit
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     S_FLAGS(%rbp), %rax
    mov     %rax, X23(%rsp)
    mov     S_ID(%rbp), %rax
    mov     %rax, X24(%rsp)
    testq   $SF_RST, X23(%rsp)
    jz      1f
    cmpq    $0, X24(%rsp)                   /* asm-quic never had it */
    je      11f
    mov     X24(%rsp), %rdi
    call    libp2p_qreset
    test    %rax, %rax
    jz      80f
11: orq     $SF_DEAD, X23(%rsp)
    jmp     90f
1:  testq   $SF_SYN, X23(%rsp)
    jz      2f
    mov     $QUIC_EVENT_OPEN_STREAM, %edi
    mov     $QUIC_EV_OPEN_SIZE, %esi
    call    libp2p_qevent
    test    %rax, %rax
    jz      80f
    mov     %rax, %r12
    mov     C_QUIC(%rbx), %rax
    mov     %rax, QUIC_EV_CONN(%r12)
    mov     %rbp, %rdi
    call    libp2p_stream_handle
    mov     %rax, QUIC_EV_OPEN_TAG(%r12)
    andq    $~SF_SYN, X23(%rsp)
2:  cmpq    $0, X24(%rsp)                   /* waiting for STREAM_OPENED */
    je      90f
3:  mov     S_Q_HEAD(%rbp), %rcx            /* data, within the window */
    cmp     $-1, %rcx
    je      4f
    CFG     %rax, LIBP2P_CFG_QUIC_WINDOW
    sub     S_QFLIGHT(%rbp), %rax
    jbe     90f
    mov     (CH_LEN - HB_HEADER)(%r15,%rcx), %rdx
    sub     (CH_DONE - HB_HEADER)(%r15,%rcx), %rdx
    cmp     %rdx, %rax
    cmova   %rdx, %rax
    mov     $LIBP2P_QUIC_WRITE, %edx
    cmp     %rdx, %rax
    cmova   %rdx, %rax
    mov     %rax, X25(%rsp)
    call    libp2p_qroom
    cmp     $(QUIC_EV_WRITE_DATA + 8), %rax
    jbe     80f
    sub     $(QUIC_EV_WRITE_DATA + 8), %rax
    mov     X25(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    mov     %rcx, X25(%rsp)
    lea     (QUIC_EV_WRITE_DATA + 7)(%rcx), %rsi
    and     $-8, %rsi
    mov     $QUIC_EVENT_STREAM_WRITE, %edi
    call    libp2p_qevent
    test    %rax, %rax
    jz      80f
    mov     %rax, %r12
    mov     X24(%rsp), %rax
    mov     %rax, QUIC_EV_STREAM(%r12)
    mov     X25(%rsp), %rax
    mov     %rax, QUIC_EV_WRITE_COUNT(%r12)
    mov     %rbp, %rdi
    lea     QUIC_EV_WRITE_DATA(%r12), %rsi
    mov     X25(%rsp), %rdx
    call    libp2p_chunk_take
    mov     X25(%rsp), %rax
    add     %rax, S_QFLIGHT(%rbp)
    jmp     3b
4:  testq   $SF_FIN, X23(%rsp)              /* FIN after the queue */
    jz      5f
    testq   $SF_FIN_SENT, X23(%rsp)
    jnz     5f
    mov     $QUIC_EVENT_STREAM_CLOSE, %edi
    mov     $QUIC_EV_STREAM_SIZE, %esi
    call    libp2p_qevent
    test    %rax, %rax
    jz      80f
    mov     X24(%rsp), %rcx
    mov     %rcx, QUIC_EV_STREAM(%rax)
    orq     $SF_FIN_SENT, X23(%rsp)
5:  mov     X23(%rsp), %rax
    and     $(SF_FIN_SENT | SF_REMOTE_FIN), %eax
    cmp     $(SF_FIN_SENT | SF_REMOTE_FIN), %eax
    jne     90f
    orq     $SF_DEAD, X23(%rsp)
90: mov     X23(%rsp), %rax
    mov     %rax, S_FLAGS(%rbp)
    xor     %eax, %eax
    jmp     99f
80: mov     X23(%rsp), %rax
    mov     %rax, S_FLAGS(%rbp)
    mov     $1, %eax
99: LEAVE   0
END_FUNCTION libp2p_quic_emit

/*
 * libp2p_quic_gather() -> 0, or 1 when the event list is full: the events
 * of each QUIC connection for asm-quic: DIAL for a new dial, CLOSE for a
 * connection that ends, then the events of each stream of an open one;
 * dead streams are freed.
 * rbx conn, rbp connections left, r12 stream index, r13 stream, X23 result.
 */
LOCAL_FUNCTION libp2p_quic_gather
    ENTER   0
    TABLE   %rbx, ST_CONN_OFF
    mov     ST_CONN_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      8f
    cmpl    $0, C_PHASE(%rbx)
    je      5f
    testq   $CF_QUIC, C_FLAGS(%rbx)
    jz      5f
    testq   $CF_QDIAL, C_FLAGS(%rbx)
    jz      2f
    mov     $QUIC_EVENT_DIAL, %edi
    mov     $QUIC_EV_DIAL_SIZE, %esi
    call    libp2p_qevent
    test    %rax, %rax
    jz      7f
    mov     %rax, %r12
    mov     %rbx, %rdi
    call    libp2p_conn_handle
    mov     %rax, QUIC_EV_TAG(%r12)
    mov     C_QSOCK(%rbx), %rax
    mov     %rax, QUIC_EV_DIAL_SOCKET(%r12)
    lea     QUIC_EV_DIAL_ADDR(%r12), %rdi
    lea     C_ADDR(%rbx), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    lea     QUIC_EV_PEER(%r12), %rdi
    mov     $QUIC_PEER_MAX, %esi
    call    libp2p_zero
    mov     C_EXP_ID_LEN(%rbx), %rdx
    mov     %rdx, QUIC_EV_PEER_LEN(%r12)
    lea     QUIC_EV_PEER(%r12), %rdi
    lea     C_EXP_ID(%rbx), %rsi
    call    libp2p_copy
    andq    $~CF_QDIAL, C_FLAGS(%rbx)
2:  testq   $CF_NEED_CLOSE, C_FLAGS(%rbx)
    jz      3f
    mov     C_QUIC(%rbx), %rdi
    test    %rdi, %rdi
    jz      3f
    call    libp2p_qclose
    test    %rax, %rax
    jz      7f
    andq    $~CF_NEED_CLOSE, C_FLAGS(%rbx)
3:  cmpl    $PH_OPEN, C_PHASE(%rbx)
    jne     5f
    mov     C_STREAM_HEAD(%rbx), %r12
4:  cmp     $-1, %r12
    je      5f
    mov     %r12, %rdi
    call    libp2p_stream_at
    mov     %rax, %r13
    mov     S_NEXT(%r13), %r12
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    libp2p_quic_emit
    mov     %rax, X23(%rsp)
    testq   $SF_DEAD, S_FLAGS(%r13)
    jz      41f
    mov     %r13, %rdi
    call    libp2p_stream_free
41: cmpq    $0, X23(%rsp)
    jne     7f
    jmp     4b
5:  add     $C_SIZE, %rbx
    dec     %rbp
    jmp     1b
7:  mov     $1, %eax
    jmp     9f
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_quic_gather

/*
 * libp2p_quic_pump(): runs asm-quic for the step. Each round hands on the
 * actions of the last quic_step, writes the events of the connections and
 * streams, and runs quic_step when it has events or a deadline is due; at
 * most 16 rounds. Then the next step is due at the deadline of asm-quic,
 * rounded up to a millisecond, or now while events or actions wait.
 * rbx rounds left, rbp the event list.
 */
LOCAL_FUNCTION libp2p_quic_pump
    ENTER   0
    mov     ST_QEV_OFF(%r15), %rbp
    add     %r15, %rbp
    mov     $16, %ebx
1:  call    libp2p_quic_actions
    test    %rax, %rax
    jz      9f                              /* the action room ran out: the rest waits */
    call    libp2p_quic_gather
    cmpq    $0, LIBP2P_BL_COUNT(%rbp)
    jne     2f
    mov     (SC_QTICK + QUIC_TICK_NOW)(%r14), %rax
    cmp     ST_QUIC_WAKE(%r15), %rax
    jb      7f                              /* nothing to do or due */
2:  test    %rbx, %rbx
    jz      6f
    dec     %rbx
    mov     ST_QUIC_OFF(%r15), %rdi
    add     %r15, %rdi
    SCR     %rsi, SC_QTICK
    mov     %rbp, %rdx
    SCR     %rcx, SC_QSCRATCH
    movq    $QUIC_SCRATCH_SIZE, (%rcx)
    mov     ST_QACT_OFF(%r15), %r8
    add     %r15, %r8
    movq    $(LIBP2P_BL_FIXED + LIBP2P_QUIC_ACTIONS), LIBP2P_BL_SIZE(%r8)
    SCR     %r9, SC_QRESULT
    movq    $0, (%r9)
    CALL_GLOBAL quic_step
    movq    $0, ST_QACT_DONE(%r15)
    mov     SC_QRESULT(%r14), %rdi
    call    libp2p_qev_drop
    jmp     1b
6:  mov     SC_NOW(%r14), %rdi              /* rounds used up */
    call    libp2p_wake_at
7:  cmpq    $0, LIBP2P_BL_COUNT(%rbp)
    je      71f
    mov     SC_NOW(%r14), %rdi
    call    libp2p_wake_at
    jmp     9f
71: mov     ST_QUIC_WAKE(%r15), %rax
    add     $999, %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, %rdi
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_quic_pump

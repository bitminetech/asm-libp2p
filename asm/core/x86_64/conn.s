/*
 * Connections of the x86-64 core: the shell events of a TCP connection,
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
    .p2align 2

/* libp2p_ms_put(dst, str, n) -> dst after one multistream message: varint(n), then the n bytes (the newline included). */
LOCAL_FUNCTION libp2p_ms_put
    ENTER   0
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     %rbp, %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    LEAVE   0
END_FUNCTION libp2p_ms_put

/* libp2p_ms_put_proto(dst, bytes, n) -> dst after the message of a protocol ID: varint(n + 1), the bytes, a newline. */
LOCAL_FUNCTION libp2p_ms_put_proto
    ENTER   0
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    lea     1(%rbp), %rsi
    call    libp2p_varint_put
    mov     %rax, %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    libp2p_copy
    movb    $10, (%rax)
    inc     %rax
    LEAVE   0
END_FUNCTION libp2p_ms_put_proto

/*
 * libp2p_ms_take(ms, cap, src, n) -> rax the bytes taken from src, rdx the
 * result: 0 when more bytes are needed, 1 when one whole message is in the
 * buffer, 2 when the bytes are not a message that fits. ms holds the
 * negotiation state, the bytes held, the varint length of the message,
 * then cap bytes of buffer. The message (its newline last) is at buffer +
 * varint length. Bytes after the message stay in src.
 * rbx ms, rbp cap, r12 src, r13 n, X23 taken, X24 the bytes held.
 */
.set MS_STATE, 0
.set MS_LEN, 8
.set MS_NEED, 16
.set MS_BUF, 24
LOCAL_FUNCTION libp2p_ms_take
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, X23(%rsp)
1:  mov     X23(%rsp), %rax
    cmp     %r13, %rax
    jae     7f
    mov     MS_LEN(%rbx), %rcx
    cmp     %rbp, %rcx
    jae     8f
    movzbl  (%r12,%rax), %edx
    movb    %dl, MS_BUF(%rbx,%rcx)
    inc     %rcx
    mov     %rcx, MS_LEN(%rbx)
    mov     %rcx, X24(%rsp)
    inc     %rax
    mov     %rax, X23(%rsp)
    lea     MS_BUF(%rbx), %rdi
    lea     (%rdi,%rcx), %rsi
    call    libp2p_varint_get
    cmp     $NONE, %rdx
    je      8f
    test    %rdx, %rdx
    jz      1b
    test    %rax, %rax
    jz      8f
    mov     %rbp, %rcx
    sub     %rdx, %rcx
    cmp     %rcx, %rax
    ja      8f
    lea     (%rax,%rdx), %rcx
    cmp     %rcx, X24(%rsp)
    jb      1b
    mov     %rdx, MS_NEED(%rbx)
    mov     X24(%rsp), %rcx
    cmpb    $10, (MS_BUF - 1)(%rbx,%rcx)
    jne     8f
    mov     X23(%rsp), %rax
    mov     $1, %edx
    jmp     9f
7:  mov     X23(%rsp), %rax
    xor     %edx, %edx
    jmp     9f
8:  mov     X23(%rsp), %rax
    mov     $2, %edx
9:  LEAVE   0
END_FUNCTION libp2p_ms_take

/* libp2p_ms_is(ms, str, n) -> 1 when the message in ms is the n bytes at str, else 0. */
LOCAL_FUNCTION libp2p_ms_is
    FRAME
    mov     MS_NEED(%rdi), %rax
    mov     MS_LEN(%rdi), %rcx
    lea     MS_BUF(%rdi,%rax), %r8
    sub     %rax, %rcx
    mov     %rdx, %r9
    mov     %rsi, %rdx
    mov     %rcx, %rsi
    mov     %r9, %rcx
    mov     %r8, %rdi
    call    libp2p_compare
    UNFRAME
END_FUNCTION libp2p_ms_is

/* ---------------------------------------------------------------- Connection slots */

/*
 * libp2p_conn_new(outbound) -> a new connection slot with its receive buffer,
 * in phase PH_DIALING, or 0 when no slot or heap block is free.
 */
LOCAL_FUNCTION libp2p_conn_new
    ENTER   0
    mov     %rdi, %rbx
    mov     $ST_CONN_OFF, %edi
    mov     $ST_CONN_COUNT, %esi
    mov     $C_SIZE, %edx
    call    libp2p_alloc_slot
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    mov     $LIBP2P_RX_SIZE, %edi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jnz     1f
    movl    $0, C_PHASE(%rbp)
    xor     %eax, %eax
    jmp     9f
1:  mov     %rax, C_RX(%rbp)
    movq    $NONE, C_PEER(%rbp)
    movq    $NONE, C_STREAM_HEAD(%rbp)
    movq    $NONE, C_MX_STREAM(%rbp)
    movq    $NONE, C_CURSOR(%rbp)
    xor     %eax, %eax
    test    %rbx, %rbx
    jz      2f
    mov     $CF_OUTBOUND, %eax
2:  mov     %rax, C_FLAGS(%rbp)
    mov     SC_NOW(%r14), %rax
    add     (ST_CONFIG + LIBP2P_CFG_HANDSHAKE_MS)(%r15), %rax
    mov     %rax, C_DEADLINE(%rbp)
    movl    $PH_DIALING, C_PHASE(%rbp)
    incq    ST_CONN_LIVE(%r15)
    mov     %rbp, %rax
9:  LEAVE   0
END_FUNCTION libp2p_conn_new

/* libp2p_conn_handle(conn) -> its handle. */
LOCAL_FUNCTION libp2p_conn_handle
    FRAME
    mov     %rdi, %rdx
    mov     $ST_CONN_OFF, %edi
    mov     $C_SIZE, %esi
    call    libp2p_handle
    UNFRAME
END_FUNCTION libp2p_conn_handle

/* libp2p_conn_free(conn): the slot becomes free. */
LOCAL_FUNCTION libp2p_conn_free
    ENTER   0
    mov     %rdi, %rbx
    mov     C_RX(%rbx), %rdi
    call    libp2p_heap_free
    movq    $0, C_RX(%rbx)
    movl    $0, C_PHASE(%rbx)
    decq    ST_CONN_LIVE(%r15)
    LEAVE   0
END_FUNCTION libp2p_conn_free

/* libp2p_conn_out(conn, str, n): queues one multistream message (str holds n bytes, the newline included). */
LOCAL_FUNCTION libp2p_conn_out
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     1(%r12), %rsi
    call    libp2p_noise_out
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_ms_put
9:  LEAVE   0
END_FUNCTION libp2p_conn_out

/*
 * libp2p_conn_teardown(conn, reason): ends everything above the socket: the
 * streams (the application hears of its own); then the peer
 * (PEER_DISCONNECTED) when this was its connection and no other is open,
 * else another connection of the peer takes over; or, for a dial not yet
 * reported, DIAL_FAILED; then the receive buffer.
 * rbx conn, rbp reason, r12 peer index, r13 peer.
 */
LOCAL_FUNCTION libp2p_conn_teardown
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
1:  mov     C_STREAM_HEAD(%rbx), %rax       /* the streams */
    cmp     $NONE, %rax
    je      2f
    imul    $S_SIZE, %rax, %rdi
    add     ST_STREAM_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_stream_kill
    jmp     1b
2:  mov     C_PEER(%rbx), %r12
    cmp     $NONE, %r12
    je      3f
    movq    $NONE, C_PEER(%rbx)             /* this connection no longer counts for the peer */
    imul    $P_SIZE, %r12, %r13             /* the peer */
    add     ST_PEER_OFF(%r15), %r13
    add     %r15, %r13
    mov     %rbx, %rax
    sub     ST_CONN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $C_SIZE, %ecx
    div     %rcx
    cmp     P_CONN(%r13), %rax
    jne     4f                              /* a secondary connection: the peer stays */
    mov     %r12, %rdi
    mov     %rbx, %rsi
    call    libp2p_peer_other
    test    %rax, %rax
    jz      21f
    mov     %rax, %rcx                      /* another connection of the peer takes over */
    sub     ST_CONN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $C_SIZE, %r8d
    div     %r8
    mov     %rax, P_CONN(%r13)
    mov     C_FLAGS(%rcx), %rax
    and     $CF_OUTBOUND, %rax
    mov     P_FLAGS(%r13), %rdx
    and     $~PF_OUTBOUND, %rdx
    or      %rax, %rdx
    mov     %rdx, P_FLAGS(%r13)
    mov     (C_ADDR + LIBP2P_ADDR_IP)(%rcx), %rax
    mov     %rax, P_IP(%r13)
    mov     (C_ADDR + LIBP2P_ADDR_IP + 8)(%rcx), %rax
    mov     %rax, (P_IP + 8)(%r13)
    mov     (C_ADDR + LIBP2P_ADDR_FAMILY)(%rcx), %rax
    mov     %rax, P_IP_FAMILY(%r13)
    mov     %r13, %rdi
    call    libp2p_gossip_peer_up               /* our gossipsub stream again, on that connection */
    jmp     4f
21: mov     %r13, %rdi
    call    libp2p_peer_down
    jmp     4f
3:  mov     C_FLAGS(%rbx), %rax
    test    $CF_OUTBOUND, %rax
    jz      4f
    test    $CF_REPORTED, %rax
    jnz     4f
    or      $CF_REPORTED, %rax
    mov     %rax, C_FLAGS(%rbx)
    mov     $LIBP2P_ACTION_DIAL_FAILED, %edi
    mov     $LIBP2P_ACT_FAILED_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      4f
    mov     C_TAG(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TAG(%rax)
    mov     %rbp, LIBP2P_ACT_REASON(%rax)
4:  mov     C_RX(%rbx), %rdi
    call    libp2p_heap_free
    movq    $0, C_RX(%rbx)
    movq    $0, C_RX_LEN(%rbx)
    movq    $0, C_OUT_LEN(%rbx)
    movq    $0, C_OUT_RAW(%rbx)
    LEAVE   0
END_FUNCTION libp2p_conn_teardown

/*
 * libp2p_conn_close(conn, reason): ends a live connection: teardown, then a
 * CLOSE action (kept as a flag for the drain when the list is full); the
 * slot waits in PH_CLOSING for the CLOSED event.
 */
LOCAL_FUNCTION libp2p_conn_close
    ENTER   0
    mov     %rdi, %rbx
    movl    C_PHASE(%rbx), %eax
    cmp     $PH_DIALING, %eax
    jb      9f
    cmp     $PH_CLOSING, %eax
    jae     9f
    call    libp2p_conn_teardown
    movl    $PH_CLOSING, C_PHASE(%rbx)
    mov     %rbx, %rdi
    call    libp2p_conn_send_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_close

/* libp2p_conn_send_close(conn): a CLOSE action for the connection, or the flag that asks the drain for one. */
LOCAL_FUNCTION libp2p_conn_send_close
    ENTER   0
    mov     %rdi, %rbx
    mov     $LIBP2P_ACTION_CLOSE, %edi
    mov     $LIBP2P_ACT_CLOSE_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jnz     1f
    orq     $CF_NEED_CLOSE, C_FLAGS(%rbx)
    jmp     9f
1:  andq    $~CF_NEED_CLOSE, C_FLAGS(%rbx)
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_conn_handle
    mov     %rax, LIBP2P_ACT_CONN(%rbp)
9:  LEAVE   0
END_FUNCTION libp2p_conn_send_close

/* ---------------------------------------------------------------- Shell events */

/* libp2p_on_accepted(event): a new inbound connection: ADOPT it, or REFUSE it when no slot is free. */
LOCAL_FUNCTION libp2p_on_accepted
    ENTER   0
    mov     %rdi, %rbx
    xor     %edi, %edi
    call    libp2p_conn_new
    test    %rax, %rax
    jnz     1f
    mov     $LIBP2P_ACTION_REFUSE, %edi
    mov     $LIBP2P_ACT_REFUSE_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     LIBP2P_EV_TOKEN(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TOKEN(%rax)
    jmp     9f
1:  mov     %rax, %rbp
    lea     C_ADDR(%rbp), %rdi
    lea     LIBP2P_EV_ACCEPTED_ADDR(%rbx), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    movl    $PH_SECURITY, C_PHASE(%rbp)
    mov     $LIBP2P_ACTION_ADOPT, %edi
    mov     $LIBP2P_ACT_ADOPT_SIZE, %esi
    call    libp2p_action
    mov     %rax, %r12
    test    %r12, %r12
    jz      8f
    mov     LIBP2P_EV_TOKEN(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TOKEN(%r12)
    mov     %rbp, %rdi
    call    libp2p_conn_handle
    mov     %rax, LIBP2P_ACT_ADOPT_CONN(%r12)
    jmp     9f
8:  mov     %rbp, %rdi                      /* no room: give the slot back */
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_accepted

/* libp2p_on_dial(event): the application asks for a connection: a DIAL action, or DIAL_FAILED when no slot is free. */
LOCAL_FUNCTION libp2p_on_dial
    ENTER   0
    mov     %rdi, %rbx
    mov     $1, %edi
    call    libp2p_conn_new
    test    %rax, %rax
    jnz     1f
    mov     $LIBP2P_ACTION_DIAL_FAILED, %edi
    mov     $LIBP2P_ACT_FAILED_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     LIBP2P_EV_TAG(%rbx), %rcx
    mov     %rcx, LIBP2P_ACT_TAG(%rax)
    movq    $LIBP2P_REASON_LIMIT, LIBP2P_ACT_REASON(%rax)
    jmp     9f
1:  mov     %rax, %rbp
    mov     LIBP2P_EV_TAG(%rbx), %rcx
    mov     %rcx, C_TAG(%rbp)
    lea     C_ADDR(%rbp), %rdi
    lea     LIBP2P_EV_DIAL_ADDR(%rbx), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    mov     LIBP2P_EV_DIAL_ID_LEN(%rbx), %rdx
    mov     %rdx, C_EXP_ID_LEN(%rbp)
    lea     C_EXP_ID(%rbp), %rdi
    lea     LIBP2P_EV_DIAL_ID(%rbx), %rsi
    call    libp2p_copy
    mov     $LIBP2P_ACTION_DIAL, %edi
    mov     $LIBP2P_ACT_DIAL_SIZE, %esi
    call    libp2p_action
    mov     %rax, %r12
    test    %r12, %r12
    jz      8f
    mov     %rbp, %rdi
    call    libp2p_conn_handle
    mov     %rax, LIBP2P_ACT_CONN(%r12)
    lea     LIBP2P_ACT_DIAL_ADDR(%r12), %rdi
    lea     C_ADDR(%rbp), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    jmp     9f
8:  mov     %rbp, %rdi
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial

/* libp2p_on_connected(event): the dial worked: propose /noise. */
LOCAL_FUNCTION libp2p_on_connected
    ENTER   0
    mov     LIBP2P_EV_CONN(%rdi), %rdi
    call    libp2p_conn
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    cmpl    $PH_DIALING, C_PHASE(%rbx)
    jne     9f
    movl    $PH_SECURITY, C_PHASE(%rbx)
    orq     $CF_SENT_HEADER, C_FLAGS(%rbx)
    mov     %rbx, %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_conn_out
    mov     %rbx, %rdi
    lea     432b(%rip), %rsi
    mov     $7, %edx
    call    libp2p_conn_out
9:  LEAVE   0
END_FUNCTION libp2p_on_connected

/* libp2p_on_dial_failed(event): the dial failed: DIAL_FAILED, and the slot is free. */
LOCAL_FUNCTION libp2p_on_dial_failed
    ENTER   0
    mov     LIBP2P_EV_CONN(%rdi), %rdi
    call    libp2p_conn
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    movl    C_PHASE(%rbx), %eax
    cmp     $PH_CLOSING, %eax
    je      1f
    cmp     $PH_DIALING, %eax
    jne     9f
    mov     %rbx, %rdi
    mov     $LIBP2P_REASON_CONNECT, %esi
    call    libp2p_conn_teardown
1:  mov     %rbx, %rdi
    call    libp2p_conn_free
9:  LEAVE   0
END_FUNCTION libp2p_on_dial_failed

/* libp2p_on_closed(event): the shell closed the socket: teardown when it was live, and the slot is free. */
LOCAL_FUNCTION libp2p_on_closed
    ENTER   0
    mov     LIBP2P_EV_CONN(%rdi), %rdi
    call    libp2p_conn
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
END_FUNCTION libp2p_on_closed

/* libp2p_on_sent(event): the shell wrote count bytes of the connection. */
LOCAL_FUNCTION libp2p_on_sent
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_CONN(%rbx), %rdi
    call    libp2p_conn
    test    %rax, %rax
    jz      9f
    mov     C_INFLIGHT(%rax), %rcx
    mov     LIBP2P_EV_COUNT(%rbx), %rdx
    cmp     %rcx, %rdx
    cmova   %rcx, %rdx
    sub     %rdx, %rcx
    mov     %rcx, C_INFLIGHT(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_on_sent

/*
 * libp2p_on_disconnect(event): the application ends the connections of a peer:
 * its secondary connections, then the first.
 * rbx peer, rbp peer index.
 */
LOCAL_FUNCTION libp2p_on_disconnect
    ENTER   0
    mov     LIBP2P_EV_PEER(%rdi), %rdi
    call    libp2p_peer
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     %rax, %rbp
1:  mov     %rbp, %rdi
    imul    $C_SIZE, P_CONN(%rbx), %rsi
    add     ST_CONN_OFF(%r15), %rsi
    add     %r15, %rsi
    call    libp2p_peer_other
    test    %rax, %rax
    jz      2f
    mov     %rax, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_close
    jmp     1b
2:  imul    $C_SIZE, P_CONN(%rbx), %rdi
    add     ST_CONN_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_disconnect

/* ---------------------------------------------------------------- Receiving */

/*
 * libp2p_on_received(event): bytes of a connection: into its receive buffer,
 * which is handled each time it fills or the bytes end.
 * rbx conn, rbp data, r12 bytes left, r13 the bytes of this round.
 */
LOCAL_FUNCTION libp2p_on_received
    ENTER   0
    mov     %rdi, %rbx
    lea     LIBP2P_EV_DATA(%rbx), %rbp
    mov     LIBP2P_EV_COUNT(%rbx), %r12
    mov     LIBP2P_EV_CONN(%rbx), %rdi
    call    libp2p_conn
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
1:  test    %r12, %r12
    jz      9f
    movl    C_PHASE(%rbx), %eax
    cmp     $PH_SECURITY, %eax
    jb      9f
    cmp     $PH_OPEN, %eax
    ja      9f
    mov     C_RX_LEN(%rbx), %rcx
    mov     $LIBP2P_RX_SIZE, %eax
    sub     %rcx, %rax
    jz      8f                              /* full, and nothing could be taken */
    mov     %r12, %r13
    cmp     %rax, %r13
    cmovae  %rax, %r13
    mov     C_RX(%rbx), %rdi
    add     %r15, %rdi
    add     %rcx, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    libp2p_copy
    add     %r13, C_RX_LEN(%rbx)
    add     %r13, %rbp
    sub     %r13, %r12
    mov     %rbx, %rdi
    call    libp2p_conn_process
    jmp     1b
8:  mov     %rbx, %rdi
    mov     $LIBP2P_REASON_CLOSED, %esi
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_on_received

/* libp2p_conn_live(conn) -> 1 while the connection is in an upgrade phase or open, else 0. A leaf. */
LOCAL_FUNCTION libp2p_conn_live
    UNWIND_END_PROLOGUE
    movl    C_PHASE(%rdi), %ecx
    xor     %eax, %eax
    cmp     $PH_SECURITY, %ecx
    jb      1f
    cmp     $PH_OPEN, %ecx
    ja      1f
    mov     $1, %eax
1:  ret
END_FUNCTION libp2p_conn_live

/*
 * libp2p_conn_process(conn): handles what the receive buffer holds: multistream
 * messages before Noise, Noise handshake messages, then transport messages,
 * whose plaintext goes on to the muxer. Moves what is left to the front.
 * rbx conn, rbp position, r12 the buffer, r13 bytes in it; rax bytes
 * available and rcx their start until the next call.
 */
LOCAL_FUNCTION libp2p_conn_process
    ENTER   0
    mov     %rdi, %rbx
    xor     %ebp, %ebp
1:  mov     %rbx, %rdi
    call    libp2p_conn_live
    test    %rax, %rax
    jz      99f
    mov     C_RX(%rbx), %r12
    add     %r15, %r12
    mov     C_RX_LEN(%rbx), %r13
    mov     %r13, %rax
    sub     %rbp, %rax                      /* bytes available */
    lea     (%r12,%rbp), %rcx               /* their start */
    cmpl    $PH_SECURITY, C_PHASE(%rbx)
    jne     2f
    test    %rax, %rax
    jz      80f
    lea     C_MS_STATE(%rbx), %rdi
    mov     $C_MS_CAP, %esi
    mov     %rcx, %rdx
    mov     %rax, %rcx
    call    libp2p_ms_take
    add     %rax, %rbp
    cmp     $2, %rdx
    je      90f
    test    %rdx, %rdx
    jz      80f
    mov     %rbx, %rdi
    call    libp2p_conn_ms
    jmp     1b
2:  cmp     $2, %rax                        /* a Noise message: 2-byte length first */
    jb      80f
    movzbl  (%rcx), %edx
    shl     $8, %edx
    movzbl  1(%rcx), %r8d
    or      %r8d, %edx
    lea     2(%rdx), %r8
    cmp     %r8, %rax
    jb      80f
    add     %r8, %rbp
    cmpl    $PH_NOISE, C_PHASE(%rbx)
    jne     3f
    mov     %rbx, %rdi
    lea     2(%rcx), %rsi
    call    libp2p_noise_message
    cmp     $2, %rax
    je      91f
    test    %rax, %rax
    jnz     90f
    cmpq    $2, C_NS_STEP(%rbx)
    jne     1b
    movl    $PH_MUXER, C_PHASE(%rbx)        /* the transport keys are ready */
    movq    $0, C_MS_LEN(%rbx)
    mov     C_FLAGS(%rbx), %rax
    and     $~(CF_SENT_HEADER | CF_GOT_HEADER), %rax
    mov     %rax, C_FLAGS(%rbx)
    test    $CF_OUTBOUND, %rax
    jz      1b
    mov     %rbx, %rdi
    call    libp2p_conn_propose_muxer
    jmp     1b
3:  mov     %rbx, %rdi
    lea     2(%rcx), %rsi
    call    libp2p_noise_open
    test    %rax, %rax
    jnz     90f
    mov     %rbx, %rdi
    lea     (SC_PLAIN + LIBP2P_BL_FIXED)(%r14), %rsi
    mov     (SC_PLAIN + LIBP2P_BL_COUNT)(%r14), %rdx
    call    libp2p_conn_plain
    jmp     1b
80: mov     %rbx, %rdi                      /* keep the rest at the front */
    call    libp2p_conn_live
    test    %rax, %rax
    jz      99f
    mov     C_RX(%rbx), %rdi
    add     %r15, %rdi
    mov     C_RX_LEN(%rbx), %rdx
    lea     (%rdi,%rbp), %rsi
    sub     %rbp, %rdx
    mov     %rdx, C_RX_LEN(%rbx)
    call    libp2p_copy
    jmp     99f
90: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_HANDSHAKE, %esi
    mov     $LIBP2P_REASON_CLOSED, %ecx
    cmpl    $PH_OPEN, C_PHASE(%rbx)
    cmove   %rcx, %rsi
    jmp     92f
91: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PEER_ID, %esi
92: call    libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_conn_process

/*
 * libp2p_conn_plain(conn, p, n): plaintext of a transport message: multistream
 * messages for the muxer first, then muxer frames.
 */
LOCAL_FUNCTION libp2p_conn_plain
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
1:  test    %r12, %r12
    jz      9f
    movl    C_PHASE(%rbx), %eax
    cmp     $PH_MUXER, %eax
    jne     2f
    lea     C_MS_STATE(%rbx), %rdi
    mov     $C_MS_CAP, %esi
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
    call    libp2p_conn_ms
    jmp     1b
2:  cmp     $PH_OPEN, %eax
    jne     9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    libp2p_mux_feed
    add     %rax, %rbp
    sub     %rax, %r12
    jmp     1b
8:  mov     %rbx, %rdi
    mov     $LIBP2P_REASON_HANDSHAKE, %esi
    call    libp2p_conn_close
9:  LEAVE   0
END_FUNCTION libp2p_conn_plain

/* libp2p_conn_propose_muxer(conn): the dialer's multistream header and first muxer: yamux when it is on, else mplex. */
LOCAL_FUNCTION libp2p_conn_propose_muxer
    ENTER   0
    mov     %rdi, %rbx
    mov     C_FLAGS(%rbx), %rax
    or      $CF_SENT_HEADER, %rax
    testq   $1, (ST_CONFIG + LIBP2P_CFG_MUXERS)(%r15)
    jnz     1f
    or      $CF_MPLEX_TRIED, %rax
1:  mov     %rax, C_FLAGS(%rbx)
    mov     %rbx, %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_conn_out
    lea     433b(%rip), %rsi
    lea     434b(%rip), %rcx
    testq   $CF_MPLEX_TRIED, C_FLAGS(%rbx)
    cmovnz  %rcx, %rsi
    mov     %rbx, %rdi
    mov     $13, %edx
    call    libp2p_conn_out
    LEAVE   0
END_FUNCTION libp2p_conn_propose_muxer

/*
 * libp2p_conn_ms(conn): one multistream message of the connection, before Noise
 * (for /noise) or after it (for the muxer). The header comes first; then
 * the listener answers proposals and the dialer reads answers.
 * rbx conn, rbp flags, r12 phase, r13 the muxers of the config, X23 the
 * muxer chosen.
 */
LOCAL_FUNCTION libp2p_conn_ms
    ENTER   0
    mov     %rdi, %rbx
    mov     C_FLAGS(%rbx), %rbp
    movl    C_PHASE(%rbx), %r12d
    test    $CF_GOT_HEADER, %rbp
    jnz     2f
    lea     C_MS_STATE(%rbx), %rdi          /* the header */
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      80f
    or      $CF_GOT_HEADER, %rbp
    mov     %rbp, C_FLAGS(%rbx)
    test    $CF_SENT_HEADER, %rbp
    jnz     70f
    or      $CF_SENT_HEADER, %rbp
    mov     %rbp, C_FLAGS(%rbx)
    mov     %rbx, %rdi
    lea     430b(%rip), %rsi
    mov     $MS_HEADER_LEN, %edx
    call    libp2p_conn_out
    jmp     70f
2:  test    $CF_OUTBOUND, %rbp
    jnz     40f
    cmp     $PH_SECURITY, %r12d             /* listener */
    jne     20f
    lea     C_MS_STATE(%rbx), %rdi
    lea     432b(%rip), %rsi
    mov     $7, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      60f
    mov     %rbx, %rdi
    lea     432b(%rip), %rsi
    mov     $7, %edx
    call    libp2p_conn_out
    jmp     30f
20: mov     (ST_CONFIG + LIBP2P_CFG_MUXERS)(%r15), %r13
    test    $1, %r13
    jz      21f
    lea     C_MS_STATE(%rbx), %rdi
    lea     433b(%rip), %rsi
    mov     $13, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      21f
    or      $CF_YAMUX, %rbp
    lea     433b(%rip), %rax
    mov     %rax, X23(%rsp)
    jmp     22f
21: test    $2, %r13
    jz      60f
    lea     C_MS_STATE(%rbx), %rdi
    lea     434b(%rip), %rsi
    mov     $13, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      60f
    or      $CF_MPLEX, %rbp
    lea     434b(%rip), %rax
    mov     %rax, X23(%rsp)
22: mov     %rbp, C_FLAGS(%rbx)
    mov     %rbx, %rdi
    mov     X23(%rsp), %rsi
    mov     $13, %edx
    call    libp2p_conn_out
    movq    $0, C_MS_LEN(%rbx)
    mov     %rbx, %rdi
    call    libp2p_conn_opened
    jmp     99f
30: movq    $0, C_MS_LEN(%rbx)              /* /noise selected */
    movl    $PH_NOISE, C_PHASE(%rbx)
    mov     %rbx, %rdi
    call    libp2p_noise_begin
    jmp     99f
40: cmp     $PH_SECURITY, %r12d             /* dialer */
    jne     41f
    lea     C_MS_STATE(%rbx), %rdi
    lea     432b(%rip), %rsi
    mov     $7, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      80f
    jmp     30b
41: lea     433b(%rip), %rsi
    lea     434b(%rip), %rax
    test    $CF_MPLEX_TRIED, %rbp
    cmovnz  %rax, %rsi
    lea     C_MS_STATE(%rbx), %rdi
    mov     $13, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      42f
    mov     $CF_YAMUX, %eax
    mov     $CF_MPLEX, %ecx
    test    $CF_MPLEX_TRIED, %rbp
    cmovnz  %rcx, %rax
    or      %rax, %rbp
    mov     %rbp, C_FLAGS(%rbx)
    movq    $0, C_MS_LEN(%rbx)
    mov     %rbx, %rdi
    call    libp2p_conn_opened
    jmp     99f
42: lea     C_MS_STATE(%rbx), %rdi          /* na: mplex next, when yamux was refused and mplex is on */
    lea     431b(%rip), %rsi
    mov     $3, %edx
    call    libp2p_ms_is
    test    %rax, %rax
    jz      80f
    test    $CF_MPLEX_TRIED, %rbp
    jnz     80f
    testq   $2, (ST_CONFIG + LIBP2P_CFG_MUXERS)(%r15)
    jz      80f
    or      $CF_MPLEX_TRIED, %rbp
    mov     %rbp, C_FLAGS(%rbx)
    mov     %rbx, %rdi
    lea     434b(%rip), %rsi
    mov     $13, %edx
    call    libp2p_conn_out
    jmp     70f
60: mov     %rbx, %rdi                      /* not supported */
    lea     431b(%rip), %rsi
    mov     $3, %edx
    call    libp2p_conn_out
70: movq    $0, C_MS_LEN(%rbx)
    jmp     99f
80: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_HANDSHAKE, %esi
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
    mov     %rdi, %rbx
    movl    $PH_OPEN, C_PHASE(%rbx)
    mov     C_FLAGS(%rbx), %rax
    xor     %ecx, %ecx
    test    $CF_YAMUX, %rax
    jz      1f
    mov     $2, %ecx
    mov     $1, %edx
    test    $CF_OUTBOUND, %rax
    cmovnz  %rdx, %rcx
1:  mov     %rcx, C_MX_NEXT_ID(%rbx)
    movq    $0, C_MX_HLEN(%rbx)
    movq    $0, C_MX_REMAIN(%rbx)
    mov     %rbx, %rdi
    call    libp2p_peer_bind
    LEAVE   0
END_FUNCTION libp2p_conn_opened

/* libp2p_peer_find(id, n) -> the peer slot (connected or retained) with the peer ID, or 0. */
LOCAL_FUNCTION libp2p_peer_find
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    TABLE   %r12, ST_PEER_OFF
    mov     ST_PEER_COUNT(%r15), %r13
1:  test    %r13, %r13
    jz      8f
    cmpl    $0, P_STATE(%r12)
    je      2f
    lea     P_ID(%r12), %rdi
    mov     P_ID_LEN(%r12), %rsi
    mov     %rbx, %rdx
    mov     %rbp, %rcx
    call    libp2p_compare
    test    %rax, %rax
    jz      2f
    mov     %r12, %rax
    jmp     9f
2:  add     $P_SIZE, %r12
    dec     %r13
    jmp     1b
8:  xor     %eax, %eax
9:  LEAVE   0
END_FUNCTION libp2p_peer_find

/* libp2p_id_less(a, alen, b, blen) -> 1 when byte string a sorts before b, else 0. A leaf. */
LOCAL_FUNCTION libp2p_id_less
    UNWIND_END_PROLOGUE
    mov     %rsi, %r8
    cmp     %rcx, %r8
    cmova   %rcx, %r8
1:  test    %r8, %r8
    jz      2f
    movzbl  (%rdi), %eax
    movzbl  (%rdx), %r9d
    inc     %rdi
    inc     %rdx
    cmp     %r9d, %eax
    jb      7f
    ja      8f
    dec     %r8
    jmp     1b
2:  cmp     %rcx, %rsi
    jb      7f
8:  xor     %eax, %eax
    ret
7:  mov     $1, %eax
    ret
END_FUNCTION libp2p_id_less

/* libp2p_peer_conns(peer) -> the open connections bound to the peer. A leaf. */
LOCAL_FUNCTION libp2p_peer_conns
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     %rax, %r8
    mov     ST_CONN_OFF(%r15), %rdx
    add     %r15, %rdx
    mov     ST_CONN_COUNT(%r15), %rcx
    xor     %eax, %eax
1:  test    %rcx, %rcx
    jz      9f
    cmpl    $PH_OPEN, C_PHASE(%rdx)
    jne     2f
    cmp     C_PEER(%rdx), %r8
    jne     2f
    inc     %rax
2:  add     $C_SIZE, %rdx
    dec     %rcx
    jmp     1b
9:  ret
END_FUNCTION libp2p_peer_conns

/* libp2p_peer_other(peer index, conn) -> another open connection bound to the peer, or 0. A leaf. */
LOCAL_FUNCTION libp2p_peer_other
    UNWIND_END_PROLOGUE
    mov     ST_CONN_OFF(%r15), %rax
    add     %r15, %rax
    mov     ST_CONN_COUNT(%r15), %rcx
1:  test    %rcx, %rcx
    jz      8f
    cmp     %rsi, %rax
    je      2f
    cmpl    $PH_OPEN, C_PHASE(%rax)
    jne     2f
    cmp     C_PEER(%rax), %rdi
    jne     2f
    ret
2:  add     $C_SIZE, %rax
    dec     %rcx
    jmp     1b
8:  xor     %eax, %eax
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
 * rbx conn, rbp peer, r12 other conn, then the action, r13 peer index.
 */
LOCAL_FUNCTION libp2p_peer_bind
    ENTER   0
    mov     %rdi, %rbx
    mov     C_EXP_ID_LEN(%rbx), %rsi
    test    %rsi, %rsi
    jz      1f
    lea     C_EXP_ID(%rbx), %rdi
    lea     C_RID(%rbx), %rdx
    mov     C_RID_LEN(%rbx), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jz      81f
1:  lea     ST_PEER_ID(%r15), %rdi
    mov     ST_PEER_ID_LEN(%r15), %rsi
    lea     C_RID(%rbx), %rdx
    mov     C_RID_LEN(%rbx), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jnz     81f
    lea     C_RID(%rbx), %rdi
    mov     C_RID_LEN(%rbx), %rsi
    call    libp2p_peer_find
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      4f
    cmpl    $PS_CONNECTED, P_STATE(%rbp)
    jne     3f
    imul    $C_SIZE, P_CONN(%rbp), %r12     /* a second connection to the peer */
    add     ST_CONN_OFF(%r15), %r12
    add     %r15, %r12
    mov     C_FLAGS(%rbx), %rax
    xor     C_FLAGS(%r12), %rax
    test    $CF_OUTBOUND, %rax
    jz      84f                             /* same dialer */
    lea     ST_PEER_ID(%r15), %rdi          /* is our ID the smaller? */
    mov     ST_PEER_ID_LEN(%r15), %rsi
    lea     C_RID(%rbx), %rdx
    mov     C_RID_LEN(%rbx), %rcx
    call    libp2p_id_less
    mov     C_FLAGS(%rbx), %rcx
    and     $CF_OUTBOUND, %rcx              /* 1 when we dialled the new one */
    cmp     %rcx, %rax
    jne     82f                             /* the old one has the smaller dialer */
    mov     %rbp, %rax                      /* the new one stays: the old one ends, with any secondary connections */
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     %rax, %r13
85: mov     %r13, %rdi
    mov     %r12, %rsi
    call    libp2p_peer_other
    test    %rax, %rax
    jz      86f
    mov     %rax, %rdi
    mov     $LIBP2P_REASON_DUPLICATE, %esi
    call    libp2p_conn_close
    jmp     85b
86: mov     %r12, %rdi
    mov     $LIBP2P_REASON_DUPLICATE, %esi
    call    libp2p_conn_close
    lea     C_RID(%rbx), %rdi
    mov     C_RID_LEN(%rbx), %rsi
    call    libp2p_peer_find
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      4f
3:  incl    P_GEN(%rbp)                     /* a retained peer comes back */
    movl    $PS_CONNECTED, P_STATE(%rbp)
    jmp     5f
4:  mov     $ST_PEER_OFF, %edi
    mov     $ST_PEER_COUNT, %esi
    mov     $P_SIZE, %edx
    call    libp2p_alloc_slot
    mov     %rax, %rbp
    test    %rbp, %rbp
    jnz     41f
    call    libp2p_peer_evict
    test    %rax, %rax
    jz      83f
    mov     $ST_PEER_OFF, %edi
    mov     $ST_PEER_COUNT, %esi
    mov     $P_SIZE, %edx
    call    libp2p_alloc_slot
    mov     %rax, %rbp
    test    %rbp, %rbp
    jz      83f
41: lea     P_ID(%rbp), %rdi
    lea     C_RID(%rbx), %rsi
    mov     C_RID_LEN(%rbx), %rdx
    mov     %rdx, P_ID_LEN(%rbp)
    call    libp2p_copy
5:  mov     %rbx, %rax                      /* fill in the peer */
    sub     ST_CONN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $C_SIZE, %ecx
    div     %rcx
    mov     %rax, P_CONN(%rbp)
    mov     C_FLAGS(%rbx), %rax
    and     $CF_OUTBOUND, %rax
    mov     %rax, P_FLAGS(%rbp)
    movq    $NONE, P_GS_OUT(%rbp)
    movq    $NONE, P_GS_IN(%rbp)
    lea     P_IP(%rbp), %rdi
    lea     (C_ADDR + LIBP2P_ADDR_IP)(%rbx), %rsi
    mov     $16, %edx
    call    libp2p_copy
    mov     (C_ADDR + LIBP2P_ADDR_FAMILY)(%rbx), %rax
    mov     %rax, P_IP_FAMILY(%rbp)
    mov     %rbp, %rax
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     %rax, C_PEER(%rbx)
    orq     $CF_REPORTED, C_FLAGS(%rbx)
    mov     $LIBP2P_ACTION_PEER_CONNECTED, %edi
    mov     $LIBP2P_ACT_PC_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      6f
    mov     %rax, %r12
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    mov     %rbp, %rdx
    call    libp2p_handle
    mov     %rax, LIBP2P_ACT_PEER(%r12)
    mov     C_TAG(%rbx), %rax
    mov     %rax, LIBP2P_ACT_PC_TAG(%r12)
    mov     C_FLAGS(%rbx), %rax
    and     $CF_OUTBOUND, %rax
    mov     %rax, LIBP2P_ACT_PC_DIRECTION(%r12)
    lea     LIBP2P_ACT_PC_ADDR(%r12), %rdi
    lea     C_ADDR(%rbx), %rsi
    mov     $LIBP2P_ADDR_SIZE, %edx
    call    libp2p_copy
    mov     P_ID_LEN(%rbp), %rdx
    mov     %rdx, LIBP2P_ACT_PC_ID_LEN(%r12)
    lea     LIBP2P_ACT_PC_ID(%r12), %rdi
    lea     P_ID(%rbp), %rsi
    call    libp2p_copy
6:  mov     %rbp, %rdi
    call    libp2p_gossip_peer_up
    jmp     99f
84: testq   $CF_OUTBOUND, C_FLAGS(%rbx)     /* we dialled the peer again: the new one ends */
    jnz     82f
    mov     %rbp, %rdi                      /* the peer dialled us again: a secondary connection */
    call    libp2p_peer_conns
    cmp     $LIBP2P_PEER_CONNS, %rax
    jae     82f
    mov     %rbp, %rax
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     %rax, C_PEER(%rbx)
    orq     $CF_REPORTED, C_FLAGS(%rbx)
    jmp     99f
81: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PEER_ID, %esi
    call    libp2p_conn_close
    jmp     99f
82: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_DUPLICATE, %esi
    call    libp2p_conn_close
    jmp     99f
83: mov     %rbx, %rdi
    mov     $LIBP2P_REASON_LIMIT, %esi
    call    libp2p_conn_close
99: LEAVE   0
END_FUNCTION libp2p_peer_bind

/*
 * libp2p_peer_evict() -> 1 when it freed the retained peer whose score ends
 * first, 0 when no peer is retained.
 * rbx peer, rbp peers left, r12 the one found, r13 its expiry.
 */
LOCAL_FUNCTION libp2p_peer_evict
    ENTER   0
    TABLE   %rbx, ST_PEER_OFF
    mov     ST_PEER_COUNT(%r15), %rbp
    xor     %r12d, %r12d
    mov     $NONE, %r13
1:  test    %rbp, %rbp
    jz      2f
    cmpl    $PS_RETAINED, P_STATE(%rbx)
    jne     11f
    mov     P_EXPIRE(%rbx), %rax
    cmp     %r13, %rax
    jae     11f
    mov     %rax, %r13
    mov     %rbx, %r12
11: add     $P_SIZE, %rbx
    dec     %rbp
    jmp     1b
2:  xor     %eax, %eax
    test    %r12, %r12
    jz      9f
    mov     %r12, %rdi
    call    libp2p_peer_release
    mov     $1, %eax
9:  LEAVE   0
END_FUNCTION libp2p_peer_evict

/* libp2p_peer_release(peer): the slot becomes free, and so do its peer x topic entries. */
LOCAL_FUNCTION libp2p_peer_release
    ENTER   0
    mov     %rdi, %rbx
    movl    $0, P_STATE(%rbx)
    mov     %rbx, %rax
    sub     ST_PEER_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $P_SIZE, %ecx
    div     %rcx
    mov     ST_TOPIC_COUNT(%r15), %rcx
    imul    %rcx, %rax
    imul    $PT_SIZE, %rax, %rax
    mov     ST_PT_OFF(%r15), %rdi
    add     %r15, %rdi
    add     %rax, %rdi
    imul    $PT_SIZE, %rcx, %rsi
    call    libp2p_zero
    LEAVE   0
END_FUNCTION libp2p_peer_release

/*
 * libp2p_peer_down(peer): its connection ended: gossipsub forgets it,
 * PEER_DISCONNECTED, then the slot is retained for its score, or freed.
 */
LOCAL_FUNCTION libp2p_peer_down
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_gossip_peer_down
    mov     $LIBP2P_ACTION_PEER_DISCONNECTED, %edi
    mov     $LIBP2P_ACT_PD_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      1f
    mov     %rax, %rbp
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    mov     %rbx, %rdx
    call    libp2p_handle
    mov     %rax, LIBP2P_ACT_PEER(%rbp)
    mov     P_ID_LEN(%rbx), %rdx
    mov     %rdx, LIBP2P_ACT_PD_ID_LEN(%rbp)
    lea     LIBP2P_ACT_PD_ID(%rbp), %rdi
    lea     P_ID(%rbx), %rsi
    call    libp2p_copy
1:  movq    $NONE, P_CONN(%rbx)
    movq    $NONE, P_GS_OUT(%rbx)
    movq    $NONE, P_GS_IN(%rbx)
    mov     (ST_CONFIG + LIBP2P_CFG_SCORING)(%r15), %rax
    mov     (ST_CONFIG + LIBP2P_CFG_RETAIN_SCORE_MS)(%r15), %rcx
    test    %rax, %rax
    jz      2f
    test    %rcx, %rcx
    jz      2f
    add     SC_NOW(%r14), %rcx
    mov     %rcx, P_EXPIRE(%rbx)
    movl    $PS_RETAINED, P_STATE(%rbx)
    incl    P_GEN(%rbx)                     /* old handles no longer work */
    jmp     9f
2:  mov     %rbx, %rdi
    call    libp2p_peer_release
9:  LEAVE   0
END_FUNCTION libp2p_peer_down

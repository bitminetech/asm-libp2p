/*
 * gossipsub input of the x86-64 core: the RPC reader of a peer's stream,
 * subscriptions, messages, control messages, the gossipsub events of the
 * application, and peers coming and going. Included by gossip.s.
 *
 * Score comparisons follow the ARM64 conditions, unordered results
 * included: "fcmp a, b; b.mi" (a < b) is "ucomisd a, b; ja" (b > a).
 */

/* ---------------------------------------------------------------- Peers */

/* libp2p_gossip_peer_up(peer): a peer connected: open our gossipsub stream to it. */
LOCAL_FUNCTION libp2p_gossip_peer_up
    ENTER   0
    mov     %rdi, %rbx
    imul    $C_SIZE, P_CONN(%rbx), %rdi
    add     ST_CONN_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     $SK_GOSSIP_OUT, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     $1, %r8d
    call    libp2p_stream_open
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_stream_index
    mov     %rax, P_GS_OUT(%rbx)
9:  LEAVE   0
END_FUNCTION libp2p_gossip_peer_up

/*
 * libp2p_gossip_peer_down(peer): a peer left: out of every mesh (with the mesh
 * failure penalty), fanout and topic; its promises are forgotten. Its
 * score counters and backoffs stay for a retained score.
 * rbx peer, rbp peer index, r12 topic index, r13 topics, X23 topic, X24 entry.
 */
LOCAL_FUNCTION libp2p_gossip_peer_down
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_peer_idx
    mov     %rax, %rbp
    mov     %rax, %rdi
    call    libp2p_promise_drop_peer
    xor     %r12d, %r12d
    mov     ST_TOPIC_COUNT(%r15), %r13
1:  cmp     %r13, %r12
    jae     9f
    mov     %r12, %rdi
    call    libp2p_topic_at
    mov     %rax, X23(%rsp)
    cmpq    $0, T_USED(%rax)
    je      3f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pt
    mov     %rax, X24(%rsp)
    testq   $PTF_MESH, PT_FLAGS(%rax)
    jz      2f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_mesh_remove
2:  mov     X24(%rsp), %rax
    mov     PT_FLAGS(%rax), %rcx
    mov     X23(%rsp), %rdx
    test    $PTF_SUBSCRIBED, %rcx
    jz      21f
    decq    T_PEERS(%rdx)
21: test    $PTF_FANOUT, %rcx
    jz      22f
    decq    T_FANOUT(%rdx)
22: movq    $0, PT_FLAGS(%rax)
    mov     %rdx, %rdi
    call    libp2p_topic_tidy
3:  inc     %r12
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_gossip_peer_down

/* libp2p_gossip_out_ready(stream): our gossipsub stream to a peer is open: it learns our subscriptions. */
LOCAL_FUNCTION libp2p_gossip_out_ready
    ENTER   0
    mov     S_PEER(%rdi), %rdi
    call    libp2p_peer_at
    mov     %rax, %rbx
    orq     $(PF_GOSSIP | PF_HELLO), P_FLAGS(%rbx)
    TABLE   %rbp, ST_TOPIC_OFF
    mov     ST_TOPIC_COUNT(%r15), %r12
1:  test    %r12, %r12
    jz      9f
    cmpq    $0, T_USED(%rbp)
    je      2f
    testq   $TF_SUBSCRIBED, T_FLAGS(%rbp)
    jz      2f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     $1, %edx
    call    libp2p_gs_send_sub
2:  add     $T_SIZE, %rbp
    dec     %r12
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_gossip_out_ready

/* libp2p_gossip_in_ready(stream): the peer opened its gossipsub stream to us. */
LOCAL_FUNCTION libp2p_gossip_in_ready
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_stream_index
    mov     %rax, %rbp
    mov     S_PEER(%rbx), %rdi
    call    libp2p_peer_at
    mov     %rbp, P_GS_IN(%rax)
    LEAVE   0
END_FUNCTION libp2p_gossip_in_ready

/* ---------------------------------------------------------------- RPC reader */

/*
 * libp2p_gossip_rx(stream, p, n): bytes of a peer's gossipsub stream: each RPC
 * is a varint length, then that many bytes, read into one heap block and
 * handled whole. An RPC above max_rpc resets the stream; one the heap
 * cannot hold is skipped.
 * rbx stream, rbp p, r12 bytes left, r13 the RPC length, X23 bytes got,
 * X24 bytes taken now, X25 the buffer.
 */
LOCAL_FUNCTION libp2p_gossip_rx
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
1:  test    %r12, %r12
    jz      9f
    cmpl    $0, S_USED(%rbx)
    je      9f
    mov     S_RPC_LEN(%rbx), %r13
    test    %r13, %r13
    jnz     3f
    movzbl  (%rbp), %eax                    /* the length prefix */
    inc     %rbp
    dec     %r12
    mov     S_RPC_VARINT(%rbx), %rdx
    mov     S_RPC_SHIFT(%rbx), %rcx
    cmp     $35, %rcx
    ja      8f
    mov     %rax, %r8
    and     $0x7F, %r8
    shl     %cl, %r8
    or      %r8, %rdx
    add     $7, %rcx
    mov     %rdx, S_RPC_VARINT(%rbx)
    mov     %rcx, S_RPC_SHIFT(%rbx)
    test    $0x80, %eax
    jnz     1b
    movq    $0, S_RPC_VARINT(%rbx)
    movq    $0, S_RPC_SHIFT(%rbx)
    test    %rdx, %rdx
    jz      1b                              /* an empty RPC */
    cmp     (ST_CONFIG + LIBP2P_CFG_MAX_RPC)(%r15), %rdx
    ja      8f
    mov     %rdx, S_RPC_LEN(%rbx)
    movq    $0, S_RPC_GOT(%rbx)
    mov     %rdx, %rdi
    call    libp2p_heap_alloc
    mov     %rax, S_RPC_BUF(%rbx)           /* 0: the bytes are skipped */
    jmp     1b
3:  mov     S_RPC_GOT(%rbx), %rax           /* the body */
    mov     %rax, X23(%rsp)
    mov     %r13, %rcx
    sub     %rax, %rcx
    mov     %r12, %rdx
    cmp     %rcx, %rdx
    cmova   %rcx, %rdx
    mov     %rdx, X24(%rsp)
    mov     S_RPC_BUF(%rbx), %rcx
    mov     %rcx, X25(%rsp)
    test    %rcx, %rcx
    jz      4f
    lea     (%r15,%rcx), %rdi
    add     %rax, %rdi
    mov     %rbp, %rsi
    call    libp2p_copy
4:  mov     X24(%rsp), %rax
    add     %rax, %rbp
    sub     %rax, %r12
    add     X23(%rsp), %rax
    mov     %rax, S_RPC_GOT(%rbx)
    cmp     %r13, %rax
    jb      1b
    movq    $0, S_RPC_LEN(%rbx)
    movq    $0, S_RPC_GOT(%rbx)
    movq    $0, S_RPC_BUF(%rbx)
    cmpq    $0, X25(%rsp)
    je      1b
    mov     S_PEER(%rbx), %rdi
    mov     X25(%rsp), %rsi
    add     %r15, %rsi
    mov     %r13, %rdx
    call    libp2p_rpc_handle
    mov     X25(%rsp), %rdi
    call    libp2p_heap_free
    jmp     1b
8:  mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PROTOCOL, %esi
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_gossip_rx

/*
 * libp2p_rpc_handle(peer index, p, n): one whole RPC of a peer: subscriptions,
 * published messages and control, in their order. A graylisted peer is not
 * heard; a field that is not well formed ends the RPC.
 * rbx peer index, rbp p, r12 end, r13 peer.
 */
LOCAL_FUNCTION libp2p_rpc_handle
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    call    libp2p_peer_at
    mov     %rax, %r13
    cmpl    $PS_CONNECTED, P_STATE(%r13)
    jne     9f
    mov     %r13, %rdi
    call    libp2p_score
    movsd   (ST_CONFIG + LIBP2P_CFG_GRAYLIST_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm0, %xmm1
    ja      9f
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     9f
    mov     %r8, %rbp
    cmp     $2, %rcx
    jne     1b
    mov     %rdx, %r9
    mov     %rdi, %rdx
    mov     %rbx, %rdi
    cmp     $1, %r9
    jne     2f
    call    libp2p_rpc_sub
    jmp     1b
2:  cmp     $2, %r9
    jne     3f
    call    libp2p_rpc_msg
    jmp     1b
3:  cmp     $3, %r9
    jne     1b
    call    libp2p_rpc_control
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_handle

/*
 * libp2p_field_bytes(p, end, field) -> rax the start and rdx the length of the
 * first type 2 field with the number, or rax = 0.
 */
LOCAL_FUNCTION libp2p_field_bytes
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
1:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     8f
    mov     %r8, %rbx
    cmp     %r12, %rdx
    jne     1b
    cmp     $2, %rcx
    jne     1b
    mov     %rsi, %rax
    mov     %rdi, %rdx
    jmp     9f
8:  xor     %eax, %eax
    xor     %edx, %edx
9:  LEAVE   0
END_FUNCTION libp2p_field_bytes

/* libp2p_peer_topic(peer index, topic, subscribed): PEER_TOPIC for the application. */
LOCAL_FUNCTION libp2p_peer_topic
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     T_LEN(%rbp), %rsi
    add     $(LIBP2P_ACT_PT_TOPIC + 7), %rsi
    and     $-8, %rsi
    mov     $LIBP2P_ACTION_PEER_TOPIC, %edi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, %rdx
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    call    libp2p_handle
    mov     %rax, LIBP2P_ACT_PEER(%r13)
    mov     %r12, LIBP2P_ACT_PT_SUBSCRIBED(%r13)
    mov     T_LEN(%rbp), %rdx
    mov     %rdx, LIBP2P_ACT_PT_TOPIC_LEN(%r13)
    lea     LIBP2P_ACT_PT_TOPIC(%r13), %rdi
    lea     T_NAME(%rbp), %rsi
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_peer_topic

/*
 * libp2p_rpc_sub(peer index, p, n): one SubOpts: subscribe (field 1) and topicid
 * (field 2). The peer's subscription is noted, with PEER_TOPIC; leaving a
 * topic takes it out of our mesh and fanout of the topic.
 * rbx peer index, rbp p, r12 end, r13 subscribe, X23 topic name then the
 * entry, X24 length, X25 topic, X26 topic index.
 */
LOCAL_FUNCTION libp2p_rpc_sub
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    xor     %r13d, %r13d
    movq    $0, X23(%rsp)
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     2f
    mov     %r8, %rbp
    cmp     $1, %rdx
    jne     11f
    xor     %r13d, %r13d
    test    %rsi, %rsi
    setne   %r13b
    jmp     1b
11: cmp     $2, %rdx
    jne     1b
    cmp     $2, %rcx
    jne     1b
    mov     %rsi, X23(%rsp)
    mov     %rdi, X24(%rsp)
    jmp     1b
2:  cmp     $NONE, %rax
    je      9f
    mov     X23(%rsp), %rax
    test    %rax, %rax
    jz      9f
    mov     X24(%rsp), %rcx
    test    %rcx, %rcx
    jz      9f
    cmp     $LIBP2P_MAX_TOPIC, %rcx
    ja      9f
    test    %r13, %r13
    jz      5f
    mov     %rax, %rdi                      /* subscribe */
    mov     %rcx, %rsi
    call    libp2p_topic_get
    test    %rax, %rax
    jz      9f
    mov     %rax, X25(%rsp)
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rsi
    mov     %rbx, %rdi
    call    libp2p_pt
    mov     PT_FLAGS(%rax), %rcx
    test    $PTF_SUBSCRIBED, %rcx
    jnz     9f
    or      $PTF_SUBSCRIBED, %rcx
    mov     %rcx, PT_FLAGS(%rax)
    mov     X25(%rsp), %rax
    incq    T_PEERS(%rax)
    mov     %rbx, %rdi
    mov     %rax, %rsi
    mov     $1, %edx
    call    libp2p_peer_topic
    jmp     9f
5:  mov     %rax, %rdi                      /* unsubscribe */
    mov     %rcx, %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, X25(%rsp)
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, X26(%rsp)
    mov     %rax, %rsi
    mov     %rbx, %rdi
    call    libp2p_pt
    mov     %rax, X23(%rsp)
    mov     PT_FLAGS(%rax), %rcx
    test    $PTF_SUBSCRIBED, %rcx
    jz      9f
    test    $PTF_MESH, %rcx
    jz      6f
    mov     %rbx, %rdi
    mov     X26(%rsp), %rsi
    call    libp2p_mesh_remove
6:  mov     X23(%rsp), %rax
    mov     PT_FLAGS(%rax), %rcx
    test    $PTF_FANOUT, %rcx
    jz      7f
    mov     X25(%rsp), %rdx
    decq    T_FANOUT(%rdx)
7:  and     $~(PTF_SUBSCRIBED | PTF_FANOUT), %rcx
    mov     %rcx, PT_FLAGS(%rax)
    mov     X25(%rsp), %rax
    decq    T_PEERS(%rax)
    mov     %rbx, %rdi
    mov     %rax, %rsi
    xor     %edx, %edx
    call    libp2p_peer_topic
    mov     X25(%rsp), %rdi
    call    libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_rpc_sub

/*
 * libp2p_rpc_msg(peer index, p, n): one published Message. Only data (2) and
 * topic (4) may be there (StrictNoSign); from, seqno, signature or key, or
 * data above max_data, count as an invalid message of the peer. A message
 * of a topic we do not subscribe to is dropped. Otherwise it waits in a
 * pending slot, with MESSAGE, for its ID.
 * rbx peer index, rbp p then the topic, r12 end then the topic index,
 * r13 data, X23 data length, X24 topic name then the pending slot, X25 its
 * length then the action, X26 nonzero when a signing field is there.
 */
LOCAL_FUNCTION libp2p_rpc_msg
    ENTER   16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    xor     %r13d, %r13d
    movq    $0, X23(%rsp)
    movq    $0, X24(%rsp)
    movq    $0, X26(%rsp)
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     2f
    mov     %r8, %rbp
    cmp     $2, %rdx
    jne     11f
    mov     %rsi, %r13
    mov     %rdi, X23(%rsp)
    jmp     1b
11: cmp     $4, %rdx
    jne     12f
    mov     %rsi, X24(%rsp)
    mov     %rdi, X25(%rsp)
    jmp     1b
12: cmp     $6, %rdx
    ja      1b
    movq    $1, X26(%rsp)                   /* from, seqno, signature or key */
    jmp     1b
2:  cmp     $NONE, %rax
    je      9f
    mov     X24(%rsp), %rdi
    test    %rdi, %rdi
    jz      9f
    mov     X25(%rsp), %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    testq   $TF_SUBSCRIBED, T_FLAGS(%rax)
    jz      9f
    mov     %rax, %rbp
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %r12
    mov     X23(%rsp), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_MAX_DATA)(%r15), %rax
    jbe     21f
    movq    $1, X26(%rsp)
21: cmpq    $0, X26(%rsp)
    je      3f
    mov     %rbx, %rdi                      /* invalid */
    mov     %r12, %rsi
    call    libp2p_score_invalid
    jmp     9f
3:  mov     $ST_PEND_OFF, %edi
    mov     $ST_PEND_COUNT, %esi
    mov     $PD_SIZE, %edx
    call    libp2p_alloc_slot
    test    %rax, %rax
    jz      9f
    mov     %rax, X24(%rsp)
    mov     X23(%rsp), %rdi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jz      8f
    mov     X24(%rsp), %rcx
    mov     %rax, PD_DATA(%rcx)
    lea     (%r15,%rax), %rdi
    mov     %r13, %rsi
    mov     X23(%rsp), %rdx
    call    libp2p_copy
    mov     X24(%rsp), %rax
    mov     %rbx, PD_PEER(%rax)
    mov     %r12, PD_TOPIC(%rax)
    mov     X23(%rsp), %rcx
    mov     %rcx, PD_DATA_LEN(%rax)
    mov     SC_NOW(%r14), %rcx
    mov     %rcx, PD_TIME(%rax)
    movl    $PDS_WAIT_ID, PD_STATE(%rax)
    mov     T_LEN(%rbp), %rsi               /* MESSAGE */
    add     $(LIBP2P_ACT_MSG_TOPIC + 7), %rsi
    and     $-8, %rsi
    mov     $LIBP2P_ACTION_MESSAGE, %edi
    call    libp2p_action
    test    %rax, %rax
    jz      8f
    mov     %rax, X25(%rsp)
    mov     $ST_PEND_OFF, %edi
    mov     $PD_SIZE, %esi
    mov     X24(%rsp), %rdx
    call    libp2p_handle
    mov     X25(%rsp), %rcx
    mov     %rax, LIBP2P_ACT_HANDLE(%rcx)
    mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, %rdx
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    call    libp2p_handle
    mov     X25(%rsp), %rcx
    mov     %rax, LIBP2P_ACT_MSG_PEER(%rcx)
    mov     X24(%rsp), %rax
    mov     PD_DATA(%rax), %rdx
    mov     %rdx, LIBP2P_ACT_MSG_DATA_OFF(%rcx)
    mov     X23(%rsp), %rdx
    mov     %rdx, LIBP2P_ACT_MSG_DATA_LEN(%rcx)
    mov     T_LEN(%rbp), %rdx
    mov     %rdx, LIBP2P_ACT_MSG_TOPIC_LEN(%rcx)
    lea     LIBP2P_ACT_MSG_TOPIC(%rcx), %rdi
    lea     T_NAME(%rbp), %rsi
    call    libp2p_copy
    jmp     9f
8:  mov     X24(%rsp), %rdi
    call    libp2p_pend_free
9:  LEAVE   16
END_FUNCTION libp2p_rpc_msg

/* libp2p_rpc_control(peer index, p, n): a ControlMessage: ihave (1), iwant (2), graft (3), prune (4). */
LOCAL_FUNCTION libp2p_rpc_control
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     9f
    mov     %r8, %rbp
    cmp     $2, %rcx
    jne     1b
    mov     %rdx, %r9
    mov     %rdi, %rdx
    mov     %rbx, %rdi
    cmp     $1, %r9
    jne     2f
    call    libp2p_ctl_ihave
    jmp     1b
2:  cmp     $2, %r9
    jne     3f
    call    libp2p_ctl_iwant
    jmp     1b
3:  cmp     $3, %r9
    jne     4f
    call    libp2p_ctl_graft
    jmp     1b
4:  cmp     $4, %r9
    jne     1b
    call    libp2p_ctl_prune
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_control

/* libp2p_backoff_secs(ms) -> whole seconds, rounded up. A leaf. */
LOCAL_FUNCTION libp2p_backoff_secs
    UNWIND_END_PROLOGUE
    lea     999(%rdi), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    ret
END_FUNCTION libp2p_backoff_secs

/*
 * libp2p_prune_to(peer index, topic index, backoff ms): PRUNE to the peer with
 * the backoff, and no GRAFT of it before then.
 * rbx peer index, rbp topic index, r12 backoff, r13 seconds, X23 peer.
 */
LOCAL_FUNCTION libp2p_prune_to
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    call    libp2p_pt
    mov     SC_NOW(%r14), %rcx
    add     %r12, %rcx
    mov     PT_BACKOFF(%rax), %rdx
    cmp     %rcx, %rdx
    cmova   %rdx, %rcx
    mov     %rcx, PT_BACKOFF(%rax)
    mov     %r12, %rdi
    call    libp2p_backoff_secs
    mov     %rax, %r13
    mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, X23(%rsp)
    mov     %rbp, %rdi
    call    libp2p_topic_at
    mov     %rax, %rsi
    mov     X23(%rsp), %rdi
    mov     %r13, %rdx
    call    libp2p_gs_send_prune
    LEAVE   0
END_FUNCTION libp2p_prune_to

/*
 * libp2p_ctl_graft(peer index, p, n): a GRAFT. Ignored for a topic we do not
 * subscribe to or a peer already in the mesh. Within a backoff it costs a
 * behaviour penalty (two within graft_flood of the PRUNE) and gets PRUNE;
 * a negative score, or a full mesh and an inbound peer, also get PRUNE.
 * Otherwise the peer joins the mesh.
 * rbx peer index, rbp topic, r12 topic index, r13 entry, X23 now, X24 peer.
 */
LOCAL_FUNCTION libp2p_ctl_graft
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rdi
    lea     (%rsi,%rdx), %rsi
    mov     $1, %edx
    call    libp2p_field_bytes
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    mov     %rdx, %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    testq   $TF_SUBSCRIBED, T_FLAGS(%rbp)
    jz      9f
    mov     %rbp, %rdi
    call    libp2p_topic_idx
    mov     %rax, %r12
    mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_pt
    mov     %rax, %r13
    testq   $PTF_MESH, PT_FLAGS(%r13)
    jnz     9f
    mov     SC_NOW(%r14), %rax
    mov     %rax, X23(%rsp)
    cmp     PT_BACKOFF(%r13), %rax
    jae     2f
    mov     %rbx, %rdi                      /* within the backoff */
    call    libp2p_peer_at
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    mov     $1, %esi
    call    libp2p_behaviour_penalty
    mov     PT_BACKOFF(%r13), %rax
    sub     (ST_CONFIG + LIBP2P_CFG_PRUNE_BACKOFF_MS)(%r15), %rax
    add     (ST_CONFIG + LIBP2P_CFG_GRAFT_FLOOD_MS)(%r15), %rax
    cmp     %rax, X23(%rsp)
    jae     8f
    mov     X24(%rsp), %rdi
    mov     $1, %esi
    call    libp2p_behaviour_penalty
    jmp     8f
2:  mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    call    libp2p_score
    xorpd   %xmm1, %xmm1
    ucomisd %xmm0, %xmm1
    ja      8f
    mov     T_MESH(%rbp), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_D_HIGH)(%r15), %rax
    jb      3f
    mov     X24(%rsp), %rax
    testq   $PF_OUTBOUND, P_FLAGS(%rax)
    jz      8f
3:  mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_mesh_add
    jmp     9f
8:  mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     (ST_CONFIG + LIBP2P_CFG_PRUNE_BACKOFF_MS)(%r15), %rdx
    call    libp2p_prune_to
9:  LEAVE   0
END_FUNCTION libp2p_ctl_graft

/*
 * libp2p_ctl_prune(peer index, p, n): a PRUNE: the peer leaves our mesh of the
 * topic, and we do not GRAFT it again for its backoff (in seconds) or
 * prune_backoff. Exchanged peers are not used.
 * rbx peer index, rbp p then the entry, r12 end then the topic index,
 * r13 topic name, X23 its length, X24 backoff ms.
 */
LOCAL_FUNCTION libp2p_ctl_prune
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    xor     %r13d, %r13d
    mov     (ST_CONFIG + LIBP2P_CFG_PRUNE_BACKOFF_MS)(%r15), %rax
    mov     %rax, X24(%rsp)
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     2f
    mov     %r8, %rbp
    cmp     $1, %rdx
    jne     11f
    cmp     $2, %rcx
    jne     1b
    mov     %rsi, %r13
    mov     %rdi, X23(%rsp)
    jmp     1b
11: cmp     $3, %rdx
    jne     1b
    test    %rcx, %rcx
    jnz     1b
    mov     $86400, %eax                    /* at most a day */
    cmp     %rax, %rsi
    cmovae  %rax, %rsi
    imul    $1000, %rsi, %rsi
    mov     %rsi, X24(%rsp)
    jmp     1b
2:  test    %r13, %r13
    jz      9f
    mov     %r13, %rdi
    mov     X23(%rsp), %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %r12
    mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_pt
    mov     %rax, %rbp
    testq   $PTF_MESH, PT_FLAGS(%rbp)
    jz      3f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_mesh_remove
3:  mov     SC_NOW(%r14), %rcx
    add     X24(%rsp), %rcx
    mov     PT_BACKOFF(%rbp), %rdx
    cmp     %rcx, %rdx
    cmova   %rdx, %rcx
    mov     %rcx, PT_BACKOFF(%rbp)
9:  LEAVE   0
END_FUNCTION libp2p_ctl_prune

/*
 * libp2p_ctl_ihave(peer index, p, n): an IHAVE. Heard only from a peer at or
 * above gossip_threshold, at most max_ihave_messages times and
 * max_ihave_length IDs in a heartbeat, for a topic we subscribe to. The IDs
 * not seen go back as one IWANT, and one of them, at random, becomes a
 * promise.
 * rbx peer index, rbp p, r12 end, r13 peer, X23 list, X24 count, X25 room,
 * X26 topic; 32(%rsp) and 40(%rsp) an ID and its length.
 */
LOCAL_FUNCTION libp2p_ctl_ihave
    ENTER   16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    call    libp2p_peer_at
    mov     %rax, %r13
    mov     %rax, %rdi
    call    libp2p_score
    movsd   (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm0, %xmm1
    ja      9f
    mov     P_IHAVE_COUNT(%r13), %rax
    inc     %rax
    mov     %rax, P_IHAVE_COUNT(%r13)
    cmp     (ST_CONFIG + LIBP2P_CFG_MAX_IHAVE_MESSAGES)(%r15), %rax
    ja      9f
    mov     (ST_CONFIG + LIBP2P_CFG_MAX_IHAVE_LENGTH)(%r15), %rax
    sub     P_IHAVE_IDS(%r13), %rax
    jbe     9f
    mov     %rax, X25(%rsp)
    mov     %rbp, %rdi
    mov     %r12, %rsi
    mov     $1, %edx
    call    libp2p_field_bytes
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    mov     %rdx, %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, X26(%rsp)
    testq   $TF_SUBSCRIBED, T_FLAGS(%rax)
    jz      9f
    SCR     %rax, SC_IDS
    mov     %rax, X23(%rsp)
    movq    $0, X24(%rsp)
1:  mov     X24(%rsp), %rax
    cmp     X25(%rsp), %rax
    jae     3f
    cmp     $(SC_IDS_SIZE / 16), %rax
    jae     3f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     3f
    mov     %r8, %rbp
    cmp     $2, %rdx
    jne     1b
    cmp     $2, %rcx
    jne     1b
    test    %rdi, %rdi
    jz      1b
    cmp     $LIBP2P_MAX_MSG_ID, %rdi
    ja      1b
    mov     %rsi, 32(%rsp)
    mov     %rdi, 40(%rsp)
    mov     %rdi, %rax
    mov     %rsi, %rdi
    mov     %rax, %rsi
    call    libp2p_seen_find
    test    %rax, %rax
    jnz     1b
    mov     X24(%rsp), %rax
    shl     $4, %rax
    add     X23(%rsp), %rax
    mov     32(%rsp), %rcx
    mov     %rcx, (%rax)
    mov     40(%rsp), %rcx
    mov     %rcx, 8(%rax)
    incq    X24(%rsp)
    jmp     1b
3:  cmpq    $0, X24(%rsp)
    je      9f
    mov     X24(%rsp), %rax
    add     %rax, P_IHAVE_IDS(%r13)
    mov     %r13, %rdi
    mov     X26(%rsp), %rsi
    mov     X23(%rsp), %rdx
    mov     X24(%rsp), %rcx
    mov     $2, %r8d
    call    libp2p_gs_send_ids
    mov     X24(%rsp), %rdi
    call    libp2p_random_below
    shl     $4, %rax
    add     X23(%rsp), %rax
    mov     (%rax), %rsi
    mov     8(%rax), %rdx
    mov     %rbx, %rdi
    call    libp2p_promise_add
9:  LEAVE   16
END_FUNCTION libp2p_ctl_ihave

/*
 * libp2p_ctl_iwant(peer index, p, n): an IWANT from a peer at or above
 * gossip_threshold: each message still in the cache goes to it, at most
 * retransmission times.
 * rbx peer index, rbp p, r12 end, r13 peer, X23 entry.
 */
LOCAL_FUNCTION libp2p_ctl_iwant
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    call    libp2p_peer_at
    mov     %rax, %r13
    mov     %rax, %rdi
    call    libp2p_score
    movsd   (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm0, %xmm1
    ja      9f
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     9f
    mov     %r8, %rbp
    cmp     $1, %rdx
    jne     1b
    cmp     $2, %rcx
    jne     1b
    mov     %rdi, %rax
    mov     %rsi, %rdi
    mov     %rax, %rsi
    call    libp2p_mc_find
    test    %rax, %rax
    jz      1b
    mov     %rax, X23(%rsp)
    mov     %rax, %rdi
    mov     %rbx, %rsi
    call    libp2p_mc_sent
    test    %rax, %rax
    jz      1b
    mov     X23(%rsp), %rax
    mov     MC_TOPIC(%rax), %rdi
    call    libp2p_topic_at
    mov     %rax, %rsi
    mov     %r13, %rdi
    mov     X23(%rsp), %rax
    mov     MC_DATA(%rax), %rdx
    add     %r15, %rdx
    mov     MC_DATA_LEN(%rax), %rcx
    call    libp2p_gs_send_msg
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_ctl_iwant

/* ---------------------------------------------------------------- Mesh */

/* libp2p_mesh_add(peer index, topic index): the peer joins our mesh of the topic, with GRAFT. */
LOCAL_FUNCTION libp2p_mesh_add
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_pt
    orq     $PTF_MESH, PT_FLAGS(%rax)
    mov     SC_NOW(%r14), %rcx
    mov     %rcx, PT_GRAFT_TIME(%rax)
    mov     %rbp, %rdi
    call    libp2p_topic_at
    mov     %rax, %r12
    incq    T_MESH(%r12)
    mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     %r12, %rsi
    call    libp2p_gs_send_graft
    LEAVE   0
END_FUNCTION libp2p_mesh_add

/* libp2p_mesh_remove(peer index, topic index): the peer leaves our mesh of the topic, with the mesh failure penalty. */
LOCAL_FUNCTION libp2p_mesh_remove
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    libp2p_score_mesh_leave
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    andq    $~PTF_MESH, PT_FLAGS(%rax)
    mov     %rbp, %rdi
    call    libp2p_topic_at
    decq    T_MESH(%rax)
    LEAVE   0
END_FUNCTION libp2p_mesh_remove

/*
 * libp2p_candidates(topic index, need flags, refuse flags, floor) -> the count
 * of peers in the list at SC_LIST (u32 peer indexes): gossipsub peers
 * subscribed to the topic whose entry has every need flag and no refuse
 * flag, whose score is at or above floor (xmm0), and, when the backoff bit
 * of refuse is set, outside a backoff.
 * rbx topic index, rbp need, r12 refuse, r13 peer index, X23 count,
 * X24 list, X25 peer; 32(%rsp) the floor.
 */
.set CAND_BACKOFF, 0x100
.set CAND_OUTBOUND, 0x200               /* need: outbound peers only */
LOCAL_FUNCTION libp2p_candidates
    ENTER   16
    movsd   %xmm0, 32(%rsp)
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    or      $PTF_SUBSCRIBED, %rbp
    mov     %rdx, %r12
    xor     %r13d, %r13d
    movq    $0, X23(%rsp)
    SCR     %rax, SC_LIST
    mov     %rax, X24(%rsp)
1:  cmp     ST_PEER_COUNT(%r15), %r13
    jae     9f
    mov     %r13, %rdi
    call    libp2p_peer_at
    mov     %rax, X25(%rsp)
    mov     %rax, %rdi
    call    libp2p_gs_ready
    test    %rax, %rax
    jz      2f
    mov     X25(%rsp), %rax
    movsd   P_SCORE(%rax), %xmm0
    movsd   32(%rsp), %xmm1
    ucomisd %xmm0, %xmm1
    ja      2f
    test    $CAND_OUTBOUND, %rbp
    jz      11f
    testq   $PF_OUTBOUND, P_FLAGS(%rax)
    jz      2f
11: mov     %r13, %rdi
    mov     %rbx, %rsi
    call    libp2p_pt
    mov     PT_FLAGS(%rax), %rcx
    mov     %rbp, %rdx
    and     $0xFF, %rdx
    mov     %rcx, %r8
    and     %rdx, %r8
    cmp     %rdx, %r8
    jne     2f
    mov     %r12, %rdx
    and     $0xFF, %rdx
    test    %rdx, %rcx
    jnz     2f
    test    $CAND_BACKOFF, %r12
    jz      12f
    mov     SC_NOW(%r14), %rdx
    cmp     PT_BACKOFF(%rax), %rdx
    jb      2f
12: mov     X24(%rsp), %rax
    mov     X23(%rsp), %rcx
    movl    %r13d, (%rax,%rcx,4)
    incq    X23(%rsp)
2:  inc     %r13
    jmp     1b
9:  mov     X23(%rsp), %rax
    LEAVE   16
END_FUNCTION libp2p_candidates

/* libp2p_shuffle(list, count): a random order of the u32 values (Fisher-Yates). rbx list, rbp count. */
LOCAL_FUNCTION libp2p_shuffle
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
1:  cmp     $1, %rbp
    jbe     9f
    mov     %rbp, %rdi
    call    libp2p_random_below
    dec     %rbp
    movl    (%rbx,%rax,4), %ecx
    movl    (%rbx,%rbp,4), %edx
    movl    %edx, (%rbx,%rax,4)
    movl    %ecx, (%rbx,%rbp,4)
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_shuffle

/* ---------------------------------------------------------------- Application events */

/*
 * libp2p_on_subscribe(event): we join a topic: our fanout peers of it, then
 * other subscribed peers at random, fill the mesh up to D (score 0 or more,
 * outside backoff), each with GRAFT; every gossipsub peer hears of it.
 * rbx topic, rbp topic index, r12 mesh count, r13 list, X23 count, X24 i.
 */
LOCAL_FUNCTION libp2p_on_subscribe
    ENTER   0
    lea     LIBP2P_EV_TOPIC(%rdi), %rax
    mov     LIBP2P_EV_TOPIC_LEN(%rdi), %rsi
    mov     %rax, %rdi
    call    libp2p_topic_get
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    mov     T_FLAGS(%rbx), %rax
    test    $TF_SUBSCRIBED, %rax
    jnz     9f
    or      $TF_SUBSCRIBED, %rax
    mov     %rax, T_FLAGS(%rbx)
    mov     %rbx, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rbp
    call    libp2p_score_all
    xor     %r12d, %r12d
    xorpd   %xmm0, %xmm0                    /* fanout peers first */
    mov     %rbp, %rdi
    mov     $PTF_FANOUT, %esi
    mov     $CAND_BACKOFF, %edx
    call    libp2p_candidates
    mov     %rax, X23(%rsp)
    SCR     %r13, SC_LIST
    movq    $0, X24(%rsp)
1:  mov     X24(%rsp), %rax
    cmp     X23(%rsp), %rax
    jae     3f
    movl    (%r13,%rax,4), %edi
    mov     %rbp, %rsi
    call    libp2p_pt
    andq    $~PTF_FANOUT, PT_FLAGS(%rax)
    decq    T_FANOUT(%rbx)
    cmp     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %r12
    jae     2f
    mov     X24(%rsp), %rax
    movl    (%r13,%rax,4), %edi
    mov     %rbp, %rsi
    call    libp2p_mesh_add
    inc     %r12
2:  incq    X24(%rsp)
    jmp     1b
3:  call    libp2p_fanout_clear_topic
    cmp     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %r12
    jae     5f
    xorpd   %xmm0, %xmm0
    mov     %rbp, %rdi
    xor     %esi, %esi
    mov     $(PTF_MESH | CAND_BACKOFF), %edx
    call    libp2p_candidates
    mov     %rax, X23(%rsp)
    mov     %r13, %rdi
    mov     %rax, %rsi
    call    libp2p_shuffle
    movq    $0, X24(%rsp)
4:  mov     X24(%rsp), %rax
    cmp     X23(%rsp), %rax
    jae     5f
    cmp     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %r12
    jae     5f
    movl    (%r13,%rax,4), %edi
    mov     %rbp, %rsi
    call    libp2p_mesh_add
    inc     %r12
    incq    X24(%rsp)
    jmp     4b
5:  mov     %rbx, %rdi
    mov     $1, %esi
    call    libp2p_gs_announce
9:  LEAVE   0
END_FUNCTION libp2p_on_subscribe

/* libp2p_fanout_clear_topic(): (the caller's rbx topic, rbp index) no peer stays in its fanout. r12 peer index. */
LOCAL_FUNCTION libp2p_fanout_clear_topic
    ENTER   0
    xor     %r12d, %r12d
1:  cmp     ST_PEER_COUNT(%r15), %r12
    jae     9f
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    mov     PT_FLAGS(%rax), %rcx
    test    $PTF_FANOUT, %rcx
    jz      2f
    and     $~PTF_FANOUT, %rcx
    mov     %rcx, PT_FLAGS(%rax)
    decq    T_FANOUT(%rbx)
2:  inc     %r12
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_fanout_clear_topic

/*
 * libp2p_on_unsubscribe(event): we leave a topic: every mesh peer gets PRUNE
 * with unsubscribe_backoff and leaves the mesh; every gossipsub peer hears
 * of it. rbx topic, rbp topic index, r12 peer index.
 */
LOCAL_FUNCTION libp2p_on_unsubscribe
    ENTER   0
    lea     LIBP2P_EV_TOPIC(%rdi), %rax
    mov     LIBP2P_EV_TOPIC_LEN(%rdi), %rsi
    mov     %rax, %rdi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    mov     T_FLAGS(%rbx), %rax
    test    $TF_SUBSCRIBED, %rax
    jz      9f
    and     $~TF_SUBSCRIBED, %rax
    mov     %rax, T_FLAGS(%rbx)
    mov     %rbx, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rbp
    xor     %r12d, %r12d
1:  cmp     ST_PEER_COUNT(%r15), %r12
    jae     3f
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    testq   $PTF_MESH, PT_FLAGS(%rax)
    jz      2f
    mov     %r12, %rdi
    mov     %rbp, %rsi
    mov     (ST_CONFIG + LIBP2P_CFG_UNSUB_BACKOFF_MS)(%r15), %rdx
    call    libp2p_prune_to
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    libp2p_mesh_remove
2:  inc     %r12
    jmp     1b
3:  mov     %rbx, %rdi
    xor     %esi, %esi
    call    libp2p_gs_announce
    mov     %rbx, %rdi
    call    libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_on_unsubscribe

/*
 * libp2p_on_publish(event): our own message. Already seen: not sent. Else it is
 * seen (valid), cached, and sent: with flood_publish to every subscribed
 * peer at or above publish_threshold; else to the mesh, or to the fanout
 * of a topic we do not subscribe to (filled up to D). PUBLISHED gives the
 * number of peers.
 * rbx event, rbp topic, r12 topic index, r13 data block, X23 peers sent,
 * X24 list, X25 count, X26 i.
 */
LOCAL_FUNCTION libp2p_on_publish
    ENTER   0
    mov     %rdi, %rbx
    movq    $0, X23(%rsp)
    lea     LIBP2P_EV_PUB_ID(%rbx), %rdi
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rsi
    call    libp2p_seen_find
    test    %rax, %rax
    jnz     8f
    lea     LIBP2P_EV_PUB_TOPIC(%rbx), %rdi
    mov     LIBP2P_EV_PUB_TOPIC_LEN(%rbx), %rsi
    call    libp2p_topic_get
    test    %rax, %rax
    jz      8f
    mov     %rax, %rbp
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %r12
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %rdi
    call    libp2p_heap_alloc
    test    %rax, %rax
    jz      8f
    mov     %rax, %r13
    mov     LIBP2P_EV_PUB_TOPIC_LEN(%rbx), %rcx /* the data follows the topic, at a multiple of 8 */
    add     $7, %rcx
    and     $-8, %rcx
    lea     LIBP2P_EV_PUB_TOPIC(%rbx,%rcx), %rsi
    lea     (%r15,%r13), %rdi
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %rdx
    call    libp2p_copy
    lea     LIBP2P_EV_PUB_ID(%rbx), %rdi
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rsi
    mov     %r12, %rdx
    mov     $SS_VALID, %ecx
    call    libp2p_seen_add
    lea     LIBP2P_EV_PUB_ID(%rbx), %rdi
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %r8
    call    libp2p_mc_put
    call    libp2p_score_all
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_FLOOD_PUBLISH)(%r15)
    je      2f
    movsd   (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(%r15), %xmm0
    mov     %r12, %rdi
    xor     %esi, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    jmp     6f
2:  testq   $TF_SUBSCRIBED, T_FLAGS(%rbp)
    jz      3f
    movabs  $0xFFF0000000000000, %rax       /* the mesh, at any score: -infinity */
    movq    %rax, %xmm0
    mov     %r12, %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    jmp     6f
3:  mov     SC_NOW(%r14), %rax              /* the fanout */
    mov     %rax, T_FANOUT_LAST(%rbp)
    cmpq    $0, T_FANOUT(%rbp)
    jne     5f
    movsd   (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(%r15), %xmm0
    mov     %r12, %rdi
    xor     %esi, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, X25(%rsp)
    SCR     %rax, SC_LIST
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    mov     X25(%rsp), %rsi
    call    libp2p_shuffle
    mov     X25(%rsp), %rax
    mov     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %rcx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     %rax, X25(%rsp)
    movq    $0, X26(%rsp)
4:  mov     X26(%rsp), %rax
    cmp     X25(%rsp), %rax
    jae     5f
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_pt
    orq     $PTF_FANOUT, PT_FLAGS(%rax)
    incq    T_FANOUT(%rbp)
    incq    X26(%rsp)
    jmp     4b
5:  movabs  $0xFFF0000000000000, %rax
    movq    %rax, %xmm0
    mov     %r12, %rdi
    mov     $PTF_FANOUT, %esi
    xor     %edx, %edx
    call    libp2p_candidates
6:  mov     %rax, X25(%rsp)                 /* send to the list */
    SCR     %rax, SC_LIST
    mov     %rax, X24(%rsp)
    movq    $0, X26(%rsp)
7:  mov     X26(%rsp), %rax
    cmp     X25(%rsp), %rax
    jae     8f
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     %rbp, %rsi
    lea     (%r15,%r13), %rdx
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %rcx
    call    libp2p_gs_send_msg
    add     %rax, X23(%rsp)
    incq    X26(%rsp)
    jmp     7b
8:  mov     $LIBP2P_ACTION_PUBLISHED, %edi
    mov     $LIBP2P_ACT_PUB_SIZE, %esi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, X24(%rsp)
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rdx
    mov     %rdx, LIBP2P_ACT_PUB_ID_LEN(%rax)
    lea     LIBP2P_ACT_PUB_ID(%rax), %rdi
    lea     LIBP2P_EV_PUB_ID(%rbx), %rsi
    call    libp2p_copy
    mov     X24(%rsp), %rax
    mov     X23(%rsp), %rcx
    mov     %rcx, LIBP2P_ACT_PUB_PEERS(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_on_publish

/*
 * libp2p_on_message_id(event): the ID of a message waiting for one. Seen
 * before: a duplicate (scores, promises), MESSAGE_STATUS duplicate, and
 * the slot is free. Else it is seen (pending), promises of it are kept,
 * and MESSAGE_STATUS new asks for a VALIDATION.
 * rbx event, rbp pending, r12 seen.
 */
LOCAL_FUNCTION libp2p_on_message_id
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_HANDLE(%rbx), %rdi
    call    libp2p_pend
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    cmpl    $PDS_WAIT_ID, PD_STATE(%rbp)
    jne     9f
    mov     LIBP2P_EV_MSG_ID_LEN(%rbx), %rdx
    mov     %rdx, PD_ID_LEN(%rbp)
    lea     PD_ID(%rbp), %rdi
    lea     LIBP2P_EV_MSG_ID(%rbx), %rsi
    call    libp2p_copy
    lea     PD_ID(%rbp), %rdi
    mov     PD_ID_LEN(%rbp), %rsi
    call    libp2p_promise_keep
    lea     PD_ID(%rbp), %rdi
    mov     PD_ID_LEN(%rbp), %rsi
    call    libp2p_seen_find
    test    %rax, %rax
    jz      1f
    mov     %rax, %r12                      /* a duplicate */
    mov     PD_PEER(%rbp), %rdi
    mov     %r12, %rsi
    call    libp2p_score_duplicate
    mov     %rbp, %rdi
    mov     $LIBP2P_MSG_DUPLICATE, %esi
    call    libp2p_pend_status
    mov     %rbp, %rdi
    call    libp2p_pend_free
    jmp     9f
1:  lea     PD_ID(%rbp), %rdi
    mov     PD_ID_LEN(%rbp), %rsi
    mov     PD_TOPIC(%rbp), %rdx
    mov     $SS_PENDING, %ecx
    call    libp2p_seen_add
    sub     ST_SEEN_OFF(%r15), %rax
    sub     %r15, %rax
    xor     %edx, %edx
    mov     $SN_SIZE, %ecx
    div     %rcx
    mov     %rax, PD_SEEN(%rbp)
    movl    $PDS_WAIT_VERDICT, PD_STATE(%rbp)
    mov     %rbp, %rdi
    mov     $LIBP2P_MSG_NEW, %esi
    call    libp2p_pend_status
9:  LEAVE   0
END_FUNCTION libp2p_on_message_id

/*
 * libp2p_on_validation(event): the application judged a new message. ACCEPT:
 * seen valid, first-delivery and mesh-delivery scores, cached, and sent to
 * the mesh of the topic except the peers that already sent it. REJECT:
 * seen invalid and an invalid message for those peers. IGNORE: seen
 * ignored. Then the slot is free.
 * rbx event, rbp pending, r12 seen, r13 result, X23 topic, X24 i, X25 list,
 * X26 count.
 */
LOCAL_FUNCTION libp2p_on_validation
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_HANDLE(%rbx), %rdi
    call    libp2p_pend
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    cmpl    $PDS_WAIT_VERDICT, PD_STATE(%rbp)
    jne     9f
    mov     LIBP2P_EV_RESULT(%rbx), %r13
    imul    $SN_SIZE, PD_SEEN(%rbp), %r12   /* the seen entry, if it is still that message */
    add     ST_SEEN_OFF(%r15), %r12
    add     %r15, %r12
    lea     SN_ID(%r12), %rdi
    mov     SN_ID_LEN(%r12), %rsi
    lea     PD_ID(%rbp), %rdx
    mov     PD_ID_LEN(%rbp), %rcx
    call    libp2p_compare
    test    %rax, %rax
    jnz     1f
    xor     %r12d, %r12d
1:  cmp     $LIBP2P_ACCEPT, %r13
    jne     5f
    test    %r12, %r12
    jz      2f
    movq    $SS_VALID, SN_STATUS(%r12)
    mov     SC_NOW(%r14), %rax
    mov     %rax, SN_VALIDATED(%r12)
2:  mov     PD_PEER(%rbp), %rdi
    mov     PD_TOPIC(%rbp), %rsi
    mov     %r12, %rdx
    call    libp2p_score_valid
    lea     PD_ID(%rbp), %rdi               /* cached: the cache owns the data now */
    mov     PD_ID_LEN(%rbp), %rsi
    mov     PD_TOPIC(%rbp), %rdx
    mov     PD_DATA(%rbp), %rcx
    mov     PD_DATA_LEN(%rbp), %r8
    call    libp2p_mc_put
    mov     PD_TOPIC(%rbp), %rdi
    call    libp2p_topic_at
    mov     %rax, X23(%rsp)
    movabs  $0xFFF0000000000000, %rax
    movq    %rax, %xmm0
    mov     PD_TOPIC(%rbp), %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, X26(%rsp)
    SCR     %rax, SC_LIST
    mov     %rax, X25(%rsp)
    movq    $0, X24(%rsp)
3:  mov     X24(%rsp), %rax
    cmp     X26(%rsp), %rax
    jae     4f
    mov     X25(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    cmp     PD_PEER(%rbp), %rdi
    je      31f
    mov     %r12, %rsi
    call    libp2p_seen_delivered
    test    %rax, %rax
    jnz     31f
    mov     X24(%rsp), %rax
    mov     X25(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     X23(%rsp), %rsi
    mov     PD_DATA(%rbp), %rdx
    add     %r15, %rdx
    mov     PD_DATA_LEN(%rbp), %rcx
    call    libp2p_gs_send_msg
31: incq    X24(%rsp)
    jmp     3b
4:  movq    $0, PD_DATA(%rbp)
    jmp     8f
5:  cmp     $LIBP2P_REJECT, %r13
    jne     6f
    test    %r12, %r12
    jz      51f
    movq    $SS_INVALID, SN_STATUS(%r12)
51: mov     PD_PEER(%rbp), %rdi
    mov     PD_TOPIC(%rbp), %rsi
    mov     %r12, %rdx
    call    libp2p_score_rejected
    jmp     8f
6:  test    %r12, %r12
    jz      8f
    movq    $SS_IGNORED, SN_STATUS(%r12)
8:  mov     %rbp, %rdi
    call    libp2p_pend_free
9:  LEAVE   0
END_FUNCTION libp2p_on_validation

/* libp2p_seen_delivered(peer index, seen) -> 1 when the peer is a deliverer of the seen message, else 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_delivered
    UNWIND_END_PROLOGUE
    test    %rsi, %rsi
    jz      8f
    movl    SN_COUNT(%rsi), %ecx
    lea     SN_PEERS(%rsi), %rdx
1:  test    %rcx, %rcx
    jz      8f
    movzwl  (%rdx), %eax
    add     $2, %rdx
    cmp     %rdi, %rax
    je      7f
    dec     %rcx
    jmp     1b
7:  mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_seen_delivered

/* libp2p_on_app_score(event): the application-specific score of a peer (P5). */
LOCAL_FUNCTION libp2p_on_app_score
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_PEER(%rbx), %rdi
    call    libp2p_peer
    test    %rax, %rax
    jz      9f
    mov     LIBP2P_EV_SCORE(%rbx), %rcx
    mov     %rcx, P_APP_SCORE(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_on_app_score

/* libp2p_on_topic_params(event): the score parameters of a topic. */
LOCAL_FUNCTION libp2p_on_topic_params
    ENTER   0
    mov     %rdi, %rbx
    lea     LIBP2P_EV_TP_TOPIC(%rbx), %rdi
    mov     LIBP2P_EV_TP_TOPIC_LEN(%rbx), %rsi
    call    libp2p_topic_get
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    lea     T_PARAMS(%rbp), %rdi
    lea     LIBP2P_EV_TP_PARAMS(%rbx), %rsi
    mov     $LIBP2P_TP_SIZE, %edx
    call    libp2p_copy
    orq     $TF_PARAMS, T_FLAGS(%rbp)
9:  LEAVE   0
END_FUNCTION libp2p_on_topic_params

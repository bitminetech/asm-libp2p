/*
 * gossipsub input of the x86-64 core: the RPC reader of a peer's stream,
 * subscriptions, messages, control messages, the gossipsub events of the
 * application, and peers coming and going. Included by gossip.s.
 *
 * Score comparisons follow the ARM64 conditions, unordered results
 * included: "fcmp a, b; b.mi" (a < b) is "ucomisd a, b; ja" (b > a).
 */

/* ---------------------------------------------------------------- Peers */

/*
 * libp2p_gossip_peer_up(peer): a peer connected: its IDONTWANT ring is empty,
 * and our gossipsub stream to it opens, with /meshsub/1.3.0 when
 * gossipsub_v13 is on, /meshsub/1.2.0 when gossipsub_v12 is on, then
 * /meshsub/1.1.0 to propose.
 */
LOCAL_FUNCTION libp2p_gossip_peer_up
    ENTER   0
    mov     %rdi, %rbx
    movq    $0, P_DW_HEAD(%rbx)
    movq    $0, P_DW_COUNT(%rbx)
    call    libp2p_peer_idx
    mov     %rax, %rdi
    call    libp2p_dw_ring
    mov     %rax, %rdi
    imul    $DW_SIZE, (ST_CONFIG + LIBP2P_CFG_DONTWANT_SLOTS)(%r15), %rsi
    call    libp2p_zero
    imul    $C_SIZE, P_CONN(%rbx), %rdi
    add     ST_CONN_OFF(%r15), %rdi
    add     %r15, %rdi
    mov     $SK_GOSSIP_OUT, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15), %r8
    add     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15), %r8
    inc     %r8
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

/*
 * libp2p_gossip_out_ready(stream): our gossipsub stream to a peer is open:
 * with /meshsub/1.3.0 its first RPC is our Extensions control message; it
 * learns our subscriptions; with /meshsub/1.2.0 or /meshsub/1.3.0 it gets
 * IDONTWANT.
 */
LOCAL_FUNCTION libp2p_gossip_out_ready
    ENTER   0
    mov     %rdi, %r13
    mov     S_PEER(%rdi), %rdi
    call    libp2p_peer_at
    mov     %rax, %rbx
    orq     $(PF_GOSSIP | PF_HELLO), P_FLAGS(%rbx)
    mov     S_PROTO(%r13), %rax             /* the index of the proposal taken */
    mov     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V12)(%r15), %rcx
    add     (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15), %rcx /* the index of /meshsub/1.1.0 */
    cmp     %rcx, %rax
    jae     3f
    orq     $PF_IDONTWANT, P_FLAGS(%rbx)
3:  test    %rax, %rax                      /* /meshsub/1.3.0: our extensions first */
    jnz     4f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_GOSSIPSUB_V13)(%r15)
    je      4f
    mov     %rbx, %rdi
    call    libp2p_gs_send_ext
4:
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

/*
 * libp2p_gossip_in_ready(stream): the peer opened its gossipsub stream to us:
 * its extensions come with the first RPC on it.
 */
LOCAL_FUNCTION libp2p_gossip_in_ready
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_stream_index
    mov     %rax, %rbp
    mov     S_PEER(%rbx), %rdi
    call    libp2p_peer_at
    mov     %rbp, P_GS_IN(%rax)
    andq    $~(PF_EXT_SEEN | PF_EXT_GOT | PF_PARTIAL), P_FLAGS(%rax)
    LEAVE   0
END_FUNCTION libp2p_gossip_in_ready

/* ---------------------------------------------------------------- RPC reader */

/*
 * libp2p_gossip_rx(stream, p, n): bytes of a peer's gossipsub stream: each RPC
 * is a varint length, then that many bytes, read into one heap block and
 * handled whole. An RPC above max_rpc resets the stream; one the heap
 * cannot hold is skipped. A block that PARTIAL actions refer to stays, on
 * the ST_KEPT_RPC list, until the next step.
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
    test    %rax, %rax
    jz      5f
    mov     X25(%rsp), %rax                 /* kept until the next step */
    lea     -HB_HEADER(%r15,%rax), %rcx
    mov     ST_KEPT_RPC(%r15), %rdx
    mov     %rdx, HB_NEXT(%rcx)
    mov     %rax, ST_KEPT_RPC(%r15)
    jmp     1b
5:  mov     X25(%rsp), %rdi
    call    libp2p_heap_free
    jmp     1b
8:  mov     %rbx, %rdi
    mov     $LIBP2P_REASON_PROTOCOL, %esi
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_gossip_rx

/*
 * libp2p_rpc_handle(peer index, p, n) -> 1 when a PARTIAL action refers to
 * the bytes of the RPC, else 0: one whole RPC of a peer: subscriptions,
 * published messages, control and partial messages, in their order. A
 * graylisted peer is not heard; a field that is not well formed ends the
 * RPC. After the first RPC, the extensions of the peer are known.
 * rbx peer index, rbp p, r12 end, r13 peer, X23 result.
 */
LOCAL_FUNCTION libp2p_rpc_handle
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    movq    $0, X23(%rsp)
    call    libp2p_peer_at
    mov     %rax, %r13
    cmpl    $PS_CONNECTED, P_STATE(%r13)
    jne     9f
    mov     %r13, %rdi
    call    libp2p_score
    movsd   (ST_CONFIG + LIBP2P_CFG_GRAYLIST_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm0, %xmm1
    ja      8f
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     8f
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
    jne     4f
    call    libp2p_rpc_control
    jmp     1b
4:  cmp     $10, %r9
    jne     1b
    call    libp2p_rpc_partial
    or      %rax, X23(%rsp)
    jmp     1b
8:  orq     $PF_EXT_SEEN, P_FLAGS(%r13)     /* its extensions are known now */
9:  mov     X23(%rsp), %rax
    LEAVE   0
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
 * libp2p_rpc_sub(peer index, p, n): one SubOpts: subscribe (field 1), topicid
 * (field 2), requestsPartial (3) and supportsSendingPartial (4). The peer's
 * subscription and its partial flags are noted, with PEER_TOPIC for a new
 * one; leaving a topic takes it out of our mesh and fanout of the topic.
 * rbx peer index, rbp p, r12 end, r13 subscribe, X23 topic name then the
 * entry, X24 length, X25 topic, X26 partial flags (LIBP2P_PARTIAL_*) then
 * the topic index.
 */
LOCAL_FUNCTION libp2p_rpc_sub
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    xor     %r13d, %r13d
    movq    $0, X23(%rsp)
    movq    $0, X26(%rsp)
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
    jne     12f
    cmp     $2, %rcx
    jne     1b
    mov     %rsi, X23(%rsp)
    mov     %rdi, X24(%rsp)
    jmp     1b
12: test    %rcx, %rcx                      /* requestsPartial: supports too */
    jnz     1b
    test    %rsi, %rsi
    jz      1b
    cmp     $3, %rdx
    jne     13f
    orq     $(LIBP2P_PARTIAL_REQUESTS | LIBP2P_PARTIAL_SUPPORTS), X26(%rsp)
    jmp     1b
13: cmp     $4, %rdx
    jne     1b
    orq     $LIBP2P_PARTIAL_SUPPORTS, X26(%rsp)
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
    mov     %rcx, %rdx
    and     $~(PTF_REQUESTS_PARTIAL | PTF_SUPPORTS_PARTIAL), %rdx
    mov     X26(%rsp), %rsi
    shl     $3, %rsi
    or      %rsi, %rdx
    or      $PTF_SUBSCRIBED, %rdx
    mov     %rdx, PT_FLAGS(%rax)
    test    $PTF_SUBSCRIBED, %rcx
    jnz     9f
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
7:  and     $~(PTF_SUBSCRIBED | PTF_FANOUT | PTF_REQUESTS_PARTIAL | PTF_SUPPORTS_PARTIAL), %rcx
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

/* libp2p_rpc_control(peer index, p, n): a ControlMessage: ihave (1), iwant (2), graft (3), prune (4), idontwant (5), extensions (6). */
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
    jne     5f
    call    libp2p_ctl_prune
    jmp     1b
5:  cmp     $5, %r9
    jne     6f
    call    libp2p_ctl_idontwant
    jmp     1b
6:  cmp     $6, %r9
    jne     1b
    call    libp2p_ctl_extensions
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_control

/*
 * libp2p_ctl_extensions(peer index, p, n): the Extensions control message of
 * a peer. Only its first RPC on the stream may hold one, once; another costs
 * a behaviour penalty. partialMessages (field 10) set marks the peer.
 * rbx peer index, rbp p, r12 end, r13 peer, X23 partialMessages.
 */
LOCAL_FUNCTION libp2p_ctl_extensions
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    call    libp2p_peer_at
    mov     %rax, %r13
    testq   $(PF_EXT_SEEN | PF_EXT_GOT), P_FLAGS(%r13)
    jz      1f
    mov     %r13, %rdi                      /* not the first: a protocol violation */
    mov     $1, %esi
    call    libp2p_behaviour_penalty
    jmp     9f
1:  orq     $PF_EXT_GOT, P_FLAGS(%r13)
    movq    $0, X23(%rsp)
2:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     3f
    mov     %r8, %rbp
    cmp     $10, %rdx
    jne     2b
    test    %rcx, %rcx
    jnz     2b
    xor     %eax, %eax
    test    %rsi, %rsi
    setne   %al
    mov     %rax, X23(%rsp)
    jmp     2b
3:  cmpq    $0, X23(%rsp)
    je      9f
    orq     $PF_PARTIAL, P_FLAGS(%r13)
9:  LEAVE   0
END_FUNCTION libp2p_ctl_extensions

/*
 * libp2p_rpc_partial(peer index, p, n) -> 1 when a PARTIAL action refers to
 * the bytes of the RPC, else 0: the PartialMessagesExtension of a peer that
 * has the extension, when partial_messages is on: topicID (field 1, 1 to
 * LIBP2P_MAX_TOPIC bytes) and groupID (2) must be there; partialMessage (3)
 * counts only on a topic we want partial messages on; partsMetadata (4).
 * PARTIAL gives the bytes, with the peer's flags on the topic, when metadata
 * or a message is left.
 * rbx peer index, rbp p, r12 end, r13 topic, X23 topic length, X24 group,
 * X25 group length, X26 action then the result. 32(%rsp): metadata, then
 * message (address and length each); 64(%rsp): the peer's flags;
 * 72(%rsp): our topic flags.
 */
LOCAL_FUNCTION libp2p_rpc_partial
    ENTER   48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    xor     %r13d, %r13d
    movq    $0, X24(%rsp)
    movq    $0, X26(%rsp)
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)
    movq    $0, 48(%rsp)
    movq    $0, 56(%rsp)
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)(%r15)
    je      9f
    call    libp2p_peer_at
    testq   $PF_PARTIAL, P_FLAGS(%rax)
    jz      9f
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     2f
    mov     %r8, %rbp
    cmp     $2, %rcx
    jne     1b
    cmp     $1, %rdx
    jne     11f
    mov     %rsi, %r13
    mov     %rdi, X23(%rsp)
    jmp     1b
11: cmp     $2, %rdx
    jne     12f
    mov     %rsi, X24(%rsp)
    mov     %rdi, X25(%rsp)
    jmp     1b
12: cmp     $3, %rdx
    jne     13f
    mov     %rsi, 48(%rsp)                  /* the message */
    mov     %rdi, 56(%rsp)
    jmp     1b
13: cmp     $4, %rdx
    jne     1b
    mov     %rsi, 32(%rsp)                  /* the metadata */
    mov     %rdi, 40(%rsp)
    jmp     1b
2:  cmp     $NONE, %rax
    je      9f
    test    %r13, %r13
    jz      9f
    cmpq    $0, X24(%rsp)
    je      9f
    mov     X23(%rsp), %rax                 /* 1 to LIBP2P_MAX_TOPIC bytes */
    dec     %rax
    cmp     $(LIBP2P_MAX_TOPIC - 1), %rax
    ja      9f
    movq    $0, 64(%rsp)                    /* the peer's flags, our topic flags */
    movq    $0, 72(%rsp)
    mov     %r13, %rdi
    mov     X23(%rsp), %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      21f
    mov     T_FLAGS(%rax), %rcx
    mov     %rcx, 72(%rsp)
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rsi
    mov     %rbx, %rdi
    call    libp2p_partial_flags
    mov     %rax, 64(%rsp)
    testq   $TF_REQUESTS_PARTIAL, 72(%rsp)  /* a message: only on a topic we want them on */
    jnz     3f
21: movq    $0, 48(%rsp)
    movq    $0, 56(%rsp)
3:  mov     40(%rsp), %rax
    or      56(%rsp), %rax
    jz      9f                              /* nothing to give */
    mov     X23(%rsp), %rsi
    add     $(LIBP2P_ACT_PM_TOPIC + 7), %rsi
    and     $~7, %rsi
    mov     $LIBP2P_ACTION_PARTIAL, %edi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, X26(%rsp)
    mov     %rbx, %rdi
    call    libp2p_peer_at
    mov     %rax, %rdx
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    call    libp2p_handle
    mov     X26(%rsp), %rcx
    mov     %rax, LIBP2P_ACT_PM_PEER(%rcx)
    mov     64(%rsp), %rax
    mov     %rax, LIBP2P_ACT_PM_FLAGS(%rcx)
    mov     X23(%rsp), %rax
    mov     %rax, LIBP2P_ACT_PM_TOPIC_LEN(%rcx)
    mov     X24(%rsp), %rax                 /* offsets from the start of the state */
    sub     %r15, %rax
    mov     %rax, LIBP2P_ACT_PM_GROUP_OFF(%rcx)
    mov     X25(%rsp), %rax
    mov     %rax, LIBP2P_ACT_PM_GROUP_LEN(%rcx)
    mov     32(%rsp), %rax
    sub     %r15, %rax
    mov     40(%rsp), %rdx
    test    %rdx, %rdx
    jnz     4f
    xor     %eax, %eax
4:  mov     %rax, LIBP2P_ACT_PM_META_OFF(%rcx)
    mov     %rdx, LIBP2P_ACT_PM_META_LEN(%rcx)
    mov     48(%rsp), %rax
    sub     %r15, %rax
    mov     56(%rsp), %rdx
    test    %rdx, %rdx
    jnz     5f
    xor     %eax, %eax
5:  mov     %rax, LIBP2P_ACT_PM_MSG_OFF(%rcx)
    mov     %rdx, LIBP2P_ACT_PM_MSG_LEN(%rcx)
    lea     LIBP2P_ACT_PM_TOPIC(%rcx), %rdi
    mov     %r13, %rsi
    mov     X23(%rsp), %rdx
    call    libp2p_copy
    movq    $1, X26(%rsp)
9:  mov     X26(%rsp), %rax
    LEAVE   48
END_FUNCTION libp2p_rpc_partial

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
 * retransmission times, unless the peer sent IDONTWANT for it.
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
    mov     %rbx, %rdi
    lea     MC_ID(%rax), %rsi
    mov     MC_ID_LEN(%rax), %rdx
    call    libp2p_dontwant
    test    %rax, %rax
    jnz     1b
    mov     X23(%rsp), %rdi
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

/*
 * libp2p_ctl_idontwant(peer index, p, n): an IDONTWANT of a peer: up to
 * max_idontwant_length of its message IDs (1 to LIBP2P_MAX_MSG_ID bytes)
 * go in the peer's ring with the heartbeat number, each over the oldest.
 * With no slots, or past max_idontwant_messages in this heartbeat, it is
 * not heard.
 * rbx peer index, rbp p, r12 end, r13 peer, X23 IDs left, X24 ring,
 * X25 slots.
 */
LOCAL_FUNCTION libp2p_ctl_idontwant
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (%rsi,%rdx), %r12
    mov     (ST_CONFIG + LIBP2P_CFG_DONTWANT_SLOTS)(%r15), %rax
    test    %rax, %rax
    jz      9f
    mov     %rax, X25(%rsp)
    call    libp2p_peer_at
    mov     %rax, %r13
    mov     P_DW_COUNT(%r13), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_MAX_IDONTWANT_MESSAGES)(%r15), %rax
    jae     9f
    inc     %rax
    mov     %rax, P_DW_COUNT(%r13)
    mov     (ST_CONFIG + LIBP2P_CFG_MAX_IDONTWANT_LENGTH)(%r15), %rax
    mov     %rax, X23(%rsp)
    mov     %rbx, %rdi
    call    libp2p_dw_ring
    mov     %rax, X24(%rsp)
1:  cmpq    $0, X23(%rsp)
    je      9f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pb_next
    cmp     $1, %rax
    jne     9f
    mov     %r8, %rbp
    cmp     $1, %rdx
    jne     1b
    cmp     $2, %rcx
    jne     1b
    decq    X23(%rsp)
    lea     -1(%rdi), %rax                  /* 1 to LIBP2P_MAX_MSG_ID bytes */
    cmp     $(LIBP2P_MAX_MSG_ID - 1), %rax
    ja      1b
    mov     P_DW_HEAD(%r13), %rax
    imul    $DW_SIZE, %rax, %rcx
    add     X24(%rsp), %rcx
    inc     %rax
    xor     %edx, %edx
    cmp     X25(%rsp), %rax
    cmovae  %rdx, %rax
    mov     %rax, P_DW_HEAD(%r13)
    mov     ST_HEARTBEATS(%r15), %rax
    mov     %rax, DW_HB(%rcx)
    mov     %rdi, DW_ID_LEN(%rcx)
    mov     %rdi, %rdx
    lea     DW_ID(%rcx), %rdi
    call    libp2p_copy
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_ctl_idontwant

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

/* libp2p_on_subscribe(event): SUBSCRIBE: libp2p_subscribe, the partial flags kept. */
LOCAL_FUNCTION libp2p_on_subscribe
    FRAME
    lea     LIBP2P_EV_TOPIC(%rdi), %rax
    mov     LIBP2P_EV_TOPIC_LEN(%rdi), %rsi
    mov     %rax, %rdi
    mov     $NONE, %rdx
    call    libp2p_subscribe
    UNFRAME
END_FUNCTION libp2p_on_subscribe

/* libp2p_on_partial_subscribe(event): PARTIAL_SUBSCRIBE: libp2p_subscribe with its flags. */
LOCAL_FUNCTION libp2p_on_partial_subscribe
    FRAME
    lea     LIBP2P_EV_PS_TOPIC(%rdi), %rax
    mov     LIBP2P_EV_PS_TOPIC_LEN(%rdi), %rsi
    mov     LIBP2P_EV_PS_FLAGS(%rdi), %rdx
    mov     %rax, %rdi
    call    libp2p_subscribe
    UNFRAME
END_FUNCTION libp2p_on_partial_subscribe

/*
 * libp2p_subscribe(name, n, flags): we join a topic. flags (LIBP2P_PARTIAL_*,
 * REQUESTS implying SUPPORTS) become our partial flags of it, or NONE keeps
 * them. A topic we subscribe to already: when its flags change, every
 * gossipsub peer hears the new SubOpts. Else our fanout peers of it, then
 * other subscribed peers at random, fill the mesh up to D (score 0 or
 * more, outside backoff), each with GRAFT; every gossipsub peer hears of it.
 * rbx topic, rbp topic index, r12 mesh count, r13 list, X23 count, X24 i,
 * X25 flags.
 */
LOCAL_FUNCTION libp2p_subscribe
    ENTER   0
    mov     %rdx, X25(%rsp)
    call    libp2p_topic_get
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    mov     T_FLAGS(%rbx), %rax
    mov     X25(%rsp), %rcx
    cmp     $NONE, %rcx
    je      11f
    test    $LIBP2P_PARTIAL_REQUESTS, %rcx
    jz      10f
    or      $LIBP2P_PARTIAL_SUPPORTS, %rcx
10: shl     $2, %rcx
    mov     %rax, %rdx
    and     $~(TF_REQUESTS_PARTIAL | TF_SUPPORTS_PARTIAL), %rdx
    or      %rcx, %rdx
    mov     %rdx, T_FLAGS(%rbx)
    test    $TF_SUBSCRIBED, %rax
    jz      12f
    cmp     %rax, %rdx
    je      9f
    mov     %rbx, %rdi                      /* new flags: the peers hear them */
    mov     $1, %esi
    call    libp2p_gs_announce
    jmp     9f
11: test    $TF_SUBSCRIBED, %rax
    jnz     9f
12: orq     $TF_SUBSCRIBED, T_FLAGS(%rbx)
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
END_FUNCTION libp2p_subscribe

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
 * libp2p_on_unsubscribe(event): we leave a topic, and our partial flags of it
 * end: every mesh peer gets PRUNE with unsubscribe_backoff and leaves the
 * mesh; every gossipsub peer hears of it. rbx topic, rbp topic index, r12
 * peer index.
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
    and     $~(TF_SUBSCRIBED | TF_REQUESTS_PARTIAL | TF_SUPPORTS_PARTIAL), %rax
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
 * of a topic we do not subscribe to (libp2p_fanout_list); never to a peer
 * that sent IDONTWANT for it or that gets partial messages of the topic
 * from us. PUBLISHED gives the number of peers.
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
3:  mov     %rbp, %rdi                      /* the fanout */
    mov     %r12, %rsi
    call    libp2p_fanout_list
6:  mov     %rax, X25(%rsp)                 /* send to the list */
    SCR     %rax, SC_LIST
    mov     %rax, X24(%rsp)
    movq    $0, X26(%rsp)
7:  mov     X26(%rsp), %rax
    cmp     X25(%rsp), %rax
    jae     8f
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_wants_partial
    test    %rax, %rax
    jnz     71f
    mov     X26(%rsp), %rax
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    lea     LIBP2P_EV_PUB_ID(%rbx), %rsi
    mov     LIBP2P_EV_PUB_ID_LEN(%rbx), %rdx
    call    libp2p_dontwant
    test    %rax, %rax
    jnz     71f
    mov     X26(%rsp), %rax
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     %rbp, %rsi
    lea     (%r15,%r13), %rdx
    mov     LIBP2P_EV_PUB_DATA_LEN(%rbx), %rcx
    call    libp2p_gs_send_msg
    add     %rax, X23(%rsp)
71: incq    X26(%rsp)
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
 * libp2p_fanout_list(topic, topic index) -> the count of the fanout peers of
 * a topic we do not subscribe to, in SC_LIST: an empty fanout is filled
 * first with up to D subscribed peers at or above publish_threshold, at
 * random. Our last publish to the topic is now.
 * rbx topic, rbp topic index, r12 list, r13 count, X23 i.
 */
LOCAL_FUNCTION libp2p_fanout_list
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     SC_NOW(%r14), %rax
    mov     %rax, T_FANOUT_LAST(%rbx)
    cmpq    $0, T_FANOUT(%rbx)
    jne     5f
    movsd   (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(%r15), %xmm0
    mov     %rbp, %rdi
    xor     %esi, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, %r13
    SCR     %r12, SC_LIST
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_shuffle
    mov     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %rcx
    cmp     %rcx, %r13
    cmovae  %rcx, %r13
    movq    $0, X23(%rsp)
4:  mov     X23(%rsp), %rax
    cmp     %r13, %rax
    jae     5f
    movl    (%r12,%rax,4), %edi
    mov     %rbp, %rsi
    call    libp2p_pt
    orq     $PTF_FANOUT, PT_FLAGS(%rax)
    incq    T_FANOUT(%rbx)
    incq    X23(%rsp)
    jmp     4b
5:  movabs  $0xFFF0000000000000, %rax       /* the fanout, at any score: -infinity */
    movq    %rax, %xmm0
    mov     %rbp, %rdi
    mov     $PTF_FANOUT, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    LEAVE   0
END_FUNCTION libp2p_fanout_list

/*
 * libp2p_on_message_id(event): the ID of a message waiting for one. Seen
 * before: a duplicate (scores, promises), MESSAGE_STATUS duplicate, and
 * the slot is free. Else it is seen (pending), promises of it are kept,
 * IDONTWANT goes to the mesh at once, and MESSAGE_STATUS new asks for a
 * VALIDATION.
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
    call    libp2p_gs_idontwant
    mov     %rbp, %rdi
    mov     $LIBP2P_MSG_NEW, %esi
    call    libp2p_pend_status
9:  LEAVE   0
END_FUNCTION libp2p_on_message_id

/*
 * libp2p_on_validation(event): the application judged a new message. ACCEPT:
 * seen valid, first-delivery and mesh-delivery scores, cached, and sent to
 * the mesh of the topic except the peers that already sent it, sent
 * IDONTWANT for it or get partial messages of the topic from us. REJECT:
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
    mov     PD_TOPIC(%rbp), %rsi
    call    libp2p_wants_partial
    test    %rax, %rax
    jnz     31f
    mov     X24(%rsp), %rax
    mov     X25(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_seen_delivered
    test    %rax, %rax
    jnz     31f
    mov     X24(%rsp), %rax
    mov     X25(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    lea     PD_ID(%rbp), %rsi
    mov     PD_ID_LEN(%rbp), %rdx
    call    libp2p_dontwant
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

/* ---------------------------------------------------------------- Partial messages */

/*
 * libp2p_partial_flags(peer index, topic index) -> the LIBP2P_PARTIAL_* flags
 * of the peer's subscription to the topic; 0 when partial_messages is off
 * or the peer lacks the extension. A leaf.
 */
LOCAL_FUNCTION libp2p_partial_flags
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)(%r15)
    je      9f
    imul    $P_SIZE, %rdi, %rcx
    add     ST_PEER_OFF(%r15), %rcx
    testq   $PF_PARTIAL, P_FLAGS(%r15,%rcx)
    jz      9f
    imul    ST_TOPIC_COUNT(%r15), %rdi
    add     %rsi, %rdi
    imul    $PT_SIZE, %rdi, %rdi
    add     ST_PT_OFF(%r15), %rdi
    mov     PT_FLAGS(%r15,%rdi), %rax
    shr     $3, %rax
    and     $3, %eax
9:  ret
END_FUNCTION libp2p_partial_flags

/*
 * libp2p_wants_partial(peer index, topic index) -> 1 when we send partial
 * messages on the topic and the peer wants them, else 0.
 * rbx topic index, rbp the peer's flags.
 */
LOCAL_FUNCTION libp2p_wants_partial
    ENTER   0
    mov     %rsi, %rbx
    call    libp2p_partial_flags
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_topic_at
    mov     T_FLAGS(%rax), %rax
    shr     $3, %rax                        /* TF_SUPPORTS_PARTIAL */
    and     %rbp, %rax                      /* and LIBP2P_PARTIAL_REQUESTS of the peer */
    and     $1, %eax
    LEAVE   0
END_FUNCTION libp2p_wants_partial

/*
 * libp2p_sends_partial(peer index, topic index) -> 1 when we want partial
 * messages on the topic and the peer sends them, else 0.
 * rbx topic index, rbp the peer's flags.
 */
LOCAL_FUNCTION libp2p_sends_partial
    ENTER   0
    mov     %rsi, %rbx
    call    libp2p_partial_flags
    shr     $1, %rax                        /* LIBP2P_PARTIAL_SUPPORTS of the peer */
    mov     %rax, %rbp
    mov     %rbx, %rdi
    call    libp2p_topic_at
    mov     T_FLAGS(%rax), %rax
    shr     $2, %rax                        /* TF_REQUESTS_PARTIAL */
    and     %rbp, %rax
    and     $1, %eax
    LEAVE   0
END_FUNCTION libp2p_sends_partial

/*
 * libp2p_on_partial_peers(event): PARTIAL_PEERS gives the peers of a topic to
 * send partial messages to, with their LIBP2P_PARTIAL_* flags: the mesh
 * peers of a topic we subscribe to with libp2p_wants_partial or
 * libp2p_sends_partial; else the fanout peers (libp2p_fanout_list) that
 * want partial messages. The list is empty when the topic table is full.
 * rbx event, rbp topic, r12 topic index, r13 list, X23 count kept, X24 i,
 * X25 count, then the action, X26 the result of libp2p_wants_partial, then
 * the entry.
 */
LOCAL_FUNCTION libp2p_on_partial_peers
    ENTER   0
    mov     %rdi, %rbx
    movq    $0, X23(%rsp)
    call    libp2p_score_all
    lea     LIBP2P_EV_PP_TOPIC(%rbx), %rdi
    mov     LIBP2P_EV_PP_TOPIC_LEN(%rbx), %rsi
    call    libp2p_topic_get
    test    %rax, %rax
    jz      5f
    mov     %rax, %rbp
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %r12
    testq   $TF_SUBSCRIBED, T_FLAGS(%rbp)
    jz      1f
    movabs  $0xFFF0000000000000, %rax       /* the mesh, at any score: -infinity */
    movq    %rax, %xmm0
    mov     %r12, %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    jmp     2f
1:  mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_fanout_list
2:  mov     %rax, X25(%rsp)
    SCR     %r13, SC_LIST
    movq    $0, X24(%rsp)
3:  mov     X24(%rsp), %rax                 /* keep the peers that take part */
    cmp     X25(%rsp), %rax
    jae     5f
    testq   $TF_SUBSCRIBED, T_FLAGS(%rbp)
    jnz     31f
    movl    (%r13,%rax,4), %edi             /* the fanout: the peers that want them */
    mov     %r12, %rsi
    call    libp2p_partial_flags
    and     $LIBP2P_PARTIAL_REQUESTS, %eax
    jmp     32f
31: movl    (%r13,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_wants_partial
    mov     %rax, X26(%rsp)
    mov     X24(%rsp), %rax
    movl    (%r13,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_sends_partial
    or      X26(%rsp), %rax
32: test    %rax, %rax
    jz      4f
    mov     X24(%rsp), %rax
    movl    (%r13,%rax,4), %ecx
    mov     X23(%rsp), %rax
    movl    %ecx, (%r13,%rax,4)
    incq    X23(%rsp)
4:  incq    X24(%rsp)
    jmp     3b
5:  mov     LIBP2P_EV_PP_TOPIC_LEN(%rbx), %rax
    add     $(LIBP2P_ACT_PL_TOPIC + 7), %rax
    and     $~7, %rax
    mov     %rax, X24(%rsp)                 /* the list, in the action */
    mov     X23(%rsp), %rsi
    shl     $4, %rsi
    add     %rax, %rsi
    mov     $LIBP2P_ACTION_PARTIAL_PEERS, %edi
    call    libp2p_action
    test    %rax, %rax
    jz      9f
    mov     %rax, X25(%rsp)
    mov     LIBP2P_EV_PP_TOPIC_LEN(%rbx), %rdx
    mov     %rdx, LIBP2P_ACT_PL_TOPIC_LEN(%rax)
    mov     X23(%rsp), %rcx
    mov     %rcx, LIBP2P_ACT_PL_COUNT(%rax)
    lea     LIBP2P_ACT_PL_TOPIC(%rax), %rdi
    lea     LIBP2P_EV_PP_TOPIC(%rbx), %rsi
    call    libp2p_copy
    mov     X25(%rsp), %rax
    add     X24(%rsp), %rax
    mov     %rax, X26(%rsp)
    movq    $0, X24(%rsp)
6:  mov     X24(%rsp), %rax
    cmp     X23(%rsp), %rax
    jae     9f
    movl    (%r13,%rax,4), %edi
    call    libp2p_peer_at
    mov     %rax, %rdx
    mov     $ST_PEER_OFF, %edi
    mov     $P_SIZE, %esi
    call    libp2p_handle
    mov     X26(%rsp), %rcx
    mov     %rax, (%rcx)
    mov     X24(%rsp), %rax
    movl    (%r13,%rax,4), %edi
    mov     %r12, %rsi
    call    libp2p_partial_flags
    mov     X26(%rsp), %rcx
    mov     %rax, 8(%rcx)
    addq    $16, X26(%rsp)
    incq    X24(%rsp)
    jmp     6b
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_peers

/*
 * libp2p_on_partial_send(event): PARTIAL_SEND: one PartialMessagesExtension
 * to a connected peer that has the extension, when partial_messages is on.
 * The message goes only to a peer that wants partial messages on the topic.
 * Nothing goes when no metadata or message is left.
 * rbx event, rbp peer, r12 with message, r13 peer index.
 */
LOCAL_FUNCTION libp2p_on_partial_send
    ENTER   0
    mov     %rdi, %rbx
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_PARTIAL_MESSAGES)(%r15)
    je      9f
    mov     LIBP2P_EV_PSEND_PEER(%rbx), %rdi
    call    libp2p_peer
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbp
    testq   $PF_PARTIAL, P_FLAGS(%rbp)
    jz      9f
    mov     %rbp, %rdi
    call    libp2p_peer_idx
    mov     %rax, %r13
    xor     %r12d, %r12d
    cmpq    $0, LIBP2P_EV_PSEND_MSG_LEN(%rbx)
    je      1f
    lea     LIBP2P_EV_PSEND_BYTES(%rbx), %rdi
    mov     LIBP2P_EV_PSEND_TOPIC_LEN(%rbx), %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      1f
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rsi
    mov     %r13, %rdi
    call    libp2p_partial_flags
    and     $LIBP2P_PARTIAL_REQUESTS, %eax
    mov     %rax, %r12
1:  mov     LIBP2P_EV_PSEND_META_LEN(%rbx), %rax
    or      %r12, %rax
    jz      9f
    mov     %rbp, %rdi
    mov     %rbx, %rsi
    mov     %r12, %rdx
    call    libp2p_gs_send_partial
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_send

/*
 * libp2p_on_partial_score(event): the application judged partial message data
 * of a peer in a topic: ACCEPT counts as a first delivery, REJECT as an
 * invalid message.
 * rbx event, rbp peer index.
 */
LOCAL_FUNCTION libp2p_on_partial_score
    ENTER   0
    mov     %rdi, %rbx
    mov     LIBP2P_EV_PSCORE_PEER(%rbx), %rdi
    call    libp2p_peer
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_peer_idx
    mov     %rax, %rbp
    lea     LIBP2P_EV_PSCORE_TOPIC(%rbx), %rdi
    mov     LIBP2P_EV_PSCORE_TOPIC_LEN(%rbx), %rsi
    call    libp2p_topic_find
    test    %rax, %rax
    jz      9f
    mov     %rax, %rdi
    call    libp2p_topic_idx
    mov     %rax, %rsi
    mov     %rbp, %rdi
    cmpq    $LIBP2P_ACCEPT, LIBP2P_EV_PSCORE_RESULT(%rbx)
    jne     1f
    xor     %edx, %edx
    call    libp2p_score_valid
    jmp     9f
1:  call    libp2p_score_invalid
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_score

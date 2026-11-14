/*
 * gossipsub timers of the x86-64 core: validation timeouts, retained
 * scores, the heartbeat (promises, mesh and fanout maintenance, gossip, the
 * message cache windows, the seen cache) and score decay. Included by
 * gossip.s.
 */

/*
 * libp2p_gossip_timers(): messages the application did not judge within
 * validation_ms are dropped (MESSAGE_STATUS dropped); retained scores past
 * retain_score end; the heartbeat and decay run when due. Then a wakeup at
 * the next of these times.
 * rbx slot, rbp slots left, r12 now.
 */
LOCAL_FUNCTION libp2p_gossip_timers
    ENTER   0
    mov     SC_NOW(%r14), %r12
    TABLE   %rbx, ST_PEND_OFF
    mov     ST_PEND_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      3f
    cmpl    $0, PD_STATE(%rbx)
    je      2f
    mov     PD_TIME(%rbx), %rdi
    add     (ST_CONFIG + LIBP2P_CFG_VALIDATION_MS)(%r15), %rdi
    cmp     %rdi, %r12
    jb      11f
    call    libp2p_room
    cmp     $64, %rax
    jb      12f
    mov     %rbx, %rdi
    mov     $LIBP2P_MSG_DROPPED, %esi
    call    libp2p_pend_status
    mov     %rbx, %rdi
    call    libp2p_pend_free
    jmp     2f
11: call    libp2p_wake_at
    jmp     2f
12: mov     %r12, %rdi                      /* no room: next step */
    call    libp2p_wake_at
2:  add     $PD_SIZE, %rbx
    dec     %rbp
    jmp     1b
3:  TABLE   %rbx, ST_PEER_OFF               /* retained scores */
    mov     ST_PEER_COUNT(%r15), %rbp
4:  test    %rbp, %rbp
    jz      5f
    cmpl    $PS_RETAINED, P_STATE(%rbx)
    jne     41f
    mov     P_EXPIRE(%rbx), %rdi
    cmp     %rdi, %r12
    jb      42f
    mov     %rbx, %rdi
    call    libp2p_peer_release
    jmp     41f
42: call    libp2p_wake_at
41: add     $P_SIZE, %rbx
    dec     %rbp
    jmp     4b
5:  cmp     ST_HEARTBEAT_AT(%r15), %r12     /* the heartbeat */
    jb      6f
    call    libp2p_heartbeat
    mov     ST_HEARTBEAT_AT(%r15), %rax
    mov     (ST_CONFIG + LIBP2P_CFG_HEARTBEAT_MS)(%r15), %rcx
    add     %rcx, %rax
    lea     (%r12,%rcx), %rdx
    cmp     %r12, %rax
    cmovbe  %rdx, %rax
    mov     %rax, ST_HEARTBEAT_AT(%r15)
6:  mov     ST_HEARTBEAT_AT(%r15), %rdi
    call    libp2p_wake_at
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_SCORING)(%r15)
    je      9f
    cmp     ST_DECAY_AT(%r15), %r12         /* score decay */
    jb      8f
    call    libp2p_score_decay
    mov     ST_DECAY_AT(%r15), %rax
    mov     (ST_CONFIG + LIBP2P_CFG_DECAY_INTERVAL_MS)(%r15), %rcx
    add     %rcx, %rax
    lea     (%r12,%rcx), %rdx
    cmp     %r12, %rax
    cmovbe  %rdx, %rax
    mov     %rax, ST_DECAY_AT(%r15)
8:  mov     ST_DECAY_AT(%r15), %rdi
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_gossip_timers

/*
 * libp2p_heartbeat(): scores of this heartbeat; IHAVE and IDONTWANT counters reset; broken
 * promises cost a behaviour penalty; mesh maintenance of each topic we
 * subscribe to, fanout maintenance of the others; gossip; then the message
 * cache moves to a new window and old seen entries leave.
 * rbx slot or topic index, rbp count, r12 topic, r13 now.
 */
LOCAL_FUNCTION libp2p_heartbeat
    ENTER   0
    mov     SC_NOW(%r14), %r13
    call    libp2p_score_all
    TABLE   %rbx, ST_PEER_OFF               /* IHAVE and IDONTWANT counters */
    mov     ST_PEER_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      2f
    movq    $0, P_IHAVE_COUNT(%rbx)
    movq    $0, P_IHAVE_IDS(%rbx)
    movq    $0, P_DW_COUNT(%rbx)
    add     $P_SIZE, %rbx
    dec     %rbp
    jmp     1b
2:  TABLE   %rbx, ST_PROMISE_OFF            /* broken promises */
    mov     $LIBP2P_PROMISES, %ebp
3:  test    %rbp, %rbp
    jz      4f
    mov     PR_PEER(%rbx), %rdi
    cmp     $NONE, %rdi
    je      31f
    cmp     PR_DEADLINE(%rbx), %r13
    jb      31f
    movq    $NONE, PR_PEER(%rbx)
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     $1, %esi
    call    libp2p_behaviour_penalty
31: add     $PR_SIZE, %rbx
    dec     %rbp
    jmp     3b
4:  xor     %ebx, %ebx                      /* the topics */
    mov     ST_TOPIC_COUNT(%r15), %rbp
5:  cmp     %rbp, %rbx
    jae     7f
    mov     %rbx, %rdi
    call    libp2p_topic_at
    mov     %rax, %r12
    cmpq    $0, T_USED(%r12)
    je      6f
    testq   $TF_SUBSCRIBED, T_FLAGS(%r12)
    jz      51f
    mov     %rbx, %rdi
    call    libp2p_mesh_maintain
    jmp     52f
51: cmpq    $0, T_FANOUT(%r12)
    je      6f
    mov     %rbx, %rdi
    call    libp2p_fanout_maintain
52: mov     %rbx, %rdi
    call    libp2p_emit_gossip
6:  inc     %rbx
    jmp     5b
7:  incq    ST_HEARTBEATS(%r15)
    call    libp2p_mc_shift
    call    libp2p_seen_expire
    LEAVE   0
END_FUNCTION libp2p_heartbeat

/* libp2p_list_score(list, i) -> xmm0 the heartbeat score of the peer at list[i]. A leaf. */
LOCAL_FUNCTION libp2p_list_score
    UNWIND_END_PROLOGUE
    movl    (%rdi,%rsi,4), %eax
    imul    $P_SIZE, %rax, %rax
    add     ST_PEER_OFF(%r15), %rax
    add     %r15, %rax
    movsd   P_SCORE(%rax), %xmm0
    ret
END_FUNCTION libp2p_list_score

/* libp2p_list_outbound(list, i) -> 1 when the peer at list[i] is outbound. A leaf. */
LOCAL_FUNCTION libp2p_list_outbound
    UNWIND_END_PROLOGUE
    movl    (%rdi,%rsi,4), %eax
    imul    $P_SIZE, %rax, %rax
    add     ST_PEER_OFF(%r15), %rax
    add     %r15, %rax
    mov     P_FLAGS(%rax), %rax
    and     $PF_OUTBOUND, %rax
    ret
END_FUNCTION libp2p_list_outbound

/*
 * libp2p_sort_score(list, count): the list in falling order of score
 * (insertion sort). rbx list, rbp count, r12 i, r13 the value moved, X23 j;
 * 32(%rsp) its score.
 */
LOCAL_FUNCTION libp2p_sort_score
    ENTER   16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $1, %r12d
1:  cmp     %rbp, %r12
    jae     9f
    movl    (%rbx,%r12,4), %r13d
    mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_list_score
    movsd   %xmm0, 32(%rsp)
    mov     %r12, X23(%rsp)
2:  mov     X23(%rsp), %rax
    test    %rax, %rax
    jz      3f
    mov     %rbx, %rdi
    lea     -1(%rax), %rsi
    call    libp2p_list_score
    ucomisd 32(%rsp), %xmm0
    jae     3f
    mov     X23(%rsp), %rax
    lea     -1(%rax), %rcx
    movl    (%rbx,%rcx,4), %edx
    movl    %edx, (%rbx,%rax,4)
    mov     %rcx, X23(%rsp)
    jmp     2b
3:  mov     X23(%rsp), %rax
    movl    %r13d, (%rbx,%rax,4)
    inc     %r12
    jmp     1b
9:  LEAVE   16
END_FUNCTION libp2p_sort_score

/* libp2p_add_from_list(topic index, count): the first count peers of the list join the mesh. rbx topic index, rbp count, r12 list, r13 i. */
LOCAL_FUNCTION libp2p_add_from_list
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    SCR     %r12, SC_LIST
    xor     %r13d, %r13d
1:  cmp     %rbp, %r13
    jae     9f
    movl    (%r12,%r13,4), %edi
    mov     %rbx, %rsi
    call    libp2p_mesh_add
    inc     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_add_from_list

/*
 * libp2p_mesh_maintain(topic index): mesh peers that are not ready or score
 * below 0 leave with PRUNE; below D_low the mesh grows to D; above D_high
 * it shrinks to D, keeping the D_score best and D_out outbound peers;
 * then it takes outbound peers up to D_out; every opportunistic_ticks
 * heartbeats, a mesh whose median score is below the threshold takes peers
 * above the median.
 * rbx topic index, rbp topic, r12 list, r13 count, X23 i, X24 mesh count
 * or peer, X25 a limit.
 */
LOCAL_FUNCTION libp2p_mesh_maintain
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_topic_at
    mov     %rax, %rbp
    SCR     %r12, SC_LIST
    movq    $0, X23(%rsp)                   /* mesh peers not ready or below 0 */
1:  mov     X23(%rsp), %rax
    cmp     ST_PEER_COUNT(%r15), %rax
    jae     3f
    mov     %rax, %rdi
    mov     %rbx, %rsi
    call    libp2p_pt
    testq   $PTF_MESH, PT_FLAGS(%rax)
    jz      2f
    mov     X23(%rsp), %rdi
    call    libp2p_peer_at
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    call    libp2p_gs_ready
    test    %rax, %rax
    jz      11f
    mov     X24(%rsp), %rax
    movsd   P_SCORE(%rax), %xmm0
    xorpd   %xmm1, %xmm1
    ucomisd %xmm0, %xmm1
    jbe     2f
    mov     X23(%rsp), %rdi
    mov     %rbx, %rsi
    mov     (ST_CONFIG + LIBP2P_CFG_PRUNE_BACKOFF_MS)(%r15), %rdx
    call    libp2p_prune_to
11: mov     X23(%rsp), %rdi
    mov     %rbx, %rsi
    call    libp2p_mesh_remove
2:  incq    X23(%rsp)
    jmp     1b
3:  mov     T_MESH(%rbp), %rax              /* too few */
    mov     %rax, X24(%rsp)
    cmp     (ST_CONFIG + LIBP2P_CFG_D_LOW)(%r15), %rax
    jae     4f
    xorpd   %xmm0, %xmm0
    mov     %rbx, %rdi
    xor     %esi, %esi
    mov     $(PTF_MESH | CAND_BACKOFF), %edx
    call    libp2p_candidates
    mov     %rax, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_shuffle
    mov     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %rsi
    sub     X24(%rsp), %rsi
    cmp     %rsi, %r13
    cmovb   %r13, %rsi
    mov     %rbx, %rdi
    call    libp2p_add_from_list
4:  mov     T_MESH(%rbp), %rax              /* too many */
    mov     %rax, X24(%rsp)
    cmp     (ST_CONFIG + LIBP2P_CFG_D_HIGH)(%r15), %rax
    jbe     6f
    movabs  $0xFFF0000000000000, %rax
    movq    %rax, %xmm0
    mov     %rbx, %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_sort_score
    mov     (ST_CONFIG + LIBP2P_CFG_D_SCORE)(%r15), %rax    /* the best D_score stay; the rest in random order */
    cmp     %r13, %rax
    cmovae  %r13, %rax
    lea     (%r12,%rax,4), %rdi
    mov     %r13, %rsi
    sub     %rax, %rsi
    call    libp2p_shuffle
    mov     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %rax          /* kept: list[0..D) */
    mov     %rax, X25(%rsp)
    mov     %r12, %rdi
    mov     %rax, %rsi
    mov     %r13, %rdx
    call    libp2p_keep_outbound
    mov     X25(%rsp), %rax
    mov     %rax, X23(%rsp)
5:  mov     X23(%rsp), %rax
    cmp     %r13, %rax
    jae     6f
    movl    (%r12,%rax,4), %edi
    mov     %rbx, %rsi
    mov     (ST_CONFIG + LIBP2P_CFG_PRUNE_BACKOFF_MS)(%r15), %rdx
    call    libp2p_prune_to
    mov     X23(%rsp), %rax
    movl    (%r12,%rax,4), %edi
    mov     %rbx, %rsi
    call    libp2p_mesh_remove
    incq    X23(%rsp)
    jmp     5b
6:  mov     T_MESH(%rbp), %rax              /* outbound quota */
    mov     %rax, X24(%rsp)
    cmp     (ST_CONFIG + LIBP2P_CFG_D_LOW)(%r15), %rax
    jb      7f
    movabs  $0xFFF0000000000000, %rax
    movq    %rax, %xmm0
    mov     %rbx, %rdi
    mov     $(PTF_MESH | CAND_OUTBOUND), %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     (ST_CONFIG + LIBP2P_CFG_D_OUT)(%r15), %rcx
    sub     %rax, %rcx
    jbe     7f
    mov     %rcx, X25(%rsp)
    xorpd   %xmm0, %xmm0
    mov     %rbx, %rdi
    mov     $CAND_OUTBOUND, %esi
    mov     $(PTF_MESH | CAND_BACKOFF), %edx
    call    libp2p_candidates
    mov     %rax, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_shuffle
    mov     X25(%rsp), %rsi
    cmp     %rsi, %r13
    cmovb   %r13, %rsi
    mov     %rbx, %rdi
    call    libp2p_add_from_list
7:  mov     (ST_CONFIG + LIBP2P_CFG_OPPORTUNISTIC_TICKS)(%r15), %rcx    /* opportunistic grafting */
    test    %rcx, %rcx
    jz      9f
    mov     ST_HEARTBEATS(%r15), %rax
    xor     %edx, %edx
    div     %rcx
    test    %rdx, %rdx
    jnz     9f
    mov     T_MESH(%rbp), %rax
    mov     %rax, X24(%rsp)
    cmp     $1, %rax
    jbe     9f
    movabs  $0xFFF0000000000000, %rax
    movq    %rax, %xmm0
    mov     %rbx, %rdi
    mov     $PTF_MESH, %esi
    xor     %edx, %edx
    call    libp2p_candidates
    mov     %rax, %r13
    cmp     $1, %r13
    jbe     9f
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_sort_score
    mov     %r12, %rdi
    mov     %r13, %rsi
    shr     $1, %rsi
    call    libp2p_list_score                   /* the median */
    movsd   (ST_CONFIG + LIBP2P_CFG_OPPORTUNISTIC_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm1, %xmm0
    jae     9f
    movq    %xmm0, %rax                     /* above the median: the next double up is the floor */
    inc     %rax
    xorpd   %xmm1, %xmm1
    ucomisd %xmm1, %xmm0
    jae     71f
    sub     $2, %rax
71: movq    %rax, %xmm0
    mov     %rbx, %rdi
    xor     %esi, %esi
    mov     $(PTF_MESH | CAND_BACKOFF), %edx
    call    libp2p_candidates
    mov     %rax, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_shuffle
    mov     (ST_CONFIG + LIBP2P_CFG_OPPORTUNISTIC_PEERS)(%r15), %rsi
    cmp     %rsi, %r13
    cmovb   %r13, %rsi
    mov     %rbx, %rdi
    call    libp2p_add_from_list
9:  LEAVE   0
END_FUNCTION libp2p_mesh_maintain

/*
 * libp2p_keep_outbound(list, kept, count): when list[0..kept) has fewer than
 * D_out outbound peers, outbound peers from list[kept..count) take the
 * places of the last inbound kept peers.
 * rbx list, rbp kept, r12 count, r13 outbound kept, X23 i, X24 j.
 */
LOCAL_FUNCTION libp2p_keep_outbound
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    cmp     %rdx, %rbp
    cmovae  %rdx, %rbp
    mov     %rdx, %r12
    xor     %r13d, %r13d
    movq    $0, X23(%rsp)
1:  mov     X23(%rsp), %rsi
    cmp     %rbp, %rsi
    jae     2f
    mov     %rbx, %rdi
    call    libp2p_list_outbound
    add     %rax, %r13
    incq    X23(%rsp)
    jmp     1b
2:  mov     %rbp, X23(%rsp)                 /* outbound candidates beyond the kept part */
    mov     %rbp, X24(%rsp)                 /* the next kept place to give up, from the end */
3:  cmp     (ST_CONFIG + LIBP2P_CFG_D_OUT)(%r15), %r13
    jae     9f
    mov     X23(%rsp), %rsi
    cmp     %r12, %rsi
    jae     9f
    mov     %rbx, %rdi
    call    libp2p_list_outbound
    test    %rax, %rax
    jz      5f
4:  mov     X24(%rsp), %rsi                 /* an inbound kept peer to swap out */
    test    %rsi, %rsi
    jz      9f
    dec     %rsi
    mov     %rsi, X24(%rsp)
    mov     %rbx, %rdi
    call    libp2p_list_outbound
    test    %rax, %rax
    jnz     4b
    mov     X23(%rsp), %rax
    mov     X24(%rsp), %rcx
    movl    (%rbx,%rax,4), %edx
    movl    (%rbx,%rcx,4), %esi
    movl    %edx, (%rbx,%rcx,4)
    movl    %esi, (%rbx,%rax,4)
    inc     %r13
5:  incq    X23(%rsp)
    jmp     3b
9:  LEAVE   0
END_FUNCTION libp2p_keep_outbound

/*
 * libp2p_fanout_maintain(topic index): a fanout unused for fanout_ttl ends;
 * else peers below publish_threshold leave it and it grows to D.
 * rbx topic index, rbp topic, r12 peer index then the list, r13 entry then
 * the count, X23 peer then i, X24 places to fill.
 */
LOCAL_FUNCTION libp2p_fanout_maintain
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_topic_at
    mov     %rax, %rbp
    mov     SC_NOW(%r14), %rax
    sub     T_FANOUT_LAST(%rbp), %rax
    cmp     (ST_CONFIG + LIBP2P_CFG_FANOUT_TTL_MS)(%r15), %rax
    jbe     1f
    xchg    %rbx, %rbp                      /* libp2p_fanout_clear_topic takes rbx topic, rbp index */
    call    libp2p_fanout_clear_topic
    mov     %rbx, %rdi
    call    libp2p_topic_tidy
    jmp     9f
1:  xor     %r12d, %r12d
2:  cmp     ST_PEER_COUNT(%r15), %r12
    jae     4f
    mov     %r12, %rdi
    mov     %rbx, %rsi
    call    libp2p_pt
    mov     %rax, %r13
    testq   $PTF_FANOUT, PT_FLAGS(%r13)
    jz      3f
    mov     %r12, %rdi
    call    libp2p_peer_at
    mov     %rax, X23(%rsp)
    mov     %rax, %rdi
    call    libp2p_gs_ready
    test    %rax, %rax
    jz      21f
    mov     X23(%rsp), %rax
    movsd   P_SCORE(%rax), %xmm0
    movsd   (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(%r15), %xmm1
    ucomisd %xmm0, %xmm1
    jbe     3f
21: andq    $~PTF_FANOUT, PT_FLAGS(%r13)
    decq    T_FANOUT(%rbp)
3:  inc     %r12
    jmp     2b
4:  mov     (ST_CONFIG + LIBP2P_CFG_D)(%r15), %rax
    sub     T_FANOUT(%rbp), %rax
    jbe     9f
    mov     %rax, X24(%rsp)
    movsd   (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(%r15), %xmm0
    mov     %rbx, %rdi
    xor     %esi, %esi
    mov     $PTF_FANOUT, %edx
    call    libp2p_candidates
    mov     %rax, %r13
    SCR     %r12, SC_LIST
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    libp2p_shuffle
    mov     X24(%rsp), %rax
    cmp     %rax, %r13
    cmovae  %rax, %r13
    movq    $0, X23(%rsp)
5:  mov     X23(%rsp), %rax
    cmp     %r13, %rax
    jae     9f
    movl    (%r12,%rax,4), %edi
    mov     %rbx, %rsi
    call    libp2p_pt
    orq     $PTF_FANOUT, PT_FLAGS(%rax)
    incq    T_FANOUT(%rbp)
    incq    X23(%rsp)
    jmp     5b
9:  LEAVE   0
END_FUNCTION libp2p_fanout_maintain

/*
 * libp2p_emit_gossip(topic index): the IDs of the topic's messages in the last
 * mcache_gossip windows (at most max_ihave_length, chosen at random) go as
 * IHAVE to max(D_lazy, gossip_factor x candidates) peers at random that are
 * not in the mesh or fanout and are at or above gossip_threshold.
 * rbx topic index, rbp topic, r12 IDs, r13 ID count, X23 i, X24 list or
 * the count left, X25 peers, X26 the first window.
 */
LOCAL_FUNCTION libp2p_emit_gossip
    ENTER   0
    mov     %rdi, %rbx
    call    libp2p_topic_at
    mov     %rax, %rbp
    SCR     %r12, SC_IDS
    xor     %r13d, %r13d
    mov     ST_HEARTBEATS(%r15), %rax       /* windows from heartbeats - mcache_gossip + 1 */
    mov     (ST_CONFIG + LIBP2P_CFG_MCACHE_GOSSIP)(%r15), %rcx
    xor     %edx, %edx
    sub     %rcx, %rax
    cmovb   %rdx, %rax
    inc     %rax
    test    %rcx, %rcx
    jnz     1f
    mov     $NONE, %rax                     /* mcache_gossip 0: none */
1:  mov     %rax, X26(%rsp)
    movq    $0, X23(%rsp)
2:  mov     X23(%rsp), %rax
    cmp     ST_MC_COUNT(%r15), %rax
    jae     4f
    cmp     $(SC_IDS_SIZE / 16), %r13
    jae     4f
    call    libp2p_mc_args
    mov     X23(%rsp), %rax
    imul    %rcx, %rax
    add     %rdx, %rax
    cmpq    $0, MC_USED(%rax)
    je      3f
    cmp     MC_TOPIC(%rax), %rbx
    jne     3f
    mov     MC_WINDOW(%rax), %rcx
    cmp     X26(%rsp), %rcx
    jb      3f
    lea     MC_ID(%rax), %rcx
    mov     MC_ID_LEN(%rax), %rdx
    mov     %r13, %rsi
    shl     $4, %rsi
    add     %r12, %rsi
    mov     %rcx, (%rsi)
    mov     %rdx, 8(%rsi)
    inc     %r13
3:  incq    X23(%rsp)
    jmp     2b
4:  test    %r13, %r13
    jz      9f
    mov     (ST_CONFIG + LIBP2P_CFG_MAX_IHAVE_LENGTH)(%r15), %rax   /* at most max_ihave_length of them, at random */
    cmp     %rax, %r13
    jbe     5f
    mov     %rax, X23(%rsp)
    mov     %r13, X24(%rsp)
41: mov     X24(%rsp), %rdi                 /* move random IDs to the front, then cut */
    cmp     X23(%rsp), %rdi
    jbe     42f
    call    libp2p_random_below
    decq    X24(%rsp)
    shl     $4, %rax
    add     %r12, %rax
    mov     X24(%rsp), %rcx
    shl     $4, %rcx
    add     %r12, %rcx
    mov     (%rax), %rdx
    mov     8(%rax), %rsi
    mov     (%rcx), %rdi
    mov     8(%rcx), %r8
    mov     %rdi, (%rax)
    mov     %r8, 8(%rax)
    mov     %rdx, (%rcx)
    mov     %rsi, 8(%rcx)
    jmp     41b
42: mov     X23(%rsp), %r13
5:  movsd   (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(%r15), %xmm0
    mov     %rbx, %rdi
    xor     %esi, %esi
    mov     $(PTF_MESH | PTF_FANOUT), %edx
    call    libp2p_candidates
    mov     %rax, X25(%rsp)
    test    %rax, %rax
    jz      9f
    SCR     %rax, SC_LIST
    mov     %rax, X24(%rsp)
    mov     %rax, %rdi
    mov     X25(%rsp), %rsi
    call    libp2p_shuffle
    cvtsi2sdq X25(%rsp), %xmm0              /* max(D_lazy, gossip_factor x candidates) */
    mulsd   (ST_CONFIG + LIBP2P_CFG_GOSSIP_FACTOR)(%r15), %xmm0
    xor     %eax, %eax                      /* toward zero to an unsigned: 0 when not above 0 */
    xorpd   %xmm1, %xmm1
    ucomisd %xmm1, %xmm0
    jbe     51f
    cvttsd2si %xmm0, %rax
51: mov     (ST_CONFIG + LIBP2P_CFG_D_LAZY)(%r15), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     X25(%rsp), %rcx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     %rax, X25(%rsp)
    movq    $0, X23(%rsp)
6:  mov     X23(%rsp), %rax
    cmp     X25(%rsp), %rax
    jae     9f
    mov     X24(%rsp), %rcx
    movl    (%rcx,%rax,4), %edi
    call    libp2p_peer_at
    mov     %rax, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     $1, %r8d
    call    libp2p_gs_send_ids
    incq    X23(%rsp)
    jmp     6b
9:  LEAVE   0
END_FUNCTION libp2p_emit_gossip

/*
 * gossipsub v1.1 peer scores of the x86-64 core: the score function, the
 * counters of P2, P3, P3b, P4 and P7, and their decay. f64 arithmetic in
 * SSE2 scalar registers. A product and a sum round apart (mulsd, then
 * addsd), so every ISA gets the same scores. Included by gossip.s.
 */

/*
 * dst = the smaller of dst and src, as ARM64 fmin: NaN when either is NaN
 * (minsd gives src), and -0 below +0 (minsd gives src for two zeros). src
 * is an xmm register or memory; tmp an xmm register, not dst.
 */
.macro FMIN src, dst, tmp
    movsd   \src, \tmp
    ucomisd \tmp, \dst
    jp      1001f
    jne     1002f
    orpd    \tmp, \dst                    /* equal: two zeros give -0 when either is -0 */
    jmp     1003f
1001: addsd \tmp, \dst                    /* a NaN operand gives NaN */
    jmp     1003f
1002: minsd \tmp, \dst
1003:
.endm

/* libp2p_params(topic index) -> the TopicParams of a topic with parameters, or 0. A leaf. */
LOCAL_FUNCTION libp2p_params
    UNWIND_END_PROLOGUE
    imul    $T_SIZE, %rdi, %rax
    add     ST_TOPIC_OFF(%r15), %rax
    add     %r15, %rax
    cmpq    $0, T_USED(%rax)
    je      8f
    testq   $TF_PARAMS, T_FLAGS(%rax)
    jz      8f
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_SCORING)(%r15)
    je      8f
    add     $T_PARAMS, %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION libp2p_params

/*
 * libp2p_score(peer) -> xmm0 the score of gossipsub v1.1:
 * TopicCap(sum of topic weight x (w1 P1 + w2 P2 + w3 P3 + w3b P3b + w4 P4))
 * + w5 P5 + w6 P6 + w7 P7. 0 when scoring is off.
 * rbx peer, rbp peer index, r12 topic index, r13 topics, X23 now, X24
 * params, X25 entry; 32(%rsp) the total. Within a topic: r10 entry,
 * r11 params, xmm2 the topic score.
 */
LOCAL_FUNCTION libp2p_score
    ENTER   16
    mov     %rdi, %rbx
    xorpd   %xmm0, %xmm0
    movsd   %xmm0, 32(%rsp)
    cmpq    $0, (ST_CONFIG + LIBP2P_CFG_SCORING)(%r15)
    je      90f
    call    libp2p_peer_idx
    mov     %rax, %rbp
    mov     SC_NOW(%r14), %rax
    mov     %rax, X23(%rsp)
    xor     %r12d, %r12d
    mov     ST_TOPIC_COUNT(%r15), %r13
1:  cmp     %r13, %r12
    jae     5f
    mov     %r12, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      4f
    mov     %rax, X24(%rsp)
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pt
    mov     %rax, X25(%rsp)
    mov     X24(%rsp), %r11
    mov     X25(%rsp), %r10
    xorpd   %xmm2, %xmm2
    testq   $PTF_MESH, PT_FLAGS(%r10)
    jz      2f
    mov     X23(%rsp), %r8                  /* P1: time in mesh, in quanta, up to the cap */
    sub     PT_GRAFT_TIME(%r10), %r8
    mov     LIBP2P_TP_TIME_QUANTUM_MS(%r11), %r9
    test    %r9, %r9
    jnz     11f
    mov     $1, %r9d
11: mov     %r8, %rax
    xor     %edx, %edx
    div     %r9
    cvtsi2sdq %rax, %xmm0
    FMIN    LIBP2P_TP_TIME_CAP(%r11), %xmm0, %xmm1
    mulsd   LIBP2P_TP_TIME_WEIGHT(%r11), %xmm0
    addsd   %xmm0, %xmm2
    cmp     LIBP2P_TP_MESH_ACTIVATION_MS(%r11), %r8     /* P3: delivery deficit, once active */
    jbe     2f
    movsd   PT_MESH_DEL(%r10), %xmm0
    movsd   LIBP2P_TP_MESH_THRESHOLD(%r11), %xmm1
    ucomisd %xmm0, %xmm1
    jbe     2f
    subsd   %xmm0, %xmm1
    mulsd   %xmm1, %xmm1
    mulsd   LIBP2P_TP_MESH_WEIGHT(%r11), %xmm1
    addsd   %xmm1, %xmm2
2:  movsd   PT_FIRST(%r10), %xmm0           /* P2 */
    mulsd   LIBP2P_TP_FIRST_WEIGHT(%r11), %xmm0
    addsd   %xmm0, %xmm2
    movsd   PT_MESH_FAIL(%r10), %xmm0       /* P3b */
    mulsd   LIBP2P_TP_FAIL_WEIGHT(%r11), %xmm0
    addsd   %xmm0, %xmm2
    movsd   PT_INVALID(%r10), %xmm0         /* P4: squared */
    mulsd   %xmm0, %xmm0
    mulsd   LIBP2P_TP_INVALID_WEIGHT(%r11), %xmm0
    addsd   %xmm0, %xmm2
    mulsd   LIBP2P_TP_WEIGHT(%r11), %xmm2
    movsd   32(%rsp), %xmm0
    addsd   %xmm2, %xmm0
    movsd   %xmm0, 32(%rsp)
4:  inc     %r12
    jmp     1b
5:  movsd   32(%rsp), %xmm0
    movsd   (ST_CONFIG + LIBP2P_CFG_TOPIC_CAP)(%r15), %xmm1
    xorpd   %xmm2, %xmm2
    ucomisd %xmm2, %xmm1
    jbe     6f
    FMIN    %xmm1, %xmm0, %xmm3
6:  movsd   P_APP_SCORE(%rbx), %xmm1        /* P5 */
    mulsd   (ST_CONFIG + LIBP2P_CFG_APP_WEIGHT)(%r15), %xmm1
    addsd   %xmm1, %xmm0
    movsd   %xmm0, 32(%rsp)
    mov     %rbx, %rdi                      /* P6: peers on the same IP above the threshold, squared */
    call    libp2p_ip_count
    movsd   32(%rsp), %xmm0
    mov     (ST_CONFIG + LIBP2P_CFG_IP_THRESHOLD)(%r15), %rcx
    cmp     %rcx, %rax
    jbe     7f
    sub     %rcx, %rax
    cvtsi2sdq %rax, %xmm1
    mulsd   %xmm1, %xmm1
    mulsd   (ST_CONFIG + LIBP2P_CFG_IP_WEIGHT)(%r15), %xmm1
    addsd   %xmm1, %xmm0
7:  movsd   P_BEHAVIOUR(%rbx), %xmm1        /* P7: above the threshold, squared */
    movsd   (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_THRESHOLD)(%r15), %xmm2
    ucomisd %xmm2, %xmm1
    jbe     91f
    subsd   %xmm2, %xmm1
    mulsd   %xmm1, %xmm1
    mulsd   (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_WEIGHT)(%r15), %xmm1
    addsd   %xmm1, %xmm0
    jmp     91f
90: xorpd   %xmm0, %xmm0
91: LEAVE   16
END_FUNCTION libp2p_score

/* libp2p_ip_count(peer) -> the connected peers with the same IP family and address, itself included. A leaf. */
LOCAL_FUNCTION libp2p_ip_count
    UNWIND_END_PROLOGUE
    mov     ST_PEER_OFF(%r15), %rcx
    add     %r15, %rcx
    mov     ST_PEER_COUNT(%r15), %rdx
    xor     %eax, %eax
1:  test    %rdx, %rdx
    jz      9f
    cmpl    $PS_CONNECTED, P_STATE(%rcx)
    jne     2f
    mov     P_IP_FAMILY(%rcx), %r8
    cmp     P_IP_FAMILY(%rdi), %r8
    jne     2f
    mov     P_IP(%rcx), %r8
    cmp     P_IP(%rdi), %r8
    jne     2f
    mov     (P_IP + 8)(%rcx), %r8
    cmp     (P_IP + 8)(%rdi), %r8
    jne     2f
    inc     %rax
2:  add     $P_SIZE, %rcx
    dec     %rdx
    jmp     1b
9:  ret
END_FUNCTION libp2p_ip_count

/* libp2p_score_all(): every connected peer's score, kept in its slot for this step. rbx peer, rbp left. */
LOCAL_FUNCTION libp2p_score_all
    ENTER   0
    TABLE   %rbx, ST_PEER_OFF
    mov     ST_PEER_COUNT(%r15), %rbp
1:  test    %rbp, %rbp
    jz      9f
    cmpl    $PS_CONNECTED, P_STATE(%rbx)
    jne     2f
    mov     %rbx, %rdi
    call    libp2p_score
    movsd   %xmm0, P_SCORE(%rbx)
2:  add     $P_SIZE, %rbx
    dec     %rbp
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_score_all

/* libp2p_behaviour_penalty(peer, count): P7 counter += count. A leaf. */
LOCAL_FUNCTION libp2p_behaviour_penalty
    UNWIND_END_PROLOGUE
    cvtsi2sdq %rsi, %xmm1
    movsd   P_BEHAVIOUR(%rdi), %xmm0
    addsd   %xmm1, %xmm0
    movsd   %xmm0, P_BEHAVIOUR(%rdi)
    ret
END_FUNCTION libp2p_behaviour_penalty

/* libp2p_score_invalid(peer index, topic index): an invalid message of the peer in the topic: P4 counter + 1. */
LOCAL_FUNCTION libp2p_score_invalid
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rsi, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    movabs  $0x3FF0000000000000, %rcx       /* 1.0 */
    movq    %rcx, %xmm1
    movsd   PT_INVALID(%rax), %xmm0
    addsd   %xmm1, %xmm0
    movsd   %xmm0, PT_INVALID(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_score_invalid

/*
 * libp2p_score_delivery(peer index, topic index, first): a valid delivery of
 * the peer in the topic: with first, P2 + 1 up to its cap; in the mesh,
 * P3 + 1 up to its cap. rbx peer index, rbp topic index, r12 first,
 * r13 params.
 */
LOCAL_FUNCTION libp2p_score_delivery
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rsi, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    movabs  $0x3FF0000000000000, %rcx       /* 1.0 */
    movq    %rcx, %xmm2
    test    %r12, %r12
    jz      1f
    movsd   PT_FIRST(%rax), %xmm0
    addsd   %xmm2, %xmm0
    FMIN    LIBP2P_TP_FIRST_CAP(%r13), %xmm0, %xmm3
    movsd   %xmm0, PT_FIRST(%rax)
1:  testq   $PTF_MESH, PT_FLAGS(%rax)
    jz      9f
    movsd   PT_MESH_DEL(%rax), %xmm0
    addsd   %xmm2, %xmm0
    FMIN    LIBP2P_TP_MESH_CAP(%r13), %xmm0, %xmm3
    movsd   %xmm0, PT_MESH_DEL(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_score_delivery

/*
 * libp2p_score_valid(peer index, topic index, seen): an accepted message: the
 * first delivery of its sender, and mesh deliveries of the peers that sent
 * it while it was judged. rbx peer index, rbp topic index, r12 seen,
 * r13 deliverers left, X23 the next.
 */
LOCAL_FUNCTION libp2p_score_valid
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     $1, %edx
    call    libp2p_score_delivery
    test    %r12, %r12
    jz      9f
    movl    SN_COUNT(%r12), %r13d
    lea     SN_PEERS(%r12), %rax
    mov     %rax, X23(%rsp)
1:  test    %r13, %r13
    jz      9f
    mov     X23(%rsp), %rax
    movzwl  (%rax), %edi
    add     $2, %rax
    mov     %rax, X23(%rsp)
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    libp2p_score_delivery
    dec     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_score_valid

/* libp2p_score_rejected(peer index, topic index, seen): a rejected message: an invalid message of its sender and of the peers that sent it while it was judged. */
LOCAL_FUNCTION libp2p_score_rejected
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    call    libp2p_score_invalid
    test    %r12, %r12
    jz      9f
    movl    SN_COUNT(%r12), %r13d
    lea     SN_PEERS(%r12), %rax
    mov     %rax, X23(%rsp)
1:  test    %r13, %r13
    jz      9f
    mov     X23(%rsp), %rax
    movzwl  (%rax), %edi
    add     $2, %rax
    mov     %rax, X23(%rsp)
    mov     %rbp, %rsi
    call    libp2p_score_invalid
    dec     %r13
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_score_rejected

/*
 * libp2p_score_duplicate(peer index, seen): a message the peer sent that was
 * seen before. Still judged: the peer is kept as a deliverer (up to 12).
 * Valid: a mesh delivery when it came within the mesh delivery window of
 * the validation. Invalid: an invalid message of the peer.
 * rbx peer index, rbp seen, r12 topic index.
 */
LOCAL_FUNCTION libp2p_score_duplicate
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    movl    SN_TOPIC(%rbp), %r12d
    mov     SN_STATUS(%rbp), %rax
    cmp     $SS_PENDING, %rax
    jne     2f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_seen_delivered
    test    %rax, %rax
    jnz     9f
    movl    SN_COUNT(%rbp), %eax
    cmp     $LIBP2P_MAX_DELIVERERS, %rax
    jae     9f
    movw    %bx, SN_PEERS(%rbp,%rax,2)
    inc     %eax
    movl    %eax, SN_COUNT(%rbp)
    jmp     9f
2:  cmp     $SS_VALID, %rax
    jne     3f
    mov     %r12, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      9f
    mov     SC_NOW(%r14), %rcx
    sub     SN_VALIDATED(%rbp), %rcx
    cmp     LIBP2P_TP_MESH_WINDOW_MS(%rax), %rcx
    ja      9f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    xor     %edx, %edx
    call    libp2p_score_delivery
    jmp     9f
3:  cmp     $SS_INVALID, %rax
    jne     9f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    call    libp2p_score_invalid
9:  LEAVE   0
END_FUNCTION libp2p_score_duplicate

/*
 * libp2p_score_mesh_leave(peer index, topic index): the peer leaves our mesh:
 * with P3 active and below its threshold, P3b += the deficit squared.
 * rbx peer index, rbp topic index, r12 params.
 */
LOCAL_FUNCTION libp2p_score_mesh_leave
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rsi, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      9f
    mov     %rax, %r12
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    libp2p_pt
    testq   $PTF_MESH, PT_FLAGS(%rax)
    jz      9f
    mov     SC_NOW(%r14), %rcx
    sub     PT_GRAFT_TIME(%rax), %rcx
    cmp     LIBP2P_TP_MESH_ACTIVATION_MS(%r12), %rcx
    jbe     9f
    movsd   PT_MESH_DEL(%rax), %xmm0
    movsd   LIBP2P_TP_MESH_THRESHOLD(%r12), %xmm1
    ucomisd %xmm0, %xmm1
    jbe     9f
    subsd   %xmm0, %xmm1
    mulsd   %xmm1, %xmm1
    addsd   PT_MESH_FAIL(%rax), %xmm1
    movsd   %xmm1, PT_MESH_FAIL(%rax)
9:  LEAVE   0
END_FUNCTION libp2p_score_mesh_leave

/* libp2p_decay(address, factor in xmm0): the f64 at address times the factor, 0 below decay_to_zero. A leaf. */
LOCAL_FUNCTION libp2p_decay
    UNWIND_END_PROLOGUE
    movsd   (%rdi), %xmm1
    mulsd   %xmm0, %xmm1
    movsd   (ST_CONFIG + LIBP2P_CFG_DECAY_TO_ZERO)(%r15), %xmm2
    movq    %xmm1, %rcx                     /* the absolute value */
    movabs  $0x7FFFFFFFFFFFFFFF, %rax
    and     %rax, %rcx
    movq    %rcx, %xmm3
    ucomisd %xmm3, %xmm2
    jbe     1f
    xorpd   %xmm1, %xmm1
1:  movsd   %xmm1, (%rdi)
    ret
END_FUNCTION libp2p_decay

/*
 * libp2p_score_decay(): every decay_interval: P2, P3, P3b and P4 of each peer
 * (connected or retained) in each topic with parameters, and P7, times
 * their decay factors.
 * rbx peer, rbp peer index, r12 topic index, r13 params, X23 entry.
 */
LOCAL_FUNCTION libp2p_score_decay
    ENTER   0
    xor     %ebp, %ebp
1:  cmp     ST_PEER_COUNT(%r15), %rbp
    jae     9f
    mov     %rbp, %rdi
    call    libp2p_peer_at
    mov     %rax, %rbx
    cmpl    $0, P_STATE(%rbx)
    je      4f
    xor     %r12d, %r12d
2:  cmp     ST_TOPIC_COUNT(%r15), %r12
    jae     3f
    mov     %r12, %rdi
    call    libp2p_params
    test    %rax, %rax
    jz      21f
    mov     %rax, %r13
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    libp2p_pt
    mov     %rax, X23(%rsp)
    movsd   LIBP2P_TP_FIRST_DECAY(%r13), %xmm0
    lea     PT_FIRST(%rax), %rdi
    call    libp2p_decay
    movsd   LIBP2P_TP_MESH_DECAY(%r13), %xmm0
    mov     X23(%rsp), %rdi
    add     $PT_MESH_DEL, %rdi
    call    libp2p_decay
    movsd   LIBP2P_TP_FAIL_DECAY(%r13), %xmm0
    mov     X23(%rsp), %rdi
    add     $PT_MESH_FAIL, %rdi
    call    libp2p_decay
    movsd   LIBP2P_TP_INVALID_DECAY(%r13), %xmm0
    mov     X23(%rsp), %rdi
    add     $PT_INVALID, %rdi
    call    libp2p_decay
21: inc     %r12
    jmp     2b
3:  movsd   (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_DECAY)(%r15), %xmm0
    lea     P_BEHAVIOUR(%rbx), %rdi
    call    libp2p_decay
4:  inc     %rbp
    jmp     1b
9:  LEAVE   0
END_FUNCTION libp2p_score_decay

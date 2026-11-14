/*
 * gossipsub v1.1 peer scores of the ARM64 core: the score function, the
 * counters of P2, P3, P3b, P4 and P7, and their decay. f64 arithmetic in
 * d0 to d7 and d16 to d31 only. A product and a sum round apart (fmul, then
 * fadd), so every ISA gets the same scores. Included by gossip.s.
 */

/* libp2p_params(topic index) -> the TopicParams of a topic with parameters, or 0. A leaf. */
LOCAL_FUNCTION libp2p_params
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_TOPIC_OFF]
    add     x1, x27, x1
    mov     x2, #T_SIZE
    madd    x1, x0, x2, x1
    ldr     x2, [x1, #T_USED]
    cbz     x2, 8f
    ldr     x2, [x1, #T_FLAGS]
    tst     x2, #TF_PARAMS
    b.eq    8f
    ldr     x2, [x27, #(ST_CONFIG + LIBP2P_CFG_SCORING)]
    cbz     x2, 8f
    add     x0, x1, #T_PARAMS
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_params

/*
 * libp2p_score(peer) -> d0 the score of gossipsub v1.1:
 * TopicCap(sum of topic weight x (w1 P1 + w2 P2 + w3 P3 + w3b P3b + w4 P4))
 * + w5 P5 + w6 P6 + w7 P7. 0 when scoring is off.
 * x19 peer, x20 peer index, x21 topic index, x22 topics, x23 now.
 * d16 total, d17 topic score.
 */
LOCAL_FUNCTION libp2p_score
    ENTER   16
    mov     x19, x0
    fmov    d16, xzr
    CFG     x9, LIBP2P_CFG_SCORING
    cbz     x9, 90f
    bl      libp2p_peer_idx
    mov     x20, x0
    ldr     x23, [x28, #SC_NOW]
    mov     x21, #0
    ldr     x22, [x27, #ST_TOPIC_COUNT]
1:  cmp     x21, x22
    b.hs    5f
    mov     x0, x21
    bl      libp2p_params
    cbz     x0, 4f
    mov     x24, x0
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_pt
    mov     x25, x0
    fmov    d17, xzr
    ldr     x9, [x25, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    2f
    ldr     x10, [x25, #PT_GRAFT_TIME]      /* P1: time in mesh, in quanta, up to the cap */
    sub     x10, x23, x10
    ldr     x11, [x24, #LIBP2P_TP_TIME_QUANTUM_MS]
    cmp     x11, #0
    csinc   x11, x11, xzr, ne
    udiv    x12, x10, x11
    ucvtf   d0, x12
    ldr     d1, [x24, #LIBP2P_TP_TIME_CAP]
    fmin    d0, d0, d1
    ldr     d1, [x24, #LIBP2P_TP_TIME_WEIGHT]
    fmul    d7, d0, d1
    fadd    d17, d17, d7
    ldr     x11, [x24, #LIBP2P_TP_MESH_ACTIVATION_MS] /* P3: delivery deficit, once active */
    cmp     x10, x11
    b.ls    2f
    ldr     d0, [x25, #PT_MESH_DEL]
    ldr     d1, [x24, #LIBP2P_TP_MESH_THRESHOLD]
    fcmp    d0, d1
    b.pl    2f
    fsub    d0, d1, d0
    fmul    d0, d0, d0
    ldr     d1, [x24, #LIBP2P_TP_MESH_WEIGHT]
    fmul    d7, d0, d1
    fadd    d17, d17, d7
2:  ldr     d0, [x25, #PT_FIRST]            /* P2 */
    ldr     d1, [x24, #LIBP2P_TP_FIRST_WEIGHT]
    fmul    d7, d0, d1
    fadd    d17, d17, d7
    ldr     d0, [x25, #PT_MESH_FAIL]        /* P3b */
    ldr     d1, [x24, #LIBP2P_TP_FAIL_WEIGHT]
    fmul    d7, d0, d1
    fadd    d17, d17, d7
    ldr     d0, [x25, #PT_INVALID]          /* P4: squared */
    fmul    d0, d0, d0
    ldr     d1, [x24, #LIBP2P_TP_INVALID_WEIGHT]
    fmul    d7, d0, d1
    fadd    d17, d17, d7
    ldr     d1, [x24, #LIBP2P_TP_WEIGHT]
    fmul    d7, d17, d1
    fadd    d16, d16, d7
4:  add     x21, x21, #1
    b       1b
5:  ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_TOPIC_CAP)]
    fcmp    d1, #0.0
    b.le    6f
    fmin    d16, d16, d1
6:  ldr     d0, [x19, #P_APP_SCORE]         /* P5 */
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_APP_WEIGHT)]
    fmul    d7, d0, d1
    fadd    d16, d16, d7
    str     d16, [sp, #96]
    mov     x0, x19                         /* P6: peers on the same IP above the threshold, squared */
    bl      libp2p_ip_count
    ldr     d16, [sp, #96]
    CFG     x9, LIBP2P_CFG_IP_THRESHOLD
    cmp     x0, x9
    b.ls    7f
    sub     x0, x0, x9
    ucvtf   d0, x0
    fmul    d0, d0, d0
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_IP_WEIGHT)]
    fmul    d7, d0, d1
    fadd    d16, d16, d7
7:  ldr     d0, [x19, #P_BEHAVIOUR]         /* P7: above the threshold, squared */
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_THRESHOLD)]
    fcmp    d0, d1
    b.le    90f
    fsub    d0, d0, d1
    fmul    d0, d0, d0
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_WEIGHT)]
    fmul    d7, d0, d1
    fadd    d16, d16, d7
90: fmov    d0, d16
    LEAVE   16
END_FUNCTION libp2p_score

/* libp2p_ip_count(peer) -> the connected peers with the same IP family and address, itself included. */
LOCAL_FUNCTION libp2p_ip_count
    ENTER   0
    mov     x19, x0
    TABLE   x20, ST_PEER_OFF
    ldr     x21, [x27, #ST_PEER_COUNT]
    mov     x22, #0
1:  cbz     x21, 9f
    ldr     w9, [x20, #P_STATE]
    cmp     w9, #PS_CONNECTED
    b.ne    2f
    ldr     x9, [x20, #P_IP_FAMILY]
    ldr     x10, [x19, #P_IP_FAMILY]
    cmp     x9, x10
    b.ne    2f
    ldp     x9, x10, [x20, #P_IP]
    ldp     x11, x12, [x19, #P_IP]
    cmp     x9, x11
    b.ne    2f
    cmp     x10, x12
    b.ne    2f
    add     x22, x22, #1
2:  add     x20, x20, #P_SIZE
    sub     x21, x21, #1
    b       1b
9:  mov     x0, x22
    LEAVE   0
END_FUNCTION libp2p_ip_count

/* libp2p_score_all(): every connected peer's score, kept in its slot for this step. */
LOCAL_FUNCTION libp2p_score_all
    ENTER   0
    TABLE   x19, ST_PEER_OFF
    ldr     x20, [x27, #ST_PEER_COUNT]
1:  cbz     x20, 9f
    ldr     w9, [x19, #P_STATE]
    cmp     w9, #PS_CONNECTED
    b.ne    2f
    mov     x0, x19
    bl      libp2p_score
    str     d0, [x19, #P_SCORE]
2:  add     x19, x19, #P_SIZE
    sub     x20, x20, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_all

/* libp2p_behaviour_penalty(peer, count): P7 counter += count. A leaf. */
LOCAL_FUNCTION libp2p_behaviour_penalty
    UNWIND_END_PROLOGUE
    ucvtf   d1, x1
    ldr     d0, [x0, #P_BEHAVIOUR]
    fadd    d0, d0, d1
    str     d0, [x0, #P_BEHAVIOUR]
    ret
END_FUNCTION libp2p_behaviour_penalty

/* libp2p_score_invalid(peer index, topic index): an invalid message of the peer in the topic: P4 counter + 1. */
LOCAL_FUNCTION libp2p_score_invalid
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, x1
    bl      libp2p_params
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_pt
    ldr     d0, [x0, #PT_INVALID]
    fmov    d1, #1.0
    fadd    d0, d0, d1
    str     d0, [x0, #PT_INVALID]
9:  LEAVE   0
END_FUNCTION libp2p_score_invalid

/*
 * libp2p_score_delivery(peer index, topic index, first): a valid delivery of
 * the peer in the topic: with first, P2 + 1 up to its cap; in the mesh,
 * P3 + 1 up to its cap.
 */
LOCAL_FUNCTION libp2p_score_delivery
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x1
    bl      libp2p_params
    cbz     x0, 9f
    mov     x22, x0
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_pt
    fmov    d2, #1.0
    cbz     x21, 1f
    ldr     d0, [x0, #PT_FIRST]
    fadd    d0, d0, d2
    ldr     d1, [x22, #LIBP2P_TP_FIRST_CAP]
    fmin    d0, d0, d1
    str     d0, [x0, #PT_FIRST]
1:  ldr     x9, [x0, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    9f
    ldr     d0, [x0, #PT_MESH_DEL]
    fadd    d0, d0, d2
    ldr     d1, [x22, #LIBP2P_TP_MESH_CAP]
    fmin    d0, d0, d1
    str     d0, [x0, #PT_MESH_DEL]
9:  LEAVE   0
END_FUNCTION libp2p_score_delivery

/*
 * libp2p_score_valid(peer index, topic index, seen): an accepted message: the
 * first delivery of its sender, and mesh deliveries of the peers that sent
 * it while it was judged.
 */
LOCAL_FUNCTION libp2p_score_valid
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x2, #1
    bl      libp2p_score_delivery
    cbz     x21, 9f
    ldr     w22, [x21, #SN_COUNT]
    add     x23, x21, #SN_PEERS
1:  cbz     x22, 9f
    ldrh    w0, [x23], #2
    mov     x1, x20
    mov     x2, #0
    bl      libp2p_score_delivery
    sub     x22, x22, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_valid

/* libp2p_score_rejected(peer index, topic index, seen): a rejected message: an invalid message of its sender and of the peers that sent it while it was judged. */
LOCAL_FUNCTION libp2p_score_rejected
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    bl      libp2p_score_invalid
    cbz     x21, 9f
    ldr     w22, [x21, #SN_COUNT]
    add     x23, x21, #SN_PEERS
1:  cbz     x22, 9f
    ldrh    w0, [x23], #2
    mov     x1, x20
    bl      libp2p_score_invalid
    sub     x22, x22, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_rejected

/*
 * libp2p_score_duplicate(peer index, seen): a message the peer sent that was
 * seen before. Still judged: the peer is kept as a deliverer (up to 12).
 * Valid: a mesh delivery when it came within the mesh delivery window of
 * the validation. Invalid: an invalid message of the peer.
 */
LOCAL_FUNCTION libp2p_score_duplicate
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     w21, [x20, #SN_TOPIC]
    ldr     x9, [x20, #SN_STATUS]
    cmp     x9, #SS_PENDING
    b.ne    2f
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_seen_delivered
    cbnz    x0, 9f
    ldr     w9, [x20, #SN_COUNT]
    cmp     x9, #LIBP2P_MAX_DELIVERERS
    b.hs    9f
    add     x10, x20, #SN_PEERS
    strh    w19, [x10, x9, lsl #1]
    add     w9, w9, #1
    str     w9, [x20, #SN_COUNT]
    b       9f
2:  cmp     x9, #SS_VALID
    b.ne    3f
    mov     x0, x21
    bl      libp2p_params
    cbz     x0, 9f
    ldr     x9, [x28, #SC_NOW]
    ldr     x10, [x20, #SN_VALIDATED]
    sub     x9, x9, x10
    ldr     x10, [x0, #LIBP2P_TP_MESH_WINDOW_MS]
    cmp     x9, x10
    b.hi    9f
    mov     x0, x19
    mov     x1, x21
    mov     x2, #0
    bl      libp2p_score_delivery
    b       9f
3:  cmp     x9, #SS_INVALID
    b.ne    9f
    mov     x0, x19
    mov     x1, x21
    bl      libp2p_score_invalid
9:  LEAVE   0
END_FUNCTION libp2p_score_duplicate

/*
 * libp2p_score_mesh_leave(peer index, topic index): the peer leaves our mesh:
 * with P3 active and below its threshold, P3b += the deficit squared.
 */
LOCAL_FUNCTION libp2p_score_mesh_leave
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, x1
    bl      libp2p_params
    cbz     x0, 9f
    mov     x21, x0
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    9f
    ldr     x9, [x28, #SC_NOW]
    ldr     x10, [x0, #PT_GRAFT_TIME]
    sub     x9, x9, x10
    ldr     x10, [x21, #LIBP2P_TP_MESH_ACTIVATION_MS]
    cmp     x9, x10
    b.ls    9f
    ldr     d0, [x0, #PT_MESH_DEL]
    ldr     d1, [x21, #LIBP2P_TP_MESH_THRESHOLD]
    fcmp    d0, d1
    b.pl    9f
    fsub    d0, d1, d0
    fmul    d0, d0, d0
    ldr     d1, [x0, #PT_MESH_FAIL]
    fadd    d0, d0, d1
    str     d0, [x0, #PT_MESH_FAIL]
9:  LEAVE   0
END_FUNCTION libp2p_score_mesh_leave

/* libp2p_decay(address, factor in d0): the f64 at address times the factor, 0 below decay_to_zero. A leaf. */
LOCAL_FUNCTION libp2p_decay
    UNWIND_END_PROLOGUE
    ldr     d1, [x0]
    fmul    d1, d1, d0
    ldr     d2, [x27, #(ST_CONFIG + LIBP2P_CFG_DECAY_TO_ZERO)]
    fabs    d3, d1
    fcmp    d3, d2
    b.pl    1f
    fmov    d1, xzr
1:  str     d1, [x0]
    ret
END_FUNCTION libp2p_decay

/*
 * libp2p_score_decay(): every decay_interval: P2, P3, P3b and P4 of each peer
 * (connected or retained) in each topic with parameters, and P7, times
 * their decay factors.
 * x19 peer, x20 peer index, x21 topic index, x22 params, x23 entry.
 */
LOCAL_FUNCTION libp2p_score_decay
    ENTER   0
    mov     x20, #0
1:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x20, x9
    b.hs    9f
    mov     x0, x20
    bl      libp2p_peer_at
    mov     x19, x0
    ldr     w9, [x19, #P_STATE]
    cbz     w9, 4f
    mov     x21, #0
2:  ldr     x9, [x27, #ST_TOPIC_COUNT]
    cmp     x21, x9
    b.hs    3f
    mov     x0, x21
    bl      libp2p_params
    cbz     x0, 21f
    mov     x22, x0
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_pt
    mov     x23, x0
    ldr     d0, [x22, #LIBP2P_TP_FIRST_DECAY]
    add     x0, x23, #PT_FIRST
    bl      libp2p_decay
    ldr     d0, [x22, #LIBP2P_TP_MESH_DECAY]
    add     x0, x23, #PT_MESH_DEL
    bl      libp2p_decay
    ldr     d0, [x22, #LIBP2P_TP_FAIL_DECAY]
    add     x0, x23, #PT_MESH_FAIL
    bl      libp2p_decay
    ldr     d0, [x22, #LIBP2P_TP_INVALID_DECAY]
    add     x0, x23, #PT_INVALID
    bl      libp2p_decay
21: add     x21, x21, #1
    b       2b
3:  ldr     d0, [x27, #(ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_DECAY)]
    add     x0, x19, #P_BEHAVIOUR
    bl      libp2p_decay
4:  add     x20, x20, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_decay

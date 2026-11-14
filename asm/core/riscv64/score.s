/*
 * gossipsub v1.1 peer scores of the RISC-V core: the score function, the
 * counters of P2, P3, P3b, P4 and P7, and their decay. f64 arithmetic in
 * fa0 to fa7 and ft0 to ft1 only. A product and a sum round apart (fmul,
 * then fadd), so every ISA gets the same scores. Included by gossip.s.
 */

/*
 * rd = the smaller of fx and fy, as ARM64 fmin: NaN when either is NaN
 * (fmin.d alone gives the other operand), and -0 below +0. Uses t5, t6.
 */
.macro FMIN rd, fx, fy
    feq.d   t5, \fx, \fx
    feq.d   t6, \fy, \fy
    and     t5, t5, t6
    fmin.d  \rd, \fx, \fy
    bnez    t5, 1001f
    li      t5, 0x7FF8000000000000
    fmv.d.x \rd, t5
1001:
.endm

/* libp2p_params(topic index) -> the TopicParams of a topic with parameters, or 0. A leaf. */
LOCAL_FUNCTION libp2p_params
    UNWIND_END_PROLOGUE
    ld      a1, ST_TOPIC_OFF(s9)
    add     a1, s9, a1
    li      a2, T_SIZE
    mul     a0, a0, a2
    add     a1, a1, a0
    ld      a2, T_USED(a1)
    beqz    a2, 8f
    ld      a2, T_FLAGS(a1)
    andi    a2, a2, TF_PARAMS
    beqz    a2, 8f
    ld      a2, (ST_CONFIG + LIBP2P_CFG_SCORING)(s9)
    beqz    a2, 8f
    addi    a0, a1, T_PARAMS
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_params

/*
 * libp2p_score(peer) -> fa0 the score of gossipsub v1.1:
 * TopicCap(sum of topic weight x (w1 P1 + w2 P2 + w3 P3 + w3b P3b + w4 P4))
 * + w5 P5 + w6 P6 + w7 P7. 0 when scoring is off.
 * s1 peer, s2 peer index, s3 topic index, s4 topics, s5 now, s6 params,
 * s7 entry. ft0 total, ft1 topic score; the total at sp + FL across calls.
 */
LOCAL_FUNCTION libp2p_score
    ENTER   16
    mv      s1, a0
    fmv.d.x ft0, zero
    CFG     t0, LIBP2P_CFG_SCORING
    beqz    t0, 90f
    call    libp2p_peer_idx
    mv      s2, a0
    ld      s5, SC_NOW(s10)
    li      s3, 0
    ld      s4, ST_TOPIC_COUNT(s9)
1:  bgeu    s3, s4, 5f
    mv      a0, s3
    call    libp2p_params
    beqz    a0, 4f
    mv      s6, a0
    mv      a0, s2
    mv      a1, s3
    call    libp2p_pt
    mv      s7, a0
    fmv.d.x ft1, zero
    ld      t0, PT_FLAGS(s7)
    andi    t0, t0, PTF_MESH
    beqz    t0, 2f
    ld      t1, PT_GRAFT_TIME(s7)           # P1: time in mesh, in quanta, up to the cap
    sub     t1, s5, t1
    ld      t2, LIBP2P_TP_TIME_QUANTUM_MS(s6)
    bnez    t2, 11f
    li      t2, 1
11: divu    t3, t1, t2
    fcvt.d.lu fa0, t3
    fld     fa1, LIBP2P_TP_TIME_CAP(s6)
    FMIN    fa0, fa0, fa1
    fld     fa1, LIBP2P_TP_TIME_WEIGHT(s6)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft1, ft1, fa7
    ld      t2, LIBP2P_TP_MESH_ACTIVATION_MS(s6) # P3: delivery deficit, once active
    bgeu    t2, t1, 2f
    fld     fa0, PT_MESH_DEL(s7)
    fld     fa1, LIBP2P_TP_MESH_THRESHOLD(s6)
    flt.d   t0, fa0, fa1
    beqz    t0, 2f
    fsub.d  fa0, fa1, fa0
    fmul.d  fa0, fa0, fa0
    fld     fa1, LIBP2P_TP_MESH_WEIGHT(s6)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft1, ft1, fa7
2:  fld     fa0, PT_FIRST(s7)               # P2
    fld     fa1, LIBP2P_TP_FIRST_WEIGHT(s6)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft1, ft1, fa7
    fld     fa0, PT_MESH_FAIL(s7)           # P3b
    fld     fa1, LIBP2P_TP_FAIL_WEIGHT(s6)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft1, ft1, fa7
    fld     fa0, PT_INVALID(s7)             # P4: squared
    fmul.d  fa0, fa0, fa0
    fld     fa1, LIBP2P_TP_INVALID_WEIGHT(s6)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft1, ft1, fa7
    fld     fa1, LIBP2P_TP_WEIGHT(s6)
    fmul.d  fa7, ft1, fa1
    fadd.d  ft0, ft0, fa7
4:  addi    s3, s3, 1
    j       1b
5:  fld     fa1, (ST_CONFIG + LIBP2P_CFG_TOPIC_CAP)(s9)
    fmv.d.x fa2, zero
    flt.d   t0, fa2, fa1
    beqz    t0, 6f
    FMIN    ft0, ft0, fa1
6:  fld     fa0, P_APP_SCORE(s1)            # P5
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_APP_WEIGHT)(s9)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft0, ft0, fa7
    fsd     ft0, FL(sp)
    mv      a0, s1                          # P6: peers on the same IP above the threshold, squared
    call    libp2p_ip_count
    fld     ft0, FL(sp)
    CFG     t0, LIBP2P_CFG_IP_THRESHOLD
    bgeu    t0, a0, 7f
    sub     a0, a0, t0
    fcvt.d.lu fa0, a0
    fmul.d  fa0, fa0, fa0
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_IP_WEIGHT)(s9)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft0, ft0, fa7
7:  fld     fa0, P_BEHAVIOUR(s1)            # P7: above the threshold, squared
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_THRESHOLD)(s9)
    flt.d   t0, fa1, fa0
    beqz    t0, 90f
    fsub.d  fa0, fa0, fa1
    fmul.d  fa0, fa0, fa0
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_WEIGHT)(s9)
    fmul.d  fa7, fa0, fa1
    fadd.d  ft0, ft0, fa7
90: fmv.d   fa0, ft0
    LEAVE   16
END_FUNCTION libp2p_score

/* libp2p_ip_count(peer) -> the connected peers with the same IP family and address, itself included. */
LOCAL_FUNCTION libp2p_ip_count
    ENTER   0
    mv      s1, a0
    TABLE   s2, ST_PEER_OFF
    ld      s3, ST_PEER_COUNT(s9)
    li      s4, 0
1:  beqz    s3, 9f
    lwu     t0, P_STATE(s2)
    li      t1, PS_CONNECTED
    bne     t0, t1, 2f
    ld      t0, P_IP_FAMILY(s2)
    ld      t1, P_IP_FAMILY(s1)
    bne     t0, t1, 2f
    ld      t0, P_IP(s2)
    ld      t1, P_IP(s1)
    bne     t0, t1, 2f
    ld      t0, (P_IP + 8)(s2)
    ld      t1, (P_IP + 8)(s1)
    bne     t0, t1, 2f
    addi    s4, s4, 1
2:  addi    s2, s2, P_SIZE
    addi    s3, s3, -1
    j       1b
9:  mv      a0, s4
    LEAVE   0
END_FUNCTION libp2p_ip_count

/* libp2p_score_all(): every connected peer's score, kept in its slot for this step. */
LOCAL_FUNCTION libp2p_score_all
    ENTER   0
    TABLE   s1, ST_PEER_OFF
    ld      s2, ST_PEER_COUNT(s9)
1:  beqz    s2, 9f
    lwu     t0, P_STATE(s1)
    li      t1, PS_CONNECTED
    bne     t0, t1, 2f
    mv      a0, s1
    call    libp2p_score
    fsd     fa0, P_SCORE(s1)
2:  addi    s1, s1, P_SIZE
    addi    s2, s2, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_all

/* libp2p_behaviour_penalty(peer, count): P7 counter += count. A leaf. */
LOCAL_FUNCTION libp2p_behaviour_penalty
    UNWIND_END_PROLOGUE
    fcvt.d.lu fa1, a1
    fld     fa0, P_BEHAVIOUR(a0)
    fadd.d  fa0, fa0, fa1
    fsd     fa0, P_BEHAVIOUR(a0)
    ret
END_FUNCTION libp2p_behaviour_penalty

/* libp2p_score_invalid(peer index, topic index): an invalid message of the peer in the topic: P4 counter + 1. */
LOCAL_FUNCTION libp2p_score_invalid
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      a0, a1
    call    libp2p_params
    beqz    a0, 9f
    mv      a0, s1
    mv      a1, s2
    call    libp2p_pt
    fld     fa0, PT_INVALID(a0)
    li      t0, 0x3FF0000000000000          # 1.0
    fmv.d.x fa1, t0
    fadd.d  fa0, fa0, fa1
    fsd     fa0, PT_INVALID(a0)
9:  LEAVE   0
END_FUNCTION libp2p_score_invalid

/*
 * libp2p_score_delivery(peer index, topic index, first): a valid delivery of
 * the peer in the topic: with first, P2 + 1 up to its cap; in the mesh,
 * P3 + 1 up to its cap.
 */
LOCAL_FUNCTION libp2p_score_delivery
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      a0, a1
    call    libp2p_params
    beqz    a0, 9f
    mv      s4, a0
    mv      a0, s1
    mv      a1, s2
    call    libp2p_pt
    li      t0, 0x3FF0000000000000          # 1.0
    fmv.d.x fa2, t0
    beqz    s3, 1f
    fld     fa0, PT_FIRST(a0)
    fadd.d  fa0, fa0, fa2
    fld     fa1, LIBP2P_TP_FIRST_CAP(s4)
    FMIN    fa0, fa0, fa1
    fsd     fa0, PT_FIRST(a0)
1:  ld      t0, PT_FLAGS(a0)
    andi    t0, t0, PTF_MESH
    beqz    t0, 9f
    fld     fa0, PT_MESH_DEL(a0)
    fadd.d  fa0, fa0, fa2
    fld     fa1, LIBP2P_TP_MESH_CAP(s4)
    FMIN    fa0, fa0, fa1
    fsd     fa0, PT_MESH_DEL(a0)
9:  LEAVE   0
END_FUNCTION libp2p_score_delivery

/*
 * libp2p_score_valid(peer index, topic index, seen): an accepted message: the
 * first delivery of its sender, and mesh deliveries of the peers that sent
 * it while it was judged.
 */
LOCAL_FUNCTION libp2p_score_valid
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a2, 1
    call    libp2p_score_delivery
    beqz    s3, 9f
    lwu     s4, SN_COUNT(s3)
    addi    s5, s3, SN_PEERS
1:  beqz    s4, 9f
    lhu     a0, 0(s5)
    addi    s5, s5, 2
    mv      a1, s2
    li      a2, 0
    call    libp2p_score_delivery
    addi    s4, s4, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_valid

/* libp2p_score_rejected(peer index, topic index, seen): a rejected message: an invalid message of its sender and of the peers that sent it while it was judged. */
LOCAL_FUNCTION libp2p_score_rejected
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    call    libp2p_score_invalid
    beqz    s3, 9f
    lwu     s4, SN_COUNT(s3)
    addi    s5, s3, SN_PEERS
1:  beqz    s4, 9f
    lhu     a0, 0(s5)
    addi    s5, s5, 2
    mv      a1, s2
    call    libp2p_score_invalid
    addi    s4, s4, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_rejected

/*
 * libp2p_score_duplicate(peer index, seen): a message the peer sent that was
 * seen before. Still judged: the peer is kept as a deliverer (up to 12).
 * Valid: a mesh delivery when it came within the mesh delivery window of
 * the validation. Invalid: an invalid message of the peer.
 * s1 peer index, s2 seen, s3 topic index.
 */
LOCAL_FUNCTION libp2p_score_duplicate
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    lwu     s3, SN_TOPIC(s2)
    ld      t0, SN_STATUS(s2)
    li      t1, SS_PENDING
    bne     t0, t1, 2f
    mv      a0, s1
    mv      a1, s2
    call    libp2p_seen_delivered
    bnez    a0, 9f
    lwu     t0, SN_COUNT(s2)
    li      t1, LIBP2P_MAX_DELIVERERS
    bgeu    t0, t1, 9f
    addi    t1, s2, SN_PEERS
    slli    t2, t0, 1
    add     t1, t1, t2
    sh      s1, 0(t1)
    addiw   t0, t0, 1
    sw      t0, SN_COUNT(s2)
    j       9f
2:  li      t1, SS_VALID
    bne     t0, t1, 3f
    mv      a0, s3
    call    libp2p_params
    beqz    a0, 9f
    ld      t0, SC_NOW(s10)
    ld      t1, SN_VALIDATED(s2)
    sub     t0, t0, t1
    ld      t1, LIBP2P_TP_MESH_WINDOW_MS(a0)
    bltu    t1, t0, 9f
    mv      a0, s1
    mv      a1, s3
    li      a2, 0
    call    libp2p_score_delivery
    j       9f
3:  li      t1, SS_INVALID
    bne     t0, t1, 9f
    mv      a0, s1
    mv      a1, s3
    call    libp2p_score_invalid
9:  LEAVE   0
END_FUNCTION libp2p_score_duplicate

/*
 * libp2p_score_mesh_leave(peer index, topic index): the peer leaves our mesh:
 * with P3 active and below its threshold, P3b += the deficit squared.
 */
LOCAL_FUNCTION libp2p_score_mesh_leave
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      a0, a1
    call    libp2p_params
    beqz    a0, 9f
    mv      s3, a0
    mv      a0, s1
    mv      a1, s2
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t0, t0, PTF_MESH
    beqz    t0, 9f
    ld      t0, SC_NOW(s10)
    ld      t1, PT_GRAFT_TIME(a0)
    sub     t0, t0, t1
    ld      t1, LIBP2P_TP_MESH_ACTIVATION_MS(s3)
    bgeu    t1, t0, 9f
    fld     fa0, PT_MESH_DEL(a0)
    fld     fa1, LIBP2P_TP_MESH_THRESHOLD(s3)
    flt.d   t0, fa0, fa1
    beqz    t0, 9f
    fsub.d  fa0, fa1, fa0
    fmul.d  fa0, fa0, fa0
    fld     fa1, PT_MESH_FAIL(a0)
    fadd.d  fa0, fa0, fa1
    fsd     fa0, PT_MESH_FAIL(a0)
9:  LEAVE   0
END_FUNCTION libp2p_score_mesh_leave

/* libp2p_decay(address, factor in fa0): the f64 at address times the factor, 0 below decay_to_zero. A leaf. */
LOCAL_FUNCTION libp2p_decay
    UNWIND_END_PROLOGUE
    fld     fa1, 0(a0)
    fmul.d  fa1, fa1, fa0
    fld     fa2, (ST_CONFIG + LIBP2P_CFG_DECAY_TO_ZERO)(s9)
    fabs.d  fa3, fa1
    flt.d   a1, fa3, fa2
    beqz    a1, 1f
    fmv.d.x fa1, zero
1:  fsd     fa1, 0(a0)
    ret
END_FUNCTION libp2p_decay

/*
 * libp2p_score_decay(): every decay_interval: P2, P3, P3b and P4 of each peer
 * (connected or retained) in each topic with parameters, and P7, times
 * their decay factors.
 * s1 peer, s2 peer index, s3 topic index, s4 params, s5 entry.
 */
LOCAL_FUNCTION libp2p_score_decay
    ENTER   0
    li      s2, 0
1:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s2, t0, 9f
    mv      a0, s2
    call    libp2p_peer_at
    mv      s1, a0
    lwu     t0, P_STATE(s1)
    beqz    t0, 4f
    li      s3, 0
2:  ld      t0, ST_TOPIC_COUNT(s9)
    bgeu    s3, t0, 3f
    mv      a0, s3
    call    libp2p_params
    beqz    a0, 21f
    mv      s4, a0
    mv      a0, s2
    mv      a1, s3
    call    libp2p_pt
    mv      s5, a0
    fld     fa0, LIBP2P_TP_FIRST_DECAY(s4)
    addi    a0, s5, PT_FIRST
    call    libp2p_decay
    fld     fa0, LIBP2P_TP_MESH_DECAY(s4)
    addi    a0, s5, PT_MESH_DEL
    call    libp2p_decay
    fld     fa0, LIBP2P_TP_FAIL_DECAY(s4)
    addi    a0, s5, PT_MESH_FAIL
    call    libp2p_decay
    fld     fa0, LIBP2P_TP_INVALID_DECAY(s4)
    addi    a0, s5, PT_INVALID
    call    libp2p_decay
21: addi    s3, s3, 1
    j       2b
3:  fld     fa0, (ST_CONFIG + LIBP2P_CFG_BEHAVIOUR_DECAY)(s9)
    addi    a0, s1, P_BEHAVIOUR
    call    libp2p_decay
4:  addi    s2, s2, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_score_decay

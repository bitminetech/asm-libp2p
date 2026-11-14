/*
 * gossipsub timers of the RISC-V core: validation timeouts, retained
 * scores, the heartbeat (promises, mesh and fanout maintenance, gossip, the
 * message cache windows, the seen cache) and score decay. Included by
 * gossip.s.
 */

/*
 * libp2p_gossip_timers(): messages the application did not judge within
 * validation_ms are dropped (MESSAGE_STATUS dropped); retained scores past
 * retain_score end; the heartbeat and decay run when due. Then a wakeup at
 * the next of these times.
 * s1 slot, s2 slots left, s3 now.
 */
LOCAL_FUNCTION libp2p_gossip_timers
    ENTER   0
    ld      s3, SC_NOW(s10)
    TABLE   s1, ST_PEND_OFF
    ld      s2, ST_PEND_COUNT(s9)
1:  beqz    s2, 3f
    lwu     t0, PD_STATE(s1)
    beqz    t0, 2f
    ld      a0, PD_TIME(s1)
    CFG     t0, LIBP2P_CFG_VALIDATION_MS
    add     a0, a0, t0
    bltu    s3, a0, 11f
    call    libp2p_room
    li      t0, 64
    bltu    a0, t0, 12f
    mv      a0, s1
    li      a1, LIBP2P_MSG_DROPPED
    call    libp2p_pend_status
    mv      a0, s1
    call    libp2p_pend_free
    j       2f
11: call    libp2p_wake_at
    j       2f
12: mv      a0, s3                          # no room: next step
    call    libp2p_wake_at
2:  addi    s1, s1, PD_SIZE
    addi    s2, s2, -1
    j       1b
3:  TABLE   s1, ST_PEER_OFF                 # retained scores
    ld      s2, ST_PEER_COUNT(s9)
4:  beqz    s2, 5f
    lwu     t0, P_STATE(s1)
    li      t1, PS_RETAINED
    bne     t0, t1, 41f
    ld      a0, P_EXPIRE(s1)
    bltu    s3, a0, 42f
    mv      a0, s1
    call    libp2p_peer_release
    j       41f
42: call    libp2p_wake_at
41: addi    s1, s1, P_SIZE
    addi    s2, s2, -1
    j       4b
5:  ld      t0, ST_HEARTBEAT_AT(s9)         # the heartbeat
    bltu    s3, t0, 6f
    call    libp2p_heartbeat
    ld      t0, ST_HEARTBEAT_AT(s9)
    CFG     t1, LIBP2P_CFG_HEARTBEAT_MS
    add     t0, t0, t1
    bltu    s3, t0, 51f
    add     t0, s3, t1
51: sd      t0, ST_HEARTBEAT_AT(s9)
6:  ld      a0, ST_HEARTBEAT_AT(s9)
    call    libp2p_wake_at
    CFG     t0, LIBP2P_CFG_SCORING
    beqz    t0, 9f
    ld      t0, ST_DECAY_AT(s9)             # score decay
    bltu    s3, t0, 8f
    call    libp2p_score_decay
    ld      t0, ST_DECAY_AT(s9)
    CFG     t1, LIBP2P_CFG_DECAY_INTERVAL_MS
    add     t0, t0, t1
    bltu    s3, t0, 71f
    add     t0, s3, t1
71: sd      t0, ST_DECAY_AT(s9)
8:  ld      a0, ST_DECAY_AT(s9)
    call    libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_gossip_timers

/*
 * libp2p_heartbeat(): scores of this heartbeat; IHAVE and IDONTWANT counters reset; broken
 * promises cost a behaviour penalty; mesh maintenance of each topic we
 * subscribe to, fanout maintenance of the others; gossip; then the message
 * cache moves to a new window and old seen entries leave.
 * s1 topic index, s2 topics, s3 topic, s4 now.
 */
LOCAL_FUNCTION libp2p_heartbeat
    ENTER   0
    ld      s4, SC_NOW(s10)
    call    libp2p_score_all
    TABLE   s1, ST_PEER_OFF                 # IHAVE and IDONTWANT counters
    ld      s2, ST_PEER_COUNT(s9)
1:  beqz    s2, 2f
    sd      zero, P_IHAVE_COUNT(s1)
    sd      zero, P_IHAVE_IDS(s1)
    sd      zero, P_DW_COUNT(s1)
    addi    s1, s1, P_SIZE
    addi    s2, s2, -1
    j       1b
2:  TABLE   s1, ST_PROMISE_OFF              # broken promises
    li      s2, LIBP2P_PROMISES
3:  beqz    s2, 4f
    ld      t0, PR_PEER(s1)
    li      t1, NONE
    beq     t0, t1, 31f
    ld      t2, PR_DEADLINE(s1)
    bltu    s4, t2, 31f
    sd      t1, PR_PEER(s1)
    mv      a0, t0
    call    libp2p_peer_at
    li      a1, 1
    call    libp2p_behaviour_penalty
31: addi    s1, s1, PR_SIZE
    addi    s2, s2, -1
    j       3b
4:  li      s1, 0                           # the topics
    ld      s2, ST_TOPIC_COUNT(s9)
5:  bgeu    s1, s2, 7f
    mv      a0, s1
    call    libp2p_topic_at
    mv      s3, a0
    ld      t0, T_USED(s3)
    beqz    t0, 6f
    ld      t0, T_FLAGS(s3)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 51f
    mv      a0, s1
    call    libp2p_mesh_maintain
    j       52f
51: ld      t0, T_FANOUT(s3)
    beqz    t0, 6f
    mv      a0, s1
    call    libp2p_fanout_maintain
52: mv      a0, s1
    call    libp2p_emit_gossip
6:  addi    s1, s1, 1
    j       5b
7:  ld      t0, ST_HEARTBEATS(s9)
    addi    t0, t0, 1
    sd      t0, ST_HEARTBEATS(s9)
    call    libp2p_mc_shift
    call    libp2p_seen_expire
    LEAVE   0
END_FUNCTION libp2p_heartbeat

/* libp2p_list_score(list, i) -> fa0 the heartbeat score of the peer at list[i]. A leaf. */
LOCAL_FUNCTION libp2p_list_score
    UNWIND_END_PROLOGUE
    slli    a1, a1, 2
    add     a0, a0, a1
    lwu     a0, 0(a0)
    ld      a1, ST_PEER_OFF(s9)
    add     a1, s9, a1
    li      a2, P_SIZE
    mul     a0, a0, a2
    add     a0, a0, a1
    fld     fa0, P_SCORE(a0)
    ret
END_FUNCTION libp2p_list_score

/* libp2p_list_outbound(list, i) -> 1 when the peer at list[i] is outbound. A leaf. */
LOCAL_FUNCTION libp2p_list_outbound
    UNWIND_END_PROLOGUE
    slli    a1, a1, 2
    add     a0, a0, a1
    lwu     a0, 0(a0)
    ld      a1, ST_PEER_OFF(s9)
    add     a1, s9, a1
    li      a2, P_SIZE
    mul     a0, a0, a2
    add     a0, a0, a1
    ld      a0, P_FLAGS(a0)
    andi    a0, a0, PF_OUTBOUND
    ret
END_FUNCTION libp2p_list_outbound

/*
 * libp2p_sort_score(list, count): the list in falling order of score
 * (insertion sort). s1 list, s2 count, s3 i, s4 the value, s5 j.
 * ft0 the score of the value (libp2p_list_score keeps it).
 */
LOCAL_FUNCTION libp2p_sort_score
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    li      s3, 1
1:  bgeu    s3, s2, 9f
    slli    t0, s3, 2
    add     t0, s1, t0
    lwu     s4, 0(t0)
    mv      a0, s1
    mv      a1, s3
    call    libp2p_list_score
    fmv.d   ft0, fa0
    mv      s5, s3
2:  beqz    s5, 3f
    mv      a0, s1
    addi    a1, s5, -1
    call    libp2p_list_score
    fle.d   t0, ft0, fa0
    bnez    t0, 3f
    addi    t0, s5, -1
    slli    t1, t0, 2
    add     t1, s1, t1
    lwu     t2, 0(t1)
    slli    t3, s5, 2
    add     t3, s1, t3
    sw      t2, 0(t3)
    mv      s5, t0
    j       2b
3:  slli    t0, s5, 2
    add     t0, s1, t0
    sw      s4, 0(t0)
    addi    s3, s3, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_sort_score

/* libp2p_add_from_list(topic index, count): the first count peers of the list join the mesh. */
LOCAL_FUNCTION libp2p_add_from_list
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    SCR     s3, SC_LIST
    li      s4, 0
1:  bgeu    s4, s2, 9f
    slli    t0, s4, 2
    add     t0, s3, t0
    lwu     a0, 0(t0)
    mv      a1, s1
    call    libp2p_mesh_add
    addi    s4, s4, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_add_from_list

/*
 * libp2p_mesh_maintain(topic index): mesh peers that are not ready or score
 * below 0 leave with PRUNE; below D_low the mesh grows to D; above D_high
 * it shrinks to D, keeping the D_score best and D_out outbound peers;
 * then it takes outbound peers up to D_out; every opportunistic_ticks
 * heartbeats, a mesh whose median score is below the threshold takes peers
 * above the median.
 * s1 topic index, s2 topic, s3 list, s4 count, s5 i, s6 mesh count, s7 limit.
 */
LOCAL_FUNCTION libp2p_mesh_maintain
    ENTER   0
    mv      s1, a0
    call    libp2p_topic_at
    mv      s2, a0
    SCR     s3, SC_LIST
    li      s5, 0                           # mesh peers not ready or below 0
1:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s5, t0, 3f
    mv      a0, s5
    mv      a1, s1
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t0, t0, PTF_MESH
    beqz    t0, 2f
    mv      a0, s5
    call    libp2p_peer_at
    mv      s6, a0
    call    libp2p_gs_ready
    beqz    a0, 11f
    fld     fa0, P_SCORE(s6)
    fmv.d.x ft0, zero
    flt.d   t0, fa0, ft0
    beqz    t0, 2f
    mv      a0, s5
    mv      a1, s1
    CFG     a2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    call    libp2p_prune_to
11: mv      a0, s5
    mv      a1, s1
    call    libp2p_mesh_remove
2:  addi    s5, s5, 1
    j       1b
3:  ld      s6, T_MESH(s2)                  # too few
    CFG     t0, LIBP2P_CFG_D_LOW
    bgeu    s6, t0, 4f
    fmv.d.x fa0, zero
    mv      a0, s1
    li      a1, 0
    li      a2, (PTF_MESH | CAND_BACKOFF)
    call    libp2p_candidates
    mv      s4, a0
    mv      a0, s3
    mv      a1, s4
    call    libp2p_shuffle
    CFG     t0, LIBP2P_CFG_D
    sub     t0, t0, s6
    mv      a1, s4
    bltu    s4, t0, 31f
    mv      a1, t0
31: mv      a0, s1
    call    libp2p_add_from_list
4:  ld      s6, T_MESH(s2)                  # too many
    CFG     t0, LIBP2P_CFG_D_HIGH
    bgeu    t0, s6, 6f
    li      t0, 0xFFF0000000000000
    fmv.d.x fa0, t0
    mv      a0, s1
    li      a1, PTF_MESH
    li      a2, 0
    call    libp2p_candidates
    mv      s4, a0
    mv      a0, s3
    mv      a1, s4
    call    libp2p_sort_score
    CFG     s7, LIBP2P_CFG_D_SCORE          # the best D_score stay; the rest in random order
    bltu    s7, s4, 41f
    mv      s7, s4
41: slli    a0, s7, 2
    add     a0, s3, a0
    sub     a1, s4, s7
    call    libp2p_shuffle
    CFG     s7, LIBP2P_CFG_D                # kept: list[0..D)
    mv      a0, s3
    mv      a1, s7
    mv      a2, s4
    call    libp2p_keep_outbound
    mv      s5, s7
5:  bgeu    s5, s4, 6f
    slli    t0, s5, 2
    add     t0, s3, t0
    lwu     a0, 0(t0)
    mv      a1, s1
    CFG     a2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    call    libp2p_prune_to
    slli    t0, s5, 2
    add     t0, s3, t0
    lwu     a0, 0(t0)
    mv      a1, s1
    call    libp2p_mesh_remove
    addi    s5, s5, 1
    j       5b
6:  ld      s6, T_MESH(s2)                  # outbound quota
    CFG     t0, LIBP2P_CFG_D_LOW
    bltu    s6, t0, 7f
    li      t0, 0xFFF0000000000000
    fmv.d.x fa0, t0
    mv      a0, s1
    li      a1, (PTF_MESH | CAND_OUTBOUND)
    li      a2, 0
    call    libp2p_candidates
    CFG     t0, LIBP2P_CFG_D_OUT
    bgeu    a0, t0, 7f
    sub     s7, t0, a0
    fmv.d.x fa0, zero
    mv      a0, s1
    li      a1, CAND_OUTBOUND
    li      a2, (PTF_MESH | CAND_BACKOFF)
    call    libp2p_candidates
    mv      s4, a0
    mv      a0, s3
    mv      a1, s4
    call    libp2p_shuffle
    mv      a1, s4
    bltu    s4, s7, 61f
    mv      a1, s7
61: mv      a0, s1
    call    libp2p_add_from_list
7:  ld      t0, ST_HEARTBEATS(s9)           # opportunistic grafting
    CFG     t1, LIBP2P_CFG_OPPORTUNISTIC_TICKS
    beqz    t1, 9f
    remu    t2, t0, t1
    bnez    t2, 9f
    ld      s6, T_MESH(s2)
    li      t0, 1
    bgeu    t0, s6, 9f
    li      t0, 0xFFF0000000000000
    fmv.d.x fa0, t0
    mv      a0, s1
    li      a1, PTF_MESH
    li      a2, 0
    call    libp2p_candidates
    mv      s4, a0
    li      t0, 1
    bgeu    t0, s4, 9f
    mv      a0, s3
    mv      a1, s4
    call    libp2p_sort_score
    mv      a0, s3
    srli    a1, s4, 1
    call    libp2p_list_score                   # the median
    fmv.d   ft0, fa0
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_OPPORTUNISTIC_THRESHOLD)(s9)
    fle.d   t0, fa1, ft0
    bnez    t0, 9f
    fmv.x.d t0, ft0                         # above the median: the next double up is the floor
    addi    t0, t0, 1
    fmv.d.x fa0, t0
    fmv.d.x ft1, zero
    fle.d   t1, ft1, ft0
    bnez    t1, 71f
    addi    t0, t0, -2
    fmv.d.x fa0, t0
71: mv      a0, s1
    li      a1, 0
    li      a2, (PTF_MESH | CAND_BACKOFF)
    call    libp2p_candidates
    mv      s4, a0
    mv      a0, s3
    mv      a1, s4
    call    libp2p_shuffle
    CFG     t0, LIBP2P_CFG_OPPORTUNISTIC_PEERS
    mv      a1, s4
    bltu    s4, t0, 72f
    mv      a1, t0
72: mv      a0, s1
    call    libp2p_add_from_list
9:  LEAVE   0
END_FUNCTION libp2p_mesh_maintain

/*
 * libp2p_keep_outbound(list, kept, count): when list[0..kept) has fewer than
 * D_out outbound peers, outbound peers from list[kept..count) take the
 * places of the last inbound kept peers.
 * s1 list, s2 kept, s3 count, s4 outbound kept, s5 i, s6 j.
 */
LOCAL_FUNCTION libp2p_keep_outbound
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    bltu    a1, a2, 1f
    mv      s2, a2
1:  mv      s3, a2
    li      s4, 0
    li      s5, 0
11: bgeu    s5, s2, 2f
    mv      a0, s1
    mv      a1, s5
    call    libp2p_list_outbound
    add     s4, s4, a0
    addi    s5, s5, 1
    j       11b
2:  mv      s5, s2                          # outbound candidates beyond the kept part
    mv      s6, s2                          # the next kept place to give up, from the end
3:  CFG     t0, LIBP2P_CFG_D_OUT
    bgeu    s4, t0, 9f
    bgeu    s5, s3, 9f
    mv      a0, s1
    mv      a1, s5
    call    libp2p_list_outbound
    beqz    a0, 5f
4:  beqz    s6, 9f                          # an inbound kept peer to swap out
    addi    s6, s6, -1
    mv      a0, s1
    mv      a1, s6
    call    libp2p_list_outbound
    bnez    a0, 4b
    slli    t0, s5, 2
    add     t0, s1, t0
    slli    t1, s6, 2
    add     t1, s1, t1
    lwu     t2, 0(t0)
    lwu     t3, 0(t1)
    sw      t2, 0(t1)
    sw      t3, 0(t0)
    addi    s4, s4, 1
5:  addi    s5, s5, 1
    j       3b
9:  LEAVE   0
END_FUNCTION libp2p_keep_outbound

/*
 * libp2p_fanout_maintain(topic index): a fanout unused for fanout_ttl ends;
 * else peers below publish_threshold leave it and it grows to D.
 * s1 topic index, s2 topic, s3 peer index, s4 entry, s5 peer, s6 room.
 */
LOCAL_FUNCTION libp2p_fanout_maintain
    ENTER   0
    mv      s1, a0
    call    libp2p_topic_at
    mv      s2, a0
    ld      t0, SC_NOW(s10)
    ld      t1, T_FANOUT_LAST(s2)
    sub     t0, t0, t1
    CFG     t1, LIBP2P_CFG_FANOUT_TTL_MS
    bgeu    t1, t0, 1f
    mv      t0, s1                          # libp2p_fanout_clear_topic takes s1 topic, s2 index
    mv      s1, s2
    mv      s2, t0
    call    libp2p_fanout_clear_topic
    mv      a0, s1
    call    libp2p_topic_tidy
    j       9f
1:  li      s3, 0
2:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s3, t0, 4f
    mv      a0, s3
    mv      a1, s1
    call    libp2p_pt
    mv      s4, a0
    ld      t0, PT_FLAGS(s4)
    andi    t0, t0, PTF_FANOUT
    beqz    t0, 3f
    mv      a0, s3
    call    libp2p_peer_at
    mv      s5, a0
    call    libp2p_gs_ready
    beqz    a0, 21f
    fld     fa0, P_SCORE(s5)
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(s9)
    flt.d   t0, fa0, fa1
    beqz    t0, 3f
21: ld      t0, PT_FLAGS(s4)
    andi    t0, t0, ~PTF_FANOUT
    sd      t0, PT_FLAGS(s4)
    ld      t0, T_FANOUT(s2)
    addi    t0, t0, -1
    sd      t0, T_FANOUT(s2)
3:  addi    s3, s3, 1
    j       2b
4:  ld      t0, T_FANOUT(s2)
    CFG     t1, LIBP2P_CFG_D
    bgeu    t0, t1, 9f
    sub     s6, t1, t0
    fld     fa0, (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(s9)
    mv      a0, s1
    li      a1, 0
    li      a2, PTF_FANOUT
    call    libp2p_candidates
    mv      s4, a0
    SCR     s3, SC_LIST
    mv      a0, s3
    mv      a1, s4
    call    libp2p_shuffle
    bltu    s4, s6, 41f
    mv      s4, s6
41: li      s5, 0
5:  bgeu    s5, s4, 9f
    slli    t0, s5, 2
    add     t0, s3, t0
    lwu     a0, 0(t0)
    mv      a1, s1
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    ori     t0, t0, PTF_FANOUT
    sd      t0, PT_FLAGS(a0)
    ld      t0, T_FANOUT(s2)
    addi    t0, t0, 1
    sd      t0, T_FANOUT(s2)
    addi    s5, s5, 1
    j       5b
9:  LEAVE   0
END_FUNCTION libp2p_fanout_maintain

/*
 * libp2p_emit_gossip(topic index): the IDs of the topic's messages in the last
 * mcache_gossip windows (at most max_ihave_length, chosen at random) go as
 * IHAVE to max(D_lazy, gossip_factor x candidates) peers at random that are
 * not in the mesh or fanout and are at or above gossip_threshold. Of those
 * peers, the ones that get partial messages of the topic from us
 * (libp2p_wants_partial) get no IHAVE: PARTIAL_GOSSIP lists them for the
 * application, also when there are no IDs.
 * s1 topic index, s2 topic, s3 IDs then the list of the action, s4 ID
 * count, s5 i, s6 list, s7 count then the action, s8 the first window then
 * the partial count.
 */
LOCAL_FUNCTION libp2p_emit_gossip
    ENTER   0
    mv      s1, a0
    call    libp2p_topic_at
    mv      s2, a0
    SCR     s3, SC_IDS
    li      s4, 0
    ld      t0, ST_HEARTBEATS(s9)           # windows from heartbeats - mcache_gossip + 1
    CFG     t1, LIBP2P_CFG_MCACHE_GOSSIP
    li      s8, 0
    bltu    t0, t1, 10f
    sub     s8, t0, t1
10: addi    s8, s8, 1
    bnez    t1, 1f
    li      s8, NONE                        # mcache_gossip 0: none
1:  li      s5, 0
2:  ld      t0, ST_MC_COUNT(s9)
    bgeu    s5, t0, 4f
    li      t0, (SC_IDS_SIZE / 16)
    bgeu    s4, t0, 4f
    call    libp2p_mc_args
    mul     a0, s5, a3
    add     a0, a0, a2
    ld      t0, MC_USED(a0)
    beqz    t0, 3f
    ld      t0, MC_TOPIC(a0)
    bne     t0, s1, 3f
    ld      t0, MC_WINDOW(a0)
    bltu    t0, s8, 3f
    addi    t0, a0, MC_ID
    ld      t1, MC_ID_LEN(a0)
    slli    t2, s4, 4
    add     t2, s3, t2
    sd      t0, 0(t2)
    sd      t1, 8(t2)
    addi    s4, s4, 1
3:  addi    s5, s5, 1
    j       2b
4:  bnez    s4, 40f
    ld      t0, T_FLAGS(s2)                 # no IDs: partial gossip only
    andi    t0, t0, TF_SUPPORTS_PARTIAL
    beqz    t0, 9f
40: CFG     t0, LIBP2P_CFG_MAX_IHAVE_LENGTH # at most max_ihave_length of them, at random
    bgeu    t0, s4, 5f
    mv      s5, t0
    mv      s6, s4
41: bgeu    s5, s6, 42f                     # move random IDs to the front, then cut
    mv      a0, s6
    call    libp2p_random_below
    addi    s6, s6, -1
    slli    t0, a0, 4
    add     t0, s3, t0
    slli    t1, s6, 4
    add     t1, s3, t1
    ld      t2, 0(t0)
    ld      t3, 8(t0)
    ld      t4, 0(t1)
    ld      t5, 8(t1)
    sd      t4, 0(t0)
    sd      t5, 8(t0)
    sd      t2, 0(t1)
    sd      t3, 8(t1)
    j       41b
42: mv      s4, s5
5:  fld     fa0, (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(s9)
    mv      a0, s1
    li      a1, 0
    li      a2, (PTF_MESH | PTF_FANOUT)
    call    libp2p_candidates
    mv      s7, a0
    beqz    s7, 9f
    SCR     s6, SC_LIST
    mv      a0, s6
    mv      a1, s7
    call    libp2p_shuffle
    fcvt.d.lu fa0, s7                       # max(D_lazy, gossip_factor x candidates)
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_GOSSIP_FACTOR)(s9)
    fmul.d  fa0, fa0, fa1
    li      t0, 0                           # as ARM64 fcvtzu: NaN gives 0
    feq.d   t1, fa0, fa0
    beqz    t1, 51f
    fcvt.lu.d t0, fa0, rtz
51: CFG     t1, LIBP2P_CFG_D_LAZY
    bgeu    t0, t1, 52f
    mv      t0, t1
52: bgeu    t0, s7, 53f
    mv      s7, t0
53: li      s5, 0
    li      s8, 0
6:  bgeu    s5, s7, 7f
    slli    t0, s5, 2
    add     t0, s6, t0
    lwu     a0, 0(t0)
    mv      a1, s1
    call    libp2p_wants_partial
    beqz    a0, 61f
    slli    t0, s5, 2                       # partial gossip: to the front of the list
    add     t0, s6, t0
    lwu     t1, 0(t0)
    slli    t0, s8, 2
    add     t0, s6, t0
    sw      t1, 0(t0)
    addi    s8, s8, 1
    j       62f
61: beqz    s4, 62f
    slli    t0, s5, 2
    add     t0, s6, t0
    lwu     a0, 0(t0)
    call    libp2p_peer_at
    mv      a1, s2
    mv      a2, s3
    mv      a3, s4
    li      a4, 1
    call    libp2p_gs_send_ids
62: addi    s5, s5, 1
    j       6b
7:  beqz    s8, 9f                          # PARTIAL_GOSSIP
    ld      t0, T_LEN(s2)
    addi    t0, t0, (LIBP2P_ACT_PL_TOPIC + 7)
    andi    s5, t0, ~7
    slli    a1, s8, 3
    add     a1, a1, s5
    li      a0, LIBP2P_ACTION_PARTIAL_GOSSIP
    call    libp2p_action
    beqz    a0, 9f
    mv      s7, a0
    ld      a2, T_LEN(s2)
    sd      a2, LIBP2P_ACT_PL_TOPIC_LEN(s7)
    sd      s8, LIBP2P_ACT_PL_COUNT(s7)
    addi    a0, s7, LIBP2P_ACT_PL_TOPIC
    addi    a1, s2, T_NAME
    call    libp2p_copy
    add     s3, s7, s5
    li      s5, 0
8:  bgeu    s5, s8, 9f
    slli    t0, s5, 2
    add     t0, s6, t0
    lwu     a0, 0(t0)
    call    libp2p_peer_at
    mv      a2, a0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    call    libp2p_handle
    slli    t0, s5, 3
    add     t0, s3, t0
    sd      a0, 0(t0)
    addi    s5, s5, 1
    j       8b
9:  LEAVE   0
END_FUNCTION libp2p_emit_gossip

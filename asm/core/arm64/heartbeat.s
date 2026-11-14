/*
 * gossipsub timers of the ARM64 core: validation timeouts, retained scores,
 * the heartbeat (promises, mesh and fanout maintenance, gossip, the message
 * cache windows, the seen cache) and score decay. Included by gossip.s.
 */

/*
 * libp2p_gossip_timers(): messages the application did not judge within
 * validation_ms are dropped (MESSAGE_STATUS dropped); retained scores past
 * retain_score end; the heartbeat and decay run when due. Then a wakeup at
 * the next of these times.
 * x19 slot, x20 slots left, x21 now.
 */
LOCAL_FUNCTION libp2p_gossip_timers
    ENTER   0
    ldr     x21, [x28, #SC_NOW]
    TABLE   x19, ST_PEND_OFF
    ldr     x20, [x27, #ST_PEND_COUNT]
1:  cbz     x20, 3f
    ldr     w9, [x19, #PD_STATE]
    cbz     w9, 2f
    ldr     x0, [x19, #PD_TIME]
    CFG     x9, LIBP2P_CFG_VALIDATION_MS
    add     x0, x0, x9
    cmp     x21, x0
    b.lo    11f
    bl      libp2p_room
    cmp     x0, #64
    b.lo    12f
    mov     x0, x19
    mov     x1, #LIBP2P_MSG_DROPPED
    bl      libp2p_pend_status
    mov     x0, x19
    bl      libp2p_pend_free
    b       2f
11: bl      libp2p_wake_at
    b       2f
12: mov     x0, x21                         /* no room: next step */
    bl      libp2p_wake_at
2:  add     x19, x19, #PD_SIZE
    sub     x20, x20, #1
    b       1b
3:  TABLE   x19, ST_PEER_OFF                /* retained scores */
    ldr     x20, [x27, #ST_PEER_COUNT]
4:  cbz     x20, 5f
    ldr     w9, [x19, #P_STATE]
    cmp     w9, #PS_RETAINED
    b.ne    41f
    ldr     x0, [x19, #P_EXPIRE]
    cmp     x21, x0
    b.lo    42f
    mov     x0, x19
    bl      libp2p_peer_release
    b       41f
42: bl      libp2p_wake_at
41: add     x19, x19, #P_SIZE
    sub     x20, x20, #1
    b       4b
5:  ldr     x9, [x27, #ST_HEARTBEAT_AT]     /* the heartbeat */
    cmp     x21, x9
    b.lo    6f
    bl      libp2p_heartbeat
    ldr     x9, [x27, #ST_HEARTBEAT_AT]
    CFG     x10, LIBP2P_CFG_HEARTBEAT_MS
    add     x9, x9, x10
    add     x11, x21, x10
    cmp     x9, x21
    csel    x9, x11, x9, ls
    str     x9, [x27, #ST_HEARTBEAT_AT]
6:  ldr     x0, [x27, #ST_HEARTBEAT_AT]
    bl      libp2p_wake_at
    CFG     x9, LIBP2P_CFG_SCORING
    cbz     x9, 9f
    ldr     x9, [x27, #ST_DECAY_AT]         /* score decay */
    cmp     x21, x9
    b.lo    8f
    bl      libp2p_score_decay
    ldr     x9, [x27, #ST_DECAY_AT]
    CFG     x10, LIBP2P_CFG_DECAY_INTERVAL_MS
    add     x9, x9, x10
    add     x11, x21, x10
    cmp     x9, x21
    csel    x9, x11, x9, ls
    str     x9, [x27, #ST_DECAY_AT]
8:  ldr     x0, [x27, #ST_DECAY_AT]
    bl      libp2p_wake_at
9:  LEAVE   0
END_FUNCTION libp2p_gossip_timers

/*
 * libp2p_heartbeat(): scores of this heartbeat; IHAVE and IDONTWANT counters reset; broken
 * promises cost a behaviour penalty; mesh maintenance of each topic we
 * subscribe to, fanout maintenance of the others; gossip; then the message
 * cache moves to a new window and old seen entries leave.
 * x19 topic index, x20 topics, x21 topic, x22 now.
 */
LOCAL_FUNCTION libp2p_heartbeat
    ENTER   0
    ldr     x22, [x28, #SC_NOW]
    bl      libp2p_score_all
    TABLE   x19, ST_PEER_OFF                /* IHAVE and IDONTWANT counters */
    ldr     x20, [x27, #ST_PEER_COUNT]
1:  cbz     x20, 2f
    str     xzr, [x19, #P_IHAVE_COUNT]
    str     xzr, [x19, #P_IHAVE_IDS]
    str     xzr, [x19, #P_DW_COUNT]
    add     x19, x19, #P_SIZE
    sub     x20, x20, #1
    b       1b
2:  TABLE   x19, ST_PROMISE_OFF             /* broken promises */
    mov     x20, #LIBP2P_PROMISES
3:  cbz     x20, 4f
    ldr     x9, [x19, #PR_PEER]
    cmn     x9, #1
    b.eq    31f
    ldr     x10, [x19, #PR_DEADLINE]
    cmp     x22, x10
    b.lo    31f
    mov     x10, #NONE
    str     x10, [x19, #PR_PEER]
    mov     x0, x9
    bl      libp2p_peer_at
    mov     x1, #1
    bl      libp2p_behaviour_penalty
31: add     x19, x19, #PR_SIZE
    sub     x20, x20, #1
    b       3b
4:  mov     x19, #0                         /* the topics */
    ldr     x20, [x27, #ST_TOPIC_COUNT]
5:  cmp     x19, x20
    b.hs    7f
    mov     x0, x19
    bl      libp2p_topic_at
    mov     x21, x0
    ldr     x9, [x21, #T_USED]
    cbz     x9, 6f
    ldr     x9, [x21, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    51f
    mov     x0, x19
    bl      libp2p_mesh_maintain
    b       52f
51: ldr     x9, [x21, #T_FANOUT]
    cbz     x9, 6f
    mov     x0, x19
    bl      libp2p_fanout_maintain
52: mov     x0, x19
    bl      libp2p_emit_gossip
6:  add     x19, x19, #1
    b       5b
7:  ldr     x9, [x27, #ST_HEARTBEATS]
    add     x9, x9, #1
    str     x9, [x27, #ST_HEARTBEATS]
    bl      libp2p_mc_shift
    bl      libp2p_seen_expire
    LEAVE   0
END_FUNCTION libp2p_heartbeat

/* libp2p_list_score(list, i) -> d0 the heartbeat score of the peer at list[i]. A leaf. */
LOCAL_FUNCTION libp2p_list_score
    UNWIND_END_PROLOGUE
    ldr     w0, [x0, x1, lsl #2]
    ldr     x1, [x27, #ST_PEER_OFF]
    add     x1, x27, x1
    mov     x2, #P_SIZE
    madd    x0, x0, x2, x1
    ldr     d0, [x0, #P_SCORE]
    ret
END_FUNCTION libp2p_list_score

/* libp2p_list_outbound(list, i) -> 1 when the peer at list[i] is outbound. A leaf. */
LOCAL_FUNCTION libp2p_list_outbound
    UNWIND_END_PROLOGUE
    ldr     w0, [x0, x1, lsl #2]
    ldr     x1, [x27, #ST_PEER_OFF]
    add     x1, x27, x1
    mov     x2, #P_SIZE
    madd    x0, x0, x2, x1
    ldr     x0, [x0, #P_FLAGS]
    and     x0, x0, #PF_OUTBOUND
    ret
END_FUNCTION libp2p_list_outbound

/* libp2p_sort_score(list, count): the list in falling order of score (insertion sort). */
LOCAL_FUNCTION libp2p_sort_score
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, #1
1:  cmp     x21, x20
    b.hs    9f
    ldr     w22, [x19, x21, lsl #2]
    mov     x0, x19
    mov     x1, x21
    bl      libp2p_list_score
    fmov    d16, d0
    mov     x23, x21
2:  cbz     x23, 3f
    mov     x0, x19
    sub     x1, x23, #1
    bl      libp2p_list_score
    fcmp    d0, d16
    b.ge    3f
    sub     x9, x23, #1
    ldr     w10, [x19, x9, lsl #2]
    str     w10, [x19, x23, lsl #2]
    mov     x23, x9
    b       2b
3:  str     w22, [x19, x23, lsl #2]
    add     x21, x21, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_sort_score

/* libp2p_add_from_list(topic index, count): the first count peers of the list join the mesh. */
LOCAL_FUNCTION libp2p_add_from_list
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    SCR     x21, SC_LIST
    mov     x22, #0
1:  cmp     x22, x20
    b.hs    9f
    ldr     w0, [x21, x22, lsl #2]
    mov     x1, x19
    bl      libp2p_mesh_add
    add     x22, x22, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_add_from_list

/*
 * libp2p_mesh_maintain(topic index): mesh peers that are not ready or score
 * below 0 leave with PRUNE; below D_low the mesh grows to D; above D_high
 * it shrinks to D, keeping the D_score best and D_out outbound peers;
 * then it takes outbound peers up to D_out; every opportunistic_ticks
 * heartbeats, a mesh whose median score is below the threshold takes peers
 * above the median.
 * x19 topic index, x20 topic, x21 list, x22 count, x23 i, x24 mesh count.
 */
LOCAL_FUNCTION libp2p_mesh_maintain
    ENTER   0
    mov     x19, x0
    bl      libp2p_topic_at
    mov     x20, x0
    SCR     x21, SC_LIST
    mov     x23, #0                         /* mesh peers not ready or below 0 */
1:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x23, x9
    b.hs    3f
    mov     x0, x23
    mov     x1, x19
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    2f
    mov     x0, x23
    bl      libp2p_peer_at
    mov     x24, x0
    bl      libp2p_gs_ready
    cbz     x0, 11f
    ldr     d0, [x24, #P_SCORE]
    fcmp    d0, #0.0
    b.pl    2f
    mov     x0, x23
    mov     x1, x19
    CFG     x2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    bl      libp2p_prune_to
11: mov     x0, x23
    mov     x1, x19
    bl      libp2p_mesh_remove
2:  add     x23, x23, #1
    b       1b
3:  ldr     x24, [x20, #T_MESH]             /* too few */
    CFG     x9, LIBP2P_CFG_D_LOW
    cmp     x24, x9
    b.hs    4f
    fmov    d0, xzr
    mov     x0, x19
    mov     x1, #0
    mov     x2, #(PTF_MESH | CAND_BACKOFF)
    bl      libp2p_candidates
    mov     x22, x0
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_shuffle
    CFG     x9, LIBP2P_CFG_D
    sub     x9, x9, x24
    cmp     x22, x9
    csel    x1, x22, x9, lo
    mov     x0, x19
    bl      libp2p_add_from_list
4:  ldr     x24, [x20, #T_MESH]             /* too many */
    CFG     x9, LIBP2P_CFG_D_HIGH
    cmp     x24, x9
    b.ls    6f
    mov     x9, #0xFFF0000000000000
    fmov    d0, x9
    mov     x0, x19
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    mov     x22, x0
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_sort_score
    CFG     x25, LIBP2P_CFG_D_SCORE         /* the best D_score stay; the rest in random order */
    cmp     x25, x22
    csel    x25, x25, x22, lo
    add     x0, x21, x25, lsl #2
    sub     x1, x22, x25
    bl      libp2p_shuffle
    CFG     x25, LIBP2P_CFG_D               /* kept: list[0..D) */
    mov     x0, x21
    mov     x1, x25
    mov     x2, x22
    bl      libp2p_keep_outbound
    mov     x23, x25
5:  cmp     x23, x22
    b.hs    6f
    ldr     w0, [x21, x23, lsl #2]
    mov     x1, x19
    CFG     x2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    bl      libp2p_prune_to
    ldr     w0, [x21, x23, lsl #2]
    mov     x1, x19
    bl      libp2p_mesh_remove
    add     x23, x23, #1
    b       5b
6:  ldr     x24, [x20, #T_MESH]             /* outbound quota */
    CFG     x9, LIBP2P_CFG_D_LOW
    cmp     x24, x9
    b.lo    7f
    mov     x9, #0xFFF0000000000000
    fmov    d0, x9
    mov     x0, x19
    mov     x1, #(PTF_MESH | CAND_OUTBOUND)
    mov     x2, #0
    bl      libp2p_candidates
    CFG     x9, LIBP2P_CFG_D_OUT
    subs    x25, x9, x0
    b.ls    7f
    fmov    d0, xzr
    mov     x0, x19
    mov     x1, #CAND_OUTBOUND
    mov     x2, #(PTF_MESH | CAND_BACKOFF)
    bl      libp2p_candidates
    mov     x22, x0
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_shuffle
    cmp     x22, x25
    csel    x1, x22, x25, lo
    mov     x0, x19
    bl      libp2p_add_from_list
7:  ldr     x9, [x27, #ST_HEARTBEATS]       /* opportunistic grafting */
    CFG     x10, LIBP2P_CFG_OPPORTUNISTIC_TICKS
    cbz     x10, 9f
    udiv    x11, x9, x10
    msub    x11, x11, x10, x9
    cbnz    x11, 9f
    ldr     x24, [x20, #T_MESH]
    cmp     x24, #1
    b.ls    9f
    mov     x9, #0xFFF0000000000000
    fmov    d0, x9
    mov     x0, x19
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    mov     x22, x0
    cmp     x22, #1
    b.ls    9f
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_sort_score
    mov     x0, x21
    lsr     x1, x22, #1
    bl      libp2p_list_score                   /* the median */
    fmov    d16, d0
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_OPPORTUNISTIC_THRESHOLD)]
    fcmp    d16, d1
    b.ge    9f
    fmov    x9, d16                         /* above the median: the next double up is the floor */
    add     x9, x9, #1
    fmov    d0, x9
    fcmp    d16, #0.0
    b.ge    71f
    sub     x9, x9, #2
    fmov    d0, x9
71: mov     x0, x19
    mov     x1, #0
    mov     x2, #(PTF_MESH | CAND_BACKOFF)
    bl      libp2p_candidates
    mov     x22, x0
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_shuffle
    CFG     x9, LIBP2P_CFG_OPPORTUNISTIC_PEERS
    cmp     x22, x9
    csel    x1, x22, x9, lo
    mov     x0, x19
    bl      libp2p_add_from_list
9:  LEAVE   0
END_FUNCTION libp2p_mesh_maintain

/*
 * libp2p_keep_outbound(list, kept, count): when list[0..kept) has fewer than
 * D_out outbound peers, outbound peers from list[kept..count) take the
 * places of the last inbound kept peers.
 * x19 list, x20 kept, x21 count, x22 outbound kept, x23 i, x24 j.
 */
LOCAL_FUNCTION libp2p_keep_outbound
    ENTER   0
    mov     x19, x0
    cmp     x1, x2
    csel    x20, x1, x2, lo
    mov     x21, x2
    mov     x22, #0
    mov     x23, #0
1:  cmp     x23, x20
    b.hs    2f
    mov     x0, x19
    mov     x1, x23
    bl      libp2p_list_outbound
    add     x22, x22, x0
    add     x23, x23, #1
    b       1b
2:  mov     x23, x20                        /* outbound candidates beyond the kept part */
    mov     x24, x20                        /* the next kept place to give up, from the end */
3:  CFG     x9, LIBP2P_CFG_D_OUT
    cmp     x22, x9
    b.hs    9f
    cmp     x23, x21
    b.hs    9f
    mov     x0, x19
    mov     x1, x23
    bl      libp2p_list_outbound
    cbz     x0, 5f
4:  cbz     x24, 9f                         /* an inbound kept peer to swap out */
    sub     x24, x24, #1
    mov     x0, x19
    mov     x1, x24
    bl      libp2p_list_outbound
    cbnz    x0, 4b
    ldr     w9, [x19, x23, lsl #2]
    ldr     w10, [x19, x24, lsl #2]
    str     w9, [x19, x24, lsl #2]
    str     w10, [x19, x23, lsl #2]
    add     x22, x22, #1
5:  add     x23, x23, #1
    b       3b
9:  LEAVE   0
END_FUNCTION libp2p_keep_outbound

/*
 * libp2p_fanout_maintain(topic index): a fanout unused for fanout_ttl ends;
 * else peers below publish_threshold leave it and it grows to D.
 * x19 topic index, x20 topic, x21 peer index.
 */
LOCAL_FUNCTION libp2p_fanout_maintain
    ENTER   0
    mov     x19, x0
    bl      libp2p_topic_at
    mov     x20, x0
    ldr     x9, [x28, #SC_NOW]
    ldr     x10, [x20, #T_FANOUT_LAST]
    sub     x9, x9, x10
    CFG     x10, LIBP2P_CFG_FANOUT_TTL_MS
    cmp     x9, x10
    b.ls    1f
    mov     x21, x19                        /* libp2p_fanout_clear_topic takes x19 topic, x20 index */
    mov     x9, x20
    mov     x20, x21
    mov     x19, x9
    bl      libp2p_fanout_clear_topic
    mov     x0, x19
    bl      libp2p_topic_tidy
    b       9f
1:  mov     x21, #0
2:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x21, x9
    b.hs    4f
    mov     x0, x21
    mov     x1, x19
    bl      libp2p_pt
    mov     x22, x0
    ldr     x9, [x22, #PT_FLAGS]
    tst     x9, #PTF_FANOUT
    b.eq    3f
    mov     x0, x21
    bl      libp2p_peer_at
    mov     x23, x0
    bl      libp2p_gs_ready
    cbz     x0, 21f
    ldr     d0, [x23, #P_SCORE]
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)]
    fcmp    d0, d1
    b.pl    3f
21: ldr     x9, [x22, #PT_FLAGS]
    and     x9, x9, #~PTF_FANOUT
    str     x9, [x22, #PT_FLAGS]
    ldr     x9, [x20, #T_FANOUT]
    sub     x9, x9, #1
    str     x9, [x20, #T_FANOUT]
3:  add     x21, x21, #1
    b       2b
4:  ldr     x24, [x20, #T_FANOUT]
    CFG     x9, LIBP2P_CFG_D
    subs    x24, x9, x24
    b.ls    9f
    ldr     d0, [x27, #(ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)]
    mov     x0, x19
    mov     x1, #0
    mov     x2, #PTF_FANOUT
    bl      libp2p_candidates
    mov     x22, x0
    SCR     x21, SC_LIST
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_shuffle
    cmp     x22, x24
    csel    x22, x22, x24, lo
    mov     x23, #0
5:  cmp     x23, x22
    b.hs    9f
    ldr     w0, [x21, x23, lsl #2]
    mov     x1, x19
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    orr     x9, x9, #PTF_FANOUT
    str     x9, [x0, #PT_FLAGS]
    ldr     x9, [x20, #T_FANOUT]
    add     x9, x9, #1
    str     x9, [x20, #T_FANOUT]
    add     x23, x23, #1
    b       5b
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
 * x19 topic index, x20 topic, x21 IDs, then the list of the action, x22 ID
 * count, x23 i, x24 list, x25 count, then the action, x26 partial count.
 */
LOCAL_FUNCTION libp2p_emit_gossip
    ENTER   0
    mov     x19, x0
    bl      libp2p_topic_at
    mov     x20, x0
    SCR     x21, SC_IDS
    mov     x22, #0
    ldr     x9, [x27, #ST_HEARTBEATS]       /* windows from heartbeats - mcache_gossip + 1 */
    CFG     x10, LIBP2P_CFG_MCACHE_GOSSIP
    subs    x26, x9, x10
    csel    x26, xzr, x26, lo
    add     x26, x26, #1
    cbnz    x10, 1f
    mov     x26, #NONE                      /* mcache_gossip 0: none */
1:  mov     x23, #0
2:  ldr     x9, [x27, #ST_MC_COUNT]
    cmp     x23, x9
    b.hs    4f
    MOV64   x9, (SC_IDS_SIZE / 16)
    cmp     x22, x9
    b.hs    4f
    bl      libp2p_mc_args
    madd    x0, x23, x3, x2
    ldr     x9, [x0, #MC_USED]
    cbz     x9, 3f
    ldr     x9, [x0, #MC_TOPIC]
    cmp     x9, x19
    b.ne    3f
    ldr     x9, [x0, #MC_WINDOW]
    cmp     x9, x26
    b.lo    3f
    add     x9, x0, #MC_ID
    ldr     x10, [x0, #MC_ID_LEN]
    add     x11, x21, x22, lsl #4
    stp     x9, x10, [x11]
    add     x22, x22, #1
3:  add     x23, x23, #1
    b       2b
4:  cbnz    x22, 40f
    ldr     x9, [x20, #T_FLAGS]             /* no IDs: partial gossip only */
    tst     x9, #TF_SUPPORTS_PARTIAL
    b.eq    9f
40: CFG     x9, LIBP2P_CFG_MAX_IHAVE_LENGTH /* at most max_ihave_length of them, at random */
    cmp     x22, x9
    b.ls    5f
    mov     x23, x9
    mov     x24, x22
41: cmp     x24, x23                        /* move random IDs to the front, then cut */
    b.ls    42f
    mov     x0, x24
    bl      libp2p_random_below
    sub     x24, x24, #1
    add     x9, x21, x0, lsl #4
    add     x10, x21, x24, lsl #4
    ldp     x11, x12, [x9]
    ldp     x13, x14, [x10]
    stp     x13, x14, [x9]
    stp     x11, x12, [x10]
    b       41b
42: mov     x22, x23
5:  ldr     d0, [x27, #(ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)]
    mov     x0, x19
    mov     x1, #0
    mov     x2, #(PTF_MESH | PTF_FANOUT)
    bl      libp2p_candidates
    mov     x25, x0
    cbz     x25, 9f
    SCR     x24, SC_LIST
    mov     x0, x24
    mov     x1, x25
    bl      libp2p_shuffle
    ucvtf   d0, x25                         /* max(D_lazy, gossip_factor x candidates) */
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_GOSSIP_FACTOR)]
    fmul    d0, d0, d1
    fcvtzu  x9, d0
    CFG     x10, LIBP2P_CFG_D_LAZY
    cmp     x9, x10
    csel    x9, x9, x10, hs
    cmp     x9, x25
    csel    x25, x9, x25, lo
    mov     x23, #0
    mov     x26, #0
6:  cmp     x23, x25
    b.hs    7f
    ldr     w0, [x24, x23, lsl #2]
    mov     x1, x19
    bl      libp2p_wants_partial
    cbz     x0, 61f
    ldr     w9, [x24, x23, lsl #2]          /* partial gossip: to the front of the list */
    str     w9, [x24, x26, lsl #2]
    add     x26, x26, #1
    b       62f
61: cbz     x22, 62f
    ldr     w0, [x24, x23, lsl #2]
    bl      libp2p_peer_at
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    mov     x4, #1
    bl      libp2p_gs_send_ids
62: add     x23, x23, #1
    b       6b
7:  cbz     x26, 9f                         /* PARTIAL_GOSSIP */
    ldr     x9, [x20, #T_LEN]
    add     x9, x9, #(LIBP2P_ACT_PL_TOPIC + 7)
    and     x23, x9, #~7
    add     x1, x23, x26, lsl #3
    mov     x0, #LIBP2P_ACTION_PARTIAL_GOSSIP
    bl      libp2p_action
    cbz     x0, 9f
    mov     x25, x0
    ldr     x2, [x20, #T_LEN]
    str     x2, [x25, #LIBP2P_ACT_PL_TOPIC_LEN]
    str     x26, [x25, #LIBP2P_ACT_PL_COUNT]
    add     x0, x25, #LIBP2P_ACT_PL_TOPIC
    add     x1, x20, #T_NAME
    bl      libp2p_copy
    add     x21, x25, x23
    mov     x23, #0
8:  cmp     x23, x26
    b.hs    9f
    ldr     w0, [x24, x23, lsl #2]
    bl      libp2p_peer_at
    mov     x2, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x21, x23, lsl #3]
    add     x23, x23, #1
    b       8b
9:  LEAVE   0
END_FUNCTION libp2p_emit_gossip

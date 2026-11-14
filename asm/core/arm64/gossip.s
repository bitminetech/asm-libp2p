/*
 * gossipsub of the ARM64 core (/meshsub/1.1.0 with StrictNoSign, the
 * IDONTWANT of /meshsub/1.2.0, the Extensions control message of
 * /meshsub/1.3.0 and the Partial Messages extension): topics, the seen
 * cache, the message cache, messages waiting for the application, IWANT
 * promises, RPCs in and out, and the events of the application. The
 * heartbeat and scores are in heartbeat.s and score.s. Included by
 * libp2p.s.
 */

/* ---------------------------------------------------------------- Tables */

/* libp2p_peer_at(index) -> the peer slot. A leaf. */
LOCAL_FUNCTION libp2p_peer_at
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_PEER_OFF]
    add     x1, x27, x1
    mov     x2, #P_SIZE
    madd    x0, x0, x2, x1
    ret
END_FUNCTION libp2p_peer_at

/* libp2p_peer_idx(peer) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_peer_idx
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_PEER_OFF]
    add     x1, x27, x1
    sub     x0, x0, x1
    mov     x1, #P_SIZE
    udiv    x0, x0, x1
    ret
END_FUNCTION libp2p_peer_idx

/* libp2p_topic_at(index) -> the topic slot. A leaf. */
LOCAL_FUNCTION libp2p_topic_at
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_TOPIC_OFF]
    add     x1, x27, x1
    mov     x2, #T_SIZE
    madd    x0, x0, x2, x1
    ret
END_FUNCTION libp2p_topic_at

/* libp2p_topic_idx(topic) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_topic_idx
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_TOPIC_OFF]
    add     x1, x27, x1
    sub     x0, x0, x1
    mov     x1, #T_SIZE
    udiv    x0, x0, x1
    ret
END_FUNCTION libp2p_topic_idx

/* libp2p_pt(peer index, topic index) -> the peer x topic entry. A leaf. */
LOCAL_FUNCTION libp2p_pt
    UNWIND_END_PROLOGUE
    ldr     x2, [x27, #ST_TOPIC_COUNT]
    madd    x0, x0, x2, x1
    ldr     x2, [x27, #ST_PT_OFF]
    add     x2, x27, x2
    mov     x3, #PT_SIZE
    madd    x0, x0, x3, x2
    ret
END_FUNCTION libp2p_pt

/*
 * libp2p_topic_find(name, n) -> the topic slot with the name, or 0.
 * x19 name, x20 n, x21 hash, x22 slot, x23 slots left.
 */
LOCAL_FUNCTION libp2p_topic_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_hash
    mov     x21, x0
    TABLE   x22, ST_TOPIC_OFF
    ldr     x23, [x27, #ST_TOPIC_COUNT]
1:  cbz     x23, 8f
    ldr     x9, [x22, #T_USED]
    cbz     x9, 2f
    ldr     x9, [x22, #T_HASH]
    cmp     x9, x21
    b.ne    2f
    add     x0, x22, #T_NAME
    ldr     x1, [x22, #T_LEN]
    mov     x2, x19
    mov     x3, x20
    bl      libp2p_compare
    cbz     x0, 2f
    mov     x0, x22
    b       9f
2:  add     x22, x22, #T_SIZE
    sub     x23, x23, #1
    b       1b
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_topic_find

/* libp2p_topic_get(name, n) -> the topic slot with the name, a new one when there is none; 0 when the table is full. */
LOCAL_FUNCTION libp2p_topic_get
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_topic_find
    cbnz    x0, 9f
    TABLE   x22, ST_TOPIC_OFF
    ldr     x23, [x27, #ST_TOPIC_COUNT]
1:  cbz     x23, 8f
    ldr     x9, [x22, #T_USED]
    cbz     x9, 2f
    add     x22, x22, #T_SIZE
    sub     x23, x23, #1
    b       1b
2:  mov     x0, x22
    mov     x1, #T_SIZE
    bl      libp2p_zero
    mov     x9, #1
    str     x9, [x22, #T_USED]
    str     x20, [x22, #T_LEN]
    add     x0, x22, #T_NAME
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_hash
    str     x0, [x22, #T_HASH]
    mov     x0, x22
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_topic_get

/* libp2p_topic_tidy(topic): a topic nobody uses and without score parameters becomes free. A leaf. */
LOCAL_FUNCTION libp2p_topic_tidy
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #T_FLAGS]
    ldr     x2, [x0, #T_PEERS]
    orr     x1, x1, x2
    ldr     x2, [x0, #T_MESH]
    orr     x1, x1, x2
    ldr     x2, [x0, #T_FANOUT]
    orr     x1, x1, x2
    cbnz    x1, 9f
    str     xzr, [x0, #T_USED]
9:  ret
END_FUNCTION libp2p_topic_tidy

/* libp2p_gs_ready(peer) -> 1 when the peer is connected and our gossipsub stream to it is open. A leaf. */
LOCAL_FUNCTION libp2p_gs_ready
    UNWIND_END_PROLOGUE
    ldr     w1, [x0, #P_STATE]
    cmp     w1, #PS_CONNECTED
    b.ne    8f
    ldr     x1, [x0, #P_FLAGS]
    tst     x1, #PF_GOSSIP
    b.eq    8f
    ldr     x1, [x0, #P_GS_OUT]
    cmn     x1, #1
    b.eq    8f
    mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_gs_ready

/* ---------------------------------------------------------------- Hash indexes of message IDs */

/*
 * libp2p_idx_find(index, slots, entries, stride, id, n) -> the entry index of
 * the message ID, or NONE. The index is open addressing with linear
 * probing; a slot holds an entry index + 1, or 0. Entries hold the ID
 * length at 0 and the ID at 8.
 * x19 index, x20 slots, x21 entries, x22 stride, x23 id, x24 n, x25 slot.
 */
LOCAL_FUNCTION libp2p_idx_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x0, x23
    mov     x1, x24
    bl      libp2p_hash
    udiv    x9, x0, x20
    msub    x25, x9, x20, x0
1:  ldr     w26, [x19, x25, lsl #2]
    cbz     w26, 8f
    sub     x26, x26, #1
    madd    x10, x26, x22, x21
    ldr     x1, [x10]
    add     x0, x10, #8
    mov     x2, x23
    mov     x3, x24
    bl      libp2p_compare
    cbnz    x0, 7f
    add     x25, x25, #1
    cmp     x25, x20
    csel    x25, xzr, x25, hs
    b       1b
7:  mov     x0, x26
    b       9f
8:  mov     x0, #NONE
9:  LEAVE   0
END_FUNCTION libp2p_idx_find

/* libp2p_idx_add(index, slots, entry, hash): puts entry + 1 in the first empty slot from hash mod slots. A leaf. */
LOCAL_FUNCTION libp2p_idx_add
    UNWIND_END_PROLOGUE
    udiv    x4, x3, x1
    msub    x4, x4, x1, x3
    add     w2, w2, #1
1:  ldr     w5, [x0, x4, lsl #2]
    cbz     w5, 2f
    add     x4, x4, #1
    cmp     x4, x1
    csel    x4, xzr, x4, hs
    b       1b
2:  str     w2, [x0, x4, lsl #2]
    ret
END_FUNCTION libp2p_idx_add

/*
 * libp2p_idx_del(index, slots, entries, stride, entry): takes entry out of the
 * index and moves later entries of the probe run back, so every lookup
 * still finds its entry.
 * x19 index, x20 slots, x21 entries, x22 stride, x23 hole, x24 position.
 */
LOCAL_FUNCTION libp2p_idx_del
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    add     w9, w4, #1                      /* find the slot that holds it */
    madd    x10, x4, x22, x21
    add     x0, x10, #8
    ldr     x1, [x10]
    mov     w26, w9
    bl      libp2p_hash
    udiv    x9, x0, x20
    msub    x23, x9, x20, x0
1:  ldr     w9, [x19, x23, lsl #2]
    cbz     w9, 9f
    cmp     w9, w26
    b.eq    2f
    add     x23, x23, #1
    cmp     x23, x20
    csel    x23, xzr, x23, hs
    b       1b
2:  mov     x24, x23                        /* the hole at x23 */
3:  add     x24, x24, #1
    cmp     x24, x20
    csel    x24, xzr, x24, hs
    ldr     w25, [x19, x24, lsl #2]
    cbz     w25, 8f
    sub     x9, x25, #1                     /* the home slot of the entry at x24 */
    madd    x10, x9, x22, x21
    add     x0, x10, #8
    ldr     x1, [x10]
    bl      libp2p_hash
    udiv    x9, x0, x20
    msub    x9, x9, x20, x0
    /* move it into the hole unless its home lies cyclically in (hole, position] */
    cmp     x23, x24
    b.hi    4f
    cmp     x9, x23
    b.ls    5f
    cmp     x9, x24
    b.hi    5f
    b       3b
4:  cmp     x9, x23
    b.hi    3b
    cmp     x9, x24
    b.ls    3b
5:  str     w25, [x19, x23, lsl #2]
    mov     x23, x24
    b       3b
8:  str     wzr, [x19, x23, lsl #2]
9:  LEAVE   0
END_FUNCTION libp2p_idx_del

/* ---------------------------------------------------------------- Seen cache */

/* libp2p_seen_args(): x0 index, x1 slots, x2 entries, x3 stride of the seen cache. A leaf. */
LOCAL_FUNCTION libp2p_seen_args
    UNWIND_END_PROLOGUE
    ldr     x0, [x27, #ST_SEEN_INDEX_OFF]
    add     x0, x27, x0
    ldr     x1, [x27, #ST_SEEN_COUNT]
    lsl     x1, x1, #1
    ldr     x2, [x27, #ST_SEEN_OFF]
    add     x2, x27, x2
    mov     x3, #SN_SIZE
    ret
END_FUNCTION libp2p_seen_args

/* libp2p_seen_find(id, n) -> the seen entry of the message ID, or 0. */
LOCAL_FUNCTION libp2p_seen_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_seen_args
    mov     x4, x19
    mov     x5, x20
    mov     x21, x2
    bl      libp2p_idx_find
    cmn     x0, #1
    b.eq    8f
    mov     x9, #SN_SIZE
    madd    x0, x0, x9, x21
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_seen_find

/* libp2p_seen_drop_tail(): the oldest seen entry leaves the ring and the index. */
LOCAL_FUNCTION libp2p_seen_drop_tail
    ENTER   0
    ldr     x19, [x27, #ST_SEEN_USED]
    cbz     x19, 9f
    ldr     x20, [x27, #ST_SEEN_HEAD]
    ldr     x21, [x27, #ST_SEEN_COUNT]
    add     x20, x20, x21                   /* tail = (head - used) mod count */
    sub     x20, x20, x19
    udiv    x9, x20, x21
    msub    x20, x9, x21, x20
    bl      libp2p_seen_args
    mov     x4, x20
    bl      libp2p_idx_del
    sub     x19, x19, #1
    str     x19, [x27, #ST_SEEN_USED]
9:  LEAVE   0
END_FUNCTION libp2p_seen_drop_tail

/* libp2p_seen_tail() -> the oldest seen entry, or 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_tail
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_SEEN_USED]
    cbz     x1, 8f
    ldr     x2, [x27, #ST_SEEN_HEAD]
    ldr     x3, [x27, #ST_SEEN_COUNT]
    add     x2, x2, x3
    sub     x2, x2, x1
    udiv    x4, x2, x3
    msub    x2, x4, x3, x2
    ldr     x4, [x27, #ST_SEEN_OFF]
    add     x4, x27, x4
    mov     x5, #SN_SIZE
    madd    x0, x2, x5, x4
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_seen_tail

/*
 * libp2p_seen_add(id, n, topic, status) -> the new seen entry, first seen now,
 * with no deliverers. When the ring is full the oldest entry goes first.
 */
LOCAL_FUNCTION libp2p_seen_add
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x9, [x27, #ST_SEEN_USED]
    ldr     x10, [x27, #ST_SEEN_COUNT]
    cmp     x9, x10
    b.lo    1f
    bl      libp2p_seen_drop_tail
1:  ldr     x23, [x27, #ST_SEEN_HEAD]
    TABLE   x24, ST_SEEN_OFF
    mov     x9, #SN_SIZE
    madd    x24, x23, x9, x24
    mov     x0, x24
    mov     x1, #SN_SIZE
    bl      libp2p_zero
    str     x20, [x24, #SN_ID_LEN]
    add     x0, x24, #SN_ID
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    ldr     x9, [x28, #SC_NOW]
    str     x9, [x24, #SN_TIME]
    str     x22, [x24, #SN_STATUS]
    str     w21, [x24, #SN_TOPIC]
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_hash
    mov     x3, x0
    bl      libp2p_seen_args_keep
    mov     x2, x23
    bl      libp2p_idx_add
    ldr     x9, [x27, #ST_SEEN_HEAD]
    add     x9, x9, #1
    ldr     x10, [x27, #ST_SEEN_COUNT]
    cmp     x9, x10
    csel    x9, xzr, x9, hs
    str     x9, [x27, #ST_SEEN_HEAD]
    ldr     x9, [x27, #ST_SEEN_USED]
    add     x9, x9, #1
    str     x9, [x27, #ST_SEEN_USED]
    mov     x0, x24
    LEAVE   0
END_FUNCTION libp2p_seen_add

/* libp2p_seen_args_keep(): x0 the seen index and x1 its slots, leaving x2 and x3 as they are. A leaf. */
LOCAL_FUNCTION libp2p_seen_args_keep
    UNWIND_END_PROLOGUE
    ldr     x0, [x27, #ST_SEEN_INDEX_OFF]
    add     x0, x27, x0
    ldr     x1, [x27, #ST_SEEN_COUNT]
    lsl     x1, x1, #1
    ret
END_FUNCTION libp2p_seen_args_keep

/* libp2p_seen_expire(): seen entries older than seen_ttl leave. */
LOCAL_FUNCTION libp2p_seen_expire
    ENTER   0
    ldr     x19, [x28, #SC_NOW]
    CFG     x20, LIBP2P_CFG_SEEN_TTL_MS
1:  bl      libp2p_seen_tail
    cbz     x0, 9f
    ldr     x9, [x0, #SN_TIME]
    add     x9, x9, x20
    cmp     x9, x19
    b.hi    9f
    bl      libp2p_seen_drop_tail
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_seen_expire

/* ---------------------------------------------------------------- Message cache */

/* libp2p_mc_args(): x0 index, x1 slots, x2 entries, x3 stride of the message cache. A leaf. */
LOCAL_FUNCTION libp2p_mc_args
    UNWIND_END_PROLOGUE
    ldr     x0, [x27, #ST_MC_INDEX_OFF]
    add     x0, x27, x0
    ldr     x1, [x27, #ST_MC_COUNT]
    lsl     x1, x1, #1
    ldr     x2, [x27, #ST_MC_OFF]
    add     x2, x27, x2
    ldr     x3, [x27, #ST_MC_STRIDE]
    ret
END_FUNCTION libp2p_mc_args

/* libp2p_mc_find(id, n) -> the message cache entry of the message ID, or 0. */
LOCAL_FUNCTION libp2p_mc_find
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_mc_args
    mov     x21, x2
    mov     x22, x3
    mov     x4, x19
    mov     x5, x20
    bl      libp2p_idx_find
    cmn     x0, #1
    b.eq    8f
    madd    x0, x0, x22, x21
    b       9f
8:  mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_mc_find

/* libp2p_mc_tail() -> x0 the oldest message cache entry or 0, x1 its index. A leaf. */
LOCAL_FUNCTION libp2p_mc_tail
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_MC_USED]
    cbz     x1, 8f
    ldr     x2, [x27, #ST_MC_HEAD]
    ldr     x3, [x27, #ST_MC_COUNT]
    add     x2, x2, x3
    sub     x2, x2, x1
    udiv    x4, x2, x3
    msub    x1, x4, x3, x2
    ldr     x4, [x27, #ST_MC_OFF]
    add     x4, x27, x4
    ldr     x5, [x27, #ST_MC_STRIDE]
    madd    x0, x1, x5, x4
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_mc_tail

/* libp2p_mc_drop_tail(): the oldest message cache entry leaves, with its data. */
LOCAL_FUNCTION libp2p_mc_drop_tail
    ENTER   0
    bl      libp2p_mc_tail
    cbz     x0, 9f
    mov     x19, x0
    mov     x20, x1
    ldr     x0, [x19, #MC_DATA]
    bl      libp2p_heap_free
    str     xzr, [x19, #MC_USED]
    bl      libp2p_mc_args
    mov     x4, x20
    bl      libp2p_idx_del
    ldr     x9, [x27, #ST_MC_USED]
    sub     x9, x9, #1
    str     x9, [x27, #ST_MC_USED]
9:  LEAVE   0
END_FUNCTION libp2p_mc_drop_tail

/*
 * libp2p_mc_put(id, n, topic, data, length): a message in the current window of
 * the cache, which now owns the heap block of its data. When the cache is
 * full the oldest entry goes first.
 */
LOCAL_FUNCTION libp2p_mc_put
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x27, #ST_MC_USED]
    ldr     x10, [x27, #ST_MC_COUNT]
    cmp     x9, x10
    b.lo    1f
    bl      libp2p_mc_drop_tail
1:  ldr     x24, [x27, #ST_MC_HEAD]
    bl      libp2p_mc_args
    madd    x25, x24, x3, x2
    mov     x0, x25
    mov     x1, x3
    bl      libp2p_zero
    str     x20, [x25, #MC_ID_LEN]
    add     x0, x25, #MC_ID
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_copy
    str     x21, [x25, #MC_TOPIC]
    str     x22, [x25, #MC_DATA]
    str     x23, [x25, #MC_DATA_LEN]
    ldr     x9, [x27, #ST_HEARTBEATS]
    str     x9, [x25, #MC_WINDOW]
    mov     x9, #1
    str     x9, [x25, #MC_USED]
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_hash
    mov     x3, x0
    ldr     x0, [x27, #ST_MC_INDEX_OFF]
    add     x0, x27, x0
    ldr     x1, [x27, #ST_MC_COUNT]
    lsl     x1, x1, #1
    mov     x2, x24
    bl      libp2p_idx_add
    ldr     x9, [x27, #ST_MC_HEAD]
    add     x9, x9, #1
    ldr     x10, [x27, #ST_MC_COUNT]
    cmp     x9, x10
    csel    x9, xzr, x9, hs
    str     x9, [x27, #ST_MC_HEAD]
    ldr     x9, [x27, #ST_MC_USED]
    add     x9, x9, #1
    str     x9, [x27, #ST_MC_USED]
    LEAVE   0
END_FUNCTION libp2p_mc_put

/* libp2p_mc_shift(): entries of windows mcache_len or more heartbeats old leave. */
LOCAL_FUNCTION libp2p_mc_shift
    ENTER   0
    ldr     x19, [x27, #ST_HEARTBEATS]
    CFG     x20, LIBP2P_CFG_MCACHE_LEN
1:  bl      libp2p_mc_tail
    cbz     x0, 9f
    ldr     x9, [x0, #MC_WINDOW]
    add     x9, x9, x20
    cmp     x9, x19
    b.hi    9f
    bl      libp2p_mc_drop_tail
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_mc_shift

/*
 * libp2p_mc_sent(entry, peer index) -> 1 when the message may go to the peer
 * for an IWANT once more (fewer than retransmission sends), counting it;
 * else 0. Two bits for each peer. A leaf.
 */
LOCAL_FUNCTION libp2p_mc_sent
    UNWIND_END_PROLOGUE
    lsr     x2, x1, #5                      /* word */
    and     x3, x1, #31
    lsl     x3, x3, #1                      /* bit */
    add     x4, x0, #MC_TX
    ldr     x5, [x4, x2, lsl #3]
    lsr     x6, x5, x3
    and     x6, x6, #3
    ldr     x7, [x27, #(ST_CONFIG + LIBP2P_CFG_RETRANSMISSION)]
    cmp     x7, #3
    mov     x8, #3
    csel    x7, x7, x8, lo
    cmp     x6, x7
    b.hs    8f
    mov     x8, #1
    lsl     x8, x8, x3
    add     x5, x5, x8
    str     x5, [x4, x2, lsl #3]
    mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_mc_sent

/* ---------------------------------------------------------------- Messages waiting for the application */

/* libp2p_pend(handle) -> the pending message of a handle, or 0. */
LOCAL_FUNCTION libp2p_pend
    ENTER   0
    mov     x3, x0
    mov     x0, #ST_PEND_OFF
    mov     x1, #ST_PEND_COUNT
    mov     x2, #PD_SIZE
    bl      libp2p_slot
    LEAVE   0
END_FUNCTION libp2p_pend

/* libp2p_pend_free(pending): frees its data block (when it still owns one) and the slot. */
LOCAL_FUNCTION libp2p_pend_free
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #PD_DATA]
    bl      libp2p_heap_free
    str     xzr, [x19, #PD_DATA]
    str     wzr, [x19, #PD_STATE]
    LEAVE   0
END_FUNCTION libp2p_pend_free

/* libp2p_pend_status(pending, status): MESSAGE_STATUS for the application. */
LOCAL_FUNCTION libp2p_pend_status
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, #LIBP2P_ACTION_MESSAGE_STATUS
    mov     x1, #LIBP2P_ACT_STATUS_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    mov     x21, x0
    mov     x0, #ST_PEND_OFF
    mov     x1, #PD_SIZE
    mov     x2, x19
    bl      libp2p_handle
    str     x0, [x21, #LIBP2P_ACT_HANDLE]
    str     x20, [x21, #LIBP2P_ACT_STATUS]
9:  LEAVE   0
END_FUNCTION libp2p_pend_status

/* ---------------------------------------------------------------- IWANT promises */

/* libp2p_promise_add(peer index, id, n): a promise of the peer to send the message within iwant_followup. Full: nothing. */
LOCAL_FUNCTION libp2p_promise_add
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    TABLE   x22, ST_PROMISE_OFF
    mov     x23, #LIBP2P_PROMISES
1:  cbz     x23, 9f
    ldr     x9, [x22, #PR_PEER]
    cmn     x9, #1
    b.eq    2f
    add     x22, x22, #PR_SIZE
    sub     x23, x23, #1
    b       1b
2:  str     x19, [x22, #PR_PEER]
    ldr     x9, [x28, #SC_NOW]
    CFG     x10, LIBP2P_CFG_IWANT_FOLLOWUP_MS
    add     x9, x9, x10
    str     x9, [x22, #PR_DEADLINE]
    str     x21, [x22, #PR_ID_LEN]
    add     x0, x22, #PR_ID
    mov     x1, x20
    mov     x2, x21
    bl      libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_promise_add

/* libp2p_promise_keep(id, n): the message came: every promise of it is kept. */
LOCAL_FUNCTION libp2p_promise_keep
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    TABLE   x22, ST_PROMISE_OFF
    mov     x23, #LIBP2P_PROMISES
1:  cbz     x23, 9f
    ldr     x9, [x22, #PR_PEER]
    cmn     x9, #1
    b.eq    2f
    add     x0, x22, #PR_ID
    ldr     x1, [x22, #PR_ID_LEN]
    mov     x2, x19
    mov     x3, x20
    bl      libp2p_compare
    cbz     x0, 2f
    mov     x9, #NONE
    str     x9, [x22, #PR_PEER]
2:  add     x22, x22, #PR_SIZE
    sub     x23, x23, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_promise_keep

/* libp2p_promise_drop_peer(peer index): the promises of a peer that left are forgotten. A leaf. */
LOCAL_FUNCTION libp2p_promise_drop_peer
    UNWIND_END_PROLOGUE
    ldr     x1, [x27, #ST_PROMISE_OFF]
    add     x1, x27, x1
    mov     x2, #LIBP2P_PROMISES
    mov     x3, #NONE
1:  cbz     x2, 9f
    ldr     x4, [x1, #PR_PEER]
    cmp     x4, x0
    b.ne    2f
    str     x3, [x1, #PR_PEER]
2:  add     x1, x1, #PR_SIZE
    sub     x2, x2, #1
    b       1b
9:  ret
END_FUNCTION libp2p_promise_drop_peer

/* ---------------------------------------------------------------- IDONTWANT */

/* libp2p_dw_ring(peer index) -> the first entry of the peer's IDONTWANT ring. A leaf. */
LOCAL_FUNCTION libp2p_dw_ring
    UNWIND_END_PROLOGUE
    CFG     x9, LIBP2P_CFG_DONTWANT_SLOTS
    mov     x10, #DW_SIZE
    mul     x9, x9, x10
    mul     x9, x9, x0
    ldr     x10, [x27, #ST_DW_OFF]
    add     x9, x9, x10
    add     x0, x27, x9
    ret
END_FUNCTION libp2p_dw_ring

/*
 * libp2p_dontwant(peer index, id, n) -> 1 when the peer sent IDONTWANT for
 * the message ID within the last dontwant_ttl heartbeats, else 0.
 * x19 id, x20 n, x21 entry, x22 entries left, x23 heartbeat number.
 */
LOCAL_FUNCTION libp2p_dontwant
    ENTER   0
    mov     x19, x1
    mov     x20, x2
    CFG     x22, LIBP2P_CFG_DONTWANT_SLOTS
    cbz     x22, 8f
    bl      libp2p_dw_ring
    mov     x21, x0
    ldr     x23, [x27, #ST_HEARTBEATS]
1:  ldr     x9, [x21, #DW_ID_LEN]
    cmp     x9, x20
    b.ne    2f
    ldr     x10, [x21, #DW_HB]
    sub     x10, x23, x10
    CFG     x11, LIBP2P_CFG_DONTWANT_TTL
    cmp     x10, x11
    b.hs    2f
    add     x0, x21, #DW_ID
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_equal
    cbnz    x0, 7f
2:  add     x21, x21, #DW_SIZE
    subs    x22, x22, #1
    b.ne    1b
8:  mov     x0, #0
    b       9f
7:  mov     x0, #1
9:  LEAVE   0
END_FUNCTION libp2p_dontwant

/* ---------------------------------------------------------------- RPCs out */

/*
 * libp2p_gs_alloc(n) -> x0 the place for n bytes of a send chunk, x1 the
 * chunk (a state offset, for libp2p_gs_push); x0 = 0 when the heap is full.
 */
LOCAL_FUNCTION libp2p_gs_alloc
    ENTER   0
    mov     x19, x0
    add     x0, x0, #(CH_DATA - HB_HEADER)
    bl      libp2p_heap_alloc
    cbz     x0, 9f
    mov     x1, x0
    sub     x9, x0, #HB_HEADER
    add     x9, x27, x9
    mov     x10, #NONE
    str     x10, [x9, #CH_NEXT]
    str     x19, [x9, #CH_LEN]
    str     xzr, [x9, #CH_DONE]
    add     x0, x9, #CH_DATA
9:  LEAVE   0
END_FUNCTION libp2p_gs_alloc

/*
 * libp2p_gs_push(peer, chunk) -> 1 when the chunk is queued on our gossipsub
 * stream to the peer; 0 when the peer is not ready or its queue is past
 * stream_queue (the chunk is then freed).
 */
LOCAL_FUNCTION libp2p_gs_push
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_gs_ready
    cbz     x0, 8f
    ldr     x0, [x19, #P_GS_OUT]
    bl      libp2p_stream_at
    mov     x21, x0
    ldr     x9, [x21, #S_Q_BYTES]
    CFG     x10, LIBP2P_CFG_STREAM_QUEUE
    cmp     x9, x10
    b.hi    8f
    sub     x22, x20, #HB_HEADER
    add     x22, x27, x22
    ldr     x9, [x21, #S_Q_TAIL]
    cmn     x9, #1
    b.ne    1f
    str     x20, [x21, #S_Q_HEAD]
    b       2f
1:  sub     x9, x9, #HB_HEADER
    add     x9, x27, x9
    str     x20, [x9, #CH_NEXT]
2:  str     x20, [x21, #S_Q_TAIL]
    ldr     x9, [x21, #S_Q_BYTES]
    ldr     x10, [x22, #CH_LEN]
    add     x9, x9, x10
    str     x9, [x21, #S_Q_BYTES]
    mov     x0, #1
    b       9f
8:  mov     x0, x20
    bl      libp2p_heap_free
    mov     x0, #0
9:  LEAVE   0
END_FUNCTION libp2p_gs_push

/* libp2p_pb_head(dst, field, n) -> dst after the key of a type 2 field and the length n. */
LOCAL_FUNCTION libp2p_pb_head
    ENTER   0
    mov     x19, x2
    lsl     x1, x1, #3
    orr     x1, x1, #2
    bl      libp2p_varint_put
    mov     x1, x19
    bl      libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_head

/*
 * libp2p_gs_rpc(peer, inner, inner size, field) -> the place for inner size
 * bytes, after the varint length of the RPC and the head of its field; the
 * chunk goes in x1 (libp2p_gs_push sends it). 0 when the heap is full.
 * The RPC is one field (subscriptions 1, publish 2, control 3 or partial
 * 10) of inner size bytes.
 */
LOCAL_FUNCTION libp2p_gs_rpc
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x0, x22
    mov     x1, x21
    bl      libp2p_pb_size                      /* the RPC */
    mov     x23, x0
    bl      libp2p_varint_len
    add     x0, x0, x23
    bl      libp2p_gs_alloc
    cbz     x0, 9f
    mov     x24, x1
    mov     x1, x23
    bl      libp2p_varint_put
    mov     x1, x22
    mov     x2, x21
    bl      libp2p_pb_head
    mov     x1, x24
9:  LEAVE   0
END_FUNCTION libp2p_gs_rpc

/*
 * libp2p_gs_send_sub(peer, topic, subscribe): an RPC with one SubOpts:
 * subscribe (1) and topicid (2); for a subscription, requestsPartial (3) and
 * supportsSendingPartial (4) when our partial flags of the topic have them.
 * x19 peer, x20 topic, x21 subscribe, x22 inner size, x23 chunk, x24 flags.
 */
LOCAL_FUNCTION libp2p_gs_send_sub
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x24, #0
    cbz     x21, 1f
    ldr     x9, [x20, #T_FLAGS]
    ubfx    x24, x9, #2, #2                 /* LIBP2P_PARTIAL_* */
1:  mov     x0, #2
    ldr     x1, [x20, #T_LEN]
    bl      libp2p_pb_size
    add     x22, x0, #2                     /* subscribe (field 1, a varint 0 or 1), topicid (field 2) */
    and     x9, x24, #1                     /* 2 bytes for each partial field */
    add     x22, x22, x9, lsl #1
    lsr     x9, x24, #1
    add     x22, x22, x9, lsl #1
    mov     x0, x19
    mov     x2, x22
    mov     x3, #1
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x23, x1
    mov     w9, #0x08
    strb    w9, [x0]
    strb    w21, [x0, #1]
    add     x0, x0, #2
    mov     x1, #2
    add     x2, x20, #T_NAME
    ldr     x3, [x20, #T_LEN]
    bl      libp2p_pb_bytes
    mov     w10, #1
    tbz     x24, #0, 2f
    mov     w9, #0x18                       /* requestsPartial: true */
    strb    w9, [x0], #1
    strb    w10, [x0], #1
2:  tbz     x24, #1, 3f
    mov     w9, #0x20                       /* supportsSendingPartial: true */
    strb    w9, [x0], #1
    strb    w10, [x0], #1
3:  mov     x0, x19
    mov     x1, x23
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_sub

/*
 * libp2p_gs_send_ext(peer): with partial_messages on, an RPC whose control
 * holds our Extensions control message (field 6): partialMessages (field
 * 10) set.
 * x19 peer, x20 chunk.
 */
LOCAL_FUNCTION libp2p_gs_send_ext
    ENTER   0
    mov     x19, x0
    CFG     x9, LIBP2P_CFG_PARTIAL_MESSAGES
    cbz     x9, 9f
    mov     x0, x19
    mov     x2, #4                          /* ControlMessage: extensions of 2 bytes */
    mov     x3, #3
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x20, x1
    mov     w9, #0x32                       /* field 6, type 2, length 2 */
    strb    w9, [x0]
    mov     w9, #2
    strb    w9, [x0, #1]
    mov     w9, #0x50                       /* field 10, type 0: true */
    strb    w9, [x0, #2]
    mov     w9, #1
    strb    w9, [x0, #3]
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_ext

/*
 * libp2p_gs_send_partial(peer, event, with message): an RPC with one
 * PartialMessagesExtension (field 10) from a PARTIAL_SEND event: topicID
 * (1), groupID (2), partialMessage (3) when with message is 1 and it has
 * bytes, partsMetadata (4) when it has bytes.
 * x19 peer, x20 event, x21 with message, x22 inner size, x23 chunk,
 * x24 topic, x25 group, x26 metadata.
 */
LOCAL_FUNCTION libp2p_gs_send_partial
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x20, #LIBP2P_EV_PSEND_MSG_LEN]
    cmp     x9, #0
    csel    x21, xzr, x21, eq
    add     x24, x20, #LIBP2P_EV_PSEND_BYTES /* each part at a multiple of 8 */
    ldr     x9, [x20, #LIBP2P_EV_PSEND_TOPIC_LEN]
    add     x9, x9, #7
    and     x9, x9, #~7
    add     x25, x24, x9
    ldr     x9, [x20, #LIBP2P_EV_PSEND_GROUP_LEN]
    add     x9, x9, #7
    and     x9, x9, #~7
    add     x26, x25, x9
    mov     x0, #1                          /* the inner size */
    ldr     x1, [x20, #LIBP2P_EV_PSEND_TOPIC_LEN]
    bl      libp2p_pb_size
    mov     x22, x0
    mov     x0, #2
    ldr     x1, [x20, #LIBP2P_EV_PSEND_GROUP_LEN]
    bl      libp2p_pb_size
    add     x22, x22, x0
    ldr     x1, [x20, #LIBP2P_EV_PSEND_META_LEN]
    cbz     x1, 1f
    mov     x0, #4
    bl      libp2p_pb_size
    add     x22, x22, x0
1:  cbz     x21, 2f
    mov     x0, #3
    ldr     x1, [x20, #LIBP2P_EV_PSEND_MSG_LEN]
    bl      libp2p_pb_size
    add     x22, x22, x0
2:  mov     x0, x19
    mov     x2, x22
    mov     x3, #10
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x23, x1
    mov     x1, #1
    mov     x2, x24
    ldr     x3, [x20, #LIBP2P_EV_PSEND_TOPIC_LEN]
    bl      libp2p_pb_bytes
    mov     x1, #2
    mov     x2, x25
    ldr     x3, [x20, #LIBP2P_EV_PSEND_GROUP_LEN]
    bl      libp2p_pb_bytes
    cbz     x21, 3f
    ldr     x9, [x20, #LIBP2P_EV_PSEND_META_LEN]
    add     x9, x9, #7
    and     x9, x9, #~7
    add     x2, x26, x9                     /* the message */
    mov     x1, #3
    ldr     x3, [x20, #LIBP2P_EV_PSEND_MSG_LEN]
    bl      libp2p_pb_bytes
3:  ldr     x3, [x20, #LIBP2P_EV_PSEND_META_LEN]
    cbz     x3, 4f
    mov     x1, #4
    mov     x2, x26
    bl      libp2p_pb_bytes
4:  mov     x0, x19
    mov     x1, x23
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_partial

/* libp2p_gs_send_msg(peer, topic, data, n): an RPC that publishes one message: data (field 2) and topic (field 4). */
LOCAL_FUNCTION libp2p_gs_send_msg
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x0, #2
    mov     x1, x22
    bl      libp2p_pb_size
    mov     x23, x0
    mov     x0, #4
    ldr     x1, [x20, #T_LEN]
    bl      libp2p_pb_size
    add     x23, x23, x0
    mov     x0, x19
    mov     x1, x19
    mov     x2, x23
    mov     x3, #2
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x24, x1
    mov     x1, #2
    mov     x2, x21
    mov     x3, x22
    bl      libp2p_pb_bytes
    mov     x1, #4
    add     x2, x20, #T_NAME
    ldr     x3, [x20, #T_LEN]
    bl      libp2p_pb_bytes
    mov     x0, x19
    mov     x1, x24
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_msg

/* libp2p_gs_send_graft(peer, topic): control with one GRAFT. */
LOCAL_FUNCTION libp2p_gs_send_graft
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x0, #1
    ldr     x1, [x20, #T_LEN]
    bl      libp2p_pb_size
    mov     x21, x0                         /* ControlGraft */
    mov     x0, #3
    mov     x1, x21
    bl      libp2p_pb_size
    mov     x2, x0                          /* ControlMessage */
    mov     x0, x19
    mov     x3, #3
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x22, x1
    mov     x1, #3
    mov     x2, x21
    bl      libp2p_pb_head
    mov     x1, #1
    add     x2, x20, #T_NAME
    ldr     x3, [x20, #T_LEN]
    bl      libp2p_pb_bytes
    mov     x0, x19
    mov     x1, x22
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_graft

/* libp2p_gs_send_prune(peer, topic, backoff seconds): control with one PRUNE: topicID (1), backoff (3). */
LOCAL_FUNCTION libp2p_gs_send_prune
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x23, x2
    mov     x0, #1
    ldr     x1, [x20, #T_LEN]
    bl      libp2p_pb_size
    mov     x21, x0
    mov     x0, x23
    bl      libp2p_varint_len
    add     x21, x21, x0
    add     x21, x21, #1                    /* ControlPrune */
    mov     x0, #4
    mov     x1, x21
    bl      libp2p_pb_size
    mov     x2, x0
    mov     x0, x19
    mov     x3, #3
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x22, x1
    mov     x1, #4
    mov     x2, x21
    bl      libp2p_pb_head
    mov     x1, #1
    add     x2, x20, #T_NAME
    ldr     x3, [x20, #T_LEN]
    bl      libp2p_pb_bytes
    mov     x1, #3
    mov     x2, x23
    bl      libp2p_pb_varint
    mov     x0, x19
    mov     x1, x22
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_prune

/*
 * libp2p_gs_send_ids(peer, topic, list, count, kind): control with one IHAVE
 * (kind 1: topicID, then messageIDs as field 2), one IWANT (kind 2) or one
 * IDONTWANT (kind 5): messageIDs as field 1, no topic. The kind is the
 * field of the ControlMessage. list holds count pairs: the address of an
 * ID, then its length.
 * x19 peer, x20 topic, x21 list, x22 count, x23 kind, x24 inner size.
 */
LOCAL_FUNCTION libp2p_gs_send_ids
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, #0
    cmp     x23, #1
    b.ne    1f
    mov     x0, #1
    ldr     x1, [x20, #T_LEN]
    bl      libp2p_pb_size
    mov     x24, x0
1:  mov     x25, #0
2:  cmp     x25, x22
    b.hs    3f
    add     x9, x21, x25, lsl #4
    ldr     x1, [x9, #8]
    mov     x0, #1
    cmp     x23, #1
    mov     x10, #2
    csel    x0, x10, x0, eq
    bl      libp2p_pb_size
    add     x24, x24, x0
    add     x25, x25, #1
    b       2b
3:  mov     x0, x23
    mov     x1, x24
    bl      libp2p_pb_size
    mov     x2, x0
    mov     x0, x19
    mov     x3, #3
    bl      libp2p_gs_rpc
    cbz     x0, 9f
    mov     x26, x1
    mov     x1, x23
    mov     x2, x24
    bl      libp2p_pb_head
    cmp     x23, #1
    b.ne    4f
    mov     x1, #1
    add     x2, x20, #T_NAME
    ldr     x3, [x20, #T_LEN]
    bl      libp2p_pb_bytes
4:  mov     x25, #0
5:  cmp     x25, x22
    b.hs    6f
    add     x9, x21, x25, lsl #4
    ldr     x2, [x9]
    ldr     x3, [x9, #8]
    mov     x1, #1
    cmp     x23, #1
    mov     x10, #2
    csel    x1, x10, x1, eq
    bl      libp2p_pb_bytes
    add     x25, x25, #1
    b       5b
6:  mov     x0, x19
    mov     x1, x26
    bl      libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_ids

/*
 * libp2p_gs_idontwant(pending): a new message of idontwant_threshold bytes
 * or more: IDONTWANT with its ID, at once, to each mesh peer of its topic
 * that speaks /meshsub/1.2.0, except the peer that sent it and the peers
 * that send us partial messages of the topic (libp2p_sends_partial).
 * x19 pending, x20 list, x21 count, x22 i.
 */
LOCAL_FUNCTION libp2p_gs_idontwant
    ENTER   0
    mov     x19, x0
    CFG     x9, LIBP2P_CFG_IDONTWANT_THRESHOLD
    cbz     x9, 9f
    ldr     x10, [x19, #PD_DATA_LEN]
    cmp     x10, x9
    b.lo    9f
    SCR     x9, SC_IDS                      /* the one ID */
    add     x10, x19, #PD_ID
    str     x10, [x9]
    ldr     x10, [x19, #PD_ID_LEN]
    str     x10, [x9, #8]
    mov     x9, #0xFFF0000000000000         /* the mesh, at any score: -infinity */
    fmov    d0, x9
    ldr     x0, [x19, #PD_TOPIC]
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    mov     x21, x0
    SCR     x20, SC_LIST
    mov     x22, #0
1:  cmp     x22, x21
    b.hs    9f
    ldr     w0, [x20, x22, lsl #2]
    ldr     x9, [x19, #PD_PEER]
    cmp     x0, x9
    b.eq    2f
    ldr     x1, [x19, #PD_TOPIC]
    bl      libp2p_sends_partial
    cbnz    x0, 2f
    ldr     w0, [x20, x22, lsl #2]
    bl      libp2p_peer_at
    ldr     x9, [x0, #P_FLAGS]
    tst     x9, #PF_IDONTWANT
    b.eq    2f
    mov     x1, #0
    SCR     x2, SC_IDS
    mov     x3, #1
    mov     x4, #5
    bl      libp2p_gs_send_ids
2:  add     x22, x22, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_idontwant

/* libp2p_gs_announce(topic, subscribe): our subscription change, to every gossipsub peer. */
LOCAL_FUNCTION libp2p_gs_announce
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    TABLE   x21, ST_PEER_OFF
    ldr     x22, [x27, #ST_PEER_COUNT]
1:  cbz     x22, 9f
    mov     x0, x21
    bl      libp2p_gs_ready
    cbz     x0, 2f
    mov     x0, x21
    mov     x1, x19
    mov     x2, x20
    bl      libp2p_gs_send_sub
2:  add     x21, x21, #P_SIZE
    sub     x22, x22, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_announce

.include "gossip_in.s"
.include "heartbeat.s"
.include "score.s"

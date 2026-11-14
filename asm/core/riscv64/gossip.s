/*
 * gossipsub v1.1 of the RISC-V core (/meshsub/1.1.0, StrictNoSign):
 * topics, the seen cache, the message cache, messages waiting for the
 * application, IWANT promises, RPCs in and out, and the events of the
 * application. The heartbeat and scores are in heartbeat.s and score.s.
 * Included by libp2p.s.
 */

/* ---------------------------------------------------------------- Tables */

/* libp2p_peer_at(index) -> the peer slot. A leaf. */
LOCAL_FUNCTION libp2p_peer_at
    UNWIND_END_PROLOGUE
    ld      a1, ST_PEER_OFF(s9)
    add     a1, s9, a1
    li      a2, P_SIZE
    mul     a0, a0, a2
    add     a0, a0, a1
    ret
END_FUNCTION libp2p_peer_at

/* libp2p_peer_idx(peer) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_peer_idx
    UNWIND_END_PROLOGUE
    ld      a1, ST_PEER_OFF(s9)
    add     a1, s9, a1
    sub     a0, a0, a1
    li      a1, P_SIZE
    divu    a0, a0, a1
    ret
END_FUNCTION libp2p_peer_idx

/* libp2p_topic_at(index) -> the topic slot. A leaf. */
LOCAL_FUNCTION libp2p_topic_at
    UNWIND_END_PROLOGUE
    ld      a1, ST_TOPIC_OFF(s9)
    add     a1, s9, a1
    li      a2, T_SIZE
    mul     a0, a0, a2
    add     a0, a0, a1
    ret
END_FUNCTION libp2p_topic_at

/* libp2p_topic_idx(topic) -> its index. A leaf. */
LOCAL_FUNCTION libp2p_topic_idx
    UNWIND_END_PROLOGUE
    ld      a1, ST_TOPIC_OFF(s9)
    add     a1, s9, a1
    sub     a0, a0, a1
    li      a1, T_SIZE
    divu    a0, a0, a1
    ret
END_FUNCTION libp2p_topic_idx

/* libp2p_pt(peer index, topic index) -> the peer x topic entry. A leaf. */
LOCAL_FUNCTION libp2p_pt
    UNWIND_END_PROLOGUE
    ld      a2, ST_TOPIC_COUNT(s9)
    mul     a0, a0, a2
    add     a0, a0, a1
    ld      a2, ST_PT_OFF(s9)
    add     a2, s9, a2
    li      a3, PT_SIZE
    mul     a0, a0, a3
    add     a0, a0, a2
    ret
END_FUNCTION libp2p_pt

/*
 * libp2p_topic_find(name, n) -> the topic slot with the name, or 0.
 * s1 name, s2 n, s3 hash, s4 slot, s5 slots left.
 */
LOCAL_FUNCTION libp2p_topic_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_hash
    mv      s3, a0
    TABLE   s4, ST_TOPIC_OFF
    ld      s5, ST_TOPIC_COUNT(s9)
1:  beqz    s5, 8f
    ld      t0, T_USED(s4)
    beqz    t0, 2f
    ld      t0, T_HASH(s4)
    bne     t0, s3, 2f
    addi    a0, s4, T_NAME
    ld      a1, T_LEN(s4)
    mv      a2, s1
    mv      a3, s2
    call    libp2p_compare
    beqz    a0, 2f
    mv      a0, s4
    j       9f
2:  addi    s4, s4, T_SIZE
    addi    s5, s5, -1
    j       1b
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_topic_find

/* libp2p_topic_get(name, n) -> the topic slot with the name, a new one when there is none; 0 when the table is full. */
LOCAL_FUNCTION libp2p_topic_get
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_topic_find
    bnez    a0, 9f
    TABLE   s4, ST_TOPIC_OFF
    ld      s5, ST_TOPIC_COUNT(s9)
1:  beqz    s5, 8f
    ld      t0, T_USED(s4)
    beqz    t0, 2f
    addi    s4, s4, T_SIZE
    addi    s5, s5, -1
    j       1b
2:  mv      a0, s4
    li      a1, T_SIZE
    call    libp2p_zero
    li      t0, 1
    sd      t0, T_USED(s4)
    sd      s2, T_LEN(s4)
    addi    a0, s4, T_NAME
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    mv      a0, s1
    mv      a1, s2
    call    libp2p_hash
    sd      a0, T_HASH(s4)
    mv      a0, s4
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_topic_get

/* libp2p_topic_tidy(topic): a topic nobody uses and without score parameters becomes free. A leaf. */
LOCAL_FUNCTION libp2p_topic_tidy
    UNWIND_END_PROLOGUE
    ld      a1, T_FLAGS(a0)
    ld      a2, T_PEERS(a0)
    or      a1, a1, a2
    ld      a2, T_MESH(a0)
    or      a1, a1, a2
    ld      a2, T_FANOUT(a0)
    or      a1, a1, a2
    bnez    a1, 9f
    sd      zero, T_USED(a0)
9:  ret
END_FUNCTION libp2p_topic_tidy

/* libp2p_gs_ready(peer) -> 1 when the peer is connected and our gossipsub stream to it is open. A leaf. */
LOCAL_FUNCTION libp2p_gs_ready
    UNWIND_END_PROLOGUE
    lwu     a1, P_STATE(a0)
    li      a2, PS_CONNECTED
    bne     a1, a2, 8f
    ld      a1, P_FLAGS(a0)
    andi    a1, a1, PF_GOSSIP
    beqz    a1, 8f
    ld      a1, P_GS_OUT(a0)
    li      a2, NONE
    beq     a1, a2, 8f
    li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_gs_ready

/* ---------------------------------------------------------------- Hash indexes of message IDs */

/*
 * libp2p_idx_find(index, slots, entries, stride, id, n) -> the entry index of
 * the message ID, or NONE. The index is open addressing with linear
 * probing; a slot holds an entry index + 1, or 0. Entries hold the ID
 * length at 0 and the ID at 8.
 * s1 index, s2 slots, s3 entries, s4 stride, s5 id, s6 n, s7 slot, s8 entry.
 */
LOCAL_FUNCTION libp2p_idx_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      a0, s5
    mv      a1, s6
    call    libp2p_hash
    remu    s7, a0, s2
1:  slli    t0, s7, 2
    add     t0, s1, t0
    lwu     s8, 0(t0)
    beqz    s8, 8f
    addi    s8, s8, -1
    mul     t0, s8, s4
    add     t0, t0, s3
    ld      a1, 0(t0)
    addi    a0, t0, 8
    mv      a2, s5
    mv      a3, s6
    call    libp2p_compare
    bnez    a0, 7f
    addi    s7, s7, 1
    bltu    s7, s2, 1b
    li      s7, 0
    j       1b
7:  mv      a0, s8
    j       9f
8:  li      a0, NONE
9:  LEAVE   0
END_FUNCTION libp2p_idx_find

/* libp2p_idx_add(index, slots, entry, hash): puts entry + 1 in the first empty slot from hash mod slots. A leaf. */
LOCAL_FUNCTION libp2p_idx_add
    UNWIND_END_PROLOGUE
    remu    a4, a3, a1
    addiw   a2, a2, 1
1:  slli    a6, a4, 2
    add     a6, a0, a6
    lwu     a5, 0(a6)
    beqz    a5, 2f
    addi    a4, a4, 1
    bltu    a4, a1, 1b
    li      a4, 0
    j       1b
2:  sw      a2, 0(a6)
    ret
END_FUNCTION libp2p_idx_add

/*
 * libp2p_idx_del(index, slots, entries, stride, entry): takes entry out of the
 * index and moves later entries of the probe run back, so every lookup
 * still finds its entry.
 * s1 index, s2 slots, s3 entries, s4 stride, s5 hole, s6 position,
 * s7 the slot value at the position, s8 entry + 1.
 */
LOCAL_FUNCTION libp2p_idx_del
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    addi    s8, a4, 1                       # find the slot that holds it
    slli    s8, s8, 32
    srli    s8, s8, 32
    mul     t0, a4, s4
    add     t0, t0, s3
    addi    a0, t0, 8
    ld      a1, 0(t0)
    call    libp2p_hash
    remu    s5, a0, s2
1:  slli    t0, s5, 2
    add     t0, s1, t0
    lwu     t1, 0(t0)
    beqz    t1, 9f
    beq     t1, s8, 2f
    addi    s5, s5, 1
    bltu    s5, s2, 1b
    li      s5, 0
    j       1b
2:  mv      s6, s5                          # the hole at s5
3:  addi    s6, s6, 1
    bltu    s6, s2, 31f
    li      s6, 0
31: slli    t0, s6, 2
    add     t0, s1, t0
    lwu     s7, 0(t0)
    beqz    s7, 8f
    addi    t0, s7, -1                      # the home slot of the entry at s6
    mul     t0, t0, s4
    add     t0, t0, s3
    addi    a0, t0, 8
    ld      a1, 0(t0)
    call    libp2p_hash
    remu    t0, a0, s2
    # move it into the hole unless its home lies cyclically in (hole, position]
    bltu    s6, s5, 4f
    bgeu    s5, t0, 5f
    bltu    s6, t0, 5f
    j       3b
4:  bltu    s5, t0, 3b
    bgeu    s6, t0, 3b
5:  slli    t1, s5, 2
    add     t1, s1, t1
    sw      s7, 0(t1)
    mv      s5, s6
    j       3b
8:  slli    t1, s5, 2
    add     t1, s1, t1
    sw      zero, 0(t1)
9:  LEAVE   0
END_FUNCTION libp2p_idx_del

/* ---------------------------------------------------------------- Seen cache */

/* libp2p_seen_args(): a0 index, a1 slots, a2 entries, a3 stride of the seen cache. A leaf. */
LOCAL_FUNCTION libp2p_seen_args
    UNWIND_END_PROLOGUE
    ld      a0, ST_SEEN_INDEX_OFF(s9)
    add     a0, s9, a0
    ld      a1, ST_SEEN_COUNT(s9)
    slli    a1, a1, 1
    ld      a2, ST_SEEN_OFF(s9)
    add     a2, s9, a2
    li      a3, SN_SIZE
    ret
END_FUNCTION libp2p_seen_args

/* libp2p_seen_find(id, n) -> the seen entry of the message ID, or 0. */
LOCAL_FUNCTION libp2p_seen_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_seen_args
    mv      a4, s1
    mv      a5, s2
    mv      s3, a2
    call    libp2p_idx_find
    li      t0, NONE
    beq     a0, t0, 8f
    li      t0, SN_SIZE
    mul     a0, a0, t0
    add     a0, a0, s3
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_seen_find

/* libp2p_seen_drop_tail(): the oldest seen entry leaves the ring and the index. */
LOCAL_FUNCTION libp2p_seen_drop_tail
    ENTER   0
    ld      s1, ST_SEEN_USED(s9)
    beqz    s1, 9f
    ld      s2, ST_SEEN_HEAD(s9)
    ld      s3, ST_SEEN_COUNT(s9)
    add     s2, s2, s3                      # tail = (head - used) mod count
    sub     s2, s2, s1
    remu    s2, s2, s3
    call    libp2p_seen_args
    mv      a4, s2
    call    libp2p_idx_del
    addi    s1, s1, -1
    sd      s1, ST_SEEN_USED(s9)
9:  LEAVE   0
END_FUNCTION libp2p_seen_drop_tail

/* libp2p_seen_tail() -> the oldest seen entry, or 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_tail
    UNWIND_END_PROLOGUE
    ld      a1, ST_SEEN_USED(s9)
    beqz    a1, 8f
    ld      a2, ST_SEEN_HEAD(s9)
    ld      a3, ST_SEEN_COUNT(s9)
    add     a2, a2, a3
    sub     a2, a2, a1
    remu    a2, a2, a3
    ld      a4, ST_SEEN_OFF(s9)
    add     a4, s9, a4
    li      a5, SN_SIZE
    mul     a0, a2, a5
    add     a0, a0, a4
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_seen_tail

/*
 * libp2p_seen_add(id, n, topic, status) -> the new seen entry, first seen now,
 * with no deliverers. When the ring is full the oldest entry goes first.
 */
LOCAL_FUNCTION libp2p_seen_add
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, ST_SEEN_USED(s9)
    ld      t1, ST_SEEN_COUNT(s9)
    bltu    t0, t1, 1f
    call    libp2p_seen_drop_tail
1:  ld      s5, ST_SEEN_HEAD(s9)
    TABLE   s6, ST_SEEN_OFF
    li      t0, SN_SIZE
    mul     t0, s5, t0
    add     s6, s6, t0
    mv      a0, s6
    li      a1, SN_SIZE
    call    libp2p_zero
    sd      s2, SN_ID_LEN(s6)
    addi    a0, s6, SN_ID
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    ld      t0, SC_NOW(s10)
    sd      t0, SN_TIME(s6)
    sd      s4, SN_STATUS(s6)
    sw      s3, SN_TOPIC(s6)
    mv      a0, s1
    mv      a1, s2
    call    libp2p_hash
    mv      a3, a0
    call    libp2p_seen_args_keep
    mv      a2, s5
    call    libp2p_idx_add
    ld      t0, ST_SEEN_HEAD(s9)
    addi    t0, t0, 1
    ld      t1, ST_SEEN_COUNT(s9)
    bltu    t0, t1, 2f
    li      t0, 0
2:  sd      t0, ST_SEEN_HEAD(s9)
    ld      t0, ST_SEEN_USED(s9)
    addi    t0, t0, 1
    sd      t0, ST_SEEN_USED(s9)
    mv      a0, s6
    LEAVE   0
END_FUNCTION libp2p_seen_add

/* libp2p_seen_args_keep(): a0 the seen index and a1 its slots, leaving a2 and a3 as they are. A leaf. */
LOCAL_FUNCTION libp2p_seen_args_keep
    UNWIND_END_PROLOGUE
    ld      a0, ST_SEEN_INDEX_OFF(s9)
    add     a0, s9, a0
    ld      a1, ST_SEEN_COUNT(s9)
    slli    a1, a1, 1
    ret
END_FUNCTION libp2p_seen_args_keep

/* libp2p_seen_expire(): seen entries older than seen_ttl leave. */
LOCAL_FUNCTION libp2p_seen_expire
    ENTER   0
    ld      s1, SC_NOW(s10)
    CFG     s2, LIBP2P_CFG_SEEN_TTL_MS
1:  call    libp2p_seen_tail
    beqz    a0, 9f
    ld      t0, SN_TIME(a0)
    add     t0, t0, s2
    bltu    s1, t0, 9f
    call    libp2p_seen_drop_tail
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_seen_expire

/* ---------------------------------------------------------------- Message cache */

/* libp2p_mc_args(): a0 index, a1 slots, a2 entries, a3 stride of the message cache. A leaf. */
LOCAL_FUNCTION libp2p_mc_args
    UNWIND_END_PROLOGUE
    ld      a0, ST_MC_INDEX_OFF(s9)
    add     a0, s9, a0
    ld      a1, ST_MC_COUNT(s9)
    slli    a1, a1, 1
    ld      a2, ST_MC_OFF(s9)
    add     a2, s9, a2
    ld      a3, ST_MC_STRIDE(s9)
    ret
END_FUNCTION libp2p_mc_args

/* libp2p_mc_find(id, n) -> the message cache entry of the message ID, or 0. */
LOCAL_FUNCTION libp2p_mc_find
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_mc_args
    mv      s3, a2
    mv      s4, a3
    mv      a4, s1
    mv      a5, s2
    call    libp2p_idx_find
    li      t0, NONE
    beq     a0, t0, 8f
    mul     a0, a0, s4
    add     a0, a0, s3
    j       9f
8:  li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_mc_find

/* libp2p_mc_tail() -> a0 the oldest message cache entry or 0, a1 its index. A leaf. */
LOCAL_FUNCTION libp2p_mc_tail
    UNWIND_END_PROLOGUE
    ld      a1, ST_MC_USED(s9)
    beqz    a1, 8f
    ld      a2, ST_MC_HEAD(s9)
    ld      a3, ST_MC_COUNT(s9)
    add     a2, a2, a3
    sub     a2, a2, a1
    remu    a1, a2, a3
    ld      a4, ST_MC_OFF(s9)
    add     a4, s9, a4
    ld      a5, ST_MC_STRIDE(s9)
    mul     a0, a1, a5
    add     a0, a0, a4
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_mc_tail

/* libp2p_mc_drop_tail(): the oldest message cache entry leaves, with its data. */
LOCAL_FUNCTION libp2p_mc_drop_tail
    ENTER   0
    call    libp2p_mc_tail
    beqz    a0, 9f
    mv      s1, a0
    mv      s2, a1
    ld      a0, MC_DATA(s1)
    call    libp2p_heap_free
    sd      zero, MC_USED(s1)
    call    libp2p_mc_args
    mv      a4, s2
    call    libp2p_idx_del
    ld      t0, ST_MC_USED(s9)
    addi    t0, t0, -1
    sd      t0, ST_MC_USED(s9)
9:  LEAVE   0
END_FUNCTION libp2p_mc_drop_tail

/*
 * libp2p_mc_put(id, n, topic, data, length): a message in the current window of
 * the cache, which now owns the heap block of its data. When the cache is
 * full the oldest entry goes first.
 */
LOCAL_FUNCTION libp2p_mc_put
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      t0, ST_MC_USED(s9)
    ld      t1, ST_MC_COUNT(s9)
    bltu    t0, t1, 1f
    call    libp2p_mc_drop_tail
1:  ld      s6, ST_MC_HEAD(s9)
    call    libp2p_mc_args
    mul     s7, s6, a3
    add     s7, s7, a2
    mv      a0, s7
    mv      a1, a3
    call    libp2p_zero
    sd      s2, MC_ID_LEN(s7)
    addi    a0, s7, MC_ID
    mv      a1, s1
    mv      a2, s2
    call    libp2p_copy
    sd      s3, MC_TOPIC(s7)
    sd      s4, MC_DATA(s7)
    sd      s5, MC_DATA_LEN(s7)
    ld      t0, ST_HEARTBEATS(s9)
    sd      t0, MC_WINDOW(s7)
    li      t0, 1
    sd      t0, MC_USED(s7)
    mv      a0, s1
    mv      a1, s2
    call    libp2p_hash
    mv      a3, a0
    ld      a0, ST_MC_INDEX_OFF(s9)
    add     a0, s9, a0
    ld      a1, ST_MC_COUNT(s9)
    slli    a1, a1, 1
    mv      a2, s6
    call    libp2p_idx_add
    ld      t0, ST_MC_HEAD(s9)
    addi    t0, t0, 1
    ld      t1, ST_MC_COUNT(s9)
    bltu    t0, t1, 2f
    li      t0, 0
2:  sd      t0, ST_MC_HEAD(s9)
    ld      t0, ST_MC_USED(s9)
    addi    t0, t0, 1
    sd      t0, ST_MC_USED(s9)
    LEAVE   0
END_FUNCTION libp2p_mc_put

/* libp2p_mc_shift(): entries of windows mcache_len or more heartbeats old leave. */
LOCAL_FUNCTION libp2p_mc_shift
    ENTER   0
    ld      s1, ST_HEARTBEATS(s9)
    CFG     s2, LIBP2P_CFG_MCACHE_LEN
1:  call    libp2p_mc_tail
    beqz    a0, 9f
    ld      t0, MC_WINDOW(a0)
    add     t0, t0, s2
    bltu    s1, t0, 9f
    call    libp2p_mc_drop_tail
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_mc_shift

/*
 * libp2p_mc_sent(entry, peer index) -> 1 when the message may go to the peer
 * for an IWANT once more (fewer than retransmission sends), counting it;
 * else 0. Two bits for each peer. A leaf.
 */
LOCAL_FUNCTION libp2p_mc_sent
    UNWIND_END_PROLOGUE
    srli    a2, a1, 5                       # word
    andi    a3, a1, 31
    slli    a3, a3, 1                       # bit
    addi    a4, a0, MC_TX
    slli    a2, a2, 3
    add     a4, a4, a2
    ld      a5, 0(a4)
    srl     a6, a5, a3
    andi    a6, a6, 3
    CFG     a7, LIBP2P_CFG_RETRANSMISSION
    li      t0, 3
    bltu    a7, t0, 1f
    mv      a7, t0
1:  bgeu    a6, a7, 8f
    li      t0, 1
    sll     t0, t0, a3
    add     a5, a5, t0
    sd      a5, 0(a4)
    li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_mc_sent

/* ---------------------------------------------------------------- Messages waiting for the application */

/* libp2p_pend(handle) -> the pending message of a handle, or 0. */
LOCAL_FUNCTION libp2p_pend
    ENTER   0
    mv      a3, a0
    li      a0, ST_PEND_OFF
    li      a1, ST_PEND_COUNT
    li      a2, PD_SIZE
    call    libp2p_slot
    LEAVE   0
END_FUNCTION libp2p_pend

/* libp2p_pend_free(pending): frees its data block (when it still owns one) and the slot. */
LOCAL_FUNCTION libp2p_pend_free
    ENTER   0
    mv      s1, a0
    ld      a0, PD_DATA(s1)
    call    libp2p_heap_free
    sd      zero, PD_DATA(s1)
    sw      zero, PD_STATE(s1)
    LEAVE   0
END_FUNCTION libp2p_pend_free

/* libp2p_pend_status(pending, status): MESSAGE_STATUS for the application. */
LOCAL_FUNCTION libp2p_pend_status
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    li      a0, LIBP2P_ACTION_MESSAGE_STATUS
    li      a1, LIBP2P_ACT_STATUS_SIZE
    call    libp2p_action
    beqz    a0, 9f
    mv      s3, a0
    li      a0, ST_PEND_OFF
    li      a1, PD_SIZE
    mv      a2, s1
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_HANDLE(s3)
    sd      s2, LIBP2P_ACT_STATUS(s3)
9:  LEAVE   0
END_FUNCTION libp2p_pend_status

/* ---------------------------------------------------------------- IWANT promises */

/* libp2p_promise_add(peer index, id, n): a promise of the peer to send the message within iwant_followup. Full: nothing. */
LOCAL_FUNCTION libp2p_promise_add
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    TABLE   s4, ST_PROMISE_OFF
    li      s5, LIBP2P_PROMISES
1:  beqz    s5, 9f
    ld      t0, PR_PEER(s4)
    li      t1, NONE
    beq     t0, t1, 2f
    addi    s4, s4, PR_SIZE
    addi    s5, s5, -1
    j       1b
2:  sd      s1, PR_PEER(s4)
    ld      t0, SC_NOW(s10)
    CFG     t1, LIBP2P_CFG_IWANT_FOLLOWUP_MS
    add     t0, t0, t1
    sd      t0, PR_DEADLINE(s4)
    sd      s3, PR_ID_LEN(s4)
    addi    a0, s4, PR_ID
    mv      a1, s2
    mv      a2, s3
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_promise_add

/* libp2p_promise_keep(id, n): the message came: every promise of it is kept. */
LOCAL_FUNCTION libp2p_promise_keep
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    TABLE   s4, ST_PROMISE_OFF
    li      s5, LIBP2P_PROMISES
1:  beqz    s5, 9f
    ld      t0, PR_PEER(s4)
    li      t1, NONE
    beq     t0, t1, 2f
    addi    a0, s4, PR_ID
    ld      a1, PR_ID_LEN(s4)
    mv      a2, s1
    mv      a3, s2
    call    libp2p_compare
    beqz    a0, 2f
    li      t0, NONE
    sd      t0, PR_PEER(s4)
2:  addi    s4, s4, PR_SIZE
    addi    s5, s5, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_promise_keep

/* libp2p_promise_drop_peer(peer index): the promises of a peer that left are forgotten. A leaf. */
LOCAL_FUNCTION libp2p_promise_drop_peer
    UNWIND_END_PROLOGUE
    ld      a1, ST_PROMISE_OFF(s9)
    add     a1, s9, a1
    li      a2, LIBP2P_PROMISES
    li      a3, NONE
1:  beqz    a2, 9f
    ld      a4, PR_PEER(a1)
    bne     a4, a0, 2f
    sd      a3, PR_PEER(a1)
2:  addi    a1, a1, PR_SIZE
    addi    a2, a2, -1
    j       1b
9:  ret
END_FUNCTION libp2p_promise_drop_peer

/* ---------------------------------------------------------------- IDONTWANT */

/* libp2p_dw_ring(peer index) -> the first entry of the peer's IDONTWANT ring. A leaf. */
LOCAL_FUNCTION libp2p_dw_ring
    UNWIND_END_PROLOGUE
    CFG     t0, LIBP2P_CFG_DONTWANT_SLOTS
    li      t1, DW_SIZE
    mul     t0, t0, t1
    mul     t0, t0, a0
    ld      t1, ST_DW_OFF(s9)
    add     t0, t0, t1
    add     a0, s9, t0
    ret
END_FUNCTION libp2p_dw_ring

/*
 * libp2p_dontwant(peer index, id, n) -> 1 when the peer sent IDONTWANT for
 * the message ID within the last dontwant_ttl heartbeats, else 0.
 * s1 id, s2 n, s3 entry, s4 entries left, s5 heartbeat number.
 */
LOCAL_FUNCTION libp2p_dontwant
    ENTER   0
    mv      s1, a1
    mv      s2, a2
    CFG     s4, LIBP2P_CFG_DONTWANT_SLOTS
    beqz    s4, 8f
    call    libp2p_dw_ring
    mv      s3, a0
    ld      s5, ST_HEARTBEATS(s9)
1:  ld      t0, DW_ID_LEN(s3)
    bne     t0, s2, 2f
    ld      t1, DW_HB(s3)
    sub     t1, s5, t1
    CFG     t2, LIBP2P_CFG_DONTWANT_TTL
    bgeu    t1, t2, 2f
    addi    a0, s3, DW_ID
    mv      a1, s1
    mv      a2, s2
    call    libp2p_equal
    bnez    a0, 7f
2:  addi    s3, s3, DW_SIZE
    addi    s4, s4, -1
    bnez    s4, 1b
8:  li      a0, 0
    j       9f
7:  li      a0, 1
9:  LEAVE   0
END_FUNCTION libp2p_dontwant

/* ---------------------------------------------------------------- RPCs out */

/*
 * libp2p_gs_alloc(n) -> a0 the place for n bytes of a send chunk, a1 the
 * chunk (a state offset, for libp2p_gs_push); a0 = 0 when the heap is full.
 */
LOCAL_FUNCTION libp2p_gs_alloc
    ENTER   0
    mv      s1, a0
    addi    a0, a0, (CH_DATA - HB_HEADER)
    call    libp2p_heap_alloc
    beqz    a0, 9f
    mv      a1, a0
    addi    t0, a0, -HB_HEADER
    add     t0, s9, t0
    li      t1, NONE
    sd      t1, CH_NEXT(t0)
    sd      s1, CH_LEN(t0)
    sd      zero, CH_DONE(t0)
    addi    a0, t0, CH_DATA
9:  LEAVE   0
END_FUNCTION libp2p_gs_alloc

/*
 * libp2p_gs_push(peer, chunk) -> 1 when the chunk is queued on our gossipsub
 * stream to the peer; 0 when the peer is not ready or its queue is past
 * stream_queue (the chunk is then freed).
 */
LOCAL_FUNCTION libp2p_gs_push
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_gs_ready
    beqz    a0, 8f
    ld      a0, P_GS_OUT(s1)
    call    libp2p_stream_at
    mv      s3, a0
    ld      t0, S_Q_BYTES(s3)
    CFG     t1, LIBP2P_CFG_STREAM_QUEUE
    bltu    t1, t0, 8f
    addi    s4, s2, -HB_HEADER
    add     s4, s9, s4
    ld      t0, S_Q_TAIL(s3)
    li      t1, NONE
    bne     t0, t1, 1f
    sd      s2, S_Q_HEAD(s3)
    j       2f
1:  addi    t0, t0, -HB_HEADER
    add     t0, s9, t0
    sd      s2, CH_NEXT(t0)
2:  sd      s2, S_Q_TAIL(s3)
    ld      t0, S_Q_BYTES(s3)
    ld      t1, CH_LEN(s4)
    add     t0, t0, t1
    sd      t0, S_Q_BYTES(s3)
    li      a0, 1
    j       9f
8:  mv      a0, s2
    call    libp2p_heap_free
    li      a0, 0
9:  LEAVE   0
END_FUNCTION libp2p_gs_push

/* libp2p_pb_head(dst, field, n) -> dst after the key of a type 2 field and the length n. */
LOCAL_FUNCTION libp2p_pb_head
    ENTER   0
    mv      s1, a2
    slli    a1, a1, 3
    ori     a1, a1, 2
    call    libp2p_varint_put
    mv      a1, s1
    call    libp2p_varint_put
    LEAVE   0
END_FUNCTION libp2p_pb_head

/*
 * libp2p_gs_rpc(peer, inner, inner size, field) -> the place for inner size
 * bytes, after the varint length of the RPC and the head of its field; the
 * chunk goes in a1 (libp2p_gs_push sends it). 0 when the heap is full.
 * The RPC is one field (subscriptions 1, publish 2 or control 3) of
 * inner size bytes.
 */
LOCAL_FUNCTION libp2p_gs_rpc
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      a0, s4
    mv      a1, s3
    call    libp2p_pb_size                      # the RPC
    mv      s5, a0
    call    libp2p_varint_len
    add     a0, a0, s5
    call    libp2p_gs_alloc
    beqz    a0, 9f
    mv      s6, a1
    mv      a1, s5
    call    libp2p_varint_put
    mv      a1, s4
    mv      a2, s3
    call    libp2p_pb_head
    mv      a1, s6
9:  LEAVE   0
END_FUNCTION libp2p_gs_rpc

/* libp2p_gs_send_sub(peer, topic, subscribe): an RPC with one SubOpts. */
LOCAL_FUNCTION libp2p_gs_send_sub
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a0, 2
    ld      a1, T_LEN(s2)
    call    libp2p_pb_size
    addi    s4, a0, 2                       # subscribe (field 1, a varint 0 or 1), topicid (field 2)
    mv      a0, s1
    mv      a2, s4
    li      a3, 1
    call    libp2p_gs_rpc
    beqz    a0, 9f
    mv      s5, a1
    li      t0, 0x08
    sb      t0, 0(a0)
    sb      s3, 1(a0)
    addi    a0, a0, 2
    li      a1, 2
    addi    a2, s2, T_NAME
    ld      a3, T_LEN(s2)
    call    libp2p_pb_bytes
    mv      a0, s1
    mv      a1, s5
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_sub

/* libp2p_gs_send_msg(peer, topic, data, n): an RPC that publishes one message: data (field 2) and topic (field 4). */
LOCAL_FUNCTION libp2p_gs_send_msg
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      a0, 2
    mv      a1, s4
    call    libp2p_pb_size
    mv      s5, a0
    li      a0, 4
    ld      a1, T_LEN(s2)
    call    libp2p_pb_size
    add     s5, s5, a0
    mv      a0, s1
    mv      a1, s1
    mv      a2, s5
    li      a3, 2
    call    libp2p_gs_rpc
    beqz    a0, 9f
    mv      s6, a1
    li      a1, 2
    mv      a2, s3
    mv      a3, s4
    call    libp2p_pb_bytes
    li      a1, 4
    addi    a2, s2, T_NAME
    ld      a3, T_LEN(s2)
    call    libp2p_pb_bytes
    mv      a0, s1
    mv      a1, s6
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_msg

/* libp2p_gs_send_graft(peer, topic): control with one GRAFT. */
LOCAL_FUNCTION libp2p_gs_send_graft
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    li      a0, 1
    ld      a1, T_LEN(s2)
    call    libp2p_pb_size
    mv      s3, a0                          # ControlGraft
    li      a0, 3
    mv      a1, s3
    call    libp2p_pb_size
    mv      a2, a0                          # ControlMessage
    mv      a0, s1
    li      a3, 3
    call    libp2p_gs_rpc
    beqz    a0, 9f
    mv      s4, a1
    li      a1, 3
    mv      a2, s3
    call    libp2p_pb_head
    li      a1, 1
    addi    a2, s2, T_NAME
    ld      a3, T_LEN(s2)
    call    libp2p_pb_bytes
    mv      a0, s1
    mv      a1, s4
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_graft

/* libp2p_gs_send_prune(peer, topic, backoff seconds): control with one PRUNE: topicID (1), backoff (3). */
LOCAL_FUNCTION libp2p_gs_send_prune
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s5, a2
    li      a0, 1
    ld      a1, T_LEN(s2)
    call    libp2p_pb_size
    mv      s3, a0
    mv      a0, s5
    call    libp2p_varint_len
    add     s3, s3, a0
    addi    s3, s3, 1                       # ControlPrune
    li      a0, 4
    mv      a1, s3
    call    libp2p_pb_size
    mv      a2, a0
    mv      a0, s1
    li      a3, 3
    call    libp2p_gs_rpc
    beqz    a0, 9f
    mv      s4, a1
    li      a1, 4
    mv      a2, s3
    call    libp2p_pb_head
    li      a1, 1
    addi    a2, s2, T_NAME
    ld      a3, T_LEN(s2)
    call    libp2p_pb_bytes
    li      a1, 3
    mv      a2, s5
    call    libp2p_pb_varint
    mv      a0, s1
    mv      a1, s4
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_prune

/*
 * libp2p_gs_send_ids(peer, topic, list, count, kind): control with one IHAVE
 * (kind 1: topicID, then messageIDs as field 2), one IWANT (kind 2) or one
 * IDONTWANT (kind 5): messageIDs as field 1, no topic. The kind is the
 * field of the ControlMessage. list holds count pairs: the address of an
 * ID, then its length.
 * s1 peer, s2 topic, s3 list, s4 count, s5 kind, s6 inner size, s7 index,
 * s8 chunk.
 */
LOCAL_FUNCTION libp2p_gs_send_ids
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    li      s6, 0
    li      t0, 1
    bne     s5, t0, 1f
    li      a0, 1
    ld      a1, T_LEN(s2)
    call    libp2p_pb_size
    mv      s6, a0
1:  li      s7, 0
2:  bgeu    s7, s4, 3f
    slli    t0, s7, 4
    add     t0, s3, t0
    ld      a1, 8(t0)
    li      a0, 1
    li      t1, 1
    bne     s5, t1, 21f
    li      a0, 2
21: call    libp2p_pb_size
    add     s6, s6, a0
    addi    s7, s7, 1
    j       2b
3:  mv      a0, s5
    mv      a1, s6
    call    libp2p_pb_size
    mv      a2, a0
    mv      a0, s1
    li      a3, 3
    call    libp2p_gs_rpc
    beqz    a0, 9f
    mv      s8, a1
    mv      a1, s5
    mv      a2, s6
    call    libp2p_pb_head
    li      t0, 1
    bne     s5, t0, 4f
    li      a1, 1
    addi    a2, s2, T_NAME
    ld      a3, T_LEN(s2)
    call    libp2p_pb_bytes
4:  li      s7, 0
5:  bgeu    s7, s4, 6f
    slli    t0, s7, 4
    add     t0, s3, t0
    ld      a2, 0(t0)
    ld      a3, 8(t0)
    li      a1, 1
    li      t1, 1
    bne     s5, t1, 51f
    li      a1, 2
51: call    libp2p_pb_bytes
    addi    s7, s7, 1
    j       5b
6:  mv      a0, s1
    mv      a1, s8
    call    libp2p_gs_push
9:  LEAVE   0
END_FUNCTION libp2p_gs_send_ids

/*
 * libp2p_gs_idontwant(pending): a new message of idontwant_threshold bytes
 * or more: IDONTWANT with its ID, at once, to each mesh peer of its topic
 * that speaks /meshsub/1.2.0, except the peer that sent it.
 * s1 pending, s2 list, s3 count, s4 i.
 */
LOCAL_FUNCTION libp2p_gs_idontwant
    ENTER   0
    mv      s1, a0
    CFG     t0, LIBP2P_CFG_IDONTWANT_THRESHOLD
    beqz    t0, 9f
    ld      t1, PD_DATA_LEN(s1)
    bltu    t1, t0, 9f
    SCR     t0, SC_IDS                      # the one ID
    addi    t1, s1, PD_ID
    sd      t1, 0(t0)
    ld      t1, PD_ID_LEN(s1)
    sd      t1, 8(t0)
    li      t0, 0xFFF0000000000000          # the mesh, at any score: -infinity
    fmv.d.x fa0, t0
    ld      a0, PD_TOPIC(s1)
    li      a1, PTF_MESH
    li      a2, 0
    call    libp2p_candidates
    mv      s3, a0
    SCR     s2, SC_LIST
    li      s4, 0
1:  bgeu    s4, s3, 9f
    slli    t0, s4, 2
    add     t0, s2, t0
    lwu     a0, 0(t0)
    ld      t1, PD_PEER(s1)
    beq     a0, t1, 2f
    call    libp2p_peer_at
    ld      t0, P_FLAGS(a0)
    andi    t0, t0, PF_IDONTWANT
    beqz    t0, 2f
    li      a1, 0
    SCR     a2, SC_IDS
    li      a3, 1
    li      a4, 5
    call    libp2p_gs_send_ids
2:  addi    s4, s4, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_idontwant

/* libp2p_gs_announce(topic, subscribe): our subscription change, to every gossipsub peer. */
LOCAL_FUNCTION libp2p_gs_announce
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    TABLE   s3, ST_PEER_OFF
    ld      s4, ST_PEER_COUNT(s9)
1:  beqz    s4, 9f
    mv      a0, s3
    call    libp2p_gs_ready
    beqz    a0, 2f
    mv      a0, s3
    mv      a1, s1
    mv      a2, s2
    call    libp2p_gs_send_sub
2:  addi    s3, s3, P_SIZE
    addi    s4, s4, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_gs_announce

.include "gossip_in.s"
.include "heartbeat.s"
.include "score.s"

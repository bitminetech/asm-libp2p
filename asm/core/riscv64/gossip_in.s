/*
 * gossipsub input of the RISC-V core: the RPC reader of a peer's stream,
 * subscriptions, messages, control messages, the gossipsub events of the
 * application, and peers coming and going. Included by gossip.s.
 */

/* ---------------------------------------------------------------- Peers */

/* libp2p_gossip_peer_up(peer): a peer connected: open our gossipsub stream to it. */
LOCAL_FUNCTION libp2p_gossip_peer_up
    ENTER   0
    mv      s1, a0
    ld      t0, P_CONN(s1)
    TABLE   t1, ST_CONN_OFF
    li      t2, C_SIZE
    mul     t0, t0, t2
    add     a0, t1, t0
    li      a1, SK_GOSSIP_OUT
    li      a2, 0
    li      a3, 0
    li      a4, 1
    call    libp2p_stream_open
    beqz    a0, 9f
    call    libp2p_stream_index
    sd      a0, P_GS_OUT(s1)
9:  LEAVE   0
END_FUNCTION libp2p_gossip_peer_up

/*
 * libp2p_gossip_peer_down(peer): a peer left: out of every mesh (with the mesh
 * failure penalty), fanout and topic; its promises are forgotten. Its
 * score counters and backoffs stay for a retained score.
 * s1 peer, s2 peer index, s3 topic index, s4 topics, s5 topic, s6 entry,
 * s7 flags.
 */
LOCAL_FUNCTION libp2p_gossip_peer_down
    ENTER   0
    mv      s1, a0
    call    libp2p_peer_idx
    mv      s2, a0
    call    libp2p_promise_drop_peer
    li      s3, 0
    ld      s4, ST_TOPIC_COUNT(s9)
1:  bgeu    s3, s4, 9f
    mv      a0, s3
    call    libp2p_topic_at
    mv      s5, a0
    ld      t0, T_USED(s5)
    beqz    t0, 3f
    mv      a0, s2
    mv      a1, s3
    call    libp2p_pt
    mv      s6, a0
    ld      s7, PT_FLAGS(s6)
    andi    t0, s7, PTF_MESH
    beqz    t0, 2f
    mv      a0, s2
    mv      a1, s3
    call    libp2p_mesh_remove
2:  ld      s7, PT_FLAGS(s6)
    andi    t0, s7, PTF_SUBSCRIBED
    beqz    t0, 21f
    ld      t0, T_PEERS(s5)
    addi    t0, t0, -1
    sd      t0, T_PEERS(s5)
21: andi    t0, s7, PTF_FANOUT
    beqz    t0, 22f
    ld      t0, T_FANOUT(s5)
    addi    t0, t0, -1
    sd      t0, T_FANOUT(s5)
22: sd      zero, PT_FLAGS(s6)
    mv      a0, s5
    call    libp2p_topic_tidy
3:  addi    s3, s3, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_gossip_peer_down

/* libp2p_gossip_out_ready(stream): our gossipsub stream to a peer is open: it learns our subscriptions. */
LOCAL_FUNCTION libp2p_gossip_out_ready
    ENTER   0
    ld      a0, S_PEER(a0)
    call    libp2p_peer_at
    mv      s1, a0
    ld      t0, P_FLAGS(s1)
    ori     t0, t0, (PF_GOSSIP | PF_HELLO)
    sd      t0, P_FLAGS(s1)
    TABLE   s2, ST_TOPIC_OFF
    ld      s3, ST_TOPIC_COUNT(s9)
1:  beqz    s3, 9f
    ld      t0, T_USED(s2)
    beqz    t0, 2f
    ld      t0, T_FLAGS(s2)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 2f
    mv      a0, s1
    mv      a1, s2
    li      a2, 1
    call    libp2p_gs_send_sub
2:  addi    s2, s2, T_SIZE
    addi    s3, s3, -1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_gossip_out_ready

/* libp2p_gossip_in_ready(stream): the peer opened its gossipsub stream to us. */
LOCAL_FUNCTION libp2p_gossip_in_ready
    ENTER   0
    mv      s1, a0
    call    libp2p_stream_index
    mv      s2, a0
    ld      a0, S_PEER(s1)
    call    libp2p_peer_at
    sd      s2, P_GS_IN(a0)
    LEAVE   0
END_FUNCTION libp2p_gossip_in_ready

/* ---------------------------------------------------------------- RPC reader */

/*
 * libp2p_gossip_rx(stream, p, n): bytes of a peer's gossipsub stream: each RPC
 * is a varint length, then that many bytes, read into one heap block and
 * handled whole. An RPC above max_rpc resets the stream; one the heap
 * cannot hold is skipped.
 * s1 stream, s2 p, s3 bytes left, s4 RPC length, s5 got, s6 bytes, s7 block.
 */
LOCAL_FUNCTION libp2p_gossip_rx
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
1:  beqz    s3, 9f
    lwu     t0, S_USED(s1)
    beqz    t0, 9f
    ld      s4, S_RPC_LEN(s1)
    bnez    s4, 3f
    lbu     t0, 0(s2)                       # the length prefix
    addi    s2, s2, 1
    addi    s3, s3, -1
    ld      t1, S_RPC_VARINT(s1)
    ld      t2, S_RPC_SHIFT(s1)
    li      t3, 35
    bltu    t3, t2, 8f
    andi    t3, t0, 0x7F
    sll     t3, t3, t2
    or      t1, t1, t3
    addi    t2, t2, 7
    sd      t1, S_RPC_VARINT(s1)
    sd      t2, S_RPC_SHIFT(s1)
    andi    t0, t0, 0x80
    bnez    t0, 1b
    sd      zero, S_RPC_VARINT(s1)
    sd      zero, S_RPC_SHIFT(s1)
    beqz    t1, 1b                          # an empty RPC
    CFG     t3, LIBP2P_CFG_MAX_RPC
    bltu    t3, t1, 8f
    sd      t1, S_RPC_LEN(s1)
    sd      zero, S_RPC_GOT(s1)
    mv      a0, t1
    call    libp2p_heap_alloc
    sd      a0, S_RPC_BUF(s1)               # 0: the bytes are skipped
    j       1b
3:  ld      s5, S_RPC_GOT(s1)               # the body
    sub     t0, s4, s5
    mv      s6, s3
    bltu    s3, t0, 31f
    mv      s6, t0
31: ld      s7, S_RPC_BUF(s1)
    beqz    s7, 4f
    add     a0, s9, s7
    add     a0, a0, s5
    mv      a1, s2
    mv      a2, s6
    call    libp2p_copy
4:  add     s2, s2, s6
    sub     s3, s3, s6
    add     s5, s5, s6
    sd      s5, S_RPC_GOT(s1)
    bltu    s5, s4, 1b
    sd      zero, S_RPC_LEN(s1)
    sd      zero, S_RPC_GOT(s1)
    sd      zero, S_RPC_BUF(s1)
    beqz    s7, 1b
    ld      a0, S_PEER(s1)
    add     a1, s9, s7
    mv      a2, s4
    call    libp2p_rpc_handle
    mv      a0, s7
    call    libp2p_heap_free
    j       1b
8:  mv      a0, s1
    li      a1, LIBP2P_REASON_PROTOCOL
    call    libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_gossip_rx

/*
 * libp2p_rpc_handle(peer index, p, n): one whole RPC of a peer: subscriptions,
 * published messages and control, in their order. A graylisted peer is not
 * heard; a field that is not well formed ends the RPC.
 */
LOCAL_FUNCTION libp2p_rpc_handle
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    mv      a0, s1
    call    libp2p_peer_at
    mv      s4, a0
    lwu     t0, P_STATE(s4)
    li      t1, PS_CONNECTED
    bne     t0, t1, 9f
    mv      a0, s4
    call    libp2p_score
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_GRAYLIST_THRESHOLD)(s9)
    flt.d   t0, fa0, fa1
    bnez    t0, 9f
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 9f
    mv      s2, a5
    li      t0, 2
    bne     a2, t0, 1b
    mv      a0, s1
    mv      t1, a1
    mv      a1, a3
    mv      a2, a4
    li      t0, 1
    bne     t1, t0, 2f
    call    libp2p_rpc_sub
    j       1b
2:  li      t0, 2
    bne     t1, t0, 3f
    call    libp2p_rpc_msg
    j       1b
3:  li      t0, 3
    bne     t1, t0, 1b
    call    libp2p_rpc_control
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_handle

/*
 * libp2p_field_bytes(p, end, field) -> a0 the start and a1 the length of the
 * first type 2 field with the number, or a0 = 0.
 */
LOCAL_FUNCTION libp2p_field_bytes
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
1:  mv      a0, s1
    mv      a1, s2
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 8f
    mv      s1, a5
    bne     a1, s3, 1b
    li      t0, 2
    bne     a2, t0, 1b
    mv      a0, a3
    mv      a1, a4
    j       9f
8:  li      a0, 0
    li      a1, 0
9:  LEAVE   0
END_FUNCTION libp2p_field_bytes

/* libp2p_peer_topic(peer index, topic, subscribed): PEER_TOPIC for the application. */
LOCAL_FUNCTION libp2p_peer_topic
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, T_LEN(s2)
    addi    a1, t0, (LIBP2P_ACT_PT_TOPIC + 7)
    andi    a1, a1, -8
    li      a0, LIBP2P_ACTION_PEER_TOPIC
    call    libp2p_action
    beqz    a0, 9f
    mv      s4, a0
    mv      a0, s1
    call    libp2p_peer_at
    mv      a2, a0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_PEER(s4)
    sd      s3, LIBP2P_ACT_PT_SUBSCRIBED(s4)
    ld      a2, T_LEN(s2)
    sd      a2, LIBP2P_ACT_PT_TOPIC_LEN(s4)
    addi    a0, s4, LIBP2P_ACT_PT_TOPIC
    addi    a1, s2, T_NAME
    call    libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_peer_topic

/*
 * libp2p_rpc_sub(peer index, p, n): one SubOpts: subscribe (field 1) and topicid
 * (field 2). The peer's subscription is noted, with PEER_TOPIC; leaving a
 * topic takes it out of our mesh and fanout of the topic.
 * s1 peer index, s2 p, s3 end, s4 subscribe, s5 topic name, s6 length,
 * s7 topic, s8 topic index.
 */
LOCAL_FUNCTION libp2p_rpc_sub
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    li      s4, 0
    li      s5, 0
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 2f
    mv      s2, a5
    bne     a1, t0, 11f
    snez    s4, a3
    j       1b
11: li      t0, 2
    bne     a1, t0, 1b
    bne     a2, t0, 1b
    mv      s5, a3
    mv      s6, a4
    j       1b
2:  li      t0, NONE
    beq     a0, t0, 9f
    beqz    s5, 9f
    beqz    s6, 9f
    li      t0, LIBP2P_MAX_TOPIC
    bltu    t0, s6, 9f
    beqz    s4, 5f
    mv      a0, s5                          # subscribe
    mv      a1, s6
    call    libp2p_topic_get
    beqz    a0, 9f
    mv      s7, a0
    call    libp2p_topic_idx
    mv      a1, a0
    mv      a0, s1
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t1, t0, PTF_SUBSCRIBED
    bnez    t1, 9f
    ori     t0, t0, PTF_SUBSCRIBED
    sd      t0, PT_FLAGS(a0)
    ld      t0, T_PEERS(s7)
    addi    t0, t0, 1
    sd      t0, T_PEERS(s7)
    mv      a0, s1
    mv      a1, s7
    li      a2, 1
    call    libp2p_peer_topic
    j       9f
5:  mv      a0, s5                          # unsubscribe
    mv      a1, s6
    call    libp2p_topic_find
    beqz    a0, 9f
    mv      s7, a0
    call    libp2p_topic_idx
    mv      s8, a0
    mv      a1, a0
    mv      a0, s1
    call    libp2p_pt
    mv      s5, a0
    ld      t0, PT_FLAGS(s5)
    andi    t1, t0, PTF_SUBSCRIBED
    beqz    t1, 9f
    andi    t1, t0, PTF_MESH
    beqz    t1, 6f
    mv      a0, s1
    mv      a1, s8
    call    libp2p_mesh_remove
6:  ld      t0, PT_FLAGS(s5)
    andi    t1, t0, PTF_FANOUT
    beqz    t1, 7f
    ld      t1, T_FANOUT(s7)
    addi    t1, t1, -1
    sd      t1, T_FANOUT(s7)
7:  andi    t0, t0, ~(PTF_SUBSCRIBED | PTF_FANOUT)
    sd      t0, PT_FLAGS(s5)
    ld      t0, T_PEERS(s7)
    addi    t0, t0, -1
    sd      t0, T_PEERS(s7)
    mv      a0, s1
    mv      a1, s7
    li      a2, 0
    call    libp2p_peer_topic
    mv      a0, s7
    call    libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_rpc_sub

/*
 * libp2p_rpc_msg(peer index, p, n): one published Message. Only data (2) and
 * topic (4) may be there (StrictNoSign); from, seqno, signature or key, or
 * data above max_data, count as an invalid message of the peer. A message
 * of a topic we do not subscribe to is dropped. Otherwise it waits in a
 * pending slot, with MESSAGE, for its ID.
 * s1 peer index, s2 p, s3 end, s4 data, s5 data length, s6 topic name,
 * s7 its length, s8 1 when a signing field is there.
 */
LOCAL_FUNCTION libp2p_rpc_msg
    ENTER   16
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    li      s4, 0
    li      s5, 0
    li      s6, 0
    li      s8, 0
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 2f
    mv      s2, a5
    li      t0, 2
    bne     a1, t0, 11f
    mv      s4, a3
    mv      s5, a4
    j       1b
11: li      t0, 4
    bne     a1, t0, 12f
    mv      s6, a3
    mv      s7, a4
    j       1b
12: li      t0, 6
    bltu    t0, a1, 1b
    li      s8, 1                           # from, seqno, signature or key
    j       1b
2:  li      t0, NONE
    beq     a0, t0, 9f
    beqz    s6, 9f
    mv      a0, s6
    mv      a1, s7
    call    libp2p_topic_find
    beqz    a0, 9f
    ld      t0, T_FLAGS(a0)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 9f
    mv      s2, a0
    call    libp2p_topic_idx
    mv      s3, a0
    CFG     t0, LIBP2P_CFG_MAX_DATA
    sltu    t0, t0, s5
    or      s8, s8, t0
    beqz    s8, 3f
    mv      a0, s1                          # invalid
    mv      a1, s3
    call    libp2p_score_invalid
    j       9f
3:  li      a0, ST_PEND_OFF
    li      a1, ST_PEND_COUNT
    li      a2, PD_SIZE
    call    libp2p_alloc_slot
    beqz    a0, 9f
    mv      s6, a0
    mv      a0, s5
    call    libp2p_heap_alloc
    beqz    a0, 8f
    sd      a0, PD_DATA(s6)
    add     a0, s9, a0
    mv      a1, s4
    mv      a2, s5
    call    libp2p_copy
    sd      s1, PD_PEER(s6)
    sd      s3, PD_TOPIC(s6)
    sd      s5, PD_DATA_LEN(s6)
    ld      t0, SC_NOW(s10)
    sd      t0, PD_TIME(s6)
    li      t0, PDS_WAIT_ID
    sw      t0, PD_STATE(s6)
    ld      t0, T_LEN(s2)                   # MESSAGE
    addi    a1, t0, (LIBP2P_ACT_MSG_TOPIC + 7)
    andi    a1, a1, -8
    li      a0, LIBP2P_ACTION_MESSAGE
    call    libp2p_action
    beqz    a0, 8f
    mv      s7, a0
    li      a0, ST_PEND_OFF
    li      a1, PD_SIZE
    mv      a2, s6
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_HANDLE(s7)
    mv      a0, s1
    call    libp2p_peer_at
    mv      a2, a0
    li      a0, ST_PEER_OFF
    li      a1, P_SIZE
    call    libp2p_handle
    sd      a0, LIBP2P_ACT_MSG_PEER(s7)
    ld      t0, PD_DATA(s6)
    sd      t0, LIBP2P_ACT_MSG_DATA_OFF(s7)
    sd      s5, LIBP2P_ACT_MSG_DATA_LEN(s7)
    ld      a2, T_LEN(s2)
    sd      a2, LIBP2P_ACT_MSG_TOPIC_LEN(s7)
    addi    a0, s7, LIBP2P_ACT_MSG_TOPIC
    addi    a1, s2, T_NAME
    call    libp2p_copy
    j       9f
8:  mv      a0, s6
    call    libp2p_pend_free
9:  LEAVE   16
END_FUNCTION libp2p_rpc_msg

/* libp2p_rpc_control(peer index, p, n): a ControlMessage: ihave (1), iwant (2), graft (3), prune (4). */
LOCAL_FUNCTION libp2p_rpc_control
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 9f
    mv      s2, a5
    li      t0, 2
    bne     a2, t0, 1b
    mv      a0, s1
    mv      t1, a1
    mv      a1, a3
    mv      a2, a4
    li      t0, 1
    bne     t1, t0, 2f
    call    libp2p_ctl_ihave
    j       1b
2:  li      t0, 2
    bne     t1, t0, 3f
    call    libp2p_ctl_iwant
    j       1b
3:  li      t0, 3
    bne     t1, t0, 4f
    call    libp2p_ctl_graft
    j       1b
4:  li      t0, 4
    bne     t1, t0, 1b
    call    libp2p_ctl_prune
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_control

/* libp2p_backoff_secs(ms) -> whole seconds, rounded up. A leaf. */
LOCAL_FUNCTION libp2p_backoff_secs
    UNWIND_END_PROLOGUE
    addi    a0, a0, 999
    li      a1, 1000
    divu    a0, a0, a1
    ret
END_FUNCTION libp2p_backoff_secs

/*
 * libp2p_prune_to(peer index, topic index, backoff ms): PRUNE to the peer with
 * the backoff, and no GRAFT of it before then.
 */
LOCAL_FUNCTION libp2p_prune_to
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    call    libp2p_pt
    ld      t0, SC_NOW(s10)
    add     t0, t0, s3
    ld      t1, PT_BACKOFF(a0)
    bgeu    t0, t1, 1f
    mv      t0, t1
1:  sd      t0, PT_BACKOFF(a0)
    mv      a0, s3
    call    libp2p_backoff_secs
    mv      s4, a0
    mv      a0, s1
    call    libp2p_peer_at
    mv      s5, a0
    mv      a0, s2
    call    libp2p_topic_at
    mv      a1, a0
    mv      a0, s5
    mv      a2, s4
    call    libp2p_gs_send_prune
    LEAVE   0
END_FUNCTION libp2p_prune_to

/*
 * libp2p_ctl_graft(peer index, p, n): a GRAFT. Ignored for a topic we do not
 * subscribe to or a peer already in the mesh. Within a backoff it costs a
 * behaviour penalty (two within graft_flood of the PRUNE) and gets PRUNE;
 * a negative score, or a full mesh and an inbound peer, also get PRUNE.
 * Otherwise the peer joins the mesh.
 * s1 peer index, s2 topic, s3 topic index, s4 entry, s5 now, s6 peer.
 */
LOCAL_FUNCTION libp2p_ctl_graft
    ENTER   0
    mv      s1, a0
    mv      a0, a1
    add     a1, a1, a2
    li      a2, 1
    call    libp2p_field_bytes
    beqz    a0, 9f
    call    libp2p_topic_find
    beqz    a0, 9f
    mv      s2, a0
    ld      t0, T_FLAGS(s2)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 9f
    call    libp2p_topic_idx
    mv      s3, a0
    mv      a0, s1
    mv      a1, s3
    call    libp2p_pt
    mv      s4, a0
    ld      t0, PT_FLAGS(s4)
    andi    t0, t0, PTF_MESH
    bnez    t0, 9f
    ld      s5, SC_NOW(s10)
    ld      t0, PT_BACKOFF(s4)
    bgeu    s5, t0, 2f
    mv      a0, s1                          # within the backoff
    call    libp2p_peer_at
    mv      s6, a0
    li      a1, 1
    call    libp2p_behaviour_penalty
    ld      t0, PT_BACKOFF(s4)
    CFG     t1, LIBP2P_CFG_PRUNE_BACKOFF_MS
    sub     t0, t0, t1
    CFG     t1, LIBP2P_CFG_GRAFT_FLOOD_MS
    add     t0, t0, t1
    bgeu    s5, t0, 8f
    mv      a0, s6
    li      a1, 1
    call    libp2p_behaviour_penalty
    j       8f
2:  mv      a0, s1
    call    libp2p_peer_at
    mv      s6, a0
    call    libp2p_score
    fmv.d.x ft0, zero
    flt.d   t0, fa0, ft0
    bnez    t0, 8f
    ld      t0, T_MESH(s2)
    CFG     t1, LIBP2P_CFG_D_HIGH
    bltu    t0, t1, 3f
    ld      t0, P_FLAGS(s6)
    andi    t0, t0, PF_OUTBOUND
    beqz    t0, 8f
3:  mv      a0, s1
    mv      a1, s3
    call    libp2p_mesh_add
    j       9f
8:  mv      a0, s1
    mv      a1, s3
    CFG     a2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    call    libp2p_prune_to
9:  LEAVE   0
END_FUNCTION libp2p_ctl_graft

/*
 * libp2p_ctl_prune(peer index, p, n): a PRUNE: the peer leaves our mesh of the
 * topic, and we do not GRAFT it again for its backoff (in seconds) or
 * prune_backoff. Exchanged peers are not used.
 * s1 peer index, s2 p, s3 end, s4 topic name, s5 length, s6 backoff ms.
 */
LOCAL_FUNCTION libp2p_ctl_prune
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    li      s4, 0
    CFG     s6, LIBP2P_CFG_PRUNE_BACKOFF_MS
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 2f
    mv      s2, a5
    bne     a1, t0, 11f
    li      t0, 2
    bne     a2, t0, 1b
    mv      s4, a3
    mv      s5, a4
    j       1b
11: li      t0, 3
    bne     a1, t0, 1b
    bnez    a2, 1b
    li      t0, 86400                       # at most a day
    bltu    a3, t0, 12f
    mv      a3, t0
12: li      t0, 1000
    mul     s6, a3, t0
    j       1b
2:  beqz    s4, 9f
    mv      a0, s4
    mv      a1, s5
    call    libp2p_topic_find
    beqz    a0, 9f
    call    libp2p_topic_idx
    mv      s3, a0
    mv      a0, s1
    mv      a1, s3
    call    libp2p_pt
    mv      s2, a0
    ld      t0, PT_FLAGS(s2)
    andi    t0, t0, PTF_MESH
    beqz    t0, 3f
    mv      a0, s1
    mv      a1, s3
    call    libp2p_mesh_remove
3:  ld      t0, SC_NOW(s10)
    add     t0, t0, s6
    ld      t1, PT_BACKOFF(s2)
    bgeu    t0, t1, 4f
    mv      t0, t1
4:  sd      t0, PT_BACKOFF(s2)
9:  LEAVE   0
END_FUNCTION libp2p_ctl_prune

/*
 * libp2p_ctl_ihave(peer index, p, n): an IHAVE. Heard only from a peer at or
 * above gossip_threshold, at most max_ihave_messages times and
 * max_ihave_length IDs in a heartbeat, for a topic we subscribe to. The IDs
 * not seen go back as one IWANT, and one of them, at random, becomes a
 * promise.
 * s1 peer index, s2 p, s3 end, s4 peer, s5 list, s6 count, s7 room,
 * s8 topic. Locals: an ID (address, length) at sp + FL.
 */
LOCAL_FUNCTION libp2p_ctl_ihave
    ENTER   16
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    mv      a0, s1
    call    libp2p_peer_at
    mv      s4, a0
    call    libp2p_score
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(s9)
    flt.d   t0, fa0, fa1
    bnez    t0, 9f
    ld      t0, P_IHAVE_COUNT(s4)
    addi    t0, t0, 1
    sd      t0, P_IHAVE_COUNT(s4)
    CFG     t1, LIBP2P_CFG_MAX_IHAVE_MESSAGES
    bltu    t1, t0, 9f
    CFG     s7, LIBP2P_CFG_MAX_IHAVE_LENGTH
    ld      t0, P_IHAVE_IDS(s4)
    bgeu    t0, s7, 9f
    sub     s7, s7, t0
    mv      a0, s2
    mv      a1, s3
    li      a2, 1
    call    libp2p_field_bytes
    beqz    a0, 9f
    call    libp2p_topic_find
    beqz    a0, 9f
    mv      s8, a0
    ld      t0, T_FLAGS(s8)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 9f
    SCR     s5, SC_IDS
    li      s6, 0
1:  bgeu    s6, s7, 3f
    li      t0, (SC_IDS_SIZE / 16)
    bgeu    s6, t0, 3f
    mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 3f
    mv      s2, a5
    li      t0, 2
    bne     a1, t0, 1b
    bne     a2, t0, 1b
    beqz    a4, 1b
    li      t0, LIBP2P_MAX_MSG_ID
    bltu    t0, a4, 1b
    sd      a3, FL(sp)
    sd      a4, (FL + 8)(sp)
    mv      a0, a3
    mv      a1, a4
    call    libp2p_seen_find
    ld      a3, FL(sp)
    ld      a4, (FL + 8)(sp)
    bnez    a0, 1b
    slli    t0, s6, 4
    add     t0, s5, t0
    sd      a3, 0(t0)
    sd      a4, 8(t0)
    addi    s6, s6, 1
    j       1b
3:  beqz    s6, 9f
    ld      t0, P_IHAVE_IDS(s4)
    add     t0, t0, s6
    sd      t0, P_IHAVE_IDS(s4)
    mv      a0, s4
    mv      a1, s8
    mv      a2, s5
    mv      a3, s6
    li      a4, 2
    call    libp2p_gs_send_ids
    mv      a0, s6
    call    libp2p_random_below
    slli    t0, a0, 4
    add     t0, s5, t0
    ld      a1, 0(t0)
    ld      a2, 8(t0)
    mv      a0, s1
    call    libp2p_promise_add
9:  LEAVE   16
END_FUNCTION libp2p_ctl_ihave

/*
 * libp2p_ctl_iwant(peer index, p, n): an IWANT from a peer at or above
 * gossip_threshold: each message still in the cache goes to it, at most
 * retransmission times.
 * s1 peer index, s2 p, s3 end, s4 peer, s5 entry.
 */
LOCAL_FUNCTION libp2p_ctl_iwant
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    add     s3, a1, a2
    mv      a0, s1
    call    libp2p_peer_at
    mv      s4, a0
    call    libp2p_score
    fld     fa1, (ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)(s9)
    flt.d   t0, fa0, fa1
    bnez    t0, 9f
1:  mv      a0, s2
    mv      a1, s3
    call    libp2p_pb_next
    li      t0, 1
    bne     a0, t0, 9f
    mv      s2, a5
    bne     a1, t0, 1b
    li      t0, 2
    bne     a2, t0, 1b
    mv      a0, a3
    mv      a1, a4
    call    libp2p_mc_find
    beqz    a0, 1b
    mv      s5, a0
    mv      a1, s1
    call    libp2p_mc_sent
    beqz    a0, 1b
    ld      a0, MC_TOPIC(s5)
    call    libp2p_topic_at
    mv      a1, a0
    mv      a0, s4
    ld      a2, MC_DATA(s5)
    add     a2, s9, a2
    ld      a3, MC_DATA_LEN(s5)
    call    libp2p_gs_send_msg
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_ctl_iwant

/* ---------------------------------------------------------------- Mesh */

/* libp2p_mesh_add(peer index, topic index): the peer joins our mesh of the topic, with GRAFT. */
LOCAL_FUNCTION libp2p_mesh_add
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    ori     t0, t0, PTF_MESH
    sd      t0, PT_FLAGS(a0)
    ld      t0, SC_NOW(s10)
    sd      t0, PT_GRAFT_TIME(a0)
    mv      a0, s2
    call    libp2p_topic_at
    mv      s3, a0
    ld      t0, T_MESH(s3)
    addi    t0, t0, 1
    sd      t0, T_MESH(s3)
    mv      a0, s1
    call    libp2p_peer_at
    mv      a1, s3
    call    libp2p_gs_send_graft
    LEAVE   0
END_FUNCTION libp2p_mesh_add

/* libp2p_mesh_remove(peer index, topic index): the peer leaves our mesh of the topic, with the mesh failure penalty. */
LOCAL_FUNCTION libp2p_mesh_remove
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    call    libp2p_score_mesh_leave
    mv      a0, s1
    mv      a1, s2
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t0, t0, ~PTF_MESH
    sd      t0, PT_FLAGS(a0)
    mv      a0, s2
    call    libp2p_topic_at
    ld      t0, T_MESH(a0)
    addi    t0, t0, -1
    sd      t0, T_MESH(a0)
    LEAVE   0
END_FUNCTION libp2p_mesh_remove

/*
 * libp2p_candidates(topic index, need flags, refuse flags, floor) -> the count
 * of peers in the list at SC_LIST (u32 peer indexes): gossipsub peers
 * subscribed to the topic whose entry has every need flag and no refuse
 * flag, whose score is at or above floor (fa0), and, when the backoff bit
 * of refuse is set, outside a backoff.
 * s1 topic index, s2 need, s3 refuse, s4 peer index, s5 count, s6 list,
 * s7 peer. Local: the floor at sp + FL.
 */
.set CAND_BACKOFF, 0x100
.set CAND_OUTBOUND, 0x200               /* need: outbound peers only */
LOCAL_FUNCTION libp2p_candidates
    ENTER   16
    fsd     fa0, FL(sp)
    mv      s1, a0
    ori     s2, a1, PTF_SUBSCRIBED
    mv      s3, a2
    li      s4, 0
    li      s5, 0
    SCR     s6, SC_LIST
1:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s4, t0, 9f
    mv      a0, s4
    call    libp2p_peer_at
    mv      s7, a0
    call    libp2p_gs_ready
    beqz    a0, 2f
    fld     fa0, P_SCORE(s7)
    fld     fa1, FL(sp)
    flt.d   t0, fa0, fa1
    bnez    t0, 2f
    andi    t0, s2, CAND_OUTBOUND
    beqz    t0, 11f
    ld      t0, P_FLAGS(s7)
    andi    t0, t0, PF_OUTBOUND
    beqz    t0, 2f
11: mv      a0, s4
    mv      a1, s1
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t1, s2, 0xFF
    and     t2, t0, t1
    bne     t2, t1, 2f
    andi    t1, s3, 0xFF
    and     t2, t0, t1
    bnez    t2, 2f
    andi    t1, s3, CAND_BACKOFF
    beqz    t1, 12f
    ld      t0, PT_BACKOFF(a0)
    ld      t1, SC_NOW(s10)
    bltu    t1, t0, 2f
12: slli    t0, s5, 2
    add     t0, s6, t0
    sw      s4, 0(t0)
    addi    s5, s5, 1
2:  addi    s4, s4, 1
    j       1b
9:  mv      a0, s5
    LEAVE   16
END_FUNCTION libp2p_candidates

/* libp2p_shuffle(list, count): a random order of the u32 values (Fisher-Yates). */
LOCAL_FUNCTION libp2p_shuffle
    ENTER   0
    mv      s1, a0
    mv      s2, a1
1:  li      t0, 1
    bgeu    t0, s2, 9f
    mv      a0, s2
    call    libp2p_random_below
    addi    s2, s2, -1
    slli    t0, a0, 2
    add     t0, s1, t0
    slli    t1, s2, 2
    add     t1, s1, t1
    lwu     t2, 0(t0)
    lwu     t3, 0(t1)
    sw      t3, 0(t0)
    sw      t2, 0(t1)
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_shuffle

/* ---------------------------------------------------------------- Application events */

/*
 * libp2p_on_subscribe(event): we join a topic: our fanout peers of it, then
 * other subscribed peers at random, fill the mesh up to D (score 0 or more,
 * outside backoff), each with GRAFT; every gossipsub peer hears of it.
 * s1 topic, s2 topic index, s3 mesh count, s4 list, s5 count, s6 i.
 */
LOCAL_FUNCTION libp2p_on_subscribe
    ENTER   0
    ld      a1, LIBP2P_EV_TOPIC_LEN(a0)
    addi    a0, a0, LIBP2P_EV_TOPIC
    call    libp2p_topic_get
    beqz    a0, 9f
    mv      s1, a0
    ld      t0, T_FLAGS(s1)
    andi    t1, t0, TF_SUBSCRIBED
    bnez    t1, 9f
    ori     t0, t0, TF_SUBSCRIBED
    sd      t0, T_FLAGS(s1)
    call    libp2p_topic_idx
    mv      s2, a0
    call    libp2p_score_all
    li      s3, 0
    fmv.d.x fa0, zero                       # fanout peers first
    mv      a0, s2
    li      a1, PTF_FANOUT
    li      a2, CAND_BACKOFF
    call    libp2p_candidates
    mv      s5, a0
    SCR     s4, SC_LIST
    li      s6, 0
1:  bgeu    s6, s5, 3f
    slli    t0, s6, 2
    add     t0, s4, t0
    lwu     a0, 0(t0)
    mv      a1, s2
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t0, t0, ~PTF_FANOUT
    sd      t0, PT_FLAGS(a0)
    ld      t0, T_FANOUT(s1)
    addi    t0, t0, -1
    sd      t0, T_FANOUT(s1)
    CFG     t0, LIBP2P_CFG_D
    bgeu    s3, t0, 2f
    slli    t0, s6, 2
    add     t0, s4, t0
    lwu     a0, 0(t0)
    mv      a1, s2
    call    libp2p_mesh_add
    addi    s3, s3, 1
2:  addi    s6, s6, 1
    j       1b
3:  call    libp2p_fanout_clear_topic
    CFG     t0, LIBP2P_CFG_D
    bgeu    s3, t0, 5f
    fmv.d.x fa0, zero
    mv      a0, s2
    li      a1, 0
    li      a2, (PTF_MESH | CAND_BACKOFF)
    call    libp2p_candidates
    mv      s5, a0
    mv      a0, s4
    mv      a1, s5
    call    libp2p_shuffle
    li      s6, 0
4:  bgeu    s6, s5, 5f
    CFG     t0, LIBP2P_CFG_D
    bgeu    s3, t0, 5f
    slli    t0, s6, 2
    add     t0, s4, t0
    lwu     a0, 0(t0)
    mv      a1, s2
    call    libp2p_mesh_add
    addi    s3, s3, 1
    addi    s6, s6, 1
    j       4b
5:  mv      a0, s1
    li      a1, 1
    call    libp2p_gs_announce
9:  LEAVE   0
END_FUNCTION libp2p_on_subscribe

/* libp2p_fanout_clear_topic(): (s1 topic, s2 index) no peer stays in its fanout. s3 peer index. */
LOCAL_FUNCTION libp2p_fanout_clear_topic
    ENTER   0
    li      s3, 0
1:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s3, t0, 9f
    mv      a0, s3
    mv      a1, s2
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t1, t0, PTF_FANOUT
    beqz    t1, 2f
    andi    t0, t0, ~PTF_FANOUT
    sd      t0, PT_FLAGS(a0)
    ld      t0, T_FANOUT(s1)
    addi    t0, t0, -1
    sd      t0, T_FANOUT(s1)
2:  addi    s3, s3, 1
    j       1b
9:  LEAVE   0
END_FUNCTION libp2p_fanout_clear_topic

/*
 * libp2p_on_unsubscribe(event): we leave a topic: every mesh peer gets PRUNE
 * with unsubscribe_backoff and leaves the mesh; every gossipsub peer hears
 * of it.
 * s1 topic, s2 topic index, s3 peer index.
 */
LOCAL_FUNCTION libp2p_on_unsubscribe
    ENTER   0
    ld      a1, LIBP2P_EV_TOPIC_LEN(a0)
    addi    a0, a0, LIBP2P_EV_TOPIC
    call    libp2p_topic_find
    beqz    a0, 9f
    mv      s1, a0
    ld      t0, T_FLAGS(s1)
    andi    t1, t0, TF_SUBSCRIBED
    beqz    t1, 9f
    andi    t0, t0, ~TF_SUBSCRIBED
    sd      t0, T_FLAGS(s1)
    call    libp2p_topic_idx
    mv      s2, a0
    li      s3, 0
1:  ld      t0, ST_PEER_COUNT(s9)
    bgeu    s3, t0, 3f
    mv      a0, s3
    mv      a1, s2
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    andi    t0, t0, PTF_MESH
    beqz    t0, 2f
    mv      a0, s3
    mv      a1, s2
    CFG     a2, LIBP2P_CFG_UNSUB_BACKOFF_MS
    call    libp2p_prune_to
    mv      a0, s3
    mv      a1, s2
    call    libp2p_mesh_remove
2:  addi    s3, s3, 1
    j       1b
3:  mv      a0, s1
    li      a1, 0
    call    libp2p_gs_announce
    mv      a0, s1
    call    libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_on_unsubscribe

/*
 * libp2p_on_publish(event): our own message. Already seen: not sent. Else it is
 * seen (valid), cached, and sent: with flood_publish to every subscribed
 * peer at or above publish_threshold; else to the mesh, or to the fanout
 * of a topic we do not subscribe to (filled up to D). PUBLISHED gives the
 * number of peers.
 * s1 event, s2 topic, s3 topic index, s4 data block, s5 peers sent,
 * s6 list, s7 count, s8 i.
 */
LOCAL_FUNCTION libp2p_on_publish
    ENTER   0
    mv      s1, a0
    li      s5, 0
    addi    a0, s1, LIBP2P_EV_PUB_ID
    ld      a1, LIBP2P_EV_PUB_ID_LEN(s1)
    call    libp2p_seen_find
    bnez    a0, 8f
    addi    a0, s1, LIBP2P_EV_PUB_TOPIC
    ld      a1, LIBP2P_EV_PUB_TOPIC_LEN(s1)
    call    libp2p_topic_get
    beqz    a0, 8f
    mv      s2, a0
    call    libp2p_topic_idx
    mv      s3, a0
    ld      a0, LIBP2P_EV_PUB_DATA_LEN(s1)
    call    libp2p_heap_alloc
    beqz    a0, 8f
    mv      s4, a0
    ld      t0, LIBP2P_EV_PUB_TOPIC_LEN(s1) # the data follows the topic, at a multiple of 8
    addi    t0, t0, 7
    andi    t0, t0, -8
    addi    a1, s1, LIBP2P_EV_PUB_TOPIC
    add     a1, a1, t0
    add     a0, s9, s4
    ld      a2, LIBP2P_EV_PUB_DATA_LEN(s1)
    call    libp2p_copy
    addi    a0, s1, LIBP2P_EV_PUB_ID
    ld      a1, LIBP2P_EV_PUB_ID_LEN(s1)
    mv      a2, s3
    li      a3, SS_VALID
    call    libp2p_seen_add
    addi    a0, s1, LIBP2P_EV_PUB_ID
    ld      a1, LIBP2P_EV_PUB_ID_LEN(s1)
    mv      a2, s3
    mv      a3, s4
    ld      a4, LIBP2P_EV_PUB_DATA_LEN(s1)
    call    libp2p_mc_put
    call    libp2p_score_all
    CFG     t0, LIBP2P_CFG_FLOOD_PUBLISH
    beqz    t0, 2f
    fld     fa0, (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(s9)
    mv      a0, s3
    li      a1, 0
    li      a2, 0
    call    libp2p_candidates
    j       6f
2:  ld      t0, T_FLAGS(s2)
    andi    t0, t0, TF_SUBSCRIBED
    beqz    t0, 3f
    li      t0, 0xFFF0000000000000          # the mesh, at any score: -infinity
    fmv.d.x fa0, t0
    mv      a0, s3
    li      a1, PTF_MESH
    li      a2, 0
    call    libp2p_candidates
    j       6f
3:  ld      t0, SC_NOW(s10)                 # the fanout
    sd      t0, T_FANOUT_LAST(s2)
    ld      t0, T_FANOUT(s2)
    bnez    t0, 5f
    fld     fa0, (ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)(s9)
    mv      a0, s3
    li      a1, 0
    li      a2, 0
    call    libp2p_candidates
    mv      s7, a0
    SCR     s6, SC_LIST
    mv      a0, s6
    mv      a1, s7
    call    libp2p_shuffle
    CFG     t0, LIBP2P_CFG_D
    bltu    s7, t0, 31f
    mv      s7, t0
31: li      s8, 0
4:  bgeu    s8, s7, 5f
    slli    t0, s8, 2
    add     t0, s6, t0
    lwu     a0, 0(t0)
    mv      a1, s3
    call    libp2p_pt
    ld      t0, PT_FLAGS(a0)
    ori     t0, t0, PTF_FANOUT
    sd      t0, PT_FLAGS(a0)
    ld      t0, T_FANOUT(s2)
    addi    t0, t0, 1
    sd      t0, T_FANOUT(s2)
    addi    s8, s8, 1
    j       4b
5:  li      t0, 0xFFF0000000000000
    fmv.d.x fa0, t0
    mv      a0, s3
    li      a1, PTF_FANOUT
    li      a2, 0
    call    libp2p_candidates
6:  mv      s7, a0                          # send to the list
    SCR     s6, SC_LIST
    li      s8, 0
7:  bgeu    s8, s7, 8f
    slli    t0, s8, 2
    add     t0, s6, t0
    lwu     a0, 0(t0)
    call    libp2p_peer_at
    mv      a1, s2
    add     a2, s9, s4
    ld      a3, LIBP2P_EV_PUB_DATA_LEN(s1)
    call    libp2p_gs_send_msg
    add     s5, s5, a0
    addi    s8, s8, 1
    j       7b
8:  li      a0, LIBP2P_ACTION_PUBLISHED
    li      a1, LIBP2P_ACT_PUB_SIZE
    call    libp2p_action
    beqz    a0, 9f
    mv      s6, a0
    ld      a2, LIBP2P_EV_PUB_ID_LEN(s1)
    sd      a2, LIBP2P_ACT_PUB_ID_LEN(s6)
    addi    a0, s6, LIBP2P_ACT_PUB_ID
    addi    a1, s1, LIBP2P_EV_PUB_ID
    call    libp2p_copy
    sd      s5, LIBP2P_ACT_PUB_PEERS(s6)
9:  LEAVE   0
END_FUNCTION libp2p_on_publish

/*
 * libp2p_on_message_id(event): the ID of a message waiting for one. Seen
 * before: a duplicate (scores, promises), MESSAGE_STATUS duplicate, and
 * the slot is free. Else it is seen (pending), promises of it are kept,
 * and MESSAGE_STATUS new asks for a VALIDATION.
 * s1 event, s2 pending, s3 seen.
 */
LOCAL_FUNCTION libp2p_on_message_id
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_HANDLE(s1)
    call    libp2p_pend
    beqz    a0, 9f
    mv      s2, a0
    lwu     t0, PD_STATE(s2)
    li      t1, PDS_WAIT_ID
    bne     t0, t1, 9f
    ld      a2, LIBP2P_EV_MSG_ID_LEN(s1)
    sd      a2, PD_ID_LEN(s2)
    addi    a0, s2, PD_ID
    addi    a1, s1, LIBP2P_EV_MSG_ID
    call    libp2p_copy
    addi    a0, s2, PD_ID
    ld      a1, PD_ID_LEN(s2)
    call    libp2p_promise_keep
    addi    a0, s2, PD_ID
    ld      a1, PD_ID_LEN(s2)
    call    libp2p_seen_find
    beqz    a0, 1f
    mv      s3, a0                          # a duplicate
    ld      a0, PD_PEER(s2)
    mv      a1, s3
    call    libp2p_score_duplicate
    mv      a0, s2
    li      a1, LIBP2P_MSG_DUPLICATE
    call    libp2p_pend_status
    mv      a0, s2
    call    libp2p_pend_free
    j       9f
1:  addi    a0, s2, PD_ID
    ld      a1, PD_ID_LEN(s2)
    ld      a2, PD_TOPIC(s2)
    li      a3, SS_PENDING
    call    libp2p_seen_add
    TABLE   t0, ST_SEEN_OFF
    sub     t0, a0, t0
    li      t1, SN_SIZE
    divu    t0, t0, t1
    sd      t0, PD_SEEN(s2)
    li      t0, PDS_WAIT_VERDICT
    sw      t0, PD_STATE(s2)
    mv      a0, s2
    li      a1, LIBP2P_MSG_NEW
    call    libp2p_pend_status
9:  LEAVE   0
END_FUNCTION libp2p_on_message_id

/*
 * libp2p_on_validation(event): the application judged a new message. ACCEPT:
 * seen valid, first-delivery and mesh-delivery scores, cached, and sent to
 * the mesh of the topic except the peers that already sent it. REJECT:
 * seen invalid and an invalid message for those peers. IGNORE: seen
 * ignored. Then the slot is free.
 * s1 event, s2 pending, s3 seen, s4 result, s5 topic, s6 i, s7 list,
 * s8 count.
 */
LOCAL_FUNCTION libp2p_on_validation
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_HANDLE(s1)
    call    libp2p_pend
    beqz    a0, 9f
    mv      s2, a0
    lwu     t0, PD_STATE(s2)
    li      t1, PDS_WAIT_VERDICT
    bne     t0, t1, 9f
    ld      s4, LIBP2P_EV_RESULT(s1)
    ld      t0, PD_SEEN(s2)                 # the seen entry, if it is still that message
    TABLE   s3, ST_SEEN_OFF
    li      t1, SN_SIZE
    mul     t0, t0, t1
    add     s3, s3, t0
    addi    a0, s3, SN_ID
    ld      a1, SN_ID_LEN(s3)
    addi    a2, s2, PD_ID
    ld      a3, PD_ID_LEN(s2)
    call    libp2p_compare
    bnez    a0, 1f
    li      s3, 0
1:  li      t0, LIBP2P_ACCEPT
    bne     s4, t0, 5f
    beqz    s3, 2f
    li      t0, SS_VALID
    sd      t0, SN_STATUS(s3)
    ld      t0, SC_NOW(s10)
    sd      t0, SN_VALIDATED(s3)
2:  ld      a0, PD_PEER(s2)
    ld      a1, PD_TOPIC(s2)
    mv      a2, s3
    call    libp2p_score_valid
    addi    a0, s2, PD_ID                   # cached: the cache owns the data now
    ld      a1, PD_ID_LEN(s2)
    ld      a2, PD_TOPIC(s2)
    ld      a3, PD_DATA(s2)
    ld      a4, PD_DATA_LEN(s2)
    call    libp2p_mc_put
    ld      a0, PD_TOPIC(s2)
    call    libp2p_topic_at
    mv      s5, a0
    li      t0, 0xFFF0000000000000
    fmv.d.x fa0, t0
    ld      a0, PD_TOPIC(s2)
    li      a1, PTF_MESH
    li      a2, 0
    call    libp2p_candidates
    mv      s8, a0
    SCR     s7, SC_LIST
    li      s6, 0
3:  bgeu    s6, s8, 4f
    slli    t0, s6, 2
    add     t0, s7, t0
    lwu     a0, 0(t0)
    ld      t1, PD_PEER(s2)
    beq     a0, t1, 31f
    mv      a1, s3
    call    libp2p_seen_delivered
    bnez    a0, 31f
    slli    t0, s6, 2
    add     t0, s7, t0
    lwu     a0, 0(t0)
    call    libp2p_peer_at
    mv      a1, s5
    ld      a2, PD_DATA(s2)
    add     a2, s9, a2
    ld      a3, PD_DATA_LEN(s2)
    call    libp2p_gs_send_msg
31: addi    s6, s6, 1
    j       3b
4:  sd      zero, PD_DATA(s2)
    j       8f
5:  li      t0, LIBP2P_REJECT
    bne     s4, t0, 6f
    beqz    s3, 51f
    li      t0, SS_INVALID
    sd      t0, SN_STATUS(s3)
51: ld      a0, PD_PEER(s2)
    ld      a1, PD_TOPIC(s2)
    mv      a2, s3
    call    libp2p_score_rejected
    j       8f
6:  beqz    s3, 8f
    li      t0, SS_IGNORED
    sd      t0, SN_STATUS(s3)
8:  mv      a0, s2
    call    libp2p_pend_free
9:  LEAVE   0
END_FUNCTION libp2p_on_validation

/* libp2p_seen_delivered(peer index, seen) -> 1 when the peer is a deliverer of the seen message, else 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_delivered
    UNWIND_END_PROLOGUE
    beqz    a1, 8f
    lwu     a2, SN_COUNT(a1)
    addi    a3, a1, SN_PEERS
1:  beqz    a2, 8f
    lhu     a4, 0(a3)
    addi    a3, a3, 2
    beq     a4, a0, 7f
    addi    a2, a2, -1
    j       1b
7:  li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION libp2p_seen_delivered

/* libp2p_on_app_score(event): the application-specific score of a peer (P5). */
LOCAL_FUNCTION libp2p_on_app_score
    ENTER   0
    mv      s1, a0
    ld      a0, LIBP2P_EV_PEER(s1)
    call    libp2p_peer
    beqz    a0, 9f
    ld      t0, LIBP2P_EV_SCORE(s1)
    sd      t0, P_APP_SCORE(a0)
9:  LEAVE   0
END_FUNCTION libp2p_on_app_score

/* libp2p_on_topic_params(event): the score parameters of a topic. */
LOCAL_FUNCTION libp2p_on_topic_params
    ENTER   0
    mv      s1, a0
    addi    a0, s1, LIBP2P_EV_TP_TOPIC
    ld      a1, LIBP2P_EV_TP_TOPIC_LEN(s1)
    call    libp2p_topic_get
    beqz    a0, 9f
    mv      s2, a0
    addi    a0, s2, T_PARAMS
    addi    a1, s1, LIBP2P_EV_TP_PARAMS
    li      a2, LIBP2P_TP_SIZE
    call    libp2p_copy
    ld      t0, T_FLAGS(s2)
    ori     t0, t0, TF_PARAMS
    sd      t0, T_FLAGS(s2)
9:  LEAVE   0
END_FUNCTION libp2p_on_topic_params

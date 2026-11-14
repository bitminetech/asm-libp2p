/*
 * gossipsub input of the ARM64 core: the RPC reader of a peer's stream,
 * subscriptions, messages, control messages, the gossipsub events of the
 * application, and peers coming and going. Included by gossip.s.
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
    mov     x19, x0
    str     xzr, [x19, #P_DW_HEAD]
    str     xzr, [x19, #P_DW_COUNT]
    bl      libp2p_peer_idx
    bl      libp2p_dw_ring
    CFG     x9, LIBP2P_CFG_DONTWANT_SLOTS
    mov     x10, #DW_SIZE
    mul     x1, x9, x10
    bl      libp2p_zero
    ldr     x9, [x19, #P_CONN]
    TABLE   x10, ST_CONN_OFF
    mov     x11, #C_SIZE
    madd    x0, x9, x11, x10
    mov     x1, #SK_GOSSIP_OUT
    mov     x2, #0
    mov     x3, #0
    CFG     x9, LIBP2P_CFG_GOSSIPSUB_V12
    CFG     x10, LIBP2P_CFG_GOSSIPSUB_V13
    add     x4, x9, x10
    add     x4, x4, #1
    bl      libp2p_stream_open
    cbz     x0, 9f
    bl      libp2p_stream_index
    str     x0, [x19, #P_GS_OUT]
9:  LEAVE   0
END_FUNCTION libp2p_gossip_peer_up

/*
 * libp2p_gossip_peer_down(peer): a peer left: out of every mesh (with the mesh
 * failure penalty), fanout and topic; its promises are forgotten. Its
 * score counters and backoffs stay for a retained score.
 * x19 peer, x20 peer index, x21 topic index, x22 topics.
 */
LOCAL_FUNCTION libp2p_gossip_peer_down
    ENTER   0
    mov     x19, x0
    bl      libp2p_peer_idx
    mov     x20, x0
    bl      libp2p_promise_drop_peer
    mov     x21, #0
    ldr     x22, [x27, #ST_TOPIC_COUNT]
1:  cmp     x21, x22
    b.hs    9f
    mov     x0, x21
    bl      libp2p_topic_at
    mov     x23, x0
    ldr     x9, [x23, #T_USED]
    cbz     x9, 3f
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_pt
    mov     x24, x0
    ldr     x25, [x24, #PT_FLAGS]
    tst     x25, #PTF_MESH
    b.eq    2f
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_mesh_remove
2:  ldr     x25, [x24, #PT_FLAGS]
    tst     x25, #PTF_SUBSCRIBED
    b.eq    21f
    ldr     x9, [x23, #T_PEERS]
    sub     x9, x9, #1
    str     x9, [x23, #T_PEERS]
21: tst     x25, #PTF_FANOUT
    b.eq    22f
    ldr     x9, [x23, #T_FANOUT]
    sub     x9, x9, #1
    str     x9, [x23, #T_FANOUT]
22: str     xzr, [x24, #PT_FLAGS]
    mov     x0, x23
    bl      libp2p_topic_tidy
3:  add     x21, x21, #1
    b       1b
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
    mov     x22, x0
    ldr     x0, [x22, #S_PEER]
    bl      libp2p_peer_at
    mov     x19, x0
    ldr     x9, [x19, #P_FLAGS]
    orr     x9, x9, #(PF_GOSSIP | PF_HELLO)
    ldr     x10, [x22, #S_PROTO]            /* the index of the proposal taken */
    CFG     x11, LIBP2P_CFG_GOSSIPSUB_V12
    CFG     x12, LIBP2P_CFG_GOSSIPSUB_V13
    add     x11, x11, x12                   /* the index of /meshsub/1.1.0 */
    cmp     x10, x11
    b.hs    3f
    orr     x9, x9, #PF_IDONTWANT
3:  str     x9, [x19, #P_FLAGS]
    cbnz    x10, 4f                         /* /meshsub/1.3.0: our extensions first */
    cbz     x12, 4f
    mov     x0, x19
    bl      libp2p_gs_send_ext
4:  TABLE   x20, ST_TOPIC_OFF
    ldr     x21, [x27, #ST_TOPIC_COUNT]
1:  cbz     x21, 9f
    ldr     x9, [x20, #T_USED]
    cbz     x9, 2f
    ldr     x9, [x20, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    2f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #1
    bl      libp2p_gs_send_sub
2:  add     x20, x20, #T_SIZE
    sub     x21, x21, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_gossip_out_ready

/*
 * libp2p_gossip_in_ready(stream): the peer opened its gossipsub stream to us:
 * its extensions come with the first RPC on it.
 */
LOCAL_FUNCTION libp2p_gossip_in_ready
    ENTER   0
    mov     x19, x0
    bl      libp2p_stream_index
    mov     x20, x0
    ldr     x0, [x19, #S_PEER]
    bl      libp2p_peer_at
    str     x20, [x0, #P_GS_IN]
    ldr     x9, [x0, #P_FLAGS]
    mov     x10, #(PF_EXT_SEEN | PF_EXT_GOT | PF_PARTIAL)
    bic     x9, x9, x10
    str     x9, [x0, #P_FLAGS]
    LEAVE   0
END_FUNCTION libp2p_gossip_in_ready

/* ---------------------------------------------------------------- RPC reader */

/*
 * libp2p_gossip_rx(stream, p, n): bytes of a peer's gossipsub stream: each RPC
 * is a varint length, then that many bytes, read into one heap block and
 * handled whole. An RPC above max_rpc resets the stream; one the heap
 * cannot hold is skipped. A block that PARTIAL actions refer to stays, on
 * the ST_KEPT_RPC list, until the next step.
 * x19 stream, x20 p, x21 bytes left.
 */
LOCAL_FUNCTION libp2p_gossip_rx
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x21, 9f
    ldr     w9, [x19, #S_USED]
    cbz     w9, 9f
    ldr     x22, [x19, #S_RPC_LEN]
    cbnz    x22, 3f
    ldrb    w9, [x20], #1                   /* the length prefix */
    sub     x21, x21, #1
    ldr     x10, [x19, #S_RPC_VARINT]
    ldr     x11, [x19, #S_RPC_SHIFT]
    cmp     x11, #35
    b.hi    8f
    and     x12, x9, #0x7F
    lsl     x12, x12, x11
    orr     x10, x10, x12
    add     x11, x11, #7
    str     x10, [x19, #S_RPC_VARINT]
    str     x11, [x19, #S_RPC_SHIFT]
    tbnz    w9, #7, 1b
    str     xzr, [x19, #S_RPC_VARINT]
    str     xzr, [x19, #S_RPC_SHIFT]
    cbz     x10, 1b                         /* an empty RPC */
    CFG     x12, LIBP2P_CFG_MAX_RPC
    cmp     x10, x12
    b.hi    8f
    str     x10, [x19, #S_RPC_LEN]
    str     xzr, [x19, #S_RPC_GOT]
    mov     x0, x10
    bl      libp2p_heap_alloc
    str     x0, [x19, #S_RPC_BUF]           /* 0: the bytes are skipped */
    b       1b
3:  ldr     x23, [x19, #S_RPC_GOT]          /* the body */
    sub     x9, x22, x23
    cmp     x21, x9
    csel    x24, x21, x9, lo
    ldr     x25, [x19, #S_RPC_BUF]
    cbz     x25, 4f
    add     x0, x27, x25
    add     x0, x0, x23
    mov     x1, x20
    mov     x2, x24
    bl      libp2p_copy
4:  add     x20, x20, x24
    sub     x21, x21, x24
    add     x23, x23, x24
    str     x23, [x19, #S_RPC_GOT]
    cmp     x23, x22
    b.lo    1b
    str     xzr, [x19, #S_RPC_LEN]
    str     xzr, [x19, #S_RPC_GOT]
    str     xzr, [x19, #S_RPC_BUF]
    cbz     x25, 1b
    ldr     x0, [x19, #S_PEER]
    add     x1, x27, x25
    mov     x2, x22
    bl      libp2p_rpc_handle
    cbz     x0, 5f
    sub     x9, x25, #HB_HEADER             /* kept until the next step */
    add     x9, x27, x9
    ldr     x10, [x27, #ST_KEPT_RPC]
    str     x10, [x9, #HB_NEXT]
    str     x25, [x27, #ST_KEPT_RPC]
    b       1b
5:  mov     x0, x25
    bl      libp2p_heap_free
    b       1b
8:  mov     x0, x19
    mov     x1, #LIBP2P_REASON_PROTOCOL
    bl      libp2p_stream_abort
9:  LEAVE   0
END_FUNCTION libp2p_gossip_rx

/*
 * libp2p_rpc_handle(peer index, p, n) -> 1 when a PARTIAL action refers to
 * the bytes of the RPC, else 0: one whole RPC of a peer: subscriptions,
 * published messages, control and partial messages, in their order. A
 * graylisted peer is not heard; a field that is not well formed ends the
 * RPC. After the first RPC, the extensions of the peer are known.
 * x19 peer index, x20 p, x21 end, x22 peer, x23 result.
 */
LOCAL_FUNCTION libp2p_rpc_handle
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x23, #0
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x22, x0
    ldr     w9, [x22, #P_STATE]
    cmp     w9, #PS_CONNECTED
    b.ne    9f
    mov     x0, x22
    bl      libp2p_score
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_GRAYLIST_THRESHOLD)]
    fcmp    d0, d1
    b.mi    8f
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    8f
    mov     x20, x5
    cmp     x2, #2
    b.ne    1b
    mov     x0, x19
    mov     x9, x1
    mov     x1, x3
    mov     x2, x4
    cmp     x9, #1
    b.ne    2f
    bl      libp2p_rpc_sub
    b       1b
2:  cmp     x9, #2
    b.ne    3f
    bl      libp2p_rpc_msg
    b       1b
3:  cmp     x9, #3
    b.ne    4f
    bl      libp2p_rpc_control
    b       1b
4:  cmp     x9, #10
    b.ne    1b
    bl      libp2p_rpc_partial
    orr     x23, x23, x0
    b       1b
8:  ldr     x9, [x22, #P_FLAGS]             /* its extensions are known now */
    orr     x9, x9, #PF_EXT_SEEN
    str     x9, [x22, #P_FLAGS]
9:  mov     x0, x23
    LEAVE   0
END_FUNCTION libp2p_rpc_handle

/*
 * libp2p_field_bytes(p, end, field) -> x0 the start and x1 the length of the
 * first type 2 field with the number, or x0 = 0.
 */
LOCAL_FUNCTION libp2p_field_bytes
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  mov     x0, x19
    mov     x1, x20
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    8f
    mov     x19, x5
    cmp     x1, x21
    b.ne    1b
    cmp     x2, #2
    b.ne    1b
    mov     x0, x3
    mov     x1, x4
    b       9f
8:  mov     x0, #0
    mov     x1, #0
9:  LEAVE   0
END_FUNCTION libp2p_field_bytes

/* libp2p_peer_topic(peer index, topic, subscribed): PEER_TOPIC for the application. */
LOCAL_FUNCTION libp2p_peer_topic
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x20, #T_LEN]
    add     x1, x9, #(LIBP2P_ACT_PT_TOPIC + 7)
    and     x1, x1, #~7
    mov     x0, #LIBP2P_ACTION_PEER_TOPIC
    bl      libp2p_action
    cbz     x0, 9f
    mov     x22, x0
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x2, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x22, #LIBP2P_ACT_PEER]
    str     x21, [x22, #LIBP2P_ACT_PT_SUBSCRIBED]
    ldr     x2, [x20, #T_LEN]
    str     x2, [x22, #LIBP2P_ACT_PT_TOPIC_LEN]
    add     x0, x22, #LIBP2P_ACT_PT_TOPIC
    add     x1, x20, #T_NAME
    bl      libp2p_copy
9:  LEAVE   0
END_FUNCTION libp2p_peer_topic

/*
 * libp2p_rpc_sub(peer index, p, n): one SubOpts: subscribe (field 1), topicid
 * (field 2), requestsPartial (3) and supportsSendingPartial (4). The peer's
 * subscription and its partial flags are noted, with PEER_TOPIC for a new
 * one; leaving a topic takes it out of our mesh and fanout of the topic.
 * x19 peer index, x20 p, x21 end, x22 subscribe, x23 topic name, x24 length,
 * x25 topic, x26 partial flags (LIBP2P_PARTIAL_*).
 */
LOCAL_FUNCTION libp2p_rpc_sub
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x22, #0
    mov     x23, #0
    mov     x26, #0
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    2f
    mov     x20, x5
    cmp     x1, #1
    b.ne    11f
    cmp     x3, #0
    cset    x22, ne
    b       1b
11: cmp     x1, #2
    b.ne    12f
    cmp     x2, #2
    b.ne    1b
    mov     x23, x3
    mov     x24, x4
    b       1b
12: cmp     x2, #0                          /* requestsPartial: supports too */
    b.ne    1b
    cbz     x3, 1b
    cmp     x1, #3
    b.ne    13f
    orr     x26, x26, #(LIBP2P_PARTIAL_REQUESTS | LIBP2P_PARTIAL_SUPPORTS)
    b       1b
13: cmp     x1, #4
    b.ne    1b
    orr     x26, x26, #LIBP2P_PARTIAL_SUPPORTS
    b       1b
2:  cmn     x0, #1
    b.eq    9f
    cbz     x23, 9f
    cbz     x24, 9f
    cmp     x24, #LIBP2P_MAX_TOPIC
    b.hi    9f
    cbz     x22, 5f
    mov     x0, x23                         /* subscribe */
    mov     x1, x24
    bl      libp2p_topic_get
    cbz     x0, 9f
    mov     x25, x0
    bl      libp2p_topic_idx
    mov     x1, x0
    mov     x0, x19
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    mov     x10, #(PTF_REQUESTS_PARTIAL | PTF_SUPPORTS_PARTIAL)
    bic     x11, x9, x10
    orr     x11, x11, x26, lsl #3
    orr     x11, x11, #PTF_SUBSCRIBED
    str     x11, [x0, #PT_FLAGS]
    tst     x9, #PTF_SUBSCRIBED
    b.ne    9f
    ldr     x9, [x25, #T_PEERS]
    add     x9, x9, #1
    str     x9, [x25, #T_PEERS]
    mov     x0, x19
    mov     x1, x25
    mov     x2, #1
    bl      libp2p_peer_topic
    b       9f
5:  mov     x0, x23                         /* unsubscribe */
    mov     x1, x24
    bl      libp2p_topic_find
    cbz     x0, 9f
    mov     x25, x0
    bl      libp2p_topic_idx
    mov     x26, x0
    mov     x1, x0
    mov     x0, x19
    bl      libp2p_pt
    mov     x23, x0
    ldr     x9, [x23, #PT_FLAGS]
    tst     x9, #PTF_SUBSCRIBED
    b.eq    9f
    tst     x9, #PTF_MESH
    b.eq    6f
    mov     x0, x19
    mov     x1, x26
    bl      libp2p_mesh_remove
6:  ldr     x9, [x23, #PT_FLAGS]
    tst     x9, #PTF_FANOUT
    b.eq    7f
    ldr     x10, [x25, #T_FANOUT]
    sub     x10, x10, #1
    str     x10, [x25, #T_FANOUT]
7:  mov     x10, #(PTF_SUBSCRIBED | PTF_FANOUT | PTF_REQUESTS_PARTIAL | PTF_SUPPORTS_PARTIAL)
    bic     x9, x9, x10
    str     x9, [x23, #PT_FLAGS]
    ldr     x9, [x25, #T_PEERS]
    sub     x9, x9, #1
    str     x9, [x25, #T_PEERS]
    mov     x0, x19
    mov     x1, x25
    mov     x2, #0
    bl      libp2p_peer_topic
    mov     x0, x25
    bl      libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_rpc_sub

/*
 * libp2p_rpc_msg(peer index, p, n): one published Message. Only data (2) and
 * topic (4) may be there (StrictNoSign); from, seqno, signature or key, or
 * data above max_data, count as an invalid message of the peer. A message
 * of a topic we do not subscribe to is dropped. Otherwise it waits in a
 * pending slot, with MESSAGE, for its ID.
 * x19 peer index, x20 p, x21 end, x22 data, x23 data length, x24 topic
 * name, x25 its length, x26 1 when a signing field is there.
 */
LOCAL_FUNCTION libp2p_rpc_msg
    ENTER   16
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x22, #0
    mov     x23, #0
    mov     x24, #0
    mov     x26, #0
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    2f
    mov     x20, x5
    cmp     x1, #2
    b.ne    11f
    mov     x22, x3
    mov     x23, x4
    b       1b
11: cmp     x1, #4
    b.ne    12f
    mov     x24, x3
    mov     x25, x4
    b       1b
12: cmp     x1, #6
    b.hi    1b
    mov     x26, #1                         /* from, seqno, signature or key */
    b       1b
2:  cmn     x0, #1
    b.eq    9f
    cbz     x24, 9f
    mov     x0, x24
    mov     x1, x25
    bl      libp2p_topic_find
    cbz     x0, 9f
    ldr     x9, [x0, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    9f
    mov     x20, x0
    bl      libp2p_topic_idx
    mov     x21, x0
    CFG     x9, LIBP2P_CFG_MAX_DATA
    cmp     x23, x9
    cset    x9, hi
    orr     x26, x26, x9
    cbz     x26, 3f
    mov     x0, x19                         /* invalid */
    mov     x1, x21
    bl      libp2p_score_invalid
    b       9f
3:  mov     x0, #ST_PEND_OFF
    mov     x1, #ST_PEND_COUNT
    mov     x2, #PD_SIZE
    bl      libp2p_alloc_slot
    cbz     x0, 9f
    mov     x24, x0
    mov     x0, x23
    bl      libp2p_heap_alloc
    cbz     x0, 8f
    str     x0, [x24, #PD_DATA]
    add     x0, x27, x0
    mov     x1, x22
    mov     x2, x23
    bl      libp2p_copy
    str     x19, [x24, #PD_PEER]
    str     x21, [x24, #PD_TOPIC]
    str     x23, [x24, #PD_DATA_LEN]
    ldr     x9, [x28, #SC_NOW]
    str     x9, [x24, #PD_TIME]
    mov     w9, #PDS_WAIT_ID
    str     w9, [x24, #PD_STATE]
    ldr     x9, [x20, #T_LEN]               /* MESSAGE */
    add     x1, x9, #(LIBP2P_ACT_MSG_TOPIC + 7)
    and     x1, x1, #~7
    mov     x0, #LIBP2P_ACTION_MESSAGE
    bl      libp2p_action
    cbz     x0, 8f
    mov     x25, x0
    mov     x0, #ST_PEND_OFF
    mov     x1, #PD_SIZE
    mov     x2, x24
    bl      libp2p_handle
    str     x0, [x25, #LIBP2P_ACT_HANDLE]
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x2, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x25, #LIBP2P_ACT_MSG_PEER]
    ldr     x9, [x24, #PD_DATA]
    str     x9, [x25, #LIBP2P_ACT_MSG_DATA_OFF]
    str     x23, [x25, #LIBP2P_ACT_MSG_DATA_LEN]
    ldr     x2, [x20, #T_LEN]
    str     x2, [x25, #LIBP2P_ACT_MSG_TOPIC_LEN]
    add     x0, x25, #LIBP2P_ACT_MSG_TOPIC
    add     x1, x20, #T_NAME
    bl      libp2p_copy
    b       9f
8:  mov     x0, x24
    bl      libp2p_pend_free
9:  LEAVE   16
END_FUNCTION libp2p_rpc_msg

/* libp2p_rpc_control(peer index, p, n): a ControlMessage: ihave (1), iwant (2), graft (3), prune (4), idontwant (5), extensions (6). */
LOCAL_FUNCTION libp2p_rpc_control
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    9f
    mov     x20, x5
    cmp     x2, #2
    b.ne    1b
    mov     x0, x19
    mov     x9, x1
    mov     x1, x3
    mov     x2, x4
    cmp     x9, #1
    b.ne    2f
    bl      libp2p_ctl_ihave
    b       1b
2:  cmp     x9, #2
    b.ne    3f
    bl      libp2p_ctl_iwant
    b       1b
3:  cmp     x9, #3
    b.ne    4f
    bl      libp2p_ctl_graft
    b       1b
4:  cmp     x9, #4
    b.ne    5f
    bl      libp2p_ctl_prune
    b       1b
5:  cmp     x9, #5
    b.ne    6f
    bl      libp2p_ctl_idontwant
    b       1b
6:  cmp     x9, #6
    b.ne    1b
    bl      libp2p_ctl_extensions
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_rpc_control

/*
 * libp2p_ctl_extensions(peer index, p, n): the Extensions control message of
 * a peer. Only its first RPC on the stream may hold one, once; another costs
 * a behaviour penalty. partialMessages (field 10) set marks the peer.
 * x19 peer index, x20 p, x21 end, x22 peer, x23 partialMessages.
 */
LOCAL_FUNCTION libp2p_ctl_extensions
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x22, x0
    ldr     x9, [x22, #P_FLAGS]
    tst     x9, #(PF_EXT_SEEN | PF_EXT_GOT)
    b.eq    1f
    mov     x0, x22                         /* not the first: a protocol violation */
    mov     x1, #1
    bl      libp2p_behaviour_penalty
    b       9f
1:  orr     x9, x9, #PF_EXT_GOT
    str     x9, [x22, #P_FLAGS]
    mov     x23, #0
2:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    3f
    mov     x20, x5
    cmp     x1, #10
    b.ne    2b
    cbnz    x2, 2b
    cmp     x3, #0
    cset    x23, ne
    b       2b
3:  cbz     x23, 9f
    ldr     x9, [x22, #P_FLAGS]
    orr     x9, x9, #PF_PARTIAL
    str     x9, [x22, #P_FLAGS]
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
 * x19 peer index, x20 p, x21 end, x22 topic, x23 topic length, x24 group,
 * x25 group length, x26 action. sp + 96: metadata, then message (address
 * and length each); sp + 128: the peer's flags; sp + 136: our topic flags.
 */
LOCAL_FUNCTION libp2p_rpc_partial
    ENTER   48
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x22, #0
    mov     x24, #0
    mov     x26, #0
    stp     xzr, xzr, [sp, #96]
    stp     xzr, xzr, [sp, #112]
    CFG     x9, LIBP2P_CFG_PARTIAL_MESSAGES
    cbz     x9, 9f
    mov     x0, x19
    bl      libp2p_peer_at
    ldr     x9, [x0, #P_FLAGS]
    tst     x9, #PF_PARTIAL
    b.eq    9f
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    2f
    mov     x20, x5
    cmp     x2, #2
    b.ne    1b
    cmp     x1, #1
    b.ne    11f
    mov     x22, x3
    mov     x23, x4
    b       1b
11: cmp     x1, #2
    b.ne    12f
    mov     x24, x3
    mov     x25, x4
    b       1b
12: cmp     x1, #3
    b.ne    13f
    stp     x3, x4, [sp, #112]              /* the message */
    b       1b
13: cmp     x1, #4
    b.ne    1b
    stp     x3, x4, [sp, #96]               /* the metadata */
    b       1b
2:  cmn     x0, #1
    b.eq    9f
    cbz     x22, 9f
    cbz     x24, 9f
    sub     x9, x23, #1                     /* 1 to LIBP2P_MAX_TOPIC bytes */
    cmp     x9, #(LIBP2P_MAX_TOPIC - 1)
    b.hi    9f
    stp     xzr, xzr, [sp, #128]            /* the peer's flags, our topic flags */
    mov     x0, x22
    mov     x1, x23
    bl      libp2p_topic_find
    cbz     x0, 21f
    ldr     x9, [x0, #T_FLAGS]
    str     x9, [sp, #136]
    bl      libp2p_topic_idx
    mov     x1, x0
    mov     x0, x19
    bl      libp2p_partial_flags
    str     x0, [sp, #128]
    ldr     x9, [sp, #136]                  /* a message: only on a topic we want them on */
    tst     x9, #TF_REQUESTS_PARTIAL
    b.ne    3f
21: stp     xzr, xzr, [sp, #112]
3:  ldr     x9, [sp, #104]
    ldr     x10, [sp, #120]
    orr     x9, x9, x10
    cbz     x9, 9f                          /* nothing to give */
    add     x1, x23, #(LIBP2P_ACT_PM_TOPIC + 7)
    and     x1, x1, #~7
    mov     x0, #LIBP2P_ACTION_PARTIAL
    bl      libp2p_action
    cbz     x0, 9f
    mov     x26, x0
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x2, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x26, #LIBP2P_ACT_PM_PEER]
    ldr     x9, [sp, #128]
    str     x9, [x26, #LIBP2P_ACT_PM_FLAGS]
    str     x23, [x26, #LIBP2P_ACT_PM_TOPIC_LEN]
    sub     x9, x24, x27                    /* offsets from the start of the state */
    str     x9, [x26, #LIBP2P_ACT_PM_GROUP_OFF]
    str     x25, [x26, #LIBP2P_ACT_PM_GROUP_LEN]
    ldp     x9, x10, [sp, #96]
    sub     x9, x9, x27
    cmp     x10, #0
    csel    x9, xzr, x9, eq
    str     x9, [x26, #LIBP2P_ACT_PM_META_OFF]
    str     x10, [x26, #LIBP2P_ACT_PM_META_LEN]
    ldp     x9, x10, [sp, #112]
    sub     x9, x9, x27
    cmp     x10, #0
    csel    x9, xzr, x9, eq
    str     x9, [x26, #LIBP2P_ACT_PM_MSG_OFF]
    str     x10, [x26, #LIBP2P_ACT_PM_MSG_LEN]
    add     x0, x26, #LIBP2P_ACT_PM_TOPIC
    mov     x1, x22
    mov     x2, x23
    bl      libp2p_copy
    mov     x26, #1
9:  mov     x0, x26
    LEAVE   48
END_FUNCTION libp2p_rpc_partial

/* libp2p_backoff_secs(ms) -> whole seconds, rounded up. A leaf. */
LOCAL_FUNCTION libp2p_backoff_secs
    UNWIND_END_PROLOGUE
    add     x0, x0, #999
    mov     x1, #1000
    udiv    x0, x0, x1
    ret
END_FUNCTION libp2p_backoff_secs

/*
 * libp2p_prune_to(peer index, topic index, backoff ms): PRUNE to the peer with
 * the backoff, and no GRAFT of it before then.
 */
LOCAL_FUNCTION libp2p_prune_to
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    bl      libp2p_pt
    ldr     x9, [x28, #SC_NOW]
    add     x9, x9, x21
    ldr     x10, [x0, #PT_BACKOFF]
    cmp     x10, x9
    csel    x9, x10, x9, hi
    str     x9, [x0, #PT_BACKOFF]
    mov     x0, x21
    bl      libp2p_backoff_secs
    mov     x22, x0
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x23, x0
    mov     x0, x20
    bl      libp2p_topic_at
    mov     x1, x0
    mov     x0, x23
    mov     x2, x22
    bl      libp2p_gs_send_prune
    LEAVE   0
END_FUNCTION libp2p_prune_to

/*
 * libp2p_ctl_graft(peer index, p, n): a GRAFT. Ignored for a topic we do not
 * subscribe to or a peer already in the mesh. Within a backoff it costs a
 * behaviour penalty (two within graft_flood of the PRUNE) and gets PRUNE;
 * a negative score, or a full mesh and an inbound peer, also get PRUNE.
 * Otherwise the peer joins the mesh.
 * x19 peer index, x20 topic, x21 topic index, x22 entry, x23 now.
 */
LOCAL_FUNCTION libp2p_ctl_graft
    ENTER   0
    mov     x19, x0
    add     x1, x1, x2
    mov     x9, x1
    sub     x1, x9, x2
    mov     x0, x1
    mov     x1, x9
    mov     x2, #1
    bl      libp2p_field_bytes
    cbz     x0, 9f
    bl      libp2p_topic_find
    cbz     x0, 9f
    mov     x20, x0
    ldr     x9, [x20, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    9f
    bl      libp2p_topic_idx
    mov     x21, x0
    mov     x0, x19
    mov     x1, x21
    bl      libp2p_pt
    mov     x22, x0
    ldr     x9, [x22, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.ne    9f
    ldr     x23, [x28, #SC_NOW]
    ldr     x9, [x22, #PT_BACKOFF]
    cmp     x23, x9
    b.hs    2f
    mov     x0, x19                         /* within the backoff */
    bl      libp2p_peer_at
    mov     x24, x0
    mov     x1, #1
    bl      libp2p_behaviour_penalty
    ldr     x9, [x22, #PT_BACKOFF]
    CFG     x10, LIBP2P_CFG_PRUNE_BACKOFF_MS
    sub     x9, x9, x10
    CFG     x10, LIBP2P_CFG_GRAFT_FLOOD_MS
    add     x9, x9, x10
    cmp     x23, x9
    b.hs    8f
    mov     x0, x24
    mov     x1, #1
    bl      libp2p_behaviour_penalty
    b       8f
2:  mov     x0, x19
    bl      libp2p_peer_at
    mov     x24, x0
    bl      libp2p_score
    fcmp    d0, #0.0
    b.mi    8f
    ldr     x9, [x20, #T_MESH]
    CFG     x10, LIBP2P_CFG_D_HIGH
    cmp     x9, x10
    b.lo    3f
    ldr     x9, [x24, #P_FLAGS]
    tst     x9, #PF_OUTBOUND
    b.eq    8f
3:  mov     x0, x19
    mov     x1, x21
    bl      libp2p_mesh_add
    b       9f
8:  mov     x0, x19
    mov     x1, x21
    CFG     x2, LIBP2P_CFG_PRUNE_BACKOFF_MS
    bl      libp2p_prune_to
9:  LEAVE   0
END_FUNCTION libp2p_ctl_graft

/*
 * libp2p_ctl_prune(peer index, p, n): a PRUNE: the peer leaves our mesh of the
 * topic, and we do not GRAFT it again for its backoff (in seconds) or
 * prune_backoff. Exchanged peers are not used.
 * x19 peer index, x20 p, x21 end, x22 topic name, x23 length, x24 backoff ms.
 */
LOCAL_FUNCTION libp2p_ctl_prune
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x22, #0
    CFG     x24, LIBP2P_CFG_PRUNE_BACKOFF_MS
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    2f
    mov     x20, x5
    cmp     x1, #1
    b.ne    11f
    cmp     x2, #2
    b.ne    1b
    mov     x22, x3
    mov     x23, x4
    b       1b
11: cmp     x1, #3
    b.ne    1b
    cmp     x2, #0
    b.ne    1b
    MOV64   x9, 86400                       /* at most a day */
    cmp     x3, x9
    csel    x3, x3, x9, lo
    mov     x9, #1000
    mul     x24, x3, x9
    b       1b
2:  cbz     x22, 9f
    mov     x0, x22
    mov     x1, x23
    bl      libp2p_topic_find
    cbz     x0, 9f
    bl      libp2p_topic_idx
    mov     x21, x0
    mov     x0, x19
    mov     x1, x21
    bl      libp2p_pt
    mov     x20, x0
    ldr     x9, [x20, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    3f
    mov     x0, x19
    mov     x1, x21
    bl      libp2p_mesh_remove
3:  ldr     x9, [x28, #SC_NOW]
    add     x9, x9, x24
    ldr     x10, [x20, #PT_BACKOFF]
    cmp     x10, x9
    csel    x9, x10, x9, hi
    str     x9, [x20, #PT_BACKOFF]
9:  LEAVE   0
END_FUNCTION libp2p_ctl_prune

/*
 * libp2p_ctl_ihave(peer index, p, n): an IHAVE. Heard only from a peer at or
 * above gossip_threshold, at most max_ihave_messages times and
 * max_ihave_length IDs in a heartbeat, for a topic we subscribe to. The IDs
 * not seen go back as one IWANT, and one of them, at random, becomes a
 * promise.
 * x19 peer index, x20 p, x21 end, x22 peer, x23 list, x24 count, x25 room.
 */
LOCAL_FUNCTION libp2p_ctl_ihave
    ENTER   16
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x22, x0
    bl      libp2p_score
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)]
    fcmp    d0, d1
    b.mi    9f
    ldr     x9, [x22, #P_IHAVE_COUNT]
    add     x9, x9, #1
    str     x9, [x22, #P_IHAVE_COUNT]
    CFG     x10, LIBP2P_CFG_MAX_IHAVE_MESSAGES
    cmp     x9, x10
    b.hi    9f
    CFG     x25, LIBP2P_CFG_MAX_IHAVE_LENGTH
    ldr     x9, [x22, #P_IHAVE_IDS]
    subs    x25, x25, x9
    b.ls    9f
    mov     x0, x20
    mov     x1, x21
    mov     x2, #1
    bl      libp2p_field_bytes
    cbz     x0, 9f
    bl      libp2p_topic_find
    cbz     x0, 9f
    mov     x26, x0
    ldr     x9, [x26, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    9f
    SCR     x23, SC_IDS
    mov     x24, #0
1:  cmp     x24, x25
    b.hs    3f
    MOV64   x9, (SC_IDS_SIZE / 16)
    cmp     x24, x9
    b.hs    3f
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    3f
    mov     x20, x5
    cmp     x1, #2
    b.ne    1b
    cmp     x2, #2
    b.ne    1b
    cbz     x4, 1b
    cmp     x4, #LIBP2P_MAX_MSG_ID
    b.hi    1b
    stp     x3, x4, [sp, #96]
    mov     x0, x3
    mov     x1, x4
    bl      libp2p_seen_find
    ldp     x3, x4, [sp, #96]
    cbnz    x0, 1b
    add     x9, x23, x24, lsl #4
    stp     x3, x4, [x9]
    add     x24, x24, #1
    b       1b
3:  cbz     x24, 9f
    ldr     x9, [x22, #P_IHAVE_IDS]
    add     x9, x9, x24
    str     x9, [x22, #P_IHAVE_IDS]
    mov     x0, x22
    mov     x1, x26
    mov     x2, x23
    mov     x3, x24
    mov     x4, #2
    bl      libp2p_gs_send_ids
    mov     x0, x24
    bl      libp2p_random_below
    add     x9, x23, x0, lsl #4
    ldp     x1, x2, [x9]
    mov     x0, x19
    bl      libp2p_promise_add
9:  LEAVE   16
END_FUNCTION libp2p_ctl_ihave

/*
 * libp2p_ctl_iwant(peer index, p, n): an IWANT from a peer at or above
 * gossip_threshold: each message still in the cache goes to it, at most
 * retransmission times, unless the peer sent IDONTWANT for it.
 * x19 peer index, x20 p, x21 end, x22 peer.
 */
LOCAL_FUNCTION libp2p_ctl_iwant
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x22, x0
    bl      libp2p_score
    ldr     d1, [x27, #(ST_CONFIG + LIBP2P_CFG_GOSSIP_THRESHOLD)]
    fcmp    d0, d1
    b.mi    9f
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    9f
    mov     x20, x5
    cmp     x1, #1
    b.ne    1b
    cmp     x2, #2
    b.ne    1b
    mov     x0, x3
    mov     x1, x4
    bl      libp2p_mc_find
    cbz     x0, 1b
    mov     x23, x0
    mov     x0, x19
    add     x1, x23, #MC_ID
    ldr     x2, [x23, #MC_ID_LEN]
    bl      libp2p_dontwant
    cbnz    x0, 1b
    mov     x0, x23
    mov     x1, x19
    bl      libp2p_mc_sent
    cbz     x0, 1b
    ldr     x0, [x23, #MC_TOPIC]
    bl      libp2p_topic_at
    mov     x1, x0
    mov     x0, x22
    ldr     x2, [x23, #MC_DATA]
    add     x2, x27, x2
    ldr     x3, [x23, #MC_DATA_LEN]
    bl      libp2p_gs_send_msg
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_ctl_iwant

/*
 * libp2p_ctl_idontwant(peer index, p, n): an IDONTWANT of a peer: up to
 * max_idontwant_length of its message IDs (1 to LIBP2P_MAX_MSG_ID bytes)
 * go in the peer's ring with the heartbeat number, each over the oldest.
 * With no slots, or past max_idontwant_messages in this heartbeat, it is
 * not heard.
 * x19 peer index, x20 p, x21 end, x22 peer, x23 IDs left, x24 ring,
 * x25 slots, x26 entry.
 */
LOCAL_FUNCTION libp2p_ctl_idontwant
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    add     x21, x1, x2
    CFG     x25, LIBP2P_CFG_DONTWANT_SLOTS
    cbz     x25, 9f
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x22, x0
    ldr     x9, [x22, #P_DW_COUNT]
    CFG     x10, LIBP2P_CFG_MAX_IDONTWANT_MESSAGES
    cmp     x9, x10
    b.hs    9f
    add     x9, x9, #1
    str     x9, [x22, #P_DW_COUNT]
    CFG     x23, LIBP2P_CFG_MAX_IDONTWANT_LENGTH
    mov     x0, x19
    bl      libp2p_dw_ring
    mov     x24, x0
1:  cbz     x23, 9f
    mov     x0, x20
    mov     x1, x21
    bl      libp2p_pb_next
    cmp     x0, #1
    b.ne    9f
    mov     x20, x5
    cmp     x1, #1
    b.ne    1b
    cmp     x2, #2
    b.ne    1b
    sub     x23, x23, #1
    sub     x9, x4, #1                      /* 1 to LIBP2P_MAX_MSG_ID bytes */
    cmp     x9, #(LIBP2P_MAX_MSG_ID - 1)
    b.hi    1b
    ldr     x10, [x22, #P_DW_HEAD]
    mov     x11, #DW_SIZE
    madd    x26, x10, x11, x24
    add     x10, x10, #1
    cmp     x10, x25
    csel    x10, xzr, x10, hs
    str     x10, [x22, #P_DW_HEAD]
    ldr     x9, [x27, #ST_HEARTBEATS]
    str     x9, [x26, #DW_HB]
    str     x4, [x26, #DW_ID_LEN]
    add     x0, x26, #DW_ID
    mov     x1, x3
    mov     x2, x4
    bl      libp2p_copy
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_ctl_idontwant

/* ---------------------------------------------------------------- Mesh */

/* libp2p_mesh_add(peer index, topic index): the peer joins our mesh of the topic, with GRAFT. */
LOCAL_FUNCTION libp2p_mesh_add
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    orr     x9, x9, #PTF_MESH
    str     x9, [x0, #PT_FLAGS]
    ldr     x9, [x28, #SC_NOW]
    str     x9, [x0, #PT_GRAFT_TIME]
    mov     x0, x20
    bl      libp2p_topic_at
    mov     x21, x0
    ldr     x9, [x21, #T_MESH]
    add     x9, x9, #1
    str     x9, [x21, #T_MESH]
    mov     x0, x19
    bl      libp2p_peer_at
    mov     x1, x21
    bl      libp2p_gs_send_graft
    LEAVE   0
END_FUNCTION libp2p_mesh_add

/* libp2p_mesh_remove(peer index, topic index): the peer leaves our mesh of the topic, with the mesh failure penalty. */
LOCAL_FUNCTION libp2p_mesh_remove
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    bl      libp2p_score_mesh_leave
    mov     x0, x19
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    and     x9, x9, #~PTF_MESH
    str     x9, [x0, #PT_FLAGS]
    mov     x0, x20
    bl      libp2p_topic_at
    ldr     x9, [x0, #T_MESH]
    sub     x9, x9, #1
    str     x9, [x0, #T_MESH]
    LEAVE   0
END_FUNCTION libp2p_mesh_remove

/*
 * libp2p_candidates(topic index, need flags, refuse flags, floor) -> the count
 * of peers in the list at SC_LIST (u32 peer indexes): gossipsub peers
 * subscribed to the topic whose entry has every need flag and no refuse
 * flag, whose score is at or above floor (d0), and, when the backoff bit
 * of refuse is set, outside a backoff.
 * x19 topic index, x20 need, x21 refuse, x22 peer index, x23 count, x24 list.
 */
.set CAND_BACKOFF, 0x100
.set CAND_OUTBOUND, 0x200               /* need: outbound peers only */
LOCAL_FUNCTION libp2p_candidates
    ENTER   16
    str     d0, [sp, #96]
    mov     x19, x0
    orr     x20, x1, #PTF_SUBSCRIBED
    mov     x21, x2
    mov     x22, #0
    mov     x23, #0
    SCR     x24, SC_LIST
1:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x22, x9
    b.hs    9f
    mov     x0, x22
    bl      libp2p_peer_at
    mov     x25, x0
    bl      libp2p_gs_ready
    cbz     x0, 2f
    ldr     d0, [x25, #P_SCORE]
    ldr     d1, [sp, #96]
    fcmp    d0, d1
    b.mi    2f
    tst     x20, #CAND_OUTBOUND
    b.eq    11f
    ldr     x9, [x25, #P_FLAGS]
    tst     x9, #PF_OUTBOUND
    b.eq    2f
11: mov     x0, x22
    mov     x1, x19
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    and     x10, x20, #0xFF
    and     x11, x9, x10
    cmp     x11, x10
    b.ne    2f
    and     x10, x21, #0xFF
    tst     x9, x10
    b.ne    2f
    tst     x21, #CAND_BACKOFF
    b.eq    12f
    ldr     x9, [x0, #PT_BACKOFF]
    ldr     x10, [x28, #SC_NOW]
    cmp     x10, x9
    b.lo    2f
12: str     w22, [x24, x23, lsl #2]
    add     x23, x23, #1
2:  add     x22, x22, #1
    b       1b
9:  mov     x0, x23
    LEAVE   16
END_FUNCTION libp2p_candidates

/* libp2p_shuffle(list, count): a random order of the u32 values (Fisher-Yates). */
LOCAL_FUNCTION libp2p_shuffle
    ENTER   0
    mov     x19, x0
    mov     x20, x1
1:  cmp     x20, #1
    b.ls    9f
    mov     x0, x20
    bl      libp2p_random_below
    sub     x20, x20, #1
    ldr     w9, [x19, x0, lsl #2]
    ldr     w10, [x19, x20, lsl #2]
    str     w10, [x19, x0, lsl #2]
    str     w9, [x19, x20, lsl #2]
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_shuffle

/* ---------------------------------------------------------------- Application events */

/* libp2p_on_subscribe(event): SUBSCRIBE: libp2p_subscribe, the partial flags kept. */
LOCAL_FUNCTION libp2p_on_subscribe
    ENTER   0
    add     x0, x0, #LIBP2P_EV_TOPIC
    ldr     x1, [x0, #(LIBP2P_EV_TOPIC_LEN - LIBP2P_EV_TOPIC)]
    mov     x2, #NONE
    bl      libp2p_subscribe
    LEAVE   0
END_FUNCTION libp2p_on_subscribe

/* libp2p_on_partial_subscribe(event): PARTIAL_SUBSCRIBE: libp2p_subscribe with its flags. */
LOCAL_FUNCTION libp2p_on_partial_subscribe
    ENTER   0
    mov     x9, x0
    add     x0, x9, #LIBP2P_EV_PS_TOPIC
    ldr     x1, [x9, #LIBP2P_EV_PS_TOPIC_LEN]
    ldr     x2, [x9, #LIBP2P_EV_PS_FLAGS]
    bl      libp2p_subscribe
    LEAVE   0
END_FUNCTION libp2p_on_partial_subscribe

/*
 * libp2p_subscribe(name, n, flags): we join a topic. flags (LIBP2P_PARTIAL_*,
 * REQUESTS implying SUPPORTS) become our partial flags of it, or NONE keeps
 * them. A topic we subscribe to already: when its flags change, every
 * gossipsub peer hears the new SubOpts. Else our fanout peers of it, then
 * other subscribed peers at random, fill the mesh up to D (score 0 or
 * more, outside backoff), each with GRAFT; every gossipsub peer hears of it.
 * x19 topic, x20 topic index, x21 mesh count, x22 list, x23 count, x24 i,
 * x25 flags.
 */
LOCAL_FUNCTION libp2p_subscribe
    ENTER   0
    mov     x25, x2
    bl      libp2p_topic_get
    cbz     x0, 9f
    mov     x19, x0
    ldr     x9, [x19, #T_FLAGS]
    cmn     x25, #1
    b.eq    11f
    tst     x25, #LIBP2P_PARTIAL_REQUESTS
    b.eq    10f
    orr     x25, x25, #LIBP2P_PARTIAL_SUPPORTS
10: mov     x10, #(TF_REQUESTS_PARTIAL | TF_SUPPORTS_PARTIAL)
    bic     x11, x9, x10
    orr     x11, x11, x25, lsl #2
    str     x11, [x19, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    12f
    cmp     x11, x9
    b.eq    9f
    mov     x0, x19                         /* new flags: the peers hear them */
    mov     x1, #1
    bl      libp2p_gs_announce
    b       9f
11: tst     x9, #TF_SUBSCRIBED
    b.ne    9f
12: ldr     x9, [x19, #T_FLAGS]
    orr     x9, x9, #TF_SUBSCRIBED
    str     x9, [x19, #T_FLAGS]
    mov     x0, x19
    bl      libp2p_topic_idx
    mov     x20, x0
    bl      libp2p_score_all
    mov     x21, #0
    fmov    d0, xzr                         /* fanout peers first */
    mov     x0, x20
    mov     x1, #PTF_FANOUT
    mov     x2, #CAND_BACKOFF
    bl      libp2p_candidates
    mov     x23, x0
    SCR     x22, SC_LIST
    mov     x24, #0
1:  cmp     x24, x23
    b.hs    3f
    ldr     w0, [x22, x24, lsl #2]
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    and     x9, x9, #~PTF_FANOUT
    str     x9, [x0, #PT_FLAGS]
    ldr     x9, [x19, #T_FANOUT]
    sub     x9, x9, #1
    str     x9, [x19, #T_FANOUT]
    CFG     x9, LIBP2P_CFG_D
    cmp     x21, x9
    b.hs    2f
    ldr     w0, [x22, x24, lsl #2]
    mov     x1, x20
    bl      libp2p_mesh_add
    add     x21, x21, #1
2:  add     x24, x24, #1
    b       1b
3:  bl      libp2p_fanout_clear_topic
    CFG     x9, LIBP2P_CFG_D
    cmp     x21, x9
    b.hs    5f
    fmov    d0, xzr
    mov     x0, x20
    mov     x1, #0
    mov     x2, #(PTF_MESH | CAND_BACKOFF)
    bl      libp2p_candidates
    mov     x23, x0
    mov     x0, x22
    mov     x1, x23
    bl      libp2p_shuffle
    mov     x24, #0
4:  cmp     x24, x23
    b.hs    5f
    CFG     x9, LIBP2P_CFG_D
    cmp     x21, x9
    b.hs    5f
    ldr     w0, [x22, x24, lsl #2]
    mov     x1, x20
    bl      libp2p_mesh_add
    add     x21, x21, #1
    add     x24, x24, #1
    b       4b
5:  mov     x0, x19
    mov     x1, #1
    bl      libp2p_gs_announce
9:  LEAVE   0
END_FUNCTION libp2p_subscribe

/* libp2p_fanout_clear_topic(): (x19 topic, x20 index) no peer stays in its fanout. */
LOCAL_FUNCTION libp2p_fanout_clear_topic
    ENTER   0
    mov     x21, #0
1:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x21, x9
    b.hs    9f
    mov     x0, x21
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    tst     x9, #PTF_FANOUT
    b.eq    2f
    and     x9, x9, #~PTF_FANOUT
    str     x9, [x0, #PT_FLAGS]
    ldr     x9, [x19, #T_FANOUT]
    sub     x9, x9, #1
    str     x9, [x19, #T_FANOUT]
2:  add     x21, x21, #1
    b       1b
9:  LEAVE   0
END_FUNCTION libp2p_fanout_clear_topic

/*
 * libp2p_on_unsubscribe(event): we leave a topic, and our partial flags of it
 * end: every mesh peer gets PRUNE with unsubscribe_backoff and leaves the
 * mesh; every gossipsub peer hears of it.
 */
LOCAL_FUNCTION libp2p_on_unsubscribe
    ENTER   0
    add     x0, x0, #LIBP2P_EV_TOPIC
    ldr     x1, [x0, #(LIBP2P_EV_TOPIC_LEN - LIBP2P_EV_TOPIC)]
    bl      libp2p_topic_find
    cbz     x0, 9f
    mov     x19, x0
    ldr     x9, [x19, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    9f
    mov     x10, #(TF_SUBSCRIBED | TF_REQUESTS_PARTIAL | TF_SUPPORTS_PARTIAL)
    bic     x9, x9, x10
    str     x9, [x19, #T_FLAGS]
    bl      libp2p_topic_idx
    mov     x20, x0
    mov     x21, #0
1:  ldr     x9, [x27, #ST_PEER_COUNT]
    cmp     x21, x9
    b.hs    3f
    mov     x0, x21
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    tst     x9, #PTF_MESH
    b.eq    2f
    mov     x0, x21
    mov     x1, x20
    CFG     x2, LIBP2P_CFG_UNSUB_BACKOFF_MS
    bl      libp2p_prune_to
    mov     x0, x21
    mov     x1, x20
    bl      libp2p_mesh_remove
2:  add     x21, x21, #1
    b       1b
3:  mov     x0, x19
    mov     x1, #0
    bl      libp2p_gs_announce
    mov     x0, x19
    bl      libp2p_topic_tidy
9:  LEAVE   0
END_FUNCTION libp2p_on_unsubscribe

/*
 * libp2p_on_publish(event): our own message. Already seen: not sent. Else it is
 * seen (valid), cached, and sent: with flood_publish to every subscribed
 * peer at or above publish_threshold; else to the mesh, or to the fanout
 * of a topic we do not subscribe to (libp2p_fanout_list); never to a peer
 * that sent IDONTWANT for it or that gets partial messages of the topic
 * from us. PUBLISHED gives the number of peers.
 * x19 event, x20 topic, x21 topic index, x22 data block, x23 peers sent,
 * x24 list, x25 count.
 */
LOCAL_FUNCTION libp2p_on_publish
    ENTER   0
    mov     x19, x0
    mov     x23, #0
    add     x0, x19, #LIBP2P_EV_PUB_ID
    ldr     x1, [x19, #LIBP2P_EV_PUB_ID_LEN]
    bl      libp2p_seen_find
    cbnz    x0, 8f
    add     x0, x19, #LIBP2P_EV_PUB_TOPIC
    ldr     x1, [x19, #LIBP2P_EV_PUB_TOPIC_LEN]
    bl      libp2p_topic_get
    cbz     x0, 8f
    mov     x20, x0
    bl      libp2p_topic_idx
    mov     x21, x0
    ldr     x0, [x19, #LIBP2P_EV_PUB_DATA_LEN]
    bl      libp2p_heap_alloc
    cbz     x0, 8f
    mov     x22, x0
    ldr     x9, [x19, #LIBP2P_EV_PUB_TOPIC_LEN] /* the data follows the topic, at a multiple of 8 */
    add     x9, x9, #7
    and     x9, x9, #~7
    add     x1, x19, #LIBP2P_EV_PUB_TOPIC
    add     x1, x1, x9
    add     x0, x27, x22
    ldr     x2, [x19, #LIBP2P_EV_PUB_DATA_LEN]
    bl      libp2p_copy
    add     x0, x19, #LIBP2P_EV_PUB_ID
    ldr     x1, [x19, #LIBP2P_EV_PUB_ID_LEN]
    mov     x2, x21
    mov     x3, #SS_VALID
    bl      libp2p_seen_add
    add     x0, x19, #LIBP2P_EV_PUB_ID
    ldr     x1, [x19, #LIBP2P_EV_PUB_ID_LEN]
    mov     x2, x21
    mov     x3, x22
    ldr     x4, [x19, #LIBP2P_EV_PUB_DATA_LEN]
    bl      libp2p_mc_put
    bl      libp2p_score_all
    CFG     x9, LIBP2P_CFG_FLOOD_PUBLISH
    cbz     x9, 2f
    ldr     d0, [x27, #(ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)]
    mov     x0, x21
    mov     x1, #0
    mov     x2, #0
    bl      libp2p_candidates
    b       6f
2:  ldr     x9, [x20, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    3f
    mov     x9, #0xFFF0000000000000         /* the mesh, at any score: -infinity */
    fmov    d0, x9
    mov     x0, x21
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    b       6f
3:  mov     x0, x20                         /* the fanout */
    mov     x1, x21
    bl      libp2p_fanout_list
6:  mov     x25, x0                         /* send to the list */
    SCR     x24, SC_LIST
    mov     x26, #0
7:  cmp     x26, x25
    b.hs    8f
    ldr     w0, [x24, x26, lsl #2]
    mov     x1, x21
    bl      libp2p_wants_partial
    cbnz    x0, 71f
    ldr     w0, [x24, x26, lsl #2]
    add     x1, x19, #LIBP2P_EV_PUB_ID
    ldr     x2, [x19, #LIBP2P_EV_PUB_ID_LEN]
    bl      libp2p_dontwant
    cbnz    x0, 71f
    ldr     w0, [x24, x26, lsl #2]
    bl      libp2p_peer_at
    mov     x1, x20
    mov     x2, x22
    add     x2, x27, x2
    ldr     x3, [x19, #LIBP2P_EV_PUB_DATA_LEN]
    bl      libp2p_gs_send_msg
    add     x23, x23, x0
71: add     x26, x26, #1
    b       7b
8:  mov     x0, #LIBP2P_ACTION_PUBLISHED
    mov     x1, #LIBP2P_ACT_PUB_SIZE
    bl      libp2p_action
    cbz     x0, 9f
    mov     x24, x0
    ldr     x2, [x19, #LIBP2P_EV_PUB_ID_LEN]
    str     x2, [x24, #LIBP2P_ACT_PUB_ID_LEN]
    add     x0, x24, #LIBP2P_ACT_PUB_ID
    add     x1, x19, #LIBP2P_EV_PUB_ID
    bl      libp2p_copy
    str     x23, [x24, #LIBP2P_ACT_PUB_PEERS]
9:  LEAVE   0
END_FUNCTION libp2p_on_publish

/*
 * libp2p_fanout_list(topic, topic index) -> the count of the fanout peers of
 * a topic we do not subscribe to, in SC_LIST: an empty fanout is filled
 * first with up to D subscribed peers at or above publish_threshold, at
 * random. Our last publish to the topic is now.
 * x19 topic, x20 topic index, x21 list, x22 count, x23 i.
 */
LOCAL_FUNCTION libp2p_fanout_list
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x28, #SC_NOW]
    str     x9, [x19, #T_FANOUT_LAST]
    ldr     x9, [x19, #T_FANOUT]
    cbnz    x9, 5f
    ldr     d0, [x27, #(ST_CONFIG + LIBP2P_CFG_PUBLISH_THRESHOLD)]
    mov     x0, x20
    mov     x1, #0
    mov     x2, #0
    bl      libp2p_candidates
    mov     x22, x0
    SCR     x21, SC_LIST
    mov     x0, x21
    mov     x1, x22
    bl      libp2p_shuffle
    CFG     x9, LIBP2P_CFG_D
    cmp     x22, x9
    csel    x22, x22, x9, lo
    mov     x23, #0
4:  cmp     x23, x22
    b.hs    5f
    ldr     w0, [x21, x23, lsl #2]
    mov     x1, x20
    bl      libp2p_pt
    ldr     x9, [x0, #PT_FLAGS]
    orr     x9, x9, #PTF_FANOUT
    str     x9, [x0, #PT_FLAGS]
    ldr     x9, [x19, #T_FANOUT]
    add     x9, x9, #1
    str     x9, [x19, #T_FANOUT]
    add     x23, x23, #1
    b       4b
5:  mov     x9, #0xFFF0000000000000         /* the fanout, at any score: -infinity */
    fmov    d0, x9
    mov     x0, x20
    mov     x1, #PTF_FANOUT
    mov     x2, #0
    bl      libp2p_candidates
    LEAVE   0
END_FUNCTION libp2p_fanout_list

/*
 * libp2p_on_message_id(event): the ID of a message waiting for one. Seen
 * before: a duplicate (scores, promises), MESSAGE_STATUS duplicate, and
 * the slot is free. Else it is seen (pending), promises of it are kept,
 * IDONTWANT goes to the mesh at once, and MESSAGE_STATUS new asks for a
 * VALIDATION.
 * x19 event, x20 pending, x21 seen.
 */
LOCAL_FUNCTION libp2p_on_message_id
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_HANDLE]
    bl      libp2p_pend
    cbz     x0, 9f
    mov     x20, x0
    ldr     w9, [x20, #PD_STATE]
    cmp     w9, #PDS_WAIT_ID
    b.ne    9f
    ldr     x9, [x19, #LIBP2P_EV_MSG_ID_LEN]
    str     x9, [x20, #PD_ID_LEN]
    add     x0, x20, #PD_ID
    add     x1, x19, #LIBP2P_EV_MSG_ID
    mov     x2, x9
    bl      libp2p_copy
    add     x0, x20, #PD_ID
    ldr     x1, [x20, #PD_ID_LEN]
    bl      libp2p_promise_keep
    add     x0, x20, #PD_ID
    ldr     x1, [x20, #PD_ID_LEN]
    bl      libp2p_seen_find
    cbz     x0, 1f
    mov     x21, x0                         /* a duplicate */
    ldr     x0, [x20, #PD_PEER]
    mov     x1, x21
    bl      libp2p_score_duplicate
    mov     x0, x20
    mov     x1, #LIBP2P_MSG_DUPLICATE
    bl      libp2p_pend_status
    mov     x0, x20
    bl      libp2p_pend_free
    b       9f
1:  add     x0, x20, #PD_ID
    ldr     x1, [x20, #PD_ID_LEN]
    ldr     x2, [x20, #PD_TOPIC]
    mov     x3, #SS_PENDING
    bl      libp2p_seen_add
    TABLE   x9, ST_SEEN_OFF
    sub     x9, x0, x9
    mov     x10, #SN_SIZE
    udiv    x9, x9, x10
    str     x9, [x20, #PD_SEEN]
    mov     w9, #PDS_WAIT_VERDICT
    str     w9, [x20, #PD_STATE]
    mov     x0, x20
    bl      libp2p_gs_idontwant
    mov     x0, x20
    mov     x1, #LIBP2P_MSG_NEW
    bl      libp2p_pend_status
9:  LEAVE   0
END_FUNCTION libp2p_on_message_id

/*
 * libp2p_on_validation(event): the application judged a new message. ACCEPT:
 * seen valid, first-delivery and mesh-delivery scores, cached, and sent to
 * the mesh of the topic except the peers that already sent it, sent
 * IDONTWANT for it or get partial messages of the topic from us. REJECT:
 * seen invalid and an invalid message for those peers. IGNORE: seen
 * ignored. Then the slot is free.
 * x19 event, x20 pending, x21 seen, x22 result, x23 topic, x24 i, x25 list,
 * x26 count.
 */
LOCAL_FUNCTION libp2p_on_validation
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_HANDLE]
    bl      libp2p_pend
    cbz     x0, 9f
    mov     x20, x0
    ldr     w9, [x20, #PD_STATE]
    cmp     w9, #PDS_WAIT_VERDICT
    b.ne    9f
    ldr     x22, [x19, #LIBP2P_EV_RESULT]
    ldr     x9, [x20, #PD_SEEN]             /* the seen entry, if it is still that message */
    TABLE   x21, ST_SEEN_OFF
    mov     x10, #SN_SIZE
    madd    x21, x9, x10, x21
    add     x0, x21, #SN_ID
    ldr     x1, [x21, #SN_ID_LEN]
    add     x2, x20, #PD_ID
    ldr     x3, [x20, #PD_ID_LEN]
    bl      libp2p_compare
    cbnz    x0, 1f
    mov     x21, #0
1:  cmp     x22, #LIBP2P_ACCEPT
    b.ne    5f
    cbz     x21, 2f
    mov     x9, #SS_VALID
    str     x9, [x21, #SN_STATUS]
    ldr     x9, [x28, #SC_NOW]
    str     x9, [x21, #SN_VALIDATED]
2:  ldr     x0, [x20, #PD_PEER]
    ldr     x1, [x20, #PD_TOPIC]
    mov     x2, x21
    bl      libp2p_score_valid
    add     x0, x20, #PD_ID                 /* cached: the cache owns the data now */
    ldr     x1, [x20, #PD_ID_LEN]
    ldr     x2, [x20, #PD_TOPIC]
    ldr     x3, [x20, #PD_DATA]
    ldr     x4, [x20, #PD_DATA_LEN]
    bl      libp2p_mc_put
    ldr     x0, [x20, #PD_TOPIC]
    bl      libp2p_topic_at
    mov     x23, x0
    mov     x9, #0xFFF0000000000000
    fmov    d0, x9
    ldr     x0, [x20, #PD_TOPIC]
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    mov     x26, x0
    SCR     x25, SC_LIST
    mov     x24, #0
3:  cmp     x24, x26
    b.hs    4f
    ldr     w0, [x25, x24, lsl #2]
    ldr     x9, [x20, #PD_PEER]
    cmp     x0, x9
    b.eq    31f
    ldr     x1, [x20, #PD_TOPIC]
    bl      libp2p_wants_partial
    cbnz    x0, 31f
    ldr     w0, [x25, x24, lsl #2]
    mov     x1, x21
    bl      libp2p_seen_delivered
    cbnz    x0, 31f
    ldr     w0, [x25, x24, lsl #2]
    add     x1, x20, #PD_ID
    ldr     x2, [x20, #PD_ID_LEN]
    bl      libp2p_dontwant
    cbnz    x0, 31f
    ldr     w0, [x25, x24, lsl #2]
    bl      libp2p_peer_at
    mov     x1, x23
    ldr     x2, [x20, #PD_DATA]
    add     x2, x27, x2
    ldr     x3, [x20, #PD_DATA_LEN]
    bl      libp2p_gs_send_msg
31: add     x24, x24, #1
    b       3b
4:  str     xzr, [x20, #PD_DATA]
    b       8f
5:  cmp     x22, #LIBP2P_REJECT
    b.ne    6f
    cbz     x21, 51f
    mov     x9, #SS_INVALID
    str     x9, [x21, #SN_STATUS]
51: ldr     x0, [x20, #PD_PEER]
    ldr     x1, [x20, #PD_TOPIC]
    mov     x2, x21
    bl      libp2p_score_rejected
    b       8f
6:  cbz     x21, 8f
    mov     x9, #SS_IGNORED
    str     x9, [x21, #SN_STATUS]
8:  mov     x0, x20
    bl      libp2p_pend_free
9:  LEAVE   0
END_FUNCTION libp2p_on_validation

/* libp2p_seen_delivered(peer index, seen) -> 1 when the peer is a deliverer of the seen message, else 0. A leaf. */
LOCAL_FUNCTION libp2p_seen_delivered
    UNWIND_END_PROLOGUE
    cbz     x1, 8f
    ldr     w2, [x1, #SN_COUNT]
    add     x3, x1, #SN_PEERS
1:  cbz     x2, 8f
    ldrh    w4, [x3], #2
    cmp     x4, x0
    b.eq    7f
    sub     x2, x2, #1
    b       1b
7:  mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_seen_delivered

/* libp2p_on_app_score(event): the application-specific score of a peer (P5). */
LOCAL_FUNCTION libp2p_on_app_score
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_PEER]
    bl      libp2p_peer
    cbz     x0, 9f
    ldr     x9, [x19, #LIBP2P_EV_SCORE]
    str     x9, [x0, #P_APP_SCORE]
9:  LEAVE   0
END_FUNCTION libp2p_on_app_score

/* libp2p_on_topic_params(event): the score parameters of a topic. */
LOCAL_FUNCTION libp2p_on_topic_params
    ENTER   0
    mov     x19, x0
    add     x0, x19, #LIBP2P_EV_TP_TOPIC
    ldr     x1, [x19, #LIBP2P_EV_TP_TOPIC_LEN]
    bl      libp2p_topic_get
    cbz     x0, 9f
    mov     x20, x0
    add     x0, x20, #T_PARAMS
    add     x1, x19, #LIBP2P_EV_TP_PARAMS
    mov     x2, #LIBP2P_TP_SIZE
    bl      libp2p_copy
    ldr     x9, [x20, #T_FLAGS]
    orr     x9, x9, #TF_PARAMS
    str     x9, [x20, #T_FLAGS]
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
    CFG     x2, LIBP2P_CFG_PARTIAL_MESSAGES
    cbz     x2, 8f
    ldr     x2, [x27, #ST_PEER_OFF]
    add     x2, x27, x2
    mov     x3, #P_SIZE
    madd    x2, x0, x3, x2
    ldr     x2, [x2, #P_FLAGS]
    tst     x2, #PF_PARTIAL
    b.eq    8f
    ldr     x2, [x27, #ST_TOPIC_COUNT]
    madd    x0, x0, x2, x1
    ldr     x2, [x27, #ST_PT_OFF]
    add     x2, x27, x2
    mov     x3, #PT_SIZE
    madd    x0, x0, x3, x2
    ldr     x0, [x0, #PT_FLAGS]
    ubfx    x0, x0, #3, #2
    ret
8:  mov     x0, #0
    ret
END_FUNCTION libp2p_partial_flags

/*
 * libp2p_wants_partial(peer index, topic index) -> 1 when we send partial
 * messages on the topic and the peer wants them, else 0.
 */
LOCAL_FUNCTION libp2p_wants_partial
    ENTER   0
    mov     x19, x1
    bl      libp2p_partial_flags
    mov     x20, x0
    mov     x0, x19
    bl      libp2p_topic_at
    ldr     x9, [x0, #T_FLAGS]
    ubfx    x9, x9, #3, #1                  /* TF_SUPPORTS_PARTIAL */
    and     x0, x20, x9                     /* and LIBP2P_PARTIAL_REQUESTS of the peer */
    LEAVE   0
END_FUNCTION libp2p_wants_partial

/*
 * libp2p_sends_partial(peer index, topic index) -> 1 when we want partial
 * messages on the topic and the peer sends them, else 0.
 */
LOCAL_FUNCTION libp2p_sends_partial
    ENTER   0
    mov     x19, x1
    bl      libp2p_partial_flags
    lsr     x20, x0, #1                     /* LIBP2P_PARTIAL_SUPPORTS of the peer */
    mov     x0, x19
    bl      libp2p_topic_at
    ldr     x9, [x0, #T_FLAGS]
    ubfx    x9, x9, #2, #1                  /* TF_REQUESTS_PARTIAL */
    and     x0, x20, x9
    LEAVE   0
END_FUNCTION libp2p_sends_partial

/*
 * libp2p_on_partial_peers(event): PARTIAL_PEERS gives the peers of a topic to
 * send partial messages to, with their LIBP2P_PARTIAL_* flags: the mesh
 * peers of a topic we subscribe to with libp2p_wants_partial or
 * libp2p_sends_partial; else the fanout peers (libp2p_fanout_list) that
 * want partial messages. The list is empty when the topic table is full.
 * x19 event, x20 topic, x21 topic index, x22 list, x23 count kept, x24 i,
 * x25 count, then the action, x26 entry.
 */
LOCAL_FUNCTION libp2p_on_partial_peers
    ENTER   0
    mov     x19, x0
    mov     x23, #0
    bl      libp2p_score_all
    add     x0, x19, #LIBP2P_EV_PP_TOPIC
    ldr     x1, [x19, #LIBP2P_EV_PP_TOPIC_LEN]
    bl      libp2p_topic_get
    cbz     x0, 5f
    mov     x20, x0
    bl      libp2p_topic_idx
    mov     x21, x0
    ldr     x9, [x20, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.eq    1f
    mov     x9, #0xFFF0000000000000         /* the mesh, at any score: -infinity */
    fmov    d0, x9
    mov     x0, x21
    mov     x1, #PTF_MESH
    mov     x2, #0
    bl      libp2p_candidates
    b       2f
1:  mov     x0, x20
    mov     x1, x21
    bl      libp2p_fanout_list
2:  mov     x25, x0
    SCR     x22, SC_LIST
    mov     x24, #0
3:  cmp     x24, x25                        /* keep the peers that take part */
    b.hs    5f
    ldr     x9, [x20, #T_FLAGS]
    tst     x9, #TF_SUBSCRIBED
    b.ne    31f
    ldr     w0, [x22, x24, lsl #2]          /* the fanout: the peers that want them */
    mov     x1, x21
    bl      libp2p_partial_flags
    and     x0, x0, #LIBP2P_PARTIAL_REQUESTS
    b       32f
31: ldr     w0, [x22, x24, lsl #2]
    mov     x1, x21
    bl      libp2p_wants_partial
    mov     x26, x0
    ldr     w0, [x22, x24, lsl #2]
    mov     x1, x21
    bl      libp2p_sends_partial
    orr     x0, x0, x26
32: cbz     x0, 4f
    ldr     w9, [x22, x24, lsl #2]
    str     w9, [x22, x23, lsl #2]
    add     x23, x23, #1
4:  add     x24, x24, #1
    b       3b
5:  ldr     x9, [x19, #LIBP2P_EV_PP_TOPIC_LEN]
    add     x9, x9, #(LIBP2P_ACT_PL_TOPIC + 7)
    and     x24, x9, #~7                    /* the list, in the action */
    add     x1, x24, x23, lsl #4
    mov     x0, #LIBP2P_ACTION_PARTIAL_PEERS
    bl      libp2p_action
    cbz     x0, 9f
    mov     x25, x0
    ldr     x2, [x19, #LIBP2P_EV_PP_TOPIC_LEN]
    str     x2, [x25, #LIBP2P_ACT_PL_TOPIC_LEN]
    str     x23, [x25, #LIBP2P_ACT_PL_COUNT]
    add     x0, x25, #LIBP2P_ACT_PL_TOPIC
    add     x1, x19, #LIBP2P_EV_PP_TOPIC
    bl      libp2p_copy
    add     x26, x25, x24
    mov     x24, #0
6:  cmp     x24, x23
    b.hs    9f
    ldr     w0, [x22, x24, lsl #2]
    bl      libp2p_peer_at
    mov     x2, x0
    mov     x0, #ST_PEER_OFF
    mov     x1, #P_SIZE
    bl      libp2p_handle
    str     x0, [x26]
    ldr     w0, [x22, x24, lsl #2]
    mov     x1, x21
    bl      libp2p_partial_flags
    str     x0, [x26, #8]
    add     x26, x26, #16
    add     x24, x24, #1
    b       6b
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_peers

/*
 * libp2p_on_partial_send(event): PARTIAL_SEND: one PartialMessagesExtension
 * to a connected peer that has the extension, when partial_messages is on.
 * The message goes only to a peer that wants partial messages on the topic.
 * Nothing goes when no metadata or message is left.
 * x19 event, x20 peer, x21 with message, x22 peer index.
 */
LOCAL_FUNCTION libp2p_on_partial_send
    ENTER   0
    mov     x19, x0
    CFG     x9, LIBP2P_CFG_PARTIAL_MESSAGES
    cbz     x9, 9f
    ldr     x0, [x19, #LIBP2P_EV_PSEND_PEER]
    bl      libp2p_peer
    cbz     x0, 9f
    mov     x20, x0
    ldr     x9, [x20, #P_FLAGS]
    tst     x9, #PF_PARTIAL
    b.eq    9f
    bl      libp2p_peer_idx
    mov     x22, x0
    mov     x21, #0
    ldr     x9, [x19, #LIBP2P_EV_PSEND_MSG_LEN]
    cbz     x9, 1f
    add     x0, x19, #LIBP2P_EV_PSEND_BYTES
    ldr     x1, [x19, #LIBP2P_EV_PSEND_TOPIC_LEN]
    bl      libp2p_topic_find
    cbz     x0, 1f
    bl      libp2p_topic_idx
    mov     x1, x0
    mov     x0, x22
    bl      libp2p_partial_flags
    and     x21, x0, #LIBP2P_PARTIAL_REQUESTS
1:  ldr     x9, [x19, #LIBP2P_EV_PSEND_META_LEN]
    orr     x9, x9, x21
    cbz     x9, 9f
    mov     x0, x20
    mov     x1, x19
    mov     x2, x21
    bl      libp2p_gs_send_partial
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_send

/*
 * libp2p_on_partial_score(event): the application judged partial message data
 * of a peer in a topic: ACCEPT counts as a first delivery, REJECT as an
 * invalid message.
 * x19 event, x20 peer index.
 */
LOCAL_FUNCTION libp2p_on_partial_score
    ENTER   0
    mov     x19, x0
    ldr     x0, [x19, #LIBP2P_EV_PSCORE_PEER]
    bl      libp2p_peer
    cbz     x0, 9f
    bl      libp2p_peer_idx
    mov     x20, x0
    add     x0, x19, #LIBP2P_EV_PSCORE_TOPIC
    ldr     x1, [x19, #LIBP2P_EV_PSCORE_TOPIC_LEN]
    bl      libp2p_topic_find
    cbz     x0, 9f
    bl      libp2p_topic_idx
    mov     x1, x0
    mov     x0, x20
    ldr     x9, [x19, #LIBP2P_EV_PSCORE_RESULT]
    cmp     x9, #LIBP2P_ACCEPT
    b.ne    1f
    mov     x2, #0
    bl      libp2p_score_valid
    b       9f
1:  bl      libp2p_score_invalid
9:  LEAVE   0
END_FUNCTION libp2p_on_partial_score

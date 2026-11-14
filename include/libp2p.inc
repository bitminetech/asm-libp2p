/*
 * asm-libp2p definitions, in assembler syntax.
 * The requirement entries are in docs/reference/.
 *
 * All numbers are little-endian u64 unless a comment says otherwise. A
 * handle is a slot index in the low 32 bits and the slot generation in the
 * high 32 bits. Offsets named *_OFF are from the start of the state.
 */

/* ---------------------------------------------------------------- Status codes (ARCHITECTURE.md section 6) */

.set LIBP2P_OK, 0
.set LIBP2P_BUFFER_TOO_SMALL, 1
.set LIBP2P_INVALID_CONFIG, 2           /* libp2p_init: a limit or parameter is out of range */
.set LIBP2P_INVALID_EVENT, 3            /* libp2p_step: an event breaks the rules of its kind */
.set LIBP2P_INVALID_KEY, 4              /* libp2p_init: the private key is not valid for its type */
.set LIBP2P_OS_ERROR, 8                 /* shell: an OS call failed */

/* ---------------------------------------------------------------- Byte lists */

.set LIBP2P_BL_SIZE, 0
.set LIBP2P_BL_OFFSET, 8
.set LIBP2P_BL_COUNT, 16
.set LIBP2P_BL_FIXED, 24

/* ---------------------------------------------------------------- Limits */

.set LIBP2P_MAX_PEER_ID, 48             /* bytes of a peer ID (an identity multihash) */
.set LIBP2P_MAX_PROTOCOL, 128           /* bytes of a protocol ID, without the newline */
.set LIBP2P_MAX_PROPOSALS, 4            /* protocols one OPEN_STREAM may propose */
.set LIBP2P_MAX_TOPIC, 256              /* bytes of a topic */
.set LIBP2P_MAX_MSG_ID, 32              /* bytes of a message ID */
.set LIBP2P_NOISE_MAX, 65535            /* bytes of a Noise message */
.set LIBP2P_NOISE_PLAIN, 65519          /* plaintext bytes of a Noise transport message */
.set LIBP2P_YAMUX_WINDOW, 262144        /* the initial window of a yamux stream */
.set LIBP2P_YAMUX_BACKLOG, 256          /* inbound yamux streams not yet acknowledged */
.set LIBP2P_MPLEX_MAX, 1048576          /* bytes of an mplex message */
.set LIBP2P_MAX_DELIVERERS, 12          /* peers kept per seen message, for scores */
.set LIBP2P_PROMISES, 1024              /* IWANT promises followed at a time */
.set LIBP2P_CONN_STREAMS, 256           /* streams of one connection */
.set LIBP2P_PEER_CONNS, 4              /* open connections of one peer: the first, and more the peer dialled */
.set LIBP2P_RECEIVE_MAX, 65536          /* bytes of one RECEIVED event */
.set LIBP2P_RX_SIZE, 65552              /* the receive buffer of a connection: one Noise message */
.set LIBP2P_ACTIONS_MIN, 1056768        /* action room libp2p_step needs: 4096 + 64 + 16 x 65536, rounded up */
.set LIBP2P_SCRATCH_SIZE, 594536       /* bytes of the scratch of libp2p_step */
.set LIBP2P_STATE_VERSION, 3

/* ---------------------------------------------------------------- Address */

.set LIBP2P_ADDR_FAMILY, 0              /* u64: 4 or 6 */
.set LIBP2P_ADDR_PORT, 8                /* u64: TCP port */
.set LIBP2P_ADDR_IP, 16                 /* 16 bytes: IPv4 in the first 4 bytes, or IPv6 */
.set LIBP2P_ADDR_SIZE, 32

/* ---------------------------------------------------------------- Key types (libp2p peer-ids KeyType) */

.set LIBP2P_KEY_ED25519, 1
.set LIBP2P_KEY_SECP256K1, 2

/* ---------------------------------------------------------------- Config (input of libp2p_init) */

.set LIBP2P_CFG_SIZE, 0                 /* total size: fixed fields, then the protocol part */
.set LIBP2P_CFG_KEY_TYPE, 8
.set LIBP2P_CFG_PRIVATE_KEY, 16         /* 32 bytes */
.set LIBP2P_CFG_ENTROPY, 48             /* 32 bytes */
.set LIBP2P_CFG_NOW, 80                 /* ms, monotonic */
.set LIBP2P_CFG_MAX_CONNECTIONS, 88
.set LIBP2P_CFG_MAX_STREAMS, 96
.set LIBP2P_CFG_MAX_PEERS, 104
.set LIBP2P_CFG_MAX_TOPICS, 112
.set LIBP2P_CFG_HEAP_SIZE, 120          /* a power of two */
.set LIBP2P_CFG_SEEN_CAPACITY, 128
.set LIBP2P_CFG_MCACHE_CAPACITY, 136
.set LIBP2P_CFG_PENDING_CAPACITY, 144
.set LIBP2P_CFG_MUXERS, 152             /* bit 0 yamux, bit 1 mplex; yamux is proposed first */
.set LIBP2P_CFG_SEND_WINDOW, 160        /* bytes a connection may have with the shell */
.set LIBP2P_CFG_MAX_RPC, 168            /* bytes of a gossipsub RPC */
.set LIBP2P_CFG_MAX_DATA, 176           /* bytes of a gossipsub message's data */
.set LIBP2P_CFG_HANDSHAKE_MS, 184       /* time for the upgrade of a connection */
.set LIBP2P_CFG_VALIDATION_MS, 192      /* time for the application to judge a message */
.set LIBP2P_CFG_STREAM_QUEUE, 200       /* bytes a stream may have queued */
.set LIBP2P_CFG_PROTOCOLS, 208          /* part: offset, then count: ProtocolEntry list */
.set LIBP2P_CFG_PROTOCOLS_COUNT, 216
/* gossipsub v1.0 and v1.1 parameters */
.set LIBP2P_CFG_D, 224
.set LIBP2P_CFG_D_LOW, 232
.set LIBP2P_CFG_D_HIGH, 240
.set LIBP2P_CFG_D_LAZY, 248
.set LIBP2P_CFG_D_SCORE, 256
.set LIBP2P_CFG_D_OUT, 264
.set LIBP2P_CFG_HEARTBEAT_MS, 272
.set LIBP2P_CFG_FANOUT_TTL_MS, 280
.set LIBP2P_CFG_MCACHE_LEN, 288
.set LIBP2P_CFG_MCACHE_GOSSIP, 296
.set LIBP2P_CFG_SEEN_TTL_MS, 304
.set LIBP2P_CFG_PRUNE_BACKOFF_MS, 312
.set LIBP2P_CFG_UNSUB_BACKOFF_MS, 320
.set LIBP2P_CFG_GRAFT_FLOOD_MS, 328
.set LIBP2P_CFG_FLOOD_PUBLISH, 336
.set LIBP2P_CFG_GOSSIP_FACTOR, 344      /* f64 */
.set LIBP2P_CFG_MAX_IHAVE_LENGTH, 352
.set LIBP2P_CFG_MAX_IHAVE_MESSAGES, 360
.set LIBP2P_CFG_IWANT_FOLLOWUP_MS, 368
.set LIBP2P_CFG_RETRANSMISSION, 376
.set LIBP2P_CFG_OPPORTUNISTIC_TICKS, 384
.set LIBP2P_CFG_OPPORTUNISTIC_PEERS, 392
/* peer score (gossipsub v1.1), f64 unless marked */
.set LIBP2P_CFG_SCORING, 400            /* u64: 0 off, 1 on */
.set LIBP2P_CFG_GOSSIP_THRESHOLD, 408
.set LIBP2P_CFG_PUBLISH_THRESHOLD, 416
.set LIBP2P_CFG_GRAYLIST_THRESHOLD, 424
.set LIBP2P_CFG_ACCEPT_PX_THRESHOLD, 432
.set LIBP2P_CFG_OPPORTUNISTIC_THRESHOLD, 440
.set LIBP2P_CFG_DECAY_INTERVAL_MS, 448  /* u64 */
.set LIBP2P_CFG_DECAY_TO_ZERO, 456
.set LIBP2P_CFG_RETAIN_SCORE_MS, 464    /* u64 */
.set LIBP2P_CFG_APP_WEIGHT, 472
.set LIBP2P_CFG_IP_WEIGHT, 480
.set LIBP2P_CFG_IP_THRESHOLD, 488       /* u64 */
.set LIBP2P_CFG_BEHAVIOUR_WEIGHT, 496
.set LIBP2P_CFG_BEHAVIOUR_THRESHOLD, 504
.set LIBP2P_CFG_BEHAVIOUR_DECAY, 512
.set LIBP2P_CFG_TOPIC_CAP, 520          /* 0 means no cap */
/* identify */
.set LIBP2P_CFG_AGENT_LEN, 528          /* agentVersion: length, then bytes */
.set LIBP2P_CFG_AGENT, 536              /* 64 bytes */
.set LIBP2P_CFG_PV_LEN, 600             /* protocolVersion: length, then bytes */
.set LIBP2P_CFG_PV, 608                 /* 32 bytes */
/* gossipsub v1.2 */
.set LIBP2P_CFG_GOSSIPSUB_V12, 640      /* 1: /meshsub/1.2.0 is proposed first and accepted; 0: /meshsub/1.1.0 only */
.set LIBP2P_CFG_IDONTWANT_THRESHOLD, 648 /* data bytes from which a new message gets IDONTWANT; 0: none is sent */
.set LIBP2P_CFG_DONTWANT_SLOTS, 656     /* message IDs of IDONTWANT kept for each peer; 0: IDONTWANT is not heard */
.set LIBP2P_CFG_DONTWANT_TTL, 664       /* heartbeats an ID of IDONTWANT is kept */
.set LIBP2P_CFG_MAX_IDONTWANT_MESSAGES, 672 /* IDONTWANT messages heard from a peer per heartbeat */
.set LIBP2P_CFG_MAX_IDONTWANT_LENGTH, 680   /* message IDs taken from one IDONTWANT */
/* gossipsub v1.3 */
.set LIBP2P_CFG_GOSSIPSUB_V13, 688      /* 1: /meshsub/1.3.0 is proposed first and accepted; needs gossipsub_v12 */
.set LIBP2P_CFG_PARTIAL_MESSAGES, 696   /* 1: the Partial Messages extension; needs gossipsub_v13 */
.set LIBP2P_CFG_FIXED, 704

/* ProtocolEntry: a protocol ID the node accepts on inbound streams. */
.set LIBP2P_PROTO_LEN, 0
.set LIBP2P_PROTO_BYTES, 8              /* LIBP2P_MAX_PROTOCOL bytes */
.set LIBP2P_PROTO_SIZE, 136

/* TopicParams: the score parameters of one topic (gossipsub v1.1), f64 unless marked. */
.set LIBP2P_TP_WEIGHT, 0
.set LIBP2P_TP_TIME_WEIGHT, 8
.set LIBP2P_TP_TIME_QUANTUM_MS, 16      /* u64 */
.set LIBP2P_TP_TIME_CAP, 24
.set LIBP2P_TP_FIRST_WEIGHT, 32
.set LIBP2P_TP_FIRST_DECAY, 40
.set LIBP2P_TP_FIRST_CAP, 48
.set LIBP2P_TP_MESH_WEIGHT, 56
.set LIBP2P_TP_MESH_DECAY, 64
.set LIBP2P_TP_MESH_THRESHOLD, 72
.set LIBP2P_TP_MESH_CAP, 80
.set LIBP2P_TP_MESH_ACTIVATION_MS, 88   /* u64 */
.set LIBP2P_TP_MESH_WINDOW_MS, 96       /* u64 */
.set LIBP2P_TP_FAIL_WEIGHT, 104
.set LIBP2P_TP_FAIL_DECAY, 112
.set LIBP2P_TP_INVALID_WEIGHT, 120
.set LIBP2P_TP_INVALID_DECAY, 128
.set LIBP2P_TP_SIZE, 136

/* ---------------------------------------------------------------- Tick (input of libp2p_step) */

.set LIBP2P_TICK_NOW, 0                 /* ms, monotonic */
.set LIBP2P_TICK_ENTROPY, 8             /* 32 fresh random bytes */
.set LIBP2P_TICK_SIZE, 40

/* StepResult (output of libp2p_step). */
.set LIBP2P_RESULT_ACCEPTED, 0          /* events handled, from the first */
.set LIBP2P_RESULT_SIZE, 8

/* ---------------------------------------------------------------- Events and actions */

.set LIBP2P_EV_SIZE, 0
.set LIBP2P_EV_KIND, 8

/* Event kinds. Shell results: */
.set LIBP2P_EVENT_ACCEPTED, 1           /* token, address */
.set LIBP2P_EVENT_CONNECTED, 2          /* connection */
.set LIBP2P_EVENT_DIAL_FAILED, 3        /* connection, error */
.set LIBP2P_EVENT_RECEIVED, 4           /* connection, count, bytes */
.set LIBP2P_EVENT_SENT, 5               /* connection, count */
.set LIBP2P_EVENT_CLOSED, 6             /* connection, error */
/* Application requests: */
.set LIBP2P_EVENT_DIAL, 7               /* tag, address, peer ID length, peer ID */
.set LIBP2P_EVENT_DISCONNECT, 8         /* peer */
.set LIBP2P_EVENT_OPEN_STREAM, 9        /* peer, tag, count, protocols */
.set LIBP2P_EVENT_STREAM_WRITE, 10      /* stream, count, bytes */
.set LIBP2P_EVENT_STREAM_CLOSE, 11      /* stream */
.set LIBP2P_EVENT_STREAM_RESET, 12      /* stream */
.set LIBP2P_EVENT_SUBSCRIBE, 13         /* topic length, topic */
.set LIBP2P_EVENT_UNSUBSCRIBE, 14       /* topic length, topic */
.set LIBP2P_EVENT_PUBLISH, 15           /* ID length, ID, topic length, data length, topic, data */
.set LIBP2P_EVENT_MESSAGE_ID, 16        /* handle, ID length, ID */
.set LIBP2P_EVENT_VALIDATION, 17        /* handle, result */
.set LIBP2P_EVENT_APP_SCORE, 18         /* peer, score (f64) */
.set LIBP2P_EVENT_TOPIC_PARAMS, 19      /* topic length, TopicParams, topic */
.set LIBP2P_EVENT_PARTIAL_SUBSCRIBE, 20 /* flags, topic length, topic */
.set LIBP2P_EVENT_PARTIAL_PEERS, 21     /* topic length, topic */
.set LIBP2P_EVENT_PARTIAL_SEND, 22      /* peer, topic, group, metadata and message lengths, then their bytes */
.set LIBP2P_EVENT_PARTIAL_SCORE, 23     /* peer, result, topic length, topic */
.set LIBP2P_EVENT_LAST, 23

/* Event fields. */
.set LIBP2P_EV_TOKEN, 16                /* ACCEPTED */
.set LIBP2P_EV_ACCEPTED_ADDR, 24
.set LIBP2P_EV_ACCEPTED_SIZE, 56
.set LIBP2P_EV_CONN, 16                 /* CONNECTED, DIAL_FAILED, RECEIVED, SENT, CLOSED */
.set LIBP2P_EV_ERROR, 24                /* DIAL_FAILED, CLOSED */
.set LIBP2P_EV_COUNT, 24                /* RECEIVED, SENT */
.set LIBP2P_EV_DATA, 32                 /* RECEIVED */
.set LIBP2P_EV_CONN_SIZE, 32
.set LIBP2P_EV_TAG, 16                  /* DIAL */
.set LIBP2P_EV_DIAL_ADDR, 24
.set LIBP2P_EV_DIAL_ID_LEN, 56
.set LIBP2P_EV_DIAL_ID, 64
.set LIBP2P_EV_DIAL_SIZE, 112
.set LIBP2P_EV_PEER, 16                 /* DISCONNECT, OPEN_STREAM, APP_SCORE */
.set LIBP2P_EV_PEER_SIZE, 24
.set LIBP2P_EV_OPEN_TAG, 24             /* OPEN_STREAM */
.set LIBP2P_EV_OPEN_COUNT, 32
.set LIBP2P_EV_OPEN_PROTOCOLS, 40       /* count ProtocolEntry values */
.set LIBP2P_EV_STREAM, 16               /* STREAM_WRITE, STREAM_CLOSE, STREAM_RESET */
.set LIBP2P_EV_STREAM_COUNT, 24
.set LIBP2P_EV_STREAM_DATA, 32
.set LIBP2P_EV_STREAM_SIZE, 24
.set LIBP2P_EV_TOPIC_LEN, 16            /* SUBSCRIBE, UNSUBSCRIBE */
.set LIBP2P_EV_TOPIC, 24
.set LIBP2P_EV_PUB_ID_LEN, 16           /* PUBLISH */
.set LIBP2P_EV_PUB_ID, 24
.set LIBP2P_EV_PUB_TOPIC_LEN, 56
.set LIBP2P_EV_PUB_DATA_LEN, 64
.set LIBP2P_EV_PUB_TOPIC, 72            /* then the data, at the next multiple of 8 */
.set LIBP2P_EV_HANDLE, 16               /* MESSAGE_ID, VALIDATION */
.set LIBP2P_EV_MSG_ID_LEN, 24
.set LIBP2P_EV_MSG_ID, 32
.set LIBP2P_EV_MSG_ID_SIZE, 64
.set LIBP2P_EV_RESULT, 24
.set LIBP2P_EV_VALIDATION_SIZE, 32
.set LIBP2P_EV_SCORE, 24                /* APP_SCORE */
.set LIBP2P_EV_SCORE_SIZE, 32
.set LIBP2P_EV_TP_TOPIC_LEN, 16         /* TOPIC_PARAMS */
.set LIBP2P_EV_TP_PARAMS, 24
.set LIBP2P_EV_TP_TOPIC, 24 + LIBP2P_TP_SIZE
.set LIBP2P_EV_PS_FLAGS, 16             /* PARTIAL_SUBSCRIBE */
.set LIBP2P_EV_PS_TOPIC_LEN, 24
.set LIBP2P_EV_PS_TOPIC, 32
.set LIBP2P_EV_PP_TOPIC_LEN, 16         /* PARTIAL_PEERS */
.set LIBP2P_EV_PP_TOPIC, 24
.set LIBP2P_EV_PSEND_PEER, 16           /* PARTIAL_SEND */
.set LIBP2P_EV_PSEND_TOPIC_LEN, 24
.set LIBP2P_EV_PSEND_GROUP_LEN, 32
.set LIBP2P_EV_PSEND_META_LEN, 40
.set LIBP2P_EV_PSEND_MSG_LEN, 48
.set LIBP2P_EV_PSEND_BYTES, 56          /* topic, group, metadata, message: each at a multiple of 8 */
.set LIBP2P_EV_PSCORE_PEER, 16          /* PARTIAL_SCORE */
.set LIBP2P_EV_PSCORE_RESULT, 24
.set LIBP2P_EV_PSCORE_TOPIC_LEN, 32
.set LIBP2P_EV_PSCORE_TOPIC, 40

/* Flags of PARTIAL_SUBSCRIBE, PARTIAL_PEERS and the Partial Messages extension. */
.set LIBP2P_PARTIAL_REQUESTS, 1         /* partial messages are wanted on the topic */
.set LIBP2P_PARTIAL_SUPPORTS, 2         /* partial messages are sent on the topic */

/* Validation results. */
.set LIBP2P_ACCEPT, 1
.set LIBP2P_REJECT, 2
.set LIBP2P_IGNORE, 3

/* Action kinds. Shell requests: */
.set LIBP2P_ACTION_DIAL, 1              /* connection, address */
.set LIBP2P_ACTION_ADOPT, 2             /* token, connection */
.set LIBP2P_ACTION_REFUSE, 3            /* token */
.set LIBP2P_ACTION_SEND, 4              /* connection, count, bytes */
.set LIBP2P_ACTION_CLOSE, 5             /* connection */
.set LIBP2P_ACTION_WAKEUP, 6            /* time */
/* Application notices: */
.set LIBP2P_ACTION_PEER_CONNECTED, 7    /* peer, tag, direction, address, peer ID length, peer ID */
.set LIBP2P_ACTION_PEER_DISCONNECTED, 8 /* peer, peer ID length, peer ID */
.set LIBP2P_ACTION_DIAL_FAILED, 9       /* tag, reason */
.set LIBP2P_ACTION_STREAM_INBOUND, 10   /* stream, peer, protocol index */
.set LIBP2P_ACTION_STREAM_OPENED, 11    /* stream, tag, proposal index */
.set LIBP2P_ACTION_STREAM_FAILED, 12    /* tag, reason */
.set LIBP2P_ACTION_STREAM_DATA, 13      /* stream, count, bytes */
.set LIBP2P_ACTION_STREAM_EOF, 14       /* stream */
.set LIBP2P_ACTION_STREAM_RESET, 15     /* stream */
.set LIBP2P_ACTION_MESSAGE, 16          /* handle, peer, data offset, data length, topic length, topic */
.set LIBP2P_ACTION_MESSAGE_STATUS, 17   /* handle, status */
.set LIBP2P_ACTION_PUBLISHED, 18        /* ID length, ID, peers */
.set LIBP2P_ACTION_PEER_TOPIC, 19       /* peer, subscribed, topic length, topic */
.set LIBP2P_ACTION_PARTIAL, 20          /* peer, flags, topic length, group, metadata, message, topic */
.set LIBP2P_ACTION_PARTIAL_PEERS, 21    /* topic length, count, topic, then peer and flags pairs */
.set LIBP2P_ACTION_PARTIAL_GOSSIP, 22   /* topic length, count, topic, then peers */

/* Action fields. */
.set LIBP2P_ACT_SIZE, 0
.set LIBP2P_ACT_KIND, 8
.set LIBP2P_ACT_CONN, 16                /* DIAL, SEND, CLOSE */
.set LIBP2P_ACT_DIAL_ADDR, 24
.set LIBP2P_ACT_DIAL_SIZE, 56
.set LIBP2P_ACT_TOKEN, 16               /* ADOPT, REFUSE */
.set LIBP2P_ACT_ADOPT_CONN, 24
.set LIBP2P_ACT_ADOPT_SIZE, 32
.set LIBP2P_ACT_REFUSE_SIZE, 24
.set LIBP2P_ACT_SEND_COUNT, 24
.set LIBP2P_ACT_SEND_DATA, 32
.set LIBP2P_ACT_CLOSE_SIZE, 24
.set LIBP2P_ACT_TIME, 16                /* WAKEUP */
.set LIBP2P_ACT_WAKEUP_SIZE, 24
.set LIBP2P_ACT_PEER, 16                /* PEER_CONNECTED, PEER_DISCONNECTED */
.set LIBP2P_ACT_PC_TAG, 24
.set LIBP2P_ACT_PC_DIRECTION, 32        /* 0 inbound, 1 outbound */
.set LIBP2P_ACT_PC_ADDR, 40
.set LIBP2P_ACT_PC_ID_LEN, 72
.set LIBP2P_ACT_PC_ID, 80
.set LIBP2P_ACT_PC_SIZE, 128
.set LIBP2P_ACT_PD_ID_LEN, 24
.set LIBP2P_ACT_PD_ID, 32
.set LIBP2P_ACT_PD_SIZE, 80
.set LIBP2P_ACT_TAG, 16                 /* DIAL_FAILED, STREAM_FAILED */
.set LIBP2P_ACT_REASON, 24
.set LIBP2P_ACT_FAILED_SIZE, 32
.set LIBP2P_ACT_STREAM, 16              /* STREAM_* */
.set LIBP2P_ACT_SI_PEER, 24             /* STREAM_INBOUND */
.set LIBP2P_ACT_SI_PROTOCOL, 32
.set LIBP2P_ACT_SI_SIZE, 40
.set LIBP2P_ACT_SO_TAG, 24              /* STREAM_OPENED */
.set LIBP2P_ACT_SO_INDEX, 32
.set LIBP2P_ACT_SO_SIZE, 40
.set LIBP2P_ACT_SD_COUNT, 24            /* STREAM_DATA */
.set LIBP2P_ACT_SD_DATA, 32
.set LIBP2P_ACT_STREAM_SIZE, 24         /* STREAM_EOF, STREAM_RESET */
.set LIBP2P_ACT_HANDLE, 16              /* MESSAGE, MESSAGE_STATUS */
.set LIBP2P_ACT_MSG_PEER, 24
.set LIBP2P_ACT_MSG_DATA_OFF, 32
.set LIBP2P_ACT_MSG_DATA_LEN, 40
.set LIBP2P_ACT_MSG_TOPIC_LEN, 48
.set LIBP2P_ACT_MSG_TOPIC, 56
.set LIBP2P_ACT_STATUS, 24
.set LIBP2P_ACT_STATUS_SIZE, 32
.set LIBP2P_ACT_PUB_ID_LEN, 16          /* PUBLISHED */
.set LIBP2P_ACT_PUB_ID, 24
.set LIBP2P_ACT_PUB_PEERS, 56
.set LIBP2P_ACT_PUB_SIZE, 64
.set LIBP2P_ACT_PT_SUBSCRIBED, 24       /* PEER_TOPIC */
.set LIBP2P_ACT_PT_TOPIC_LEN, 32
.set LIBP2P_ACT_PT_TOPIC, 40
.set LIBP2P_ACT_PM_PEER, 16             /* PARTIAL */
.set LIBP2P_ACT_PM_FLAGS, 24            /* LIBP2P_PARTIAL_* of the peer on the topic */
.set LIBP2P_ACT_PM_TOPIC_LEN, 32
.set LIBP2P_ACT_PM_GROUP_OFF, 40
.set LIBP2P_ACT_PM_GROUP_LEN, 48
.set LIBP2P_ACT_PM_META_OFF, 56
.set LIBP2P_ACT_PM_META_LEN, 64
.set LIBP2P_ACT_PM_MSG_OFF, 72
.set LIBP2P_ACT_PM_MSG_LEN, 80
.set LIBP2P_ACT_PM_TOPIC, 88
.set LIBP2P_ACT_PL_TOPIC_LEN, 16        /* PARTIAL_PEERS, PARTIAL_GOSSIP */
.set LIBP2P_ACT_PL_COUNT, 24
.set LIBP2P_ACT_PL_TOPIC, 32            /* then the list, at the next multiple of 8 */

/* MESSAGE_STATUS values. */
.set LIBP2P_MSG_NEW, 1                  /* judge it and send VALIDATION */
.set LIBP2P_MSG_DUPLICATE, 2            /* seen before: drop it */
.set LIBP2P_MSG_DROPPED, 3              /* no answer in time, or no room: drop it */

/* Reasons of DIAL_FAILED, STREAM_FAILED and CLOSED. */
.set LIBP2P_REASON_CONNECT, 1           /* the TCP connection failed, or did not open within handshake_ms */
.set LIBP2P_REASON_HANDSHAKE, 2         /* the upgrade failed or timed out */
.set LIBP2P_REASON_PEER_ID, 3           /* the peer is not the one dialled */
.set LIBP2P_REASON_LIMIT, 4             /* a table or the heap is full */
.set LIBP2P_REASON_PROTOCOL, 5          /* the peer refused every proposed protocol */
.set LIBP2P_REASON_NO_PEER, 6           /* the peer is not connected */
.set LIBP2P_REASON_CLOSED, 7            /* the connection closed */
.set LIBP2P_REASON_DUPLICATE, 8         /* a connection to the same peer was kept instead */

/* Direction of a connection. */
.set LIBP2P_INBOUND, 0
.set LIBP2P_OUTBOUND, 1

/* ---------------------------------------------------------------- Shell */

/* ShellParams (input of libp2p_shell_size and libp2p_shell_init). */
.set LIBP2P_SP_CAPACITY, 0              /* connection slots: max_connections of the config */
.set LIBP2P_SP_BUFFER, 8                /* send buffer bytes of a connection: at least send_window */
.set LIBP2P_SP_SIZE, 16

/* ShellContext: the sockets of the shell. */
.set LIBP2P_SH_SIZE, 0
.set LIBP2P_SH_CAPACITY, 8
.set LIBP2P_SH_BUFFER, 16
.set LIBP2P_SH_STRIDE, 24               /* bytes of one connection entry */
.set LIBP2P_SH_LISTENERS, 32            /* listening sockets */
.set LIBP2P_SH_LISTEN, 40               /* 4 native sockets (u64), NONE when unused */
.set LIBP2P_SH_MAX_LISTEN, 4
.set LIBP2P_SH_STARTED, 72              /* Windows: Winsock started */
.set LIBP2P_SH_POLL, 80                 /* offset of the poll array */
.set LIBP2P_SH_ENTRIES, 88              /* offset of the connection entries */
.set LIBP2P_SH_FIXED, 96
.set LIBP2P_SE_SOCKET, 0                /* native socket, NONE when free */
.set LIBP2P_SE_HANDLE, 8                /* the connection handle */
.set LIBP2P_SE_STATE, 16                /* 0 free, 1 connecting, 2 open */
.set LIBP2P_SE_LEN, 24                  /* bytes waiting in the send buffer */
.set LIBP2P_SE_DATA, 32                 /* the send buffer */
.set LIBP2P_SE_FIXED, 32
.set LIBP2P_SHELL_ACCEPTING, 16         /* accepted sockets that may wait for ADOPT */

/* ListenResult (output of libp2p_shell_listen). */
.set LIBP2P_LR_ERROR, 0                 /* 0, or the OS error number */
.set LIBP2P_LR_ADDR, 8                  /* the bound address */
.set LIBP2P_LR_SIZE, 40

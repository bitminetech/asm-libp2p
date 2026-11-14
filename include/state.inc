/*
 * asm-libp2p internal layouts: the State value and its tables.
 * The requirement entries are in docs/reference/node.md.
 *
 * The state is one buffer: the fixed fields below, then one part for each
 * table, at the offsets that libp2p_init stores in the fixed fields. A slot
 * reference is a slot index; NONE (all ones) means no slot.
 */

.set NONE, -1

/* ---------------------------------------------------------------- State: fixed fields */

.set ST_SIZE, 0
.set ST_VERSION, 8
.set ST_NOW, 16                         /* ms: the largest tick seen */
.set ST_DRBG_KEY, 24                    /* 32 bytes */
.set ST_DRBG_COUNT, 56
.set ST_KEY_TYPE, 64
.set ST_PRIVATE_KEY, 72                 /* 32 bytes */
.set ST_PUBLIC_KEY, 104                 /* 33 bytes for secp256k1 (compressed), 32 for Ed25519 */
.set ST_PUBLIC_LEN, 144
.set ST_PEER_ID_LEN, 152
.set ST_PEER_ID, 160                    /* LIBP2P_MAX_PEER_ID bytes */
.set ST_NOISE_PRIV, 208                 /* 32 bytes: the static X25519 key of Noise */
.set ST_NOISE_PUB, 240                  /* 32 bytes */
.set ST_NOISE_SIG_LEN, 272
.set ST_NOISE_SIG, 280                  /* 72 bytes: the identity signature of the static key */
.set ST_PAYLOAD_LEN, 352
.set ST_PAYLOAD, 360                    /* 160 bytes: our NoiseHandshakePayload */
.set ST_CONFIG, 520                     /* the fixed fields of the config, LIBP2P_CFG_FIXED bytes */
.set ST_TABLES, ST_CONFIG + LIBP2P_CFG_FIXED
/* table offsets and counts */
.set ST_CONN_OFF, ST_TABLES
.set ST_CONN_COUNT, ST_TABLES + 8
.set ST_STREAM_OFF, ST_TABLES + 16
.set ST_STREAM_COUNT, ST_TABLES + 24
.set ST_PEER_OFF, ST_TABLES + 32
.set ST_PEER_COUNT, ST_TABLES + 40
.set ST_TOPIC_OFF, ST_TABLES + 48
.set ST_TOPIC_COUNT, ST_TABLES + 56
.set ST_PT_OFF, ST_TABLES + 64          /* peer x topic table: entry (peer * topics + topic) */
.set ST_SEEN_OFF, ST_TABLES + 72
.set ST_SEEN_COUNT, ST_TABLES + 80      /* capacity */
.set ST_SEEN_INDEX_OFF, ST_TABLES + 88  /* 2 * capacity u32 */
.set ST_MC_OFF, ST_TABLES + 96
.set ST_MC_COUNT, ST_TABLES + 104       /* capacity */
.set ST_MC_INDEX_OFF, ST_TABLES + 112   /* 2 * capacity u32 */
.set ST_MC_STRIDE, ST_TABLES + 120      /* bytes of one entry: fixed part, then 2 bits for each peer */
.set ST_PEND_OFF, ST_TABLES + 128
.set ST_PEND_COUNT, ST_TABLES + 136
.set ST_PROMISE_OFF, ST_TABLES + 144    /* LIBP2P_PROMISES entries */
.set ST_PROTO_OFF, ST_TABLES + 152      /* the ProtocolEntry list of the config */
.set ST_PROTO_COUNT, ST_TABLES + 160
.set ST_HEAP_OFF, ST_TABLES + 168
.set ST_HEAP_SIZE, ST_TABLES + 176
/* running values */
.set ST_SEEN_HEAD, ST_TABLES + 184      /* ring: next entry to write */
.set ST_SEEN_USED, ST_TABLES + 192
.set ST_MC_HEAD, ST_TABLES + 200
.set ST_MC_USED, ST_TABLES + 208
.set ST_HEARTBEAT_AT, ST_TABLES + 216   /* ms */
.set ST_HEARTBEATS, ST_TABLES + 224     /* heartbeat count: the mcache window */
.set ST_DECAY_AT, ST_TABLES + 232       /* ms */
.set ST_CONN_LIVE, ST_TABLES + 240
.set ST_HEAP_FREE, ST_TABLES + 248      /* free list heads: 48 orders */
.set ST_HEAP_ORDERS, 48
.set ST_HEAP_USED, ST_HEAP_FREE + 8 * ST_HEAP_ORDERS
.set ST_FIXED, ST_HEAP_USED + 8

/* ---------------------------------------------------------------- Heap blocks (buddy allocator) */

.set HB_ORDER, 0                        /* u32: the block is 2^order bytes */
.set HB_FREE, 4                         /* u32: 1 on a free list */
.set HB_NEXT, 8                         /* free list links: heap offsets, or NONE */
.set HB_PREV, 16
.set HB_HEADER, 16                      /* the payload of a used block starts here */
.set HEAP_MIN_ORDER, 6

/* Send chunks: heap blocks queued on a stream. */
.set CH_NEXT, HB_HEADER                 /* heap offset of the next chunk, or NONE */
.set CH_LEN, HB_HEADER + 8              /* bytes of data */
.set CH_DONE, HB_HEADER + 16            /* bytes already framed and sent */
.set CH_DATA, HB_HEADER + 24

/* ---------------------------------------------------------------- Connection slot */

.set C_GEN, 0                           /* u32 */
.set C_PHASE, 4                         /* u32 */
.set C_FLAGS, 8
.set C_PEER, 16                         /* peer slot index once bound (P_CONN of the peer, or a secondary connection), else NONE */
.set C_TAG, 24                          /* the DIAL tag */
.set C_ADDR, 32                         /* LIBP2P_ADDR_SIZE */
.set C_DEADLINE, 64                     /* ms: the upgrade must finish by then */
.set C_EXP_ID_LEN, 72                   /* the peer ID the dial expects, or length 0 */
.set C_EXP_ID, 80                       /* 48 bytes */
.set C_RX, 128                          /* heap offset of the receive buffer */
.set C_RX_LEN, 136
.set C_INFLIGHT, 144                    /* bytes with the shell, not yet SENT */
.set C_OUT_LEN, 152
.set C_OUT, 160                         /* 768 bytes: bytes before the muxer */
.set C_OUT_CAP, 768
.set C_NS_H, 928                        /* Noise SymmetricState and handshake */
.set C_NS_CK, 960
.set C_NS_K, 992
.set C_NS_N, 1024
.set C_NS_HASK, 1032
.set C_NS_E, 1040                       /* e: private, then public */
.set C_NS_EPUB, 1072
.set C_NS_RE, 1104
.set C_NS_RS, 1136
.set C_TX_K, 1168                       /* transport CipherStates */
.set C_TX_N, 1200
.set C_RX_K, 1208
.set C_RX_N, 1240
.set C_MS_STATE, 1248                   /* multistream before the muxer */
.set C_MS_LEN, 1256
.set C_MS_NEED, 1264
.set C_MS_BUF, 1272                     /* 160 bytes */
.set C_MS_CAP, 160
.set C_MX_HDR, 1432                     /* muxer frame parser: 24 header bytes */
.set C_MX_HLEN, 1456
.set C_MX_STREAM, 1464                  /* stream slot of the current frame, or NONE */
.set C_MX_REMAIN, 1472                  /* data bytes of the current frame still to come */
.set C_MX_FLAGS, 1480                   /* type and flags of the current frame */
.set C_MX_NEXT_ID, 1488                 /* the next stream ID this side opens */
.set C_PING_COUNT, 1496                 /* yamux pings to answer */
.set C_PINGS, 1504                      /* 4 u32 values */
.set C_STREAM_HEAD, 1520                /* first stream slot of the connection */
.set C_STREAMS, 1528
.set C_BACKLOG, 1536                    /* inbound streams not yet acknowledged */
.set C_CURSOR, 1544                     /* the stream the drain starts at */
.set C_NS_STEP, 1552                    /* Noise messages handled */
.set C_RID_LEN, 1560                    /* the peer ID the handshake proved */
.set C_RID, 1568                        /* 48 bytes */
.set C_KEY_TYPE, 1616
.set C_OUT_RAW, 1624                    /* the first C_OUT_RAW bytes of C_OUT go out unencrypted */
.set C_RSTS, 1632                       /* yamux stream IDs to reset: count, then 6 u32 */
.set C_RST_IDS, 1640
.set C_SIZE, 1664

/* Connection phases. */
.set PH_FREE, 0
.set PH_DIALING, 1                      /* DIAL sent, waiting for CONNECTED */
.set PH_ADOPTING, 2                     /* ADOPT sent */
.set PH_SECURITY, 3                     /* multistream for /noise */
.set PH_NOISE, 4                        /* Noise XX */
.set PH_MUXER, 5                        /* multistream for the muxer */
.set PH_OPEN, 6
.set PH_CLOSING, 7                      /* CLOSE sent, waiting for CLOSED */

/* Connection flags. */
.set CF_OUTBOUND, 1
.set CF_YAMUX, 2
.set CF_MPLEX, 4
.set CF_GOAWAY, 8                       /* a yamux Go Away to send */
.set CF_SENT_HEADER, 16                 /* multistream header sent */
.set CF_GOT_HEADER, 32                  /* multistream header received */
.set CF_TRANSPORT, 64                   /* Noise transport keys in use */
.set CF_MPLEX_TRIED, 128                /* yamux was refused, mplex proposed */
.set CF_REPORTED, 256                   /* PEER_CONNECTED or DIAL_FAILED was given */
.set CF_NEED_CLOSE, 512                 /* a CLOSE action is still to be written */

/* ---------------------------------------------------------------- Stream slot */

.set S_GEN, 0                           /* u32 */
.set S_USED, 4                          /* u32 */
.set S_CONN, 8
.set S_ID, 16                           /* the muxer stream ID */
.set S_FLAGS, 24
.set S_KIND, 32
.set S_PROTO, 40                        /* app protocol index, or the proposal accepted */
.set S_TAG, 48
.set S_PEER, 56
.set S_SEND_WIN, 64
.set S_RECV_WIN, 72
.set S_RECV_PEND, 80                    /* bytes taken, not yet granted back */
.set S_Q_HEAD, 88
.set S_Q_TAIL, 96
.set S_Q_BYTES, 104
.set S_NEXT, 112
.set S_PREV, 120
.set S_MS_STATE, 128
.set S_MS_LEN, 136
.set S_MS_NEED, 144
.set S_MS_BUF, 152                      /* 136 bytes */
.set S_MS_CAP, 136
.set S_PROPOSALS, 288                   /* heap offset of the proposals (outbound app streams) */
.set S_PROP_COUNT, 296
.set S_PROP_INDEX, 304
.set S_RPC_BUF, 312                     /* gossipsub RPC being read: heap offset */
.set S_RPC_LEN, 320                     /* its length */
.set S_RPC_GOT, 328
.set S_RPC_VARINT, 336                  /* the length prefix being read */
.set S_RPC_SHIFT, 344
.set S_TARGET, 352                      /* the kind it becomes once negotiated */
.set S_SIZE, 360

/* Stream kinds. */
.set SK_NEGOTIATING, 0
.set SK_GOSSIP_IN, 1
.set SK_GOSSIP_OUT, 2
.set SK_APP, 3
.set SK_IDENTIFY, 4                     /* we answered /ipfs/id/1.0.0 */

/* Stream flags. */
.set SF_LOCAL, 1                        /* this side opened it */
.set SF_SYN, 2                          /* yamux SYN or mplex NewStream to send */
.set SF_ACK, 4                          /* yamux ACK to send */
.set SF_FIN, 8                          /* FIN or close to send, after the queue */
.set SF_FIN_SENT, 16
.set SF_RST, 32                         /* RST or reset to send */
.set SF_REMOTE_FIN, 64
.set SF_REPORTED, 128                   /* the application knows the stream */
.set SF_DEAD, 256                       /* reset or both sides closed: free after the drain */
.set SF_GOT_HEADER, 512                 /* the multistream header of the stream came */

/* ---------------------------------------------------------------- Peer slot */

.set P_GEN, 0                           /* u32 */
.set P_STATE, 4                         /* u32 */
.set P_CONN, 8
.set P_ID_LEN, 16
.set P_ID, 24                           /* 48 bytes */
.set P_FLAGS, 72
.set P_GS_OUT, 80                       /* our gossipsub stream to the peer */
.set P_GS_IN, 88
.set P_IP, 96                           /* 16 bytes */
.set P_IP_FAMILY, 112
.set P_APP_SCORE, 120                   /* f64 */
.set P_BEHAVIOUR, 128                   /* f64 */
.set P_IHAVE_COUNT, 136                 /* IHAVE messages this heartbeat */
.set P_IHAVE_IDS, 144                   /* IDs asked for this heartbeat */
.set P_EXPIRE, 152                      /* ms: a retained score ends then */
.set P_SCORE, 160                       /* f64: the score at the last heartbeat */
.set P_SIZE, 168

/* Peer states. */
.set PS_FREE, 0
.set PS_CONNECTED, 1
.set PS_RETAINED, 2

/* Peer flags. */
.set PF_OUTBOUND, 1
.set PF_GOSSIP, 2                       /* our /meshsub/1.1.0 stream is open */
.set PF_HELLO, 4                        /* our subscriptions were sent */

/* ---------------------------------------------------------------- Topic slot */

.set T_USED, 0
.set T_FLAGS, 8
.set T_LEN, 16
.set T_HASH, 24
.set T_NAME, 32                         /* 256 bytes */
.set T_MESH, 288                        /* peers in the mesh */
.set T_FANOUT, 296
.set T_FANOUT_LAST, 304                 /* ms: our last publish */
.set T_PEERS, 312                       /* peers subscribed */
.set T_PARAMS, 320                      /* TopicParams */
.set T_SIZE, T_PARAMS + LIBP2P_TP_SIZE

/* Topic flags. */
.set TF_SUBSCRIBED, 1
.set TF_PARAMS, 2

/* ---------------------------------------------------------------- Peer x topic entry */

.set PT_FLAGS, 0
.set PT_GRAFT_TIME, 8                   /* ms */
.set PT_BACKOFF, 16                     /* ms: no GRAFT before then */
.set PT_FIRST, 24                       /* f64: P2 counter */
.set PT_MESH_DEL, 32                    /* f64: P3 counter */
.set PT_MESH_FAIL, 40                   /* f64: P3b counter */
.set PT_INVALID, 48                     /* f64: P4 counter */
.set PT_SIZE, 64

/* Peer x topic flags. */
.set PTF_SUBSCRIBED, 1                  /* the peer said it subscribes */
.set PTF_MESH, 2
.set PTF_FANOUT, 4

/* ---------------------------------------------------------------- Seen message */

.set SN_ID_LEN, 0
.set SN_ID, 8                           /* 32 bytes */
.set SN_TIME, 40                        /* ms: first seen */
.set SN_STATUS, 48
.set SN_VALIDATED, 56                   /* ms */
.set SN_TOPIC, 64                       /* u32 topic slot, u32 deliverer count */
.set SN_COUNT, 68
.set SN_PEERS, 72                       /* LIBP2P_MAX_DELIVERERS u16 peer slots */
.set SN_SIZE, 96

/* Seen statuses. */
.set SS_PENDING, 0
.set SS_VALID, 1
.set SS_INVALID, 2
.set SS_IGNORED, 3

/* ---------------------------------------------------------------- Message cache entry */

.set MC_ID_LEN, 0
.set MC_ID, 8
.set MC_TOPIC, 40
.set MC_DATA, 48                        /* heap offset */
.set MC_DATA_LEN, 56
.set MC_WINDOW, 64                      /* heartbeat number when it was put */
.set MC_USED, 72
.set MC_TX, 80                          /* 2 bits for each peer: IWANT answers sent */

/* ---------------------------------------------------------------- Pending message */

.set PD_GEN, 0                          /* u32 */
.set PD_STATE, 4                        /* u32 */
.set PD_PEER, 8
.set PD_TOPIC, 16
.set PD_DATA, 24                        /* heap offset */
.set PD_DATA_LEN, 32
.set PD_TIME, 40
.set PD_ID_LEN, 48
.set PD_ID, 56                          /* 32 bytes */
.set PD_SEEN, 88                        /* the seen entry, once the ID came */
.set PD_SIZE, 96

/* Pending states. */
.set PDS_FREE, 0
.set PDS_WAIT_ID, 1
.set PDS_WAIT_VERDICT, 2

/* ---------------------------------------------------------------- IWANT promise */

.set PR_PEER, 0                         /* NONE when unused */
.set PR_DEADLINE, 8
.set PR_ID_LEN, 16
.set PR_ID, 24
.set PR_SIZE, 56

/* ---------------------------------------------------------------- Step scratch */

.set SC_SIZE, 0
.set SC_ACTIONS, 8                      /* the actions list of this step (a pointer, for this call only) */
.set SC_NOW, 16
.set SC_WAKE, 24                        /* the earliest time the next step is due */
.set SC_RESERVE, 32                     /* action bytes kept for the end of the step */
.set SC_HMAC, 40                        /* 96 + 64 bytes: HMAC and HKDF scratch, size first */
.set SC_HMAC_SIZE, 160
.set SC_OKM, 200                        /* ByteList: 24 + 64 bytes */
.set SC_LENGTH, 288                     /* u64: 64, the HKDF output length */
.set SC_EMPTY, 296                      /* ByteList: empty */
.set SC_AAD, 320                        /* ByteList: 24 + 32 bytes (h) */
.set SC_NONCE, 376                      /* 16 bytes: 12 used */
.set SC_PRK, 392                        /* ByteList: 24 + 32 bytes */
.set SC_WORK, 448                       /* 4096 bytes: payloads, signatures, small messages */
.set SC_WORK_SIZE, 4096
.set SC_PLAIN, SC_WORK + SC_WORK_SIZE   /* ByteList: 24 + 65536 bytes */
.set SC_SEAL, SC_PLAIN + 65560          /* ByteList: 24 + 65536 + 64 bytes */
.set SC_MIX, SC_SEAL + 65624            /* ByteList: 24 + 32 + 65536 bytes, the input of MixHash */
.set SC_LIST, SC_MIX + 65592            /* 262144 bytes: peer lists and message ID lists of gossipsub */
.set SC_LIST_SIZE, 262144
.set SC_IDS, SC_LIST + SC_LIST_SIZE     /* 8192 pairs: the address of a message ID, then its length */
.set SC_IDS_SIZE, 131072
.set SC_TOTAL, SC_IDS + SC_IDS_SIZE
.if SC_TOTAL - LIBP2P_SCRATCH_SIZE
.error "SC_TOTAL differs from LIBP2P_SCRATCH_SIZE"
.endif

/* Action room kept for the end of a step: timers, the drain and WAKEUP. */
.set ACTIONS_RESERVE, 4096

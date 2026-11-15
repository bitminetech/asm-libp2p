/*
 * C view of the asm-libp2p interface, for the tests: the values of
 * include/libp2p.inc and the entry points of docs/reference/.
 */
#ifndef LIBP2P_H
#define LIBP2P_H
#include <stdint.h>

#if defined(_WIN32) && defined(__x86_64__)
#define LIBP2P_ABI __attribute__((sysv_abi))
#else
#define LIBP2P_ABI
#endif

LIBP2P_ABI uint64_t libp2p_state_size(const void *config, uint64_t *size);
LIBP2P_ABI uint64_t libp2p_init(const void *config, void *state);
LIBP2P_ABI uint64_t libp2p_step(void *state, const void *tick, const void *events, void *scratch, void *actions,
                                uint64_t *result);

typedef struct { uint64_t capacity, buffer; } libp2p_shell_params;
typedef struct { uint64_t error; struct { uint64_t family, port; uint8_t ip[16]; } addr; } libp2p_listen_result;
LIBP2P_ABI uint64_t libp2p_shell_size(const libp2p_shell_params *params, uint64_t *size);
LIBP2P_ABI uint64_t libp2p_shell_init(const libp2p_shell_params *params, void *context);
LIBP2P_ABI uint64_t libp2p_shell_listen(void *context, const void *addr, libp2p_listen_result *result);
typedef struct { uint64_t error, socket; struct { uint64_t family, port; uint8_t ip[16]; } addr; } libp2p_bind_result;
LIBP2P_ABI uint64_t libp2p_shell_bind(void *context, const void *addr, libp2p_bind_result *result);
LIBP2P_ABI uint64_t libp2p_shell_perform(void *context, const void *actions, void *events);
LIBP2P_ABI uint64_t libp2p_shell_wait(void *context, const uint64_t *timeout_ms, void *events);
LIBP2P_ABI uint64_t libp2p_shell_close(void *context);
LIBP2P_ABI uint64_t libp2p_shell_clock(void *tick);

enum {
    LIBP2P_OK = 0, LIBP2P_BUFFER_TOO_SMALL = 1, LIBP2P_INVALID_CONFIG = 2, LIBP2P_INVALID_EVENT = 3,
    LIBP2P_INVALID_KEY = 4, LIBP2P_OS_ERROR = 8,
};

enum { LIBP2P_KEY_ED25519 = 1, LIBP2P_KEY_SECP256K1 = 2 };
enum { LIBP2P_MAX_PEER_ID = 48, LIBP2P_MAX_PROTOCOL = 128, LIBP2P_MAX_TOPIC = 256, LIBP2P_MAX_MSG_ID = 32 };
enum { LIBP2P_RECEIVE_MAX = 65536, LIBP2P_ACTIONS_MIN = 1056768, LIBP2P_SCRATCH_SIZE = 608928 };
enum { LIBP2P_DATAGRAM_MAX = 65535 };
enum { LIBP2P_TCP = 0, LIBP2P_QUIC = 1 };
enum { LIBP2P_QUIC_ON = 1, LIBP2P_QUIC_ACCEPT = 2 };

typedef struct { uint64_t family, port; uint8_t ip[16]; } libp2p_addr;
typedef struct { uint64_t len; uint8_t bytes[128]; } libp2p_proto;

typedef struct {
    uint64_t size, key_type;
    uint8_t private_key[32], entropy[32];
    uint64_t now, max_connections, max_streams, max_peers, max_topics, heap_size, seen_capacity, mcache_capacity,
        pending_capacity, muxers, send_window, max_rpc, max_data, handshake_ms, validation_ms, stream_queue,
        protocols, protocols_count;
    uint64_t d, d_low, d_high, d_lazy, d_score, d_out, heartbeat_ms, fanout_ttl_ms, mcache_len, mcache_gossip,
        seen_ttl_ms, prune_backoff_ms, unsub_backoff_ms, graft_flood_ms, flood_publish;
    double gossip_factor;
    uint64_t max_ihave_length, max_ihave_messages, iwant_followup_ms, retransmission, opportunistic_ticks,
        opportunistic_peers;
    uint64_t scoring;
    double gossip_threshold, publish_threshold, graylist_threshold, accept_px_threshold, opportunistic_threshold;
    uint64_t decay_interval_ms;
    double decay_to_zero;
    uint64_t retain_score_ms;
    double app_weight, ip_weight;
    uint64_t ip_threshold;
    double behaviour_weight, behaviour_threshold, behaviour_decay, topic_cap;
    uint64_t agent_len;
    uint8_t agent[64];
    uint64_t pv_len;
    uint8_t pv[32];
    uint64_t gossipsub_v12, idontwant_threshold, dontwant_slots, dontwant_ttl, max_idontwant_messages,
        max_idontwant_length;
    uint64_t gossipsub_v13, partial_messages;
    uint64_t quic, quic_heap, quic_idle_ms, quic_keep_alive_ms, quic_max_data, quic_stream_data, quic_max_streams,
        quic_sent, quic_window;
} libp2p_config;                                    /* LIBP2P_CFG_FIXED = 776 bytes */

typedef struct {
    double weight, time_weight;
    uint64_t time_quantum_ms;
    double time_cap, first_weight, first_decay, first_cap, mesh_weight, mesh_decay, mesh_threshold, mesh_cap;
    uint64_t mesh_activation_ms, mesh_window_ms;
    double fail_weight, fail_decay, invalid_weight, invalid_decay;
} libp2p_topic_params;                              /* 136 bytes */

typedef struct { uint64_t now; uint8_t entropy[32]; uint64_t us, unix_time; } libp2p_tick;

enum {
    EV_ACCEPTED = 1, EV_CONNECTED, EV_DIAL_FAILED, EV_RECEIVED, EV_SENT, EV_CLOSED, EV_DIAL, EV_DISCONNECT,
    EV_OPEN_STREAM, EV_STREAM_WRITE, EV_STREAM_CLOSE, EV_STREAM_RESET, EV_SUBSCRIBE, EV_UNSUBSCRIBE, EV_PUBLISH,
    EV_MESSAGE_ID, EV_VALIDATION, EV_APP_SCORE, EV_TOPIC_PARAMS, EV_PARTIAL_SUBSCRIBE, EV_PARTIAL_PEERS,
    EV_PARTIAL_SEND, EV_PARTIAL_SCORE, EV_DATAGRAM,
};
enum {
    ACT_DIAL = 1, ACT_ADOPT, ACT_REFUSE, ACT_SEND, ACT_CLOSE, ACT_WAKEUP, ACT_PEER_CONNECTED, ACT_PEER_DISCONNECTED,
    ACT_DIAL_FAILED, ACT_STREAM_INBOUND, ACT_STREAM_OPENED, ACT_STREAM_FAILED, ACT_STREAM_DATA, ACT_STREAM_EOF,
    ACT_STREAM_RESET, ACT_MESSAGE, ACT_MESSAGE_STATUS, ACT_PUBLISHED, ACT_PEER_TOPIC, ACT_PARTIAL,
    ACT_PARTIAL_PEERS, ACT_PARTIAL_GOSSIP, ACT_SEND_DATAGRAM,
};
enum { PARTIAL_REQUESTS = 1, PARTIAL_SUPPORTS = 2 };
enum { LIBP2P_ACCEPT = 1, LIBP2P_REJECT = 2, LIBP2P_IGNORE = 3 };
enum { MSG_NEW = 1, MSG_DUPLICATE = 2, MSG_DROPPED = 3 };

/* Event and action layouts. */
typedef struct { uint64_t size, kind; } libp2p_header;
typedef struct { uint64_t size, kind, token; libp2p_addr addr; } ev_accepted;
typedef struct { uint64_t size, kind, conn, value; } ev_conn;              /* CONNECTED (value unused), DIAL_FAILED, SENT, CLOSED */
typedef struct { uint64_t size, kind, conn, count; uint8_t data[]; } ev_received;
typedef struct { uint64_t size, kind, tag; libp2p_addr addr; uint64_t id_len; uint8_t id[48]; uint64_t transport, socket; } ev_dial;
typedef struct { uint64_t size, kind, socket; libp2p_addr addr; uint64_t count; uint8_t data[]; } ev_datagram;
typedef struct { uint64_t size, kind, peer, tag, count; libp2p_proto protocols[]; } ev_open_stream;
typedef struct { uint64_t size, kind, stream, count; uint8_t data[]; } ev_stream_write;
typedef struct { uint64_t size, kind, handle, id_len; uint8_t id[32]; } ev_message_id;

typedef struct { uint64_t size, kind, conn; libp2p_addr addr; } act_dial;
typedef struct { uint64_t size, kind, token, conn; } act_adopt;
typedef struct { uint64_t size, kind, conn, count; uint8_t data[]; } act_send;
typedef struct { uint64_t size, kind, peer, tag, direction; libp2p_addr addr; uint64_t id_len; uint8_t id[48]; uint64_t transport; } act_peer_connected;
typedef struct { uint64_t size, kind, socket; libp2p_addr addr; uint64_t count; uint8_t data[]; } act_datagram;
typedef struct { uint64_t size, kind, peer, id_len; uint8_t id[48]; } act_peer_disconnected;
typedef struct { uint64_t size, kind, tag, reason; } act_failed;
typedef struct { uint64_t size, kind, stream, peer, protocol; } act_stream_inbound;
typedef struct { uint64_t size, kind, stream, tag, index; } act_stream_opened;
typedef struct { uint64_t size, kind, stream, count; uint8_t data[]; } act_stream_data;
typedef struct { uint64_t size, kind, handle, peer, data_off, data_len, topic_len; uint8_t topic[]; } act_message;
typedef struct { uint64_t size, kind, handle, status; } act_message_status;
typedef struct { uint64_t size, kind, id_len; uint8_t id[32]; uint64_t peers; } act_published;
typedef struct { uint64_t size, kind, peer, subscribed, topic_len; uint8_t topic[]; } act_peer_topic;
typedef struct { uint64_t size, kind, flags, topic_len; uint8_t topic[]; } ev_partial_subscribe;
typedef struct { uint64_t size, kind, topic_len; uint8_t topic[]; } ev_partial_peers;
/* PARTIAL_SEND: then topic, group, metadata and message, each at a multiple of 8. */
typedef struct { uint64_t size, kind, peer, topic_len, group_len, meta_len, msg_len; uint8_t bytes[]; } ev_partial_send;
typedef struct { uint64_t size, kind, peer, result, topic_len; uint8_t topic[]; } ev_partial_score;
typedef struct {
    uint64_t size, kind, peer, flags, topic_len, group_off, group_len, meta_off, meta_len, msg_off, msg_len;
    uint8_t topic[];
} act_partial;
/* PARTIAL_PEERS (peer and flags pairs) and PARTIAL_GOSSIP (peers): the list after the topic, at a multiple of 8. */
typedef struct { uint64_t size, kind, topic_len, count; uint8_t topic[]; } act_partial_list;

#endif

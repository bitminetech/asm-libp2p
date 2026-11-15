/*
 * Scenario runner for asm-libp2p. Test code: the library itself is assembly.
 *
 * Usage: runner [SCENARIO ...]   (no names: every scenario)
 *
 * Nodes run in memory. The runner plays the shell: it carries the bytes of
 * each connection to the other node, and answers DIAL, ADOPT, REFUSE, SEND
 * and CLOSE as a socket layer would; it carries each SEND_DATAGRAM to the
 * node of its UDP address, and may drop every n-th. Keys, entropy and time are fixed, so
 * each scenario is deterministic. Each scenario checks its outcomes, then
 * prints a transcript digest: FNV-1a 64 over every action of every node, in
 * order. Every ISA must give the digests of the DIGESTS table (recorded on
 * ARM64): the cores follow one instruction sequence, so any difference is a
 * port error.
 *
 * Every library call goes through abi_call (tests/runner/abi_<ISA>.s). The
 * runner prints the most stack each function used, and fails when a call
 * uses more than STACK_CAP or changes state that the ABI says it must keep.
 * With no names, it ends with a "FUNCTION <name> PASS" or FAIL line for
 * each L2 function, for the tick tables.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libp2p.h"

LIBP2P_ABI uint64_t crypto_sha256(const void *message, void *digest);

#define STACK_CAP 16384 /* README: stack per call */
#define PAINT_BYTES (STACK_CAP + 4096)

typedef struct {
    uint64_t fn, arg[5], paint, status, fault, stack, scratch[4], arg5;
} abi_ctx;
LIBP2P_ABI void abi_call(abi_ctx *ctx);

enum { F_STATE_SIZE, F_INIT, F_STEP, F_COUNT };
static const char *FN_NAME[F_COUNT] = {"libp2p_state_size", "libp2p_init", "libp2p_step"};
static void *const FN_ADDR[F_COUNT] = {(void *)libp2p_state_size, (void *)libp2p_init, (void *)libp2p_step};
static uint64_t stack_peak[F_COUNT], abi_fault[F_COUNT];

static uint64_t call(int fn, const void *a0, const void *a1, const void *a2, const void *a3, const void *a4,
                     const void *a5) {
    abi_ctx c;
    memset(&c, 0, sizeof c);
    c.fn = (uint64_t)(uintptr_t)FN_ADDR[fn];
    c.arg[0] = (uint64_t)(uintptr_t)a0;
    c.arg[1] = (uint64_t)(uintptr_t)a1;
    c.arg[2] = (uint64_t)(uintptr_t)a2;
    c.arg[3] = (uint64_t)(uintptr_t)a3;
    c.arg[4] = (uint64_t)(uintptr_t)a4;
    c.arg5 = (uint64_t)(uintptr_t)a5;
    c.paint = PAINT_BYTES;
    abi_call(&c);
    if (c.stack > stack_peak[fn]) stack_peak[fn] = c.stack;
    abi_fault[fn] |= c.fault;
    return c.status;
}

static void *xmalloc(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return p;
}

/* ---------------------------------------------------------------- Checks and the transcript */

static int failures;
static const char *scenario;
static uint64_t digest;

#define CHECK(cond, ...)                                                                                              \
    do {                                                                                                              \
        if (!(cond)) {                                                                                                \
            failures++;                                                                                               \
            printf("  FAIL %s line %d: ", scenario, __LINE__);                                                        \
            printf(__VA_ARGS__);                                                                                      \
            printf("\n");                                                                                             \
        }                                                                                                             \
    } while (0)

static void fnv(const void *p, size_t n) {
    const uint8_t *b = p;
    for (size_t i = 0; i < n; i++) {
        digest ^= b[i];
        digest *= 0x100000001B3ull;
    }
}

/* The message ID of the runner: the first 20 bytes of SHA-256 of the data. */
static void msg_id(const void *data, size_t n, uint8_t *id) {
    uint8_t *bl = xmalloc(24 + n), d[32];
    ((uint64_t *)bl)[0] = 24 + n;
    ((uint64_t *)bl)[1] = 24;
    ((uint64_t *)bl)[2] = n;
    memcpy(bl + 24, data, n);
    crypto_sha256(bl, d);
    free(bl);
    memcpy(id, d, 20);
}

/* ---------------------------------------------------------------- Nodes */

#define MAX_NODES 8
#define MAX_STREAMS 64
#define MAX_PEERS 16
#define MAX_MSGS 64
#define EV_ROOM (8u << 20)
#define ACT_ROOM ((uint64_t)LIBP2P_ACTIONS_MIN + (4u << 20))

typedef struct {
    uint64_t handle;
    int used, outbound, opened, inbound, eof, reset, failed;
    uint64_t protocol, index, tag;
    uint8_t *data;
    size_t len, cap;
} stream_rec;

typedef struct {
    uint64_t handle, direction, id_len, transport;
    uint8_t id[48];
    int up;
} peer_rec;

typedef struct {
    uint64_t handle;
    uint8_t data[256];
    size_t len;
    int status;            /* 0 waiting, else MSG_NEW, MSG_DUPLICATE, MSG_DROPPED */
} msg_rec;

/* A PARTIAL action: the first bytes of each part. */
typedef struct {
    uint64_t peer, flags, tlen, glen, mlen, dlen;
    uint8_t topic[32], group[32], meta[32], data[64];
} partial_rec;
#define MAX_PARTIALS 16

typedef struct {
    int used, silent, dead;   /* silent: dials to it never connect; dead: it gets no bytes */
    int quic;                 /* QUIC on: it gets datagrams at its UDP address */
    void *state, *scratch;
    uint8_t *events, *actions;
    uint64_t now, state_size;
    stream_rec streams[MAX_STREAMS];
    peer_rec peers[MAX_PEERS];
    msg_rec msgs[MAX_MSGS];
    int nmsgs, new_msgs, dup_msgs;
    uint64_t verdict;                  /* validation result for new messages */
    int dial_failed[16], stream_failed[16], connected_events, disconnected_events, published, peer_topics;
    uint64_t last_status;
    partial_rec partials[MAX_PARTIALS];
    int npartials;
    uint64_t pp_peer[MAX_PEERS], pp_flags[MAX_PEERS];  /* the last PARTIAL_PEERS */
    int pp_count, pp_seen;
    uint64_t pg_peer[MAX_PEERS];                        /* every peer of PARTIAL_GOSSIP */
    int pg_count, pg_seen;
} node;

static node nodes[MAX_NODES];

/* A connection between two nodes: the handle on each side. */
typedef struct {
    int a, b, used;
    uint64_t ca, cb;
} link_rec;
#define MAX_LINKS 128
static link_rec links[MAX_LINKS];

/* A dial in flight: node a, its connection, the target and the token the target got. */
typedef struct {
    int a, b, used;
    uint64_t ca, token;
} dial_rec;
static dial_rec dials[MAX_LINKS];
static uint64_t next_token = 1000;

/* QUIC: the nodes made next have QUIC on; every n-th datagram is lost. */
static int with_quic;
static uint64_t datagrams, drop_every, dropped;

/* The UDP address of node i: 10.0.0.(i + 1), port 7000 + i. */
static libp2p_addr udp_addr(int i) {
    libp2p_addr a;
    memset(&a, 0, sizeof a);
    a.family = 4;
    a.port = (uint64_t)(7000 + i);
    a.ip[0] = 10;
    a.ip[3] = (uint8_t)(i + 1);
    return a;
}

static void *ev_add(node *n, uint64_t kind, uint64_t size) {
    uint64_t *h = (uint64_t *)n->events;
    size = (size + 7) & ~7ull;
    if (h[2] + size > EV_ROOM - 24) {
        fprintf(stderr, "event room\n");
        exit(2);
    }
    uint8_t *p = n->events + 24 + h[2];
    memset(p, 0, size);
    ((uint64_t *)p)[0] = size;
    ((uint64_t *)p)[1] = kind;
    h[2] += size;
    return p;
}

typedef struct {
    int key_type;
    uint64_t muxers, max_connections, d, d_low, d_high, d_lazy, scoring;
    int clone;                         /* 1 + the index of a node whose key this node uses, or 0 */
    int v11;                           /* 1: gossipsub v1.1 only */
    int no_idontwant;                  /* 1: no IDONTWANT sent, none heard */
    int partial;                       /* 1: gossipsub v1.3 and the Partial Messages extension */
} node_opts;

typedef struct {
    libp2p_config c;
    libp2p_proto p[2];
} config_rec;

static void config_for(config_rec *cfg, int index, const node_opts *o) {
    libp2p_config *c = &cfg->c;
    memset(cfg, 0, sizeof *cfg);
    c->size = sizeof *cfg;
    c->key_type = (uint64_t)o->key_type;
    int key = o->clone ? o->clone - 1 : index;
    for (int i = 0; i < 32; i++) {
        c->private_key[i] = (uint8_t)(key * 31 + i + 1);
        c->entropy[i] = (uint8_t)(index * 17 + i * 3);
    }
    c->now = 1000;
    c->max_connections = o->max_connections ? o->max_connections : 8;
    c->max_streams = 64;
    c->max_peers = c->max_connections > 16 ? c->max_connections : 16;
    c->max_topics = 8;
    c->heap_size = 1 << 22;
    c->seen_capacity = 1024;
    c->mcache_capacity = 256;
    c->pending_capacity = 64;
    c->muxers = o->muxers ? o->muxers : 3;
    c->send_window = 1 << 18;
    c->max_rpc = 1 << 20;
    c->max_data = 1 << 19;
    c->handshake_ms = 10000;
    c->validation_ms = 5000;
    c->stream_queue = 1 << 20;
    c->protocols = sizeof cfg->c;
    c->protocols_count = 2;
    cfg->p[0].len = 11;
    memcpy(cfg->p[0].bytes, "/test/1.0.0", 11);
    cfg->p[1].len = 11;
    memcpy(cfg->p[1].bytes, "/echo/1.0.0", 11);
    c->d = o->d ? o->d : 8;
    c->d_low = o->d ? o->d_low : 6;
    c->d_high = o->d ? o->d_high : 12;
    c->d_lazy = o->d ? o->d_lazy : 6;
    c->d_score = c->d_low < 4 ? c->d_low : 4;
    c->d_out = c->d_low < 2 ? c->d_low : 2;
    c->heartbeat_ms = 700;
    c->fanout_ttl_ms = 60000;
    c->mcache_len = 6;
    c->mcache_gossip = 3;
    c->seen_ttl_ms = 120000;
    c->prune_backoff_ms = 60000;
    c->unsub_backoff_ms = 10000;
    c->graft_flood_ms = 10000;
    c->flood_publish = 1;
    c->gossip_factor = 0.25;
    c->max_ihave_length = 5000;
    c->max_ihave_messages = 10;
    c->iwant_followup_ms = 3000;
    c->retransmission = 3;
    c->opportunistic_ticks = 60;
    c->opportunistic_peers = 2;
    if (o->scoring) {
        c->scoring = 1;
        c->gossip_threshold = -10;
        c->publish_threshold = -50;
        c->graylist_threshold = -80;
        c->accept_px_threshold = 100;
        c->opportunistic_threshold = 5;
        c->decay_interval_ms = 1000;
        c->decay_to_zero = 0.01;
        c->retain_score_ms = 10000;
        c->app_weight = 1;
        c->ip_weight = -1;
        c->ip_threshold = 10;
        c->behaviour_weight = -10;
        c->behaviour_threshold = 0;
        c->behaviour_decay = 0.9;
        c->topic_cap = 100;
    }
    c->agent_len = 10;
    memcpy(c->agent, "asm-runner", 10);
    c->pv_len = 10;
    memcpy(c->pv, "ipfs/0.1.0", 10);
    c->gossipsub_v12 = !o->v11;
    c->idontwant_threshold = o->no_idontwant ? 0 : 1024;   /* go-libp2p-pubsub IDontWantMessageThreshold */
    c->dontwant_slots = o->no_idontwant ? 0 : 64;
    c->dontwant_ttl = 3;                                    /* IDontWantMessageTTL */
    c->max_idontwant_messages = 1000;                       /* MaxIDontWantMessages */
    c->max_idontwant_length = 10;                           /* MaxIDontWantLength */
    c->gossipsub_v13 = (uint64_t)o->partial;
    c->partial_messages = (uint64_t)o->partial;
    if (with_quic) {
        c->quic = LIBP2P_QUIC_ON | LIBP2P_QUIC_ACCEPT;
        c->quic_heap = 1 << 22;
        c->quic_idle_ms = 30000;
        c->quic_keep_alive_ms = 10000;
        c->quic_max_data = 1 << 22;
        c->quic_stream_data = 1 << 20;
        c->quic_max_streams = 64;
        c->quic_sent = 256;
        c->quic_window = 1 << 18;
    }
}

static void make_node(int index, const node_opts *o) {
    node *n = &nodes[index];
    config_rec cfg;
    config_for(&cfg, index, o);
    uint64_t size = 0;
    uint64_t st = call(F_STATE_SIZE, &cfg, &size, 0, 0, 0, 0);
    CHECK(st == LIBP2P_OK, "state_size status %llu", (unsigned long long)st);
    memset(n, 0, sizeof *n);
    n->used = 1;
    n->state_size = size;
    n->state = xmalloc(size);
    ((uint64_t *)n->state)[0] = size;
    st = call(F_INIT, &cfg, n->state, 0, 0, 0, 0);
    CHECK(st == LIBP2P_OK, "init status %llu", (unsigned long long)st);
    n->scratch = xmalloc(LIBP2P_SCRATCH_SIZE);
    ((uint64_t *)n->scratch)[0] = LIBP2P_SCRATCH_SIZE;
    n->events = xmalloc(EV_ROOM);
    n->actions = xmalloc(ACT_ROOM);
    ((uint64_t *)n->events)[0] = EV_ROOM;
    ((uint64_t *)n->events)[1] = 24;
    n->now = 1000;
    n->verdict = LIBP2P_ACCEPT;
    n->quic = with_quic;
}

static void free_nodes(void) {
    for (int i = 0; i < MAX_NODES; i++) {
        node *n = &nodes[i];
        if (!n->used) continue;
        for (int k = 0; k < MAX_STREAMS; k++) free(n->streams[k].data);
        free(n->state);
        free(n->scratch);
        free(n->events);
        free(n->actions);
        memset(n, 0, sizeof *n);
    }
    memset(links, 0, sizeof links);
    memset(dials, 0, sizeof dials);
    next_token = 1000;
    datagrams = drop_every = dropped = 0;
}

static const uint8_t *peer_id(int index, uint64_t *len) {
    uint8_t *s = nodes[index].state;
    *len = *(uint64_t *)(s + 152);                    /* ST_PEER_ID_LEN, include/state.inc */
    return s + 160;                                   /* ST_PEER_ID */
}

static void dial(int a, int b, int id_of) {
    ev_dial *d = ev_add(&nodes[a], EV_DIAL, sizeof *d);
    d->tag = (uint64_t)(100 + b);
    d->addr.family = 4;
    d->addr.port = (uint64_t)(9000 + b);
    d->addr.ip[0] = 10;
    d->addr.ip[3] = (uint8_t)(b + 1);
    uint64_t len;
    const uint8_t *id = peer_id(id_of, &len);
    d->id_len = len;
    memcpy(d->id, id, len);
}

/* Node a dials node b over QUIC, expecting the peer ID of node id_of. */
static void dial_quic(int a, int b, int id_of) {
    ev_dial *d = ev_add(&nodes[a], EV_DIAL, sizeof *d);
    d->tag = (uint64_t)(100 + b);
    d->addr = udp_addr(b);
    uint64_t len;
    const uint8_t *id = peer_id(id_of, &len);
    d->id_len = len;
    memcpy(d->id, id, len);
    d->transport = LIBP2P_QUIC;
    d->socket = 0;
}

static stream_rec *stream_of(node *n, uint64_t h, int make) {
    stream_rec *free_slot = NULL;
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (n->streams[i].used && n->streams[i].handle == h) return &n->streams[i];
        if (!n->streams[i].used && !free_slot) free_slot = &n->streams[i];
    }
    if (!make || !free_slot) return NULL;
    memset(free_slot, 0, sizeof *free_slot);
    free_slot->used = 1;
    free_slot->handle = h;
    return free_slot;
}

static peer_rec *peer_of(node *n, uint64_t h) {
    for (int i = 0; i < MAX_PEERS; i++)
        if (n->peers[i].up && n->peers[i].handle == h) return &n->peers[i];
    return NULL;
}

static int peers_up(node *n) {
    int c = 0;
    for (int i = 0; i < MAX_PEERS; i++) c += n->peers[i].up;
    return c;
}

/* The handle at node x of its peer node y, or 0. */
static uint64_t peer_handle(int x, int y) {
    uint64_t len;
    const uint8_t *id = peer_id(y, &len);
    for (int i = 0; i < MAX_PEERS; i++) {
        peer_rec *p = &nodes[x].peers[i];
        if (p->up && p->id_len == len && !memcmp(p->id, id, len)) return p->handle;
    }
    return 0;
}

static void deliver(int to, uint64_t conn, const uint8_t *data, uint64_t count) {
    while (count) {
        uint64_t k = count > LIBP2P_RECEIVE_MAX ? LIBP2P_RECEIVE_MAX : count;
        ev_received *e = ev_add(&nodes[to], EV_RECEIVED, 32 + k);
        e->conn = conn;
        e->count = k;
        memcpy(e->data, data, k);
        data += k;
        count -= k;
    }
}

static link_rec *link_of(int n, uint64_t conn, int *other, uint64_t *other_conn) {
    for (int i = 0; i < MAX_LINKS; i++) {
        link_rec *l = &links[i];
        if (!l->used) continue;
        if (l->a == n && l->ca == conn) {
            *other = l->b;
            *other_conn = l->cb;
            return l;
        }
        if (l->b == n && l->cb == conn) {
            *other = l->a;
            *other_conn = l->ca;
            return l;
        }
    }
    return NULL;
}

/* The shell part: DIAL, ADOPT, REFUSE, SEND and CLOSE. */
static void shell_action(int i, uint8_t *p) {
    node *n = &nodes[i];
    libp2p_header *h = (libp2p_header *)p;
    switch (h->kind) {
    case ACT_DIAL: {
        act_dial *a = (act_dial *)p;
        int b = (int)a->addr.port - 9000;
        if (b < 0 || b >= MAX_NODES || !nodes[b].used) {
            ev_conn *e = ev_add(n, EV_DIAL_FAILED, 32);
            e->conn = a->conn;
            e->value = 111;                           /* ECONNREFUSED */
            break;
        }
        if (nodes[b].silent) break;                   /* the SYN is never answered */
        for (int k = 0; k < MAX_LINKS; k++)
            if (!dials[k].used) {
                dials[k] = (dial_rec){i, b, 1, a->conn, next_token};
                ev_accepted *e = ev_add(&nodes[b], EV_ACCEPTED, sizeof *e);
                e->token = next_token++;
                e->addr.family = 4;
                e->addr.port = (uint64_t)(40000 + i);
                e->addr.ip[0] = 10;
                e->addr.ip[3] = (uint8_t)(i + 1);
                break;
            }
        break;
    }
    case ACT_ADOPT:
    case ACT_REFUSE: {
        act_adopt *a = (act_adopt *)p;
        for (int k = 0; k < MAX_LINKS; k++) {
            dial_rec *d = &dials[k];
            if (!d->used || d->b != i || d->token != a->token) continue;
            d->used = 0;
            if (h->kind == ACT_REFUSE) {              /* the listener closes the socket: the dial fails */
                ev_conn *e = ev_add(&nodes[d->a], EV_DIAL_FAILED, 32);
                e->conn = d->ca;
                e->value = 104;                       /* ECONNRESET */
                break;
            }
            for (int m = 0; m < MAX_LINKS; m++)
                if (!links[m].used) {
                    links[m] = (link_rec){d->a, i, 1, d->ca, a->conn};
                    break;
                }
            ev_conn *e = ev_add(&nodes[d->a], EV_CONNECTED, 24);
            e->conn = d->ca;
            break;
        }
        break;
    }
    case ACT_SEND: {
        act_send *a = (act_send *)p;
        int o;
        uint64_t oc;
        if (!link_of(i, a->conn, &o, &oc)) break;
        if (!nodes[o].dead) deliver(o, oc, a->data, a->count);
        ev_conn *e = ev_add(n, EV_SENT, 32);
        e->conn = a->conn;
        e->value = a->count;
        break;
    }
    case ACT_SEND_DATAGRAM: {
        act_datagram *a = (act_datagram *)p;
        int b = (int)a->addr.port - 7000;
        datagrams++;
        if (b < 0 || b >= MAX_NODES || !nodes[b].used || !nodes[b].quic || nodes[b].dead) break;
        if (drop_every && datagrams % drop_every == 0) {
            dropped++;
            break;
        }
        ev_datagram *e = ev_add(&nodes[b], EV_DATAGRAM, sizeof *e + a->count);
        e->socket = 0;
        e->addr = udp_addr(i);
        e->count = a->count;
        memcpy(e->data, a->data, a->count);
        break;
    }
    case ACT_CLOSE: {
        act_send *a = (act_send *)p;
        int o;
        uint64_t oc;
        link_rec *l = link_of(i, a->conn, &o, &oc);
        ev_conn *e = ev_add(n, EV_CLOSED, 32);
        e->conn = a->conn;
        if (l) {
            l->used = 0;
            ev_conn *f = ev_add(&nodes[o], EV_CLOSED, 32);
            f->conn = oc;
        }
        for (int k = 0; k < MAX_LINKS; k++)          /* a dial still in flight */
            if (dials[k].used && dials[k].a == i && dials[k].ca == a->conn) dials[k].used = 0;
        break;
    }
    default: break;
    }
}

static void app_action(int i, uint8_t *p) {
    node *n = &nodes[i];
    libp2p_header *h = (libp2p_header *)p;
    switch (h->kind) {
    case ACT_PEER_CONNECTED: {
        act_peer_connected *a = (act_peer_connected *)p;
        n->connected_events++;
        for (int k = 0; k < MAX_PEERS; k++)
            if (!n->peers[k].up) {
                n->peers[k].up = 1;
                n->peers[k].handle = a->peer;
                n->peers[k].direction = a->direction;
                n->peers[k].transport = a->transport;
                n->peers[k].id_len = a->id_len;
                memcpy(n->peers[k].id, a->id, a->id_len);
                break;
            }
        break;
    }
    case ACT_PEER_DISCONNECTED: {
        act_peer_disconnected *a = (act_peer_disconnected *)p;
        n->disconnected_events++;
        peer_rec *r = peer_of(n, a->peer);
        if (r) r->up = 0;
        break;
    }
    case ACT_DIAL_FAILED: n->dial_failed[((act_failed *)p)->reason & 15]++; break;
    case ACT_STREAM_FAILED: n->stream_failed[((act_failed *)p)->reason & 15]++; break;
    case ACT_STREAM_OPENED: {
        act_stream_opened *a = (act_stream_opened *)p;
        stream_rec *s = stream_of(n, a->stream, 1);
        if (!s) break;
        s->outbound = 1;
        s->opened = 1;
        s->index = a->index;
        s->tag = a->tag;
        break;
    }
    case ACT_STREAM_INBOUND: {
        act_stream_inbound *a = (act_stream_inbound *)p;
        stream_rec *s = stream_of(n, a->stream, 1);
        if (!s) break;
        s->inbound = 1;
        s->protocol = a->protocol;
        break;
    }
    case ACT_STREAM_DATA: {
        act_stream_data *a = (act_stream_data *)p;
        stream_rec *s = stream_of(n, a->stream, 0);
        if (!s) break;
        if (s->len + a->count > s->cap) {
            s->cap = (s->len + a->count) * 2;
            s->data = realloc(s->data, s->cap);
        }
        memcpy(s->data + s->len, a->data, a->count);
        s->len += a->count;
        break;
    }
    case ACT_STREAM_EOF: {
        stream_rec *s = stream_of(n, ((act_stream_data *)p)->stream, 0);
        if (s) s->eof = 1;
        break;
    }
    case ACT_STREAM_RESET: {
        stream_rec *s = stream_of(n, ((act_stream_data *)p)->stream, 0);
        if (s) s->reset = 1;
        break;
    }
    case ACT_MESSAGE: {
        act_message *a = (act_message *)p;
        const uint8_t *data = (const uint8_t *)n->state + a->data_off;
        ev_message_id *e = ev_add(n, EV_MESSAGE_ID, sizeof *e);
        e->handle = a->handle;
        e->id_len = 20;
        msg_id(data, a->data_len, e->id);
        if (n->nmsgs < MAX_MSGS) {
            msg_rec *m = &n->msgs[n->nmsgs++];
            m->handle = a->handle;
            m->len = a->data_len < sizeof m->data ? a->data_len : sizeof m->data;
            memcpy(m->data, data, m->len);
        }
        break;
    }
    case ACT_MESSAGE_STATUS: {
        act_message_status *a = (act_message_status *)p;
        for (int k = n->nmsgs - 1; k >= 0; k--)
            if (n->msgs[k].handle == a->handle && !n->msgs[k].status) {
                n->msgs[k].status = (int)a->status;
                break;
            }
        if (a->status == MSG_NEW) {
            n->new_msgs++;
            ev_conn *e = ev_add(n, EV_VALIDATION, 32);
            e->conn = a->handle;
            e->value = n->verdict;
        } else if (a->status == MSG_DUPLICATE) {
            n->dup_msgs++;
        }
        break;
    }
    case ACT_PUBLISHED: n->published++; break;
    case ACT_PEER_TOPIC: n->peer_topics += ((act_peer_topic *)p)->subscribed ? 1 : -1; break;
    case ACT_PARTIAL: {
        act_partial *a = (act_partial *)p;
        if (n->npartials >= MAX_PARTIALS) break;
        partial_rec *r = &n->partials[n->npartials++];
        const uint8_t *st = n->state;
        r->peer = a->peer;
        r->flags = a->flags;
        r->tlen = a->topic_len;
        r->glen = a->group_len;
        r->mlen = a->meta_len;
        r->dlen = a->msg_len;
        memcpy(r->topic, a->topic, a->topic_len < 32 ? a->topic_len : 32);
        memcpy(r->group, st + a->group_off, a->group_len < 32 ? a->group_len : 32);
        if (a->meta_len) memcpy(r->meta, st + a->meta_off, a->meta_len < 32 ? a->meta_len : 32);
        if (a->msg_len) memcpy(r->data, st + a->msg_off, a->msg_len < 64 ? a->msg_len : 64);
        break;
    }
    case ACT_PARTIAL_PEERS: {
        act_partial_list *a = (act_partial_list *)p;
        const uint64_t *e = (const uint64_t *)(a->topic + ((a->topic_len + 7) & ~7ull));
        n->pp_seen++;
        n->pp_count = 0;
        for (uint64_t k = 0; k < a->count && k < MAX_PEERS; k++) {
            n->pp_peer[k] = e[2 * k];
            n->pp_flags[k] = e[2 * k + 1];
            n->pp_count++;
        }
        break;
    }
    case ACT_PARTIAL_GOSSIP: {
        act_partial_list *a = (act_partial_list *)p;
        const uint64_t *e = (const uint64_t *)(a->topic + ((a->topic_len + 7) & ~7ull));
        n->pg_seen++;
        for (uint64_t k = 0; k < a->count; k++) {
            int have = 0;
            for (int m = 0; m < n->pg_count; m++) have |= n->pg_peer[m] == e[k];
            if (!have && n->pg_count < MAX_PEERS) n->pg_peer[n->pg_count++] = e[k];
        }
        break;
    }
    default: break;
    }
}

/* One step of node i: returns the actions besides WAKEUP. */
static int step(int i) {
    node *n = &nodes[i];
    libp2p_tick t;
    t.now = n->now;
    for (int k = 0; k < 32; k++) t.entropy[k] = (uint8_t)(k * 13 + n->now + (uint64_t)i * 7);
    t.us = n->now * 1000;
    t.unix_time = 1794700800 + n->now / 1000;        /* 2026-11-15 */
    uint64_t *ah = (uint64_t *)n->actions;
    ah[0] = ACT_ROOM;
    uint64_t result = 0;
    uint64_t st = call(F_STEP, n->state, &t, n->events, n->scratch, n->actions, &result);
    n->last_status = st;
    fnv(&i, sizeof i);
    fnv(&st, 8);
    if (st) return 0;
    uint64_t *eh = (uint64_t *)n->events;
    uint8_t *e = n->events + 24;
    uint64_t off = 0;
    for (uint64_t k = 0; k < result; k++) off += ((uint64_t *)(e + off))[0];
    memmove(e, e + off, eh[2] - off);
    eh[2] -= off;
    int count = 0;
    uint8_t *p = n->actions + ah[1], *end = p + ah[2];
    while (p < end) {
        libp2p_header *h = (libp2p_header *)p;
        fnv(p, h->size);
        if (h->kind <= ACT_CLOSE || h->kind == ACT_SEND_DATAGRAM) shell_action(i, p);
        else app_action(i, p);
        if (h->kind != ACT_WAKEUP) count++;
        p += h->size;
    }
    return count;
}

/* Rounds of every node, then dt ms. Ends early when no node acts and no events wait. */
static void run(int rounds, uint64_t dt, int until_idle) {
    for (int r = 0; r < rounds; r++) {
        int busy = 0;
        for (int i = 0; i < MAX_NODES; i++)
            if (nodes[i].used) busy += step(i);
        for (int i = 0; i < MAX_NODES; i++)
            if (nodes[i].used) {
                busy += ((uint64_t *)nodes[i].events)[2] != 0;
                nodes[i].now += dt;
            }
        if (until_idle && !busy) break;
    }
}

/* Rounds until the nodes are idle; with lost datagrams, 4 s, for the retransmission timers of QUIC. */
static void settle(void) {
    if (drop_every) run(400, 10, 0);
    else run(60, 10, 1);
}

static void open_stream(int a, int b, int nprotos, const char *const *protos, uint64_t tag) {
    ev_open_stream *o = ev_add(&nodes[a], EV_OPEN_STREAM, sizeof *o + (uint64_t)nprotos * sizeof(libp2p_proto));
    o->peer = peer_handle(a, b);
    o->tag = tag;
    o->count = (uint64_t)nprotos;
    for (int k = 0; k < nprotos; k++) {
        o->protocols[k].len = strlen(protos[k]);
        memcpy(o->protocols[k].bytes, protos[k], strlen(protos[k]));
    }
}

static stream_rec *stream_by_tag(int a, uint64_t tag) {
    for (int k = 0; k < MAX_STREAMS; k++)
        if (nodes[a].streams[k].used && nodes[a].streams[k].opened && nodes[a].streams[k].tag == tag)
            return &nodes[a].streams[k];
    return NULL;
}

static stream_rec *inbound_stream(int b) {
    for (int k = MAX_STREAMS - 1; k >= 0; k--)
        if (nodes[b].streams[k].used && nodes[b].streams[k].inbound) return &nodes[b].streams[k];
    return NULL;
}

static void write_stream(int a, uint64_t stream, const void *data, uint64_t n) {
    ev_stream_write *w = ev_add(&nodes[a], EV_STREAM_WRITE, 32 + n);
    w->stream = stream;
    w->count = n;
    memcpy(w->data, data, n);
}

static void stream_event(int a, uint64_t kind, uint64_t stream) {
    ev_conn *c = ev_add(&nodes[a], kind, 24);
    c->conn = stream;
}

static void topic_event(int a, uint64_t kind, const char *topic) {
    size_t tl = strlen(topic);
    uint8_t *e = ev_add(&nodes[a], kind, 24 + tl);
    ((uint64_t *)e)[2] = tl;
    memcpy(e + 24, topic, tl);
}

static void publish_n(int a, const char *topic, const void *msg, size_t ml) {
    size_t tl = strlen(topic), tla = (tl + 7) & ~7ul;
    uint8_t *e = ev_add(&nodes[a], EV_PUBLISH, 72 + tla + ml);
    ((uint64_t *)e)[2] = 20;
    msg_id(msg, ml, e + 24);
    ((uint64_t *)e)[7] = tl;
    ((uint64_t *)e)[8] = ml;
    memcpy(e + 72, topic, tl);
    memcpy(e + 72 + tla, msg, ml);
}

static void publish(int a, const char *topic, const char *msg) { publish_n(a, topic, msg, strlen(msg)); }

static void partial_subscribe(int a, const char *topic, uint64_t flags) {
    size_t tl = strlen(topic);
    ev_partial_subscribe *e = ev_add(&nodes[a], EV_PARTIAL_SUBSCRIBE, sizeof *e + tl);
    e->flags = flags;
    e->topic_len = tl;
    memcpy(e->topic, topic, tl);
}

static void partial_peers(int a, const char *topic) {
    size_t tl = strlen(topic);
    ev_partial_peers *e = ev_add(&nodes[a], EV_PARTIAL_PEERS, sizeof *e + tl);
    e->topic_len = tl;
    memcpy(e->topic, topic, tl);
}

/* PARTIAL_SEND from node a to its peer node b; NULL or "" leaves a part out. */
static void partial_send(int a, int b, const char *topic, const char *group, const char *meta, const char *msg) {
    size_t tl = strlen(topic), gl = strlen(group), ml = meta ? strlen(meta) : 0, dl = msg ? strlen(msg) : 0;
    size_t ta = (tl + 7) & ~7ul, ga = (gl + 7) & ~7ul, ma = (ml + 7) & ~7ul;
    ev_partial_send *e = ev_add(&nodes[a], EV_PARTIAL_SEND, sizeof *e + ta + ga + ma + dl);
    e->peer = peer_handle(a, b);
    e->topic_len = tl;
    e->group_len = gl;
    e->meta_len = ml;
    e->msg_len = dl;
    memcpy(e->bytes, topic, tl);
    memcpy(e->bytes + ta, group, gl);
    if (ml) memcpy(e->bytes + ta + ga, meta, ml);
    if (dl) memcpy(e->bytes + ta + ga + ma, msg, dl);
}

static void partial_score(int a, int b, const char *topic, uint64_t result) {
    size_t tl = strlen(topic);
    ev_partial_score *e = ev_add(&nodes[a], EV_PARTIAL_SCORE, sizeof *e + tl);
    e->peer = peer_handle(a, b);
    e->result = result;
    e->topic_len = tl;
    memcpy(e->topic, topic, tl);
}

/* The PARTIAL actions node a got from node b with these parts; NULL matches a part left out. */
static int partials_from(int a, int b, const char *group, const char *meta, const char *msg) {
    uint64_t h = peer_handle(a, b);
    int c = 0;
    for (int k = 0; k < nodes[a].npartials; k++) {
        partial_rec *r = &nodes[a].partials[k];
        size_t ml = meta ? strlen(meta) : 0, dl = msg ? strlen(msg) : 0;
        c += r->peer == h && r->glen == strlen(group) && !memcmp(r->group, group, r->glen) && r->mlen == ml &&
             !memcmp(r->meta, meta ? meta : "", ml) && r->dlen == dl && !memcmp(r->data, msg ? msg : "", dl);
    }
    return c;
}

/* The flags of node b in the last PARTIAL_PEERS of node a, or -1 when it is not there. */
static int64_t pp_flags_of(int a, int b) {
    uint64_t h = peer_handle(a, b);
    for (int k = 0; k < nodes[a].pp_count; k++)
        if (nodes[a].pp_peer[k] == h) return (int64_t)nodes[a].pp_flags[k];
    return -1;
}

static int pg_has(int a, int b) {
    uint64_t h = peer_handle(a, b);
    for (int k = 0; k < nodes[a].pg_count; k++)
        if (nodes[a].pg_peer[k] == h) return 1;
    return 0;
}

/* MESSAGE actions with these bytes, whatever their status. */
static int seen_with(int a, const char *msg) {
    int c = 0;
    for (int k = 0; k < nodes[a].nmsgs; k++)
        c += nodes[a].msgs[k].len == strlen(msg) && !memcmp(nodes[a].msgs[k].data, msg, strlen(msg));
    return c;
}

static int new_with(int a, const char *msg) {
    int c = 0;
    for (int k = 0; k < nodes[a].nmsgs; k++)
        if (nodes[a].msgs[k].status == MSG_NEW && nodes[a].msgs[k].len == strlen(msg) &&
            !memcmp(nodes[a].msgs[k].data, msg, strlen(msg)))
            c++;
    return c;
}

/* ---------------------------------------------------------------- Scenarios */

/* Config checks: every out-of-range field gives INVALID_CONFIG; a short state gives BUFFER_TOO_SMALL. */
static void s_config(void) {
    config_rec cfg, bad;
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    config_for(&cfg, 0, &o);
    uint64_t size = 0;
    CHECK(call(F_STATE_SIZE, &cfg, &size, 0, 0, 0, 0) == LIBP2P_OK, "valid config");
    fnv(&size, 8);
#define BAD(field_change)                                                                                             \
    do {                                                                                                              \
        bad = cfg;                                                                                                    \
        field_change;                                                                                                 \
        uint64_t s2 = 0;                                                                                              \
        uint64_t st = call(F_STATE_SIZE, &bad, &s2, 0, 0, 0, 0);                                                      \
        CHECK(st == LIBP2P_INVALID_CONFIG, "%s gave %llu", #field_change, (unsigned long long)st);                    \
    } while (0)
    BAD(bad.c.key_type = 0);
    BAD(bad.c.key_type = 3);
    BAD(bad.c.muxers = 0);
    BAD(bad.c.muxers = 4);
    BAD(bad.c.max_connections = 0);
    BAD(bad.c.max_peers = bad.c.max_connections - 1);
    BAD(bad.c.heap_size = (1 << 22) + 8);
    BAD(bad.c.send_window = 131071);
    BAD(bad.c.max_data = bad.c.max_rpc + 1);
    BAD(bad.c.d_low = bad.c.d + 1);
    BAD(bad.c.max_ihave_length = 8193);
    BAD(bad.c.agent_len = 65);
    BAD(bad.c.pv_len = 33);
    BAD(bad.c.gossipsub_v12 = 2);
    BAD(bad.c.dontwant_slots = 4097);
    BAD(bad.c.dontwant_ttl = 0);
    BAD(bad.c.gossipsub_v13 = 2);
    BAD((bad.c.gossipsub_v13 = 1, bad.c.gossipsub_v12 = 0));
    BAD(bad.c.partial_messages = 2);
    BAD(bad.c.partial_messages = 1);
    BAD(bad.c.protocols_count = 65);
    BAD(bad.p[0].len = 0);
    BAD(bad.p[1].bytes[3] = '\n');
    BAD(bad.c.size = sizeof bad.c + sizeof(libp2p_proto));
    BAD(bad.c.quic = LIBP2P_QUIC_ACCEPT);
    BAD(bad.c.quic = 4);
    /* QUIC on: its own fields, and the fields of the asm-quic config. */
    with_quic = 1;
    config_rec q;
    config_for(&q, 0, &o);
    with_quic = 0;
    uint64_t qsize = 0;
    CHECK(call(F_STATE_SIZE, &q, &qsize, 0, 0, 0, 0) == LIBP2P_OK && qsize > size, "valid QUIC config");
    fnv(&qsize, 8);
    cfg = q;
    BAD(bad.c.quic_window = 65535);
    BAD(bad.c.quic_window = (1u << 30) + 1);
    BAD(bad.c.quic_heap = 3 << 16);
    BAD(bad.c.quic_sent = 15);
    BAD((bad.c.max_connections = 65536, bad.c.max_peers = 65536));
    BAD(bad.c.handshake_ms = 1ull << 40);
    config_for(&cfg, 0, &o);
#undef BAD
    void *state = xmalloc(size);
    ((uint64_t *)state)[0] = size - 1;
    CHECK(call(F_INIT, &cfg, state, 0, 0, 0, 0) == LIBP2P_BUFFER_TOO_SMALL, "short state");
    ((uint64_t *)state)[0] = size;
    config_rec k = cfg;
    k.c.key_type = LIBP2P_KEY_SECP256K1;
    memset(k.c.private_key, 0, 32);
    CHECK(call(F_INIT, &k, state, 0, 0, 0, 0) == LIBP2P_INVALID_KEY, "zero secp256k1 key");
    memset(k.c.private_key, 0xFF, 32);
    CHECK(call(F_INIT, &k, state, 0, 0, 0, 0) == LIBP2P_INVALID_KEY, "secp256k1 key above the order");
    CHECK(call(F_INIT, &cfg, state, 0, 0, 0, 0) == LIBP2P_OK, "valid init");
    fnv(state, (size_t)(size < 4096 ? size : 4096));
    free(state);
}

/*
 * Two nodes connect (over QUIC when quic is 1), open a stream with a fallback
 * protocol, echo, half-close, then disconnect.
 */
static void connect_pair_on(int ka, int kb, uint64_t ma, uint64_t mb, int quic) {
    node_opts oa = {ka, ma, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, ob = {kb, mb, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    with_quic = quic;
    make_node(0, &oa);
    make_node(1, &ob);
    if (quic) dial_quic(0, 1, 1);
    else dial(0, 1, 1);
    run(60, 10, 1);
    CHECK(peers_up(&nodes[0]) == 1 && peers_up(&nodes[1]) == 1, "connected %d %d", peers_up(&nodes[0]),
          peers_up(&nodes[1]));
    uint64_t h01 = peer_handle(0, 1), h10 = peer_handle(1, 0);
    CHECK(h01 && h10, "peer IDs match the keys");
    if (!h01 || !h10) return;
    CHECK(peer_of(&nodes[0], h01)->direction == 1 && peer_of(&nodes[1], h10)->direction == 0,
          "directions");
    CHECK(peer_of(&nodes[0], h01)->transport == (uint64_t)quic && peer_of(&nodes[1], h10)->transport == (uint64_t)quic,
          "transports");
    const char *protos[] = {"/nope/1.0.0", "/test/1.0.0"};
    open_stream(0, 1, 2, protos, 7);
    run(60, 10, 1);
    stream_rec *sa = stream_by_tag(0, 7), *sb = inbound_stream(1);
    CHECK(sa && sa->index == 1, "opened with the second protocol");
    CHECK(sb && sb->protocol == 0, "inbound /test/1.0.0");
    if (!sa || !sb) return;
    write_stream(0, sa->handle, "hello", 5);
    stream_event(0, EV_STREAM_CLOSE, sa->handle);
    run(60, 10, 1);
    CHECK(sb->len == 5 && !memcmp(sb->data, "hello", 5) && sb->eof, "B got hello and EOF");
    write_stream(1, sb->handle, "world", 5);
    stream_event(1, EV_STREAM_CLOSE, sb->handle);
    run(60, 10, 1);
    CHECK(sa->len == 5 && !memcmp(sa->data, "world", 5) && sa->eof, "A got world and EOF");
    ev_conn *d = ev_add(&nodes[0], EV_DISCONNECT, 24);
    d->conn = h01;
    run(60, 10, 1);
    CHECK(peers_up(&nodes[0]) == 0 && peers_up(&nodes[1]) == 0, "disconnected");
    CHECK(!sa->reset && !sb->reset, "no STREAM_RESET for a stream closed both ways");
}

static void s_yamux(void) { connect_pair_on(LIBP2P_KEY_ED25519, LIBP2P_KEY_ED25519, 1, 1, 0); }
static void s_mplex(void) { connect_pair_on(LIBP2P_KEY_SECP256K1, LIBP2P_KEY_ED25519, 2, 2, 0); }
static void s_fallback(void) { connect_pair_on(LIBP2P_KEY_SECP256K1, LIBP2P_KEY_SECP256K1, 3, 2, 0); }
static void s_mplex_first(void) { connect_pair_on(LIBP2P_KEY_ED25519, LIBP2P_KEY_SECP256K1, 2, 3, 0); }

/* QUIC: the same with Ed25519 keys, then with secp256k1 and Ed25519 keys. */
static void s_quic(void) {
    connect_pair_on(LIBP2P_KEY_ED25519, LIBP2P_KEY_ED25519, 3, 3, 1);
    free_nodes();
    connect_pair_on(LIBP2P_KEY_SECP256K1, LIBP2P_KEY_ED25519, 3, 3, 1);
}

/* No shared muxer: the dial fails in the upgrade, and no node reports a peer. */
static void s_no_muxer(void) {
    node_opts oa = {LIBP2P_KEY_ED25519, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, ob = {LIBP2P_KEY_ED25519, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &oa);
    make_node(1, &ob);
    dial(0, 1, 1);
    run(60, 10, 1);
    CHECK(nodes[0].dial_failed[2] == 1, "DIAL_FAILED handshake");
    CHECK(nodes[0].connected_events == 0 && nodes[1].connected_events == 0, "no peer");
}

/* The dialled node is not the expected peer: DIAL_FAILED with reason PEER_ID. */
static void s_peer_id(void) {
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &o);
    make_node(1, &o);
    make_node(2, &o);
    dial(0, 1, 2);
    run(60, 10, 1);
    CHECK(nodes[0].dial_failed[3] == 1, "DIAL_FAILED peer ID");
    CHECK(nodes[0].connected_events == 0 && nodes[1].connected_events == 0, "no peer: %d %d %d", nodes[0].connected_events, nodes[1].connected_events, nodes[1].disconnected_events);
}

/*
 * Refused protocols, a reset, and 1 MiB through each muxer's flow control;
 * over QUIC (quic 1), through the window of quic_window bytes in flight,
 * which STREAM_ACKED opens again.
 */
static void streams_on(uint64_t muxers, int quic) {
    node_opts o = {LIBP2P_KEY_ED25519, muxers, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    with_quic = quic;
    make_node(0, &o);
    make_node(1, &o);
    if (quic) dial_quic(0, 1, 1);
    else dial(0, 1, 1);
    settle();
    const char *nope[] = {"/nope/1.0.0"};
    open_stream(0, 1, 1, nope, 1);
    settle();
    CHECK(nodes[0].stream_failed[5] == 1, "STREAM_FAILED protocol");
    const char *echo[] = {"/echo/1.0.0"};
    open_stream(0, 1, 1, echo, 2);
    settle();
    stream_rec *sa = stream_by_tag(0, 2), *sb = inbound_stream(1);
    CHECK(sa && sb && sb->protocol == 1, "echo stream");
    if (!sa || !sb) return;
    stream_event(0, EV_STREAM_RESET, sa->handle);
    settle();
    CHECK(sb->reset, "B saw the reset");
    open_stream(0, 1, 1, echo, 3);
    settle();
    sa = stream_by_tag(0, 3);
    sb = inbound_stream(1);
    CHECK(sa && sb && !sb->reset, "second stream");
    if (!sa || !sb) return;
    static uint8_t big[1 << 20];
    for (size_t k = 0; k < sizeof big; k++) big[k] = (uint8_t)(k * 7 + (k >> 9));
    for (size_t off = 0; off < sizeof big; off += 65536) write_stream(0, sa->handle, big + off, 65536);
    stream_event(0, EV_STREAM_CLOSE, sa->handle);
    run(quic ? 2000 : 400, 10, !quic);
    CHECK(sb->len == sizeof big && !memcmp(sb->data, big, sizeof big) && sb->eof, "1 MiB in order, got %zu",
          sb->len);
}

static void s_streams_yamux(void) { streams_on(1, 0); }
static void s_streams_mplex(void) { streams_on(2, 0); }
static void s_quic_streams(void) { streams_on(3, 1); }

/* QUIC with every 7th datagram lost: the connection, a stream and 1 MiB still go through. */
static void s_quic_loss(void) {
    drop_every = 7;
    streams_on(3, 1);
    printf("  datagrams: %llu sent, %llu lost\n", (unsigned long long)datagrams, (unsigned long long)dropped);
    CHECK(dropped > 0, "no datagram was lost");
    fnv(&dropped, 8);
}

/* QUIC: a dial that reaches another peer than it names fails with PEER_ID; a node that never answers, with CONNECT. */
static void s_quic_dial_fails(void) {
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    with_quic = 1;
    for (int i = 0; i < 4; i++) make_node(i, &o);
    nodes[3].dead = 1;
    dial_quic(0, 1, 2);
    dial_quic(0, 3, 3);
    run(200, 100, 0);
    CHECK(nodes[0].dial_failed[3] == 1, "DIAL_FAILED peer ID");
    CHECK(nodes[0].dial_failed[1] == 1, "DIAL_FAILED connect");
    CHECK(nodes[0].connected_events == 0 && nodes[1].connected_events == 0, "no peer: %d %d",
          nodes[0].connected_events, nodes[1].connected_events);
}

/* Timeouts: an unanswered dial gives CONNECT; a peer that never answers gives HANDSHAKE. */
static void s_timeout(void) {
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &o);
    make_node(1, &o);
    make_node(2, &o);
    nodes[1].silent = 1;
    nodes[2].dead = 1;
    dial(0, 1, 1);
    dial(0, 2, 2);
    run(200, 100, 0);
    CHECK(nodes[0].dial_failed[1] == 1, "CONNECT timeout");
    CHECK(nodes[0].dial_failed[2] == 1, "HANDSHAKE timeout");
}

/* Garbage bytes at a listener and at a dialer close the connection; nothing breaks. */
static void s_garbage(void) {
    node_opts o = {LIBP2P_KEY_SECP256K1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &o);
    make_node(1, &o);
    nodes[1].dead = 1;                                /* node 1's core never answers; the runner sends garbage */
    dial(0, 1, 1);
    run(3, 10, 0);
    uint8_t junk[300];
    for (int k = 0; k < 300; k++) junk[k] = (uint8_t)(k * 89 + 3);
    for (int m = 0; m < MAX_LINKS; m++)
        if (links[m].used) {
            deliver(links[m].a, links[m].ca, junk, sizeof junk);
            deliver(links[m].b, links[m].cb, junk, sizeof junk);
        }
    run(60, 10, 1);
    CHECK(nodes[0].dial_failed[2] + nodes[0].dial_failed[7] == 1, "dialer failed the dial");
    CHECK(nodes[0].connected_events == 0 && nodes[1].connected_events == 0, "no peer");
    for (int m = 0; m < MAX_LINKS; m++) CHECK(!links[m].used, "connection %d closed", m);
}

/* Malformed events and short buffers: an error status, nothing accepted, the state unchanged. */
static void s_errors(void) {
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &o);
    node *n = &nodes[0];
    uint8_t *before = xmalloc(n->state_size);
    libp2p_tick t = {2000, {0}, 2000000, 1794700802};
    struct { int kind; uint64_t size; uint64_t f2; } cases[] = {
        {0, 24, 0}, {20, 24, 0}, {EV_DISCONNECT, 0, 0}, {EV_DISCONNECT, 20, 0}, {EV_DISCONNECT, 1 << 30, 0},
        {EV_STREAM_WRITE, 32, 64}, {EV_SUBSCRIBE, 24, 300}, {EV_DIAL, 112, 0},
    };
    for (size_t c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        ((uint64_t *)n->events)[2] = 0;
        uint8_t *e = ev_add(n, 1, 112);
        ((uint64_t *)e)[0] = cases[c].size;
        ((uint64_t *)e)[1] = (uint64_t)cases[c].kind;
        ((uint64_t *)e)[2] = 5;
        ((uint64_t *)e)[3] = cases[c].f2;
        if (cases[c].kind == EV_DIAL) ((uint64_t *)e)[3] = 9;      /* address family 9 */
        memcpy(before, n->state, n->state_size);
        ((uint64_t *)n->actions)[0] = ACT_ROOM;
        uint64_t result = 77;
        uint64_t st = call(F_STEP, n->state, &t, n->events, n->scratch, n->actions, &result);
        CHECK(st == LIBP2P_INVALID_EVENT, "case %zu gave %llu", c, (unsigned long long)st);
        CHECK(!memcmp(before, n->state, n->state_size), "case %zu changed the state", c);
        fnv(&st, 8);
    }
    ((uint64_t *)n->events)[2] = 0;
    topic_event(0, EV_SUBSCRIBE, "t");
    memcpy(before, n->state, n->state_size);
    ((uint64_t *)n->actions)[0] = LIBP2P_ACTIONS_MIN - 8;
    uint64_t result = 0;
    uint64_t st = call(F_STEP, n->state, &t, n->events, n->scratch, n->actions, &result);
    CHECK(st == LIBP2P_BUFFER_TOO_SMALL, "short actions gave %llu", (unsigned long long)st);
    CHECK(!memcmp(before, n->state, n->state_size), "short actions changed the state");
    ((uint64_t *)n->actions)[0] = ACT_ROOM;
    ((uint64_t *)n->scratch)[0] = LIBP2P_SCRATCH_SIZE - 8;
    st = call(F_STEP, n->state, &t, n->events, n->scratch, n->actions, &result);
    CHECK(st == LIBP2P_BUFFER_TOO_SMALL, "short scratch gave %llu", (unsigned long long)st);
    CHECK(!memcmp(before, n->state, n->state_size), "short scratch changed the state");
    ((uint64_t *)n->scratch)[0] = LIBP2P_SCRATCH_SIZE;
    st = call(F_STEP, n->state, &t, n->events, n->scratch, n->actions, &result);
    CHECK(st == LIBP2P_OK && result == 1, "the subscription then goes through");
    free(before);
    /* QUIC events: a QUIC dial and a datagram need QUIC on; a transport above QUIC, a count past the event and a
       datagram above 65535 bytes are invalid. */
    with_quic = 1;
    make_node(1, &o);
    with_quic = 0;
    for (int c = 0; c < 7; c++) {
        node *m = c < 2 ? &nodes[0] : &nodes[1];
        ((uint64_t *)m->events)[2] = 0;
        if (c == 0 || c == 2 || c == 3) {
            ev_dial *d = ev_add(m, EV_DIAL, sizeof *d);
            d->addr = udp_addr(0);
            d->transport = c == 0 ? LIBP2P_QUIC : c == 2 ? 2 : LIBP2P_TCP;
            if (c == 3) d->addr.port = 70000;
        } else {
            uint64_t count = c == 6 ? 65536 : 8;
            ev_datagram *g = ev_add(m, EV_DATAGRAM, sizeof *g + count);
            g->addr = udp_addr(0);
            g->count = c == 4 ? 16 : count;
            if (c == 5) g->addr.family = 5;
        }
        uint8_t *was = xmalloc(m->state_size);
        memcpy(was, m->state, m->state_size);
        ((uint64_t *)m->actions)[0] = ACT_ROOM;
        st = call(F_STEP, m->state, &t, m->events, m->scratch, m->actions, &result);
        CHECK(st == LIBP2P_INVALID_EVENT, "QUIC case %d gave %llu", c, (unsigned long long)st);
        CHECK(!memcmp(was, m->state, m->state_size), "QUIC case %d changed the state", c);
        fnv(&st, 8);
        free(was);
    }
    ((uint64_t *)nodes[1].events)[2] = 0;
    ev_datagram *g = ev_add(&nodes[1], EV_DATAGRAM, sizeof *g + 8);
    g->addr = udp_addr(0);
    g->count = 8;
    ((uint64_t *)nodes[1].actions)[0] = ACT_ROOM;
    st = call(F_STEP, nodes[1].state, &t, nodes[1].events, nodes[1].scratch, nodes[1].actions, &result);
    CHECK(st == LIBP2P_OK && result == 1, "a datagram of garbage goes to asm-quic");
}

/* Both nodes dial each other at once: one connection stays, each side sees one peer. */
static void s_simultaneous(void) {
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &o);
    make_node(1, &o);
    dial(0, 1, 1);
    dial(1, 0, 0);
    run(80, 10, 1);
    CHECK(peers_up(&nodes[0]) == 1 && peers_up(&nodes[1]) == 1, "one peer each: %d %d", peers_up(&nodes[0]),
          peers_up(&nodes[1]));
    int links_up = 0;
    for (int m = 0; m < MAX_LINKS; m++) links_up += links[m].used;
    CHECK(links_up == 1, "one connection, got %d", links_up);
}

/* A node with room for 2 connections refuses the third. */
static void s_limits(void) {
    node_opts small = {LIBP2P_KEY_ED25519, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0}, o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    make_node(0, &small);
    for (int i = 1; i <= 3; i++) make_node(i, &o);
    for (int i = 1; i <= 3; i++) {
        dial(i, 0, 0);
        run(60, 10, 1);
    }
    CHECK(peers_up(&nodes[0]) == 2, "node 0 has %d peers", peers_up(&nodes[0]));
    CHECK(nodes[3].connected_events == 0 && nodes[3].dial_failed[7] + nodes[3].dial_failed[1] +
          nodes[3].dial_failed[2] == 1, "the third dial failed");
}

/*
 * Six nodes in a graph: every message reaches every node once; a rejecting
 * node does not forward. quic: 0 TCP edges, 1 QUIC edges, 2 every other
 * edge QUIC.
 */
static void gossip_on(uint64_t d, uint64_t d_low, uint64_t d_high, uint64_t d_lazy, int quic) {
    node_opts o = {LIBP2P_KEY_SECP256K1, 0, 0, d, d_low, d_high, d_lazy, 0, 0, 0, 0, 0};
    with_quic = quic != 0;
    for (int i = 0; i < 6; i++) make_node(i, &o);
    static const int edges[][2] = {{0, 1}, {0, 2}, {1, 2}, {1, 3}, {2, 4}, {3, 4}, {3, 5}, {4, 5}};
    for (size_t k = 0; k < sizeof edges / sizeof edges[0]; k++) {
        if (quic == 1 || (quic == 2 && k % 2)) dial_quic(edges[k][0], edges[k][1], edges[k][1]);
        else dial(edges[k][0], edges[k][1], edges[k][1]);
    }
    run(80, 10, 1);
    for (int i = 0; i < 6; i++) topic_event(i, EV_SUBSCRIBE, "/eth2/00000000/beacon_block/ssz_snappy");
    run(40, 100, 0);                                  /* heartbeats build the meshes */
    for (int i = 0; i < 6; i++) CHECK(nodes[i].peer_topics >= 2, "node %d sees %d subscriptions", i,
                                      nodes[i].peer_topics);
    publish(0, "/eth2/00000000/beacon_block/ssz_snappy", "block-1");
    publish(0, "/eth2/00000000/beacon_block/ssz_snappy", "block-2");
    publish(5, "/eth2/00000000/beacon_block/ssz_snappy", "block-3");
    run(60, 100, 0);
    for (int i = 0; i < 6; i++) {
        CHECK(i == 0 || new_with(i, "block-1") == 1, "node %d block-1 x%d", i, new_with(i, "block-1"));
        CHECK(i == 0 || new_with(i, "block-2") == 1, "node %d block-2 x%d", i, new_with(i, "block-2"));
        CHECK(i == 5 || new_with(i, "block-3") == 1, "node %d block-3 x%d", i, new_with(i, "block-3"));
    }
    CHECK(nodes[0].published == 2 && nodes[5].published == 1, "PUBLISHED");
    /* Node 3 and node 4 reject: node 5 then hears only from them, so block-4 from node 0 stops there. */
    nodes[3].verdict = LIBP2P_REJECT;
    nodes[4].verdict = LIBP2P_REJECT;
    publish(0, "/eth2/00000000/beacon_block/ssz_snappy", "block-4");
    run(60, 100, 0);
    CHECK(new_with(3, "block-4") == 1 && new_with(4, "block-4") == 1, "3 and 4 saw block-4");
    CHECK(new_with(5, "block-4") == 0, "5 did not get block-4");
    topic_event(2, EV_UNSUBSCRIBE, "/eth2/00000000/beacon_block/ssz_snappy");
    int before = nodes[0].peer_topics;
    run(20, 100, 0);
    CHECK(nodes[0].peer_topics == before - 1, "node 0 saw node 2 leave");
}

static void s_gossip(void) { gossip_on(0, 0, 0, 0, 0); }
static void s_quic_gossip(void) { gossip_on(0, 0, 0, 0, 1); }
static void s_quic_mixed(void) { gossip_on(0, 0, 0, 0, 2); }

/*
 * A peer that dials again: node 2 has node 0's key, so node 1 sees one peer
 * dial twice. The second connection is a secondary one: no new peer. When
 * node 0 goes, node 2's connection takes over without PEER_DISCONNECTED,
 * and gossip and a new stream work through it.
 */
static void s_secondary(void) {
    const char *t = "/eth2/00000000/beacon_block/ssz_snappy";
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, c = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0};
    make_node(0, &o);
    make_node(1, &o);
    make_node(2, &c);
    dial(0, 1, 1);
    run(60, 10, 1);
    dial(2, 1, 1);
    run(60, 10, 1);
    CHECK(nodes[1].connected_events == 1 && peers_up(&nodes[1]) == 1, "node 1: one peer, %d events",
          nodes[1].connected_events);
    CHECK(nodes[0].connected_events == 1 && nodes[2].connected_events == 1, "both dials connected");
    int links_up = 0;
    for (int m = 0; m < MAX_LINKS; m++) links_up += links[m].used;
    CHECK(links_up == 2, "two connections, got %d", links_up);
    for (int i = 0; i < 3; i++) topic_event(i, EV_SUBSCRIBE, t);
    run(20, 100, 0);
    ev_conn *d = ev_add(&nodes[0], EV_DISCONNECT, 24);
    d->conn = peer_handle(0, 1);
    run(40, 100, 0);
    CHECK(nodes[1].disconnected_events == 0 && peers_up(&nodes[1]) == 1, "node 1 keeps the peer: %d %d",
          nodes[1].disconnected_events, peers_up(&nodes[1]));
    publish(2, t, "via-2");
    run(40, 100, 0);
    CHECK(new_with(1, "via-2") == 1, "node 1 got the message of node 2");
    const char *echo[] = {"/echo/1.0.0"};
    open_stream(1, 0, 1, echo, 9);
    run(60, 10, 1);
    stream_rec *s1 = stream_by_tag(1, 9), *s2 = inbound_stream(2);
    CHECK(s1 && s2, "a stream from node 1 reaches node 2");
}

static void topic_params(int a, const char *topic) {
    size_t tl = strlen(topic);
    uint8_t *e = ev_add(&nodes[a], EV_TOPIC_PARAMS, 24 + sizeof(libp2p_topic_params) + tl);
    ((uint64_t *)e)[2] = tl;
    libp2p_topic_params tp = {1, 0.01, 1000, 10, 1, 0.9, 10, 0, 0.9, 1, 10, 60000, 2000, 0, 0.9, -100, 0.99};
    memcpy(e + 24, &tp, sizeof tp);
    memcpy(e + 24 + sizeof tp, topic, tl);
}

/*
 * Peer scores: node 1 rejects two messages of node 0, so P4 takes node 0
 * below the graylist threshold at node 1; node 2 ignores them (no forward,
 * no penalty). Node 2 then sets an application score below the threshold
 * for node 0. Both nodes drop what node 0 sends next, and neither sends to
 * it: node 1 and node 2 still reach each other.
 */
static void s_scoring(void) {
    const char *t = "/eth2/00000000/voluntary_exit/ssz_snappy";
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0};
    for (int i = 0; i < 3; i++) make_node(i, &o);
    dial(0, 1, 1);
    dial(0, 2, 2);
    dial(1, 2, 2);
    run(80, 10, 1);
    for (int i = 0; i < 3; i++) {
        topic_params(i, t);
        topic_event(i, EV_SUBSCRIBE, t);
    }
    run(30, 100, 0);
    nodes[1].verdict = LIBP2P_REJECT;
    nodes[2].verdict = LIBP2P_IGNORE;
    publish(0, t, "bad-1");
    publish(0, t, "bad-2");
    run(20, 100, 0);
    CHECK(new_with(1, "bad-1") == 1 && new_with(1, "bad-2") == 1, "node 1 saw both");
    nodes[1].verdict = LIBP2P_ACCEPT;
    nodes[2].verdict = LIBP2P_ACCEPT;
    ev_conn *e = ev_add(&nodes[2], EV_APP_SCORE, 32);
    e->conn = peer_handle(2, 0);
    double low = -1000;
    memcpy(&e->value, &low, 8);
    run(20, 100, 0);
    publish(0, t, "after");
    run(40, 100, 0);
    CHECK(seen_with(1, "after") == 0 && seen_with(2, "after") == 0, "nodes 1 and 2 drop node 0: %d %d",
          seen_with(1, "after"), seen_with(2, "after"));
    publish(1, t, "from-1");
    run(40, 100, 0);
    CHECK(new_with(2, "from-1") == 1, "node 2 gets node 1's message");
    CHECK(seen_with(0, "from-1") == 0, "node 0 gets nothing: %d", seen_with(0, "from-1"));
}

static void s_gossip_lazy(void) { gossip_on(1, 1, 2, 4, 0); }

/* ---------------------------------------------------------------- Main */

typedef struct {
    const char *name;
    void (*fn)(void);
    uint64_t want;                     /* the transcript digest on ARM64; 0 before it is recorded */
} scenario_rec;

/* MESSAGE actions of a new message whose data starts with the tag. */
static int new_tagged(int a, const char *tag) {
    int c = 0;
    for (int k = 0; k < nodes[a].nmsgs; k++)
        c += nodes[a].msgs[k].status == MSG_NEW && !memcmp(nodes[a].msgs[k].data, tag, strlen(tag));
    return c;
}

/*
 * One round of gossipsub v1.2: four nodes, each connected to the others, D 3.
 * Nodes 0, 1 and 2 each publish a message of 2048 bytes, and every other
 * node gets each once. The duplicates of all nodes go to dups.
 */
static void idontwant_round(int no_idontwant, int v11_node, int *dups) {
    const char *t = "/eth2/00000000/blob_sidecar_0/ssz_snappy";
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 3, 2, 4, 0, 0, 0, 0, no_idontwant, 0}, old = o;
    old.v11 = 1;
    for (int i = 0; i < 4; i++) make_node(i, i == v11_node ? &old : &o);
    for (int a = 0; a < 4; a++)
        for (int b = a + 1; b < 4; b++) dial(a, b, b);
    run(80, 10, 1);
    for (int i = 0; i < 4; i++) topic_event(i, EV_SUBSCRIBE, t);
    run(40, 100, 0);                                  /* heartbeats build the meshes */
    static uint8_t big[2048];
    char tag[8];
    for (int k = 0; k < 3; k++) {
        memset(big, 'a' + k, sizeof big);
        snprintf(tag, sizeof tag, "big-%d", k);
        memcpy(big, tag, strlen(tag));
        publish_n(k, t, big, sizeof big);
        run(40, 100, 0);
        for (int i = 0; i < 4; i++)
            CHECK(i == k || new_tagged(i, tag) == 1, "node %d %s x%d", i, tag, new_tagged(i, tag));
    }
    *dups = 0;
    for (int i = 0; i < 4; i++) *dups += nodes[i].dup_msgs;
    free_nodes();
}

/*
 * gossipsub v1.2: with IDONTWANT, the nodes send each other fewer duplicates
 * of large messages than without it. A node of gossipsub v1.1 only gets
 * every message through /meshsub/1.1.0.
 */
static void s_idontwant(void) {
    int with, without, mixed;
    idontwant_round(0, -1, &with);
    idontwant_round(1, -1, &without);
    idontwant_round(0, 3, &mixed);
    printf("  duplicates: %d with IDONTWANT, %d without, %d with a v1.1 node\n", with, without, mixed);
    CHECK(with < without, "duplicates with IDONTWANT %d, without %d", with, without);
    fnv(&with, sizeof with);
    fnv(&without, sizeof without);
    fnv(&mixed, sizeof mixed);
}

/*
 * gossipsub v1.3 and the Partial Messages extension. Node 0 dials nodes 1, 2
 * and 3. Nodes 0 and 1 want partial messages of the topic, node 2 only sends
 * them, node 3 speaks gossipsub v1.2 only. Node 0 lists nodes 1 and 2 with
 * their flags, and node 3 not; node 1 gets data and metadata, node 2 the
 * metadata only, node 3 nothing; each PARTIAL has the flags of its sender.
 * Full messages of the topic go around node 1; a large one from node 3 gets
 * no IDONTWANT from node 0 to its partial peers. On a topic node 0 does not
 * subscribe to, PARTIAL_PEERS lists the fanout peer that wants partial
 * messages. New flags of node 2 and the leaving of node 1 change the list.
 * A node without the extension refuses PARTIAL_SUBSCRIBE with flags. Then
 * node 4 (D 1) dials nodes 5 and 6, which want partial messages: the one
 * outside its mesh comes in PARTIAL_GOSSIP at heartbeats.
 */
static void s_partial(void) {
    const char *t = "/eth2/00000000/data_column_sidecar_0/ssz_snappy";
    node_opts o = {LIBP2P_KEY_ED25519, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}, old = o;
    old.partial = 0;
    for (int i = 0; i < 4; i++) make_node(i, i == 3 ? &old : &o);
    for (int b = 1; b < 4; b++) dial(0, b, b);
    run(80, 10, 1);
    partial_subscribe(0, t, PARTIAL_REQUESTS);
    partial_subscribe(1, t, PARTIAL_REQUESTS);
    partial_subscribe(2, t, PARTIAL_SUPPORTS);
    topic_event(3, EV_SUBSCRIBE, t);
    run(40, 100, 0);
    partial_peers(0, t);
    partial_peers(1, t);
    partial_peers(3, t);
    run(4, 10, 1);
    CHECK(nodes[0].pp_seen == 1 && nodes[0].pp_count == 2, "node 0 lists %d peers", nodes[0].pp_count);
    CHECK(pp_flags_of(0, 1) == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS), "node 1 flags %lld", (long long)pp_flags_of(0, 1));
    CHECK(pp_flags_of(0, 2) == PARTIAL_SUPPORTS, "node 2 flags %lld", (long long)pp_flags_of(0, 2));
    CHECK(pp_flags_of(0, 3) == -1, "node 3 listed");
    CHECK(nodes[1].pp_count == 1 && pp_flags_of(1, 0) == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS), "node 1 lists node 0");
    CHECK(nodes[3].pp_seen == 1 && nodes[3].pp_count == 0, "node 3 lists %d peers", nodes[3].pp_count);
    partial_send(0, 1, t, "group-1", "meta-1", "cells-1");
    partial_send(0, 2, t, "group-1", "meta-2", "cells-2");
    partial_send(0, 3, t, "group-1", "meta-3", "cells-3");
    partial_send(1, 0, t, "group-1", NULL, "cells-4");
    partial_send(0, 1, t, "", "", NULL);              /* nothing to send */
    run(20, 10, 1);
    CHECK(partials_from(1, 0, "group-1", "meta-1", "cells-1") == 1, "node 1 data and metadata");
    CHECK(partials_from(2, 0, "group-1", "meta-2", NULL) == 1, "node 2 metadata only");
    CHECK(nodes[3].npartials == 0, "node 3 got %d", nodes[3].npartials);
    CHECK(partials_from(0, 1, "group-1", NULL, "cells-4") == 1, "node 0 data only");
    CHECK(nodes[1].npartials == 1 && nodes[0].npartials == 1, "extra partials %d %d", nodes[1].npartials,
          nodes[0].npartials);
    CHECK(nodes[1].partials[0].flags == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS) &&
              nodes[2].partials[0].flags == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS) &&
              nodes[0].partials[0].flags == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS),
          "flags of the senders");
    partial_score(0, 1, t, LIBP2P_ACCEPT);
    partial_score(0, 2, t, LIBP2P_REJECT);
    publish(0, t, "full-0");
    run(20, 10, 1);
    publish(3, t, "full-3");
    run(20, 10, 1);
    CHECK(seen_with(1, "full-0") == 0 && seen_with(1, "full-3") == 0, "node 1 got full messages");
    CHECK(new_with(2, "full-0") == 1 && new_with(3, "full-0") == 1, "full-0 x%d x%d", new_with(2, "full-0"),
          new_with(3, "full-0"));
    CHECK(new_with(0, "full-3") == 1 && new_with(2, "full-3") == 1, "full-3 x%d x%d", new_with(0, "full-3"),
          new_with(2, "full-3"));
    static uint8_t big[2048];
    memset(big, 'c', sizeof big);
    memcpy(big, "big-3", 5);
    publish_n(3, t, big, sizeof big);                 /* IDONTWANT from node 0: none to nodes 1 and 2 */
    run(20, 10, 1);
    CHECK(new_tagged(0, "big-3") == 1 && new_tagged(1, "big-3") == 0 && new_tagged(2, "big-3") == 1, "big-3 x%d x%d x%d",
          new_tagged(0, "big-3"), new_tagged(1, "big-3"), new_tagged(2, "big-3"));
    const char *t2 = "/eth2/00000000/data_column_sidecar_1/ssz_snappy";
    partial_subscribe(1, t2, PARTIAL_REQUESTS);
    partial_subscribe(2, t2, PARTIAL_SUPPORTS);
    run(20, 10, 1);
    partial_peers(0, t2);                            /* node 0 does not subscribe: its fanout */
    run(4, 10, 1);
    CHECK(nodes[0].pp_count == 1 && pp_flags_of(0, 1) == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS), "fanout of %d",
          nodes[0].pp_count);
    partial_subscribe(2, t, PARTIAL_REQUESTS);       /* new flags of a subscribed topic */
    topic_event(1, EV_UNSUBSCRIBE, t);
    run(20, 10, 1);
    partial_peers(0, t);
    run(4, 10, 1);
    CHECK(nodes[0].pp_count == 1 && pp_flags_of(0, 2) == (PARTIAL_REQUESTS | PARTIAL_SUPPORTS) && pp_flags_of(0, 1) == -1,
          "after the changes: %d peers", nodes[0].pp_count);
    partial_subscribe(3, t, PARTIAL_REQUESTS);        /* no extension: an invalid event */
    step(3);
    CHECK(nodes[3].last_status == LIBP2P_INVALID_EVENT, "status %llu", (unsigned long long)nodes[3].last_status);
    ((uint64_t *)nodes[3].events)[2] = 0;
    free_nodes();

    node_opts g = {LIBP2P_KEY_ED25519, 0, 0, 1, 1, 1, 2, 0, 0, 0, 0, 1};
    make_node(4, &g);
    make_node(5, &o);
    make_node(6, &o);
    dial(4, 5, 5);
    dial(4, 6, 6);
    run(80, 10, 1);
    for (int i = 4; i < 7; i++) partial_subscribe(i, t, PARTIAL_REQUESTS);
    run(40, 100, 0);
    partial_peers(4, t);
    run(4, 10, 1);
    CHECK(nodes[4].pp_count == 1, "node 4 mesh of %d", nodes[4].pp_count);
    int mesh = pp_flags_of(4, 5) >= 0 ? 5 : 6, other = 11 - mesh;
    CHECK(nodes[4].pg_seen > 0 && nodes[4].pg_count == 1 && pg_has(4, other), "node 4 gossip %d %d",
          nodes[4].pg_seen, nodes[4].pg_count);
}

static const scenario_rec SCENARIOS[] = {
    {"config", s_config, 0xf72f373fae402ed4ull},
    {"yamux", s_yamux, 0x164b55a2c482c5bfull},
    {"mplex", s_mplex, 0x549ad8c98d9c9fbbull},
    {"fallback", s_fallback, 0xb627b36b0ab9b758ull},
    {"mplex_first", s_mplex_first, 0x5a3736514fbe2d03ull},
    {"no_muxer", s_no_muxer, 0x9bcf6f37f9f50903ull},
    {"peer_id", s_peer_id, 0x3565954a455e52c8ull},
    {"streams_yamux", s_streams_yamux, 0xf7f7f5109b842668ull},
    {"streams_mplex", s_streams_mplex, 0x628872d9ca9d0b4dull},
    {"timeout", s_timeout, 0xffe7d7d1ebefd1d2ull},
    {"garbage", s_garbage, 0x72e765f2cdbb24c0ull},
    {"errors", s_errors, 0x329fbfbf00c75b86ull},
    {"simultaneous", s_simultaneous, 0xa26db6e79edaa347ull},
    {"limits", s_limits, 0xfee9c9790887921dull},
    {"gossip", s_gossip, 0x341e89b554e4b8abull},
    {"gossip_lazy", s_gossip_lazy, 0xb5393dd76d54038eull},
    {"secondary", s_secondary, 0x47ee797a462fedc8ull},
    {"scoring", s_scoring, 0x1a80df458ea9cf65ull},
    {"idontwant", s_idontwant, 0xa666643e2b9fdbd3ull},
    {"partial", s_partial, 0xddcdc2d94f6214f0ull},
    {"quic", s_quic, 0x0727621f07fed5f7ull},
    {"quic_streams", s_quic_streams, 0x7473bcae4a7110b4ull},
    {"quic_loss", s_quic_loss, 0xf19264b01055c0acull},
    {"quic_dial_fails", s_quic_dial_fails, 0x4a3c14370e4976e6ull},
    {"quic_gossip", s_quic_gossip, 0xf748cd0209e23edcull},
    {"quic_mixed", s_quic_mixed, 0x2b7c6e1130f5e5e7ull},
};

int main(int argc, char **argv) {
    int ran = 0;
    for (size_t k = 0; k < sizeof SCENARIOS / sizeof SCENARIOS[0]; k++) {
        const scenario_rec *s = &SCENARIOS[k];
        int pick = argc < 2;
        for (int a = 1; a < argc; a++) pick |= !strcmp(argv[a], s->name);
        if (!pick) continue;
        scenario = s->name;
        digest = 0xCBF29CE484222325ull;
        int before = failures;
        with_quic = 0;
        s->fn();
        free_nodes();
        if (s->want && digest != s->want) {
            failures++;
            printf("  FAIL %s: transcript digest %016llx, want %016llx\n", s->name, (unsigned long long)digest,
                   (unsigned long long)s->want);
        }
        printf("SCENARIO %s %s digest %016llx\n", s->name, failures == before ? "PASS" : "FAIL",
               (unsigned long long)digest);
        ran++;
    }
    int scenario_failures = failures;
    for (int f = 0; f < F_COUNT; f++) {
        int bad = abi_fault[f] || stack_peak[f] > STACK_CAP;
        printf("STACK %s %llu bytes%s\n", FN_NAME[f], (unsigned long long)stack_peak[f],
               abi_fault[f] ? " ABI FAULT" : "");
        if (abi_fault[f]) printf("  kept state changed: mask %llx\n", (unsigned long long)abi_fault[f]);
        if (bad) failures++;
        /* Every scenario calls every L2 function, so a function passes when nothing failed. */
        if (argc == 1) printf("FUNCTION %s %s\n", FN_NAME[f], bad || scenario_failures ? "FAIL" : "PASS");
    }
    printf("%d scenarios, %d failures\n", ran, failures);
    return failures ? 1 : 0;
}

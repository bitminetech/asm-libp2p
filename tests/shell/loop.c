/*
 * Shell loop test: two asm-libp2p nodes in one process, connected over
 * 127.0.0.1 through the shell of this OS. Standard C only, so the same file
 * runs on Linux, macOS and Windows.
 *
 * Each round: node A listens; node B dials it, with A's peer ID; both join
 * a topic. B opens an application stream, writes 256 KiB, closes its side,
 * and reads the same bytes back (A echoes, then closes). A publishes one
 * message; B gets it, gives its ID and accepts it. B disconnects; both see
 * the peer go. Round 1 uses yamux (A Ed25519, B secp256k1); round 2 mplex
 * (A secp256k1, B Ed25519). Exit 0 when both rounds pass, after a
 * "FUNCTION <name> PASS" line for each shell function, for the tick tables.
 * A failure prints FAIL and exits 1 at once.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../runner/libp2p.h"

#define EV_ROOM (4 << 20)
#define ACT_ROOM (4 << 20)
#define ECHO "/test/echo/1.0.0"
#define TOPIC "/eth2/00000000/beacon_block/ssz_snappy"
#define ECHO_LEN (256 * 1024)
#define CHUNK 16384
#define LIMIT_MS 30000
#define ST_PEER_ID_LEN 152                  /* include/state.inc */
#define ST_PEER_ID 160

typedef struct {
    const char *name;
    void *state, *scratch, *shell;
    uint8_t *ev, *act;
    uint64_t peer;                          /* the handle of the other node */
    int connected, joined, disconnected;
} node;

static node na, nb;
static uint8_t *echo_out, *echo_in;
static uint64_t echo_got, echo_stream;
static int echo_eof, published, got_message, accepted, disconnect_sent;
static const char MESSAGE[] = "asm-libp2p shell loop message";

static void fail(const char *what) {
    printf("FAIL %s\n", what);
    exit(1);
}

static uint64_t now_ms(void) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) fail("libp2p_shell_clock");
    return t.now;
}

static void random_bytes(uint8_t *p, size_t n) {
    while (n) {
        libp2p_tick t;
        if (libp2p_shell_clock(&t)) fail("libp2p_shell_clock");
        size_t k = n < 32 ? n : 32;
        memcpy(p, t.entropy, k);
        p += k;
        n -= k;
    }
}

/* The message ID of the test: 20 bytes of FNV-1a over the data, each byte from its own seed. */
static void message_id(const uint8_t *data, uint64_t n, uint8_t id[20]) {
    for (int k = 0; k < 20; k++) {
        uint64_t h = 0xCBF29CE484222325ull ^ (uint64_t)k;
        for (uint64_t i = 0; i < n; i++) h = (h ^ data[i]) * 0x100000001B3ull;
        id[k] = (uint8_t)(h >> 24);
    }
}

static void *ev_add(node *n, uint64_t kind, uint64_t size) {
    uint64_t *h = (uint64_t *)n->ev;
    size = (size + 7) & ~7ULL;
    if (24 + h[2] + size > EV_ROOM) fail("event room");
    uint8_t *p = n->ev + 24 + h[2];
    memset(p, 0, size);
    ((uint64_t *)p)[0] = size;
    ((uint64_t *)p)[1] = kind;
    h[2] += size;
    return p;
}

static void write_stream(node *n, uint64_t stream, const uint8_t *data, uint64_t len) {
    ev_stream_write *w = ev_add(n, EV_STREAM_WRITE, 32 + len);
    w->stream = stream;
    w->count = len;
    memcpy(w->data, data, len);
}

static void make_node(node *n, const char *name, uint64_t key_type, uint64_t muxers) {
    struct { libp2p_config c; libp2p_proto p[1]; } cfg;
    libp2p_config *c = &cfg.c;
    memset(n, 0, sizeof *n);
    n->name = name;
    for (int attempt = 0;; attempt++) {
        memset(&cfg, 0, sizeof cfg);
        c->size = sizeof cfg;
        c->key_type = key_type;
        random_bytes(c->private_key, 32);
        random_bytes(c->entropy, 32);
        c->now = now_ms();
        c->max_connections = 8; c->max_streams = 64; c->max_peers = 8; c->max_topics = 4;
        c->heap_size = 1 << 24; c->seen_capacity = 64; c->mcache_capacity = 64; c->pending_capacity = 16;
        c->muxers = muxers;
        c->send_window = 1 << 20; c->max_rpc = 1 << 20; c->max_data = 1 << 19;
        c->handshake_ms = 10000; c->validation_ms = 5000; c->stream_queue = 1 << 20;
        c->protocols = sizeof cfg.c; c->protocols_count = 1;
        cfg.p[0].len = strlen(ECHO);
        memcpy(cfg.p[0].bytes, ECHO, strlen(ECHO));
        c->d = 8; c->d_low = 6; c->d_high = 12; c->d_lazy = 6; c->d_score = 4; c->d_out = 2; c->heartbeat_ms = 700;
        c->fanout_ttl_ms = 60000; c->mcache_len = 6; c->mcache_gossip = 3; c->seen_ttl_ms = 120000;
        c->prune_backoff_ms = 60000; c->unsub_backoff_ms = 10000; c->graft_flood_ms = 10000; c->flood_publish = 1;
        c->gossip_factor = 0.25; c->max_ihave_length = 5000; c->max_ihave_messages = 10; c->iwant_followup_ms = 3000;
        c->retransmission = 3; c->opportunistic_ticks = 60; c->opportunistic_peers = 2;
        uint64_t size = 0;
        if (libp2p_state_size(&cfg, &size)) fail("libp2p_state_size");
        free(n->state);
        n->state = calloc(1, size);
        if (!n->state) fail("memory");
        ((uint64_t *)n->state)[0] = size;
        uint64_t st = libp2p_init(&cfg, n->state);
        if (st == LIBP2P_INVALID_KEY && attempt < 8) continue;
        if (st) fail("libp2p_init");
        break;
    }
    n->scratch = malloc(LIBP2P_SCRATCH_SIZE);
    n->ev = malloc(EV_ROOM);
    n->act = malloc(ACT_ROOM);
    if (!n->scratch || !n->ev || !n->act) fail("memory");
    ((uint64_t *)n->scratch)[0] = LIBP2P_SCRATCH_SIZE;
    ((uint64_t *)n->ev)[0] = EV_ROOM;
    ((uint64_t *)n->ev)[1] = 24;
    ((uint64_t *)n->ev)[2] = 0;
    libp2p_shell_params sp = {c->max_connections, c->send_window};
    uint64_t shell_size = 0;
    if (libp2p_shell_size(&sp, &shell_size)) fail("libp2p_shell_size");
    n->shell = calloc(1, shell_size);
    if (!n->shell) fail("memory");
    ((uint64_t *)n->shell)[0] = shell_size;
    if (libp2p_shell_init(&sp, n->shell)) fail("libp2p_shell_init");
    size_t tl = strlen(TOPIC);                      /* both join the topic */
    uint8_t *e = ev_add(n, EV_SUBSCRIBE, 24 + tl);
    ((uint64_t *)e)[2] = tl;
    memcpy(e + 24, TOPIC, tl);
}

static void free_node(node *n) {
    if (libp2p_shell_close(n->shell)) fail("libp2p_shell_close");
    free(n->state); free(n->scratch); free(n->shell); free(n->ev); free(n->act);
    memset(n, 0, sizeof *n);
}

static void publish(node *n) {
    size_t tl = strlen(TOPIC), tla = (tl + 7) & ~(size_t)7, ml = strlen(MESSAGE);
    uint8_t *p = ev_add(n, EV_PUBLISH, 72 + tla + ml);
    ((uint64_t *)p)[2] = 20;
    message_id((const uint8_t *)MESSAGE, ml, p + 24);
    ((uint64_t *)p)[7] = tl;
    ((uint64_t *)p)[8] = ml;
    memcpy(p + 72, TOPIC, tl);
    memcpy(p + 72 + tla, MESSAGE, ml);
}

static void handle_actions(node *n) {
    uint64_t *h = (uint64_t *)n->act;
    uint8_t *p = n->act + h[1], *end = p + h[2];
    int is_b = n == &nb;
    static int trace = -1;
    if (trace < 0) trace = getenv("TRACE") != NULL;
    while (p < end) {
        libp2p_header *a = (libp2p_header *)p;
        if (trace && a->kind != ACT_WAKEUP && a->kind != ACT_SEND)
            printf("%s action %llu: %llx %llx\n", n->name, (unsigned long long)a->kind, (unsigned long long)((uint64_t *)p)[2],
                   (unsigned long long)(a->size > 24 ? ((uint64_t *)p)[3] : 0));
        switch (a->kind) {
        case ACT_PEER_CONNECTED:
            n->peer = ((act_peer_connected *)p)->peer;
            n->connected = 1;
            if (is_b) {
                ev_open_stream *o = ev_add(n, EV_OPEN_STREAM, sizeof *o + sizeof(libp2p_proto));
                o->peer = n->peer;
                o->tag = 7;
                o->count = 1;
                o->protocols[0].len = strlen(ECHO);
                memcpy(o->protocols[0].bytes, ECHO, strlen(ECHO));
            }
            break;
        case ACT_PEER_DISCONNECTED: n->disconnected = 1; break;
        case ACT_DIAL_FAILED: fail("dial failed");
        case ACT_STREAM_FAILED: fail("stream failed");
        case ACT_STREAM_RESET: fail("stream reset");
        case ACT_STREAM_OPENED:
            if (!is_b || ((act_stream_opened *)p)->tag != 7) fail("stream opened");
            echo_stream = ((act_stream_opened *)p)->stream;
            for (uint64_t off = 0; off < ECHO_LEN; off += CHUNK) write_stream(n, echo_stream, echo_out + off, CHUNK);
            ((ev_conn *)ev_add(n, EV_STREAM_CLOSE, 24))->conn = echo_stream;
            break;
        case ACT_STREAM_DATA: {
            act_stream_data *d = (act_stream_data *)p;
            if (!is_b) {
                write_stream(n, d->stream, d->data, d->count);      /* echo */
            } else {
                if (d->stream != echo_stream || echo_got + d->count > ECHO_LEN) fail("echo length");
                memcpy(echo_in + echo_got, d->data, d->count);
                echo_got += d->count;
            }
            break;
        }
        case ACT_STREAM_EOF:
            if (!is_b) ((ev_conn *)ev_add(n, EV_STREAM_CLOSE, 24))->conn = ((act_stream_data *)p)->stream;
            else echo_eof = 1;
            break;
        case ACT_PEER_TOPIC:
            if (((act_peer_topic *)p)->subscribed) n->joined = 1;
            break;
        case ACT_PUBLISHED:
            if (((act_published *)p)->peers < 1) fail("published to no peer");
            break;
        case ACT_MESSAGE: {
            act_message *m = (act_message *)p;
            const uint8_t *data = (const uint8_t *)n->state + m->data_off;
            if (!is_b || m->data_len != strlen(MESSAGE) || memcmp(data, MESSAGE, m->data_len)) fail("message");
            ev_message_id *e = ev_add(n, EV_MESSAGE_ID, sizeof *e);
            e->handle = m->handle;
            e->id_len = 20;
            message_id(data, m->data_len, e->id);
            got_message = 1;
            break;
        }
        case ACT_MESSAGE_STATUS: {
            act_message_status *m = (act_message_status *)p;
            if (m->status != MSG_NEW) fail("message status");
            ev_conn *e = ev_add(n, EV_VALIDATION, 32);
            e->conn = m->handle;
            e->value = LIBP2P_ACCEPT;
            accepted = 1;
            break;
        }
        default: break;
        }
        p += a->size;
    }
}

static void step(node *n) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) fail("libp2p_shell_clock");
    ((uint64_t *)n->act)[0] = ACT_ROOM;
    uint64_t result = 0;
    if (libp2p_step(n->state, &t, n->ev, n->scratch, n->act, &result)) fail("libp2p_step");
    uint64_t *eh = (uint64_t *)n->ev;
    uint8_t *e = n->ev + 24;
    uint64_t off = 0;
    for (uint64_t i = 0; i < result; i++) off += ((uint64_t *)(e + off))[0];
    memmove(e, e + off, eh[2] - off);
    eh[2] -= off;
    if (libp2p_shell_perform(n->shell, n->act, n->ev)) fail("libp2p_shell_perform");
    handle_actions(n);
}

static void round_(int number, uint64_t muxers, uint64_t key_a, uint64_t key_b) {
    make_node(&na, "A", key_a, muxers);
    make_node(&nb, "B", key_b, muxers);
    echo_got = 0; echo_stream = 0; echo_eof = 0; published = 0; got_message = 0; accepted = 0; disconnect_sent = 0;
    for (uint64_t i = 0; i < ECHO_LEN; i++) echo_out[i] = (uint8_t)(i * 31 + (i >> 9) + 7);

    libp2p_addr la = {4, 0, {127, 0, 0, 1}};
    libp2p_listen_result lr;
    if (libp2p_shell_listen(na.shell, &la, &lr) || lr.error) fail("listen");
    ev_dial *d = ev_add(&nb, EV_DIAL, sizeof *d);
    d->tag = 1;
    d->addr = la;
    d->addr.port = lr.addr.port;
    d->id_len = ((uint64_t *)na.state)[ST_PEER_ID_LEN / 8];
    memcpy(d->id, (uint8_t *)na.state + ST_PEER_ID, d->id_len);

    uint64_t deadline = now_ms() + LIMIT_MS;
    while (!(na.disconnected && nb.disconnected)) {
        if (now_ms() > deadline) {
            printf("FAIL round %d timed out: connected %d %d, echo %llu eof %d, joined %d %d, message %d accepted %d\n",
                   number, na.connected, nb.connected, (unsigned long long)echo_got, echo_eof, na.joined, nb.joined,
                   got_message, accepted);
            exit(1);
        }
        if (na.joined && !published) {
            publish(&na);
            published = 1;
        }
        if (echo_got == ECHO_LEN && echo_eof && accepted && !disconnect_sent) {
            if (memcmp(echo_in, echo_out, ECHO_LEN)) fail("echo bytes");
            ((ev_conn *)ev_add(&nb, EV_DISCONNECT, 24))->conn = nb.peer;
            disconnect_sent = 1;
        }
        step(&na);
        step(&nb);
        uint64_t t = 2;
        if (((uint64_t *)na.ev)[2] == 0 && libp2p_shell_wait(na.shell, &t, na.ev)) fail("libp2p_shell_wait");
        if (((uint64_t *)nb.ev)[2] == 0 && libp2p_shell_wait(nb.shell, &t, nb.ev)) fail("libp2p_shell_wait");
    }
    printf("PASS round %d (%s): echo %d bytes, message delivered, disconnected\n", number,
           muxers == 1 ? "yamux" : "mplex", ECHO_LEN);
    free_node(&na);
    free_node(&nb);
}

int main(void) {
    echo_out = malloc(ECHO_LEN);
    echo_in = malloc(ECHO_LEN);
    if (!echo_out || !echo_in) fail("memory");
    round_(1, 1, LIBP2P_KEY_ED25519, LIBP2P_KEY_SECP256K1);
    round_(2, 2, LIBP2P_KEY_SECP256K1, LIBP2P_KEY_ED25519);
    static const char *const shell[] = {"libp2p_shell_size", "libp2p_shell_init", "libp2p_shell_listen",
                                        "libp2p_shell_perform", "libp2p_shell_wait", "libp2p_shell_close",
                                        "libp2p_shell_clock"};
    for (size_t i = 0; i < sizeof shell / sizeof shell[0]; i++) printf("FUNCTION %s PASS\n", shell[i]);
    printf("2 rounds, 0 failures\n");
    return 0;
}

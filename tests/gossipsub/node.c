/*
 * The asm-libp2p node of libp2p/test-plans gossipsub-interop.
 *
 * Usage: node --params PARAMS_JSON
 * The host name is node<ID>. The node listens on TCP port 9000 with an
 * Ed25519 identity whose seed is its ID as 8 bytes little endian, then zeros
 * (test-specs/implementation.md). It runs the instructions of the script in
 * PARAMS_JSON in order, the ones inside ifNodeIDEquals only for its own ID,
 * and exits 0 after the last one.
 *
 * stdout: one JSON object per line: "PeerID" at the start, and "Received
 * Message" for every message that arrives, duplicates included. A message ID
 * is the first 8 bytes of the data, logged as a big endian u64 in base 10.
 * stderr: diagnostics. TRACE=1 also prints every action.
 *
 * The library does libp2p and gossipsub, and its shell the sockets. This file
 * reads the script, turns gossipSubParams into the config, and logs.
 * Partial messages are not supported: the node stops with an error on them.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <math.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "../runner/libp2p.h"

LIBP2P_ABI uint64_t crypto_ed25519_public_key(const uint8_t *private_key, uint8_t *public_key);

#define EV_ROOM (32u << 20)
#define ACT_ROOM (64u << 20)
#define PORT 9000
#define MAX_PEERS 512
#define MAX_PENDING 4096
#define MAX_TOPICS 16
#define ST_PEER_ID_LEN 152                  /* include/state.inc */
#define ST_PEER_ID 160

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "fatal: ");
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

static void note(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

/* ---------------------------------------------------------------- JSON */

enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ };

typedef struct jv {
    int type;
    double num;
    char *str;                              /* J_STR */
    struct jv *items;                       /* J_ARR and J_OBJ values */
    char **keys;                            /* J_OBJ */
    size_t count;
} jv;

static const char *jp;

static void j_space(void) {
    while (*jp == ' ' || *jp == '\t' || *jp == '\n' || *jp == '\r') jp++;
}

static char *j_string(void) {
    if (*jp != '"') die("json: string expected at %.20s", jp);
    jp++;
    size_t cap = 16, n = 0;
    char *s = malloc(cap);
    while (*jp != '"') {
        if (!*jp) die("json: open string");
        char c = *jp++;
        if (c == '\\') {
            c = *jp++;
            switch (c) {
            case 'n': c = '\n'; break;
            case 't': c = '\t'; break;
            case 'r': c = '\r'; break;
            case 'b': c = '\b'; break;
            case 'f': c = '\f'; break;
            case 'u': {
                unsigned v = 0;
                if (sscanf(jp, "%4x", &v) != 1) die("json: bad escape");
                jp += 4;
                c = v < 0x80 ? (char)v : '?';
                break;
            }
            default: break;                 /* \" \\ \/ */
            }
        }
        if (n + 2 > cap) s = realloc(s, cap *= 2);
        s[n++] = c;
    }
    jp++;
    s[n] = 0;
    return s;
}

static void j_value(jv *v) {
    j_space();
    memset(v, 0, sizeof *v);
    if (*jp == '{' || *jp == '[') {
        int obj = *jp == '{';
        char close = obj ? '}' : ']';
        v->type = obj ? J_OBJ : J_ARR;
        jp++;
        size_t cap = 0;
        j_space();
        while (*jp != close) {
            if (v->count == cap) {
                cap = cap ? cap * 2 : 8;
                v->items = realloc(v->items, cap * sizeof *v->items);
                if (obj) v->keys = realloc(v->keys, cap * sizeof *v->keys);
            }
            if (obj) {
                j_space();
                v->keys[v->count] = j_string();
                j_space();
                if (*jp++ != ':') die("json: ':' expected");
            }
            j_value(&v->items[v->count++]);
            j_space();
            if (*jp == ',') {
                jp++;
                j_space();
            } else if (*jp != close) {
                die("json: ',' expected at %.20s", jp);
            }
        }
        jp++;
    } else if (*jp == '"') {
        v->type = J_STR;
        v->str = j_string();
    } else if (!strncmp(jp, "true", 4) || !strncmp(jp, "false", 5)) {
        v->type = J_BOOL;
        v->num = *jp == 't';
        jp += *jp == 't' ? 4 : 5;
    } else if (!strncmp(jp, "null", 4)) {
        jp += 4;
    } else {
        char *end;
        v->type = J_NUM;
        v->num = strtod(jp, &end);
        if (end == jp) die("json: value expected at %.20s", jp);
        jp = end;
    }
}

static const jv *j_get(const jv *o, const char *key) {
    if (!o || o->type != J_OBJ) return NULL;
    for (size_t i = 0; i < o->count; i++)
        if (!strcmp(o->keys[i], key)) return &o->items[i];
    return NULL;
}

static double j_num(const jv *o, const char *key) {
    const jv *v = j_get(o, key);
    if (!v || v->type != J_NUM) die("json: number %s expected", key);
    return v->num;
}

static const char *j_str(const jv *o, const char *key) {
    const jv *v = j_get(o, key);
    if (!v || v->type != J_STR) die("json: string %s expected", key);
    return v->str;
}

/* ---------------------------------------------------------------- base58btc */

static const char B58[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

static void b58_encode(const uint8_t *in, size_t n, char *out) {
    uint8_t buf[128] = {0};
    size_t len = 0, zeros = 0;
    while (zeros < n && in[zeros] == 0) zeros++;
    for (size_t i = zeros; i < n; i++) {
        int carry = in[i];
        for (size_t j = 0; j < len; j++) {
            carry += 256 * buf[j];
            buf[j] = carry % 58;
            carry /= 58;
        }
        while (carry) {
            buf[len++] = carry % 58;
            carry /= 58;
        }
    }
    size_t k = 0;
    for (size_t i = 0; i < zeros; i++) out[k++] = '1';
    for (size_t i = 0; i < len; i++) out[k++] = B58[buf[len - 1 - i]];
    out[k] = 0;
}

/* ---------------------------------------------------------------- Keys */

/* The seed of a node: its ID as 8 bytes little endian, then zeros. */
static void node_seed(int id, uint8_t seed[32]) {
    memset(seed, 0, 32);
    for (int i = 0; i < 8; i++) seed[i] = (uint8_t)((uint64_t)id >> (8 * i));
}

/* The peer ID of a node: the identity multihash of its Ed25519 public key in protobuf. */
static size_t node_peer_id(int id, uint8_t out[48]) {
    uint8_t seed[32], pub[32];
    node_seed(id, seed);
    if (crypto_ed25519_public_key(seed, pub)) die("crypto_ed25519_public_key");
    const uint8_t head[6] = {0x00, 0x24, 0x08, 0x01, 0x12, 0x20};
    memcpy(out, head, 6);
    memcpy(out + 6, pub, 32);
    return 38;
}

/* ---------------------------------------------------------------- The node */

static void *state, *scratch, *shell;
static uint8_t *events, *actions;
static uint64_t wake_at, start_ms;
static int node_id, trace;

static struct { uint64_t handle; char id[64]; } peers[MAX_PEERS];
static struct { uint64_t handle, due; } pending[MAX_PENDING];
static size_t pending_count;
static struct { char name[LIBP2P_MAX_TOPIC + 1]; double delay; } topics[MAX_TOPICS];
static size_t topic_count;

/* Dials of the running connect instruction, by target node: 0 none, 1 open, 2 done. */
static struct { int target, state, tries; uint64_t retry_at; } dials[MAX_PEERS];
static size_t dial_count;

static uint64_t now_ms(void) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) die("libp2p_shell_clock");
    return t.now;
}

static void log_line(const char *msg, const char *fields) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    gmtime_r(&ts.tv_sec, &tm);
    char when[64];
    strftime(when, sizeof when, "%Y-%m-%dT%H:%M:%S", &tm);
    printf("{\"time\":\"%s.%06ldZ\",\"level\":\"INFO\",\"msg\":\"%s\"%s}\n", when, ts.tv_nsec / 1000, msg, fields);
}

static void *ev_add(uint64_t kind, uint64_t size) {
    uint64_t *h = (uint64_t *)events;
    size = (size + 7) & ~7ULL;
    if (h[2] + size > EV_ROOM - 24) die("event room");
    uint8_t *p = events + 24 + h[2];
    memset(p, 0, size);
    ((uint64_t *)p)[0] = size;
    ((uint64_t *)p)[1] = kind;
    h[2] += size;
    return p;
}

static const char *peer_name(uint64_t handle) {
    for (size_t i = 0; i < MAX_PEERS; i++)
        if (peers[i].handle == handle) return peers[i].id;
    return "";
}

static double topic_delay(const uint8_t *name, uint64_t len) {
    for (size_t i = 0; i < topic_count; i++)
        if (strlen(topics[i].name) == len && !memcmp(topics[i].name, name, len)) return topics[i].delay;
    return 0;
}

static void dial(size_t k) {
    char host[32];
    snprintf(host, sizeof host, "node%d", dials[k].target);
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    dials[k].tries++;
    if (getaddrinfo(host, NULL, &hints, &res) || !res) {
        /* Again in 1 s, as a failed dial. */
        note("cannot resolve %s%s", host, dials[k].tries < 10 ? "; again in 1 s" : "");
        dials[k].state = dials[k].tries < 10 ? 0 : 2;
        dials[k].retry_at = now_ms() + 1000;
        return;
    }
    ev_dial *d = ev_add(EV_DIAL, sizeof *d);
    d->tag = (uint64_t)dials[k].target + 1;
    d->addr.family = 4;
    d->addr.port = PORT;
    memcpy(d->addr.ip, &((struct sockaddr_in *)res->ai_addr)->sin_addr, 4);
    freeaddrinfo(res);
    d->id_len = node_peer_id(dials[k].target, d->id);
    dials[k].state = 1;
}

static void dial_done(uint64_t tag, int failed, uint64_t reason) {
    for (size_t k = 0; k < dial_count; k++) {
        if ((uint64_t)dials[k].target + 1 != tag || dials[k].state != 1) continue;
        /* A dial to a peer that is already connected fails with DUPLICATE: the connection is there. */
        if (failed && reason != 8 && dials[k].tries < 10) {
            note("dial to node%d failed, reason %llu; again in 1 s", dials[k].target, (unsigned long long)reason);
            dials[k].state = 0;
            dials[k].retry_at = now_ms() + 1000;
            return;
        }
        if (failed && reason != 8) note("dial to node%d failed, reason %llu", dials[k].target, (unsigned long long)reason);
        dials[k].state = 2;
        return;
    }
}

static void handle_actions(void) {
    uint64_t *h = (uint64_t *)actions;
    uint8_t *p = actions + h[1], *end = p + h[2];
    while (p < end) {
        libp2p_header *a = (libp2p_header *)p;
        if (trace && a->kind != ACT_WAKEUP) {
            uint64_t *w = (uint64_t *)p;
            note("action %llu: %llx %llx %llx", (unsigned long long)a->kind, (unsigned long long)w[2],
                 (unsigned long long)(a->size > 24 ? w[3] : 0), (unsigned long long)(a->size > 32 ? w[4] : 0));
        }
        switch (a->kind) {
        case ACT_WAKEUP: wake_at = ((uint64_t *)p)[2]; break;
        case ACT_PEER_CONNECTED: {
            act_peer_connected *c = (act_peer_connected *)p;
            for (size_t i = 0; i < MAX_PEERS; i++)
                if (!peers[i].handle) {
                    peers[i].handle = c->peer;
                    b58_encode(c->id, c->id_len, peers[i].id);
                    break;
                }
            if (c->tag) dial_done(c->tag, 0, 0);
            break;
        }
        case ACT_PEER_DISCONNECTED: {
            act_peer_disconnected *c = (act_peer_disconnected *)p;
            for (size_t i = 0; i < MAX_PEERS; i++)
                if (peers[i].handle == c->peer) peers[i].handle = 0;
            break;
        }
        case ACT_DIAL_FAILED: {
            act_failed *f = (act_failed *)p;
            dial_done(f->tag, 1, f->reason);
            break;
        }
        case ACT_MESSAGE: {
            act_message *m = (act_message *)p;
            const uint8_t *data = (const uint8_t *)state + m->data_off;
            uint64_t id = 0;
            for (uint64_t i = 0; i < 8; i++) id = id << 8 | (i < m->data_len ? data[i] : 0);
            char fields[512];
            snprintf(fields, sizeof fields, ",\"service\":\"gossipsub\",\"from\":\"%s\",\"topic\":\"%.*s\",\"id\":\"%llu\"",
                     peer_name(m->peer), (int)m->topic_len, (const char *)m->topic, (unsigned long long)id);
            log_line("Received Message", fields);
            ev_message_id *e = ev_add(EV_MESSAGE_ID, sizeof *e);
            e->handle = m->handle;
            e->id_len = 8;
            for (int i = 0; i < 8; i++) e->id[i] = (uint8_t)(id >> (56 - 8 * i));
            /* The validation delay of the topic, until MESSAGE_STATUS says the message is new. */
            if (pending_count == MAX_PENDING) die("pending messages");
            pending[pending_count].handle = m->handle;
            pending[pending_count].due = (uint64_t)llround(topic_delay(m->topic, m->topic_len) * 1000.0);
            pending[pending_count].due |= 1ULL << 63;        /* not known new yet */
            pending_count++;
            break;
        }
        case ACT_MESSAGE_STATUS: {
            act_message_status *m = (act_message_status *)p;
            for (size_t i = 0; i < pending_count; i++) {
                if (pending[i].handle != m->handle || !(pending[i].due >> 63)) continue;
                if (m->status == MSG_NEW) {
                    pending[i].due = now_ms() + (pending[i].due & ~(1ULL << 63));
                } else {
                    pending[i] = pending[--pending_count];
                }
                break;
            }
            break;
        }
        case ACT_PUBLISHED:
            note("published to %llu peers", (unsigned long long)((act_published *)p)->peers);
            break;
        default: break;
        }
        p += a->size;
    }
}

static void step(void) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) die("libp2p_shell_clock");
    ((uint64_t *)actions)[0] = ACT_ROOM;
    uint64_t result = 0;
    uint64_t st = libp2p_step(state, &t, events, scratch, actions, &result);
    if (st) die("libp2p_step: status %llu", (unsigned long long)st);
    uint64_t *eh = (uint64_t *)events;
    uint8_t *e = events + 24;
    uint64_t off = 0;
    for (uint64_t i = 0; i < result; i++) off += ((uint64_t *)(e + off))[0];
    memmove(e, e + off, eh[2] - off);
    eh[2] -= off;
    if (libp2p_shell_perform(shell, actions, events)) die("libp2p_shell_perform");
    handle_actions();
}

/* ---------------------------------------------------------------- Config */

static uint64_t param_u(const jv *gs, const char *key, uint64_t fallback) {
    const jv *v = j_get(gs, key);
    return v && v->type == J_NUM ? (uint64_t)v->num : fallback;
}

static double param_f(const jv *gs, const char *key, double fallback) {
    const jv *v = j_get(gs, key);
    return v && v->type == J_NUM ? v->num : fallback;
}

/* A duration in nanoseconds, as ms; at least 1 when the value is above 0. */
static uint64_t param_ms(const jv *gs, const char *key, uint64_t fallback_ms) {
    const jv *v = j_get(gs, key);
    if (!v || v->type != J_NUM) return fallback_ms;
    uint64_t ms = (uint64_t)(v->num / 1e6);
    return ms ? ms : v->num > 0;
}

/*
 * The gossipsub config. A field that gossipSubParams leaves out takes the
 * default of go-libp2p-pubsub a01777894f4c (gossipsub.go), the version the
 * go node of the suite builds. HeartbeatInitialDelay, PrunePeers, the
 * connection fields, SlowHeartbeatWarning and the IDONTWANT fields have no
 * field in the config.
 */
static void gossip_config(libp2p_config *c, const jv *gs) {
    c->d = param_u(gs, "D", 6);
    c->d_low = param_u(gs, "Dlo", 5);
    c->d_high = param_u(gs, "Dhi", 12);
    c->d_score = param_u(gs, "Dscore", 4);
    c->d_out = param_u(gs, "Dout", 2);
    c->mcache_len = param_u(gs, "HistoryLength", 5);
    c->mcache_gossip = param_u(gs, "HistoryGossip", 3);
    c->d_lazy = param_u(gs, "Dlazy", 6);
    c->gossip_factor = param_f(gs, "GossipFactor", 0.25);
    c->retransmission = param_u(gs, "GossipRetransmission", 3);
    if (c->retransmission > 3) c->retransmission = 3;
    c->heartbeat_ms = param_ms(gs, "HeartbeatInterval", 1000);
    c->fanout_ttl_ms = param_ms(gs, "FanoutTTL", 60000);
    c->prune_backoff_ms = param_ms(gs, "PruneBackoff", 60000);
    c->unsub_backoff_ms = param_ms(gs, "UnsubscribeBackoff", 10000);
    c->opportunistic_ticks = param_u(gs, "OpportunisticGraftTicks", 60);
    c->opportunistic_peers = param_u(gs, "OpportunisticGraftPeers", 2);
    c->graft_flood_ms = param_ms(gs, "GraftFloodThreshold", 10000);
    c->max_ihave_length = param_u(gs, "MaxIHaveLength", 5000);
    if (c->max_ihave_length > 8192) c->max_ihave_length = 8192;
    c->max_ihave_messages = param_u(gs, "MaxIHaveMessages", 10);
    c->iwant_followup_ms = param_ms(gs, "IWantFollowupTime", 3000);
    c->seen_ttl_ms = 120000;                /* TimeCacheDuration */
    c->flood_publish = 1;
}

/* ---------------------------------------------------------------- The script */

static const jv *script;
static size_t pc;
static uint64_t wait_until;                 /* a waitUntil in progress: its time; else 0 */
static int connecting;                      /* a connect in progress */

/* The initGossipSub instruction for this node: the first one at the top or inside ifNodeIDEquals. */
static const jv *find_init(void) {
    for (size_t i = 0; i < script->count; i++) {
        const jv *ins = &script->items[i];
        while (!strcmp(j_str(ins, "type"), "ifNodeIDEquals")) {
            if ((int)j_num(ins, "nodeID") != node_id) break;
            ins = j_get(ins, "instruction");
        }
        if (!strcmp(j_str(ins, "type"), "initGossipSub")) return j_get(ins, "gossipSubParams");
    }
    return NULL;
}

static void run(const jv *ins) {
    const char *type = j_str(ins, "type");
    if (!strcmp(type, "ifNodeIDEquals")) {
        if ((int)j_num(ins, "nodeID") == node_id) run(j_get(ins, "instruction"));
    } else if (!strcmp(type, "initGossipSub")) {
        /* Read before the start: the config takes it. */
    } else if (!strcmp(type, "connect")) {
        const jv *to = j_get(ins, "connectTo");
        if (!to || to->type != J_ARR) die("connectTo expected");
        dial_count = 0;
        for (size_t i = 0; i < to->count; i++) {
            int target = (int)to->items[i].num;
            if (target == node_id || dial_count == MAX_PEERS) continue;
            dials[dial_count].target = target;
            dials[dial_count].tries = 0;
            dial(dial_count++);
        }
        connecting = 1;
    } else if (!strcmp(type, "waitUntil")) {
        wait_until = start_ms + (uint64_t)(j_num(ins, "elapsedSeconds") * 1000.0);
    } else if (!strcmp(type, "subscribeToTopic")) {
        const jv *partial = j_get(ins, "partial");
        if (partial && partial->type == J_BOOL && partial->num) die("partial messages are not supported");
        const char *t = j_str(ins, "topicID");
        size_t tl = strlen(t);
        uint8_t *e = ev_add(EV_SUBSCRIBE, 24 + tl);
        ((uint64_t *)e)[2] = tl;
        memcpy(e + 24, t, tl);
    } else if (!strcmp(type, "setTopicValidationDelay")) {
        const char *t = j_str(ins, "topicID");
        size_t i = 0;
        while (i < topic_count && strcmp(topics[i].name, t)) i++;
        if (i == topic_count) {
            if (topic_count == MAX_TOPICS) die("topics");
            snprintf(topics[topic_count++].name, sizeof topics[0].name, "%s", t);
        }
        topics[i].delay = j_num(ins, "delaySeconds");
    } else if (!strcmp(type, "publish")) {
        const char *t = j_str(ins, "topicID");
        uint64_t id = (uint64_t)j_num(ins, "messageID"), size = (uint64_t)j_num(ins, "messageSizeBytes");
        if (size < 8) die("messageSizeBytes below 8");
        size_t tl = strlen(t), tla = (tl + 7) & ~(size_t)7;
        uint8_t *p = ev_add(EV_PUBLISH, 72 + tla + size);
        ((uint64_t *)p)[2] = 8;
        for (int i = 0; i < 8; i++) p[24 + i] = (uint8_t)(id >> (56 - 8 * i));
        ((uint64_t *)p)[7] = tl;
        ((uint64_t *)p)[8] = size;
        memcpy(p + 72, t, tl);
        memcpy(p + 72 + tla, p + 24, 8);    /* the data: the ID big endian, then zeros */
        note("publishing message %llu", (unsigned long long)id);
    } else {
        die("instruction %s is not supported", type);
    }
}

/* 1 while the running instruction still waits. */
static int blocked(uint64_t now) {
    if (wait_until) {
        if (now < wait_until) return 1;
        wait_until = 0;
    }
    if (connecting) {
        int open = 0;
        for (size_t k = 0; k < dial_count; k++) {
            if (dials[k].state == 0 && now >= dials[k].retry_at) dial(k);
            if (dials[k].state != 2) open = 1;
        }
        if (open) return 1;
        connecting = 0;
        size_t n = 0;
        for (size_t i = 0; i < MAX_PEERS; i++) n += peers[i].handle != 0;
        note("node %d connected to %zu peers", node_id, n);
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *path = NULL;
    for (int i = 1; i + 1 < argc; i++)
        if (!strcmp(argv[i], "--params")) path = argv[i + 1];
    if (!path) die("usage: node --params PARAMS_JSON");
    trace = getenv("TRACE") != NULL;
    setvbuf(stdout, NULL, _IOLBF, 0);
    start_ms = now_ms();

    char host[256];
    if (gethostname(host, sizeof host) || sscanf(host, "node%d", &node_id) != 1) die("host name %s is not node<ID>", host);

    FILE *f = fopen(path, "rb");
    if (!f) die("cannot read %s", path);
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *text = malloc((size_t)n + 1);
    if (fread(text, 1, (size_t)n, f) != (size_t)n) die("cannot read %s", path);
    text[n] = 0;
    fclose(f);
    static jv root;
    jp = text;
    j_value(&root);
    script = j_get(&root, "script");
    if (!script || script->type != J_ARR) die("params: script expected");

    static struct { libp2p_config c; } cfg;
    libp2p_config *c = &cfg.c;
    c->size = sizeof cfg;
    c->key_type = LIBP2P_KEY_ED25519;
    node_seed(node_id, c->private_key);
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) die("libp2p_shell_clock");
    memcpy(c->entropy, t.entropy, 32);
    c->now = t.now;
    c->max_connections = 256; c->max_streams = 2048; c->max_peers = 256; c->max_topics = MAX_TOPICS;
    c->heap_size = 1u << 28; c->seen_capacity = 1 << 14; c->mcache_capacity = 1 << 12; c->pending_capacity = 1 << 10;
    c->muxers = 3;
    c->send_window = 1u << 24; c->max_rpc = 10u << 20; c->max_data = 10u << 20;
    c->handshake_ms = 30000; c->validation_ms = 60000; c->stream_queue = 1u << 22;
    c->protocols = sizeof cfg.c; c->protocols_count = 0;
    gossip_config(c, find_init());
    c->agent_len = strlen("asm-libp2p");
    memcpy(c->agent, "asm-libp2p", c->agent_len);
    c->pv_len = strlen("ipfs/0.1.0");
    memcpy(c->pv, "ipfs/0.1.0", c->pv_len);

    uint64_t size = 0;
    if (libp2p_state_size(&cfg, &size)) die("libp2p_state_size");
    state = calloc(1, size);
    if (!state) die("memory");
    ((uint64_t *)state)[0] = size;
    uint64_t st = libp2p_init(&cfg, state);
    if (st) die("libp2p_init: status %llu", (unsigned long long)st);
    scratch = malloc(LIBP2P_SCRATCH_SIZE);
    ((uint64_t *)scratch)[0] = LIBP2P_SCRATCH_SIZE;
    events = malloc(EV_ROOM);
    actions = malloc(ACT_ROOM);
    ((uint64_t *)events)[0] = EV_ROOM;
    ((uint64_t *)events)[1] = 24;
    ((uint64_t *)events)[2] = 0;
    libp2p_shell_params sp = {c->max_connections, c->send_window};
    uint64_t shell_size = 0;
    if (libp2p_shell_size(&sp, &shell_size)) die("libp2p_shell_size");
    shell = calloc(1, shell_size);
    ((uint64_t *)shell)[0] = shell_size;
    if (libp2p_shell_init(&sp, shell)) die("libp2p_shell_init");
    libp2p_addr la = {4, PORT, {0}};
    libp2p_listen_result lr;
    if (libp2p_shell_listen(shell, &la, &lr) || lr.error) die("listen on port %d: error %llu", PORT, (unsigned long long)lr.error);

    uint8_t own[48];
    size_t own_len = node_peer_id(node_id, own);
    if (((uint64_t *)state)[ST_PEER_ID_LEN / 8] != own_len || memcmp((uint8_t *)state + ST_PEER_ID, own, own_len))
        die("the peer ID of the library differs from the one of the seed");
    char own58[128], fields[256];
    b58_encode(own, own_len, own58);
    snprintf(fields, sizeof fields, ",\"id\":\"%s\",\"node_id\":%d", own58, node_id);
    log_line("PeerID", fields);

    for (;;) {
        uint64_t now = now_ms();
        while (!blocked(now) && pc < script->count) run(&script->items[pc++]);
        if (pc == script->count && !blocked(now)) break;
        /* Verdicts whose delay is over. */
        uint64_t next = wake_at ? wake_at : now + 1000;
        for (size_t i = 0; i < pending_count;) {
            if (!(pending[i].due >> 63) && pending[i].due <= now) {
                ev_conn *e = ev_add(EV_VALIDATION, 32);
                e->conn = pending[i].handle;
                e->value = LIBP2P_ACCEPT;
                pending[i] = pending[--pending_count];
                continue;
            }
            if (!(pending[i].due >> 63) && pending[i].due < next) next = pending[i].due;
            i++;
        }
        step();
        if (wait_until && wait_until < next) next = wait_until;
        if (connecting && now + 100 < next) next = now + 100;
        now = now_ms();
        uint64_t wait = next > now ? next - now : 0;
        if (wait > 1000) wait = 1000;
        if (((uint64_t *)events)[2] == 0 && libp2p_shell_wait(shell, &wait, events)) die("libp2p_shell_wait");
    }
    note("node %d: script done", node_id);
    libp2p_shell_close(shell);
    return 0;
}

/*
 * The asm-libp2p node of libp2p/test-plans transport-interop.
 *
 * Environment: transport (tcp), muxer (yamux or mplex), security (noise),
 * is_dialer, ip, redis_addr (default redis:6379), test_timeout_seconds.
 * The listener publishes /ip4/<ip>/tcp/<port>/p2p/<id> with RPUSH
 * listenerAddr; the dialer takes it with BLPOP, connects, pings with
 * /ipfs/ping/1.0.0 (32 random bytes, echoed) and prints the JSON result.
 * Logs go to stderr; only the result goes to stdout.
 *
 * The library does the protocols and its shell the sockets; this file does
 * Redis and the ping protocol, which consensus clients do not use.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
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

LIBP2P_ABI uint64_t crypto_sha256(const void *message, void *digest);

#define EV_ROOM (8 << 20)
#define ACT_ROOM (8 << 20)
#define PING "/ipfs/ping/1.0.0"

static void logf_(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static double now_f(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static void random_bytes(uint8_t *p, size_t n) {
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f || fread(p, 1, n, f) != n) die("urandom");
    fclose(f);
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

static int b58_decode(const char *s, uint8_t *out, size_t *n) {
    uint8_t buf[128] = {0};
    size_t len = 0, zeros = 0;
    while (s[zeros] == '1') zeros++;
    for (size_t i = zeros; s[i]; i++) {
        const char *p = strchr(B58, s[i]);
        if (!p || !*p) return -1;
        int carry = (int)(p - B58);
        for (size_t j = 0; j < len; j++) {
            carry += 58 * buf[j];
            buf[j] = carry & 0xFF;
            carry >>= 8;
        }
        while (carry) {
            buf[len++] = carry & 0xFF;
            carry >>= 8;
        }
    }
    if (zeros + len > *n) return -1;
    for (size_t i = 0; i < zeros; i++) out[i] = 0;
    for (size_t i = 0; i < len; i++) out[zeros + i] = buf[len - 1 - i];
    *n = zeros + len;
    return 0;
}

/* ---------------------------------------------------------------- Redis (RESP) */

static int tcp_connect_host(const char *hostport) {
    char host[256];
    const char *colon = strrchr(hostport, ':');
    if (!colon) die("bad redis_addr %s", hostport);
    snprintf(host, sizeof host, "%.*s", (int)(colon - hostport), hostport);
    struct addrinfo hints = {0}, *res;
    hints.ai_socktype = SOCK_STREAM;
    for (int attempt = 0; attempt < 50; attempt++) {
        if (getaddrinfo(host, colon + 1, &hints, &res) == 0) {
            int fd = socket(res->ai_family, SOCK_STREAM, 0);
            if (fd >= 0 && connect(fd, res->ai_addr, res->ai_addrlen) == 0) {
                freeaddrinfo(res);
                return fd;
            }
            if (fd >= 0) close(fd);
            freeaddrinfo(res);
        }
        usleep(200000);
    }
    die("cannot reach redis at %s", hostport);
    return -1;
}

static void redis_cmd(int fd, int argc, const char **argv) {
    char buf[1024];
    int k = snprintf(buf, sizeof buf, "*%d\r\n", argc);
    for (int i = 0; i < argc; i++) k += snprintf(buf + k, sizeof buf - k, "$%zu\r\n%s\r\n", strlen(argv[i]), argv[i]);
    if (write(fd, buf, k) != k) die("redis write");
}

static int redis_read(int fd, char *buf, int cap) {
    int n = 0;
    while (n < cap - 1) {
        int r = (int)read(fd, buf + n, cap - 1 - n);
        if (r <= 0) die("redis read");
        n += r;
        buf[n] = 0;
        /* a reply ends with \r\n; an array of bulk strings has 3 + 2 lines */
        if (buf[0] == '*') {
            int lines = 0;
            for (int i = 0; i < n; i++) lines += buf[i] == '\n';
            if (buf[1] == '-' ? lines >= 1 : lines >= 5) break;
        } else if (n >= 2 && buf[n - 2] == '\r' && buf[n - 1] == '\n') {
            break;
        }
    }
    return n;
}

/* ---------------------------------------------------------------- Node */

static void *state, *scratch;
static uint8_t *events, *actions;
static void *shell;
static int is_dialer;
static uint64_t wake_at;
static double t_start, t_ping;
static uint8_t ping_bytes[32];
static uint64_t ping_stream;
static int done;
static int gossip_mode;
static const char *gs_name;
static int gs_got;
#define GS_TOPIC "/eth2/00000000/beacon_block/ssz_snappy"

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

static void write_stream(uint64_t stream, const uint8_t *data, uint64_t n) {
    ev_stream_write *w = ev_add(EV_STREAM_WRITE, 32 + n);
    w->stream = stream;
    w->count = n;
    memcpy(w->data, data, n);
}

static void handle_actions(void) {
    uint64_t *h = (uint64_t *)actions;
    uint8_t *p = actions + h[1], *end = p + h[2];
    static int trace = -1;
    if (trace < 0) trace = getenv("TRACE") != NULL;
    while (p < end) {
        libp2p_header *a = (libp2p_header *)p;
        if (trace && a->kind != ACT_WAKEUP) {
            uint64_t *w = (uint64_t *)p;
            fprintf(stderr, "action %llu: %llx %llx %llx\n", (unsigned long long)a->kind, (unsigned long long)w[2],
                    (unsigned long long)(a->size > 24 ? w[3] : 0), (unsigned long long)(a->size > 32 ? w[4] : 0));
        }
        switch (a->kind) {
        case ACT_WAKEUP: wake_at = ((uint64_t *)p)[2]; break;
        case ACT_PEER_CONNECTED: {
            act_peer_connected *d = (act_peer_connected *)p;
            logf_("peer connected, direction %llu", (unsigned long long)d->direction);
            if (is_dialer) {
                ev_open_stream *o = ev_add(EV_OPEN_STREAM, sizeof *o + sizeof(libp2p_proto));
                o->peer = d->peer;
                o->tag = 1;
                o->count = 1;
                o->protocols[0].len = strlen(PING);
                memcpy(o->protocols[0].bytes, PING, strlen(PING));
            }
            break;
        }
        case ACT_PEER_DISCONNECTED: logf_("peer disconnected"); break;
        case ACT_DIAL_FAILED: die("dial failed, reason %llu", (unsigned long long)((act_failed *)p)->reason);
        case ACT_STREAM_FAILED: die("stream failed, reason %llu", (unsigned long long)((act_failed *)p)->reason);
        case ACT_STREAM_OPENED: {
            ping_stream = ((act_stream_opened *)p)->stream;
            random_bytes(ping_bytes, 32);
            t_ping = now_f();
            write_stream(ping_stream, ping_bytes, 32);
            break;
        }
        case ACT_STREAM_INBOUND: logf_("inbound stream, protocol %llu", (unsigned long long)((act_stream_inbound *)p)->protocol); break;
        case ACT_STREAM_DATA: {
            act_stream_data *d = (act_stream_data *)p;
            if (!is_dialer) {
                write_stream(d->stream, d->data, d->count);   /* echo */
            } else if (d->stream == ping_stream) {
                static uint8_t got[32];
                static uint64_t got_len;
                for (uint64_t i = 0; i < d->count && got_len < 32; i++) got[got_len++] = d->data[i];
                if (got_len == 32) {
                    if (memcmp(got, ping_bytes, 32)) die("ping reply differs");
                    double t = now_f();
                    printf("{\"handshakePlusOneRTTMillis\": %.3f, \"pingRTTMilllis\": %.3f}\n", t - t_start, t - t_ping);
                    fflush(stdout);
                    done = 1;
                }
            }
            break;
        }
        case ACT_STREAM_EOF: {
            if (!is_dialer) {
                ev_conn *c = ev_add(EV_STREAM_CLOSE, 24);
                c->conn = ((act_stream_data *)p)->stream;
            }
            break;
        }
        case ACT_STREAM_RESET: logf_("stream reset"); break;
        case ACT_MESSAGE: {
            act_message *m = (act_message *)p;
            const uint8_t *data = (const uint8_t *)state + m->data_off;
            struct { uint64_t size, offset, count; uint8_t b[1 << 16]; } *bl = malloc(sizeof *bl);
            bl->size = sizeof *bl; bl->offset = 24; bl->count = m->data_len;
            memcpy(bl->b, data, m->data_len);
            uint8_t digest[32];
            crypto_sha256(bl, digest);
            free(bl);
            ev_message_id *e = ev_add(EV_MESSAGE_ID, sizeof *e);
            e->handle = m->handle;
            e->id_len = 20;
            memcpy(e->id, digest, 20);
            printf("%s RECV %.*s\n", gs_name, (int)m->data_len, data);
            fflush(stdout);
            break;
        }
        case ACT_MESSAGE_STATUS: {
            act_message_status *m = (act_message_status *)p;
            if (m->status == MSG_NEW) {
                gs_got++;
                ev_conn *e = ev_add(EV_VALIDATION, 32);
                e->conn = m->handle;
                e->value = LIBP2P_ACCEPT;
            }
            break;
        }
        case ACT_PUBLISHED: logf_("published to %llu peers", (unsigned long long)((act_published *)p)->peers); break;
        case ACT_PEER_TOPIC: {
            act_peer_topic *t = (act_peer_topic *)p;
            logf_("peer %s topic %.*s", t->subscribed ? "joined" : "left", (int)t->topic_len, t->topic);
            break;
        }
        default: break;
        }
        p += a->size;
    }
}

static void step(void) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) die("libp2p_shell_clock");
    uint64_t *ah = (uint64_t *)actions;
    ah[0] = ACT_ROOM;
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

static void poll_once(int timeout_ms) {
    uint64_t t = (uint64_t)timeout_ms;
    if (libp2p_shell_wait(shell, &t, events)) die("libp2p_shell_wait");
}

static void parse_multiaddr(const char *m, ev_dial *d) {
    char ip[64], id[128];
    int port;
    if (sscanf(m, "/ip4/%63[^/]/tcp/%d/p2p/%127s", ip, &port, id) != 3) die("cannot parse address %s", m);
    d->addr.family = 4;
    d->addr.port = (uint64_t)port;
    if (inet_pton(AF_INET, ip, d->addr.ip) != 1) die("bad ip %s", ip);
    size_t n = sizeof d->id;
    if (b58_decode(id, d->id, &n)) die("bad peer id %s", id);
    d->id_len = n;
}

int main(void) {
    const char *transport = getenv("transport"), *muxer = getenv("muxer"), *security = getenv("security");
    const char *dialer = getenv("is_dialer"), *ip = getenv("ip"), *redis = getenv("redis_addr");
    const char *timeout_s = getenv("test_timeout_seconds");
    gossip_mode = getenv("MODE") && !strcmp(getenv("MODE"), "gossip");
    if (gossip_mode) {
        gs_name = getenv("NAME") ? getenv("NAME") : "asm";
        transport = "tcp";
        security = "noise";
        if (!muxer) muxer = "yamux";
        dialer = getenv("LISTEN") && !strcmp(getenv("LISTEN"), "1") ? "false" : "true";
        if (!getenv("redis_addr")) redis = getenv("REDIS");
    }
    if (!transport || strcmp(transport, "tcp")) die("transport %s is not supported", transport ? transport : "(none)");
    if (!security || strcmp(security, "noise")) die("security %s is not supported", security ? security : "(none)");
    if (!muxer || (strcmp(muxer, "yamux") && strcmp(muxer, "mplex"))) die("muxer %s is not supported", muxer ? muxer : "(none)");
    is_dialer = dialer && !strcmp(dialer, "true");
    if (!ip) ip = "0.0.0.0";
    if (!redis) redis = "redis:6379";
    int timeout = timeout_s ? atoi(timeout_s) : 180;

    struct { libp2p_config c; libp2p_proto p[1]; } cfg;
    libp2p_config *c = &cfg.c;
    memset(&cfg, 0, sizeof cfg);
    c->size = sizeof cfg;
    c->key_type = LIBP2P_KEY_ED25519;
    random_bytes(c->private_key, 32);
    random_bytes(c->entropy, 32);
    c->now = now_ms();
    c->max_connections = 8; c->max_streams = 64; c->max_peers = 8; c->max_topics = 4;
    c->heap_size = 1 << 24; c->seen_capacity = 64; c->mcache_capacity = 64; c->pending_capacity = 16;
    c->muxers = strcmp(muxer, "yamux") ? 2 : 1;
    c->send_window = 1 << 20; c->max_rpc = 1 << 20; c->max_data = 1 << 19;
    c->handshake_ms = 30000; c->validation_ms = 5000; c->stream_queue = 1 << 20;
    c->protocols = sizeof cfg.c; c->protocols_count = 1;
    cfg.p[0].len = strlen(PING);
    memcpy(cfg.p[0].bytes, PING, strlen(PING));
    c->d = 8; c->d_low = 6; c->d_high = 12; c->d_lazy = 6; c->d_score = 4; c->d_out = 2; c->heartbeat_ms = 700;
    c->fanout_ttl_ms = 60000; c->mcache_len = 6; c->mcache_gossip = 3; c->seen_ttl_ms = 120000;
    c->prune_backoff_ms = 60000; c->unsub_backoff_ms = 10000; c->graft_flood_ms = 10000; c->flood_publish = 1;
    c->gossip_factor = 0.25; c->max_ihave_length = 5000; c->max_ihave_messages = 10; c->iwant_followup_ms = 3000;
    c->retransmission = 3; c->opportunistic_ticks = 60; c->opportunistic_peers = 2;
    c->agent_len = strlen("asm-libp2p/0.1.0");
    memcpy(c->agent, "asm-libp2p/0.1.0", c->agent_len);
    c->pv_len = strlen("ipfs/0.1.0");
    memcpy(c->pv, "ipfs/0.1.0", c->pv_len);
    c->gossipsub_v12 = 1;                   /* gossipsub v1.2, with the IDONTWANT defaults of go-libp2p-pubsub */
    c->idontwant_threshold = 1024; c->dontwant_slots = 64; c->dontwant_ttl = 3;
    c->max_idontwant_messages = 1000; c->max_idontwant_length = 10;

    uint64_t size = 0;
    if (libp2p_state_size(&cfg, &size)) die("libp2p_state_size");
    state = calloc(1, size);
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

    uint8_t *peer_id = (uint8_t *)state + 160;       /* ST_PEER_ID */
    uint64_t peer_id_len = ((uint64_t *)state)[19];   /* ST_PEER_ID_LEN at 152 */
    char id58[128];
    b58_encode(peer_id, peer_id_len, id58);
    logf_("peer id %s, muxer %s, %s", id58, muxer, is_dialer ? "dialer" : "listener");

    int rfd = tcp_connect_host(redis);
    char reply[2048];
    uint64_t deadline = now_ms() + (uint64_t)timeout * 1000;

    if (!is_dialer) {
        libp2p_addr la = {4, 0, {0}};
        if (inet_pton(AF_INET, ip, la.ip) != 1) die("bad ip %s", ip);
        libp2p_listen_result lr;
        if (libp2p_shell_listen(shell, &la, &lr) || lr.error) die("listen: %s", strerror((int)lr.error));
        int port = (int)lr.addr.port;
        struct sockaddr_in me;
        socklen_t ml = sizeof me;
        getsockname(rfd, (struct sockaddr *)&me, &ml);   /* the address the dialer can reach */
        char ipbuf[64], maddr[256];
        inet_ntop(AF_INET, &me.sin_addr, ipbuf, sizeof ipbuf);
        snprintf(maddr, sizeof maddr, "/ip4/%s/tcp/%d/p2p/%s", ipbuf, port, id58);
        logf_("listening on %s", maddr);
        char key[80];
        snprintf(key, sizeof key, gossip_mode ? "addr-%s" : "listenerAddr", gs_name);
        int copies = gossip_mode && getenv("COPIES") ? atoi(getenv("COPIES")) : 1;
        for (int i = 0; i < copies; i++) {
            const char *argv[] = {"RPUSH", key, maddr};
            redis_cmd(rfd, 3, argv);
            redis_read(rfd, reply, sizeof reply);
        }
        while (!gossip_mode && now_ms() < deadline) {
            step();
            uint64_t now = now_ms();
            int wait = wake_at > now ? (int)(wake_at - now) : 0;
            if (wait > 1000) wait = 1000;
            if (((uint64_t *)events)[2] == 0) poll_once(wait);
        }
        if (!gossip_mode) die("listener timed out");
    }

    if (gossip_mode) {
        size_t tl = strlen(GS_TOPIC);
        uint8_t *e = ev_add(EV_SUBSCRIBE, 24 + tl);
        ((uint64_t *)e)[2] = tl;
        memcpy(e + 24, GS_TOPIC, tl);
        const char *dial = getenv("DIAL");
        if (dial && *dial) {
            char keys[256];
            snprintf(keys, sizeof keys, "%s", dial);
            for (char *k = strtok(keys, ","); k; k = strtok(NULL, ",")) {
                const char *bl[] = {"BLPOP", k, "60"};
                int rf = tcp_connect_host(redis);
                redis_cmd(rf, 3, bl);
                int n = redis_read(rf, reply, sizeof reply);
                close(rf);
                char *v = reply;
                for (int lines = 0; lines < 4 && v < reply + n; v++)
                    if (*v == '\n') lines++;
                char *cr = strstr(v, "\r\n");
                if (cr) *cr = 0;
                logf_("%s dialling %s", gs_name, v);
                ev_dial *d = ev_add(EV_DIAL, sizeof *d);
                d->tag = 2;
                parse_multiaddr(v, d);
            }
        }
        int count = getenv("COUNT") ? atoi(getenv("COUNT")) : 5;
        int secs = getenv("SECS") ? atoi(getenv("SECS")) : 10;
        uint64_t start = now_ms(), next_pub = start + 4000;
        int published = 0;
        while (now_ms() < start + 4000 + (uint64_t)count * 500 + (uint64_t)secs * 1000) {
            if (published < count && now_ms() >= next_pub) {
                char msg[64];
                int ml = snprintf(msg, sizeof msg, "from-%s-%d", gs_name, published);
                struct { uint64_t size, offset, count; uint8_t b[64]; } bl = {sizeof bl, 24, (uint64_t)ml, {0}};
                memcpy(bl.b, msg, ml);
                uint8_t digest[32];
                crypto_sha256(&bl, digest);
                size_t tla = (tl + 7) & ~7UL;
                uint8_t *pe = ev_add(EV_PUBLISH, 72 + tla + (uint64_t)ml);
                ((uint64_t *)pe)[2] = 20;
                memcpy(pe + 24, digest, 20);
                ((uint64_t *)pe)[7] = tl;
                ((uint64_t *)pe)[8] = (uint64_t)ml;
                memcpy(pe + 72, GS_TOPIC, tl);
                memcpy(pe + 72 + tla, msg, ml);
                published++;
                next_pub += 500;
            }
            step();
            uint64_t now = now_ms();
            int wait = wake_at > now ? (int)(wake_at - now) : 0;
            if (wait > 100) wait = 100;
            if (((uint64_t *)events)[2] == 0) poll_once(wait);
        }
        printf("%s TOTAL %d\n", gs_name, gs_got);
        if (getenv("TRACE")) {          /* debug: the stream table (offsets of include/state.inc) */
            uint8_t *st = state;
            uint64_t off = *(uint64_t *)(st + 1176), cnt = *(uint64_t *)(st + 1184);
            for (uint64_t i = 0; i < cnt; i++) {
                uint8_t *sl = st + off + i * 360;
                if (!*(uint32_t *)(sl + 4)) continue;
                fprintf(stderr, "stream %llu: id %llu flags %llx kind %llu ms_len %llu rpc_len %llu got %llu q %llu sendwin %llu\n",
                        (unsigned long long)i, (unsigned long long)*(uint64_t *)(sl + 16), (unsigned long long)*(uint64_t *)(sl + 24),
                        (unsigned long long)*(uint64_t *)(sl + 32), (unsigned long long)*(uint64_t *)(sl + 136),
                        (unsigned long long)*(uint64_t *)(sl + 320), (unsigned long long)*(uint64_t *)(sl + 328),
                        (unsigned long long)*(uint64_t *)(sl + 104), (unsigned long long)*(uint64_t *)(sl + 64));
            }
        }
        return 0;
    }

    char tmo[16];
    snprintf(tmo, sizeof tmo, "%d", timeout);
    const char *argv[] = {"BLPOP", "listenerAddr", tmo};
    redis_cmd(rfd, 3, argv);
    int n = redis_read(rfd, reply, sizeof reply);
    /* *2\r\n$12\r\nlistenerAddr\r\n$<n>\r\n<value>\r\n */
    char *v = reply;
    for (int lines = 0; lines < 4 && v < reply + n; v++)
        if (*v == '\n') lines++;
    char *cr = strstr(v, "\r\n");
    if (cr) *cr = 0;
    logf_("dialling %s", v);
    ev_dial *d = ev_add(EV_DIAL, sizeof *d);
    d->tag = 1;
    parse_multiaddr(v, d);
    t_start = now_f();
    while (!done && now_ms() < deadline) {
        step();
        if (done) break;
        uint64_t now = now_ms();
        int wait = wake_at > now ? (int)(wake_at - now) : 0;
        if (wait > 1000) wait = 1000;
        if (((uint64_t *)events)[2] == 0) poll_once(wait);
    }
    if (!done) die("dialer timed out");
    return 0;
}

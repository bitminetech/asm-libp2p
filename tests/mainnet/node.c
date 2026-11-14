/*
 * A live test against Ethereum mainnet consensus clients over TCP.
 *
 * Usage: node PEERS DIGEST [DIALS] [SECONDS]
 *   PEERS    the output of tests/mainnet/peers.py
 *   DIGEST   the fork digest of the network, 8 hex digits; peers with
 *            another digest are skipped
 *   DIALS    peers to dial (default 100)
 *   SECONDS  run time (default 120)
 * Environment: ONLY=IP dials only that address; TRACE=1 prints the bytes of
 * each connection and every failure with its address.
 *
 * The node uses a secp256k1 identity, offers yamux then mplex, and dials
 * the peers. On each connection it sends a Status request, answers Status,
 * Ping, Metadata and Goodbye requests (phase0 p2p-interface req/resp, as
 * Lantern will), subscribes to the global gossip topics and counts the
 * messages it gets. Messages are reported IGNORE, so the node never
 * forwards them. Each status line and the summary go to stdout.
 *
 * Req/resp lives in this test, not in the library: the library gives
 * streams. Snappy here is test code.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../runner/libp2p.h"

LIBP2P_ABI uint64_t crypto_sha256(const void *message, void *digest);

#define EV_ROOM (64u << 20)
#define ACT_ROOM (64u << 20)
#define MAX_TRACK 8192

static const char *PROTOS[] = {
    "/eth2/beacon_chain/req/status/2/ssz_snappy",   "/eth2/beacon_chain/req/status/1/ssz_snappy",
    "/eth2/beacon_chain/req/ping/1/ssz_snappy",     "/eth2/beacon_chain/req/metadata/3/ssz_snappy",
    "/eth2/beacon_chain/req/metadata/2/ssz_snappy", "/eth2/beacon_chain/req/goodbye/1/ssz_snappy",
};
enum { P_STATUS2, P_STATUS1, P_PING, P_META3, P_META2, P_GOODBYE, NPROTO };
static const char *TOPICS[] = {
    "beacon_block", "beacon_aggregate_and_proof", "voluntary_exit", "proposer_slashing", "attester_slashing",
    "sync_committee_contribution_and_proof", "bls_to_execution_change",
};
#define NTOPIC (sizeof TOPICS / sizeof TOPICS[0])

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

/* ---------------------------------------------------------------- Snappy (test code) */

static uint32_t crc32c(const uint8_t *p, size_t n) {
    uint32_t c = 0xFFFFFFFF;
    for (size_t i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0x82F63B78 & (0u - (c & 1)));
    }
    return ~c;
}

/* The snappy block format: the length of out, or -1. */
static long snappy_block(const uint8_t *in, size_t n, uint8_t *out, size_t cap) {
    size_t i = 0, o = 0;
    uint64_t len = 0;
    for (int shift = 0;; shift += 7) {
        if (i >= n || shift > 28) return -1;
        uint8_t b = in[i++];
        len |= (uint64_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) break;
    }
    if (len > cap) return -1;
    while (i < n) {
        uint8_t tag = in[i++];
        size_t l, off;
        if ((tag & 3) == 0) {
            l = tag >> 2;
            if (l >= 60) {
                size_t nb = l - 59;
                if (i + nb > n) return -1;
                l = 0;
                for (size_t k = 0; k < nb; k++) l |= (size_t)in[i + k] << (8 * k);
                i += nb;
            }
            l += 1;
            if (i + l > n || o + l > len) return -1;
            memcpy(out + o, in + i, l);
            i += l;
            o += l;
            continue;
        }
        if ((tag & 3) == 1) {
            if (i + 1 > n) return -1;
            l = ((tag >> 2) & 7) + 4;
            off = ((size_t)(tag >> 5) << 8) | in[i];
            i += 1;
        } else if ((tag & 3) == 2) {
            if (i + 2 > n) return -1;
            l = (size_t)(tag >> 2) + 1;
            off = in[i] | ((size_t)in[i + 1] << 8);
            i += 2;
        } else {
            if (i + 4 > n) return -1;
            l = (size_t)(tag >> 2) + 1;
            off = in[i] | ((size_t)in[i + 1] << 8) | ((size_t)in[i + 2] << 16) | ((size_t)in[i + 3] << 24);
            i += 4;
        }
        if (off == 0 || off > o || o + l > len) return -1;
        for (size_t k = 0; k < l; k++, o++) out[o] = out[o - off];
    }
    return o == len ? (long)o : -1;
}

/* The snappy framing format, until want bytes: the bytes read from in, or -1 (bad) or 0 (needs more). */
static long snappy_frames(const uint8_t *in, size_t n, uint8_t *out, size_t want) {
    size_t i = 0, o = 0;
    static uint8_t block[1 << 17];
    while (o < want) {
        if (i + 4 > n) return 0;
        uint8_t type = in[i];
        size_t l = in[i + 1] | ((size_t)in[i + 2] << 8) | ((size_t)in[i + 3] << 16);
        if (i + 4 + l > n) return 0;
        const uint8_t *d = in + i + 4;
        if (type == 0x00 || type == 0x01) {
            if (l < 4) return -1;
            long got;
            if (type == 0x00) {
                got = snappy_block(d + 4, l - 4, block, sizeof block);
                if (got < 0) return -1;
            } else {
                got = (long)(l - 4);
                memcpy(block, d + 4, l - 4);
            }
            uint32_t c = crc32c(block, (size_t)got);
            c = ((c >> 15) | (c << 17)) + 0xA282EAD8;
            if (c != (uint32_t)(d[0] | d[1] << 8 | d[2] << 16 | (uint32_t)d[3] << 24)) return -1;
            if (o + (size_t)got > want) return -1;
            memcpy(out + o, block, (size_t)got);
            o += (size_t)got;
        } else if (type == 0xFF) {
            if (l != 6 || memcmp(d, "sNaPpY", 6)) return -1;
        } else if (type < 0x80) {
            return -1;
        }
        i += 4 + l;
    }
    return (long)i;
}

/* One ssz_snappy payload: varint length, stream identifier, uncompressed chunk. Returns the bytes written. */
static size_t encode_payload(const uint8_t *ssz, size_t n, uint8_t *out) {
    size_t o = 0, v = n;
    do {
        out[o++] = (uint8_t)((v & 0x7F) | (v > 0x7F ? 0x80 : 0));
        v >>= 7;
    } while (v);
    static const uint8_t id[] = {0xFF, 0x06, 0x00, 0x00, 's', 'N', 'a', 'P', 'p', 'Y'};
    memcpy(out + o, id, sizeof id);
    o += sizeof id;
    size_t l = n + 4;
    out[o++] = 0x01;
    out[o++] = (uint8_t)l;
    out[o++] = (uint8_t)(l >> 8);
    out[o++] = (uint8_t)(l >> 16);
    uint32_t c = crc32c(ssz, n);
    c = ((c >> 15) | (c << 17)) + 0xA282EAD8;
    out[o++] = (uint8_t)c;
    out[o++] = (uint8_t)(c >> 8);
    out[o++] = (uint8_t)(c >> 16);
    out[o++] = (uint8_t)(c >> 24);
    memcpy(out + o, ssz, n);
    return o + n;
}

/* ---------------------------------------------------------------- Library glue */

static void *state, *scratch, *shell;
static uint8_t *events, *actions;
static uint64_t wake_at;

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

static void close_stream(uint64_t stream) {
    ev_conn *c = ev_add(EV_STREAM_CLOSE, 24);
    c->conn = stream;
}

/* ---------------------------------------------------------------- Streams and counts */

typedef struct {
    uint64_t handle;
    int used, kind;        /* kind: a protocol index; outbound status streams add 100 */
    uint8_t *buf;
    size_t len, cap;
} track;
static track tracks[MAX_TRACK];

static track *track_of(uint64_t h, int make) {
    track *free_slot = NULL;
    for (int i = 0; i < MAX_TRACK; i++) {
        if (tracks[i].used && tracks[i].handle == h) return &tracks[i];
        if (!tracks[i].used && !free_slot) free_slot = &tracks[i];
    }
    if (!make || !free_slot) return NULL;
    free_slot->used = 1;
    free_slot->handle = h;
    free_slot->len = 0;
    return free_slot;
}

static void track_drop(track *t) {
    free(t->buf);
    memset(t, 0, sizeof *t);
}

static uint64_t msg_handle[MAX_TRACK];
static int msg_topic[MAX_TRACK];

static char dial_ip[4096][64];
static int trace;
static int connected, peak, dial_failed[16], stream_failed[16], statuses, inbound[NPROTO], goodbyes;
static long topic_new[NTOPIC], topic_dup, subscriptions;
static uint8_t digest[4];
static char topic_names[NTOPIC][128];

static uint64_t goodbye_reason[8][2];

/* Our Status: the digest, and the finalized and head checkpoints the last peer gave. */
static uint8_t status_body[92];

static void status_payload(int version, uint8_t *out, size_t *n) {
    uint8_t ssz[92];
    memcpy(ssz, status_body, 92);
    memcpy(ssz, digest, 4);
    *n = encode_payload(ssz, version == 2 ? 92 : 84, out);
}

static void answer(track *t) {
    uint8_t out[256], ssz[32];
    size_t n = 0;
    out[n++] = 0;                                   /* result: success */
    switch (t->kind) {
    case P_STATUS2:
    case P_STATUS1: {
        size_t m;
        status_payload(t->kind == P_STATUS2 ? 2 : 1, out + n, &m);
        n += m;
        break;
    }
    case P_PING:
        memset(ssz, 0, 8);                          /* metadata seq_number 0 */
        n += encode_payload(ssz, 8, out + n);
        break;
    case P_META3:
    case P_META2:
        memset(ssz, 0, sizeof ssz);                 /* seq 0, no attnets, no syncnets */
        if (t->kind == P_META3) ssz[17] = 4;        /* custody_group_count 4 */
        n += encode_payload(ssz, t->kind == P_META3 ? 25 : 17, out + n);
        break;
    case P_GOODBYE: {
        goodbyes++;
        n = 0;
        uint8_t r[8];
        size_t i = 0;
        while (i < t->len && (t->buf[i] & 0x80)) i++;
        if (i + 1 < t->len && snappy_frames(t->buf + i + 1, t->len - i - 1, r, 8) > 0) {
            uint64_t reason;
            memcpy(&reason, r, 8);
            for (int k = 0; k < 8; k++)
                if (goodbye_reason[k][0] == reason || goodbye_reason[k][1] == 0) {
                    goodbye_reason[k][0] = reason;
                    goodbye_reason[k][1]++;
                    break;
                }
        }
        break;
    }
    }
    if (n) write_stream(t->handle, out, n);
    close_stream(t->handle);
}

/* A Status response on an outbound stream: prints it and keeps its checkpoints. */
static void read_status(track *t, int version) {
    size_t want = version == 2 ? 92 : 84;
    if (t->len < 2) {
        printf("status: empty response\n");
        return;
    }
    if (t->buf[0] != 0) {
        printf("status: result %u\n", t->buf[0]);
        return;
    }
    size_t i = 1, len = 0;
    for (int shift = 0; i < t->len; shift += 7) {
        uint8_t b = t->buf[i++];
        len |= (size_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) break;
    }
    uint8_t ssz[92];
    if (len != want || snappy_frames(t->buf + i, t->len - i, ssz, want) <= 0) {
        printf("status: bad payload (length %zu)\n", len);
        return;
    }
    uint64_t fin_epoch, head_slot;
    memcpy(&fin_epoch, ssz + 36, 8);
    memcpy(&head_slot, ssz + 76, 8);
    printf("status v%d: digest %02x%02x%02x%02x finalized epoch %llu head slot %llu\n", version, ssz[0], ssz[1],
           ssz[2], ssz[3], (unsigned long long)fin_epoch, (unsigned long long)head_slot);
    statuses++;
    if (!memcmp(ssz, digest, 4)) memcpy(status_body + 4, ssz + 4, 80);   /* finalized and head */
}

/* The gossip message ID: SHA-256 of domain, topic length, topic and data, first 20 bytes. */
static void message_id(const uint8_t *topic, size_t tl, const uint8_t *data, size_t dl, uint8_t *id) {
    static uint8_t plain[11 << 20];
    static struct { uint64_t size, offset, count; uint8_t b[(11 << 20) + 512]; } msg;
    long n = snappy_block(data, dl, plain, sizeof plain);
    size_t o = 0;
    const uint8_t valid[4] = {1, 0, 0, 0}, invalid[4] = {0, 0, 0, 0};
    memcpy(msg.b, n >= 0 ? valid : invalid, 4);
    o = 4;
    uint64_t l = tl;
    memcpy(msg.b + o, &l, 8);
    o += 8;
    memcpy(msg.b + o, topic, tl);
    o += tl;
    if (n >= 0) {
        memcpy(msg.b + o, plain, (size_t)n);
        o += (size_t)n;
    } else {
        memcpy(msg.b + o, data, dl);
        o += dl;
    }
    msg.size = sizeof msg;
    msg.offset = 24;
    msg.count = o;
    uint8_t d[32];
    crypto_sha256(&msg, d);
    memcpy(id, d, 20);
}

static void handle_actions(void) {
    uint64_t *h = (uint64_t *)actions;
    uint8_t *p = actions + h[1], *end = p + h[2];
    while (p < end) {
        libp2p_header *a = (libp2p_header *)p;
        switch (a->kind) {
        case ACT_WAKEUP: wake_at = ((uint64_t *)p)[2]; break;
        case ACT_PEER_CONNECTED: {
            act_peer_connected *d = (act_peer_connected *)p;
            connected++;
            if (connected > peak) peak = connected;
            if (d->direction == 1) {
                ev_open_stream *o = ev_add(EV_OPEN_STREAM, sizeof *o + 2 * sizeof(libp2p_proto));
                o->peer = d->peer;
                o->tag = d->peer;
                o->count = 2;
                for (int k = 0; k < 2; k++) {
                    o->protocols[k].len = strlen(PROTOS[k]);
                    memcpy(o->protocols[k].bytes, PROTOS[k], strlen(PROTOS[k]));
                }
            }
            break;
        }
        case ACT_PEER_DISCONNECTED:
            connected--;
            if (trace) printf("peer %llx disconnected\n", (unsigned long long)((act_peer_disconnected *)p)->peer);
            break;
        case ACT_DIAL_FAILED: {
            act_failed *d = (act_failed *)p;
            dial_failed[d->reason & 15]++;
            if (trace) printf("dial %s failed, reason %llu\n", dial_ip[d->tag & 4095], (unsigned long long)d->reason);
            break;
        }
        case ACT_SEND:
            if (trace) {
                act_send *d = (act_send *)p;
                printf("conn %llx send %llu:", (unsigned long long)d->conn, (unsigned long long)d->count);
                for (uint64_t k = 0; k < d->count && k < 48; k++) printf(" %02x", d->data[k]);
                printf("\n");
            }
            break;
        case ACT_DIAL:
            if (trace) printf("conn %llx dial\n", (unsigned long long)((act_dial *)p)->conn);
            break;
        case ACT_STREAM_FAILED: stream_failed[((act_failed *)p)->reason & 15]++; break;
        case ACT_STREAM_OPENED: {
            act_stream_opened *d = (act_stream_opened *)p;
            int version = d->index == 0 ? 2 : 1;
            track *t = track_of(d->stream, 1);
            if (!t) break;
            t->kind = 100 + version;
            uint8_t out[160];
            size_t n;
            status_payload(version, out, &n);
            write_stream(d->stream, out, n);
            close_stream(d->stream);
            break;
        }
        case ACT_STREAM_INBOUND: {
            act_stream_inbound *d = (act_stream_inbound *)p;
            track *t = track_of(d->stream, 1);
            if (!t) break;
            t->kind = (int)d->protocol;
            if (d->protocol < NPROTO) inbound[d->protocol]++;
            break;
        }
        case ACT_STREAM_DATA: {
            act_stream_data *d = (act_stream_data *)p;
            track *t = track_of(d->stream, 0);
            if (!t) break;
            if (t->len + d->count > t->cap) {
                t->cap = (t->len + d->count) * 2;
                t->buf = realloc(t->buf, t->cap);
            }
            memcpy(t->buf + t->len, d->data, d->count);
            t->len += d->count;
            break;
        }
        case ACT_STREAM_EOF: {
            track *t = track_of(((act_stream_data *)p)->stream, 0);
            if (!t) break;
            if (t->kind >= 100) {
                read_status(t, t->kind - 100);
                close_stream(t->handle);
            } else {
                answer(t);
            }
            track_drop(t);
            break;
        }
        case ACT_STREAM_RESET: {
            track *t = track_of(((act_stream_data *)p)->stream, 0);
            if (t) track_drop(t);
            break;
        }
        case ACT_MESSAGE: {
            act_message *m = (act_message *)p;
            const uint8_t *data = (const uint8_t *)state + m->data_off;
            ev_message_id *e = ev_add(EV_MESSAGE_ID, sizeof *e);
            e->handle = m->handle;
            e->id_len = 20;
            message_id(m->topic, m->topic_len, data, m->data_len, e->id);
            int slot = (int)(m->handle % MAX_TRACK);
            msg_handle[slot] = m->handle;
            msg_topic[slot] = -1;
            for (size_t k = 0; k < NTOPIC; k++)
                if (strlen(topic_names[k]) == m->topic_len && !memcmp(topic_names[k], m->topic, m->topic_len))
                    msg_topic[slot] = (int)k;
            break;
        }
        case ACT_MESSAGE_STATUS: {
            act_message_status *m = (act_message_status *)p;
            if (m->status == MSG_NEW) {
                int slot = (int)(m->handle % MAX_TRACK);
                if (msg_handle[slot] == m->handle && msg_topic[slot] >= 0) topic_new[msg_topic[slot]]++;
                ev_conn *e = ev_add(EV_VALIDATION, 32);
                e->conn = m->handle;
                e->value = LIBP2P_IGNORE;
            } else if (m->status == MSG_DUPLICATE) {
                topic_dup++;
            }
            break;
        }
        case ACT_PEER_TOPIC: subscriptions += ((act_peer_topic *)p)->subscribed ? 1 : -1; break;
        default: break;
        }
        p += a->size;
    }
}

static void trace_events(void) {
    uint64_t *h = (uint64_t *)events;
    uint8_t *p = events + h[1], *end = p + h[2];
    while (p < end) {
        libp2p_header *a = (libp2p_header *)p;
        if (a->kind == EV_RECEIVED) {
            ev_received *r = (ev_received *)p;
            printf("conn %llx recv %llu:", (unsigned long long)r->conn, (unsigned long long)r->count);
            for (uint64_t k = 0; k < r->count && k < 48; k++) printf(" %02x", r->data[k]);
            printf("\n");
        } else if (a->kind == EV_CLOSED || a->kind == EV_DIAL_FAILED || a->kind == EV_CONNECTED) {
            ev_conn *c = (ev_conn *)p;
            printf("conn %llx event %llu value %llu\n", (unsigned long long)c->conn, (unsigned long long)a->kind,
                   (unsigned long long)c->value);
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

static uint64_t now_ms(void) {
    libp2p_tick t;
    if (libp2p_shell_clock(&t)) die("libp2p_shell_clock");
    return t.now;
}

static void summary(uint64_t secs) {
    printf("t=%llus connected %d (peak %d), statuses %d, inbound status %d+%d ping %d metadata %d+%d goodbye %d, "
           "peer subscriptions %ld\n",
           (unsigned long long)secs, connected, peak, statuses, inbound[P_STATUS2], inbound[P_STATUS1],
           inbound[P_PING], inbound[P_META3], inbound[P_META2], goodbyes, subscriptions);
    printf("  messages:");
    for (size_t k = 0; k < NTOPIC; k++) printf(" %s %ld", TOPICS[k], topic_new[k]);
    printf(", duplicates %ld\n", topic_dup);
    printf("  dial failures by reason:");
    for (int k = 0; k < 16; k++)
        if (dial_failed[k]) printf(" %d:%d", k, dial_failed[k]);
    printf("; goodbye reasons:");
    for (int k = 0; k < 8; k++)
        if (goodbye_reason[k][1]) printf(" %llu:%llu", (unsigned long long)goodbye_reason[k][0], (unsigned long long)goodbye_reason[k][1]);
    printf("; stream failures by reason:");
    for (int k = 0; k < 16; k++)
        if (stream_failed[k]) printf(" %d:%d", k, stream_failed[k]);
    printf("\n");
    fflush(stdout);
}

int main(int argc, char **argv) {
    if (argc < 3) die("usage: node PEERS DIGEST [DIALS] [SECONDS]");
    unsigned dg;
    if (sscanf(argv[2], "%8x", &dg) != 1) die("bad digest %s", argv[2]);
    for (int k = 0; k < 4; k++) digest[k] = (uint8_t)(dg >> (24 - 8 * k));
    int dials = argc > 3 ? atoi(argv[3]) : 100;
    uint64_t secs = argc > 4 ? (uint64_t)atoi(argv[4]) : 120;
    setvbuf(stdout, NULL, _IOLBF, 0);

    struct { libp2p_config c; libp2p_proto p[NPROTO]; } cfg;
    libp2p_config *c = &cfg.c;
    memset(&cfg, 0, sizeof cfg);
    libp2p_tick t0;
    if (libp2p_shell_clock(&t0)) die("libp2p_shell_clock");
    c->size = sizeof cfg;
    c->key_type = LIBP2P_KEY_SECP256K1;
    memcpy(c->private_key, t0.entropy, 32);         /* below the curve order with overwhelming probability */
    c->private_key[0] &= 0x7F;
    if (libp2p_shell_clock(&t0)) die("libp2p_shell_clock");
    memcpy(c->entropy, t0.entropy, 32);
    c->now = t0.now;
    c->max_connections = 256; c->max_streams = 4096; c->max_peers = 256; c->max_topics = 16;
    c->heap_size = 1ull << 30; c->seen_capacity = 65536; c->mcache_capacity = 8192; c->pending_capacity = 4096;
    c->muxers = 3;
    c->send_window = 1 << 20; c->max_rpc = 11 << 20; c->max_data = 10 << 20;
    c->handshake_ms = 10000; c->validation_ms = 5000; c->stream_queue = 1 << 20;
    c->protocols = sizeof cfg.c; c->protocols_count = NPROTO;
    for (int k = 0; k < NPROTO; k++) {
        cfg.p[k].len = strlen(PROTOS[k]);
        memcpy(cfg.p[k].bytes, PROTOS[k], strlen(PROTOS[k]));
    }
    c->d = 8; c->d_low = 6; c->d_high = 12; c->d_lazy = 6; c->d_score = 4; c->d_out = 2; c->heartbeat_ms = 700;
    c->fanout_ttl_ms = 60000; c->mcache_len = 6; c->mcache_gossip = 3; c->seen_ttl_ms = 384000;
    c->prune_backoff_ms = 60000; c->unsub_backoff_ms = 10000; c->graft_flood_ms = 10000; c->flood_publish = 1;
    c->gossip_factor = 0.25; c->max_ihave_length = 5000; c->max_ihave_messages = 10; c->iwant_followup_ms = 3000;
    c->retransmission = 3; c->opportunistic_ticks = 60; c->opportunistic_peers = 2;
    c->agent_len = strlen("asm-libp2p/0.1.0");
    memcpy(c->agent, "asm-libp2p/0.1.0", c->agent_len);
    c->pv_len = strlen("eth2/1.0.0");
    memcpy(c->pv, "eth2/1.0.0", c->pv_len);

    uint64_t size = 0;
    if (libp2p_state_size(&cfg, &size)) die("libp2p_state_size");
    state = calloc(1, size);
    if (!state) die("no memory for %llu state bytes", (unsigned long long)size);
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

    for (size_t k = 0; k < NTOPIC; k++) {
        snprintf(topic_names[k], sizeof topic_names[k], "/eth2/%02x%02x%02x%02x/%s/ssz_snappy", digest[0], digest[1],
                 digest[2], digest[3], TOPICS[k]);
        size_t tl = strlen(topic_names[k]);
        uint8_t *e = ev_add(EV_SUBSCRIBE, 24 + tl);
        ((uint64_t *)e)[2] = tl;
        memcpy(e + 24, topic_names[k], tl);
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) die("cannot read %s", argv[1]);
    char ip[64], idhex[128], dhex[16];
    int port, n = 0;
    trace = getenv("TRACE") != NULL;
    const char *only = getenv("ONLY");
    while (n < dials && n < 4096 && fscanf(f, "%63s %d %127s %15s", ip, &port, idhex, dhex) == 4) {
        if (strcmp(dhex, argv[2]) || (only && strcmp(ip, only))) continue;
        snprintf(dial_ip[n], sizeof dial_ip[n], "%s:%d", ip, port);
        ev_dial *d = ev_add(EV_DIAL, sizeof *d);
        d->tag = (uint64_t)n;
        d->addr.family = 4;
        d->addr.port = (uint64_t)port;
        if (inet_pton(AF_INET, ip, d->addr.ip) != 1) die("bad ip %s", ip);
        d->id_len = strlen(idhex) / 2;
        for (size_t k = 0; k < d->id_len; k++) sscanf(idhex + 2 * k, "%2hhx", &d->id[k]);
        n++;
    }
    fclose(f);
    printf("dialling %d peers for %llu s\n", n, (unsigned long long)secs);

    uint64_t start = now_ms(), next_report = start + 10000;
    while (now_ms() < start + secs * 1000) {
        step();
        uint64_t now = now_ms();
        if (now >= next_report) {
            summary((now - start) / 1000);
            next_report += 10000;
        }
        uint64_t wait = wake_at > now ? wake_at - now : 0;
        if (wait > 200) wait = 200;
        if (((uint64_t *)events)[2] == 0) {
            if (libp2p_shell_wait(shell, &wait, events)) die("libp2p_shell_wait");
            if (trace) trace_events();
        }
    }
    summary(secs);
    libp2p_shell_close(shell);
    return 0;
}

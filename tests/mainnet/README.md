# Mainnet test

`node.c` connects to Ethereum mainnet consensus clients over TCP and QUIC and takes part in their gossip. It is test code in C; the library itself is pure assembly. Request/response and Snappy live in this test, as they will live in Lantern: the library gives streams.

```bash
python3 -I tests/mainnet/peers.py < records.txt > peers.txt
```

```bash
build/macos-arm64/mainnet peers.txt 8c9f62fe 300 300
```

| File | What it does |
|---|---|
| `peers.py` | Reads every `enr:` record in its input, such as the log of a discv5 crawl, and writes one line for the TCP port and one for the QUIC port of each record with an IPv4 address and a secp256k1 key: IP, port, peer ID, fork digest and transport (`tcp` or `quic`). It skips record values that are lists. |
| `node.c` | The live node. `node PEERS DIGEST [DIALS] [SECONDS]`: dials up to DIALS lines (default 100) whose fork digest is DIGEST, and runs for SECONDS (default 120). |

[platform/linux/build.sh](../../platform/linux/build.sh) builds it as `build/linux-<ISA>/mainnet`; [platform/macos/link-runner.sh](../../platform/macos/link-runner.sh) links it as `build/macos-<ISA>/mainnet`.

## The node

- Uses a secp256k1 identity, and offers yamux, then mplex, over TCP.
- Has QUIC on, binds one UDP socket on 0.0.0.0, and dials the `quic` lines over QUIC.
- On each connection, sends a Status request, and answers Status, Ping, Metadata and Goodbye requests (phase0 p2p-interface req/resp).
- Subscribes to the global gossip topics, computes each message ID as the consensus specs define, and counts new and duplicate messages.
- Speaks gossipsub v1.3 with the Partial Messages extension: joins the data column subnets 0 to 7 asking for partial messages, and counts PARTIAL actions, the peers that sent them, and the partial peers in the mesh of subnet 0.
- Reports every message IGNORE, so it never forwards one.
- Prints each Status response it gets, and a summary every 10 seconds, with the QUIC peers and the gossip messages that came over QUIC.
- `ONLY=IP` dials only that address. `TRANSPORT=tcp` or `TRANSPORT=quic` dials only the lines of that transport. `TRACE=1` prints the bytes of each TCP connection, and each failure with its address.

## Results

### QUIC

Run on 2026-11-15, on macOS ARM64, with the lines of digest `8c9f62fe` from a discv5 crawl of 3000 records (751 `tcp` lines, 673 `quic` lines): `TRANSPORT=quic mainnet peers.txt 8c9f62fe 300 300`. Every peer and message of this run came over QUIC.

| Item | Count |
|---|---|
| Peers connected at once, most | 84 |
| Status responses | 55 |
| Requests answered | Status 2, Ping 12, Metadata 13 |
| Goodbye requests | 20, all reason 129 |
| New gossip messages | beacon_block 25, beacon_aggregate_and_proof 6672, sync_committee_contribution_and_proof 610, data_column_sidecar 0 to 7: 35 |
| Duplicate gossip messages | 2407 |
| PARTIAL actions | 138 from 14 peers: 138 with parts metadata, 24 with a partial message, 23188 bytes |
| Failed dials | CONNECT 160, HANDSHAKE 3, PEER_ID 4, LIMIT 44 (300 dials, 256 connection slots) |
| Failed streams | CLOSED 31 |

- Peers end QUIC connections with fewer Goodbye requests than TCP ones. A 60 second debug run that printed the reason of each asm-quic CLOSED action gave: closed by the peer with code 0: 53; with code 0x1007 (go-libp2p `ConnGated`): 17; with code 0x47415445: 2; idle timeout: 4.

### TCP

Run on 2026-11-14, on macOS ARM64, with 252 records of digest `8c9f62fe` from a discv5 crawl: `mainnet peers.txt 8c9f62fe 300 300`.

| Item | Count |
|---|---|
| Peers connected at once, most | 96 |
| Status responses | 115 |
| Requests answered | Status 2, Ping 86, Metadata 20 |
| Goodbye requests | 115: reason 129 for 114, reason 3 for 1 |
| New gossip messages | beacon_block 25, beacon_aggregate_and_proof 6710, sync_committee_contribution_and_proof 432, data_column_sidecar 0 to 7: 94 |
| Duplicate gossip messages | 3392 |
| PARTIAL actions | 494 from 26 peers: 494 with parts metadata, 101 with a partial message, 105185 bytes |
| Partial peers in the mesh of data_column_sidecar_0, most | 3 |
| Failed dials | CONNECT 58, HANDSHAKE 4, PEER_ID 2, CLOSED 59 |
| Failed streams | NO_PEER 5, CLOSED 4 |

# Mainnet test

`node.c` connects to Ethereum mainnet consensus clients over TCP and takes part in their gossip. It is test code in C; the library itself is pure assembly. Request/response and Snappy live in this test, as they will live in Lantern: the library gives streams.

```bash
python3 -I tests/mainnet/peers.py < records.txt > peers.txt
```

```bash
build/macos-arm64/mainnet peers.txt 8c9f62fe 300 300
```

| File | What it does |
|---|---|
| `peers.py` | Reads every `enr:` record in its input, such as the log of a discv5 crawl, and writes one line per record with an IPv4 address, a TCP port and a secp256k1 key: IP, port, peer ID and fork digest. |
| `node.c` | The live node. `node PEERS DIGEST [DIALS] [SECONDS]`: dials up to DIALS peers (default 100) whose fork digest is DIGEST, and runs for SECONDS (default 120). |

[platform/linux/build.sh](../../platform/linux/build.sh) builds it as `build/linux-<ISA>/mainnet`; [platform/macos/link-runner.sh](../../platform/macos/link-runner.sh) links it as `build/macos-<ISA>/mainnet`.

## The node

- Uses a secp256k1 identity, and offers yamux, then mplex.
- On each connection, sends a Status request, and answers Status, Ping, Metadata and Goodbye requests (phase0 p2p-interface req/resp).
- Subscribes to the global gossip topics, computes each message ID as the consensus specs define, and counts new and duplicate messages.
- Reports every message IGNORE, so it never forwards one.
- Prints each Status response it gets, and a summary every 10 seconds.
- `ONLY=IP` dials only that address. `TRACE=1` prints the bytes of each connection, and each failure with its address.

## Results

Run on 2026-11-14, on macOS ARM64, with 252 records of digest `8c9f62fe` from a discv5 crawl: `mainnet peers.txt 8c9f62fe 300 300`.

| Item | Count |
|---|---|
| Peers connected at once, most | 84 |
| Status responses | 108 |
| Requests answered | Status 4, Ping 29, Metadata 27 |
| Goodbye requests | 100: reason 129 for 99, reason 3 for 1 |
| New gossip messages | beacon_block 20, beacon_aggregate_and_proof 5117, sync_committee_contribution_and_proof 258 |
| Duplicate gossip messages | 3207 |
| Failed dials | CONNECT 56, HANDSHAKE 8, PEER_ID 2, CLOSED 58 |
| Failed streams | NO_PEER 5, CLOSED 5 |

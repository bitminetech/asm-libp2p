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

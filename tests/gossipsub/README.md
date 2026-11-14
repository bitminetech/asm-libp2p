# gossipsub-interop

The asm-libp2p node runs the gossipsub interop test of [libp2p/test-plans](https://github.com/libp2p/test-plans/tree/12e2ff491db21115b8e775e0eb7ee51056d203fb/gossipsub-interop) in the [Shadow](https://shadow.github.io/) simulator, alone and in networks shared with go-libp2p, rust-libp2p, jvm-libp2p and nim-libp2p. Shadow runs only on Linux x86-64.

```bash
tests/gossipsub/build.sh /path/to/work
```

```bash
tests/gossipsub/run.sh /path/to/work
```

| File | What it does |
|---|---|
| `node.c` | The asm-libp2p node of the test. Test code in C: it reads the script, turns its gossipsub parameters into the config, and writes the log lines of the suite; the library does the rest. |
| `build.sh` | `build.sh WORK_DIR [IMPLEMENTATION ...]`: checks out test-plans in WORK_DIR, builds the asm-libp2p node as the implementation `asm`, and builds the go, rust, jvm and nim nodes. |
| `run.sh` | `run.sh WORK_DIR [COMPOSITION ...]`: runs the `subnet-blob-msg` scenario in Shadow for each composition, such as `asm+go`, runs the check of the suite, and prints the means of the analysis of the suite. `NODES=n` sets the nodes of each run (default 32). |

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs both scripts on GitHub's x86-64 Ubuntu runner.

## The test

- Every node runs one script, `params.json`: it connects until each node has at least 20 random connections, subscribes to one topic, and from 120 seconds on, a random node publishes one of 16 messages of 96 KiB every 12 seconds.
- Every node waits 5 ms before it accepts a message, as a validation delay.
- The network has the latencies between 8 regions of the world, and two kinds of host: 1024 Mbit/s and 50 Mbit/s.
- Each node runs one implementation of the composition, picked at random with equal weights.
- A composition passes when every message after the first 4 reaches every node (`checks/subnet_blob_msg.py`).
- Implementations are interoperable when the composition does not change the results: the time to reach the nodes, and the duplicates.

## The node

- The host name gives the node ID: `node<ID>`.
- The identity is Ed25519, with the node ID as 8 bytes little endian, then zeros, as the seed.
- It listens on TCP port 9000, offers yamux, then mplex, and speaks `/meshsub/1.1.0`.
- A message ID is the first 8 bytes of the data; the log gives it as a big endian u64 in base 10.
- It logs "Received Message" for every message that arrives, duplicates included.
- A gossipsub parameter that the script leaves out takes the default of go-libp2p-pubsub `a01777894f4c`, the version of the go node.
- HeartbeatInitialDelay, PrunePeers, the connection parameters, SlowHeartbeatWarning and the IDONTWANT parameters have no field in the config.
- A failed dial or name lookup is tried again after 1 second, up to 10 times.
- Partial messages stop the node with an error, so the `partial-messages` scenarios do not run.
- It exits 0 after the last instruction, as the go node does.

## Pins and fixes

| Item | Value |
|---|---|
| test-plans | `12e2ff491db21115b8e775e0eb7ee51056d203fb` |
| Shadow | v3.3.0, `5a05740bad995b6dbb90b8a16effecf59eceee09` |
| Go | 1.24.1, the `go.mod` of the go node |
| Rust | 1.100.0 |
| Nim | 2.2.10, the version that nim-libp2p `22ab040` tests |
| JDK | 17 |
| uv | 0.13.6 |
| `experiment.py` | `build.sh` adds `"asm": "asm-libp2p/gossipsub-bin"` to `IMPLEMENTATIONS` |
| `run.py` | `build.sh` removes `make binaries`, which builds all 4 implementations before each run |
| go node | Built with cgo instead of `-linkshared`: Shadow needs a dynamically linked binary |
| asm-libp2p node | Linked dynamically against libc for the same reason; the library makes its system calls directly, and Shadow traps those with seccomp |

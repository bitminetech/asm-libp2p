# gossipsub-interop

The asm-libp2p node runs the gossipsub interop tests of [libp2p/test-plans](https://github.com/libp2p/test-plans/tree/12e2ff491db21115b8e775e0eb7ee51056d203fb/gossipsub-interop), from the fork [bitminetech/test-plans](https://github.com/bitminetech/test-plans/tree/32875fd08f8264f03bf1a09e47d6ccbf90b19fa2/gossipsub-interop) with one fix to the go node, in the [Shadow](https://shadow.github.io/) simulator, alone and in networks shared with go-libp2p, rust-libp2p, jvm-libp2p and nim-libp2p: the `subnet-blob-msg` scenario of full messages, and the three scenarios of partial messages. Shadow runs only on Linux x86-64.

```bash
tests/gossipsub/build.sh /path/to/work
```

```bash
tests/gossipsub/run.sh /path/to/work
```

| File | What it does |
|---|---|
| `node.c` | The asm-libp2p node of the test. Test code in C: it reads the script, turns its gossipsub parameters into the config, holds the partial messages of the test, and writes the log lines of the suite; the library does the rest. |
| `build.sh` | `build.sh WORK_DIR [IMPLEMENTATION ...]`: checks out the fork of test-plans in WORK_DIR, builds the asm-libp2p node as the implementation `asm`, and builds the go, rust, jvm and nim nodes. |
| `run.sh` | `run.sh WORK_DIR [COMPOSITION ...]`: runs the `subnet-blob-msg` scenario in Shadow for each composition, such as `asm+go`, runs the check of the suite, and prints the means of the analysis of the suite; then runs the three partial message scenarios for each partial composition, with their check. `NODES=n` sets the nodes of each `subnet-blob-msg` run (default 32); `PARTIAL` lists the partial compositions (default `asm asm+go asm+rust asm+nim`); a run past `TIMEOUT` seconds (default 900) fails, with the processes using the most CPU. It exits 1 when a run fails. |

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs both scripts on GitHub's x86-64 Ubuntu runner.

## The test

- Every node runs one script, `params.json`.
- `subnet-blob-msg`: each node connects until it has at least 20 random connections, subscribes to one topic, and from 120 seconds on, a random node publishes one of 16 messages of 96 KiB every 12 seconds.
- Every node waits 5 ms before it accepts a message, as a validation delay.
- The network has the latencies between 8 regions of the world, and two kinds of host: 1024 Mbit/s and 50 Mbit/s.
- Each node runs one implementation of the composition, picked at random with equal weights.
- A composition passes when every message after the first 4 reaches every node (`checks/subnet_blob_msg.py`).
- Implementations are interoperable when the composition does not change the results: the time to reach the nodes, and the duplicates.

### Partial messages

| Scenario | Nodes | The script | Pass |
|---|---|---|---|
| `partial-messages` | 32 | Random connections; every node asks for partial messages of one topic, holds random parts of one group, and publishes it at 30 seconds. | Every node logs "All parts received" once. |
| `partial-messages-chain` | 8 | A chain of connections; 16 groups of 8 parts, each part on one node; a group is published every 2 seconds. | Every node logs "All parts received" 16 times. |
| `partial-messages-fanout` | 8 | Random connections; node 0 holds every part, does not subscribe, and publishes to nodes 1 to 7. | Every node logs "All parts received" once. |

- A group is 8 parts of 1024 bytes. The parts metadata is one byte: a bit for each part the sender has.
- A partial message is the bitmap of its parts, the parts in order, then the 8-byte group ID.
- The check is `checks/partial_messages.py` with the count of the table.
- go, rust and nim implement partial messages in the suite; jvm does not.

## The node

- The host name gives the node ID: `node<ID>`.
- The identity is Ed25519, with the node ID as 8 bytes little endian, then zeros, as the seed.
- It listens on TCP port 9000, offers yamux, then mplex, and speaks `/meshsub/1.3.0` with the Partial Messages extension, as the go node does; `/meshsub/1.2.0` or `/meshsub/1.1.0` with an older peer.
- A message ID is the first 8 bytes of the data; the log gives it as a big endian u64 in base 10.
- It logs "Received Message" for every message that arrives, duplicates included.
- A gossipsub parameter that the script leaves out takes the default of go-libp2p-pubsub `a01777894f4c`, the version of the go node.
- IDontWantMessageThreshold, IDontWantMessageTTL, MaxIDontWantMessages and MaxIDontWantLength set the IDONTWANT fields of the config; the node keeps 256 IDs of IDONTWANT for each peer.
- HeartbeatInitialDelay, PrunePeers, the connection parameters and SlowHeartbeatWarning have no field in the config.
- A failed dial or name lookup is tried again after 1 second, up to 10 times.
- It keeps the partial messages and peer state of the go node of the suite: for each group, its parts and, for each peer, the parts the peer has and the parts it told the peer of.
- Publishing a group asks the library for the mesh with PARTIAL_PEERS, then sends each peer of the mesh and the group its metadata the first time and when it has parts the peer does not know of, and the parts the peer lacks once the peer told its own parts and wants partial messages.
- Each PARTIAL from a peer updates its state, adds its parts, and publishes the group again; PARTIAL_GOSSIP adds the gossip peers to each group of the topic.
- It logs "All parts received" when a group becomes whole.
- It exits 0 after the last instruction, as the go node does.

## Pins and fixes

| Item | Value |
|---|---|
| test-plans | The fork `bitminetech/test-plans`, branch `asm-libp2p`, commit `32875fd08f8264f03bf1a09e47d6ccbf90b19fa2`: `libp2p/test-plans` `12e2ff491db21115b8e775e0eb7ee51056d203fb` and one commit |
| Shadow | v3.3.0, `5a05740bad995b6dbb90b8a16effecf59eceee09` |
| Go | 1.24.1, the `go.mod` of the go node |
| Rust | 1.100.0 |
| Nim | 2.2.10, the version that nim-libp2p `22ab040` tests |
| JDK | 17 |
| uv | 0.13.6 |
| `experiment.py` | `build.sh` adds `"asm": "asm-libp2p/gossipsub-bin"` to `IMPLEMENTATIONS` |
| `run.py` | `build.sh` removes `make binaries`, which builds all 4 implementations before each run |
| go node | Built with cgo instead of `-linkshared`: Shadow needs a dynamically linked binary |
| go node, the commit of the fork | The callbacks of the pubsub event loop, OnIncomingRPC and OnEmitGossip, queue their work in order without blocking. In `12e2ff4` they sent to channels of 1 and 0 slots, while the goroutine that reads them calls PublishPartial, which waits for that same event loop: two partial RPCs back to back could block both for good |
| asm-libp2p node | Linked dynamically against libc for the same reason; the library makes its system calls directly, and Shadow traps those with seccomp |
| Shadow config | `run.sh` adds `experimental.native_preemption_enabled: true` for a composition with jvm: a JVM thread can spin without system calls, and Shadow then stops ("Busy loops" in Shadow's `docs/limitations.md`). Shadow preempts a thread after 100 ms of CPU time without a system call, and moves simulated time 10 ms. |

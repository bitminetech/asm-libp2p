# Test runner

`runner.c` runs the scenarios: nodes in memory, with the runner as their shell. It carries the bytes of each connection to the other node, and answers DIAL, ADOPT, REFUSE, SEND and CLOSE as a socket layer would. It carries each SEND_DATAGRAM to the node of its UDP address (node i is 10.0.0.(i + 1), port 7000 + i), and may drop every n-th. Keys, entropy and time are fixed, so every scenario is deterministic. It is test code in C; the library itself is pure assembly.

```bash
tests/runner/docker.sh
```

```bash
tests/runner/macos.sh
```

| File | What it does |
|---|---|
| `docker.sh` | Builds the Docker image, builds the library for all 7 targets into `build/`, and runs the runner and the [shell loop test](../shell/) for Linux x86-64, ARM64 and RISC-V. ISAs other than the host's run under QEMU user mode. |
| `macos.sh` | Links the runner, the shell loop test and the mainnet node on a Mac against the library that `docker.sh` built, and runs the runner and the shell loop test. |
| `tick_tables.py` | Writes the tick table of each function into its document, from the results of every target. |
| `abi_x86_64.s`, `abi_arm64.s`, `abi_riscv64.s` | `abi_call`, through which the runner calls every library function. Test code in assembly. |
| `libp2p.h` | The C view of the interface, for the tests. |

Name scenarios to run only those, for example `build/linux-arm64/runner gossip scoring`.

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs every scenario on all 7 targets: Linux on GitHub's x64 and ARM64 runners (RISC-V under QEMU), Windows on `windows-2025` and `windows-11-arm`, and macOS on `macos-15-intel` and `macos-15`.

## Scenarios

| Scenario | What it checks |
|---|---|
| config | Each out-of-range config field gives `LIBP2P_INVALID_CONFIG`, the QUIC fields included; a short state gives `LIBP2P_BUFFER_TOO_SMALL`; a secp256k1 key of 0 or above the order gives `LIBP2P_INVALID_KEY`. |
| yamux, mplex, fallback, mplex_first | Node 0 dials node 1 with each muxer choice: both yamux; both mplex; node 0 offers both and node 1 only mplex; node 0 offers only mplex and node 1 both. Ed25519 and secp256k1 keys in turn. A stream opens with its second protocol, carries a message each way, and closes both ways with no STREAM_RESET; then the peers disconnect. |
| no_muxer | No shared muxer: the dial fails in the upgrade, and no node reports a peer. |
| peer_id | A dial that reaches another peer than it names fails with PEER_ID, and no node reports a peer. |
| streams_yamux, streams_mplex | Refused protocols, a reset, and 1 MiB from one node to the other through the flow control of each muxer. |
| timeout | An unanswered dial fails with CONNECT; a peer that never answers fails with HANDSHAKE. |
| garbage | Garbage bytes at a listener and at a dialer close the connection. |
| errors | Malformed events and short buffers give their status, accept nothing, and leave the state unchanged. Over QUIC: a QUIC DIAL with QUIC off, an unknown transport, a bad port, a DATAGRAM with QUIC off, a count past its event, a bad address family, and a count above 65535. |
| simultaneous | Both nodes dial each other at once: one connection stays, and each side sees one peer. |
| limits | A node with room for 2 connections refuses the third. |
| gossip | Six nodes in a graph: every message reaches every node once; a rejecting node does not forward. |
| gossip_lazy | The same checks with D 1, D_low 1, D_high 2 and D_lazy 4. |
| secondary | A peer that dials again gets a secondary connection; when its first connection ends, the second takes over with no PEER_DISCONNECTED, and gossip and new streams work through it. |
| scoring | Rejected messages and a low application score put a peer below the thresholds: its messages are not heard, and messages no longer go to it. |
| idontwant | Four nodes, each connected to the others, publish messages of 2048 bytes three times: with gossipsub v1.2, without IDONTWANT, and with one node of v1.1 only. Every node gets each message once, and there are fewer duplicates with IDONTWANT than without. |
| quic | The checks of yamux over QUIC: Ed25519 keys on both nodes, then secp256k1 and Ed25519. |
| quic_streams | The checks of streams_yamux over QUIC: 1 MiB goes through the window of `quic_window` bytes in flight, which STREAM_ACKED opens again. |
| quic_loss | quic_streams with every 7th datagram lost: the connection, the streams and 1 MiB still go through. |
| quic_dial_fails | A QUIC dial that reaches another peer than it names fails with PEER_ID; a node that never answers fails with CONNECT. |
| quic_gossip | The checks of gossip with every edge over QUIC. |
| quic_mixed | The checks of gossip with every other edge over QUIC and the rest over TCP. |
| partial | Gossipsub v1.3 and the Partial Messages extension. One node dials three: two want partial messages of a topic, one only sends them, one speaks v1.2 only. PARTIAL_PEERS lists the partial peers with their flags and not the v1.2 node; PARTIAL_SEND gives data and metadata to a peer that wants partial messages, the metadata only to a peer that only sends them, and nothing to the v1.2 node; each PARTIAL carries the flags of its sender; full messages of the topic go to every peer but the one that wants partial messages, and a large one gets no IDONTWANT to the partial peers; on a topic the node does not subscribe to, PARTIAL_PEERS lists the fanout peer that wants partial messages; new partial flags and an unsubscription change the list; PARTIAL_SUBSCRIBE with flags is an invalid event on a node without the extension. Then a node with D 1 and two partial peers lists the one outside its mesh in PARTIAL_GOSSIP. |

## Transcript digests

- After its checks, each scenario prints a digest: FNV-1a 64 over every action of every node, in order.
- The `want` digests in `runner.c` are recorded on ARM64. Every ISA must give them: the cores follow one instruction sequence, so a difference is a port error.

## ABI and stack check

- The runner calls every L2 function through `abi_call(ctx)`.
- Before the call, `abi_call` sets each register that the callee must keep to a known value, and paints `paint` bytes of stack below the call with `0x5A`.
- After the call, it writes the status, a mask of the kept state that changed, and the bytes of stack the call used: the lowest painted word that changed.
- The runner fails when a call changes kept state, or uses more than 16384 bytes of stack. It prints the most stack of each function as a STACK line.
- With no scenario names, it ends with a "FUNCTION <name> PASS" or FAIL line for each L2 function, for the tick tables.

| Offset | Field | Kind | Meaning |
|---|---|---|---|
| 0 | `fn` | input | Address of the function to call |
| 8 | `arg` | input | Arguments 0 to 4, 8 bytes each |
| 48 | `paint` | input | Bytes of stack to paint below the call |
| 56 | `status` | output | The return value |
| 64 | `fault` | output | Mask of the kept state that changed |
| 72 | `stack` | output | Bytes of stack the call used |
| 80 | `scratch` | state | 32 bytes for `abi_call`: the stack pointer, and the control state of each ISA before the call |
| 112 | `arg5` | input | Argument 5 |

| Bit | x86-64 | ARM64 | RISC-V |
|---|---|---|---|
| 0 to 4 | `rbx`, `rbp`, `r12`, `r13`, `r14` | `x19` to `x23` | `s0` to `s4` |
| 5 | `r15`, which holds `ctx` | `x24` | `s5` |
| 6 to 8 | | `x25` to `x27` | `s6` to `s8` |
| 9 | | `x28`, which holds `ctx` | `s9` |
| 10 | | `x29` | `s10` |
| 11 | | `d8` | `s11`, which holds `ctx` |
| 12 to 18 | | `d9` to `d15` | `fs0` to `fs6` |
| 19 to 23 | | | `fs7` to `fs11` |
| 24 | | | `gp` |
| 25 | | | `tp` |
| 60 | x87 control word | | |
| 61 | MXCSR control bits | FPCR | |
| 62 | Direction flag set | | |
| 63 | `rsp` | `sp` | `sp` |

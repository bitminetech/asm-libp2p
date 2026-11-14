# asm-libp2p

libp2p over TCP for an Ethereum consensus client, in assembly.

Noise, multistream-select, yamux and mplex, streams, identify, and gossipsub v1.1 with peer scores and the IDONTWANT of v1.2. Request/response protocols run in the application, on the stream API.

Standard: [asm-standard@2a19d3f](https://github.com/bitminetech/asm-standard/blob/2a19d3f7fa737af1c01720b6e891703e53a682aa/ARCHITECTURE.md)

## Reference

| File | Covers |
|---|---|
| [docs/reference/node.md](docs/reference/node.md) | Node: config, state, step, events and actions, heap, random bytes |
| [docs/reference/peer-ids.md](docs/reference/peer-ids.md) | Peer IDs and encodings: varints, protobuf, keys, DER |
| [docs/reference/noise.md](docs/reference/noise.md) | Noise handshake and transport messages |
| [docs/reference/connections.md](docs/reference/connections.md) | Connections: multistream-select, upgrade, peers |
| [docs/reference/streams.md](docs/reference/streams.md) | Streams |
| [docs/reference/identify.md](docs/reference/identify.md) | Identify |
| [docs/reference/muxers.md](docs/reference/muxers.md) | yamux, mplex, and SEND actions |
| [docs/reference/gossipsub.md](docs/reference/gossipsub.md) | gossipsub |
| [docs/reference/scoring.md](docs/reference/scoring.md) | Peer scoring of gossipsub v1.1 |
| [docs/reference/shell.md](docs/reference/shell.md) | Shell: TCP sockets, clock and random bytes |
| [include/libp2p.inc](include/libp2p.inc) | Constants and layouts |
| [include/state.inc](include/state.inc) | Layouts inside the state |

## Targets

| OS | ISAs |
|---|---|
| Linux | x86-64, ARM64, RISC-V |
| Windows | x86-64, ARM64 |
| macOS | x86-64, ARM64 |

## Dependencies

| Repo | Commit | Functions used |
|---|---|---|
| [asm-crypto](https://github.com/bitminetech/asm-crypto) | [`0791b66`](https://github.com/bitminetech/asm-crypto/tree/0791b669f95be34b049265829d7d85864a1d769f) | `crypto_sha256`, `crypto_hkdf_extract`, `crypto_hkdf_expand`, `crypto_chacha20_aead_encrypt`, `crypto_chacha20_aead_decrypt`, `crypto_x25519`, `crypto_secp256k1_public_key`, `crypto_secp256k1_sign`, `crypto_secp256k1_verify`, `crypto_ed25519_public_key`, `crypto_ed25519_sign`, `crypto_ed25519_verify` |
| libSystem (macOS shell) | macOS 11.0 SDK | `socket`, `setsockopt`, `getsockopt`, `fcntl`, `bind`, `listen`, `getsockname`, `connect`, `accept`, `send`, `recv`, `poll`, `close`, `__error`, `clock_gettime_nsec_np`, `getentropy` |
| ws2_32, kernel32 and bcrypt (Windows shell) | Windows 10 | `WSAStartup`, `WSACleanup`, `WSAGetLastError`, `WSAPoll`, `socket`, `setsockopt`, `getsockopt`, `ioctlsocket`, `bind`, `listen`, `getsockname`, `connect`, `accept`, `send`, `recv`, `closesocket`, `Sleep`, `GetTickCount64`, `BCryptGenRandom` |

## Build tools

| Used for | Tool |
|---|---|
| Library | LLVM 23.1.5, official release (`clang`, `llvm-ar`, `lld`) |
| Windows tests | [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) |
| macOS tests | The host Xcode clang, because they need the macOS SDK |
| Build image | [platform/linux/Dockerfile](platform/linux/Dockerfile) on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |

## Tests

| Item | Location |
|---|---|
| Export and frame check | [platform/check.py](platform/check.py) |
| Scenario runner | [tests/runner/](tests/runner/) |
| Shell loop test | [tests/shell/](tests/shell/) |
| transport-interop of libp2p/test-plans | [tests/interop/](tests/interop/) |
| gossipsub-interop of libp2p/test-plans | [tests/gossipsub/](tests/gossipsub/) |
| Live test on Ethereum mainnet | [tests/mainnet/](tests/mainnet/) |

## Target profile

| ISA | Instructions |
|---|---|
| x86-64 | x86-64-v1 |
| ARM64 | Armv8.0-A |
| RISC-V | RV64GC |

| Item | Value |
|---|---|
| macOS objects | Marked for macOS 11.0 or later |
| Linux kernel | 3.17 or later, for `getrandom` |
| Floating point | IEEE 754 binary64, round to nearest even, no flush to zero: the default of each OS |

## Environment boundaries

| OS | Call | Requirements |
|---|---|---|
| Linux | System calls `socket`, `setsockopt`, `getsockopt`, `bind`, `listen`, `getsockname`, `connect`, `accept4`, `sendto`, `recvfrom`, `ppoll`, `close`, `clock_gettime`, `getrandom` | Numbers and layouts from the kernel uapi headers of each ISA, as in Debian trixie |
| macOS | libSystem functions in the Dependencies table | macOS 11.0 or later |
| Windows | Winsock 2.2, `Sleep`, `GetTickCount64`, `BCryptGenRandom` | Windows 10 or later |

## Stack

| Item | Value |
|---|---|
| Stack per call | At most 16384 bytes, callees included |
| Shell calls | The OS calls of the shell add their own native stack |

## Integration

| Item | Value |
|---|---|
| Startup | `libp2p_shell_clock` gives the time and entropy for `libp2p_init`; `libp2p_shell_init` builds the shell context; `libp2p_shell_listen` opens listening sockets |
| Event loop | The application owns it: it calls `libp2p_step` with a fresh tick and the events since the last step, and passes the events it did not accept again |
| Actions | After a step returns 0, `libp2p_shell_perform` does its shell actions and adds their results to the events; the application handles the other actions |
| Wakeup | The application waits with `libp2p_shell_wait` until the WAKEUP time or socket activity |
| Buffers | Scratch of `LIBP2P_SCRATCH_SIZE` bytes; action room of `LIBP2P_ACTIONS_MIN` bytes after the 24-byte header |
| Message IDs | The application computes them as the consensus specs define, after MESSAGE, and judges each new message with VALIDATION |
| Request/response | The application runs it on OPEN_STREAM, STREAM_WRITE, STREAM_CLOSE and the STREAM actions |
| Shutdown | `libp2p_shell_close` |
| Concurrency | One thread at a time for a state and its shell context |

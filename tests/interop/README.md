# transport-interop

The asm-libp2p node runs the transport-interop test of [libp2p/test-plans](https://github.com/libp2p/test-plans/tree/12e2ff491db21115b8e775e0eb7ee51056d203fb/transport-interop), from the fork [bitminetech/test-plans](https://github.com/bitminetech/test-plans/tree/353d23ee364d0d7336e4a8bb9a59aad03f24a429/transport-interop) with fixes to c-v0.0.1 and nim-v1.14, against every implementation there that offers TCP with Noise or quic-v1. Each pair runs both ways: asm-libp2p dials the other implementation, and the other implementation dials asm-libp2p, once for each muxer the other offers over TCP, and once over quic-v1.

```bash
tests/runner/docker.sh
```

```bash
tests/interop/build-images.sh arm64 /path/to/work
```

```bash
tests/interop/run.sh arm64
```

| File | What it does |
|---|---|
| `node.c` | The asm-libp2p node of the test. Test code in C: it does Redis and the ping protocol; the library does the rest. |
| `Dockerfile` | The image of the node, `asm-libp2p-interop-<ISA>`, from `build/linux-<ISA>/node`. For RISC-V, the node runs under QEMU user mode. |
| `build-images.sh` | `build-images.sh ISA WORK_DIR [IMAGE ...]`: builds the image of the node, checks out test-plans in WORK_DIR, and builds the images of the other implementations. |
| `run.sh` | `run.sh ISA [IMAGE ...]`: runs each pair with Docker Compose and a Redis container, and prints PASS with the two times of the dialer, or FAIL. A pair passes when the dialer prints its times. `RUNS=n` runs each pair n times; `BASELINE=1` also runs each implementation, and asm-libp2p, against itself; `TRANSPORT=tcp` or `TRANSPORT=quic-v1` runs only the pairs of that transport. |

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs every pair on each Linux ISA:

- One job per transport, ISA and implementation: `interop-tcp` has 48 jobs (16 implementations), `interop-quic` 36 (12 implementations).
- x86-64 runs on `ubuntu-24.04`; ARM64 and RISC-V run on `ubuntu-24.04-arm`, the RISC-V node under QEMU user mode.
- The `interop-results` job counts the pairs, and fails unless 56 TCP pairs and 24 quic-v1 pairs pass on each ISA.

## The node

- Reads the settings of the test from its environment: `transport` (tcp or quic-v1), `muxer` and `security` (noise) for tcp, `is_dialer`, `ip`, `redis_addr`, `test_timeout_seconds`.
- quic-v1: has QUIC on, and binds one UDP socket; the listener takes inbound QUIC connections.
- Listener: listens, and publishes `/ip4/<ip>/tcp/<port>/p2p/<id>` or `/ip4/<ip>/udp/<port>/quic-v1/p2p/<id>` to Redis.
- Dialer: takes that address from Redis, connects over its transport, pings with `/ipfs/ping/1.0.0` (32 random bytes, echoed), and prints the result as JSON.

## Pins and fixes

| Item | Value |
|---|---|
| test-plans | The fork `bitminetech/test-plans`, branch `asm-libp2p`, commit `353d23ee364d0d7336e4a8bb9a59aad03f24a429`: `libp2p/test-plans` `12e2ff491db21115b8e775e0eb7ee51056d203fb`, the go node fix of [gossipsub-interop](../gossipsub/), and the c-v0.0.1 and nim-v1.14 fixes below |
| c-v0.0.1, the patch of the fork | c-libp2p `23a6172` emits STREAM_CLOSED when it closes an inbound stream whose protocol it refused, which never emitted STREAM_OPENED. Its listener counts open streams, so when the refused gossipsub stream of the asm-libp2p node closed after the ping stream opened, the listener stopped in the middle of the ping and freed streams its other threads still used. The fork's Makefile applies `stream-close-events.patch`: close events only for a stream with a negotiated protocol |
| nim-v1.14, the fix of the fork | nimble 0.18.2 in `nimlang/nim:2.2.4-ubuntu-regular` resolves the pinned commits of nim-libp2p `0309685` with its SAT solver and may fetch and build Nim 2.4.2; some runs fail with "Unsatisfiable dependencies" or while building that Nim. The fork's Dockerfile runs every nimble call, and the one `install_pinned` runs, with `--solver:legacy --useSystemNim`: the same packages, built with Nim 2.2.4 |
| Redis | `redis:7-alpine` |
| c-v0.0.1 | Its Makefile moves `WjCryptLib-master`; GitHub now names the archive folder after its commit, so `build-images.sh` matches `WjCryptLib-*` |
| rust-v0.56 | rust-libp2p `70082df` needs a newer rustc than the pinned cargo-chef 0.1.68 image: `build-images.sh` builds with a cargo-chef image pinned by digest, on `debian:bookworm` |
| js images | The js Makefiles tag `node-<image_name>` |
| eth-p2p-z-v0.0.1 | Its Dockerfile fetches an x86-64 zig and pins `-Dcpu=x86_64`; that zig fails under emulation on an ARM64 host. `build-images.sh` uses the zig of the host ISA with `-Dcpu=baseline` |

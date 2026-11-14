# transport-interop

The asm-libp2p node runs the transport-interop test of [libp2p/test-plans](https://github.com/libp2p/test-plans/tree/12e2ff491db21115b8e775e0eb7ee51056d203fb/transport-interop) against every implementation there that offers TCP with Noise. Each pair runs both ways: asm-libp2p dials the other implementation, and the other implementation dials asm-libp2p, once for each muxer the other offers.

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
| `run.sh` | `run.sh ISA [IMAGE ...]`: runs each pair with Docker Compose and a Redis container, and prints PASS with the two times of the dialer, or FAIL. A pair passes when the dialer prints its times. `RUNS=n` runs each pair n times; `BASELINE=1` also runs each implementation, and asm-libp2p, against itself. |

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs the Linux x86-64 node against go-v0.48 and rust-v0.56, both ways.

## The node

- Reads the settings of the test from its environment: `transport` (tcp), `muxer`, `security` (noise), `is_dialer`, `ip`, `redis_addr`, `test_timeout_seconds`.
- Listener: listens, and publishes `/ip4/<ip>/tcp/<port>/p2p/<id>` to Redis.
- Dialer: takes that address from Redis, connects, pings with `/ipfs/ping/1.0.0` (32 random bytes, echoed), and prints the result as JSON.

## Pins and fixes

| Item | Value |
|---|---|
| test-plans | `12e2ff491db21115b8e775e0eb7ee51056d203fb` |
| Redis | `redis:7-alpine` |
| c-v0.0.1 | Its Makefile moves `WjCryptLib-master`; GitHub now names the archive folder after its commit, so `build-images.sh` matches `WjCryptLib-*` |
| rust-v0.56 | rust-libp2p `70082df` needs a newer rustc than the pinned cargo-chef 0.1.68 image: `build-images.sh` builds with a cargo-chef image pinned by digest, on `debian:bookworm` |
| js images | The js Makefiles tag `node-<image_name>` |

## Results

Run on 2026-11-14 in Docker on a Mac with Apple silicon. The other implementations run as ARM64 images. The asm-libp2p node runs natively for ARM64, under the x86-64 emulation of Docker for x86-64, and under QEMU user mode for RISC-V.

| Implementation | Muxers | Pairs |
|---|---|---|
| go-v0.46, go-v0.47, go-v0.48 | yamux | 6 |
| dotnet-v1.0 | yamux | 2 |
| node-js-v1.x, node-js-v2.x, node-js-v3.x | yamux, mplex | 12 |
| nim-v1.14, nim-v2.4 | yamux, mplex | 8 |
| python-v0.x | yamux, mplex | 4 |
| jvm-libp2p-v1.3 | yamux, mplex | 4 |
| c-v0.0.1 | yamux, mplex | 4 |
| rust-v0.53, rust-v0.54, rust-v0.55, rust-v0.56 | yamux, mplex | 16 |

| Node ISA | Passed |
|---|---|
| ARM64 | 56 of 56 |
| x86-64 | 56 of 56 |
| RISC-V | 56 of 56 |

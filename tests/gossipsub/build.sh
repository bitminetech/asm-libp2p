#!/bin/sh
# Build the nodes of gossipsub-interop on Linux x86-64: the asm-libp2p node,
# and the go, rust, jvm and nim nodes of the suite.
# Usage: tests/gossipsub/build.sh WORK_DIR [IMPLEMENTATION ...]    (go, rust, jvm, nim; none: all 4)
# Needs build/linux-x86_64 (tests/runner/docker.sh or the CI build job), clang,
# and the toolchain of each implementation: Go, Rust, a JDK, Nim.
#
# WORK_DIR holds the test-plans checkout: the fork bitminetech/test-plans,
# which is libp2p/test-plans 12e2ff4 with one fix to the go node of the
# suite, so that its partial message manager cannot deadlock the pubsub
# event loop. The asm-libp2p node becomes the
# implementation "asm" of experiment.py. Shadow loads its shim with
# LD_PRELOAD, so it cannot run a static binary: the node links libc
# dynamically. The library makes its system calls itself; Shadow traps those
# with seccomp.
set -eu
work=$1
shift
root=$(cd "$(dirname "$0")/../.." && pwd)
plans=32875fd08f8264f03bf1a09e47d6ccbf90b19fa2    # bitminetech/test-plans, branch asm-libp2p
lib=$root/build/linux-x86_64

if [ ! -d "$work/test-plans" ]; then
    git init -q "$work/test-plans"
    git -C "$work/test-plans" fetch -q --depth 1 https://github.com/bitminetech/test-plans "$plans"
    git -C "$work/test-plans" checkout -q FETCH_HEAD
fi
[ "$(git -C "$work/test-plans" rev-parse HEAD)" = "$plans" ] ||
    { echo "$work/test-plans is not at $plans" >&2; exit 1; }
gs=$work/test-plans/gossipsub-interop

mkdir -p "$gs/asm-libp2p"
clang -std=c11 -O2 -Wall -Wextra -Werror "$root/tests/gossipsub/node.c" "$lib/libasm-libp2p.a" \
    "$lib"/crypto-*.o "$lib/quic.o" -lm -o "$gs/asm-libp2p/gossipsub-bin"
echo "built asm"
grep -q '"asm":' "$gs/experiment.py" ||
    sed -i 's|^IMPLEMENTATIONS: Dict\[str, str\] = {$|&\n    "asm": "asm-libp2p/gossipsub-bin",|' "$gs/experiment.py"
grep -q '"asm":' "$gs/experiment.py" || { echo "experiment.py: IMPLEMENTATIONS not found" >&2; exit 1; }
# run.py runs make binaries, which builds all 4 implementations, before each run: this script builds them once.
sed -i 's|^    subprocess.run(\["make", "binaries"\], check=True)$|    pass  # built by tests/gossipsub/build.sh|' "$gs/run.py"

for impl in ${*:-go rust jvm nim}; do
    case $impl in
      # The Makefile builds with -linkshared; a cgo build links libc dynamically, as Shadow needs.
      go)   (cd "$gs/go-libp2p" && CGO_ENABLED=1 go build -o gossipsub-bin) ;;
      rust) (cd "$gs/rust-libp2p" && cargo build --locked) ;;
      jvm)  (cd "$gs/jvm-libp2p" && ./gradlew --no-daemon -q installDist) ;;
      nim)  make -C "$gs" nim-libp2p/gossipsub-bin ;;
      *) echo "unknown implementation: $impl" >&2; exit 2 ;;
    esac
    echo "built $impl"
done
for bin in asm-libp2p/gossipsub-bin go-libp2p/gossipsub-bin; do
    [ -f "$gs/$bin" ] || continue
    ldd "$gs/$bin" >/dev/null || { echo "$bin is not dynamically linked" >&2; exit 1; }
done

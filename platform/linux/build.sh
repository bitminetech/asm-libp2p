#!/bin/sh
# Build the asm-libp2p library, its dependency objects (asm-crypto, asm-quic), the test runner, the
# shell loop test, the interop node and the mainnet node for one Linux ISA.
# Usage: platform/linux/build.sh ISA OUT_DIR    (ISA: x86_64, arm64 or riscv64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto
quic=$root/build/deps/asm-quic

case "$isa" in
  x86_64)  target=x86_64-linux-gnu;  march="-march=x86-64" ;;
  arm64)   target=aarch64-linux-gnu; march="-march=armv8-a" ;;
  riscv64) target=riscv64-linux-gnu; march="-march=rv64gc -mabi=lp64d" ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target $march -I"$root/include" -I"$crypto/include" -I"$quic/include" -I"$root/platform/linux" -I"$root/asm/core/$isa" \
    -c "$root/asm/core/$isa/libp2p.s" -o "$out/libp2p.o"
clang --target=$target $march -I"$root/include" -I"$root/platform/linux" \
    -c "$root/asm/shell/linux/$isa/shell.s" -o "$out/shell.o"
rm -f "$out/libasm-libp2p.a"
llvm-ar rcs "$out/libasm-libp2p.a" "$out/libp2p.o" "$out/shell.o"

# Dependency objects: the asm-crypto files the library and asm-quic call.
deps=""
for name in sha256 hmac chacha20 aes x25519 p256 secp256k1 sha512 ed25519; do
    clang --target=$target $march -I"$crypto/include" -I"$crypto/platform/linux" \
        -c "$crypto/asm/core/$isa/$name.s" -o "$out/crypto-$name.o"
    deps="$deps $out/crypto-$name.o"
done
# The asm-quic core: its shell is not linked; the UDP socket is in this shell.
clang --target=$target $march -I"$quic/include" -I"$crypto/include" -I"$quic/platform/linux" -I"$quic/asm/core/$isa" \
    -c "$quic/asm/core/$isa/quic.s" -o "$out/quic.o"
deps="$deps $out/quic.o"

# Tests (C), linked statically so QEMU user mode needs no target libraries.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/runner/runner.c" -I"$root/platform/linux" "$root/tests/runner/abi_$isa.s" \
    "$out/libasm-libp2p.a" $deps -o "$out/runner"
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/shell/loop.c" "$out/libasm-libp2p.a" $deps -o "$out/loop"
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/interop/node.c" "$out/libasm-libp2p.a" $deps -o "$out/node"
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/mainnet/node.c" "$out/libasm-libp2p.a" $deps -o "$out/mainnet"

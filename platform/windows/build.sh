#!/bin/sh
# Build the asm-libp2p library, its dependency objects, the test runner and
# the shell loop test for one Windows ISA.
# Usage: platform/windows/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
# The library uses the pinned LLVM; the tests use llvm-mingw for the Windows C runtime.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto
quic=$root/build/deps/asm-quic

case "$isa" in
  x86_64) target=x86_64-w64-windows-gnu;  march="-march=x86-64"; mingw=x86_64-w64-mingw32 ;;
  arm64)  target=aarch64-w64-windows-gnu; march="-march=armv8-a"; mingw=aarch64-w64-mingw32 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target $march -I"$root/include" -I"$crypto/include" -I"$quic/include" -I"$root/platform/windows" -I"$root/asm/core/$isa" \
    -c "$root/asm/core/$isa/libp2p.s" -o "$out/libp2p.o"
clang --target=$target $march -I"$root/include" -I"$root/platform/windows" \
    -c "$root/asm/shell/windows/$isa/shell.s" -o "$out/shell.o"
rm -f "$out/libasm-libp2p.a"
llvm-ar rcs "$out/libasm-libp2p.a" "$out/libp2p.o" "$out/shell.o"
deps=""
for name in sha256 hmac chacha20 aes x25519 p256 secp256k1 sha512 ed25519; do
    clang --target=$target $march -I"$crypto/include" -I"$crypto/platform/windows" \
        -c "$crypto/asm/core/$isa/$name.s" -o "$out/crypto-$name.o"
    deps="$deps $out/crypto-$name.o"
done
clang --target=$target $march -I"$quic/include" -I"$crypto/include" -I"$quic/platform/windows" -I"$quic/asm/core/$isa" \
    -c "$quic/asm/core/$isa/quic.s" -o "$out/quic.o"
deps="$deps $out/quic.o"

/opt/llvm-mingw/bin/$mingw-clang $march -std=c11 -O2 -Wall -Wextra -Werror -static \
    "$root/tests/runner/runner.c" -I"$root/platform/windows" "$root/tests/runner/abi_$isa.s" \
    "$out/libasm-libp2p.a" $deps -o "$out/runner.exe"
/opt/llvm-mingw/bin/$mingw-clang $march -std=c11 -O2 -Wall -Wextra -Werror -static \
    "$root/tests/shell/loop.c" "$out/libasm-libp2p.a" $deps -lws2_32 -lbcrypt -o "$out/loop.exe"

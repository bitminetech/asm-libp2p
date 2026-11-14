#!/bin/sh
# Build the asm-libp2p library and its dependency objects for one macOS ISA.
# Usage: platform/macos/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh, so
# the library uses the pinned LLVM. link-runner.sh links the tests on a Mac.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto

case "$isa" in
  x86_64) target=x86_64-apple-macos11 ;;
  arm64)  target=arm64-apple-macos11 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target -I"$root/include" -I"$crypto/include" -I"$root/platform/macos" -I"$root/asm/core/$isa" \
    -c "$root/asm/core/$isa/libp2p.s" -o "$out/libp2p.o"
clang --target=$target -I"$root/include" -I"$root/platform/macos" \
    -c "$root/asm/shell/macos/$isa/shell.s" -o "$out/shell.o"
rm -f "$out/libasm-libp2p.a"
llvm-ar --format=darwin rcs "$out/libasm-libp2p.a" "$out/libp2p.o" "$out/shell.o"
for name in sha256 hmac chacha20 x25519 secp256k1 sha512 ed25519; do
    clang --target=$target -I"$crypto/include" -I"$crypto/platform/macos" \
        -c "$crypto/asm/core/$isa/$name.s" -o "$out/crypto-$name.o"
done

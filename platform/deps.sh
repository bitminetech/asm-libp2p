#!/bin/sh
# Pin the dependencies, fetch them into build/deps/, and name the functions
# this repo calls in them (ARCHITECTURE.md section 5).
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
# asm-quic calls asm-crypto too, and both go into one binary: the asm-crypto
# pin of asm-quic must be the pin here.
#
# The functions this repo calls in each dependency. platform/check.py rejects
# a call to any other function.
# uses asm-crypto: crypto_sha256 crypto_hkdf_extract crypto_hkdf_expand crypto_chacha20_aead_encrypt crypto_chacha20_aead_decrypt crypto_x25519 crypto_secp256k1_public_key crypto_secp256k1_sign crypto_secp256k1_verify crypto_ed25519_public_key crypto_ed25519_sign crypto_ed25519_verify
# uses asm-quic: quic_state_size quic_init quic_step
# uses libSystem (macOS shell, macOS 11.0 SDK): socket setsockopt getsockopt fcntl bind listen getsockname connect accept send recv sendto recvfrom poll close __error clock_gettime_nsec_np getentropy
# uses ws2_32, kernel32 and bcrypt (Windows shell, Windows 10): WSAStartup WSACleanup WSAGetLastError WSAPoll socket setsockopt getsockopt ioctlsocket bind listen getsockname connect accept send recv sendto recvfrom WSAIoctl closesocket Sleep QueryPerformanceCounter QueryPerformanceFrequency GetSystemTimeAsFileTime BCryptGenRandom

set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
crypto=a364b8c3c06b55607834f93cda7b7e315323b3b8
quic=8ce353c1df72f835a234118c7f8f022118d5dac0
fetch() {
    dir=$root/build/deps/$1
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
        rm -rf "$dir"
        git init -q "$dir"
        git -C "$dir" fetch -q --depth 1 "https://github.com/bitminetech/$1" "$2"
        git -C "$dir" checkout -q FETCH_HEAD
    fi
}
fetch asm-crypto $crypto
fetch asm-quic $quic
theirs=$(sed -n 's/^fetch asm-crypto \([0-9a-f]*\).*/\1/p' "$root/build/deps/asm-quic/platform/deps.sh")
if [ "$theirs" != "$crypto" ]; then
    echo "deps.sh: asm-quic pins asm-crypto $theirs, asm-libp2p pins $crypto" >&2
    exit 1
fi

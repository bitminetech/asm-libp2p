#!/bin/sh
# Build the Docker images of transport-interop: the asm-libp2p node for one
# Linux ISA, and the TCP and quic-v1 implementations of libp2p/test-plans.
# Usage: tests/interop/build-images.sh ISA WORK_DIR [IMPLEMENTATION ...]
#   ISA: x86_64, arm64 or riscv64. Implementations by image name; none: all 17.
#
# The asm-libp2p image is asm-libp2p-interop-<ISA>, from build/linux-<ISA>/node
# (tests/runner/docker.sh builds it). The implementation images keep their
# test-plans names (go-v0.48, rust-v0.56, ...). WORK_DIR holds the test-plans
# checkout: the fork bitminetech/test-plans, which is libp2p/test-plans 12e2ff4
# with a fix to the go node of gossipsub-interop and a patch to c-v0.0.1, so
# that c-libp2p emits no close events for a stream it refused. Images that
# exist already are kept.
set -eu
isa=$1
work=$2
shift 2
root=$(cd "$(dirname "$0")/../.." && pwd)
plans=25aca13c2b5c9765ed572f4ef8ea4c54a3c33a55    # bitminetech/test-plans, branch asm-libp2p
# The cargo-chef image that builds rust-libp2p 70082df: the pinned 0.1.68 one has rustc 1.84, too old for prost 0.14.6.
chef=lukemathwalker/cargo-chef@sha256:9573268a2a874efc1c755a0094a50c25988b2c6a0b7a520ddb7fd08d868d1c43

case "$isa" in
  x86_64)  platform=linux/amd64; qemu="" ;;
  arm64)   platform=linux/arm64; qemu="" ;;
  riscv64) platform="";          qemu=qemu-riscv64 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac
ctx=$(mktemp -d)
cp "$root/build/linux-$isa/node" "$root/tests/interop/Dockerfile" "$ctx/"
docker build -q ${platform:+--platform $platform} --build-arg QEMU=$qemu -t asm-libp2p-interop-$isa "$ctx" >/dev/null
rm -rf "$ctx"
echo "built asm-libp2p-interop-$isa"

if [ ! -d "$work/test-plans" ]; then
    git init -q "$work/test-plans"
    git -C "$work/test-plans" fetch -q --depth 1 https://github.com/bitminetech/test-plans "$plans"
    git -C "$work/test-plans" checkout -q FETCH_HEAD
fi
impl=$work/test-plans/transport-interop/impl
# The c image: GitHub now names the WjCryptLib archive folder after its commit.
sed -i.orig 's/mv WjCryptLib-master\/\* external\/wjcryptlib\/ && rm -rf wjcryptlib.zip WjCryptLib-master/mv WjCryptLib-*\/* external\/wjcryptlib\/ \&\& rm -rf wjcryptlib.zip WjCryptLib-*/' \
    "$impl/c/v0.0.1/Makefile"
# The eth-p2p-z image: its Dockerfile fetches an x86-64 zig, and test-plans pins -Dcpu=x86_64. On
# an ARM64 host that zig runs under emulation and fails ("unknown target CPU 'athlon-xp'"). The
# zig of the host ISA with the baseline CPU builds on both, and keeps the binary portable.
zarch=$(uname -m)
[ "$zarch" = arm64 ] && zarch=aarch64
for d in go/v0.46 go/v0.47 go/v0.48 dotnet/v1.0 js/v1.x js/v2.x js/v3.x nim/v1.14 nim/v2.4 python/v0.x jvm/v1.3 \
         c/v0.0.1 rust/v0.53 rust/v0.54 rust/v0.55 rust/v0.56 eth-p2p-z/v0.0.1; do
    name=$(sed -n 's/^image_name := //p' "$impl/$d/Makefile")
    [ "${d%%/*}" = js ] && name=node-$name    # the js Makefiles tag node-<image_name>
    if [ $# -gt 0 ]; then
        wanted=0
        for want in "$@"; do [ "$want" = "$name" ] && wanted=1; done
        [ $wanted = 1 ] || continue
    fi
    if docker image inspect "$name" >/dev/null 2>&1; then echo "have $name"; continue; fi
    if [ "$d" = rust/v0.56 ]; then
        (cd "$impl/$d" && make rust-libp2p-70082df7e6181722630eabc5de5373733aac9a21 >/dev/null)
        src=$impl/$d/rust-libp2p-70082df7e6181722630eabc5de5373733aac9a21
        sed -i.orig -e "s|^FROM lukemathwalker/cargo-chef:0.1.68-rust-bullseye as chef|FROM $chef as chef|" \
            -e 's|^FROM debian:bullseye$|FROM debian:bookworm|' "$src/interop-tests/Dockerfile.native"
        docker build -q -t "$name" -f "$src/interop-tests/Dockerfile.native" "$src" >/dev/null
    elif [ "$d" = eth-p2p-z/v0.0.1 ]; then
        sha=$(sed -n 's/^commitSha := //p' "$impl/$d/Makefile")
        src=$impl/$d/eth-p2p-z-$sha
        if [ ! -d "$src" ]; then
            curl -fsSL -o "$impl/$d/eth-p2p-z-$sha.zip" "https://github.com/zen-eth/eth-p2p-z/archive/$sha.zip"
            (cd "$impl/$d" && unzip -q -o "eth-p2p-z-$sha.zip")
        fi
        sed -i.orig -e 's/ -Dcpu=[a-z0-9_]*//' -e 's/-Dlibxev-backend=epoll/-Dlibxev-backend=epoll -Dcpu=baseline/' \
            -e "s/zig-x86_64-linux/zig-$zarch-linux/g" "$src/interop/transport/Dockerfile"
        docker build -q -t "$name" -f "$src/interop/transport/Dockerfile" --build-arg ZIG_LOG_LEVEL=warn "$src" >/dev/null
    else
        (cd "$impl/$d" && make image.json > build.log 2>&1) || {
            echo "FAIL $name: $impl/$d/build.log ends:"; tail -n 40 "$impl/$d/build.log"; exit 1; }
    fi
    echo "built $name"
done

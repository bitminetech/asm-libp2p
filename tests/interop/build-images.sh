#!/bin/sh
# Build the Docker images of transport-interop: the asm-libp2p node for one
# Linux ISA, and the TCP implementations of libp2p/test-plans.
# Usage: tests/interop/build-images.sh ISA WORK_DIR [IMPLEMENTATION ...]
#   ISA: x86_64, arm64 or riscv64. Implementations by image name; none: all 16.
#
# The asm-libp2p image is asm-libp2p-interop-<ISA>, from build/linux-<ISA>/node
# (tests/runner/docker.sh builds it). The implementation images keep their
# test-plans names (go-v0.48, rust-v0.56, ...). WORK_DIR holds the test-plans
# checkout; images that exist already are kept.
set -eu
isa=$1
work=$2
shift 2
root=$(cd "$(dirname "$0")/../.." && pwd)
plans=12e2ff491db21115b8e775e0eb7ee51056d203fb    # libp2p/test-plans
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
    git -C "$work/test-plans" fetch -q --depth 1 https://github.com/libp2p/test-plans "$plans"
    git -C "$work/test-plans" checkout -q FETCH_HEAD
fi
impl=$work/test-plans/transport-interop/impl
# The c image: GitHub now names the WjCryptLib archive folder after its commit.
sed -i.orig 's/mv WjCryptLib-master\/\* external\/wjcryptlib\/ && rm -rf wjcryptlib.zip WjCryptLib-master/mv WjCryptLib-*\/* external\/wjcryptlib\/ \&\& rm -rf wjcryptlib.zip WjCryptLib-*/' \
    "$impl/c/v0.0.1/Makefile"
for d in go/v0.46 go/v0.47 go/v0.48 dotnet/v1.0 js/v1.x js/v2.x js/v3.x nim/v1.14 nim/v2.4 python/v0.x jvm/v1.3 \
         c/v0.0.1 rust/v0.53 rust/v0.54 rust/v0.55 rust/v0.56; do
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
    else
        (cd "$impl/$d" && make image.json > build.log 2>&1) || { echo "FAIL $name: see $impl/$d/build.log"; exit 1; }
    fi
    echo "built $name"
done

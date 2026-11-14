#!/bin/sh
# Run transport-interop pairs: the asm-libp2p node dials each implementation,
# and each implementation dials the asm-libp2p node, over TCP with Noise, for
# each muxer the implementation offers. A pair passes when the dialer prints
# its handshake and ping times.
# Usage: tests/interop/run.sh ISA [IMPLEMENTATION ...]    (no names: all 16)
# Needs the images from tests/interop/build-images.sh.
set -u
isa=$1
shift
asm=asm-libp2p-interop-$isa
all="go-v0.46:yamux go-v0.47:yamux go-v0.48:yamux dotnet-v1.0:yamux
node-js-v1.x:yamux,mplex node-js-v2.x:yamux,mplex node-js-v3.x:yamux,mplex nim-v1.14:yamux,mplex
nim-v2.4:yamux,mplex python-v0.x:yamux,mplex jvm-libp2p-v1.3:yamux,mplex c-v0.0.1:yamux,mplex
rust-v0.53:yamux,mplex rust-v0.54:yamux,mplex rust-v0.55:yamux,mplex rust-v0.56:yamux,mplex"

pair() {    # dialer image, listener image, muxer -> 0 when the dialer reported its times
    tmp=$(mktemp -d)
    cat > "$tmp/compose.yaml" <<YAML
name: interop
services:
  dialer:
    image: $1
    depends_on: [redis]
    environment: {transport: tcp, is_dialer: "true", ip: 0.0.0.0, muxer: $3, security: noise}
  listener:
    init: true
    image: $2
    depends_on: [redis]
    environment: {transport: tcp, is_dialer: "false", ip: 0.0.0.0, muxer: $3, security: noise}
  redis:
    image: redis:7-alpine
    environment: {REDIS_ARGS: --loglevel warning}
YAML
    out=$(timeout 180 docker compose -f "$tmp/compose.yaml" up --exit-code-from dialer --renew-anon-volumes 2>&1)
    docker compose -f "$tmp/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$tmp"
    echo "$out" | grep -q "dialer.*handshakePlusOneRTTMillis" && return 0
    echo "$out" | grep -E "dialer|listener" | grep -v "Container\|Attaching" | tail -15
    return 1
}

pass=0 fail=0
for entry in $all; do
    impl=${entry%%:*}
    if [ $# -gt 0 ]; then
        wanted=0
        for name in "$@"; do [ "$name" = "$impl" ] && wanted=1; done
        [ $wanted = 1 ] || continue
    fi
    for muxer in $(echo "${entry#*:}" | tr , ' '); do
        for dir in asm-to-impl impl-to-asm; do
            if [ $dir = asm-to-impl ]; then d=$asm; l=$impl; else d=$impl; l=$asm; fi
            if pair "$d" "$l" "$muxer"; then echo "PASS $impl $muxer $dir"; pass=$((pass + 1));
            else echo "FAIL $impl $muxer $dir"; fail=$((fail + 1)); fi
        done
    done
done
echo "$pass pairs passed, $fail failed"
[ $fail = 0 ]

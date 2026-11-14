#!/bin/sh
# Run transport-interop pairs: the asm-libp2p node dials each implementation,
# and each implementation dials the asm-libp2p node, over TCP with Noise, for
# each muxer the implementation offers. A pair passes when the dialer prints
# its handshake and ping times.
# Usage: tests/interop/run.sh ISA [IMPLEMENTATION ...]    (no names: all 16)
# Environment: RUNS=n runs each pair n times (default 1). BASELINE=1 also runs
# each implementation against itself, and the asm-libp2p node against itself.
# Each line: PASS or FAIL, implementation, muxer, direction, then for a pass
# the handshakePlusOneRTTMillis and pingRTTMilllis that the dialer printed.
# Needs the images from tests/interop/build-images.sh.
set -u
isa=$1
shift
asm=asm-libp2p-interop-$isa
runs=${RUNS:-1}
baseline=${BASELINE:-0}
all="go-v0.46:yamux go-v0.47:yamux go-v0.48:yamux dotnet-v1.0:yamux
node-js-v1.x:yamux,mplex node-js-v2.x:yamux,mplex node-js-v3.x:yamux,mplex nim-v1.14:yamux,mplex
nim-v2.4:yamux,mplex python-v0.x:yamux,mplex jvm-libp2p-v1.3:yamux,mplex c-v0.0.1:yamux,mplex
rust-v0.53:yamux,mplex rust-v0.54:yamux,mplex rust-v0.55:yamux,mplex rust-v0.56:yamux,mplex"
[ "$baseline" = 1 ] && all="asm-libp2p:yamux,mplex $all"

pair() {    # dialer image, listener image, muxer -> 0, with timing set, when the dialer reported its times
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
    result=$(echo "$out" | grep "dialer.*handshakePlusOneRTTMillis" | tail -1)
    if [ -n "$result" ]; then
        h=$(echo "$result" | sed -n 's/.*"handshakePlusOneRTTMillis": *\([0-9.eE+-]*\).*/\1/p')
        p=$(echo "$result" | sed -n 's/.*"pingRTTMilllis": *\([0-9.eE+-]*\).*/\1/p')
        timing="$h $p"
        return 0
    fi
    echo "$out" | grep -E "dialer|listener" | grep -v "Container\|Attaching" | tail -15
    return 1
}

pass=0 fail=0
for entry in $all; do
    impl=${entry%%:*}
    if [ $# -gt 0 ] && [ "$impl" != asm-libp2p ]; then
        wanted=0
        for name in "$@"; do [ "$name" = "$impl" ] && wanted=1; done
        [ $wanted = 1 ] || continue
    fi
    dirs="asm-to-impl impl-to-asm"
    [ "$baseline" = 1 ] && dirs="$dirs impl-to-impl"
    [ "$impl" = asm-libp2p ] && dirs=impl-to-impl
    image=$impl
    [ "$impl" = asm-libp2p ] && image=$asm
    for muxer in $(echo "${entry#*:}" | tr , ' '); do
        for dir in $dirs; do
            case $dir in
              asm-to-impl)  d=$asm;   l=$image ;;
              impl-to-asm)  d=$image; l=$asm ;;
              impl-to-impl) d=$image; l=$image ;;
            esac
            n=0
            while [ $n -lt "$runs" ]; do
                n=$((n + 1))
                if pair "$d" "$l" "$muxer"; then echo "PASS $impl $muxer $dir $timing"; pass=$((pass + 1));
                else echo "FAIL $impl $muxer $dir"; fail=$((fail + 1)); fi
            done
        done
    done
done
echo "$pass pairs passed, $fail failed"
[ $fail = 0 ]

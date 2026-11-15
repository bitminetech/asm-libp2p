#!/bin/sh
# Run gossipsub-interop in Shadow: the subnet-blob-msg scenario for each
# composition, with the check of the suite that every message after the first
# 4 reached every node; then the three partial message scenarios for each
# partial composition, with the check of the suite that every node logged
# "All parts received" for every group.
# Usage: tests/gossipsub/run.sh WORK_DIR [COMPOSITION ...]
#   A composition names implementations joined by +, such as asm+go; each
#   node runs one of them, picked at random with equal weights. None given:
#   asm, go, asm+go, asm+rust, asm+jvm, asm+nim, asm+go+rust+jvm+nim.
# Environment: NODES=n nodes in each subnet-blob-msg run (default 32, as make
# test of the suite); PARTIAL="COMPOSITION ..." the partial compositions
# (default asm asm+go asm+rust asm+nim, the implementations of the suite
# with partial messages; empty: none); TIMEOUT=s seconds a run may take
# (default 900). A run past it ends: the script prints the processes using
# the most CPU, then stops it.
# A composition with jvm runs with experimental.native_preemption_enabled in
# the Shadow config: a JVM thread can spin without system calls, and Shadow
# then stops (limitations.md of Shadow, "Busy loops").
# Needs Shadow and uv on the PATH, and tests/gossipsub/build.sh first.
#
# Each line: PASS, OTHER or FAIL, the scenario and composition; for
# subnet-blob-msg, the means over the checked messages from
# plots/analysis.txt: time to reach every node, time to reach half of them,
# duplicates per node, and the lowest reach.
#   PASS: the check of the suite passed.
#   OTHER: only nodes of other implementations failed (verdict.py names
#   them), or a run past TIMEOUT had a process of another implementation as
#   the busiest. It counts as passed, and the line says why.
#   FAIL: an asm-libp2p node failed, the run cannot be read, or a run past
#   TIMEOUT had an asm-libp2p process, or a process of no implementation, as
#   the busiest.
# The script fails when a run fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$1
shift
gs=$work/test-plans/gossipsub-interop
nodes=${NODES:-32}
partial=${PARTIAL-asm asm+go asm+rust asm+nim}
limit=${TIMEOUT:-900}
cd "$gs" || exit 2
pass=0 other=0 fail=0
# The template of the suite, kept once: each run writes shadow.template.yaml from it.
[ -f "$work/shadow.template.orig.yaml" ] || cp shadow.template.yaml "$work/shadow.template.orig.yaml"

# run SCENARIO NODES COMPOSITION: one Shadow run; 0 when it ended within the limit.
run() {
    name=$1-$2-$3
    case $3 in
      *jvm*) awk '{ print } /^experimental:$/ { print "  native_preemption_enabled: true"; found = 1 }
                  END { exit !found }' "$work/shadow.template.orig.yaml" > shadow.template.yaml ||
                 { echo "shadow.template.yaml: experimental not found" >&2; exit 2; } ;;
      *) cp "$work/shadow.template.orig.yaml" shadow.template.yaml ;;
    esac
    uv run run.py --node_count "$2" --composition $(echo "$3" | tr + ' ') \
        --scenario "$1" --output_dir "$name" > "$work/$name.log" 2>&1 &
    pid=$! waited=0
    while kill -0 $pid 2>/dev/null && [ $waited -lt "$limit" ]; do
        sleep 5
        waited=$((waited + 5))
    done
    if kill -0 $pid 2>/dev/null; then
        # The busiest process besides Shadow: a node that keeps Shadow from moving on.
        busy=$(ps -eo pcpu=,args= --sort=-pcpu | awk '$2 != "shadow" && $2 != "ps" && $2 != "awk" { $1 = ""; print; exit }')
        case $busy in
          *asm-libp2p/gossipsub-bin*) result=FAIL impl=asm-libp2p ;;
          *go-libp2p/*) result=OTHER impl=go ;;
          *rust-libp2p*) result=OTHER impl=rust ;;
          *nim-libp2p/*) result=OTHER impl=nim ;;
          *jvm-libp2p*) result=OTHER impl=jvm ;;
          *) result=FAIL impl="no implementation" ;;
        esac
        echo "$result $1 $3: no end after $limit s; the busiest process besides Shadow is of $impl. The processes using the most CPU:"
        ps -eo pid,pcpu,etime,args --sort=-pcpu | head -12 | cut -c1-200
        pkill -TERM -f "shadow --progress true" 2>/dev/null     # one simulation runs at a time
        sleep 10
        pkill -KILL -f "shadow --progress true" 2>/dev/null
        pkill -KILL -f "gossipsub-bin|rust-libp2p-gossip|jvm-libp2p-gossip" 2>/dev/null
        wait $pid 2>/dev/null
        cp shadow.yaml params.json "shadow-outputs/$name/" 2>/dev/null
        if [ $result = FAIL ]; then fail=$((fail + 1)); else other=$((other + 1)); fi
        return 1
    fi
    wait $pid
}

# judge SCENARIO COMPOSITION CHECK_STATUS COUNT DETAIL: counts and prints the result of a run that ended.
judge() {
    if [ "$3" = 0 ]; then
        echo "PASS $1 $2${5:+ $5}"; pass=$((pass + 1))
        return
    fi
    verdict=$(python3 -I "$here/verdict.py" "shadow-outputs/$name" "$1" "$4")
    if [ $? = 0 ]; then
        echo "OTHER $1 $2${5:+ $5}: the check of the suite failed on other implementations only. $verdict"
        other=$((other + 1))
    else
        echo "FAIL $1 $2${5:+ $5}: $verdict"; tail -5 "$work/$name.check"; fail=$((fail + 1))
    fi
}

for comp in ${*:-asm go asm+go asm+rust asm+jvm asm+nim asm+go+rust+jvm+nim}; do
    run subnet-blob-msg "$nodes" "$comp" || continue
    summary=$(awk -F', ' 'NR > 1 { n++; full += $2; half += $3; dup += $4; if (n == 1 || $5 < low) low = $5 }
        END { if (n) printf "full %.3fs half %.3fs duplicates %.2f reach %s", full / n, half / n, dup / n, low }' \
        "shadow-outputs/$name/plots/analysis.txt" 2>/dev/null)
    uv run checks/subnet_blob_msg.py "shadow-outputs/$name" > "$work/$name.check" 2>&1
    judge subnet-blob-msg "$comp" $? 1 "$summary"
done

# The partial scenarios with the node counts and log counts of make test of the suite.
for comp in $partial; do
    for case in partial-messages:32:1 partial-messages-chain:8:16 partial-messages-fanout:8:1; do
        scenario=${case%%:*} rest=${case#*:}
        count=${rest#*:}
        run "$scenario" "${rest%%:*}" "$comp" || continue
        uv run checks/partial_messages.py "shadow-outputs/$name" --count "$count" > "$work/$name.check" 2>&1
        judge "$scenario" "$comp" $? "$count" ""
    done
done
echo "$pass runs passed, $other failed on other implementations only, $fail failed"
[ $fail = 0 ]

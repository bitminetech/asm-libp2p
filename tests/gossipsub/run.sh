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
# (default 900). A run past it fails: the script prints the processes using
# the most CPU, then stops it.
# Needs Shadow and uv on the PATH, and tests/gossipsub/build.sh first.
#
# Each line: PASS or FAIL, the scenario and composition; for subnet-blob-msg,
# the means over the checked messages from plots/analysis.txt: time to reach
# every node, time to reach half of them, duplicates per node, and the lowest
# reach.
set -u
work=$1
shift
gs=$work/test-plans/gossipsub-interop
nodes=${NODES:-32}
partial=${PARTIAL-asm asm+go asm+rust asm+nim}
limit=${TIMEOUT:-900}
cd "$gs" || exit 2
pass=0 fail=0

# run SCENARIO NODES COMPOSITION: one Shadow run; 0 when it ended within the limit.
run() {
    name=$1-$2-$3
    uv run run.py --node_count "$2" --composition $(echo "$3" | tr + ' ') \
        --scenario "$1" --output_dir "$name" > "$work/$name.log" 2>&1 &
    pid=$! waited=0
    while kill -0 $pid 2>/dev/null && [ $waited -lt "$limit" ]; do
        sleep 5
        waited=$((waited + 5))
    done
    if kill -0 $pid 2>/dev/null; then
        echo "FAIL $1 $3: no end after $limit s; the processes using the most CPU:"
        ps -eo pid,pcpu,etime,args --sort=-pcpu | head -12 | cut -c1-200
        pkill -TERM -f "shadow --progress true" 2>/dev/null     # one simulation runs at a time
        sleep 10
        pkill -KILL -f "shadow --progress true" 2>/dev/null
        pkill -KILL -f "gossipsub-bin|rust-libp2p-gossip|jvm-libp2p-gossip" 2>/dev/null
        wait $pid 2>/dev/null
        fail=$((fail + 1))
        return 1
    fi
    wait $pid
}

for comp in ${*:-asm go asm+go asm+rust asm+jvm asm+nim asm+go+rust+jvm+nim}; do
    run subnet-blob-msg "$nodes" "$comp" || continue
    summary=$(awk -F', ' 'NR > 1 { n++; full += $2; half += $3; dup += $4; if (n == 1 || $5 < low) low = $5 }
        END { if (n) printf "full %.3fs half %.3fs duplicates %.2f reach %s", full / n, half / n, dup / n, low }' \
        "shadow-outputs/$name/plots/analysis.txt" 2>/dev/null)
    if uv run checks/subnet_blob_msg.py "shadow-outputs/$name" > "$work/$name.check" 2>&1; then
        echo "PASS subnet-blob-msg $comp $summary"; pass=$((pass + 1))
    else
        echo "FAIL subnet-blob-msg $comp $summary"; tail -5 "$work/$name.check"; fail=$((fail + 1))
    fi
done

# The partial scenarios with the node counts and log counts of make test of the suite.
for comp in $partial; do
    for case in partial-messages:32:1 partial-messages-chain:8:16 partial-messages-fanout:8:1; do
        scenario=${case%%:*} rest=${case#*:}
        count=${rest#*:}
        run "$scenario" "${rest%%:*}" "$comp" || continue
        if uv run checks/partial_messages.py "shadow-outputs/$name" --count "$count" > "$work/$name.check" 2>&1; then
            echo "PASS $scenario $comp"; pass=$((pass + 1))
        else
            echo "FAIL $scenario $comp"; tail -5 "$work/$name.check"; fail=$((fail + 1))
        fi
    done
done
echo "$pass runs passed, $fail failed"
[ $fail = 0 ]

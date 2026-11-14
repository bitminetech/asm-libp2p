#!/bin/sh
# Run gossipsub-interop in Shadow: the subnet-blob-msg scenario for each
# composition, then the check of the suite that every message after the first
# 4 reached every node.
# Usage: tests/gossipsub/run.sh WORK_DIR [COMPOSITION ...]
#   A composition names implementations joined by +, such as asm+go; each
#   node runs one of them, picked at random with equal weights. None given:
#   asm, go, asm+go, asm+rust, asm+jvm, asm+nim, asm+go+rust+jvm+nim.
# Environment: NODES=n nodes in each run (default 32, as make test of the
# suite); TIMEOUT=s seconds a run may take (default 900). A run past it
# fails: the script prints the processes using the most CPU, then stops it.
# Needs Shadow and uv on the PATH, and tests/gossipsub/build.sh first.
#
# Each line: PASS or FAIL, the composition, then the means over the checked
# messages from plots/analysis.txt: time to reach every node, time to reach
# half of them, duplicates per node, and the lowest reach.
set -u
work=$1
shift
gs=$work/test-plans/gossipsub-interop
nodes=${NODES:-32}
limit=${TIMEOUT:-900}
cd "$gs" || exit 2
pass=0 fail=0
for comp in ${*:-asm go asm+go asm+rust asm+jvm asm+nim asm+go+rust+jvm+nim}; do
    name=subnet-blob-msg-$nodes-$comp
    uv run run.py --node_count "$nodes" --composition $(echo "$comp" | tr + ' ') \
        --scenario subnet-blob-msg --output_dir "$name" > "$work/$name.log" 2>&1 &
    run=$! waited=0
    while kill -0 $run 2>/dev/null && [ $waited -lt "$limit" ]; do
        sleep 5
        waited=$((waited + 5))
    done
    if kill -0 $run 2>/dev/null; then
        echo "FAIL $comp: no end after $limit s; the processes using the most CPU:"
        ps -eo pid,pcpu,etime,args --sort=-pcpu | head -12 | cut -c1-200
        pkill -TERM -f "shadow --progress true" 2>/dev/null     # one simulation runs at a time
        sleep 10
        pkill -KILL -f "shadow --progress true" 2>/dev/null
        pkill -KILL -f "gossipsub-bin|rust-libp2p-gossip|jvm-libp2p-gossip" 2>/dev/null
        wait $run 2>/dev/null
        fail=$((fail + 1))
        continue
    fi
    wait $run
    summary=$(awk -F', ' 'NR > 1 { n++; full += $2; half += $3; dup += $4; if (n == 1 || $5 < low) low = $5 }
        END { if (n) printf "full %.3fs half %.3fs duplicates %.2f reach %s", full / n, half / n, dup / n, low }' \
        "shadow-outputs/$name/plots/analysis.txt" 2>/dev/null)
    if uv run checks/subnet_blob_msg.py "shadow-outputs/$name" > "$work/$name.check" 2>&1; then
        echo "PASS $comp $summary"; pass=$((pass + 1))
    else
        echo "FAIL $comp $summary"; tail -5 "$work/$name.check"; fail=$((fail + 1))
    fi
done
echo "$pass compositions passed, $fail failed"
[ $fail = 0 ]

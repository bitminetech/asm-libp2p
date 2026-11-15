"""The nodes of a gossipsub-interop run that failed, with their implementation.

Usage: verdict.py OUTPUT_DIR SCENARIO [COUNT]
  OUTPUT_DIR  a Shadow output directory of run.py: hosts/, shadow.yaml and
              params.json
  SCENARIO    subnet-blob-msg, or a partial message scenario
  COUNT       for a partial message scenario: the "All parts received" lines
              each node needs (default 1)

subnet-blob-msg: a node fails when a checked message did not reach it and it
did not publish it. The checked messages are the ones after the first 4, in
the order of their first delivery, as checks/subnet_blob_msg.py of the suite
takes them.
A partial message scenario: a node fails when its stdout has fewer than COUNT
"All parts received" lines, as checks/partial_messages.py of the suite counts
them.

Prints one line: the failing asm-libp2p nodes, then the failing nodes of other
implementations, each with its implementation.
Exit status: 0 when no asm-libp2p node fails; 1 when one does; 2 when the run
cannot be read.
"""
import json
import os
import re
import sys

# The first directory of the binary path of each implementation in experiment.py of the suite.
IMPLEMENTATIONS = {'asm-libp2p': 'asm', 'go-libp2p': 'go', 'rust-libp2p': 'rust', 'nim-libp2p': 'nim', 'jvm-libp2p': 'jvm'}


def implementations(path):
    """node name -> implementation, from the hosts of shadow.yaml."""
    out, host = {}, None
    for line in open(path):
        m = re.match(r'^  (node\d+):\s*$', line)
        if m:
            host = m.group(1)
            continue
        m = re.match(r'^\s+path:\s*(\S+)\s*$', line)
        if m and host and host not in out:
            out[host] = IMPLEMENTATIONS.get(m.group(1).split('/')[0], m.group(1))
    return out


def stdout_lines(hosts, node):
    """The JSON objects of the stdout logs of a node."""
    for name in sorted(os.listdir(os.path.join(hosts, node))):
        if not name.endswith('.stdout'):
            continue
        for line in open(os.path.join(hosts, node, name), errors='replace'):
            try:
                yield json.loads(line)
            except ValueError:
                continue


def publishers(path):
    """message ID (as logged: base 10) -> the node name that publishes it, from params.json."""
    out = {}

    def walk(ins, node):
        if ins.get('type') == 'ifNodeIDEquals':
            walk(ins['instruction'], 'node%d' % ins['nodeID'])
        elif ins.get('type') == 'publish' and node:
            out[str(ins['messageID'])] = node

    for ins in json.load(open(path))['script']:
        walk(ins, None)
    return out


def failing_blob(out_dir, nodes):
    hosts = os.path.join(out_dir, 'hosts')
    deliveries, first = {}, {}
    for node in nodes:
        for e in stdout_lines(hosts, node):
            if e.get('msg') == 'Received Message' and e.get('id'):
                deliveries.setdefault(e['id'], set()).add(node)
                t = e.get('time', '')
                if e['id'] not in first or t < first[e['id']]:
                    first[e['id']] = t
    pub = publishers(os.path.join(out_dir, 'params.json'))
    failing = set()
    for mid in sorted(deliveries, key=lambda m: first[m])[4:]:
        failing |= set(nodes) - deliveries[mid] - {pub.get(mid)}
    return failing


def failing_partial(out_dir, nodes, count):
    hosts = os.path.join(out_dir, 'hosts')
    return {n for n in nodes if sum(e.get('msg') == 'All parts received' for e in stdout_lines(hosts, n)) < count}


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip().split('\n')[2], file=sys.stderr)
        return 2
    out_dir, scenario = sys.argv[1], sys.argv[2]
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    try:
        impl = implementations(os.path.join(out_dir, 'shadow.yaml'))
        nodes = sorted(os.listdir(os.path.join(out_dir, 'hosts')), key=lambda n: int(n[4:]))
        failing = failing_blob(out_dir, nodes) if scenario == 'subnet-blob-msg' else failing_partial(out_dir, nodes, count)
    except (OSError, ValueError, KeyError) as e:
        print('cannot read the run: %s' % e)
        return 2
    order = sorted(failing, key=lambda n: int(n[4:]))
    ours = [n for n in order if impl.get(n) == 'asm']
    others = ['%s %s' % (n, impl.get(n, '?')) for n in order if impl.get(n) != 'asm']
    print('asm-libp2p nodes failing: %s; nodes of other implementations failing: %s'
          % (', '.join(ours) or 'none', ', '.join(others) or 'none'))
    return 1 if ours else 0


if __name__ == '__main__':
    sys.exit(main())

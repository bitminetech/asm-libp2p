"""
Turn node records into the peer list of tests/mainnet/node.c.

Usage: python3 -I tests/mainnet/peers.py < records.txt > peers.txt
Input: any text; every "enr:..." word is read as a record (EIP-778).
Output: one line per record with an IPv4 address, a TCP port and a
secp256k1 key: "IP PORT PEER_ID_HEX FORK_DIGEST_HEX". The peer ID is the
identity multihash of the protobuf public key (libp2p peer-ids spec); the
fork digest is the first 4 bytes of the "eth2" value, or 00000000.
"""

import base64
import re
import sys


def rlp_item(b, i):
    """(value, next index): value is bytes or a list."""
    p = b[i]
    if p < 0x80:
        return b[i:i + 1], i + 1
    if p < 0xB8:
        n = p - 0x80
        return b[i + 1:i + 1 + n], i + 1 + n
    if p < 0xC0:
        ln = p - 0xB7
        n = int.from_bytes(b[i + 1:i + 1 + ln], "big")
        return b[i + 1 + ln:i + 1 + ln + n], i + 1 + ln + n
    if p < 0xF8:
        n, j = p - 0xC0, i + 1
    else:
        ln = p - 0xF7
        n, j = int.from_bytes(b[i + 1:i + 1 + ln], "big"), i + 1 + ln
    end, out = j + n, []
    while j < end:
        v, j = rlp_item(b, j)
        out.append(v)
    return out, end


def record(text):
    raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    items, _ = rlp_item(raw, 0)
    return {items[k].decode("latin-1"): items[k + 1] for k in range(2, len(items) - 1, 2)}


def main():
    seen = set()
    for text in re.findall(r"enr:([A-Za-z0-9_-]+)", sys.stdin.read()):
        try:
            r = record(text)
        except (IndexError, ValueError):
            continue
        ip, tcp, key = r.get("ip"), r.get("tcp"), r.get("secp256k1")
        if not ip or len(ip) != 4 or not tcp or not key or len(key) != 33:
            continue
        peer_id = bytes([0x00, 0x25, 0x08, 0x02, 0x12, 0x21]) + key
        if peer_id in seen:
            continue
        seen.add(peer_id)
        eth2 = r.get("eth2", b"")
        digest = eth2[:4].hex() if len(eth2) >= 4 else "00000000"
        print(".".join(str(x) for x in ip), int.from_bytes(tcp, "big"), peer_id.hex(), digest)


main()

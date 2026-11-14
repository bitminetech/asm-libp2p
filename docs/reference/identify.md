# Identify

## Contents

### Functions

- [`libp2p_observed`](#function-libp2p_observed): writes the binary multiaddr of an address.
- [`libp2p_identify`](#function-libp2p_identify): answers an identify stream.

## Spec

- Document: [identify/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/identify/README.md), libp2p/specs at commit c750236.
- Section: The Identify message and the identify protocol (`/ipfs/id/1.0.0`), as a responder. go-libp2p and js-libp2p ask for it before they open gossipsub streams.

## Function `libp2p_observed`

Writes the binary multiaddr of a TCP address.

### Signature

```
libp2p_observed(dst, addr) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 20 bytes |
| `addr` | input | [`Address`](node.md#type-address) |

### Function does

- Writes /ip4 (code 4, 4 bytes) or /ip6 (code 41, 16 bytes), then /tcp (code 6, the port big endian), one byte at a time.

### Function never

- Writes more than the multiaddr.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_observed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the length, not a status.
- Argument order: `dst`, `addr`.

## Function `libp2p_identify`

Writes the Identify message on a stream the peer opened, then closes it.

### Signature

```
libp2p_identify(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Queues one Identify protobuf with its varint length: publicKey (1), observedAddr (4, the address of the connection), protocols (3: "/ipfs/id/1.0.0", "/meshsub/1.3.0" when `gossipsub_v13` is on, "/meshsub/1.2.0" when `gossipsub_v12` is on, "/meshsub/1.1.0" and the protocols of the config), then protocolVersion (5) and agentVersion (6) when the config sets them.
- Then marks the stream to close after the message.
- Closes the stream without a message when the heap has no block for it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_identify`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Test vectors

- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): go, js and rust libp2p identify the node.
- gossipsub runs with go-libp2p and js-libp2p peers in the live mainnet test ([tests/mainnet/](../../tests/mainnet/)).

## Results

<!-- CI generates the tick table for each function here. -->

# Peer IDs and encodings

## Contents

### Functions

- [`libp2p_varint_put`](#function-libp2p_varint_put): writes an unsigned varint.
- [`libp2p_varint_len`](#function-libp2p_varint_len): gives the bytes of a varint.
- [`libp2p_varint_get`](#function-libp2p_varint_get): reads an unsigned varint.
- [`libp2p_pb_next`](#function-libp2p_pb_next): reads one protobuf field.
- [`libp2p_pb_bytes`](#function-libp2p_pb_bytes): writes a bytes field.
- [`libp2p_pb_varint`](#function-libp2p_pb_varint): writes a varint field.
- [`libp2p_pb_size`](#function-libp2p_pb_size): gives the bytes of a bytes field.
- [`libp2p_key_proto`](#function-libp2p_key_proto): writes a PublicKey protobuf.
- [`libp2p_peer_id`](#function-libp2p_peer_id): writes a peer ID.
- [`libp2p_der_int`](#function-libp2p_der_int): writes a DER INTEGER.
- [`libp2p_der_encode`](#function-libp2p_der_encode): writes a DER ECDSA signature.
- [`libp2p_der_get`](#function-libp2p_der_get): reads a DER INTEGER.
- [`libp2p_der_decode`](#function-libp2p_der_decode): reads a DER ECDSA signature.

## Spec

- Document: [peer-ids/peer-ids.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/peer-ids/peer-ids.md), libp2p/specs at commit c750236; and [unsigned-varint](https://github.com/multiformats/unsigned-varint/blob/dd184f1ce89c81808503bb719b5fcb13844d08f3/README.md), multiformats/unsigned-varint at commit dd184f1.
- Section: Keys (the PublicKey protobuf), Peer Ids (the identity multihash of keys of 42 bytes or less), the unsigned varint; and the minimal protobuf and DER encodings these use.

## Function `libp2p_varint_put`

Writes an unsigned varint.

### Signature

```
libp2p_varint_put(dst, value) -> dst after the varint
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 10 bytes |
| `value` | input | u64 |

### Function does

- Writes 7 bits in each byte, the lowest first, with the top bit set on every byte but the last.

### Function never

- Writes more than the varint.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_varint_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the varint, not a status.
- Argument order: `dst`, `value`.

## Function `libp2p_varint_len`

Gives the bytes of the varint of a value.

### Signature

```
libp2p_varint_len(value) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 |

### Function does

- Gives 1 for a value below 128, and 1 more for each further 7 bits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_varint_len`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the byte count, not a status.
- Argument order: `value`.

## Function `libp2p_varint_get`

Reads an unsigned varint.

### Signature

```
libp2p_varint_get(src, end) -> value, bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `src` | input | the bytes up to `end` |
| `end` | input | u64: the address after the bytes |

### Function does

- Gives the value and the bytes the varint takes.
- Gives bytes 0 when the bytes end before the varint does.
- Gives bytes `NONE` when the varint passes 64 bits or its value is 2^63 or more.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_varint_get`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the value in x0, rax or a0 and the bytes in x1, rdx or a1.
- Argument order: `src`, `end`.

## Function `libp2p_pb_next`

Reads the next field of a protobuf message.

### Signature

```
libp2p_pb_next(p, end) -> found, field, type, value, length, next
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `p` | input | the bytes up to `end` |
| `end` | input | u64: the address after the message |

### Function does

- Gives found 1 and the field: its number, its wire type, its value (varint, 64-bit or 32-bit) or the start of its bytes (type 2), the length of its bytes, and the position after it.
- Gives found 0 at the end of the message.
- Gives found `NONE` for field number 0, a wire type other than 0, 1, 2 or 5, a bad varint, or a field past `end`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pb_next`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns found, field, type, value, length and next in x0 to x5 on ARM64, a0 to a5 on RISC-V, and rax, rdx, rcx, rsi, rdi and r8 on x86-64.
- Argument order: `p`, `end`.

## Function `libp2p_pb_bytes`

Writes a protobuf field of wire type 2.

### Signature

```
libp2p_pb_bytes(dst, field, src, n) -> dst after the field
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | the field bytes |
| `field` | input | u64: the field number |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- Writes the key (field << 3 | 2), the varint length, then the bytes.

### Function never

- Writes more than the field.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pb_bytes`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the field, not a status.
- Argument order: `dst`, `field`, `src`, `n`.

## Function `libp2p_pb_varint`

Writes a protobuf field of wire type 0.

### Signature

```
libp2p_pb_varint(dst, field, value) -> dst after the field
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | the field bytes |
| `field` | input | u64: the field number |
| `value` | input | u64 |

### Function does

- Writes the key (field << 3), then the value as a varint.

### Function never

- Writes more than the field.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pb_varint`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the field, not a status.
- Argument order: `dst`, `field`, `value`.

## Function `libp2p_pb_size`

Gives the bytes of a protobuf field of wire type 2.

### Signature

```
libp2p_pb_size(field, n) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `field` | input | u64: the field number |
| `n` | input | u64: bytes of the value |

### Function does

- Gives the bytes of the key, the length and the value.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_pb_size`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the byte count, not a status.
- Argument order: `field`, `n`.

## Function `libp2p_key_proto`

Writes the PublicKey protobuf of the peer-ids spec.

### Signature

```
libp2p_key_proto(dst, type, key, n) -> dst after the message
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | the message bytes |
| `type` | input | u64: `LIBP2P_KEY_ED25519` or `LIBP2P_KEY_SECP256K1` |
| `key` | input | n bytes |
| `n` | input | u64: 32 or 33 |

### Function does

- Writes Type (field 1, a varint), then Data (field 2, the key bytes).

### Function never

- Writes more than the message.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_key_proto`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the message, not a status.
- Argument order: `dst`, `type`, `key`, `n`.

## Function `libp2p_peer_id`

Writes the peer ID of a public key.

### Signature

```
libp2p_peer_id(dst, type, key, n) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to `LIBP2P_MAX_PEER_ID` bytes |
| `type` | input | u64: `LIBP2P_KEY_ED25519` or `LIBP2P_KEY_SECP256K1` |
| `key` | input | n bytes |
| `n` | input | u64: 32 or 33 |

### Function does

- Writes the identity multihash of the PublicKey protobuf: 0x00, the protobuf length, the protobuf.
- Gives at most 44 bytes for these key types: the protobuf of either is at most 42 bytes.

### Function never

- Writes more than the peer ID.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_id`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the length, not a status.
- Argument order: `dst`, `type`, `key`, `n`.

## Function `libp2p_der_int`

Writes a 256-bit number as a DER INTEGER.

### Signature

```
libp2p_der_int(dst, src) -> dst after the INTEGER
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 35 bytes |
| `src` | input | 32 bytes: the number, big endian |

### Function does

- Drops leading zero bytes, keeps at least one byte, and puts 0x00 first when the top bit is set: the minimal positive form.
- Writes tag 0x02, the length, then the bytes.

### Function never

- Writes more than the INTEGER.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_der_int`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the INTEGER, not a status.
- Argument order: `dst`, `src`.

## Function `libp2p_der_encode`

Writes an ECDSA signature as a DER SEQUENCE of r and s.

### Signature

```
libp2p_der_encode(dst, sig) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 72 bytes |
| `sig` | input | 64 bytes: r then s, big endian |

### Function does

- Writes tag 0x30, the length, then r and s with `libp2p_der_int`.

### Function never

- Writes more than 72 bytes.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_der_encode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the length, not a status.
- Argument order: `dst`, `sig`.

## Function `libp2p_der_get`

Reads a positive DER INTEGER of at most 32 bytes of value.

### Signature

```
libp2p_der_get(dst, p, end) -> next
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | 32 bytes: the number, big endian |
| `p` | input | the bytes up to `end` |
| `end` | input | u64: the address after the bytes |

### Function does

- Takes tag 0x02, a short length of 1 or more within `end`, a value whose top bit is clear, and at most 32 bytes after leading zero bytes.
- Writes the value right-aligned in 32 bytes and gives the position after the INTEGER, or 0 when it breaks a rule.

### Function never

- Writes more than `dst`.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_der_get`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the position or 0, not a status.
- Argument order: `dst`, `p`, `end`.

## Function `libp2p_der_decode`

Reads a DER SEQUENCE of two positive INTEGERs r and s.

### Signature

```
libp2p_der_decode(sig, p, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sig` | output | 64 bytes: r then s, big endian |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes at least 8 bytes: tag 0x30, a short length that covers exactly the rest, then r and s with `libp2p_der_get`, ending at the last byte.
- Gives 1 when the bytes follow these rules, else 0.

### Function never

- Writes more than `sig`.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_der_decode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns 1 or 0, not a status.
- Argument order: `sig`, `p`, `n`.

## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): peer_id, and every connection between nodes with Ed25519 and secp256k1 keys.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): every implementation checks the peer ID and identity signature of the node.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_varint_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_varint_len`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_varint_get`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pb_next`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pb_bytes`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pb_varint`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_pb_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_key_proto`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_der_int`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_der_encode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_der_get`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_der_decode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ |  |  |  |
| ARM64 | ✅ |  | ✅ |  |
| RISC-V | ✅ |  |  |  |

# Noise

## Contents

### Functions

- [`libp2p_ns_mixhash`](#function-libp2p_ns_mixhash): mixes bytes into the handshake hash.
- [`libp2p_ns_hkdf`](#function-libp2p_ns_hkdf): derives two keys from the chaining key.
- [`libp2p_ns_mixkey`](#function-libp2p_ns_mixkey): mixes a DH result into the keys.
- [`libp2p_ns_nonce`](#function-libp2p_ns_nonce): writes a Noise nonce.
- [`libp2p_ns_encrypt_hash`](#function-libp2p_ns_encrypt_hash): encrypts and hashes handshake bytes.
- [`libp2p_ns_decrypt_hash`](#function-libp2p_ns_decrypt_hash): decrypts and hashes handshake bytes.
- [`libp2p_ns_dh`](#function-libp2p_ns_dh): mixes a Diffie-Hellman result into the keys.
- [`libp2p_noise_out`](#function-libp2p_noise_out): makes room in the output buffer of a connection.
- [`libp2p_noise_begin`](#function-libp2p_noise_begin): starts the Noise handshake of a connection.
- [`libp2p_noise_payload`](#function-libp2p_noise_payload): checks the handshake payload of the peer.
- [`libp2p_noise_split`](#function-libp2p_noise_split): derives the transport keys.
- [`libp2p_noise_message`](#function-libp2p_noise_message): handles one Noise handshake message.
- [`libp2p_noise_seal`](#function-libp2p_noise_seal): writes one Noise transport message.
- [`libp2p_noise_open`](#function-libp2p_noise_open): reads one Noise transport message.
- [`libp2p_sign_static`](#function-libp2p_sign_static): signs the static Noise key with the identity key.
- [`libp2p_verify_static`](#function-libp2p_verify_static): checks the identity signature of a static Noise key.
- [`libp2p_low_s`](#function-libp2p_low_s): normalises an ECDSA s to its low form.

## Spec

- Document: [noise/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/noise/README.md), libp2p/specs at commit c750236; and [The Noise Protocol Framework](https://noiseprotocol.org/noise.html), revision 34.
- Section: the libp2p Noise handshake (Noise_XX_25519_ChaChaPoly_SHA256), the handshake payload and its signature, and transport messages.

## Function `libp2p_ns_mixhash`

MixHash of the Noise spec: h = SHA-256(h || data).

### Signature

```
libp2p_ns_mixhash(conn, data, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `data` | input | n bytes |
| `n` | input | u64: at most 65536 |

### Function does

- Hashes `h` of the connection and the bytes through the MIX buffer of the scratch, and writes the result to `h`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_mixhash`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `data`, `n`.

## Function `libp2p_ns_hkdf`

HKDF of the Noise spec with the chaining key.

### Signature

```
libp2p_ns_hkdf(conn, ikm, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `ikm` | input | n bytes |
| `n` | input | u64: 0 or 32 |

### Function does

- Writes HKDF-SHA-256 with salt `ck` and an empty info, 64 bytes, to the OKM of the scratch: the two outputs of the Noise HKDF.
- Sets `ck` to the first 32 bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_hkdf`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `ikm`, `n`.

## Function `libp2p_ns_mixkey`

MixKey of the Noise spec for a 32-byte DH result.

### Signature

```
libp2p_ns_mixkey(conn, ikm)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `ikm` | input | 32 bytes |

### Function does

- Sets `ck` and the cipher key `k` from `libp2p_ns_hkdf`, the nonce to 0, and marks `k` as set.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_mixkey`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `ikm`.

## Function `libp2p_ns_nonce`

Writes the 12-byte ChaCha20-Poly1305 nonce of Noise to the scratch.

### Signature

```
libp2p_ns_nonce(n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64: the nonce counter |

### Function does

- Writes 4 zero bytes, then `n` little endian, to the NONCE of the scratch.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_nonce`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `n`.

## Function `libp2p_ns_encrypt_hash`

EncryptAndHash of the Noise spec.

### Signature

```
libp2p_ns_encrypt_hash(conn, src, n, dst) -> dst after the output
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `src` | input | n bytes |
| `n` | input | u64: at most 4096 |
| `dst` | output | n or n + 16 bytes |

### Function does

- With `k` set, writes ChaCha20-Poly1305 of the bytes with `k`, the next nonce and `h` as associated data: n + 16 bytes.
- Without `k`, copies the bytes.
- Then mixes what it wrote into `h`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_encrypt_hash`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the address after the output, not a status.
- Argument order: `conn`, `src`, `n`, `dst`.

## Function `libp2p_ns_decrypt_hash`

DecryptAndHash of the Noise spec.

### Signature

```
libp2p_ns_decrypt_hash(conn, src, n) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- With `k` set, writes the plaintext to the PLAIN [`ByteList`](node.md#type-bytelist) of the scratch with `k`, the next nonce and `h` as associated data; gives 1 when `n` is below 16 or the tag does not match.
- Without `k`, copies the bytes to the PLAIN list.
- Then mixes the n input bytes into `h`, and gives 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_decrypt_hash`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0 when the bytes are good, else 1, not a status.
- Argument order: `conn`, `src`, `n`.

## Function `libp2p_ns_dh`

MixKey of an X25519 result.

### Signature

```
libp2p_ns_dh(conn, private, public) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `private` | input | 32 bytes |
| `public` | input | 32 bytes |

### Function does

- Computes X25519 of the keys with `crypto_x25519`, then `libp2p_ns_mixkey` of the result.
- Gives 1 when the result is all zero, which a low-order public key gives; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_ns_dh`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0 or 1, not a status.
- Argument order: `conn`, `private`, `public`.

## Function `libp2p_noise_out`

Makes room for n more bytes in the output buffer of a connection.

### Signature

```
libp2p_noise_out(conn, n) -> place
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `n` | input | u64 |

### Function does

- Gives the place of the n bytes and moves the buffer length past them, or gives 0 when they pass the 768 bytes of the buffer.
- Before the transport keys, marks the bytes to go out as they are.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_out`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the place or 0, not a status.
- Argument order: `conn`, `n`.

## Function `libp2p_noise_begin`

Starts the Noise XX handshake.

### Signature

```
libp2p_noise_begin(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Sets `h` and `ck` to "Noise_XX_25519_ChaChaPoly_SHA256" (32 bytes, so h is the name), with no key and nonce 0.
- Mixes the empty prologue into `h`.
- Draws a fresh ephemeral key `e` from the DRBG.
- On a dial, writes message 1 with its 2-byte length: `e`, then an empty payload.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_begin`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_noise_payload`

Checks the NoiseHandshakePayload of the peer.

### Signature

```
libp2p_noise_payload(conn, p, n, rs) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |
| `rs` | input | 32 bytes: the peer's static key |

### Function does

- Reads identity_key (field 1) and identity_sig (field 2); other fields are skipped.
- Reads Type (field 1) and Data (field 2) of the key, and checks the signature with `libp2p_verify_static`.
- Writes the key type and the peer ID to the connection, and gives 0; gives 1 when a field is missing or bad, or the signature fails.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_payload`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0 or 1, not a status.
- Argument order: `conn`, `p`, `n`, `rs`.

## Function `libp2p_noise_split`

Split of the Noise spec: the transport keys.

### Signature

```
libp2p_noise_split(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Derives (k1, k2) with `libp2p_ns_hkdf` and no input.
- The dialer sends with k1 and receives with k2; the listener the other way.
- Sets both nonces to 0, marks the transport keys in use, and wipes the ephemeral key.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_split`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_noise_message`

Handles one Noise XX handshake message and writes the next.

### Signature

```
libp2p_noise_message(conn, msg, n) -> 0, 1 or 2
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `msg` | input | n bytes: the message without its length |
| `n` | input | u64 |

### Function does

- Listener, message 1: reads `e` and the payload; writes message 2: `e`, ee, `s`, es and our payload.
- Dialer, message 2: reads `e`, ee, `s`, es and the payload of the peer; when the dial named a peer ID, checks it is the peer's; writes message 3: `s`, se and our payload; then splits.
- Listener, message 3: reads `s`, se and the payload of the peer; then splits.
- Gives 0 when the message is good, 1 when the handshake fails, and 2 when a dial reached another peer than the one it named; then message 3 is never written.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_message`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0, 1 or 2, not a status.
- Argument order: `conn`, `msg`, `n`.

## Function `libp2p_noise_seal`

Writes one Noise transport message.

### Signature

```
libp2p_noise_seal(conn, src, n, dst) -> dst after the message
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `src` | input | n bytes |
| `n` | input | u64: at most `LIBP2P_NOISE_PLAIN` |
| `dst` | output | n + 18 bytes |

### Function does

- Writes the 2-byte big-endian length n + 16, then ChaCha20-Poly1305 of the bytes with the send key, its next nonce and empty associated data.
- Takes the bytes from the PLAIN list of the scratch when `src` is there already.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_seal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the address after the message, not a status.
- Argument order: `conn`, `src`, `n`, `dst`.

## Function `libp2p_noise_open`

Reads one Noise transport message.

### Signature

```
libp2p_noise_open(conn, src, n) -> 0 or 1
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `src` | input | n bytes: the message without its length |
| `n` | input | u64 |

### Function does

- Writes the plaintext to the PLAIN [`ByteList`](node.md#type-bytelist) of the scratch with the receive key, its next nonce and empty associated data.
- Gives 1 when `n` is below 16 or the tag does not match, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_noise_open`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0 or 1, not a status.
- Argument order: `conn`, `src`, `n`.

## Function `libp2p_sign_static`

Signs the static Noise key with the identity key and builds our NoiseHandshakePayload.

### Signature

```
libp2p_sign_static()
```

### Function does

- Signs "noise-libp2p-static-key:" followed by the 32-byte static X25519 public key.
- Ed25519: the signature of `crypto_ed25519_sign`. secp256k1: the DER form of the low-s ECDSA signature of the SHA-256 of the message, from `crypto_secp256k1_sign`.
- Writes the payload to the state: identity_key (field 1, the PublicKey protobuf), then identity_sig (field 2).

### Function never

- Writes outside the state and its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 288 bytes on x86-64 (return address included), 288 bytes on ARM64, 304 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_sign_static`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_verify_static`

Checks that a signature by an identity key covers a static Noise key.

### Signature

```
libp2p_verify_static(type, key, key_length, sig, sig_length, static) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | u64: the key type |
| `key` | input | `key_length` bytes |
| `key_length` | input | u64 |
| `sig` | input | `sig_length` bytes |
| `sig_length` | input | u64 |
| `static` | input | 32 bytes |

### Function does

- Ed25519: takes a 32-byte key and a 64-byte signature, and checks with `crypto_ed25519_verify`.
- secp256k1: takes a 33-byte compressed key and a DER signature, takes s above n / 2 as n - s, and checks the SHA-256 of the message with `crypto_secp256k1_verify`.
- The message is "noise-libp2p-static-key:" followed by `static`.
- Gives 1 for a valid signature, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 320 bytes on x86-64 (return address included), 320 bytes on ARM64, 336 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_verify_static`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `type`, `key`, `key_length`, `sig`, `sig_length`, `static`.

## Function `libp2p_low_s`

Replaces a high ECDSA s with n - s.

### Signature

```
libp2p_low_s(s)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `s` | state | 32 bytes: s, big endian |

### Function does

- When s is above n / 2 of secp256k1, writes n - s; else leaves s.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_low_s`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `s`.

## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): yamux, mplex, peer_id, garbage, and every connection.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): Noise with go, rust, js, nim, python, jvm, dotnet and c libp2p.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_ns_mixhash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_hkdf`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_mixkey`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_nonce`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_encrypt_hash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_decrypt_hash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_ns_dh`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_out`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_begin`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_split`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_message`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_seal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_noise_open`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_sign_static`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_verify_static`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_low_s`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

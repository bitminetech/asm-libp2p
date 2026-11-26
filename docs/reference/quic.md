# QUIC

QUIC connections through asm-quic.

## Contents

### Functions

- [`libp2p_quic_config`](#function-libp2p_quic_config): writes the asm-quic Config of the node.
- [`libp2p_peer_id_proto`](#function-libp2p_peer_id_proto): gives the peer ID of a PublicKey protobuf.
- [`libp2p_qroom`](#function-libp2p_qroom): gives the room of the event list for asm-quic.
- [`libp2p_qevent`](#function-libp2p_qevent): starts an event for asm-quic.
- [`libp2p_qclose`](#function-libp2p_qclose): asks asm-quic to close a connection.
- [`libp2p_qreset`](#function-libp2p_qreset): asks asm-quic to reset a stream.
- [`libp2p_qev_drop`](#function-libp2p_qev_drop): drops the events asm-quic took.
- [`libp2p_on_datagram`](#function-libp2p_on_datagram): hands a UDP datagram to asm-quic.
- [`libp2p_qconn_of`](#function-libp2p_qconn_of): finds the connection of an asm-quic handle.
- [`libp2p_qconn_bind`](#function-libp2p_qconn_bind): binds an asm-quic handle to a connection.
- [`libp2p_qstream_of`](#function-libp2p_qstream_of): finds the stream of an asm-quic handle.
- [`libp2p_qstream_bind`](#function-libp2p_qstream_bind): binds an asm-quic handle to a stream.
- [`libp2p_qreason`](#function-libp2p_qreason): maps a QUIC dial failure to a libp2p reason.
- [`libp2p_quic_need`](#function-libp2p_quic_need): gives the action room an asm-quic action may need.
- [`libp2p_quic_actions`](#function-libp2p_quic_actions): hands on the actions of the last quic_step.
- [`libp2p_quic_action`](#function-libp2p_quic_action): hands on one asm-quic action.
- [`libp2p_q_send`](#function-libp2p_q_send): turns an asm-quic SEND into a SEND_DATAGRAM action.
- [`libp2p_q_connected`](#function-libp2p_q_connected): opens a QUIC connection.
- [`libp2p_q_dial_failed`](#function-libp2p_q_dial_failed): ends a QUIC dial that failed.
- [`libp2p_q_closed`](#function-libp2p_q_closed): ends a QUIC connection.
- [`libp2p_q_opened`](#function-libp2p_q_opened): binds an asm-quic stream to a stream.
- [`libp2p_q_data`](#function-libp2p_q_data): hands stream bytes to their stream.
- [`libp2p_q_fin`](#function-libp2p_q_fin): marks the end of the peer's side of a stream.
- [`libp2p_q_reset`](#function-libp2p_q_reset): ends a stream the peer reset.
- [`libp2p_q_acked`](#function-libp2p_q_acked): counts acknowledged stream bytes.
- [`libp2p_quic_emit`](#function-libp2p_quic_emit): writes the asm-quic events of one stream.
- [`libp2p_quic_gather`](#function-libp2p_quic_gather): writes the asm-quic events of every QUIC connection.
- [`libp2p_quic_pump`](#function-libp2p_quic_pump): runs asm-quic for a step.

### Types

- [`DatagramEvent`](#type-datagramevent): a UDP datagram the shell received.
- [`SendDatagramAction`](#type-senddatagramaction): a UDP datagram for the shell to send.

### Constants

- `LIBP2P_TCP`, `LIBP2P_QUIC`: the transports of DIAL and PEER_CONNECTED.
- `LIBP2P_QUIC_ON`, `LIBP2P_QUIC_ACCEPT`: the bits of the `quic` field of the config.
- `LIBP2P_DATAGRAM_MAX`: bytes of one DATAGRAM event or SEND_DATAGRAM action, at most.
- `LIBP2P_QUIC_EVENTS`: bytes of the event list for asm-quic in the state.
- `LIBP2P_QUIC_ACTIONS`: bytes of the action list of asm-quic in the state.
- `LIBP2P_QUIC_WRITE`: bytes of one asm-quic STREAM_WRITE event, at most.

## Spec

- Document: [quic/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/quic/README.md) and [tls/tls.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/tls/tls.md), libp2p/specs at commit c750236; [peer-ids/peer-ids.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/peer-ids/peer-ids.md) for the peer ID of a host key.
- Section: the libp2p side of the `/quic-v1` transport. asm-quic (README Dependencies) does QUIC v1 and the TLS 1.3 handshake with the libp2p certificate, and gives connections and streams. This library runs multistream-select, identify and gossipsub on those streams as it runs them on yamux streams.
- The state holds the asm-quic state, the event list for asm-quic, the action list of its last `quic_step`, and two u32 maps: from asm-quic connection and stream slots to the slots of this library.

## Function `libp2p_quic_config`

Writes the asm-quic Config of a node from its config.

### Signature

```
libp2p_quic_config(config, dst)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](node.md#type-config) |
| `dst` | output | asm-quic `Config`: `QUIC_CFG_SIZE` bytes |

### Function does

- Zeroes `dst`, then writes its size, `QUIC_VERSION`, the key type and private key of the config.
- Connections and streams: `max_connections` and `max_streams`.
- Handshake time: `handshake_ms`.
- The QUIC fields: `quic_heap`, `quic_idle_ms`, `quic_keep_alive_ms`, `quic_max_data`, `quic_stream_data`, `quic_max_streams`, `quic_sent`.
- Accept flag: bit 1 of `quic` (`LIBP2P_QUIC_ACCEPT`).
- Stream queue: `quic_window` + `LIBP2P_QUIC_WRITE`. asm-quic counts a chunk until all of it is acknowledged, and one STREAM_WRITE of this library is at most `LIBP2P_QUIC_WRITE` bytes.
- Leaves the seed zero: `libp2p_init` draws it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_config`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `config`, `dst`.

## Function `libp2p_peer_id_proto`

Writes the peer ID of a PublicKey protobuf.

### Signature

```
libp2p_peer_id_proto(dst, proto, n) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 44 bytes |
| `proto` | input | `n` bytes: a PublicKey protobuf |
| `n` | input | u64: 1 to 128 |

### Function does

- `n` at most 42: the identity multihash: 0x00, `n`, then the protobuf.
- Else the SHA-256 multihash: 0x12, 0x20, then `crypto_sha256` of the protobuf, from a ByteList on its own stack.
- Gives the length: `n` + 2, or 34.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 256 bytes on ARM64, 272 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_peer_id_proto`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the length, not a status.
- Argument order: `dst`, `proto`, `n`.

## Function `libp2p_qroom`

Gives the bytes left in the event list for asm-quic.

### Signature

```
libp2p_qroom() -> bytes
```

### Function does

- Gives the size of the list less its 24-byte header and its bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qroom`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the byte count, not a status.

## Function `libp2p_qevent`

Adds an event at the end of the event list for asm-quic.

### Signature

```
libp2p_qevent(kind, size) -> event
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64: `QUIC_EVENT_<KIND>` |
| `size` | input | u64: a multiple of 8, at least 24 |

### Function does

- Gives 0 when the list has fewer than `size` bytes left.
- Else adds `size` bytes to the list, sets the size and kind, zeroes the last 8 bytes, and gives the address of the event.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qevent`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the event address or 0, not a status.
- Argument order: `kind`, `size`.

## Function `libp2p_qclose`

Adds an asm-quic CLOSE event.

### Signature

```
libp2p_qclose(conn) -> event
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | input | u64: an asm-quic connection handle |

### Function does

- Adds CLOSE with the handle and code 0, and gives the event; 0 when the list has no room.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qclose`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the event address or 0, not a status.
- Argument order: `conn`.

## Function `libp2p_qreset`

Adds an asm-quic STREAM_RESET event.

### Signature

```
libp2p_qreset(stream) -> event
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | u64: an asm-quic stream handle |

### Function does

- Adds STREAM_RESET with the handle and code 0, and gives the event; 0 when the list has no room.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qreset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the event address or 0, not a status.
- Argument order: `stream`.

## Function `libp2p_qev_drop`

Removes the first events of the event list for asm-quic.

### Signature

```
libp2p_qev_drop(n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64: the events `quic_step` accepted |

### Function does

- Skips `n` events, or all when the list holds fewer.
- Moves the rest to the front of the list.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qev_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `n`.

## Function `libp2p_on_datagram`

Hands one DATAGRAM event to asm-quic.

### Signature

```
libp2p_on_datagram(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`DatagramEvent`](#type-datagramevent) |

### Function does

- Adds an asm-quic DATAGRAM event of the same size, and copies the socket, address, count and bytes.
- `libp2p_event_room` keeps the event out of the step when the list has no room for it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_datagram`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_qconn_of`

Finds the QUIC connection of an asm-quic connection handle.

### Signature

```
libp2p_qconn_of(handle) -> conn
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: an asm-quic connection handle |

### Function does

- Reads the connection index at the slot index of the handle (its low 32 bits) in the connection map.
- Gives the [`Connection`](connections.md#type-connection) when it is in use, has the QUIC flag and holds the same handle; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qconn_of`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot address or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_qconn_bind`

Binds an asm-quic connection handle to a connection.

### Signature

```
libp2p_qconn_bind(handle, conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: an asm-quic connection handle |
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Writes the handle in the connection.
- Writes the connection index in the connection map at the slot index of the handle, when that index is below `max_connections`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qconn_bind`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `handle`, `conn`.

## Function `libp2p_qstream_of`

Finds the stream of an asm-quic stream handle.

### Signature

```
libp2p_qstream_of(handle) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: an asm-quic stream handle |

### Function does

- Reads the stream index at the slot index of the handle (its low 32 bits) in the stream map.
- Gives the [`Stream`](streams.md#type-stream) when it is in use and its ID is the handle; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qstream_of`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot address or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_qstream_bind`

Binds an asm-quic stream handle to a stream.

### Signature

```
libp2p_qstream_bind(handle, stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: an asm-quic stream handle |
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Writes the handle as the stream ID.
- Writes the stream index in the stream map at the slot index of the handle, when that index is below `max_streams`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qstream_bind`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `handle`, `stream`.

## Function `libp2p_qreason`

Gives the libp2p reason of an asm-quic DIAL_FAILED reason.

### Signature

```
libp2p_qreason(reason) -> reason
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `reason` | input | u64: `QUIC_ERR_<NAME>` |

### Function does

- PEER_ID: `LIBP2P_REASON_PEER_ID`.
- LIMIT: `LIBP2P_REASON_LIMIT`.
- HANDSHAKE_TIMEOUT: `LIBP2P_REASON_CONNECT`.
- Any other: `LIBP2P_REASON_HANDSHAKE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_qreason`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the reason, not a status.
- Argument order: `reason`.

## Function `libp2p_quic_need`

Gives the action bytes that handling one asm-quic action may need.

### Signature

```
libp2p_quic_need(action) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic action |

### Function does

- SEND: its size.
- STREAM_DATA: 64 + 16 for each byte.
- CONNECTED, DIAL_FAILED and CLOSED: 16384, as for an event that can end a connection.
- WAKEUP: 0.
- Any other: 1024.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_need`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the byte count, not a status.
- Argument order: `action`.

## Function `libp2p_quic_actions`

Hands on the actions of the last `quic_step`, while the action room lasts.

### Signature

```
libp2p_quic_actions() -> done
```

### Function does

- Starts after the actions already handled, at `ST_QACT_DONE`.
- For each action: stops when `libp2p_room` is below `libp2p_quic_need`; else `libp2p_quic_action`.
- All handled: empties the action list and gives 1.
- Room ran out: asks for a wakeup now and gives 0; the next step starts with the rest.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_actions`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.

## Function `libp2p_quic_action`

Hands one asm-quic action to the function of its kind.

### Signature

```
libp2p_quic_action(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic action |

### Function does

- SEND, CONNECTED, DIAL_FAILED, CLOSED, STREAM_OPENED, STREAM_DATA, STREAM_FIN, STREAM_RESET, STREAM_ACKED: a direct call to `libp2p_q_<kind>`.
- WAKEUP: keeps its time, in microseconds, for `libp2p_quic_pump`.
- Skips any other kind.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_action`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_send`

Turns an asm-quic SEND action into a SEND_DATAGRAM action.

### Signature

```
libp2p_q_send(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic SEND action |

### Function does

- Starts a [`SendDatagramAction`](#type-senddatagramaction) of the same size, and copies the socket, address, count and bytes.
- Writes nothing when `libp2p_action` gives no room.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_send`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_connected`

Opens a connection when asm-quic finishes a QUIC handshake.

### Signature

```
libp2p_q_connected(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic CONNECTED action |

### Function does

- Tag nonzero, our dial: the tag is the connection handle; it must be a QUIC connection in the DIALING phase.
- Tag 0, the peer's dial: `libp2p_conn_new` with flags QUIC and inbound, then the address and the UDP socket ID of the action.
- Binds the asm-quic handle to the connection.
- Writes the peer ID of the host key protobuf (`libp2p_peer_id_proto`), then `libp2p_conn_opened`: the connection is open and bound to its peer, as after Noise and the muxer on TCP.
- No connection waits for it, or no slot is free: an asm-quic CLOSE.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_connected`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_dial_failed`

Ends our QUIC dial that asm-quic could not finish.

### Signature

```
libp2p_q_dial_failed(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic DIAL_FAILED action |

### Function does

- Finds the connection of the tag; it must be a QUIC connection in the DIALING phase.
- `libp2p_conn_teardown` with the reason of `libp2p_qreason`, which gives the DIAL_FAILED action, then frees the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_dial_failed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_closed`

Ends a QUIC connection that asm-quic closed.

### Signature

```
libp2p_q_closed(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic CLOSED action |

### Function does

- Finds the connection of the asm-quic handle.
- Not in the CLOSING phase: `libp2p_conn_teardown` with `LIBP2P_REASON_CLOSED`.
- Then frees the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_closed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_opened`

Binds a stream that asm-quic opened to a stream slot.

### Signature

```
libp2p_q_opened(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic STREAM_OPENED action |

### Function does

- Tag nonzero, our OPEN_STREAM: the tag is the stream handle; the stream must have ID 0 and belong to the QUIC connection of the action.
- Ours with an asm-quic handle: binds it. Ours with handle 0 (asm-quic had no stream): `libp2p_stream_abort` with `LIBP2P_REASON_LIMIT`.
- Tag 0, the peer's: its connection must be open; `libp2p_stream_new` as inbound, then binds the handle. multistream-select then runs on it as on yamux.
- No stream waits for it, or no slot is free: an asm-quic STREAM_RESET.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_opened`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_data`

Hands the bytes of an asm-quic stream to its stream.

### Signature

```
libp2p_q_data(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic STREAM_DATA action |

### Function does

- Finds the stream of the handle, then `libp2p_stream_data` with the bytes, as for a yamux DATA frame.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_data`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_fin`

Marks that the peer closed its side of an asm-quic stream.

### Signature

```
libp2p_q_fin(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic STREAM_FIN action |

### Function does

- Finds the stream of the handle, then `libp2p_stream_remote_fin`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_fin`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_reset`

Ends a stream that the peer reset.

### Signature

```
libp2p_q_reset(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic STREAM_RESET action |

### Function does

- Finds the stream of the handle.
- Adds an asm-quic STREAM_RESET for our side, then `libp2p_stream_kill` with `LIBP2P_REASON_CLOSED`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_reset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_q_acked`

Takes acknowledged bytes off the bytes in flight of a stream.

### Signature

```
libp2p_q_acked(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | an asm-quic STREAM_ACKED action |

### Function does

- Finds the stream of the handle.
- Takes the count, at most the bytes in flight, off the bytes in flight. `libp2p_quic_emit` then writes more of the queue.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_q_acked`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `action`.

## Function `libp2p_quic_emit`

Writes the asm-quic events of one stream of a QUIC connection.

### Signature

```
libp2p_quic_emit(conn, stream) -> full
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot: QUIC, open |
| `stream` | state | [`Stream`](streams.md#type-stream) slot of the connection |

### Function does

- Reset asked for: STREAM_RESET when asm-quic gave the stream a handle; the stream is then dead.
- New stream: OPEN_STREAM with the connection handle and the stream handle as tag.
- No asm-quic handle yet: stops; STREAM_OPENED gives it.
- Queued bytes: STREAM_WRITE events of at most `LIBP2P_QUIC_WRITE` bytes each, while the bytes in flight stay below `quic_window`. Each adds its count to the bytes in flight.
- Close asked for and the queue empty: STREAM_CLOSE, once.
- Closed both ways: the stream is dead.
- Gives 1 when the event list ran out of room, else 0. A later step writes the rest.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_emit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `conn`, `stream`.

## Function `libp2p_quic_gather`

Writes the asm-quic events of every QUIC connection.

### Signature

```
libp2p_quic_gather() -> full
```

### Function does

- New dial: DIAL with the connection handle as tag, the UDP socket ID, the address and the peer ID the dial expects.
- Close asked for: CLOSE of the asm-quic handle.
- Open connection: `libp2p_quic_emit` for each stream; frees each dead stream.
- Gives 1 when the event list ran out of room, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_gather`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.

## Function `libp2p_quic_pump`

Runs asm-quic for one step.

### Signature

```
libp2p_quic_pump()
```

### Function does

- Each round: `libp2p_quic_actions`, then `libp2p_quic_gather`.
- Then `quic_step` with the asm-quic tick of the step, the event list and the scratch of `quic_step` in the libp2p scratch, when the list holds events or the asm-quic deadline is due. Then drops the events it accepted.
- At most 16 rounds.
- Stops when the action room runs out, or when nothing is left to do or due.
- Wakeup: now while events or actions wait; else the asm-quic deadline, rounded up to a ms.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_quic_pump`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Type `DatagramEvent`

The shell received a UDP datagram.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `socket` | u64 | The UDP socket ID that `libp2p_shell_bind` gave |
| 24 | `addr` | [`Address`](node.md#type-address) | The sender |
| 56 | `count` | u64 | Bytes of the datagram, 0 to `LIBP2P_DATAGRAM_MAX` |
| 64 | `bytes` | `count` bytes | The datagram |

### Rules

- Kind `LIBP2P_EVENT_DATAGRAM`, size from `LIBP2P_EV_DG_DATA` + `count` rounded up to 8, at most `LIBP2P_EV_DG_DATA` + `LIBP2P_DATAGRAM_MAX`.
- Needs QUIC on in the config.
- A step takes it only while the event list for asm-quic has room for it; else it stays for a later step.

## Type `SendDatagramAction`

The shell sends a UDP datagram.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `socket` | u64 | The UDP socket ID |
| 24 | `addr` | [`Address`](node.md#type-address) | The receiver |
| 56 | `count` | u64 | Bytes of the datagram |
| 64 | `bytes` | `count` bytes | The datagram |

### Rules

- Kind `LIBP2P_ACTION_SEND_DATAGRAM`.
- The shell sends it with `sendto`, or drops it when the OS does not take it: QUIC sends again what is lost.

## Test vectors

- Runner scenarios ([tests/runner/](../../tests/runner/)): quic, quic_streams, quic_loss, quic_dial_fails, quic_gossip and quic_mixed carry datagrams between nodes in memory.
- Shell loop test ([tests/shell/](../../tests/shell/)): round 3 runs two nodes over 127.0.0.1 UDP.
- transport-interop of libp2p/test-plans over quic-v1 ([tests/interop/](../../tests/interop/)): 12 implementations, both directions.
- The live mainnet test ([tests/mainnet/](../../tests/mainnet/)) dials consensus clients over QUIC.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_quic_config`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_peer_id_proto`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qroom`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qevent`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qclose`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qreset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qev_drop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_datagram`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qconn_of`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qconn_bind`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qstream_of`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qstream_bind`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_qreason`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_need`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_actions`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_action`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_send`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_connected`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_dial_failed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_closed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_opened`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_fin`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_q_acked`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_emit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_gather`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_quic_pump`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

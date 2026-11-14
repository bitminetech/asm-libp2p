# Muxers

## Contents

### Functions

- [`libp2p_mux_feed`](#function-libp2p_mux_feed): hands plaintext to the muxer.
- [`libp2p_mux_data`](#function-libp2p_mux_data): hands frame data to its stream.
- [`libp2p_mux_end_frame`](#function-libp2p_mux_end_frame): acts on the flags of a frame.
- [`libp2p_mux_find`](#function-libp2p_mux_find): finds a stream by muxer ID.
- [`libp2p_mux_rst`](#function-libp2p_mux_rst): queues a reset for a stream without a slot.
- [`libp2p_mux_error`](#function-libp2p_mux_error): closes a connection that broke the muxer protocol.
- [`libp2p_yamux_feed`](#function-libp2p_yamux_feed): reads yamux frames.
- [`libp2p_yamux_frame`](#function-libp2p_yamux_frame): handles one yamux header.
- [`libp2p_yamux_stream`](#function-libp2p_yamux_stream): finds or opens the stream of a yamux frame.
- [`libp2p_mplex_feed`](#function-libp2p_mplex_feed): reads mplex messages.
- [`libp2p_mplex_frame`](#function-libp2p_mplex_frame): handles one mplex header.
- [`libp2p_yamux_header`](#function-libp2p_yamux_header): writes a yamux header.
- [`libp2p_mplex_header`](#function-libp2p_mplex_header): writes an mplex header.
- [`libp2p_chunk_take`](#function-libp2p_chunk_take): takes bytes from the queue of a stream.
- [`libp2p_yamux_emit`](#function-libp2p_yamux_emit): writes the yamux frames of a stream.
- [`libp2p_mplex_emit`](#function-libp2p_mplex_emit): writes the mplex messages of a stream.
- [`libp2p_mux_gather`](#function-libp2p_mux_gather): writes the muxer frames of a connection.
- [`libp2p_drain`](#function-libp2p_drain): turns queued bytes into SEND actions.
- [`libp2p_drain_conn`](#function-libp2p_drain_conn): writes one SEND action for a connection.
- [`libp2p_out_drop`](#function-libp2p_out_drop): drops bytes from the output buffer.
- [`libp2p_conn_pending`](#function-libp2p_conn_pending): tells whether a connection has frames to send.

### Types

- [`Chunk`](#type-chunk): queued bytes of a stream.
- [`SendAction`](#type-sendaction): bytes for the shell to write.

### Constants

- `LIBP2P_YAMUX_WINDOW`: the first window of a yamux stream.
- `LIBP2P_YAMUX_BACKLOG`: inbound yamux streams that may wait for ACK.
- `LIBP2P_MPLEX_MAX`: bytes of an mplex message.
- `LIBP2P_NOISE_PLAIN`: plaintext bytes of a Noise transport message.

## Spec

- Document: [yamux/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/yamux/README.md) and [mplex/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/mplex/README.md), libp2p/specs at commit c750236.
- Section: yamux framing, flags and flow control; mplex messages and flags.

## Function `libp2p_mux_feed`

Hands plaintext bytes to the muxer of a connection.

### Signature

```
libp2p_mux_feed(conn, p, n) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Calls `libp2p_yamux_feed` or `libp2p_mplex_feed`, as the connection chose.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_feed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes taken, not a status.
- Argument order: `conn`, `p`, `n`.

## Function `libp2p_mux_data`

Hands data bytes of the current frame to its stream.

### Signature

```
libp2p_mux_data(conn, p, n) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Takes at most the bytes left in the frame.
- yamux: takes them off the receive window and counts them for the next window update.
- Passes them to the stream with `libp2p_stream_data`; drops them when the frame has no stream.
- Runs `libp2p_mux_end_frame` when the frame ends.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_data`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes taken, not a status.
- Argument order: `conn`, `p`, `n`.

## Function `libp2p_mux_end_frame`

Acts on the end flags of a frame that ended.

### Signature

```
libp2p_mux_end_frame(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- RST: ends the stream with `libp2p_stream_kill` and the reason CLOSED.
- FIN: `libp2p_stream_remote_fin`.
- Forgets the stream of the frame.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_end_frame`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_mux_find`

Finds a stream of a connection by muxer ID and side.

### Signature

```
libp2p_mux_find(conn, id, local) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | input | [`Connection`](connections.md#type-connection) slot |
| `id` | input | u64: the muxer stream ID |
| `local` | input | u64: `SF_LOCAL` for our streams, 0 for the peer's |

### Function does

- Gives the stream with the ID that the side opened, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `conn`, `id`, `local`.

## Function `libp2p_mux_rst`

Queues a reset for a stream that has no slot.

### Signature

```
libp2p_mux_rst(conn, id)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `id` | input | u64: a yamux stream ID, or an mplex reset header |

### Function does

- Keeps up to 6 resets; the next drain sends them; more are dropped.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_rst`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `id`.

## Function `libp2p_mux_error`

Closes a connection whose peer broke the muxer protocol.

### Signature

```
libp2p_mux_error(conn) -> 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Closes the connection with the reason CLOSED, and gives 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_error`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0, the bytes taken, not a status.
- Argument order: `conn`.

## Function `libp2p_yamux_feed`

Takes frame data, or header bytes up to one whole header.

### Signature

```
libp2p_yamux_feed(conn, p, n) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Inside a frame: `libp2p_mux_data`.
- Else collects the 12 header bytes and handles a whole header with `libp2p_yamux_frame`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_yamux_feed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes taken, not a status.
- Argument order: `conn`, `p`, `n`.

## Function `libp2p_yamux_frame`

Handles one 12-byte yamux header.

### Signature

```
libp2p_yamux_frame(conn)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Reads version, type, flags, stream ID and length, big endian.
- Ping with SYN: keeps the opaque value for a pong, up to 4 at a time.
- Go Away: closes the connection with CLOSED.
- Data and Window Update: finds or opens the stream with `libp2p_yamux_stream`; a Window Update adds its length to the send window; Data gives the bytes that follow to the stream.
- Ends the connection with `libp2p_mux_error` for version other than 0, an unknown type, stream ID 0, a protocol error of the stream, or Data past the receive window.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_yamux_frame`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`.

## Function `libp2p_yamux_stream`

Finds the stream of a yamux frame, or opens one for SYN.

### Signature

```
libp2p_yamux_stream(conn, id, flags) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `id` | input | u64: the stream ID |
| `flags` | input | u64: the frame flags |

### Function does

- Without SYN: gives our stream with the ID, else the peer's, else 0: the frame is dropped.
- With SYN: the ID must have the parity of the peer (odd for the dialer, even for the listener) and be new, else `NONE`.
- Opens a stream of the peer that will send ACK; resets it with `libp2p_mux_rst` and gives 0 when 256 streams wait for ACK or no slot is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_yamux_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot, 0 or NONE, not a status.
- Argument order: `conn`, `id`, `flags`.

## Function `libp2p_mplex_feed`

Takes message data, or header bytes one at a time.

### Signature

```
libp2p_mplex_feed(conn, p, n) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Inside a message: `libp2p_mux_data`.
- Else takes header bytes until both varints are whole, and handles them with `libp2p_mplex_frame`.
- Ends the connection with `libp2p_mux_error` for a bad varint or a header of 20 bytes or more.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mplex_feed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes taken, not a status.
- Argument order: `conn`, `p`, `n`.

## Function `libp2p_mplex_frame`

Handles one mplex header.

### Signature

```
libp2p_mplex_frame(conn, header, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `header` | input | u64: stream ID << 3 | flag |
| `length` | input | u64: data bytes |

### Function does

- NewStream (flag 0): opens a stream of the peer; its name is dropped; resets it when no slot is free.
- Message, Close and Reset: finds the stream (odd flags come from the receiver side, so the stream is ours); Close acts as FIN and Reset as RST at the end of the message; data for no stream is dropped.
- Ends the connection with `libp2p_mux_error` for data above `LIBP2P_MPLEX_MAX`, a flag above 6, an ID of 2^28 or more, or a NewStream for an ID in use.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mplex_frame`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `header`, `length`.

## Function `libp2p_yamux_header`

Writes a 12-byte yamux header.

### Signature

```
libp2p_yamux_header(dst, type, flags, id, length) -> dst + 12
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | 12 bytes |
| `type` | input | u64 |
| `flags` | input | u64 |
| `id` | input | u64 |
| `length` | input | u64 |

### Function does

- Writes version 0, the type, the 16-bit flags, the 32-bit ID and the 32-bit length, big endian.

### Function never

- Writes more than 12 bytes.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_yamux_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns `dst` + 12, not a status.
- Argument order: `dst`, `type`, `flags`, `id`, `length`.

## Function `libp2p_mplex_header`

Writes an mplex header.

### Signature

```
libp2p_mplex_header(dst, header, length) -> dst after the header
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | up to 20 bytes |
| `header` | input | u64: stream ID << 3 | flag |
| `length` | input | u64 |

### Function does

- Writes the two varints.

### Function never

- Writes more than the header.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mplex_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address after the header, not a status.
- Argument order: `dst`, `header`, `length`.

## Function `libp2p_chunk_take`

Copies bytes from the first queued chunk of a stream.

### Signature

```
libp2p_chunk_take(stream, dst, max) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `dst` | output | up to `max` bytes |
| `max` | input | u64 |

### Function does

- Copies the unsent bytes of the first chunk, at most `max`, and counts them sent.
- Frees the chunk when all its bytes are sent.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_chunk_take`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes copied, not a status.
- Argument order: `stream`, `dst`, `max`.

## Function `libp2p_yamux_emit`

Writes the yamux frames a stream has to send.

### Signature

```
libp2p_yamux_emit(conn, stream, dst, room) -> dst after the frames
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `dst` | output | `room` bytes |
| `room` | input | u64 |

### Function does

- RST: a Window Update with RST; the stream is then dead.
- SYN or ACK: a Window Update with the flag; an ACK lowers the count of streams waiting for one.
- A Window Update with the bytes taken, once they reach 64 KiB.
- Data frames from the queue, within the send window and the room.
- FIN after the queue: a Window Update with FIN.
- A stream that sent FIN and got the FIN of the peer is dead.
- Stops at a frame that does not fit.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_yamux_emit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the address after the frames, not a status.
- Argument order: `conn`, `stream`, `dst`, `room`.

## Function `libp2p_mplex_emit`

Writes the mplex messages a stream has to send.

### Signature

```
libp2p_mplex_emit(conn, stream, dst, room) -> dst after the messages
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `dst` | output | `room` bytes |
| `room` | input | u64 |

### Function does

- Reset: ResetInitiator or ResetReceiver; the stream is then dead.
- NewStream, named by the decimal ID.
- MessageInitiator or MessageReceiver messages from the queue.
- CloseInitiator or CloseReceiver after the queue.
- Initiator when this side opened the stream, else Receiver.
- A stream that closed both ways is dead.
- Stops at a message that does not fit.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mplex_emit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the address after the messages, not a status.
- Argument order: `conn`, `stream`, `dst`, `room`.

## Function `libp2p_mux_gather`

Writes the muxer frames a connection has to send.

### Signature

```
libp2p_mux_gather(conn, dst, room) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `dst` | output | `room` bytes |
| `room` | input | u64 |

### Function does

- First the frames of the connection: yamux pongs, then resets of streams without a slot.
- Then the frames of each stream in turn, from the stream after the last one served.
- Frees dead streams.
- Stops when fewer than 32 bytes are left, and keeps its place for the next time.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_mux_gather`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the bytes written, not a status.
- Argument order: `conn`, `dst`, `room`.

## Function `libp2p_drain`

Turns what connections have to send into SEND actions.

### Signature

```
libp2p_drain()
```

### Function does

- Gives the CLOSE that a full action list held back.
- For each live connection, writes SEND actions with `libp2p_drain_conn` while it sends.
- Asks for a wakeup now when the action list fills.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_drain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).

## Function `libp2p_drain_conn`

Writes one SEND action for a connection.

### Signature

```
libp2p_drain_conn(conn) -> 0, 1 or 2
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |

### Function does

- Sends at most the send window left (`send_window` less the bytes with the shell), 256 KiB, and the room of the action list.
- Bytes before the transport keys go first as they are.
- Then Noise transport messages: bytes before the muxer, then muxer frames, each message at most `LIBP2P_NOISE_PLAIN` bytes.
- Gives 1 when it wrote one SEND, 0 when there is nothing to send or less than 4096 bytes of window, and 2 when the action list has less than 4096 bytes of room.

### Function never

- Makes an OS call.

### Effects

- The bytes count as with the shell until SENT events count them out.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_drain_conn`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 0, 1 or 2, not a status.
- Argument order: `conn`.

## Function `libp2p_out_drop`

Drops the first n bytes of the output buffer of a connection.

### Signature

```
libp2p_out_drop(conn, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `n` | input | u64: at most the bytes in the buffer |

### Function does

- Moves the rest of the bytes to the front.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_out_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `conn`, `n`.

## Function `libp2p_conn_pending`

Tells whether an open connection has muxer frames to send.

### Signature

```
libp2p_conn_pending(conn) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | input | [`Connection`](connections.md#type-connection) slot |

### Function does

- Gives 1 for pongs or resets to send, or a stream with SYN, ACK, RST or a FIN to send, a dead stream, a window update due, or queued bytes it may send now; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_conn_pending`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `conn`.

## Type `Chunk`

A heap block of bytes queued on a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `next` | u64 | Heap offset of the next chunk, or NONE |
| 24 | `len` | u64 | Bytes of data |
| 32 | `done` | u64 | Bytes already framed and sent |
| 40 | `data` | `len` bytes | The bytes |

### Rules

- The offsets are from the block start; a chunk is referred to by the state offset of its usable bytes.
- A chunk is freed when all its bytes are framed.


## Type `SendAction`

Bytes the shell writes to the socket of a connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `conn` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 24 | `count` | u64 | Bytes |
| 32 | `data` | `count` bytes | The bytes |

### Rules

- Kind `LIBP2P_ACTION_SEND`; the size covers the bytes.
- The shell writes the bytes of a connection in the order of its SEND actions.
- The shell answers with SENT events as bytes go out.
- A connection never has more than `send_window` bytes with the shell.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): yamux, mplex, fallback, mplex_first, streams_yamux, streams_mplex.
- The shell loop test ([tests/shell/loop.c](../../tests/shell/loop.c)): 256 KiB both ways, past the first yamux window.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): yamux with 16 implementations, mplex with 12.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_mux_feed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_end_frame`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_rst`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_error`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_yamux_feed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_yamux_frame`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_yamux_stream`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mplex_feed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mplex_frame`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_yamux_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mplex_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_chunk_take`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_yamux_emit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mplex_emit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_mux_gather`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_drain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_drain_conn`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_out_drop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_conn_pending`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

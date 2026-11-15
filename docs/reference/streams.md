# Streams

## Contents

### Functions

- [`libp2p_stream_index`](#function-libp2p_stream_index): gives the index of a stream slot.
- [`libp2p_stream_at`](#function-libp2p_stream_at): gives the stream slot of an index.
- [`libp2p_stream_conn`](#function-libp2p_stream_conn): gives the connection of a stream.
- [`libp2p_stream_handle`](#function-libp2p_stream_handle): gives the handle of a stream.
- [`libp2p_stream_new`](#function-libp2p_stream_new): takes a stream slot.
- [`libp2p_stream_free`](#function-libp2p_stream_free): frees a stream slot.
- [`libp2p_stream_kill`](#function-libp2p_stream_kill): ends a stream at once.
- [`libp2p_stream_failed`](#function-libp2p_stream_failed): gives STREAM_FAILED.
- [`libp2p_stream_queue`](#function-libp2p_stream_queue): queues bytes on a stream.
- [`libp2p_stream_ms_out`](#function-libp2p_stream_ms_out): queues a multistream message on a stream.
- [`libp2p_stream_ms_proto`](#function-libp2p_stream_ms_proto): queues the message of a protocol ID on a stream.
- [`libp2p_stream_open`](#function-libp2p_stream_open): opens an outbound stream.
- [`libp2p_gs_proposal`](#function-libp2p_gs_proposal): gives the gossipsub proposal of a stream.
- [`libp2p_stream_propose`](#function-libp2p_stream_propose): queues the current proposal of a stream.
- [`libp2p_stream_is_proposal`](#function-libp2p_stream_is_proposal): tells whether the answer is the proposal.
- [`libp2p_stream_find_proto`](#function-libp2p_stream_find_proto): finds the application protocol a message names.
- [`libp2p_stream_data`](#function-libp2p_stream_data): handles bytes of a stream.
- [`libp2p_stream_abort`](#function-libp2p_stream_abort): resets a stream from this side.
- [`libp2p_stream_reset`](#function-libp2p_stream_reset): marks a stream for reset.
- [`libp2p_stream_ms`](#function-libp2p_stream_ms): handles one multistream message of a stream.
- [`libp2p_stream_remote_fin`](#function-libp2p_stream_remote_fin): handles the end of the peer side.
- [`libp2p_on_open_stream`](#function-libp2p_on_open_stream): handles OPEN_STREAM.
- [`libp2p_app_stream`](#function-libp2p_app_stream): finds the application stream of a handle.
- [`libp2p_on_stream_write`](#function-libp2p_on_stream_write): handles STREAM_WRITE.
- [`libp2p_on_stream_close`](#function-libp2p_on_stream_close): handles STREAM_CLOSE.
- [`libp2p_on_stream_reset`](#function-libp2p_on_stream_reset): handles STREAM_RESET.
- [`libp2p_stream_append`](#function-libp2p_stream_append): queues a prepared chunk on a stream.

### Types

- [`Stream`](#type-stream): the slot of one stream.
- [`OpenStreamEvent`](#type-openstreamevent): a request to open a stream.
- [`StreamWriteEvent`](#type-streamwriteevent): bytes for a stream.
- [`StreamCloseEvent`](#type-streamcloseevent): closes its side of a stream.
- [`StreamResetEvent`](#type-streamresetevent): resets a stream.
- [`StreamInboundAction`](#type-streaminboundaction): a stream the peer opened.
- [`StreamOpenedAction`](#type-streamopenedaction): a stream we opened is ready.
- [`StreamFailedAction`](#type-streamfailedaction): a stream we asked for did not open.
- [`StreamDataAction`](#type-streamdataaction): bytes from a stream.
- [`StreamEofAction`](#type-streameofaction): the peer closed its side of a stream.
- [`StreamResetAction`](#type-streamresetaction): a stream ended abnormally.

### Constants

- `LIBP2P_CONN_STREAMS`: streams of one connection.
- `LIBP2P_MAX_PROPOSALS`: protocols one OPEN_STREAM may propose.
- `LIBP2P_MAX_PROTOCOL`: bytes of a protocol ID, without the newline.

## Spec

- Document: [connections/README.md](https://github.com/libp2p/specs/blob/c750236de43cd8b246a824b377dfdb26bae686db/connections/README.md), libp2p/specs at commit c750236.
- Section: Opening New Streams Over a Connection, Protocol Negotiation; streams for the request/response protocols of the consensus client ([p2p-interface.md](https://github.com/ethereum/consensus-specs/blob/313cbfe561517a81eb11607fea7c6985e562eaa9/specs/phase0/p2p-interface.md), consensus-specs at commit 313cbfe), which the application runs on the stream events.

## Function `libp2p_stream_index`

Gives the slot index of a stream.

### Signature

```
libp2p_stream_index(stream) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives the index of the slot in the stream table.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_index`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the index, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_at`

Gives the stream slot of an index.

### Signature

```
libp2p_stream_at(index) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64: a stream slot index |

### Function does

- Gives the address of the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot, not a status.
- Argument order: `index`.

## Function `libp2p_stream_conn`

Gives the connection slot of a stream.

### Signature

```
libp2p_stream_conn(stream) -> connection
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives the slot of the connection the stream runs on.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_conn`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_handle`

Gives the handle of a stream slot.

### Signature

```
libp2p_stream_handle(stream) -> handle
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives the index and generation of the slot as a [`Handle`](node.md#type-handle).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the handle, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_new`

Takes a stream slot on a connection.

### Signature

```
libp2p_stream_new(conn, id, local) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `id` | input | u64: the muxer stream ID |
| `local` | input | u64: 1 when this side opens it |

### Function does

- Takes a free slot in the negotiating state, with full yamux windows both ways, and links it first on the connection.
- Gives 0 when the connection has `LIBP2P_CONN_STREAMS` streams or no slot is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_new`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `conn`, `id`, `local`.

## Function `libp2p_stream_free`

Frees a stream slot and what it owns.

### Signature

```
libp2p_stream_free(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Unlinks the stream from its connection, and from the drain cursor and the current muxer frame.
- Frees its queue, its RPC buffer and its proposals.
- Takes a gossipsub stream off its peer: for our stream, the peer is no longer ready for gossip.
- Marks the slot free.

### Function never

- Makes an OS call.

### Effects

- Handles of the stream stop working.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_stream_kill`

Ends a stream at once, when its connection ends or the peer resets it.

### Signature

```
libp2p_stream_kill(stream, reason)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `reason` | input | u64: `LIBP2P_REASON_<NAME>` |

### Function does

- An application stream the application knows gives STREAM_RESET, unless it was closed both ways: then nothing was lost.
- An application stream this side opened that is still negotiating gives STREAM_FAILED with the reason.
- Then frees the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_kill`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `reason`.

## Function `libp2p_stream_failed`

Gives STREAM_FAILED for an outbound application stream.

### Signature

```
libp2p_stream_failed(stream, reason)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |
| `reason` | input | u64: `LIBP2P_REASON_<NAME>` |

### Function does

- Gives STREAM_FAILED with the tag of the stream and the reason.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_failed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `reason`.

## Function `libp2p_stream_queue`

Queues bytes on a stream as one heap chunk.

### Signature

```
libp2p_stream_queue(stream, src, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- Copies the bytes into a new [`Chunk`](muxers.md#type-chunk) at the end of the queue, and counts them.
- Gives 1, also for 0 bytes; gives 0 when the heap has no block for them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_queue`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `stream`, `src`, `n`.

## Function `libp2p_stream_ms_out`

Queues one multistream message on a stream.

### Signature

```
libp2p_stream_ms_out(stream, str, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `str` | input | n bytes, the newline last |
| `n` | input | u64: at most 158 |

### Function does

- Queues the varint `n`, then the bytes.
- Gives 1 when it is queued, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 256 bytes on ARM64, 272 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_ms_out`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `stream`, `str`, `n`.

## Function `libp2p_stream_ms_proto`

Queues the multistream message of a protocol ID.

### Signature

```
libp2p_stream_ms_proto(stream, bytes, n) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `bytes` | input | n bytes, no newline |
| `n` | input | u64: at most `LIBP2P_MAX_PROTOCOL` |

### Function does

- Queues the varint n + 1, the bytes and a newline.
- Gives 1 when it is queued, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 256 bytes on ARM64, 272 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_ms_proto`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `stream`, `bytes`, `n`.

## Function `libp2p_stream_open`

Opens an outbound stream that proposes protocols.

### Signature

```
libp2p_stream_open(conn, target, tag, proposals, count) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `conn` | state | [`Connection`](connections.md#type-connection) slot |
| `target` | input | u64: the stream kind once negotiated: application or gossipsub |
| `tag` | input | u64: the tag of OPEN_STREAM |
| `proposals` | input | u64: heap offset of `count` [`ProtocolEntry`](node.md#type-protocolentry) values, or 0 for gossipsub |
| `count` | input | u64: 1 to `LIBP2P_MAX_PROPOSALS` |

### Function does

- Takes the next stream ID of this side: yamux steps by 2, mplex by 1. On QUIC the ID is 0 until the asm-quic STREAM_OPENED action gives the asm-quic stream handle.
- Marks the stream to send SYN (yamux), NewStream (mplex) or the asm-quic OPEN_STREAM (QUIC), and queues the multistream header and the first proposal, from `libp2p_gs_proposal` for gossipsub.
- Gives 0 when it cannot: no slot, or no heap for the bytes; the stream and the proposals are then freed.

### Function never

- Makes an OS call.

### Effects

- The stream owns the proposals block.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_open`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `conn`, `target`, `tag`, `proposals`, `count`.

## Function `libp2p_gs_proposal`

Gives the gossipsub protocol an outbound stream proposes now.

### Signature

```
libp2p_gs_proposal(stream) -> message
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives the proposals in this order: "/meshsub/1.3.0" when `gossipsub_v13` is on, "/meshsub/1.2.0" when `gossipsub_v12` is on, then "/meshsub/1.1.0".
- Each message is 15 bytes, the newline included.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_gs_proposal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the address of the message, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_propose`

Queues the current proposal of an outbound stream.

### Signature

```
libp2p_stream_propose(stream) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Queues the proposal at the proposal index, or the one of `libp2p_gs_proposal` for gossipsub.
- Gives 1 when it is queued, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_propose`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_is_proposal`

Tells whether the message of a stream echoes its current proposal.

### Signature

```
libp2p_stream_is_proposal(stream) -> 1 or 0
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives 1 when the message held is the proposal and a newline, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_is_proposal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns 1 or 0, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_find_proto`

Finds the protocol of the config that a message names.

### Signature

```
libp2p_stream_find_proto(stream) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | [`Stream`](streams.md#type-stream) slot |

### Function does

- Gives the index in the protocol list of the config of the protocol the message names, without its newline, or `NONE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_find_proto`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the index or NONE, not a status.
- Argument order: `stream`.

## Function `libp2p_stream_data`

Handles bytes of a stream from the muxer.

### Signature

```
libp2p_stream_data(stream, p, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `p` | input | n bytes |
| `n` | input | u64 |

### Function does

- Drops the bytes of a stream that is free, reset or dead.
- Negotiating: multistream messages, with `libp2p_stream_ms`; bytes that are not multistream reset the stream with PROTOCOL.
- Application: one STREAM_DATA with the bytes.
- Gossipsub, the peer's stream: RPCs, with `libp2p_gossip_rx`.
- Other kinds: the bytes are dropped.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_data`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `p`, `n`.

## Function `libp2p_stream_abort`

Resets a stream from this side and tells the application.

### Signature

```
libp2p_stream_abort(stream, reason)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `reason` | input | u64: `LIBP2P_REASON_<NAME>` |

### Function does

- An application stream the application knows gives STREAM_RESET.
- An application stream this side opened that is still negotiating gives STREAM_FAILED with the reason.
- Then resets it with `libp2p_stream_reset`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_abort`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `reason`.

## Function `libp2p_stream_reset`

Drops the queue of a stream and marks it to send a reset.

### Signature

```
libp2p_stream_reset(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Frees the queued chunks, sets the reset flag, and clears the flag that the application knows the stream.

### Function never

- Makes an OS call.

### Effects

- The next drain sends RST (yamux) or Reset (mplex) and frees the slot.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_reset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_stream_ms`

Handles one multistream message of a stream.

### Signature

```
libp2p_stream_ms(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Takes the header first; a stream the peer opened answers it with ours.
- Our stream: the echo of the proposal selects it: STREAM_OPENED for an application stream, or gossipsub starts; "na" moves to the next proposal, and after the last the stream is reset with PROTOCOL.
- A stream the peer opened: "/meshsub/1.1.0", "/meshsub/1.2.0" when `gossipsub_v12` is on, or "/meshsub/1.3.0" when `gossipsub_v13` is on, is selected for gossipsub; "/ipfs/id/1.0.0" gets the Identify message; a protocol of the config is echoed and gives STREAM_INBOUND; anything else gets "na".
- Resets the stream with PROTOCOL when the header is wrong or the answer is neither the proposal nor "na".

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_ms`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_stream_remote_fin`

Handles the end of the peer side of a stream.

### Signature

```
libp2p_stream_remote_fin(stream)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |

### Function does

- Marks the peer side closed once.
- An application stream the application knows gives STREAM_EOF.
- The peer's gossipsub stream, or a stream still negotiating, closes our side too.
- A stream whose FIN already went out is closed both ways: it is dead, and the next drain frees it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_remote_fin`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`.

## Function `libp2p_on_open_stream`

Opens an application stream to a connected peer.

### Signature

```
libp2p_on_open_stream(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`OpenStreamEvent`](#type-openstreamevent) |

### Function does

- Copies the proposals into a heap block and opens the stream on the first connection of the peer with `libp2p_stream_open`.
- Gives STREAM_FAILED with the tag: NO_PEER when the peer is not connected, LIMIT when no slot or heap block is free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_open_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_app_stream`

Finds an application stream that the application knows.

### Signature

```
libp2p_app_stream(handle) -> stream
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the stream of the handle when it is an application stream the application knows, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_app_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V). It returns the slot or 0, not a status.
- Argument order: `handle`.

## Function `libp2p_on_stream_write`

Queues bytes the application writes to a stream.

### Signature

```
libp2p_on_stream_write(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`StreamWriteEvent`](#type-streamwriteevent) |

### Function does

- Queues the bytes with `libp2p_stream_queue`.
- Ignores a stream the application closed or reset.
- Resets the stream with LIMIT when its queue would pass `stream_queue`, or the heap cannot hold the bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_stream_write`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_stream_close`

Closes the application side of a stream.

### Signature

```
libp2p_on_stream_close(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`StreamCloseEvent`](#type-streamcloseevent) |

### Function does

- Marks the stream to send FIN (yamux) or Close (mplex) after its queue.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_stream_close`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_on_stream_reset`

Resets a stream for the application.

### Signature

```
libp2p_on_stream_reset(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | [`StreamResetEvent`](#type-streamresetevent) |

### Function does

- Resets the stream with `libp2p_stream_reset`; no STREAM_RESET action follows.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_on_stream_reset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `event`.

## Function `libp2p_stream_append`

Puts a filled send chunk at the end of the queue of a stream.

### Signature

```
libp2p_stream_append(stream, chunk)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | state | [`Stream`](streams.md#type-stream) slot |
| `chunk` | input | u64: heap offset of a [`Chunk`](muxers.md#type-chunk) with its length set |

### Function does

- Links the chunk last and counts its bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `libp2p_stream_append`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6), with the state in x27, r15 or s9 and, inside `libp2p_step`, the scratch in x28, r14 or s10 (ARM64, x86-64, RISC-V).
- Argument order: `stream`, `chunk`.

## Type `Stream`

One stream of yamux, mplex or QUIC: its ID, negotiation, windows and queue.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gen` | u32 | Generation of the slot |
| 4 | `used` | u32 | 1 while the slot is in use |
| 8 | `conn` | u64 | Index of its connection |
| 16 | `id` | u64 | The muxer stream ID; on QUIC, the asm-quic stream handle, or 0 before STREAM_OPENED |
| 24 | `flags` | u64 | SF_ flags of include/state.inc |
| 32 | `kind` | u64 | SK_NEGOTIATING, SK_GOSSIP_IN, SK_GOSSIP_OUT, SK_APP or SK_IDENTIFY |
| 40 | `proto` | u64 | App protocol index, or the proposal accepted |
| 48 | `tag` | u64 | The tag of OPEN_STREAM |
| 56 | `peer` | u64 | Index of the peer of its connection |
| 64 | `send_win` | u64 | Yamux send window |
| 72 | `recv_win` | u64 | Yamux receive window |
| 80 | `recv_pend` | u64 | Bytes taken, not yet granted back |
| 88 | `q_head` | u64 | Heap offset of the first queued chunk, or NONE |
| 96 | `q_tail` | u64 | Heap offset of the last queued chunk, or NONE |
| 104 | `q_bytes` | u64 | Bytes queued, not yet sent |
| 112 | `next` | u64 | Index of the next stream of the connection, or NONE |
| 120 | `prev` | u64 | Index of the previous stream, or NONE |
| 128 | `ms_state` | u64 | Negotiation record: state |
| 136 | `ms_len` | u64 | Bytes of the multistream message held |
| 144 | `ms_need` | u64 | Bytes of its varint length |
| 152 | `ms_buf` | 136 bytes | The multistream message being read |
| 288 | `proposals` | u64 | Heap offset of the proposals (outbound app streams) |
| 296 | `prop_count` | u64 | Proposals |
| 304 | `prop_index` | u64 | The proposal now on offer |
| 312 | `rpc_buf` | u64 | Gossipsub RPC being read: heap offset |
| 320 | `rpc_len` | u64 | Its length |
| 328 | `rpc_got` | u64 | Bytes of the RPC read so far |
| 336 | `rpc_varint` | u64 | The length prefix being read |
| 344 | `rpc_shift` | u64 | Bits of the length prefix read |
| 352 | `target` | u64 | The kind it becomes once negotiated |
| 360 | `qflight` | u64 | QUIC: bytes written to asm-quic and not yet acknowledged, at most `quic_window` |

### Rules

- A stream lives on one connection, and is freed when it is dead after the drain, or when the connection ends.


## Type `OpenStreamEvent`

The application opens a stream to a peer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 24 | `tag` | u64 | Any value: STREAM_OPENED or STREAM_FAILED carries it back |
| 32 | `count` | u64 | Proposals, 1 to `LIBP2P_MAX_PROPOSALS` |
| 40 | `protocols` | `count` [`ProtocolEntry`](node.md#type-protocolentry) | The protocols, in order of preference |

### Rules

- Kind `LIBP2P_EVENT_OPEN_STREAM`; the size covers the proposals.
- It ends in STREAM_OPENED or STREAM_FAILED, with the tag.


## Type `StreamWriteEvent`

The application writes bytes to a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |
| 24 | `count` | u64 | Bytes |
| 32 | `data` | `count` bytes | The bytes |

### Rules

- Kind `LIBP2P_EVENT_STREAM_WRITE`; the size covers the bytes.
- Bytes go out in order, after the bytes written before.


## Type `StreamCloseEvent`

The application closes its side of a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |

### Rules

- Kind `LIBP2P_EVENT_STREAM_CLOSE`, size at least `LIBP2P_EV_STREAM_SIZE`.
- Bytes queued before it still go out; then FIN or Close.
- A stale handle does nothing.


## Type `StreamResetEvent`

The application resets a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |

### Rules

- Kind `LIBP2P_EVENT_STREAM_RESET`, size at least `LIBP2P_EV_STREAM_SIZE`.
- Queued bytes are dropped; no action follows.
- A stale handle does nothing.


## Type `StreamInboundAction`

The peer opened a stream for a protocol of the config.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |
| 24 | `peer` | u64: a handle ([`Handle`](node.md#type-handle)) | The peer |
| 32 | `protocol` | u64 | Index in the protocol list of the config |

### Rules

- Kind `LIBP2P_ACTION_STREAM_INBOUND`, size `LIBP2P_ACT_SI_SIZE`.
- STREAM_DATA of the stream comes after it.


## Type `StreamOpenedAction`

A stream of OPEN_STREAM is ready.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |
| 24 | `tag` | u64 | The tag of OPEN_STREAM |
| 32 | `index` | u64 | The proposal the peer took |

### Rules

- Kind `LIBP2P_ACTION_STREAM_OPENED`, size `LIBP2P_ACT_SO_SIZE`.
- Once for each stream.


## Type `StreamFailedAction`

A stream of OPEN_STREAM did not open.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `tag` | u64 | The tag of OPEN_STREAM |
| 24 | `reason` | u64 | `LIBP2P_REASON_<NAME>` |

### Rules

- Kind `LIBP2P_ACTION_STREAM_FAILED`, size `LIBP2P_ACT_FAILED_SIZE`.
- Once for each stream that does not open.


## Type `StreamDataAction`

Bytes the peer sent on a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |
| 24 | `count` | u64 | Bytes |
| 32 | `data` | `count` bytes | The bytes |

### Rules

- Kind `LIBP2P_ACTION_STREAM_DATA`; the size covers the bytes.
- Bytes come in order.


## Type `StreamEofAction`

The peer closed its side of a stream.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |

### Rules

- Kind `LIBP2P_ACTION_STREAM_EOF`, size `LIBP2P_ACT_STREAM_SIZE`.
- No STREAM_DATA of the stream follows.


## Type `StreamResetAction`

A stream ended abnormally.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 16 | `stream` | u64: a handle ([`Handle`](node.md#type-handle)) | The stream |

### Rules

- Kind `LIBP2P_ACTION_STREAM_RESET`, size `LIBP2P_ACT_STREAM_SIZE`.
- The peer reset it, this side reset it, or its connection ended while it was open one way: bytes may be lost. The handle stops working.


## Test vectors

- Scenarios of [tests/runner/runner.c](../../tests/runner/runner.c): yamux, mplex, fallback, mplex_first, streams_yamux, streams_mplex, errors, limits.
- The shell loop test ([tests/shell/loop.c](../../tests/shell/loop.c)): an echo of 256 KiB over yamux and mplex.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)): ping streams with 16 implementations.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_stream_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_at`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_conn`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_new`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_free`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_kill`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_failed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_queue`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_ms_out`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_ms_proto`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_open`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_gs_proposal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_propose`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_is_proposal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_find_proto`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_abort`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_ms`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_remote_fin`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_open_stream`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_app_stream`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_stream_write`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_stream_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_on_stream_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_stream_append`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
